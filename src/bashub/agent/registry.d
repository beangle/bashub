/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.agent.registry;
/// 在线 agent 的登记册：每个 profile 最多一条连接，断连即摘除。
///
/// D 的 WebSocket 是回调作用域里的对象，不能塞进长期存活的登记册。于是把「连接」拆成两份：
/// 这里只放现状快照与出站队列；真正读写 socket 的循环在 `bashub.agent.socket`，它拿队列里的
/// 文本去发。`AgentSession` 因此可以脱离 WebSocket 单测。

import channel = bashub.agent.channel;

import core.time : Duration, MonoTime, seconds;
import std.uuid : randomUUID;
import vibe.core.sync : TaskCondition, TaskMutex;
import vibe.core.log : logWarn;
import vibe.data.json : Json;

import std.algorithm : canFind, sort;
import std.array : appender;
import std.string : strip;

/// 一次请求的最终状态。
enum RequestOutcome {
  ok,
  failed,
  timeout,
  offline
}

/// `result` 解开后的应答；`failed` 保留 agent 给出的错误串。
struct AgentReply {
  RequestOutcome outcome;
  Json data = Json(null);
  string error;

  static AgentReply success(Json data) {
    return AgentReply(RequestOutcome.ok, data, "");
  }

  static AgentReply failure(RequestOutcome outcome, string error) {
    return AgentReply(outcome, Json(null), error);
  }
}

/// 挂在请求号上的等待者；`accept` 只负责填结果并唤醒。
private final class PendingRequest {
  Json body = Json(null);
  bool done;
  RequestOutcome outcome = RequestOutcome.ok;
}

/// 一条 agent 通道的现状快照。
final class AgentSession {
  immutable string profile;
  immutable string connectedAt;

  string host;
  string basctlVersion;
  string basVersion;
  string basHome;
  string[] supports;
  string lastSeenAt;

  Json osReport = Json(null);
  string osAt;
  Json basReport = Json(null);
  string basAt;

  /// 出站队列：保活、立即上报与未来的请求都从这里交给 socket 循环。
  private string[] outbound;

  /// 请求号 → 等待者。请求发起后由 socket 循环在 `result` 到达时唤醒。
  private PendingRequest[string] pending;
  private TaskMutex pendingLock;
  private TaskCondition pendingChanged;

  /// 新连接踢旧连接时只打标记，旧循环自己关自己的 socket。
  bool superseded;
  bool closeRequested;
  short closeCode;
  string closeReason;

  this(string profile) {
    this.profile = profile;
    this.connectedAt = channel.now();
    this.lastSeenAt = connectedAt;
    pendingLock = new TaskMutex();
    pendingChanged = new TaskCondition(pendingLock);
  }

  /// 收到一条来自 agent 的消息；无论是什么都不抛出去。
  void accept(const channel.Envelope message) {
    lastSeenAt = channel.now();
    switch (message.typ) {
    case "hello":
      hello(message.body);
      break;
    case "report:os":
      osReport = message.body;
      osAt = message.at;
      break;
    case "report:bas":
      basReport = message.body;
      basAt = message.at;
      break;
    case "pong":
      break;
    case "result":
      complete(message.id, message.body);
      break;
    default:
      logWarn("%s: ignore %s %s", profile, message.isRequest ? "request" : "notice", message.typ);
      break;
    }
  }

  /// 投递一条出站消息。实际发送由持有 socket 的循环完成。
  bool offer(string message) {
    if (message.length == 0)
      return false;
    outbound ~= message;
    return true;
  }

  /// agent 是否在 `hello.supports` 里声明支持某个原语。
  bool supportsPrimitive(string primitive) const {
    return supports.canFind(primitive);
  }

  /// 取走当前积压；返回后队列为空。
  string[] takeOutbound() {
    auto messages = outbound;
    outbound = null;
    return messages;
  }

  /// 被同一 profile 的新连接取代。
  void supersede() {
    superseded = true;
    closeRequested = true;
    closeCode = 1008;
    closeReason = "superseded";
  }

