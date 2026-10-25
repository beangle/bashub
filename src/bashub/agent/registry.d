/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.agent.registry;
/// 在线 agent 的登记册：每个 project 最多一条连接，断连即摘除。
///
/// D 的 WebSocket 是回调作用域里的对象，不能塞进长期存活的登记册。于是把「连接」拆成两份：
/// 这里只放现状快照与出站队列；真正读写 socket 的循环在 `bashub.agent.socket`，它拿队列里的
/// 文本去发。`AgentSession` 因此可以脱离 WebSocket 单测。

import channel = bashub.agent.channel;
import bashub.agent.history : AgentHistoryStore, AgentSample;

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

/// `hello` 的字段上限：异常 agent 不能让快照无界增长。
private enum size_t MaxHelloHostBytes = 255;
private enum size_t MaxHelloVersionBytes = 128;
private enum size_t MaxHelloHomeBytes = 4096;
private enum size_t MaxCapabilityBytes = 64;
private enum size_t MaxServerIdBytes = 255;
private enum size_t MaxHealthServers = 512;

/// `result` 解开后的应答；`failed` 保留 agent 给出的错误串。
struct AgentReply {
  RequestOutcome outcome;
  Json data = Json(null);
  string error;

  static AgentReply success(Json data) {
    return AgentReply(RequestOutcome.ok, data, "");
  }

  static AgentReply failure(RequestOutcome outcome, string error, Json data = Json(null)) {
    return AgentReply(outcome, data, error);
  }
}

/// 挂在请求号上的等待者；`accept` 只负责填结果并唤醒。
private final class PendingRequest {
  Json body = Json(null);
  bool done;
  RequestOutcome outcome = RequestOutcome.ok;
}

/** 一条物理 WebSocket 的出站队列；relay master 与它的逻辑子会话共享。 */
final class AgentQueue {
  private string[] outbound;
  bool superseded;
  short closeCode;
  string closeReason;

  bool offer(string message) {
    if (message.length == 0)
      return false;
    outbound ~= message;
    return true;
  }

  string[] take() {
    auto messages = outbound;
    outbound = null;
    return messages;
  }
}

/// 一条 agent 通道的现状快照。
final class AgentSession {
  immutable string project;
  immutable string projectId;
  /// agent 上报的服务器 IP；同一 project 下按它区分多台机器（`project@ip`）。
  immutable string ip;
  immutable string connectedAt;
  /// 建立连接的本地时刻：只用来算在线时长，对外展示仍用 `connectedAt`。
  immutable MonoTime startedAt;

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

  AgentSample[] health;
  bool healthKnown;
  string healthAt;

  /// 物理连接队列；relay 子会话与 master 共享。
  AgentQueue queue;
  /// 子会话的 master；master/直连为 null。
  AgentSession master;
  /// relay 上行的逻辑 agent；直连为空。
  string agent;
  bool relayMaster;
  /// 组网分组与当前角色（candidate/master/follower）。
  string groupName = "default_group";
  string role = "candidate";

  /// 请求号 → 等待者。请求发起后由 socket 循环在 `result` 到达时唤醒。
  private PendingRequest[string] pending;
  private TaskMutex pendingLock;
  private TaskCondition pendingChanged;

