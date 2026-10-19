/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.security.cas_test;
/// CasSessionRepo 的端到端契约：URL 形状、状态码口径、JSON 解码、缓存与心跳。
/// 这里起一个假 CAS（独立线程的裸 socket，见 `fake_cas.d`），HTTP 走默认的 curl 实现——
/// 所以这套用例真的会 fork 出 curl、真的过一遍 TCP。

import beangle.security.cas : CasConfig, CasSessionRepo, casSessionMediaType;
import beangle.security.session;

import test.beangle.security.cas_fixture : jsonSession;
import test.beangle.security.fake_cas : FakeCas;

import std.conv : to;

/// CAS 会话 URL 固定使用 JSON。
private enum string jsonSuffix = "?format=application/json";

private CasSessionRepo repoOf(FakeCas cas) {
  return new CasSessionRepo(CasConfig.of("http://127.0.0.1:" ~ cas.start().to!string));
}

@("读会话：未命中回源、命中缓存、refresh 强制回源")
unittest {
  auto cas = new FakeCas();
  auto loginAt = nowSeconds();
  cas.on("/session/SID-1" ~ jsonSuffix, 200, cast(ubyte[]) jsonSession("SID-1", loginAt));
  auto repo = repoOf(cas);
  scope (exit) cas.stop();

  auto s = repo.get("SID-1");
  assert(s !is null && s.id == "SID-1" && s.principal.name == "demo");
  assert(s.ttiSeconds == 1800 && s.loginAt == loginAt);
  assert(s.agent.name == "curl");
  assert(cas.requests == ["/session/SID-1" ~ jsonSuffix]);

  assert(repo.get("SID-1") is s); // 命中缓存，连对象都是同一份
  assert(cas.requests.length == 1);
  assert(repo.get("SID-1", true) !is null);
  assert(cas.requests.length == 2);
}

@("会话不存在（404）当作没有，不抛异常")
unittest {
  auto cas = new FakeCas(); // 没装任何路由：一律 404
  auto repo = repoOf(cas);
  scope (exit) cas.stop();

  assert(repo.get("SID-9") is null);
  assert(repo.access("SID-9", nowSeconds()) is null);
  assert(cas.requests == ["/session/SID-9" ~ jsonSuffix, "/session/SID-9" ~ jsonSuffix]);
}

@("心跳：超过访问延迟就上报 /session/{id}/access?time=")
unittest {
  auto cas = new FakeCas();
  auto loginAt = nowSeconds();
  cas.on("/session/SID-1" ~ jsonSuffix, 200, cast(ubyte[]) jsonSession("SID-1", loginAt));
  auto repo = repoOf(cas);
  repo.accessDelaySeconds = 20;
  scope (exit) cas.stop();

  auto s = repo.get("SID-1");
  auto accessAt = loginAt + 300;
  cas.on("/session/SID-1/access?time=" ~ accessAt.to!string, 200, cast(ubyte[]) "ok");

  assert(repo.access("SID-1", accessAt) is s);
  assert(s.lastAccessAt == accessAt);
  assert(cas.requests.length == 1); // 攒着，还没发
  repo.reportHeartbeats();
  assert(cas.requests == ["/session/SID-1" ~ jsonSuffix,
      "/session/SID-1/access?time=" ~ accessAt.to!string]);
}

@("访问已过期的会话：清缓存并打 /session/{id}/expire")
unittest {
  auto cas = new FakeCas();
  auto loginAt = nowSeconds();
  cas.on("/session/SID-1" ~ jsonSuffix, 200, cast(ubyte[]) jsonSession("SID-1", loginAt));
  cas.on("/session/SID-1/expire", 200, cast(ubyte[]) "Expire SID-1 successfully.");
  auto repo = repoOf(cas);
  scope (exit) cas.stop();

  assert(repo.get("SID-1") !is null);
  assert(repo.access("SID-1", loginAt + 1801) is null); // tti = 1800
  assert(cas.requests[$ - 1] == "/session/SID-1/expire");
}

@("心跳发现后端已无此会话：只清本地缓存，不再打 expire")
unittest {
  auto cas = new FakeCas();
  auto loginAt = nowSeconds();
  cas.on("/session/SID-1" ~ jsonSuffix, 200, cast(ubyte[]) jsonSession("SID-1", loginAt));
  auto repo = repoOf(cas);
  repo.accessDelaySeconds = 20;
  scope (exit) cas.stop();

  assert(repo.get("SID-1") !is null);
  assert(repo.access("SID-1", loginAt + 300) !is null);
  // access 没装路由：curl 拿到 404，flush 返回 false —— 与 scala 一样，只清缓存
  repo.reportHeartbeats();
  assert(cas.requests[$ - 1] == "/session/SID-1/access?time=" ~ (loginAt + 300).to!string);
  assert(repo.get("SID-1") !is null);
  assert(cas.requests.length == 3); // 回源、心跳（404）、缓存被摘掉后再回源
}

@("findByPrincipal：先取 id 列表，再逐个回源")
unittest {
  auto cas = new FakeCas();
  auto loginAt = nowSeconds();
  cas.on("/session/demo/ids", 200, cast(ubyte[]) "SID-1,SID-2");
  cas.on("/session/SID-1" ~ jsonSuffix, 200, cast(ubyte[]) jsonSession("SID-1", loginAt));
  cas.on("/session/SID-2" ~ jsonSuffix, 200, cast(ubyte[]) jsonSession("SID-2", loginAt + 5));
  auto repo = repoOf(cas);
  scope (exit) cas.stop();

  auto found = repo.findByPrincipal("demo");
  assert(found.length == 2);
  assert(found[0].id == "SID-1" && found[1].id == "SID-2");
  assert(cas.requests == ["/session/demo/ids", "/session/SID-1" ~ jsonSuffix,
      "/session/SID-2" ~ jsonSuffix]);
}

@("四个 URL 的契约：会话固定 JSON，其余路径逐字对齐")
unittest {
  auto cfg = CasConfig.of("https://sas.openurp.net/cas/");
  assert(cfg.casServer == "https://sas.openurp.net/cas");
  assert(cfg.getUrl == "https://sas.openurp.net/cas/session/{id}" ~ jsonSuffix);
  assert(cfg.accessUrl == "https://sas.openurp.net/cas/session/{id}/access?time={time}");
  assert(cfg.findUrl == "https://sas.openurp.net/cas/session/{principal}/ids");
  assert(cfg.expireUrl == "https://sas.openurp.net/cas/session/{id}/expire");
  assert(casSessionMediaType == "application/json");
}

@("报文解不开当成没有会话，不把请求打成 500")
unittest {
  auto cas = new FakeCas();
  cas.on("/session/SID-1" ~ jsonSuffix, 200, cast(ubyte[]) "{");
  auto repo = repoOf(cas);
  scope (exit) cas.stop();

  assert(repo.get("SID-1") is null);
}
