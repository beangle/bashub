/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.ems.authority;
/// ems 资源授权域（scala `RemoteAuthorizer` + `RemoteService.getAuthorities`）的 D 版。
///
/// 只读 `${ems.innerApi}/platform/security/func/{app}/resources.json`：数组元素的三件套
/// `name` / `scope` / `roles`，`roles` 是角色 id（JSON 里可能是数字）。这里用进程内存
/// 保存最近一次成功结果；刷新失败保留旧值，不让 EMS 内网 API 的一次抖动把管理台变成匿名。

import beangle.commons.net.curl : HttpGetResult, curlGet;
import beangle.security.authz : Authority, AuthorityDomain, parseScope;
import beangle.security.session : nowSeconds;

import std.conv : to;
import std.string : strip;

import vibe.data.json : Json, parseJsonString;

/// 测试注入用。
alias AuthorityHttpGet = HttpGetResult delegate(string url);

private HttpGetResult defaultAuthorityGet(string url) {
  return curlGet(url);
}

/// JSON 数组 → 授权域；格式非法直接抛异常，让远程刷新保留上一份成功结果。
AuthorityDomain authorityDomainFromJson(string content) {
  if (content is null || content.strip.length == 0)
    throw new Exception("authority json is empty");

  Json root;
  try {
    root = parseJsonString(content);
  } catch (Exception e) {
    throw new Exception("invalid authority json: " ~ e.msg);
  }
  if (root.type != Json.Type.array)
    throw new Exception("authority json must be an array");

  Authority[] items;
  foreach (ref node; root) {
    if (node.type != Json.Type.object)
      continue;
    auto name = textOf(node["name"]).strip;
    if (name.length == 0)
      continue;
    string[] roles;
    auto roleNode = node["roles"];
    if (roleNode.type == Json.Type.array) {
      foreach (ref role; roleNode)
        roles ~= textOf(role).strip;
    }
    items ~= Authority(name, parseScope(textOf(node["scope"])), roles);
  }
  return new AuthorityDomain(items);
}

private string textOf(Json value) {
  switch (value.type) {
  case Json.Type.string:
    return value.get!string;
  case Json.Type.int_:
    return value.get!long.to!string;
  case Json.Type.bigInt:
    return value.get!long.to!string;
  case Json.Type.float_:
    return value.get!double.to!string;
  case Json.Type.bool_:
    return value.get!bool ? "true" : "false";
  default:
    return "";
  }
}

/** 带 TTL 的远程授权域。
 *
 * 默认 300 秒，与 scala `AuthorizerRefresher` 的 `0 *\/5 * * * *` 同频。刷新不在后台线程里
 * 偷偷跑：请求路径上按需刷新，失败留旧值。低功耗部署里这比常驻线程简单，也避免并发改域。
 */
class RemoteAuthoritySource {
  string url;
  int refreshSeconds = 300;
  string lastError;

  private AuthorityHttpGet httpGet;
  private AuthorityDomain domain;
  private long loadedAt = -1;

  this(string url, AuthorityHttpGet httpGet = null) {
    this.url = url;
    this.httpGet = httpGet is null ? ((string target) => defaultAuthorityGet(target)) : httpGet;
    this.domain = new AuthorityDomain();
  }

  /// 强制刷新；成功返回 true，失败保留旧域并记录 `lastError`。
  bool refresh() {
    if (url.length == 0)
      return false;
    auto response = httpGet(url);
    if (!response.isOk) {
      lastError = "HTTP " ~ response.status.to!string;
      return false;
    }
    try {
      domain = authorityDomainFromJson(cast(string) response.body);
      loadedAt = nowSeconds();
      lastError = null;
      return true;
    } catch (Exception e) {
      lastError = e.msg;
      return false;
    }
  }

  /// 取当前域；超过 TTL 时先尝试刷新。从未成功加载过时会尝试一次。
  AuthorityDomain get() {
    auto now = nowSeconds();
    if (loadedAt < 0 || (refreshSeconds > 0 && now - loadedAt >= refreshSeconds))
      refresh();
    return domain;
  }

  /// 已加载的域（测试用，不触发刷新）。
  AuthorityDomain current() {
    return domain;
  }
}
