/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.security;
/// BAS Hub 的安全装配：CAS 会话/票据 + ems 远程授权域 + Project 选择。
///
/// 路由层只拿到 `guard` 回调：是否放行、401 文档怎么写、是否 302 到 CAS，
/// 全部在这一层收口。`configs` 不调用 guard，保持登录前可读。

import bashub.config : HubConfig;
import bashub.api : hubApiPrefixes, isApiGroup;

import beangle.ems.authority : RemoteAuthoritySource;
import beangle.security.authz : AuthorityDomain, Scope, permissionAllows;
import beangle.security.cas : CasConfig;
import beangle.security.session : Session, SessionRepo;
import beangle.security.web : AccessDecision, HttpSecurity, SecurityContext, loginUrlFor, wantsJson;

import std.string : indexOf, startsWith, toLower;

import vibe.core.log : logInfo, logWarn;
import vibe.http.common : HTTPStatus, httpMethodString;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;

import beangle.jsonapi.document : errorDocument, unauthorizedDocument;
import beangle.jsonapi.router : writeJsonApi;

class HubSecurity {
  private HubConfig cfg;
  private SessionRepo sessions;
  private HttpSecurity http;
  private AuthorityDomain injectedDomain;
  private RemoteAuthoritySource source;
  private CasConfig casConfig;

  this(HubConfig cfg, SessionRepo sessions, AuthorityDomain domain = null,
      RemoteAuthoritySource source = null) {
    this.cfg = cfg;
    this.sessions = sessions;
    this.injectedDomain = domain;
    this.source = source;
    this.casConfig = cfg.casServer.length > 0 ? CasConfig.of(cfg.casServer) : CasConfig.init;
    this.http = new HttpSecurity(sessions, this.casConfig);
    if (this.source is null && cfg.authorityUrl.length > 0) {
      this.source = new RemoteAuthoritySource(cfg.authorityUrl);
      this.source.refreshSeconds = cast(int) cfg.authorityRefreshSeconds;
    }
  }

  /// `RouteOptions.guard`：未开启登录时保持原预演行为。
  bool guard(HTTPServerRequest req, HTTPServerResponse res) {
    if (!cfg.authRequired)
      return true;

    auto context = http.authenticate(req, cfg.sessionIdName);
    auto resource = resourceNameOf(req.requestPath.toString);
    auto action = httpMethodString(req.method).toLower;
    AccessDecision decision;
    // 监控节点拆分读写：登录用户可查看在线状态、历史与日志；能向 agent 下发动作的
    // 非 GET 请求仍必须显式具备控制权限。
    if (resource == "/monitor/agents") {
      if (context.session is null)
        decision = AccessDecision.unauthenticated;
      else if ((action == "get" || action == "head") || canControlAgents(context, action))
        decision = AccessDecision.allow;
      else
        decision = AccessDecision.forbidden;
    } else {
      decision = http.authorize(context, resource, action, domain());
    }

    final switch (decision) {
    case AccessDecision.allow:
      return true;
    case AccessDecision.unauthenticated:
      writeUnauthenticated(req, res);
      return false;
    case AccessDecision.forbidden:
      writeJsonApi(res, errorDocument(403, "无权访问", "当前账户没有访问 " ~ resource ~ " 的权限"),
          HTTPStatus.forbidden);
      return false;
    }
  }

  /** agent 控制权限：EMS `/monitor/agents` 私有资源的角色命中，或显式权限串。
   *
   * EMS 普通会话的 `authorities` 是角色 ID，且 JSON 会话没有 `isRoot`。因此不能靠
   * `ROLE_ADMIN` / `isRoot` 判断，而要让管理员在 EMS 里把 `/monitor/agents` 资源设为
   * Private 并授权给角色。`permissions` 里的 `/monitor/agents:*` 继续兼容其它 CAS 来源；
   * 资源未登记时写操作仍拒绝，避免 unknownIsProtected 把控制接口开放给所有登录用户。
   */
  private bool canControlAgents(SecurityContext context, string action) {
    auto session = context.session;
    if (session is null || session.principal is null)
      return false;
    auto principal = session.principal;
    if (principal.isRoot || permissionAllows(principal.permissions, "/monitor/agents", action))
      return true;

    auto authz = domain();
    if (authz is null)
      return false;
    auto authority = authz.find("/monitor/agents");
    return authority !is null && authority.level == Scope.private_
        && authority.matches(principal.authorities);
  }

