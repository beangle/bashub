/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.security.web;
/// Web 安全上下文：从 cookie 会话 / CAS ticket 认证，解析当前 Profile，再做资源授权。
///
/// 这不是 servlet 过滤器链的复刻：没有线程局部 `SecurityContext`，认证结果由调用方显式拿走。
/// 因而同一进程里的测试、后台任务都不会意外继承上一个请求的身份。

import beangle.security.authz : AuthorityDomain, Scope, accountUsable;
import beangle.security.cas : CasConfig;
import beangle.security.casvalidate : CasTicketValidator, CasValidation;
import beangle.security.session : Agent, DefaultAccount, Profile, Session, SessionRepo, nowSeconds;

import std.algorithm : canFind, sort;
import std.array : join;
import std.conv : to;
import std.string : endsWith, indexOf, split, strip, toLower;
import std.uri : encodeComponent;

import vibe.http.server : HTTPServerRequest;

/// 一次请求的安全上下文。`profile` 是 ems 账户上选中的环境 Profile，不是 BAS 的部署 Profile。
struct SecurityContext {
  Session session;
  Profile profile;

  bool authenticated() const {
    return session !is null;
  }
}

/// 授权结论：允许、未登录、已登录但无权限。
enum AccessDecision {
  allow,
  unauthenticated,
  forbidden,
}

/// 取一个 HTTP URL（测试注入假 CAS 时替换）。
alias SecurityHttpGet = CasValidation delegate(string ticket, string service);

private bool defaultJsonRequest(HTTPServerRequest req) {
  auto accept = req.headers.get("Accept", "").toLower;
  if (accept.canFind("json"))
    return true;
  auto path = req.requestPath.toString.toLower;
  if (path.endsWith(".json") || path.endsWith(".jsonapi"))
    return true;
  if (req.query.get("format", "").toLower == "json")
    return true;
  return req.headers.get("X-Requested-With", "").toLower == "xmlhttprequest";
}

/// 浏览器/前端是否期待 JSON 错误（决定 401 还是 302）。
bool wantsJson(HTTPServerRequest req) {
  return defaultJsonRequest(req);
}

/// `X-Forwarded-*` 优先，保证反代后的 CAS service 与浏览器地址一致。
string requestScheme(HTTPServerRequest req) @safe {
  auto forwarded = req.headers.get("X-Forwarded-Proto", "").strip.toLower;
  if (forwarded.length > 0)
    return forwarded;
  return req.tls ? "https" : "http";
}

string requestHost(HTTPServerRequest req) @safe {
  auto host = req.headers.get("X-Forwarded-Host", "").strip;
  if (host.length == 0)
    host = req.host;
  if (host.length == 0)
    host = "localhost";

  auto forwardedPort = req.headers.get("X-Forwarded-Port", "").strip;
  if (forwardedPort.length > 0 && host.indexOf(':') < 0) {
    auto scheme = requestScheme(req);
    auto defaultPort = (scheme == "https" && forwardedPort == "443")
        || (scheme == "http" && forwardedPort == "80");
    if (!defaultPort)
      host ~= ":" ~ forwardedPort;
  }
  return host;
}

string requestOrigin(HTTPServerRequest req) @safe {
  return requestScheme(req) ~ "://" ~ requestHost(req);
}

/** CAS 的 service：本站 URL，去掉 ticket/renew/sid_name，其余 query 排序。
 *
 * 排序不是洁癖：CAS 登录时注册的 service 与回跳校验时提交的 service 必须逐字一致，
 * 浏览器/反代对 query 顺序没有保证，所以两边都按 scala `CasEntryPoint.serviceUrl` 的规则整理。
 */
string serviceUrl(HTTPServerRequest req) {
  auto url = requestOrigin(req) ~ req.requestPath.toString;
  auto query = req.queryString.strip;
  if (query.length == 0)
    return url;

  string[] kept;
  foreach (part; query.split("&")) {
    auto eq = part.indexOf('=');
    if (eq <= 0)
      continue;
    auto key = part[0 .. eq];
    if (key == "ticket" || key == "renew" || key == "sid_name")
      continue;
    kept ~= part;
  }
  if (kept.length == 0)
    return url;
  kept.sort;
  return url ~ "?" ~ kept.join("&");
}

/// `{cas}/login?service=<encoded>`（scala `CasEntryPoint.casLoginUrl`）。
string casLoginUrl(CasConfig cfg, string service) {
  auto login = cfg.loginUrl;
  auto offset = login.indexOf('?');
  auto joinWith = offset >= 0 ? "&" : "?";
  return login ~ joinWith ~ "service=" ~ encodeComponent(service);
}

