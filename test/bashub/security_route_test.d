/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.security_route_test;
/// M4 验收：未登录、会话过期、无权限、合法用户、CAS ticket、configs 免登录与 CORS。

import bashub.config;
import bashub.demo;
import bashub.resources;
import bashub.route;
import bashub.security : HubSecurity;
import bashub.store;

import beangle.data.dao : Dao;
import beangle.data.resource : Registry;
import beangle.security.authz : Authority, AuthorityDomain, Scope, authorityDomain;
import beangle.security.session;

import test.beangle.security.fake_cas : FakeCas;

import std.algorithm.searching : startsWith;
import std.conv : to;

import vibe.data.json : parseJson;
import vibe.http.common : HTTPMethod;
import vibe.http.server : HTTPServerRequestHandler, createTestHTTPServerRequest, createTestHTTPServerResponse,
  TestHTTPResponseMode;
import vibe.inet.message : InetHeaderMap;
import vibe.inet.url : URL;
import vibe.stream.memory : createMemoryOutputStream;

/// 只读内存仓库；`access` 复刻 `DefaultSession.access` 的过期语义。
private class StaticSessionRepo : SessionRepo {
  private Session[string] byId;

  void put(Session session) {
    byId[session.id] = session;
  }

  Session get(string sessionId, bool refresh = false) {
    if (auto found = sessionId in byId)
      return *found;
    return null;
  }

  Session[] findByPrincipal(string principal) {
    Session[] found;
    foreach (_, session; byId) {
      if (session.principal.name == principal)
        found ~= session;
    }
    return found;
  }

  Session access(string sessionId, long accessAt) {
    auto session = get(sessionId);
    if (session is null)
      return null;
    if (session.expiredAt(accessAt)) {
      evict(sessionId);
      return null;
    }
    session.access(accessAt);
    return session;
  }

  void evict(string sessionId) {
    byId.remove(sessionId);
  }

  void expire(string sessionId) {
    evict(sessionId);
  }
}

private struct Exchange {
  int status;
  string body;
  string allowOrigin;
  string allowCredentials;
  string contentTypeOptions;
  string cacheControl;
}

private Exchange call(HTTPServerRequestHandler router, HTTPMethod method, string url,
    string cookie = null, string[string] extraHeaders = null) {
  InetHeaderMap headers;
  headers["Accept"] = "application/vnd.api+json";
  if (cookie.length > 0)
    headers["Cookie"] = cookie;
  if (extraHeaders !is null) {
    foreach (key, value; extraHeaders)
      headers[key] = value;
  }

  auto req = createTestHTTPServerRequest(URL(url), method, headers);
  auto output = createMemoryOutputStream();
  auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);
  router.handleRequest(req, res);

  Exchange ex;
  ex.status = cast(int) res.statusCode;
  ex.body = cast(string) output.data;
  ex.allowOrigin = res.headers.get("Access-Control-Allow-Origin", "");
  ex.allowCredentials = res.headers.get("Access-Control-Allow-Credentials", "");
  ex.contentTypeOptions = res.headers.get("X-Content-Type-Options", "");
  ex.cacheControl = res.headers.get("Cache-Control", "");
  return ex;
}

private HubConfig authConfig() {
  HubConfig cfg;
  cfg.apiPrefix = "/api/bashub";
  cfg.emsBase = "https://sas.openurp.net";
  cfg.casServer = "https://sas.openurp.net/cas";
  cfg.appName = "bas-hub";
  cfg.authRequired = true;
  return cfg;
}

private AuthorityDomain testDomain() {
  return authorityDomain([
    Authority("/config/profiles", Scope.private_, ["ROLE_ADMIN"]),
    Authority("/config/hosts", Scope.protected_, []),
    Authority("/ems/apps", Scope.private_, ["ROLE_ADMIN"]),
    Authority("/ems/app-groups", Scope.private_, ["ROLE_ADMIN"]),
  ]);
}

private Session sessionOf(string id, string[] authorities, long lastAccessAt = -1) {
  auto account = new DefaultAccount(id, id);
  account.authorities = authorities;
  auto at = lastAccessAt < 0 ? nowSeconds() : lastAccessAt;
  return new Session(id, account, at, new Agent("test", "127.0.0.1", "Linux"), 1800);
}

private HTTPServerRequestHandler securedRouter(HubConfig cfg, SessionRepo repo, AuthorityDomain domain) {
  auto reg = hubRegistry();
  auto dao = demoDao(reg);
  auto security = new HubSecurity(cfg, repo, domain);
  return buildHubRouter(cfg, reg, createHubStore(reg, dao), repo, null, security);
}

@("未登录访问受保护资源：401 带 CAS 登录地址")
unittest {
  auto repo = new StaticSessionRepo();
  auto router = securedRouter(authConfig(), repo, testDomain());
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search");
  assert(ex.status == 401);
  auto redirect = parseJson(ex.body)["errors"][0]["meta"]["redirectUrl"].get!string;
  assert(redirect.startsWith("https://sas.openurp.net/cas/login?service="));
}

@("SPA 查看最终配置也要求登录")
unittest {
  auto repo = new StaticSessionRepo();
  auto router = securedRouter(authConfig(), repo, testDomain());
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/1002/server");
  assert(ex.status == 401);
}

@("会话过期：401，且过期会话被本地清除")
unittest {
  auto repo = new StaticSessionRepo();
  repo.put(sessionOf("expired", ["ROLE_ADMIN"], nowSeconds() - 3600));
  auto router = securedRouter(authConfig(), repo, testDomain());
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search", "EMS_SID=expired");
  assert(ex.status == 401);
  assert(repo.get("expired") is null);
}