  this(string project, string projectId = "", string ip = "", string groupName = "default_group",
      AgentQueue sharedQueue = null) {
    this.project = project;
    this.projectId = projectId;
    this.ip = ip;
    this.groupName = groupName;
    this.queue = sharedQueue is null ? new AgentQueue : sharedQueue;
    this.connectedAt = channel.now();
    this.startedAt = MonoTime.currTime;
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
    case "report:health":
      health = parseHealth(message.body, healthKnown);
      if (healthKnown)
        healthAt = channel.now();
      break;
    case "pong":
      break;
    case "result":
      complete(message.id, message.body);
      break;
    default:
      logWarn("%s: ignore %s %s", project, message.isRequest ? "request" : "notice", message.typ);
      break;
    }
  }

  /// 投递一条出站消息。实际发送由持有 socket 的循环完成。
  bool offer(string message) {
    return queue.offer(message);
  }

  /// agent 是否在 `hello.supports` 里声明支持某个原语。
  bool supportsPrimitive(string primitive) const {
    return supports.canFind(primitive);
  }

  /// 取走当前积压；返回后队列为空。
  string[] takeOutbound() {
    return queue.take();
  }

  @property bool superseded() const {
    return queue.superseded;
  }

  @property short closeCode() const {
    return queue.closeCode;
  }

  @property string closeReason() const {
    return queue.closeReason;
  }

  /// 被同一 project 的新连接取代。
  void supersede() {
    queue.superseded = true;
    queue.closeCode = 1008;
    queue.closeReason = "superseded";
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

    if (offer(channel.render(typ, id, body, agent)))
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
    item["project"] = Json(project);
    item["projectId"] = Json(projectId);
    item["ip"] = Json(ip);
    item["group"] = Json(groupName);
    item["role"] = Json(role);
    item["master"] = Json(master is null ? "" : master.ip);
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
    item["healthAt"] = Json(healthAt);
    item["health"] = healthJson(effectiveHealth);
    return item;
  }

  /// 轻量在线列表用的摘要：不携带 OS 与 webapps，避免每 30 秒重复搬运大对象。
  Json summary() {
    auto item = Json.emptyObject;
    item["project"] = Json(project);
    item["projectId"] = Json(projectId);
    item["ip"] = Json(ip);
    item["group"] = Json(groupName);
    item["role"] = Json(role);
    item["master"] = Json(master is null ? "" : master.ip);
    item["host"] = Json(host);
    item["basctl"] = Json(basctlVersion);
    item["bas"] = Json(basVersion);
    auto caps = appender!(Json[])();
    foreach (capability; supports)
      caps.put(Json(capability));
    item["supports"] = Json(caps.data);
    item["connectedAt"] = Json(connectedAt);
    item["lastSeenAt"] = Json(lastSeenAt);
    item["healthAt"] = Json(healthAt);

    auto servers = effectiveHealth;
    long running;
    long stopped;
    foreach (sample; servers) {
      if (sample.state == "running")
        running++;
      else
        stopped++;
    }
    item["running"] = Json(running);
    item["stopped"] = Json(stopped);
    item["health"] = healthJson(servers);
    return item;
  }

  /// 新 agent 用 `report:health`；老 agent 没有该原语时从 `report:bas` 推导，保持向后兼容。
  AgentSample[] effectiveHealth() {
    if (healthKnown)
      return health;
    AgentSample[] result;
    if (basReport.type != Json.Type.object)
      return result;
    bool[string] runningById;
    string[] ids;
    auto running = basReport["instances"];
    if (running.type == Json.Type.array) {
      foreach (ref item; running) {
        auto id = channel.textOf(item, "id");
        if (id.length == 0 || id.length > MaxServerIdBytes)
          continue;
        if ((id in runningById) is null)
          ids ~= id;
        runningById[id] = true;
      }
    }
    auto declared = basReport["declared"];
    if (declared.type == Json.Type.array) {
      foreach (ref item; declared) {
        auto id = channel.textOf(item, "id");
        if (id.length == 0 || id.length > MaxServerIdBytes)
          continue;
        if ((id in runningById) is null) {
          ids ~= id;
          runningById[id] = false;
        }
      }
    }
    ids.sort;
    foreach (id; ids)
      result ~= AgentSample(id, runningById[id] ? "running" : "stopped");
    return result;
  }

  private void hello(Json body) {
    host = boundedText(body, "host", MaxHelloHostBytes);
    basctlVersion = boundedText(body, "basctl", MaxHelloVersionBytes);
    basVersion = boundedText(body, "bas", MaxHelloVersionBytes);
    basHome = boundedText(body, "basHome", MaxHelloHomeBytes);

    bool[string] seen;
    string[] declared;
    auto value = body["supports"];
    if (value.type == Json.Type.array) {
      foreach (ref item; value) {
        if (item.type != Json.Type.string)
          continue;
        auto capability = item.get!string.strip;
        if (capability.length > 0 && capability.length <= MaxCapabilityBytes
            && (channel.AgentPrimitives.canFind(capability)
                || channel.HubPrimitives.canFind(capability)) && capability !in seen) {
          seen[capability] = true;
          declared ~= capability;
        }
      }
    }
    supports = declared.sort.release;
  }

  /// 只接受有限数量、有限长度的 server id 与三种状态；坏数组清空旧快照，不保留半份数据。
  private AgentSample[] parseHealth(Json body, out bool known) {
    known = false;
    if (body.type != Json.Type.object)
      return null;
    auto value = body["servers"];
    if (value.type != Json.Type.array)
      return null;
    known = true;
    AgentSample[] result;
    bool[string] seen;
    foreach (ref item; value) {
      if (result.length >= MaxHealthServers)
        break;
      if (item.type != Json.Type.object)
        continue;
      auto id = channel.textOf(item, "id").strip;
      auto state = channel.textOf(item, "state").strip;
      if (id.length == 0 || id.length > MaxServerIdBytes)
        continue;
      if (state != "running" && state != "stopped" && state != "error")
        continue;
      if ((id in seen) !is null)
        continue;
      seen[id] = true;
      result ~= AgentSample(id, state);
    }
    result.sort!((left, right) => left.id < right.id);
    return result;
  }

  private static Json healthJson(const(AgentSample)[] samples) {
    Json[] items;
    foreach (sample; samples)
      items ~= Json(["id": Json(sample.id), "state": Json(sample.state)]);
    return Json(items);
  }

  private string boundedText(Json body, string key, size_t maxBytes) {
    auto value = channel.textOf(body, key);
    return value.length <= maxBytes ? value : "";
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
      auto data = body["data"];
      return AgentReply.failure(RequestOutcome.failed, error.length > 0 ? error : "agent request failed",
          data.type == Json.Type.object ? data : Json(null));
    }
    auto data = body["data"];
    return AgentReply.success(data.type == Json.Type.undefined ? Json.emptyObject : data);
  }
}

