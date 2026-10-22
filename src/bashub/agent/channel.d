/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.agent.channel;
/// 控制通道协议（hub 侧）。权威文档是 basctl 的 `docs/channel-protocol.md`。
///
/// 这里只有信封、原语名单与编解码，不碰 WebSocket，也不碰登记册：协议层可以脱离容器单测。
/// 两条不变量与 agent 侧对等：原语封闭（`type` 必须在名单里），字段开放（多余的键忽略、
/// 缺失的可选字段不抛异常）。

import vibe.data.json : Json, parseJsonString;

import core.time;
import std.array : split;
import std.conv : ConvException, to;
import std.datetime : Clock;
import std.format : format;
import std.string : strip, toLower;

/// agent → hub 的原语。
enum AgentPrimitives = ["hello", "report:os", "report:bas", "result", "pong"];

/// hub → agent 的原语。
enum HubPrimitives = [
  "ping", "report:now", "log:read", "agent:log", "service:start", "service:stop", "service:restart"
];

/// 请求号上限；与 basctl 的 `bas.channel.maxRequestIdLength` 保持一致。
private enum size_t MaxRequestIdBytes = 64;

/// 一条消息：`id` 非空表示请求，接收方要用 `result` 应答；空表示通知。
struct Envelope {
  string typ;
  string id;
  string at;
  Json body = Json.emptyObject;

  bool isRequest() const {
    return id.length > 0;
  }
}

/// 本机时区的 ISO-8601 时刻，与 `server.info` 的 `started` 同格式（`+08:00` 那种）。
string now() {
  auto current = Clock.currTime.toLocalTime;
  auto offset = cast(int) current.utcOffset.total!"minutes";
  auto sign = offset < 0 ? '-' : '+';
  if (offset < 0)
    offset = -offset;
  return format("%04d-%02d-%02dT%02d:%02d:%02d%c%02d:%02d",
      current.year, cast(int) current.month, current.day, current.hour, current.minute,
      current.second, sign, offset / 60, offset % 60);
}

/// 解析一条消息；非 JSON、不是对象、缺 `type` 都返回 false，调用方只记日志，不断连。
bool parse(string text, out Envelope envelope) {
  try {
    auto doc = parseJsonString(text);
    if (doc.type != Json.Type.object)
      return false;
    auto typ = doc["type"];
    if (typ.type != Json.Type.string)
      return false;
    auto value = typ.get!string.strip;
    if (value.length == 0)
      return false;

    Envelope parsed;
    parsed.typ = value;
    parsed.id = textOf(doc, "id");
    if (parsed.id.length && !validRequestId(parsed.id))
      return false;
    parsed.at = textOf(doc, "at");
    auto body = doc["body"];
    parsed.body = body.type == Json.Type.object ? body : Json.emptyObject;
    envelope = parsed;
    return true;
  } catch (Exception) {
    return false;
  }
}

/// 请求号只允许有限字符与长度，挡住超长缓存键和日志注入。
private bool validRequestId(string id) @safe pure nothrow {
  if (!id.length || id.length > MaxRequestIdBytes)
    return false;
  foreach (ch; id) {
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')
        || ch == '-' || ch == '_' || ch == '.' || ch == ':')
      continue;
    return false;
  }
  return true;
}

/// 渲染一条消息；`id` 非空即请求。
string render(string typ, string id, Json body) {
  auto message = Json.emptyObject;
  message["type"] = Json(typ);
  if (id.length > 0)
    message["id"] = Json(id);
  message["at"] = Json(now());
  message["body"] = body.type == Json.Type.object ? body : Json.emptyObject;
  return message.toString;
}

/// 保活；agent 沉默超时会重连，所以按期发是 hub 的责任。
string ping() {
  return render("ping", "", Json.emptyObject);
}

/// 请 agent 立刻报一次；报告本身就是回执，因此不带 `id`。
string reportNow() {
  return render("report:now", "", Json.emptyObject);
}

/// 读实例日志的一段，带 `id`，agent 用 `result` 应答。`tail` 大于 0 时用于首次定位尾部。
string logRead(string id, string instance, long from, long to, long tail = 0) {
  auto body = Json.emptyObject;
  body["instance"] = Json(instance);
  body["from"] = Json(from);
  body["to"] = Json(to);
  if (tail > 0)
    body["tail"] = Json(tail);
  return render("log:read", id, body);
}

/// 读 basagent 自身日志，不带实例名；窗口语义与 `log:read` 相同。
string agentLog(string id, long from, long to, long tail = 0) {
  auto body = Json.emptyObject;
  body["from"] = Json(from);
  body["to"] = Json(to);
  if (tail > 0)
    body["tail"] = Json(tail);
  return render("agent:log", id, body);
}

/// 服务动作：basctl 在 `hello.supports` 里申报后，hub 才能下发。
string service(string action, string id, string instance) {
  if (action != "start" && action != "stop" && action != "restart")
    return "";
  auto body = Json.emptyObject;
  body["instance"] = Json(instance);
  return render("service:" ~ action, id, body);
}

/// 对所有带 `id` 请求的应答。
string result(string id, bool ok, Json data, string error) {
  auto body = Json.emptyObject;
  body["ok"] = Json(ok);
  if (ok || data.type == Json.Type.object)
    body["data"] = data.type == Json.Type.object ? data : Json.emptyObject;
  if (!ok)
    body["error"] = Json(error);
  return render("result", id, body);
}

/// 从 `.../<profile>/agents` 取 profile；路径末尾的斜杠可以省略。
bool profileOf(string path, out string profile) {
  if (path.length == 0)
    return false;
  auto parts = path.strip.split("/");
  auto end = parts.length;
  while (end > 0 && parts[end - 1].length == 0)
    end--;
  if (end < 2 || parts[end - 1] != "agents" || parts[end - 2].length == 0)
    return false;
  profile = parts[end - 2];
  return true;
}

/// 取 `Authorization: Bearer <key>` 里的凭证；头名由调用方按 HTTP 规则取，值这里不区分大小写。
bool bearer(string header, out string key) {
  auto value = header.strip;
  if (value.length < 7 || value[0 .. 7].toLower != "bearer ")
    return false;
  key = value[7 .. $].strip;
  return key.length > 0;
}

/// 取 body 里的字符串字段；缺字段或类型不对返回空串（字段开放）。
string textOf(Json body, string key) {
  if (body.type != Json.Type.object)
    return "";
  auto value = body[key];
  return value.type == Json.Type.string ? value.get!string.strip : "";
}

/// 取 body 里的整数字段；兼容数字与数字字符串。
bool numberOf(Json body, string key, out long number) {
  if (body.type != Json.Type.object)
    return false;
  auto value = body[key];
  final switch (value.type) {
  case Json.Type.int_:
    number = value.get!long;
    return true;
  case Json.Type.float_:
    number = cast(long) value.get!double;
    return true;
  case Json.Type.bigInt:
    number = value.get!long;
    return true;
  case Json.Type.string:
    try {
      number = value.get!string.strip.to!long;
      return true;
    } catch (ConvException) {
      return false;
    }
  case Json.Type.undefined:
  case Json.Type.null_:
  case Json.Type.bool_:
  case Json.Type.array:
  case Json.Type.object:
    return false;
  }
}