@("已登录但角色不命中 Private 资源：403")
unittest {
  auto repo = new StaticSessionRepo();
  repo.put(sessionOf("user", ["ROLE_USER"]));
  auto router = securedRouter(authConfig(), repo, testDomain());
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search", "EMS_SID=user");
  assert(ex.status == 403);
  assert(parseJson(ex.body)["errors"][0]["status"].get!string == "403");
}

@("API 根前缀末尾的斜杠不影响授权资源名")
unittest {
  auto repo = new StaticSessionRepo();
  repo.put(sessionOf("user", ["ROLE_USER"]));
  auto cfg = authConfig();
  cfg.apiPrefix = "/api/bashub/";
  auto router = securedRouter(cfg, repo, testDomain());
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search", "EMS_SID=user");
  assert(ex.status == 403, ex.body);
}

@("合法用户与 superadmin 可访问 Private 资源")
unittest {
  auto repo = new StaticSessionRepo();
  repo.put(sessionOf("admin", ["ROLE_ADMIN"]));
  auto router = securedRouter(authConfig(), repo, testDomain());
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search", "EMS_SID=admin");
  assert(ex.status == 200, ex.body);

  auto rootAccount = new DefaultAccount("root", "root");
  rootAccount.isRoot = true;
  repo.put(new Session("root", rootAccount, nowSeconds(), new Agent(), 1800));
  assert(call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search", "EMS_SID=root").status == 200);
}

@("EMS 权限资源名不带 /api/bashub 前缀")
unittest {
  auto repo = new StaticSessionRepo();
  repo.put(sessionOf("admin", ["ROLE_ADMIN"]));
  auto router = securedRouter(authConfig(), repo, testDomain());

  auto apps = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/apps/search", "EMS_SID=admin");
  assert(apps.status == 200, apps.body);

  auto groups = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/app-groups/search", "EMS_SID=admin");
  assert(groups.status == 200, groups.body);
}

@("agent 监控与控制端点只允许管理员") unittest {
  auto repo = new StaticSessionRepo();
  repo.put(sessionOf("user", ["ROLE_USER"]));
  auto router = securedRouter(authConfig(), repo, testDomain());
  auto denied = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/status", "EMS_SID=user");
  assert(denied.status == 403, denied.body);

  repo.put(sessionOf("admin", ["ROLE_ADMIN"]));
  auto allowed = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/status", "EMS_SID=admin");
  assert(allowed.status == 200, allowed.body);
}

@("CAS ticket 登录会把 authorities 映射进账户并访问 Private 资源")
unittest {
  auto cas = new FakeCas();
  auto port = cas.start();
  scope (exit) cas.stop();

  auto service = "http%3A%2F%2Flocalhost%2Fapi%2Fbashub%2Fconfig%2Fprofiles%2Fsearch";
  cas.on("/serviceValidate?ticket=ST-1&service=" ~ service, 200,
      cast(ubyte[]) (`<cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
  <cas:authenticationSuccess>
    <cas:user>ticket-user</cas:user>
    <cas:attributes><cas:authorities>ROLE_ADMIN</cas:authorities></cas:attributes>
  </cas:authenticationSuccess>
</cas:serviceResponse>`).dup);

  auto cfg = authConfig();
  cfg.casServer = "http://127.0.0.1:" ~ port.to!string;
  auto router = securedRouter(cfg, null, testDomain());
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search?ticket=ST-1");
  assert(ex.status == 200, ex.body);
  assert(cas.requests.length == 1);
}

@("configs 保持免登录")
unittest {
  auto router = securedRouter(authConfig(), new StaticSessionRepo(), testDomain());
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/configs");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["app_name"].get!string == "bas-hub");
}

private HTTPServerRequestHandler publicRouter(HubConfig cfg, Registry reg, Dao dao) {
  return buildHubRouter(cfg, reg, createHubStore(reg, dao));
}

@("CORS：允许来源的预检 204，不允许来源 403，同源不下发 CORS 头")
unittest {
  HubConfig cfg;
  cfg.apiPrefix = "/api/bashub";
  cfg.emsBase = "https://sas.openurp.net";
  cfg.authRequired = false;
  auto reg = hubRegistry();
  auto router = publicRouter(cfg, reg, demoDao(reg));

  auto preflight = call(router, HTTPMethod.OPTIONS, "http://localhost/api/bashub/config/profiles/search", null,
      ["Origin": "http://localhost:5173", "Access-Control-Request-Method": "GET",
       "Access-Control-Request-Headers": "content-type"]);
  assert(preflight.status == 204);
  assert(preflight.allowOrigin == "http://localhost:5173");
  assert(preflight.allowCredentials == "true");

  auto denied = call(router, HTTPMethod.OPTIONS, "http://localhost/api/bashub/config/profiles/search", null,
      ["Origin": "http://evil.example", "Access-Control-Request-Method": "GET"]);
  assert(denied.status == 403);

  auto sameOrigin = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search", null,
      ["Origin": "http://localhost"]);
  assert(sameOrigin.status == 200);
  assert(sameOrigin.allowOrigin.length == 0);
}

@("API 响应带安全头")
unittest {
  HubConfig cfg;
  cfg.apiPrefix = "/api/bashub";
  cfg.emsBase = "https://sas.openurp.net";
  auto reg = hubRegistry();
  auto router = publicRouter(cfg, reg, demoDao(reg));
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/configs");
  assert(ex.status == 200);
  assert(ex.contentTypeOptions == "nosniff");
  assert(ex.cacheControl == "no-store");
}