/// 同一 `project@ip` 在 60 秒内又一次被新连接顶掉：说明这台 agent 在反复重连。
private enum SupersedeChurnSeconds = 60;
/// 重连告警的间隔：同一 `project@ip` 每分钟最多一条，避免 10 秒一轮的重连把日志刷满。
private enum SupersedeWarnSeconds = 60;

/// 一个 (project, group) 的 master 租约。
struct GroupMaster {
  string ip;
  long term;
  MonoTime expires;
}

/// 在线 agent 登记册：一个 project 可以有多台机器，按上报的 `ip` 区分；
/// 同一个 `project@ip` 只保留最新一条连接（旧连接被顶掉），不同 IP 的连接互不影响。
final class AgentRegistry {
  /// project → (server ip → session)。
  private AgentSession[string][string] sessions;
  private AgentHistoryStore historyStore;
  /// `project@ip` → 上次被新连接顶掉的时刻，用于识别同一台机器反复重连。
  private MonoTime[string] lastSupersedeAt;
  /// `project@ip` → 上次重连告警的时刻，用于限流。
  private MonoTime[string] lastSupersedeWarnAt;
  /// `project\0group` → master 租约。
  private GroupMaster[string] groupMasters;

  this(AgentHistoryStore historyStore = null) {
    this.historyStore = historyStore;
  }

  /// 登记新连接；同一 `project@ip` 的旧连接被标记为 `superseded`，其它 IP 的连接不受影响。
  AgentSession attach(string project, string projectId = "", string ip = "") {
    auto session = new AgentSession(project, projectId, ip);
    auto byIp = project in sessions;
    if (byIp is null) {
      sessions[project] = [ip: session];
      return session;
    }
    if (auto previous = ip in *byIp) {
      (*previous).supersede();
      noteSupersede(project, ip, *previous);
    }
    (*byIp)[ip] = session;
    return session;
  }

