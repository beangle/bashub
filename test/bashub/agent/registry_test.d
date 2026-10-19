/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.agent.registry_test;
/// 登记册与现状快照：整份替换、能力排序、重复登录踢旧、断连只摘自己。

import bashub.agent.channel : Envelope, parse, result;
import bashub.agent.registry : AgentRegistry, AgentSession, RequestOutcome;

import core.time : seconds;
import vibe.data.json : Json, parseJsonString;

import std.algorithm.searching : canFind;

private Envelope envelope(string typ, string at, string body) {
  Envelope message;
  message.typ = typ;
  message.at = at;
  message.body = parseJsonString(body);
  return message;
}

@("hello and reports form the machine snapshot")
unittest {
  auto registry = new AgentRegistry();
  auto session = registry.attach("openurp.prod");

  session.accept(envelope("hello", "2026-10-16T10:00:01+08:00",
      `{"host":"app1","basctl":"0.0.4","bas":"0.14.0","basHome":"/opt/bas",
        "supports":["report:bas","hello","pong","report:os","hello"]}`));
  session.accept(envelope("report:os", "2026-10-16T10:00:02+08:00",
      `{"os":{"name":"Fedora"},"cpu":{"cores":8},"disk":[]}`));
  session.accept(envelope("report:bas", "2026-10-16T10:00:03+08:00",
      `{"instances":[{"id":"platform.server1","http.port":20000}]}`));

  assert(session.host == "app1");
  assert(session.basHome == "/opt/bas");
  assert(session.supports == ["hello", "pong", "report:bas", "report:os"]);
  assert(session.osReport["cpu"]["cores"].get!long == 8);
  assert(session.basReport["instances"].get!(Json[]).length == 1);

  auto status = session.status;
  assert(status["profile"].get!string == "openurp.prod");
  assert(status["os"]["os"]["name"].get!string == "Fedora");
  assert(status["osAt"].get!string == "2026-10-16T10:00:02+08:00");
}

@("a later report replaces the whole previous one")
unittest {
  auto registry = new AgentRegistry();
  auto session = registry.attach("demo");
  session.accept(envelope("report:os", "2026-10-16T10:00:02+08:00",
      `{"os":{"name":"Fedora"},"cpu":{"cores":8}}`));
  session.accept(envelope("report:os", "2026-10-16T10:00:03+08:00",
      `{"os":{"name":"Rocky"},"mem":{"total":1024}}`));

  assert(session.osReport["os"]["name"].get!string == "Rocky");
  assert(session.osReport["cpu"].type == Json.Type.undefined);
}

@("a new login supersedes the old connection")
unittest {
  auto registry = new AgentRegistry();
  auto first = registry.attach("demo");
  auto second = registry.attach("demo");

  assert(first.superseded);
  assert(first.closeCode == 1008);
  assert(first.closeReason == "superseded");
  assert(!second.superseded);
  assert(registry.find("demo") is second);
  assert(registry.online.length == 1);

  // 旧连接迟到的关闭不能把新连接摘掉
  registry.detach("demo", first);
  assert(registry.find("demo") is second);
  registry.detach("demo", second);
  assert(registry.find("demo") is null);
}

@("status is sorted and reportNow queues a notice")
unittest {
  auto registry = new AgentRegistry();
  auto prod = registry.attach("openurp.prod");
  auto demo = registry.attach("demo");
  prod.accept(envelope("hello", "2026-10-16T10:00:01+08:00",
      `{"host":"app1","supports":["hello","pong","report:now","report:os","report:bas"]}`));

  auto status = registry.status;
  assert(status.get!(Json[]).length == 2);
  assert(status[0]["profile"].get!string == "demo");
  assert(status[1]["profile"].get!string == "openurp.prod");

  assert(registry.reportNow("openurp.prod"));
  assert(!registry.reportNow("missing"));
  auto messages = prod.takeOutbound();
  assert(messages.length == 1);
  assert(parseJsonString(messages[0])["type"].get!string == "report:now");
  assert(demo.takeOutbound().length == 0);
}

@("a result wakes its pending request")
unittest {
  auto session = new AgentSession("demo");
  auto body = Json.emptyObject;
  body["instance"] = Json("platform.server1");
  body["from"] = Json(1L);
  body["to"] = Json(50L);

  auto id = session.startRequest("log:read", body);
  assert(id.length > 0);

  auto outbound = session.takeOutbound();
  assert(outbound.length == 1);
  Envelope request;
  assert(parse(outbound[0], request));
  assert(request.typ == "log:read");
  assert(request.id == id);
  assert(request.body["instance"].get!string == "platform.server1");

  auto data = parseJsonString(`{"total":3,"from":1,"to":2,"lines":["a","b"]}`);
  Envelope reply;
  assert(parse(result(id, true, data, ""), reply));
  session.accept(reply);

  auto answer = session.waitRequest(id, 0.seconds);
  assert(answer.outcome == RequestOutcome.ok);
  assert(answer.data["total"].get!long == 3);
  assert(answer.data["lines"].get!(Json[]).length == 2);
}