  /// 当前请求的安全上下文（`sessions` 端点复用同一套 cookie/ticket 解析）。
  SecurityContext contextOf(HTTPServerRequest req) {
    return http.authenticate(req, cfg.sessionIdName);
  }

  /// 退出：只清本地缓存和本地 cookie，CAS 的会话让它自己按 tti 过期。
  string logout(HTTPServerRequest req, HTTPServerResponse res) {
    if (sessions !is null) {
      auto sid = req.cookies.get(cfg.sessionIdName, "");
      if (sid.length > 0)
        sessions.evict(sid);
    }
    res.setCookie(cfg.sessionIdName, null, "/");
    res.setCookie("beangle.security.projectId", null, "/");
    res.setCookie("beangle.security.runAs", null, "/");
    return casConfig.casServer.length > 0 ? casConfig.logoutUrl : cfg.emsBase ~ "/cas/logout";
  }

  /// 启动时预取一次；失败只记日志，后续请求会按 TTL 再试。
  void warmup() {
    if (source is null)
      return;
    if (source.refresh())
      logInfo("Authority domain loaded from %s (%s resources)", source.url, source.current.size);
    else
      logWarn("Load authority domain from %s failed: %s", source.url, source.lastError);
  }

  /// 当前授权域；远程源失败时保留上一次成功加载的域。
  private AuthorityDomain domain() {
    if (injectedDomain !is null)
      return injectedDomain;
    if (source !is null)
      return source.get();
    return null;
  }

  /// 写未登录响应：前端 API 401（带 CAS 登录地址），浏览器导航 302。
  void writeUnauthenticated(HTTPServerRequest req, HTTPServerResponse res) {
    auto login = loginUrlFor(casConfig, req, cfg.emsBase.length > 0 ? cfg.emsBase ~ "/cas" : "");
    if (wantsJson(req)) {
      writeJsonApi(res, unauthorizedDocument(login), HTTPStatus.unauthorized);
    } else {
      res.redirect(login, HTTPStatus.found);
    }
  }

  /** 授权资源名：不带 API 根的 `{能力域}/{资源}`，与 EMS 应用内权限命名一致。
   *
   * `/api/bashub/ems/apps/...` → `/ems/apps`；
   * `/api/bashub/ems/menus/...` → `/ems/menus`。
   * 与 scala 侧按 action 名登记资源的粒度不同，这里用 URL 资源段；ems 里没有同名资源时
   * 按 unknownIsProtected 只要求登录，因此既可逐步补齐资源定义，也不会误放开写接口。
   */
  private string resourceNameOf(string path) {
    auto prefix = hubApiPrefixes(cfg.apiPrefix).root;
    if (prefix.length == 0 || !path.startsWith(prefix))
      return path;
    auto rest = path[prefix.length .. $];
    while (rest.length > 0 && rest[0] == '/')
      rest = rest[1 .. $];
    auto slash = rest.indexOf('/');
    auto first = slash < 0 ? rest : rest[0 .. slash];
    if (first.length == 0)
      return "/";
    if (!isApiGroup(first))
      return "/" ~ first;
    auto tail = slash < 0 ? "" : rest[slash + 1 .. $];
    auto nextSlash = tail.indexOf('/');
    auto second = nextSlash < 0 ? tail : tail[0 .. nextSlash];
    return second.length == 0 ? "/" ~ first : "/" ~ first ~ "/" ~ second;
  }
}
