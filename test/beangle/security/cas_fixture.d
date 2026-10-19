/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.security.cas_fixture;
/// 假 CAS 要回的 JSON 会话报文。字段名是 getter 名、时间是 ISO_INSTANT 文本。
/// 手写字符串而不是走序列化库：「服务端到底回什么」在测试里一眼可见。

import core.time : seconds;

import std.conv : to;
import std.datetime.date : DateTime;
import std.datetime.systime : SysTime;
import std.datetime.timezone : UTC;

/// epoch 秒 → 报文里的 ISO_INSTANT 文本。
string isoOf(long epochSeconds) {
  return (SysTime(DateTime(1970, 1, 1, 0, 0, 0), UTC()) + seconds(epochSeconds)).toISOExtString;
}

/// 一份最小但完整的会话报文。`at` 同时当 loginAt 与 lastAccessAt（与 scala `DefaultSession`
/// 的构造一致），principal 只带 name/description/authorities。
string jsonSession(string id, long at, string name = "demo", string description = "演示用户",
    int ttiSeconds = 1800) {
  return `{"id":"` ~ id ~ `","loginAt":"` ~ isoOf(at) ~ `","lastAccessAt":"` ~ isoOf(at)
      ~ `","ttiSeconds":` ~ ttiSeconds.to!string
      ~ `,"principal":{"name":"` ~ name ~ `","description":"` ~ description
      ~ `","authorities":["ROLE_USER"]},"agent":{"name":"curl","ip":"127.0.0.1","os":"Linux"}}`;
}

@("isoOf 出的就是 ISO_INSTANT 文本（解码器认这个形态）")
unittest {
  assert(isoOf(1000) == "1970-01-01T00:16:40Z");
}
