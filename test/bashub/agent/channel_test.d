/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.agent.channel_test;
/// 协议层契约：样例与 basctl 的 `test/channel_test.d`、Scala 的 `ChannelTest` 对齐。

import bashub.agent.channel;

import vibe.data.json : Json, parseJsonString;

import std.array : join;
import std.range : repeat;
import std.string : indexOf;

@("parse a report notice and a log request")
unittest {
  Envelope report;
  assert(parse(`{"type":"report:os","at":"2026-10-16T10:00:00+08:00",
      "body":{"cpu":{"cores":8}}}`, report));
  assert(report.typ == "report:os");
  assert(!report.isRequest);
  assert(report.body["cpu"]["cores"].get!long == 8);

  Envelope request;
  assert(parse(`{"type":"log:read","id":"r1","at":"2026-10-16T10:00:00+08:00",
      "body":{"instance":"platform.server1","from":1,"to":50}}`, request));
  assert(request.isRequest);
  assert(request.id == "r1");
  assert(textOf(request.body, "instance") == "platform.server1");
  long from;
  assert(numberOf(request.body, "from", from));
  assert(from == 1);
}

@("a bad message is dropped instead of thrown")
unittest {
  Envelope message;
  assert(!parse("not json", message));
  assert(!parse(`[1,2,3]`, message));
  assert(!parse(`{"at":"2026-10-16T10:00:00+08:00"}`, message));
  assert(!parse(`{"type":"result","id":"bad id","body":{}}`, message));
  assert(!parse(`{"type":"result","id":"` ~ "a".repeat(65).join ~ `","body":{}}`, message));

  // 缺 body / id 不是错误，只是「没有」；字段开放
  assert(parse(`{"type":"pong"}`, message));
  assert(!message.isRequest);
  assert(message.body.type == Json.Type.object);
  assert(message.body.length == 0);
}

@("render a hub request and read it back")
unittest {
  auto text = logRead("r2", "platform.server1", 1, 50);
  auto doc = parseJsonString(text);
  assert(doc["type"].get!string == "log:read");
  assert(doc["id"].get!string == "r2");
  assert(doc["at"].get!string.length == 25);

  Envelope parsed;
  assert(parse(text, parsed));
  assert(parsed.isRequest);

  // 通知不带 id：省一次往返，报告本身就是回执
  assert(parseJsonString(reportNow())["id"].type == Json.Type.undefined);
  assert(parseJsonString(ping())["type"].get!string == "ping");
  auto tail = parseJsonString(logRead("r3", "platform.server1", 0, 0, 100));
  assert(tail["body"]["tail"].get!long == 100);
  auto own = parseJsonString(agentLog("r3", 0, 0, 100));
  assert(own["type"].get!string == "agent:log");
  assert(own["body"]["instance"].type == Json.Type.undefined);
  assert(own["body"]["tail"].get!long == 100);
  assert(service("reload", "r3", "server1").length == 0);

  auto restart = parseJsonString(service("restart", "r4", "platform.server1"));
  assert(restart["type"].get!string == "service:restart");
  assert(restart["id"].get!string == "r4");
  assert(restart["body"]["instance"].get!string == "platform.server1");
}

@("the profile comes out of the request path")
unittest {
  string profile;
  assert(profileOf("/api/openurp.demo/agents", profile));
  assert(profile == "openurp.demo");
  assert(profileOf("/bashub/api/demo/agents/", profile));
  assert(profile == "demo");
  assert(!profileOf("/api/demo", profile));
  assert(!profileOf("/agents", profile));
  assert(!profileOf("", profile));
}

@("the key comes out of the Authorization value")
unittest {
  string key;
  assert(bearer("Bearer k1", key));
  assert(key == "k1");
  assert(bearer("bearer k1", key));
  assert(key == "k1");
  assert(bearer("  Bearer   k1  ", key));
  assert(key == "k1");
  assert(!bearer("Basic abc", key));
  assert(!bearer("Bearer   ", key));
  assert(!bearer("", key));
}

@("the timestamp is local ISO-8601 with an offset")
unittest {
  auto value = now();
  assert(value.length == 25);
  assert(value[10] == 'T');
  auto offset = value[19 .. $].indexOf(":");
  assert(offset == 3);
  assert(value[19] == '+' || value[19] == '-');
}
