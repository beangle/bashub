/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.security.sessioncache;
/// 会话缓存 + 访问心跳（scala `session/cache/CacheSessionRepo` + `cache/AccessReporter` 的 D 版）。
/// 缓存只有**进程内存**一层：scala 侧那层「CacheManager 可换 Caffeine/Redis」的抽象在预演阶段裁掉
/// （见 README），所以这里的 `CacheSessionRepo` 用起来就是一份内存仓库，`fetch`/`flush` 交给子类接后端。

import beangle.security.session;

import core.time : seconds;

import std.random : uniform;

import vibe.core.core : Timer, setTimer;
import vibe.core.sync : TaskMutex;

class CacheSessionRepo : SessionRepo {
  private Session[string] sessions;
  /// 攒着待上报的会话：sid → 最近一次被访问的时刻
  private long[string] heartbeats;
  private long lastReportAt;
  private TaskMutex lock;
  private Timer heartbeatTimer;
  private bool heartbeatOn;

  /// 访问更新延迟（秒）：访问太频繁时不必每次都告诉后端，攒够这个间隔再报一次。
  /// scala 取 20~60 秒的随机数（`UpdateDelayGenerator(20, 60)`），这里同口径。
  int accessDelaySeconds;
  /// 心跳间隔（秒）；scala 默认 3 分钟。
  int flushIntervalSeconds = 3 * 60;

  this() {
    lock = new TaskMutex();
    lastReportAt = nowSeconds();
    // 在构造函数里摇号：字段初始化表达式是编译期上下文，读不了全局随机数
    accessDelaySeconds = 20 + uniform(0, 41);
  }

  Session get(string sessionId, bool refresh = false) {
    if (sessionId.length == 0)
      return null; // scala 判的是 null；cookie 取不到给的是空串，一并挡掉
    if (!refresh) {
      synchronized (lock) {
        if (auto cached = sessionId in sessions)
          return *cached;
      }
    }
    auto found = fetch(sessionId);
    if (found is null)
      return null;
    synchronized (lock) {
      if (auto cached = sessionId in sessions)
        return *cached; // putIfAbsent：这一小会儿别人放进去了，用别人那份
      sessions[sessionId] = found;
    }
    return found;
  }

  Session access(string sessionId, long accessAt) {
    auto s = get(sessionId);
    if (s is null)
      return null;
    auto elapse = s.access(accessAt);
    if (elapse > accessDelaySeconds) {
      synchronized (lock)
        heartbeats[s.id] = accessAt;
      return s;
    }
    if (elapse == -1) {
      // 本地已判定过期：清缓存，并请后端把它也删掉
      evict(s.id);
      expire(s.id);
      return null;
    }
    return s;
  }

  void evict(string sessionId) {
    synchronized (lock) {
      sessions.remove(sessionId);
      heartbeats.remove(sessionId); // scala 靠上报时发现缓存里没有；这里当场摘掉，结果一样
    }
  }

  /// 作废会话：基类只能清本地缓存，能通知后端的（见 `cas.d`）覆写它。
  void expire(string sessionId) {
    evict(sessionId);
  }

  /// 按账号取会话：基类没有后端，交给子类。
  Session[] findByPrincipal(string principal) {
    return null;
  }

  /** 回源取会话（缓存未命中时调用）；取不到返回 null。
   *
   * 基类默认「没有后端」，所以这个类自己就是一份纯内存仓库（演示与测试用）。
   */
  protected Session fetch(string sessionId) {
    return null;
  }

  /// 把会话的访问时间上报给后端；返回 false 表示后端已经不认这个会话了。基类恒为 true。
  protected bool flush(Session session) {
    return true;
  }

  /** 心跳上报（scala `AccessReporter.run`）：把攒下的 sid 逐个 flush 给后端，
   * 后端已经不认（或这次访问真的推进了 lastAccessAt 而 flush 失败）的按过期处理，清掉本地缓存。
   */
  void reportHeartbeats() {
    long last;
    string[] pending;
    synchronized (lock) {
      last = lastReportAt;
      lastReportAt = nowSeconds();
      foreach (sessionId, _; heartbeats)
        pending ~= sessionId;
    }
    foreach (sessionId; pending) {
      Session s;
      synchronized (lock) {
        if (auto cached = sessionId in sessions)
          s = *cached;
      }
      if (s is null || (s.lastAccessAt > last && !flush(s)))
        evict(sessionId);
    }
  }

  /// 起心跳定时器；`setTimer` 在事件循环起来之前调也没问题（会排队等循环）。
  void startHeartbeat() {
    stopHeartbeat();
    heartbeatTimer = setTimer(flushIntervalSeconds.seconds, &reportHeartbeats, true);
    heartbeatOn = true;
  }

  void stopHeartbeat() {
    if (heartbeatOn) {
      heartbeatTimer.stop();
      heartbeatOn = false;
    }
  }
}