  /// 发起一条带 `id` 的请求并等 `result`；超时、断连或发送失败都收敛成 `AgentReply`。
  AgentReply request(string typ, Json body, Duration timeout) {
    auto id = startRequest(typ, body);
    if (id.length == 0)
      return AgentReply.failure(RequestOutcome.offline, "send failed");
    return waitRequest(id, timeout);
  }

  /** 登记请求并入队，返回请求号；发送失败返回空串。
   *
   * 拆成 start / wait 两步是为了让等待表能脱离事件循环验证：测试可以先拿到请求号，再喂一条
   * `result`，最后以零超时取结果。
   */
  string startRequest(string typ, Json body) {
    auto id = randomUUID().toString;
    auto waiter = new PendingRequest();
    pendingLock.lock();
    pending[id] = waiter;
    pendingLock.unlock();

    if (offer(channel.render(typ, id, body)))
      return id;
    removePending(id);
    return "";
  }

  /// 等一个已登记请求的应答；超时或连接断开返回对应状态，不抛异常。
  AgentReply waitRequest(string id, Duration timeout) {
    PendingRequest waiter;
    pendingLock.lock();
    if (auto found = id in pending)
      waiter = *found;
    if (waiter is null) {
      pendingLock.unlock();
      return AgentReply.failure(RequestOutcome.failed, "no pending request: " ~ id);
    }

    auto deadline = MonoTime.currTime + timeout;
    while (!waiter.done) {
      auto remaining = deadline - MonoTime.currTime;
      if (remaining <= 0.seconds)
        break;
      pendingChanged.wait(remaining);
    }
    auto done = waiter.done;
    auto outcome = waiter.outcome;
    auto body = waiter.body;
    pending.remove(id);
    pendingLock.unlock();

    if (!done)
      return AgentReply.failure(RequestOutcome.timeout, "request " ~ id ~ " timed out");
    if (outcome == RequestOutcome.offline)
      return AgentReply.failure(RequestOutcome.offline, "agent disconnected");
    return decodeReply(body);
  }

  /// 连接断开：把等待者标成离线并全部唤醒；各调用方取到结果后自行摘除。
  void disconnect() nothrow {
    pendingLock.lock();
    foreach (_, waiter; pending) {
      if (!waiter.done) {
        waiter.done = true;
        waiter.outcome = RequestOutcome.offline;
      }
    }
    pendingChanged.notifyAll();
    pendingLock.unlock();
  }

  /// 控制台读到的现状，字段名与协议文档、Scala 侧保持一致。
  Json status() {
    auto item = Json.emptyObject;
    item["profile"] = Json(profile);
    item["host"] = Json(host);
    item["basctl"] = Json(basctlVersion);
    item["bas"] = Json(basVersion);
    item["basHome"] = Json(basHome);
    auto caps = appender!(Json[])();
    foreach (capability; supports)
      caps.put(Json(capability));
    item["supports"] = Json(caps.data);
    item["connectedAt"] = Json(connectedAt);
    item["lastSeenAt"] = Json(lastSeenAt);
    item["osAt"] = Json(osAt);
    item["os"] = osReport;
    item["basAt"] = Json(basAt);
    item["basReport"] = basReport;
    return item;
  }

  private void hello(Json body) {
    host = channel.textOf(body, "host");
    basctlVersion = channel.textOf(body, "basctl");
    basVersion = channel.textOf(body, "bas");
    basHome = channel.textOf(body, "basHome");

    bool[string] seen;
    string[] declared;
    auto value = body["supports"];
    if (value.type == Json.Type.array) {
      foreach (ref item; value) {
        if (item.type != Json.Type.string)
          continue;
        auto capability = item.get!string.strip;
        if (capability.length > 0 && capability !in seen) {
          seen[capability] = true;
          declared ~= capability;
        }
      }
    }
    supports = declared.sort.release;
  }

