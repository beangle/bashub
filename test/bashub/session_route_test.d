/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.session_route_test;
/// `sessions` 端点接上 CAS 会话仓库后的契约：cookie → 真实用户、没会话 → 401（带跳转地址）、
/// 退出登录只 evict（CAS 那边的会话让它自己过期）。这里 HTTP 客户端走默认的 curl，服务端是假 CAS。

import bashub.config;
import bashub.demo;
import bashub.resources;
import bashub.route;
import bashub.store;

import beangle.data.resource : Registry;
import beangle.data.dao : Dao;
import beangle.security.cas : CasConfig, CasSessionRepo;
import beangle.security.session;

import test.beangle.security.cas_fixture : jsonSession;
import test.beangle.security.fake_cas : FakeCas;

import std.algorithm.searching : startsWith;
import std.conv : to;

import vibe.data.json : parseJson;
import vibe.http.common : HTTPMethod;
import vibe.http.server : HTTPServerRequestHandler, createTestHTTPServerRequest, createTestHTTPServerResponse, TestHTTPResponseMode;
import vibe.inet.message : InetHeaderMap;
import vibe.inet.url : URL;
import vibe.stream.memory : createMemoryOutputStream;

private struct Exchange {
  int status;
  string body;
  bool hasSessionCookie;
  long sessionCookieMaxAge;
}

private Exchange call(HTTPServerRequestHandler router, HTTPMethod method, string url, string cookie = null) {
  InetHeaderMap headers;
  headers["Accept"] = "application/vnd.api+json";
  if (cookie.length > 0)
    headers["Cookie"] = cookie;
  auto req = createTestHTTPServerRequest(URL(url), method, headers, null);
  auto output = createMemoryOutputStream();
  auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);
  router.handleRequest(req, res);
  Exchange ex;
  ex.status = cast(int) res.statusCode;
  ex.body = cast(string) output.data;
  auto sessionCookie = res.cookies.get("EMS_SID", null);
  ex.hasSessionCookie = sessionCookie !is null;
  if (sessionCookie !is null)
    ex.sessionCookieMaxAge = sessionCookie.maxAge;
  return ex;
}

private HubConfig casConfig(bool authRequired) {
  HubConfig cfg;
  cfg.apiPrefix = "/api/bashub";
  cfg.emsBase = "https://sas.openurp.net";
  cfg.appName = "bas-hub";
  cfg.authRequired = authRequired;
  cfg.casServer = "https://sas.openurp.net/cas";
  return cfg;
}

private HTTPServerRequestHandler newRouter(HubConfig cfg, SessionRepo sessions, Registry reg, Dao dao) {
  return buildHubRouter(cfg, reg, createHubStore(reg, dao), sessions);
}


@("带 EMS_SID 时 sessions 回真实用户（每个会话只回源一次）")
unittest {
  auto cas = new FakeCas();
  cas.on("/session/SID-1?format=application/json", 200,
      cast(ubyte[]) jsonSession("SID-1", nowSeconds(), "admin", "管理员"));
  auto repo = new CasSessionRepo(CasConfig.of("http://127.0.0.1:" ~ cas.start().to!string));
  scope (exit) cas.stop();

  auto cfg = casConfig(true);
  auto reg = hubRegistry();
  auto router = newRouter(cfg, repo, reg, demoDao(reg));

  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/sessions", "EMS_SID=SID-1");
  assert(ex.status == 200);
  auto doc = parseJson(ex.body);
  assert(doc["code"].get!string == "admin");
  assert(doc["name"].get!string == "管理员");
  assert(cas.requests.length == 1);

  // 第二次走缓存，不再问 CAS
  assert(call(router, HTTPMethod.GET, "http://localhost/api/bashub/sessions", "EMS_SID=SID-1").status == 200);
  assert(cas.requests.length == 1);
}

@("要鉴权又没有会话：401 带 CAS 跳转地址")
unittest {
  auto cas = new FakeCas();
  auto repo = new CasSessionRepo(CasConfig.of("http://127.0.0.1:" ~ cas.start().to!string));
  auto cfg = casConfig(true);
  auto reg = hubRegistry();
  auto router = newRouter(cfg, repo, reg, demoDao(reg));

  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/sessions");
  assert(ex.status == 401);
  auto redirect = parseJson(ex.body)["errors"][0]["meta"]["redirectUrl"].get!string;
  assert(redirect.startsWith("https://sas.openurp.net/cas/login?service="));

  // CAS 那边已经没有这个会话（404）也是同样待遇，而且不会发第二次请求
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/sessions", "EMS_SID=SID-9");
  assert(ex.status == 401);
  assert(cas.requests.length == 1);
  cas.stop();
}

@("不要鉴权时没会话仍给演示用户（没配 cas 的部署照旧）")
unittest {
  auto reg = hubRegistry();
  auto ex = call(newRouter(casConfig(false), null, reg, demoDao(reg)), HTTPMethod.GET,
      "http://localhost/api/bashub/sessions");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["code"].get!string == "demo");
}

@("退出登录只清本地缓存，不打 CAS 的 expire")
unittest {
  auto cas = new FakeCas();
  cas.on("/session/SID-1?format=application/json", 200,
      cast(ubyte[]) jsonSession("SID-1", nowSeconds(), "admin", "管理员"));
  auto repo = new CasSessionRepo(CasConfig.of("http://127.0.0.1:" ~ cas.start().to!string));
  scope (exit) cas.stop();

  auto cfg = casConfig(true);
  auto reg = hubRegistry();
  auto router = newRouter(cfg, repo, reg, demoDao(reg));

  assert(call(router, HTTPMethod.GET, "http://localhost/api/bashub/sessions", "EMS_SID=SID-1").status == 200);
  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/sessions/logout", "EMS_SID=SID-1");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["logoutUrl"].get!string == "https://sas.openurp.net/cas/logout");
  assert(ex.hasSessionCookie);
  assert(ex.sessionCookieMaxAge == 0);
  assert(cas.requests.length == 1); // 只清了本地缓存

  // 缓存清了，下一次还得回源
  assert(call(router, HTTPMethod.GET, "http://localhost/api/bashub/sessions", "EMS_SID=SID-1").status == 200);
  assert(cas.requests.length == 2);
}
