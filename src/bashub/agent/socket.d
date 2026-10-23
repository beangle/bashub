/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.agent.socket;
/// WebSocket 的 hub 端循环。鉴权在升级前完成，这里只处理已认证的连接。
///
/// `scope WebSocket` 只活在这个回调里：登记册保存快照与出站队列，循环负责把队列发给
/// socket，并抄下 agent 发来的现状。外部请求（如 `report:now`）因此不必持有 socket。

import bashub.agent.channel : Envelope, parse, ping, reportHealth, reportNow;
import bashub.agent.registry : AgentRegistry, AgentSession;

import vibe.core.log : logDebug, logWarn;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.websockets : WebSocket, handleWebSockets;

import core.time : Duration, MonoTime, msecs, seconds;
import std.datetime : Clock, SysTime;

/// 保活节拍：agent 沉默 150s 就重连，60s 一次 `ping` 留一次丢失的余量。
enum HeartbeatInterval = 60.seconds;

/// 出站队列与 supersede 标记的检查间隔；命令延迟上限也就是这个值。
private enum PollInterval = 250.msecs;

/** bashub 对单条连接的轻量健康采样计划；0 秒表示关闭。 */
struct HealthSchedule {
  uint intervalSeconds;
  ushort startMinute = 7 * 60;
  ushort endMinute = 22 * 60;

  bool enabled() const {
    return intervalSeconds > 0;
  }

  /** bashub 主机时区的采样窗口；start 含、end 不含，支持跨午夜。 */
  bool windowContains(SysTime now) const {
    auto local = now.toLocalTime;
    auto minute = cast(uint) local.hour * 60 + local.minute;
    if (startMinute < endMinute)
      return minute >= startMinute && minute < endMinute;
    return minute >= startMinute || minute < endMinute;
  }

  /** 是否已到下一次下发时间；到达窗口边界时立即补一次，不等待一个完整周期。 */
  bool due(SysTime now, Duration sinceLast) const {
    return enabled && windowContains(now) && sinceLast >= seconds(cast(long) intervalSeconds);
  }
}

/// 完成 HTTP → WebSocket 升级并跑连接循环。调用方必须已经验证过 Bearer 与 `ip` 头。
void serveAgentSocket(AgentRegistry registry, string profile, string profileId, string ip,
    HTTPServerRequest req, HTTPServerResponse res, HealthSchedule health = HealthSchedule.init,
    Duration heartbeatInterval = HeartbeatInterval) {
  auto name = profile.idup;
  auto id = profileId.idup;
  auto agentIp = ip.idup;
  auto handler = handleWebSockets((scope WebSocket socket) nothrow {
      runAgentLoop(registry, name, id, agentIp, socket, health, heartbeatInterval);
  });
  handler(req, res);
}

/// 一条连接的生命周期：登记、读消息、发队列、按期 ping、离开时摘除。
void runAgentLoop(AgentRegistry registry, string profile, string profileId, string ip,
    scope WebSocket socket, HealthSchedule health = HealthSchedule.init,
    Duration heartbeatInterval = HeartbeatInterval) nothrow {
  AgentSession session;
  scope (exit) {
    if (session !is null)
      registry.detach(profile, ip, session);
    closeQuietly(profile, socket);
  }

  try {
    session = registry.attach(profile, profileId, ip);
    // 每次重连都会走到这里；稳定连接只应出现一次，周期重复说明 agent 在反复重连。
    // 属于排错信息，放 debug 级（log-level=debug 时才出现），默认 info 不刷日志。
    logDebug("%s@%s: agent connected", profile, ip);

    auto lastPing = MonoTime.currTime;
    auto lastHealth = lastPing;
    while (socket.connected) {
      if (session.superseded) {
        socket.close(session.closeCode, session.closeReason);
        return;
      }

      foreach (message; session.takeOutbound()) {
        if (!socket.connected)
          break;
        socket.send(message);
      }

      auto current = MonoTime.currTime;
      if (heartbeatInterval > Duration.zero && current - lastPing >= heartbeatInterval) {
        session.offer(ping());
        lastPing = current;
      }
      if (health.due(Clock.currTime, current - lastHealth)) {
        if (session.supportsPrimitive("report:health"))
          session.offer(reportHealth());
        lastHealth = current;
      }

      if (!socket.waitForData(PollInterval))
        continue;

      Envelope message;
      if (parse(socket.receiveText(), message)) {
        session.accept(message);
        if (message.typ == "report:health" && session.healthKnown)
          registry.recordProfileHealth(session.profile, session.profileId);
      } else
        logWarn("%s: unreadable message dropped", profile);
    }
  } catch (Exception e) {
    logWarn("%s: agent channel error: %s", profile, e.msg);
  }
}

private void closeQuietly(string profile, scope WebSocket socket) nothrow {
  try {
    if (socket.connected)
      socket.close();
  } catch (Exception e) {
    logWarn("%s: close agent channel failed: %s", profile, e.msg);
  }
}
