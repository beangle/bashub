/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.security.sessionjson_test;
/// JSON 报文的兼容性：下面两份参考报文由 **scala 侧真的 `JsonSerializer`** 序列化
/// `DefaultSession` 得到（`new DefaultJsonDriver` + `DefaultMapper` + `DefaultMarshallerRegistry`
/// 拼出 `JsonSerializer`，喂一份字段齐全的会话，`serialize(s)`）。
/// 所以「字段名对得上、形态解析得开」这两条就是与 scala/ems 侧真正的兼容证据——
/// 报文里的 `[[k,v],...]`（Map）、ISO_INSTANT 时间、`"1"`（Long 写成字符串）都不是这里编的。

import beangle.security.session;
import beangle.security.sessionjson : decodeSessionJson;

import std.exception : assertThrown;

/// 全字段会话：带 authorities/permissions/details/profiles。
private enum string fullJson = `{"loginAt":"1970-01-01T00:16:40Z","agent":{"ip":"10.0.0.8",`
    ~ `"name":"Firefox","os":"Linux"},"id":"SID-1","principal":{"categoryId":1,`
    ~ `"credentialExpired":false,"description":"管理员","permissions":["hub.config.read"],`
    ~ `"authorities":["ROLE_ADMIN"],"status":0,"accountExpired":false,`
    ~ `"details":[["dept","信息中心"]],"disabled":false,`
    ~ `"profiles":[{"id":"1","name":"portal","properties":[["theme","dark"]]}],`
    ~ `"credentialReadOnly":false,"name":"admin","accountLocked":false},`
    ~ `"lastAccessAt":"1970-01-01T00:26:40Z","ttiSeconds":1800}`;

/// 最简会话：scala 侧什么都没设时，空值直接不落盘（`agent` 是个空对象）。
private enum string minJson = `{"loginAt":"1970-01-01T00:00:00Z","agent":{},"id":"x",`
    ~ `"principal":{"categoryId":0,"credentialExpired":false,"status":0,"accountExpired":false,`
    ~ `"details":[],"disabled":false,"credentialReadOnly":false,"accountLocked":false},`
    ~ `"lastAccessAt":"1970-01-01T00:00:00Z","ttiSeconds":0}`;

@("decodeSessionJson 解得开 scala JsonSerializer 编的完整报文")
unittest {
  auto s = decodeSessionJson(fullJson);
  assert(s.id == "SID-1");
  assert(s.loginAt == 1000 && s.lastAccessAt == 1600 && s.ttiSeconds == 1800);
  assert(s.principal.name == "admin" && s.principal.description == "管理员");
  assert(s.principal.categoryId == 1);
  assert(s.principal.authorities == ["ROLE_ADMIN"]);
  assert(s.principal.permissions == ["hub.config.read"]);
  assert(s.principal.details["dept"] == "信息中心"); // Map 落成 [[k,v],...]
  assert(s.principal.profiles.length == 1);
  assert(s.principal.profiles[0].id == 1 && s.principal.profiles[0].name == "portal");
  assert(s.principal.profiles[0].properties["theme"] == "dark");
  assert(s.agent.name == "Firefox" && s.agent.ip == "10.0.0.8" && s.agent.os == "Linux");
}

@("缺省字段按默认值补：principal/agent 不是 null，字符串是空串")
unittest {
  auto s = decodeSessionJson(minJson);
  assert(s.id == "x" && s.loginAt == 0 && s.lastAccessAt == 0 && s.ttiSeconds == 0);
  assert(s.principal !is null && s.principal.name == "");
  assert(s.agent !is null && s.agent.name == "" && s.agent.ip == "");
  assert(s.principal.authorities == []);
  assert(s.principal.details.length == 0);
  assert(s.principal.remoteToken == "" && !s.principal.isRemote); // None 不落盘
}

@("账户状态位从 status 还原（scala 的五个 getter 不在报文里）")
unittest {
  auto locked = decodeSessionJson(`{"id":"a","principal":{"status":3}}`);
  assert(locked.principal.accountLocked && locked.principal.disabled);
  assert(!locked.principal.accountExpired && !locked.principal.credentialExpired);
  assert(!locked.principal.credentialReadOnly);
}

@("ISO_INSTANT 带小数秒也认")
unittest {
  auto s = decodeSessionJson(`{"id":"a","loginAt":"1970-01-01T00:16:40.500Z"}`);
  assert(s.loginAt == 1000);
}

@("坏报文直接抛，交给调用方决定怎么处置")
unittest {
  assertThrown!Exception(decodeSessionJson("not json at all"));
}