/// 当前请求的 CAS 登录地址；没配 CAS 时退回 ems 的 cas 前缀。
string loginUrlFor(CasConfig cfg, HTTPServerRequest req, string fallbackCasBase) {
  auto service = serviceUrl(req);
  if (cfg.casServer.length > 0)
    return casLoginUrl(cfg, service);
  return fallbackCasBase.length > 0 ? fallbackCasBase : service;
}

/// SPA 的登录凭证：优先 cookie，其次 `Authorization: Bearer <sid>`，最后 `URP_SID` 查询参数。
///
/// ems-app 在 CAS 登录后保存 token，并用 Bearer 访问同源 API；跨域或 development proxy 场景
/// 还会把它追加为 `URP_SID`。不认这两种形态时，浏览器明明已经登录，后端仍会回 401。
private string sessionIdFromRequest(HTTPServerRequest req, string sessionIdName) {
  auto sid = req.cookies.get(sessionIdName, "").strip;
  if (sid.length > 0)
    return sid;

  auto authorization = req.headers.get("Authorization", "").strip;
  if (authorization.length > 7 && authorization[0 .. 7].toLower == "bearer ") {
    sid = authorization[7 .. $].strip;
    if (sid.length > 0)
      return sid;
  }

  return req.query.get("URP_SID", "").strip;
}

/// 从请求参数或 cookie 取当前 Profile，并且只接受会话里确实存在的 id。
Profile selectedProfile(Session session, HTTPServerRequest req) {
  if (session is null || session.principal is null)
    return null;

  auto profileId = req.query.get("contextProfileId", "").strip;
  if (profileId.length == 0)
    profileId = req.cookies.get("beangle.security.profileId", "").strip;
  if (profileId.length == 0)
    return null;

  foreach (profile; session.principal.profiles) {
    if (profile.id.to!string == profileId)
      return profile;
  }
  return null;
}

/** 会话 + 票据认证。
 *
 * cookie 会话优先；没有可用 cookie 时才看 `ticket`。ticket 认证产生的身份只活在这次请求里——
 * 持久会话仍由 CAS 域的 `EMS_SID` 承载，D 侧不抢写这个共享 cookie。
 */
class HttpSecurity {
  private SessionRepo sessions;
  private CasConfig casConfig;
  private CasTicketValidator validator;

  this(SessionRepo sessions, CasConfig casConfig = CasConfig.init) {
    this.sessions = sessions;
    this.casConfig = casConfig;
    if (casConfig.casServer.length > 0)
      this.validator = new CasTicketValidator(casConfig);
  }

  SecurityContext authenticate(HTTPServerRequest req, string sessionIdName) {
    SecurityContext context;
    auto sid = sessionIdFromRequest(req, sessionIdName);
    if (sessions !is null && sid.length > 0)
      context.session = sessions.access(sid, nowSeconds());

    if (context.session is null) {
      auto ticket = req.query.get("ticket", "").strip;
      if (ticket.length > 0 && validator !is null) {
        auto validation = validator.validate(ticket, serviceUrl(req));
        if (validation.valid)
          context.session = ticketSession(validation);
      }
    }

    if (context.session !is null && !accountUsable(context.session.principal))
      context.session = null;
    context.profile = selectedProfile(context.session, req);
    return context;
  }

  AccessDecision authorize(SecurityContext context, string resource, string action,
      AuthorityDomain domain) {
    if (domain is null)
      return context.session !is null ? AccessDecision.allow : AccessDecision.unauthenticated;

    auto authority = domain.find(resource);
    if (authority is null)
      return context.session !is null ? AccessDecision.allow : AccessDecision.unauthenticated;

    if (authority.level == Scope.public_)
      return AccessDecision.allow;
    if (context.session is null)
      return AccessDecision.unauthenticated;
    if (context.session.principal.isRoot)
      return AccessDecision.allow;
    return domain.permits(resource, action, context.session)
        ? AccessDecision.allow : AccessDecision.forbidden;
  }

  private Session ticketSession(CasValidation validation) {
    auto description = validation.attributes.get("userName", validation.user);
    auto principal = new DefaultAccount(validation.user, description);
    principal.authorities = splitValues(validation.attributes.get("authorities", ""));
    principal.permissions = splitValues(validation.attributes.get("permissions", ""));
    principal.details = validation.attributes;
    auto at = nowSeconds();
    return new Session("cas-ticket:" ~ validation.user, principal, at,
        new Agent("cas", "", ""), 1800);
  }
}

/// CAS 属性里的角色/权限是逗号分隔文本（也兼容空白分隔）。
private string[] splitValues(string text) {
  string[] values;
  size_t start;
  foreach (i, c; text) {
    if (c == ',' || c == ';' || c == ' ' || c == '\t' || c == '\r' || c == '\n') {
      if (i > start)
        values ~= text[start .. i];
      start = i + 1;
    }
  }
  if (start < text.length)
    values ~= text[start .. $];
  return values;
}