  /// 登记一条 relay master 的物理连接。
  AgentSession attachRelay(string project, string projectId, string ip, string groupName = "default_group") {
    auto session = new AgentSession(project, projectId, ip, groupName);
    session.relayMaster = true;
    auto byIp = project in sessions;
    if (byIp is null) {
      sessions[project] = [ip: session];
    } else {
      if (auto previous = ip in *byIp) {
        (*previous).supersede();
        noteSupersede(project, ip, *previous);
        // 同一 master 重连：它名下的逻辑子会话也必须一起换掉，不能留下旧队列的僵尸。
        string[] stale;
        foreach (childIp, child; *byIp)
          if (child.master is *previous) {
            child.disconnect();
            stale ~= childIp;
          }
        foreach (childIp; stale)
          (*byIp).remove(childIp);
      }
      (*byIp)[ip] = session;
    }
    return session;
  }

  /// 在 master 物理连接上登记一个逻辑 follower；同一 project@ip 的旧逻辑会话被替换。
  AgentSession attachRelayChild(AgentSession master, string agentIp) {
    auto byIp = master.project in sessions;
    if (byIp is null)
      return null;
    if (auto previous = agentIp in *byIp) {
      (*previous).disconnect();
      (*byIp).remove(agentIp);
    }
    auto child = new AgentSession(master.project, master.projectId, agentIp, master.groupName, master.queue);
    child.master = master;
    child.agent = agentIp;
    child.role = "follower";
    child.groupName = master.groupName;
    (*byIp)[agentIp] = child;
    return child;
  }

  /**
   * 记录一次「同一台机器的新连接顶掉旧连接」。
   *
   * 正常重连时旧连接往往还没超时，这一次顶替不值得告警；只有同一 `project@ip` 在
   * {@link SupersedeChurnSeconds} 内被反复顶掉，才说明这台 agent 在反复重连（网络抖动、
   * 进程崩溃重启等）。告警带旧连接的 host 与在线时长，按 `project@ip` 每分钟最多一条。
   */
  private void noteSupersede(string project, string ip, AgentSession previous) {
    auto key = project ~ "@" ~ ip;
    auto now = MonoTime.currTime;
    bool churn;
    if (auto last = key in lastSupersedeAt)
      churn = now - *last < seconds(SupersedeChurnSeconds);
    lastSupersedeAt[key] = now;
    if (!churn)
      return;
    if (auto warned = key in lastSupersedeWarnAt) {
      if (now - *warned < seconds(SupersedeWarnSeconds))
        return;
    }
    lastSupersedeWarnAt[key] = now;
    logWarn("%s: agent reconnected again within %d s (host=%s, online %d s); "
        ~ "check the agent or the network", key, SupersedeChurnSeconds,
        previous.host.length ? previous.host : "unknown",
        (now - previous.startedAt).total!"seconds");
  }

  /// 摘除一条连接；只摘自己那条，旧连接迟到的关闭不能把新连接挤掉。
  void detach(string project, string ip, AgentSession session) nothrow {
    if (session.role == "master") {
      auto key = project ~ "\0" ~ session.groupName;
      if (auto found = key in groupMasters)
        if ((*found).ip == session.ip)
          groupMasters.remove(key);
    }
    if (session.relayMaster) {
      if (auto byIp = project in sessions) {
        string[] children;
        foreach (childIp, child; *byIp)
          if (child.master is session) {
            child.disconnect();
            children ~= childIp;
          }
        foreach (childIp; children)
          (*byIp).remove(childIp);
        if ((*byIp).length == 0)
          sessions.remove(project);
      }
      session.queue.superseded = true;
      session.disconnect();
      return;
    }
    if (auto byIp = project in sessions) {
      if (auto found = ip in *byIp) {
        if (*found is session) {
          (*byIp).remove(ip);
          if ((*byIp).length == 0)
            sessions.remove(project);
        }
      }
    }
    session.disconnect();
  }

  /// relay follower 断开：只摘除该 master 名下的逻辑子会话。
  void detachRelayChild(AgentSession master, string ip) nothrow {
    if (auto byIp = master.project in sessions) {
      if (auto found = ip in *byIp) {
        if ((*found).master is master) {
          (*found).disconnect();
          (*byIp).remove(ip);
        }
      }
    }
  }

