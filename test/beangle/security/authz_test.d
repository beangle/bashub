/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.security.authz_test;
/// 授权域语义：Public/Protected/Private、未知资源、root、权限串与账户状态。

import beangle.security.authz;
import beangle.security.session;

private Session sessionOf(string[] authorities, string[] permissions = null, bool root = false) {
  auto account = new DefaultAccount("tester", "测试用户");
  account.authorities = authorities;
  account.permissions = permissions;
  account.isRoot = root;
  return new Session("sid", account, nowSeconds(), new Agent("test", "", ""), 1800);
}

private AuthorityDomain sampleDomain() {
  return authorityDomain([
    Authority("/api/bashub/public", Scope.public_, []),
    Authority("/api/bashub/protected", Scope.protected_, []),
    Authority("/api/bashub/private", Scope.private_, ["ROLE_ADMIN"]),
  ]);
}

@("Public 匿名可访问，Protected/Private 匿名拒绝")
unittest {
  auto domain = sampleDomain();
  assert(domain.permits("/api/bashub/public", "get", null));
  assert(!domain.permits("/api/bashub/protected", "get", null));
  assert(!domain.permits("/api/bashub/private", "get", null));
}

@("未登记资源按 unknownIsProtected 只要求登录")
unittest {
  auto domain = sampleDomain();
  assert(!domain.permits("/api/bashub/unknown", "get", null));
  assert(domain.permits("/api/bashub/unknown", "get", sessionOf(["ROLE_USER"])));
}

@("Private 需要角色命中，root 直接放行")
unittest {
  auto domain = sampleDomain();
  assert(!domain.permits("/api/bashub/private", "get", sessionOf(["ROLE_USER"])));
  assert(domain.permits("/api/bashub/private", "get", sessionOf(["ROLE_ADMIN"])));
  assert(domain.permits("/api/bashub/private", "get", sessionOf([], null, true)));
}

@("permissions 支持 *、resource、resource:* 与 resource:action")
unittest {
  assert(permissionAllows(["*"], "/api/bashub/private", "get"));
  assert(permissionAllows(["/api/bashub/private"], "/api/bashub/private", "get"));
  assert(permissionAllows(["/api/bashub/private:*"], "/api/bashub/private", "post"));
  assert(permissionAllows(["/api/bashub/private:get"], "/api/bashub/private", "GET"));
  assert(!permissionAllows(["/api/bashub/private:post"], "/api/bashub/private", "get"));
  assert(!permissionAllows(["private:get"], "/api/bashub/private", "get"));

  auto domain = sampleDomain();
  assert(domain.permits("/api/bashub/private", "get", sessionOf([], ["/api/bashub/private:get"])));
}

@("accountUsable 覆盖锁定、禁用、账号过期与凭据过期")
unittest {
  auto account = new DefaultAccount("tester", "测试用户");
  assert(accountUsable(account));
  account.status = AccountStatus.locked;
  assert(!accountUsable(account));
  account.status = AccountStatus.disabled;
  assert(!accountUsable(account));
  account.status = AccountStatus.accountExpired;
  assert(!accountUsable(account));
  account.status = AccountStatus.credentialExpired;
  assert(!accountUsable(account));
  assert(!accountUsable(null));
}

@("parseScope 认不出时按 Private，与 scala 一致")
unittest {
  assert(parseScope("Public") == Scope.public_);
  assert(parseScope(" protected ") == Scope.protected_);
  assert(parseScope("Private") == Scope.private_);
  assert(parseScope("") == Scope.private_);
  assert(scopeName(Scope.private_) == "Private");
}
