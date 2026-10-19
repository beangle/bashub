/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.ems.authority_test;
/// ems resources.json → 授权域，以及远端刷新失败时保留旧域。

import beangle.commons.net.curl : HttpGetResult;
import beangle.ems.authority : RemoteAuthoritySource, authorityDomainFromJson;
import beangle.security.authz : Scope;

import std.exception : assertThrown;

private enum resourcesJson = `[
  {"name":"/api/hub/profiles","scope":"Private","roles":[1,2]},
  {"name":"/api/hub/hosts","scope":"Protected","roles":[]}
]`;

@("resources.json 解析 name/scope/roles，数字角色转成字符串")
unittest {
  auto domain = authorityDomainFromJson(resourcesJson);
  assert(domain.size == 2);
  auto profiles = domain.find("/api/hub/profiles");
  assert(profiles !is null);
  assert(profiles.level == Scope.private_);
  assert(profiles.roles == ["1", "2"]);
  assert(domain.find("/api/hub/hosts").level == Scope.protected_);
}

@("坏 JSON / 非数组 / 空文本抛异常")
unittest {
  assertThrown!Exception(authorityDomainFromJson(""));
  assertThrown!Exception(authorityDomainFromJson("{bad"));
  assertThrown!Exception(authorityDomainFromJson(`{"name":"x"}`));
}

@("远端刷新失败保留上一次成功域；合法空数组才清空")
unittest {
  int calls;
  auto source = new RemoteAuthoritySource("http://ems/resources.json", (string url) {
    calls++;
    if (calls == 1)
      return HttpGetResult(200, cast(ubyte[]) resourcesJson.dup);
    if (calls == 2)
      return HttpGetResult(200, cast(ubyte[]) "{bad".dup);
    if (calls == 3)
      return HttpGetResult(500, cast(ubyte[]) "down".dup);
    return HttpGetResult(200, cast(ubyte[]) "[]".dup);
  });

  assert(source.refresh());
  assert(source.current.size == 2);

  assert(!source.refresh()); // 200 但 JSON 损坏
  assert(source.current.size == 2);
  assert(source.lastError.length > 0);

  assert(!source.refresh()); // HTTP 失败
  assert(source.current.size == 2);

  assert(source.refresh()); // ems 明确返回空数组
  assert(source.current.size == 0);
}