  /// 从 master 降级时摘掉其名下的逻辑 follower。
  void dropChildren(AgentSession master) nothrow {
    if (auto byIp = master.project in sessions) {
      string[] children;
      foreach (childIp, child; *byIp)
        if (child.master is master)
          children ~= childIp;
      foreach (childIp; children) {
        (*byIp)[childIp].disconnect();
        (*byIp).remove(childIp);
      }
    }
  }

  /// 主动作废该 project 的全部连接（例如重置 Project.key 之后）。
  void supersede(string project) {
    if (auto byIp = project in sessions)
      foreach (_, session; *byIp)
        session.supersede();
  }

  /// 按 `project@ip` 找连接。
  AgentSession find(string project, string ip) {
    if (auto byIp = project in sessions) {
      if (auto found = ip in *byIp)
        return *found;
    }
    return null;
  }

  /// 该 project 下唯一的连接；0 条或多条时返回 null（调用方按 ip 指定）。
  AgentSession find(string project) {
    auto list = sessionsOf(project);
    return list.length == 1 ? list[0] : null;
  }

  /// 该 project 下的全部连接，按 ip 排序。
  AgentSession[] sessionsOf(string project) {
    AgentSession[] list;
    if (auto byIp = project in sessions)
      foreach (_, session; *byIp)
        list ~= session;
    list.sort!((left, right) => left.ip < right.ip);
    return list;
  }

  /// 在线连接，先按 project、再按 ip 排序。
  AgentSession[] online() {
    AgentSession[] list;
    foreach (projectKey, byIp; sessions)
      foreach (sessionIp, session; byIp)
        list ~= session;
    list.sort!((left, right) => left.project == right.project
        ? left.ip < right.ip : left.project < right.project);
    return list;
  }

  /// `GET /api/bashub/monitor/agents/status` 的数组。
  Json status() {
    Json[] items;
    foreach (session; online())
      items ~= session.status;
    return Json(items);
  }

  /// `GET /api/bashub/monitor/agents/summary` 的数组；只含在线状态与实例摘要。
  Json summary() {
    Json[] items;
    foreach (session; online())
      items ~= session.summary;
    return Json(items);
  }

  /// 写入一条轻量健康快照；数据库故障不能影响 agent 通道本身。
  void recordHealth(string projectId, const(AgentSample)[] samples) nothrow {
    if (historyStore is null || projectId.length == 0 || samples.length == 0)
      return;
    try
      historyStore.record(projectId, samples);
    catch (Exception e)
      logWarn("%s: record health history failed: %s", projectId, e.msg);
  }

  /**
   * 合并该 project 下所有在线 agent 的最新 health 后写一条采样。
   *
   * 同一 project 的多台 agent 各报各的 server；入库前按 server id 合并（先到先得，
   * 正常情况下 id 跨机器唯一），表里就是「这个 project 此刻所有 server 的状态」。
   */
  void recordProjectHealth(string project, string projectId) nothrow {
    if (historyStore is null || projectId.length == 0)
      return;
    try {
      AgentSample[] merged;
      bool[string] seen;
      foreach (session; sessionsOf(project)) {
        foreach (sample; session.effectiveHealth) {
          if ((sample.id in seen) !is null)
            continue;
          seen[sample.id] = true;
          merged ~= sample;
        }
      }
      if (merged.length > 0)
        historyStore.record(projectId, merged);
    } catch (Exception e) {
      logWarn("%s: record health history failed: %s", projectId, e.msg);
    }
  }

  /// 是否有可用的历史存储；路由据此区分「没有历史」与「查询失败」。
  bool hasHistory() const {
    return historyStore !is null;
  }

  /// 查询历史；调用方负责把异常转换成 HTTP 错误。
  Json history(string projectId, string projectName, int daysCount) {
    if (historyStore is null)
      throw new Exception("agent history is not configured");
    return historyStore.query(projectId, projectName, daysCount);
  }

