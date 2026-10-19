/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.security.session_test;
/// 会话语义：模型（tti/过期/时钟回拨）与「内存缓存 + 心跳」的取舍。
/// 用假后端验证，不碰网络；真发 HTTP 的那部分在 `cas_test.d`。

import beangle.security.session;
import beangle.security.sessioncache : CacheSessionRepo;

import core.time : msecs;

import vibe.core.core : exitEventLoop, runEventLoop, setTimer;

/// 记账用的假后端：只数调用次数，不连网。
class StubRepo : CacheSessionRepo {
  int fetchCount;
  int flushCount;
  long lastFlushAt;
  int expireCount;
  bool flushOk = true;
  Session[] known;

  override protected Session fetch(string sessionId) {
    fetchCount++;
    foreach (s; known) {
      if (s.id == sessionId)
        return s;
    }
    return null;
  }

  override protected bool flush(Session session) {
    flushCount++;
    lastFlushAt = session.lastAccessAt;
    return flushOk;
  }

  override void expire(string sessionId) {
    expireCount++;
    super.expire(sessionId);
  }
}

private Session aSession(string id, int ttiSeconds = 600) {
  auto principal = new DefaultAccount("demo", "演示用户");
  return new Session(id, principal, nowSeconds(), new Agent("curl", "127.0.0.1", "Linux"), ttiSeconds);
}

@("Session.access 与 scala DefaultSession 同口径")
unittest {
  auto s = new Session("s", new DefaultAccount("demo", "演示用户"), 1000, new Agent("a", "b", "c"), 60);
  assert(s.lastAccessAt == 1000); // 构造时 lastAccessAt = loginAt
  assert(s.access(1000) == 0);
  assert(s.access(1030) == 30);
  assert(s.lastAccessAt == 1030);
  assert(s.access(1020) == 0); // 时钟回拨：按 0 计，且不把 lastAccessAt 往回拨
  assert(s.lastAccessAt == 1030);
  assert(!s.expiredAt(1090)); // 边界：正好到 tti 还不算过期
  assert(s.expiredAt(1091));
  assert(s.access(2000) == -1);
  assert(s.lastAccessAt == 1030); // 过期时不动 lastAccessAt
}

@("get 命中缓存就不再回源，refresh 才回源")
unittest {
  auto repo = new StubRepo();
  repo.known = [aSession("a")];
  assert(repo.get("a").id == "a");
  assert(repo.fetchCount == 1);
  assert(repo.get("a").id == "a");
  assert(repo.fetchCount == 1);
  assert(repo.get("a", true).id == "a");
  assert(repo.fetchCount == 2);
  assert(repo.get(null) is null);
  assert(repo.get("") is null);
  assert(repo.get("nope") is null); // 后端没有：不回填缓存，下次还得问
}

@("access：延迟内只更本地、超过延迟记心跳、过期则作废")
unittest {
  auto repo = new StubRepo();
  repo.accessDelaySeconds = 20;
  auto base = nowSeconds();
  auto s = aSession("a");
  s.lastAccessAt = base;
  repo.known = [s];

  assert(repo.access("a", base + 5) is s);
  assert(s.lastAccessAt == base + 5);
  assert(repo.flushCount == 0); // 太近，不值得发心跳

  assert(repo.access("a", base + 50) is s);
  assert(repo.flushCount == 0); // 攒着，等心跳线程
  repo.reportHeartbeats();
  assert(repo.flushCount == 1);
  assert(repo.lastFlushAt == base + 50);

  assert(repo.access("missing", base + 50) is null); // 后端也没有
}

@("access 判定过期：清缓存并让后端作废")
unittest {
  auto repo = new StubRepo();
  auto s = aSession("a", 60);
  repo.known = [s];
  assert(repo.access("a", s.lastAccessAt + 61) is null);
  assert(repo.expireCount == 1);
  assert(repo.get("a") !is null); // 缓存已经清了，这次是回源取回来的
  assert(repo.fetchCount == 2);
}

@("心跳上报失败（后端已无此会话）就把它从缓存摘掉")
unittest {
  auto repo = new StubRepo();
  repo.accessDelaySeconds = 20;
  auto base = nowSeconds();
  auto s = aSession("a");
  s.lastAccessAt = base;
  repo.known = [s];
  repo.flushOk = false;

  assert(repo.access("a", base + 50) is s);
  repo.reportHeartbeats();
  assert(repo.flushCount == 1);
  assert(repo.access("a", base + 60) !is null); // 缓存已被摘掉：这次是回源
  assert(repo.fetchCount == 2);
}

@("心跳定时器按间隔触发")
unittest {
  auto repo = new StubRepo();
  repo.flushIntervalSeconds = 1;
  auto base = nowSeconds();
  auto s = aSession("a");
  repo.known = [s];
  assert(repo.access("a", base + 300) is s); // 间隔 300 > 访问延迟：记下心跳

  repo.startHeartbeat();
  setTimer(1200.msecs, { exitEventLoop(); }, false); // 到点收摊
  runEventLoop();
  repo.stopHeartbeat();
  assert(repo.flushCount >= 1);
}