  private void complete(string id, Json body) {
    if (id.length == 0)
      return;
    pendingLock.lock();
    if (auto found = id in pending) {
      auto waiter = *found;
      if (!waiter.done) {
        waiter.body = body;
        waiter.done = true;
        waiter.outcome = RequestOutcome.ok;
        pendingChanged.notifyAll();
      }
    }
    pendingLock.unlock();
  }

  private void removePending(string id) {
    pendingLock.lock();
    pending.remove(id);
    pendingLock.unlock();
  }

  private AgentReply decodeReply(Json body) {
    auto ok = body["ok"];
    if (ok.type != Json.Type.bool_)
      return AgentReply.failure(RequestOutcome.failed, "bad result envelope");
    if (!ok.get!bool) {
      auto error = channel.textOf(body, "error");
      return AgentReply.failure(RequestOutcome.failed, error.length > 0 ? error : "agent request failed");
    }
    auto data = body["data"];
    return AgentReply.success(data.type == Json.Type.undefined ? Json.emptyObject : data);
  }
}

/// 每个 profile 一条在线连接。
final class AgentRegistry {
  private AgentSession[string] sessions;

  /// 登记新连接；同一 profile 的旧连接被标记为 `superseded`。
  AgentSession attach(string profile) {
    auto session = new AgentSession(profile);
    if (auto previous = profile in sessions)
      (*previous).supersede();
    sessions[profile] = session;
    return session;
  }

  /// 摘除一条连接；只摘自己那条，旧连接迟到的关闭不能把新连接挤掉。
  void detach(string profile, AgentSession session) nothrow {
    if (auto found = profile in sessions) {
      if (*found is session)
        sessions.remove(profile);
    }
    session.disconnect();
  }

  AgentSession find(string profile) {
    if (auto found = profile in sessions)
      return *found;
    return null;
  }

  /// 在线连接，按 profile 排序。
  AgentSession[] online() {
    AgentSession[] list;
    foreach (_, session; sessions)
      list ~= session;
    list.sort!((left, right) => left.profile < right.profile);
    return list;
  }

  /// `GET /api/hub/agents/status` 的数组。
  Json status() {
    Json[] items;
    foreach (session; online())
      items ~= session.status;
    return Json(items);
  }

  /// 请某个在线 agent 立即上报；不在线返回 false。
  bool reportNow(string profile) {
    auto session = find(profile);
    if (session is null || !session.supportsPrimitive("report:now"))
      return false;
    return session.offer(channel.reportNow());
  }

  /// 下发 `log:read` 并等待 agent 的 `result`。
  AgentReply logRead(string profile, string instance, long from, long to,
      Duration timeout = 5.seconds, long tail = 0) {
    auto session = find(profile);
    if (session is null)
      return AgentReply.failure(RequestOutcome.offline, "agent offline: " ~ profile);
    if (!session.supportsPrimitive("log:read"))
      return AgentReply.failure(RequestOutcome.failed, "unsupported:log:read");
    auto body = Json.emptyObject;
    body["instance"] = Json(instance);
    body["from"] = Json(from);
    body["to"] = Json(to);
    if (tail > 0)
      body["tail"] = Json(tail);
    return session.request("log:read", body, timeout);
  }

  /// 下发 `service:start|stop|restart` 并等待 agent 的 `result`。
  AgentReply service(string profile, string action, string instance,
      Duration timeout = 120.seconds) {
    if (action != "start" && action != "stop" && action != "restart")
      return AgentReply.failure(RequestOutcome.failed, "bad-request");
    auto session = find(profile);
    if (session is null)
      return AgentReply.failure(RequestOutcome.offline, "agent offline: " ~ profile);
    auto primitive = "service:" ~ action;
    if (!session.supportsPrimitive(primitive))
      return AgentReply.failure(RequestOutcome.failed, "unsupported:" ~ primitive);
    auto body = Json.emptyObject;
    body["instance"] = Json(instance);
    return session.request(primitive, body, timeout);
  }

  /// 给所有在线连接投递一条保活；没有连接时什么也不做。
  void pingAll() {
    foreach (session; online())
      session.offer(channel.ping());
  }
}
