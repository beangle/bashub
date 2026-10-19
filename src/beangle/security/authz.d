/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.security.authz;
/// 授权域（scala `org.beangle.security.authz` 的 D 版）：资源 scope + 角色集合。
///
/// ems 应用侧的资源授权是 `AbstractRoleBasedAuthorizer` 那套：
/// - 未登记的资源按 `unknownIsProtected = true` 处理，只要求登录；
/// - `Public` 匿名可访问，`Protected` 要求登录，`Private` 还要求角色命中；
/// - 超级管理员直接放行。
///
/// 这里不引入 Spring/Hibernate，也不把权限判断塞进 JSON:API 的 Store：路由只问
/// 「这个资源上的这个动作能不能做」，数据来自内存里的只读授权域。

import beangle.security.session : DefaultAccount, Session;

import std.algorithm : canFind;
import std.string : strip, toLower;

/// 资源保护级别（scala `Scope`）。
enum Scope {
  public_,
  protected_,
  private_,
}

/// `<resource scope="...">` / ems JSON 的 scope 文本 → 枚举；认不出按 Private，和 scala 一致。
Scope parseScope(string text) {
  switch (text.strip.toLower) {
  case "public":
    return Scope.public_;
  case "protected":
    return Scope.protected_;
  case "private":
    return Scope.private_;
  default:
    return Scope.private_;
  }
}

string scopeName(Scope level) {
  final switch (level) {
  case Scope.public_:
    return "Public";
  case Scope.protected_:
    return "Protected";
  case Scope.private_:
    return "Private";
  }
}

/// 一个资源的授权定义（scala `Authority`）。
struct Authority {
  string name;
  Scope level = Scope.private_;
  string[] roles;

  bool matches(string[] authorities) const {
    foreach (authority; authorities) {
      if (roles.canFind(authority))
        return true;
    }
    return false;
  }
}

/** 授权域：启动时建好，之后只读。
 *
 * `authorities` 为空不是错误：没加载到 ems 资源时，所有请求走 `unknownIsProtected`
 * 的缺省——只要求登录，不额外拦角色。这样即使 ems 内网 API 暂不可用，管理台也不会
 * 从「需要登录」退化成「匿名可写」。
 */
class AuthorityDomain {
  private Authority[string] byName;

  this(Authority[] items = null) {
    if (items !is null) {
      foreach (item; items) {
        if (item.name.length > 0)
          byName[item.name] = item;
      }
    }
  }

  Authority* find(string resource) {
    if (auto found = resource in byName)
      return found;
    return null;
  }

  bool empty() const {
    return byName.length == 0;
  }

  size_t size() const {
    return byName.length;
  }

  /** 权限判定。`action` 取自 HTTP 方法，保留给权限字符串（`resource:action`）使用；
   * 角色授权本身与动作无关，这是 beangle `Authority` 的原语义。
   */
  bool permits(string resource, string action, Session session) {
    auto authority = find(resource);

    // 未登记资源：只要求登录（scala unknownIsProtected = true）
    if (authority is null)
      return session !is null;

    if (session is null)
      return authority.level == Scope.public_;
    if (session.principal.isRoot)
      return true;

    final switch (authority.level) {
    case Scope.public_:
      return true;
    case Scope.protected_:
      return true;
    case Scope.private_:
      if (authority.matches(session.principal.authorities))
        return true;
      return permissionAllows(session.principal.permissions, resource, action);
    }
  }
}

/** 直接权限串：`*`、`*:*`、`resource`、`resource:*`、`resource:action`。
 *
 * ems 的常规授权走角色 ID；`permissions` 是 OAuth/细粒度授权的补充入口。这里只认
 * 与资源名、动作名直接对应的形式，避免把 `read` 这种孤立词误当成「所有资源可读」。
 */
bool permissionAllows(string[] permissions, string resource, string action) {
  auto act = action.strip.toLower;
  foreach (permission; permissions) {
    auto text = permission.strip;
    if (text.length == 0)
      continue;
    if (text == "*" || text == "*:*")
      return true;
    if (text == resource || text == resource ~ ":*")
      return true;
    if (text == resource ~ ":" ~ act)
      return true;
  }
  return false;
}

/// 测试与小型部署用的授权域构造助手；线上由 ems 资源接口生成。
AuthorityDomain authorityDomain(Authority[] items) {
  return new AuthorityDomain(items);
}

/// 账户是否处于可用状态（scala 的五个状态位在登录时已经展开成 getter）。
bool accountUsable(DefaultAccount account) {
  return account !is null && !account.accountLocked && !account.disabled && !account.accountExpired
      && !account.credentialExpired;
}