@("a missing result times out and a disconnect wakes the waiter")
unittest {
  auto session = new AgentSession("demo");
  auto id = session.startRequest("log:read", Json.emptyObject);
  assert(id.length > 0);
  auto answer = session.waitRequest(id, 0.seconds);
  assert(answer.outcome == RequestOutcome.timeout);
  assert(answer.error.canFind("timed out"));

  id = session.startRequest("log:read", Json.emptyObject);
  session.disconnect();
  answer = session.waitRequest(id, 0.seconds);
  assert(answer.outcome == RequestOutcome.offline);
  assert(answer.error == "agent disconnected");
}

@("a failed result keeps the agent error and an offline registry rejects log reads")
unittest {
  auto session = new AgentSession("demo");
  auto id = session.startRequest("log:read", Json.emptyObject);
  Envelope reply;
  assert(parse(result(id, false, Json(null), "no-log"), reply));
  session.accept(reply);

  auto answer = session.waitRequest(id, 0.seconds);
  assert(answer.outcome == RequestOutcome.failed);
  assert(answer.error == "no-log");

  auto registry = new AgentRegistry();
  answer = registry.logRead("missing", "platform.server1", 0, 0, 0.seconds);
  assert(answer.outcome == RequestOutcome.offline);
}

@("hub commands are gated by hello.supports")
unittest {
  auto registry = new AgentRegistry();
  auto session = registry.attach("demo");
  session.accept(envelope("hello", "2026-10-16T10:00:01+08:00",
      `{"host":"app1","supports":["hello","pong","report:os","report:bas"]}`));

  // 老 agent 没申报 hub 指令：不投递，也不让它收到一条会回 unsupported 的请求。
  assert(!registry.reportNow("demo"));
  auto answer = registry.logRead("demo", "platform.server1", 1, 10, 0.seconds);
  assert(answer.outcome == RequestOutcome.failed);
  assert(answer.error == "unsupported:log:read");
  assert(session.takeOutbound().length == 0);

  session.accept(envelope("hello", "2026-10-16T10:00:02+08:00",
      `{"host":"app1","supports":["hello","pong","report:now","log:read"]}`));
  assert(registry.reportNow("demo"));
  auto messages = session.takeOutbound();
  assert(messages.length == 1);
  assert(parseJsonString(messages[0])["type"].get!string == "report:now");

  auto tailAnswer = registry.logRead("demo", "platform.server1", 0, 0, 0.seconds, 100);
  assert(tailAnswer.outcome == RequestOutcome.timeout);
  auto tailMessages = session.takeOutbound();
  assert(tailMessages.length == 1);
  assert(parseJsonString(tailMessages[0])["body"]["tail"].get!long == 100);
}

@("service requests are gated and carry only the instance name")
unittest {
  auto registry = new AgentRegistry();
  auto session = registry.attach("demo");
  session.accept(envelope("hello", "2026-10-16T10:00:01+08:00",
      `{"host":"app1","supports":["hello","pong","report:os","report:bas"]}`));

  auto answer = registry.service("demo", "restart", "platform.server1", 0.seconds);
  assert(answer.outcome == RequestOutcome.failed);
  assert(answer.error == "unsupported:service:restart");
  assert(session.takeOutbound().length == 0);

  session.accept(envelope("hello", "2026-10-16T10:00:02+08:00",
      `{"host":"app1","supports":["hello","pong","service:restart"]}`));
  answer = registry.service("demo", "restart", "platform.server1", 0.seconds);
  assert(answer.outcome == RequestOutcome.timeout);
  auto messages = session.takeOutbound();
  assert(messages.length == 1);
  auto request = parseJsonString(messages[0]);
  assert(request["type"].get!string == "service:restart");
  assert(request["body"]["instance"].get!string == "platform.server1");

  answer = registry.service("missing", "stop", "platform.server1", 0.seconds);
  assert(answer.outcome == RequestOutcome.offline);
  answer = registry.service("demo", "reload", "platform.server1", 0.seconds);
  assert(answer.outcome == RequestOutcome.failed);
  assert(answer.error == "bad-request");
}
