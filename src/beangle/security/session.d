/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.security.session;
/// 会话模型与仓库契约（scala `org.beangle.security.session` 的对应物）。
/// 时间一律用 epoch 秒：`/session/{id}/access?time=` 就是这个单位，报文里的 ISO 文本
/// 在解码时已经换算过来；换成 `Instant` 只是多一层来回换算。

import std.datetime.systime : Clock;
import std.datetime.timezone : UTC;

/// 账户状态位（scala `DefaultAccount.StatusMask`）。
enum AccountStatus : int {
  locked = 1,
  disabled = 2,
  accountExpired = 4,
  credentialExpired = 8,
  credentialReadOnly = 16,
}

/// 账户上的一个角色/权限档位（scala `org.beangle.security.authc.Profile`）。
class Profile {
  long id;
  string name;
  string[string] properties;
}

/** 登录账户。scala 侧 `remoteToken` 是 `Option[String]`，这里用空串表示 None（报文的缺省字段）。 */
class DefaultAccount {
  string name;
  string description;
  string remoteToken;
  int status;
  string[] authorities;
  string[] permissions;
  Profile[] profiles;
  string[string] details;
  int categoryId;
  /// 现网 CAS 的 JSON 会话不包含这个字段，因此读到的值恒为 false；普通授权仍按
  /// `authorities` / `permissions` 判定。
  bool isRoot;

  this() {
  }

  this(string name, string description) {
    this.name = name;
    this.description = description;
  }

  private bool masked(int mask) const @safe pure nothrow {
    return (status & mask) != 0;
  }

  bool accountLocked() const @safe pure nothrow {
    return masked(AccountStatus.locked);
  }

  bool disabled() const @safe pure nothrow {
    return masked(AccountStatus.disabled);
  }

  bool accountExpired() const @safe pure nothrow {
    return masked(AccountStatus.accountExpired);
  }

  bool credentialExpired() const @safe pure nothrow {
    return masked(AccountStatus.credentialExpired);
  }

  bool credentialReadOnly() const @safe pure nothrow {
    return masked(AccountStatus.credentialReadOnly);
  }

  bool isRemote() const @safe pure nothrow {
    return remoteToken.length > 0;
  }
}

/// 登录终端（scala `Session.Agent`）。
class Agent {
  string name;
  string ip;
  string os;

  this() {
  }

  this(string name, string ip, string os) {
    this.name = name;
    this.ip = ip;
    this.os = os;
  }
}

/** 一次登录会话（scala `DefaultSession`）。 */
class Session {
  string id;
  DefaultAccount principal;
  long loginAt;
  long lastAccessAt;
  Agent agent;
  int ttiSeconds;

  this() {
    principal = new DefaultAccount();
    agent = new Agent();
  }

  this(string id, DefaultAccount principal, long loginAt, Agent agent, int ttiSeconds) {
    this.id = id;
    this.principal = principal;
    this.loginAt = loginAt;
    this.lastAccessAt = loginAt;
    this.agent = agent;
    this.ttiSeconds = ttiSeconds;
  }

  /// 到 `at` 为止是否已经超过 tti（scala 用的是严格小于）。
  bool expiredAt(long at) const @safe pure nothrow {
    return lastAccessAt + ttiSeconds < at;
  }

  bool expired() const {
    return expiredAt(nowSeconds());
  }

  /** 访问会话，返回距上次访问的秒数；-1 表示已经过期。
   *
   * 逐条对齐 scala `DefaultSession.access`：过期返回 -1 且**不动** lastAccessAt；
   * 时钟回拨（间隔为负）按 0 计且不更新；否则把 lastAccessAt 推到 `at`。
   */
  long access(long at) @safe pure nothrow {
    if (expiredAt(at))
      return -1;
    long elapse = at - lastAccessAt;
    if (elapse < 0)
      return 0;
    lastAccessAt = at;
    return elapse;
  }
}

/// 当前时间（epoch 秒）。
long nowSeconds() @safe {
  return Clock.currTime(UTC()).toUnixTime;
}

/** 会话仓库（scala `SessionRepo`）。
 *
 * 会话不存在一律用 `null` 表示（scala 侧是 `Option[Session]`）：D 里 `Session` 本身就是引用类型，
 * 再加一层 Option 只是噪声。
 */
interface SessionRepo {
  /// 取会话；`refresh` 为真时跳过缓存回源。
  Session get(string sessionId, bool refresh = false);

  /// 按账号取该账号的全部会话（scala `findByPrincipal`）。
  Session[] findByPrincipal(string principal);

  /// 访问会话并续期；会话不存在或已过期返回 null（过期时已被作废）。
  Session access(string sessionId, long accessAt);

  /// 只清本地缓存，不动后端（scala `evict`；bashub 的退出登录就只做这一步）。
  void evict(string sessionId);

  /// 作废会话：清本地缓存 + 通知后端。
  void expire(string sessionId);
}