  /// 组内登记/推荐 master；已有有效租约时返回当前 master。
  GroupMaster recommendMaster(string project, string group, string candidate, Duration ttl) {
    auto key = project ~ "\0" ~ group;
    auto now = MonoTime.currTime;
    if (auto found = key in groupMasters) {
      if ((*found).expires > now && (*found).ip.length > 0)
        return *found;
    }
    auto found = find(project, candidate);
    if (found is null || found.groupName != group || found.role == "follower")
      return GroupMaster.init;
    long term = 1;
    if (auto old = key in groupMasters)
      term = (*old).term + 1;
    GroupMaster lease = GroupMaster(candidate, term, now + ttl);
    groupMasters[key] = lease;
    found.role = "master";
    return lease;
  }

  GroupMaster masterOf(string project, string group) {
    auto key = project ~ "\0" ~ group;
    if (auto found = key in groupMasters) {
      if ((*found).expires > MonoTime.currTime)
        return *found;
    }
    return GroupMaster.init;
  }

  void refreshMaster(string project, string group, string ip, Duration ttl) {
    auto key = project ~ "\0" ~ group;
    if (auto found = key in groupMasters) {
      if ((*found).ip == ip)
        (*found).expires = MonoTime.currTime + ttl;
    }
  }

  AgentSession[] sessionsOfGroup(string project, string group) {
    AgentSession[] list;
    if (auto byIp = project in sessions)
      foreach (_, session; *byIp)
        if (session.groupName == group)
          list ~= session;
    return list;
  }

  /// 请某个在线 agent 立即上报；不在线返回 false。
  bool reportNow(string project, string ip = "") {
    auto session = resolve(project, ip);
    if (session is null || !session.supportsPrimitive("report:now"))
      return false;
    return session.offer(channel.reportNow(session.agent));
  }

  /// 下发 `log:read` 并等待 agent 的 `result`。
  AgentReply logRead(string project, string instance, long from, long to,
      Duration timeout = 5.seconds, long tail = 0, string ip = "") {
    auto session = resolve(project, ip);
    if (session is null)
      return AgentReply.failure(RequestOutcome.offline, "agent offline: " ~ project);
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

  /// 下发 `agent:log` 并等待 agent 的 `result`；用于查 agent 自身日志。
  AgentReply agentLog(string project, long from, long to,
      Duration timeout = 5.seconds, long tail = 0, string ip = "") {
    auto session = resolve(project, ip);
    if (session is null)
      return AgentReply.failure(RequestOutcome.offline, "agent offline: " ~ project);
    if (!session.supportsPrimitive("agent:log"))
      return AgentReply.failure(RequestOutcome.failed, "unsupported:agent:log");
    auto body = Json.emptyObject;
    body["from"] = Json(from);
    body["to"] = Json(to);
    if (tail > 0)
      body["tail"] = Json(tail);
    return session.request("agent:log", body, timeout);
  }

  /// 下发 `service:start|stop|restart` 并等待 agent 的 `result`。
  AgentReply service(string project, string action, string instance,
      Duration timeout = 120.seconds, string ip = "") {
    if (action != "start" && action != "stop" && action != "restart")
      return AgentReply.failure(RequestOutcome.failed, "bad-request");
    auto session = resolve(project, ip);
    if (session is null)
      return AgentReply.failure(RequestOutcome.offline, "agent offline: " ~ project);
    auto primitive = "service:" ~ action;
    if (!session.supportsPrimitive(primitive))
      return AgentReply.failure(RequestOutcome.failed, "unsupported:" ~ primitive);
    auto body = Json.emptyObject;
    body["instance"] = Json(instance);
    return session.request(primitive, body, timeout);
  }

  /// 动作的目标连接：给了 ip 就精确找；没给时只有唯一连接才可用。
  private AgentSession resolve(string project, string ip) {
    if (ip.length > 0)
      return find(project, ip);
    return find(project);
  }

  /// 给所有在线连接投递一条保活；没有连接时什么也不做。
  void pingAll() {
    foreach (session; online())
      session.offer(channel.ping(session.agent));
  }
}
