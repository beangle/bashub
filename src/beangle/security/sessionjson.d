/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.security.sessionjson;
/// CAS 会话的 JSON 解码（`?format=application/json`）。现网 CAS 返回完整的 JSON 会话对象，
/// 因此 bashub 只保留这一种报文格式。
///
/// 为什么走 JSON：`/session/{id}` 就是个 webmvc 的 `@response` 接口，返回哪种格式只由 URL 上的
/// `format` 决定——`mvc.ViewManager` 会把容器里所有 `Serializer` bean 都收进去（`BindingRegistry`
/// 对 `List[Serializer]` 属性按类型自动装配），而 `beangle-she` 的 `beangle.xml` 已经注册了
/// `Serializer.json`。因此 D 侧只需要一个文本解码器。
///
/// 字段名与形态不是猜的：`test/beangle/security/sessionjson_test.d` 里的参考报文由 scala 侧真的
/// `JsonSerializer` 序列化 `DefaultSession` 得到。三个要记住的形态：时间是
/// `DateTimeFormatter.ISO_INSTANT` 文本、`Map` 落成 `[[k,v],...]`、null/None 直接不落盘。

import beangle.security.session;

import std.conv : to;
import std.datetime.systime : SysTime;

import vibe.data.json : Json, parseJsonString;

/// 取字符串。缺字段时 `opIndex` 给的是 `Type.undefined`，`opt` 会退到默认值。
private string textOf(Json j, string key, string def = "") {
  return j[key].opt!string(def);
}

private int intOf(Json j, string key, int def = 0) {
  return cast(int) j[key].opt!long(def);
}

private string[] textArrayOf(Json j, string key) {
  string[] values;
  auto node = j[key];
  if (node.type != Json.Type.array)
    return values;
  foreach (item; node.get!(Json[]))
    values ~= item.opt!string;
  return values;
}

/// scala 的 `Map[String,String]` 在 beangle 文本序列化里是 `[["k","v"],...]`，不是对象。
private string[string] textMapOf(Json j, string key) {
  string[string] map;
  auto node = j[key];
  if (node.type != Json.Type.array)
    return map;
  foreach (entry; node.get!(Json[])) {
    if (entry.type != Json.Type.array)
      continue;
    auto pair = entry.get!(Json[]);
    if (pair.length < 2)
      continue;
    map[pair[0].opt!string] = pair[1].opt!string;
  }
  return map;
}

/// ISO_INSTANT 文本 → epoch 秒（D 侧会话一律用秒）；字段缺失或空串都当 0。
private long instantOf(Json j, string key) {
  auto text = textOf(j, key);
  if (text.length == 0)
    return 0;
  return SysTime.fromISOExtString(text).toUnixTime;
}

private DefaultAccount decodeAccount(Json j) {
  auto a = new DefaultAccount();
  a.name = textOf(j, "name");
  a.description = textOf(j, "description");
  a.remoteToken = textOf(j, "remoteToken"); // scala 的 Option[String]，None 时字段不落盘
  a.status = intOf(j, "status"); // 五个账户状态位都在这里，D 侧由 status 算 getter
  a.categoryId = intOf(j, "categoryId");
  a.isRoot = j["isRoot"].opt!bool(false);
  a.authorities = textArrayOf(j, "authorities");
  a.permissions = textArrayOf(j, "permissions");
  a.details = textMapOf(j, "details");
  auto profiles = j["profiles"];
  if (profiles.type == Json.Type.array) {
    foreach (node; profiles.get!(Json[])) {
      auto p = new Profile();
      // scala 侧 id 是 Long，文本序列化把它写成字符串（"1"），这里两种都收
      p.id = node["id"].to!long;
      p.name = textOf(node, "name");
      p.properties = textMapOf(node, "properties");
      a.profiles ~= p;
    }
  }
  return a;
}

/** JSON 文本 → 会话。字段缺失按默认值补（空串/0/false）——scala 侧 null/None 本来就不落盘，
 * 所以 `principal`/`agent` 永远不是 null。
 */
Session decodeSessionJson(string text) {
  auto j = parseJsonString(text);
  auto s = new Session();
  s.id = textOf(j, "id");
  auto principal = j["principal"];
  if (principal.type == Json.Type.object)
    s.principal = decodeAccount(principal);
  s.loginAt = instantOf(j, "loginAt");
  s.lastAccessAt = instantOf(j, "lastAccessAt");
  s.ttiSeconds = intOf(j, "ttiSeconds");
  auto agent = j["agent"];
  if (agent.type == Json.Type.object)
    s.agent = new Agent(textOf(agent, "name"), textOf(agent, "ip"), textOf(agent, "os"));
  return s;
}
