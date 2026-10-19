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

import bashub.agent.channel : Envelope, parse, ping, reportNow;
import bashub.agent.registry : AgentRegistry, AgentSession;

import vibe.core.log : logInfo, logWarn;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.websockets : WebSocket, handleWebSockets;

import core.time : Duration, MonoTime, msecs, seconds;

/// 保活节拍：agent 沉默 90s 就重连，30s 一次 `ping` 留足余量。
enum HeartbeatInterval = 30.seconds;

/// 出站队列与 supersede 标记的检查间隔；命令延迟上限也就是这个值。
private enum PollInterval = 250.msecs;

/// 完成 HTTP → WebSocket 升级并跑连接循环。调用方必须已经验证过 Bearer。
void serveAgentSocket(AgentRegistry registry, string profile, HTTPServerRequest req,
    HTTPServerResponse res, Duration heartbeatInterval = HeartbeatInterval) {
  auto name = profile.idup;
  auto handler = handleWebSockets((scope WebSocket socket) nothrow {
      runAgentLoop(registry, name, socket, heartbeatInterval);
  });
  handler(req, res);
}

/// 一条连接的生命周期：登记、读消息、发队列、按期 ping、离开时摘除。
void runAgentLoop(AgentRegistry registry, string profile, scope WebSocket socket,
    Duration heartbeatInterval = HeartbeatInterval) nothrow {
  AgentSession session;
  scope (exit) {
    if (session !is null)
      registry.detach(profile, session);
    closeQuietly(profile, socket);
  }

  try {
    session = registry.attach(profile);
    logInfo("%s: agent connected", profile);

    auto lastPing = MonoTime.currTime;
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

      if (!socket.waitForData(PollInterval))
        continue;

      Envelope message;
      if (parse(socket.receiveText(), message))
        session.accept(message);
      else
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
