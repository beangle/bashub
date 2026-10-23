/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.profile.resolver;
/// `/api/bashub/{group}/{profile}` 的共同入口：按 `org.name` 定位 Profile。鉴权由调用方决定：
/// `config/server`、`micdn.xml`、节点通道走 `Profile.key`，proxy/menus/script 仍按 `ip` 头。
/// 后续 server/proxy/menus/micdn/script 都从这里拿同一个 Profile 上下文，避免各端点
/// 对「配置怎么找」出现不同口径。

import beangle.data.query : Query;
import beangle.data.resource : Registry, Resource;
import beangle.data.value : jsonText;
import beangle.jsonapi.document : attributeText, relationshipIds;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.algorithm : canFind, sort;
import std.array : split;
import std.string : indexOf, strip;

/// 已定位到配置记录（是否通过 IP / 会话校验由调用方决定）的 Profile。
struct ProfileContext {
  string id;
  /// JSON:API 的 `data` 对象
  Json data;
}

/// 解析 `{org.name}` 并按 `ip` 请求头校验来源。
///
/// 与 Scala `ConfigWS.getProfile` 同口径：IP 必须命中 Profile 自身的 `ip`，或该 Profile
/// 下任一 Host 的 `ip`。请求头为空、配置名没有 `org.` 前缀、找不到配置都返回 false。
bool resolveProfile(Registry reg, Store store, string qualifiedName, string ipHeader,
    out ProfileContext context) {
  if (!findProfile(reg, store, qualifiedName, context))
    return false;

  auto requested = splitIps(ipHeader);
  if (requested.length == 0)
    return false;
  if (requested.canFind(attributeText(context.data, "ip")))
    return true;

  Query hq;
  hq.pageSize = 100000;
  hq.addFilter("profile", context.id);
  foreach (host; dataOf(store.search(reg.find("hosts"), hq))) {
    if (requested.canFind(attributeText(host, "ip")))
      return true;
  }
  return false;
}

/// 只按配置名找 Profile，不校验来源；调用方自己决定用 Bearer 还是 `ip` 头鉴权。
bool findProfile(Registry reg, Store store, string qualifiedName, out ProfileContext context) {
  auto dot = qualifiedName.indexOf('.');
  if (dot <= 0 || dot >= qualifiedName.length - 1)
    return false;

  Query q;
  q.pageSize = 2;
  q.addFilter("org.name", qualifiedName[0 .. dot]);
  q.addFilter("name", qualifiedName[dot + 1 .. $]);
  auto profiles = dataOf(store.search(reg.find("profiles"), q));
  if (profiles.length == 0)
    return false;

  auto profile = profiles[0];
  auto id = jsonText(profile["id"]);
  if (id.length == 0)
    return false;

  return accept(id, profile, context);
}

/// 只按 JSON:API 主键找 Profile；管理台查看配置用它，鉴权由会话负责。
bool findProfileById(Registry reg, Store store, string id, out ProfileContext context) {
  if (!id.length)
    return false;
  Json document;
  if (!store.fetch(reg.find("profiles"), id, Query.init, document))
    return false;
  auto profile = document["data"];
  auto actualId = jsonText(profile["id"]);
  if (actualId.length == 0)
    return false;
  return accept(actualId, profile, context);
}

/// 一次取完某个 Profile 下的资源。配置分发端点的数据量很小，不做分页与缓存。
Json[] loadAll(Store store, const Resource res, string[string] filters = null) {
  Query q;
  q.pageSize = 100000;
  if (filters !is null) {
    foreach (key, value; filters)
      q.addFilter(key, value);
  }
  return dataOf(store.search(res, q));
}

/// 文档 `data` 数组；不是数组时返回空数组。
Json[] dataOf(Json document) {
  Json[] items;
  auto data = document["data"];
  if (data.type != Json.Type.array)
    return items;
  foreach (ref item; data)
    items ~= item;
  return items;
}

private bool accept(string id, Json profile, out ProfileContext context) {
  context.id = id;
  context.data = profile;
  return true;
}

/// Scala 侧 `Strings.split(ips, " ")` 的等价物：空白分隔，忽略空项。
private string[] splitIps(string header) {
  string[] ips;
  foreach (part; header.split) {
    auto ip = part.strip;
    if (ip.length > 0)
      ips ~= ip;
  }
  return ips;
}

/**
 * 从 agent 上报的地址里挑出属于该 Profile 的那个，作为「profile + server ip」身份。
 *
 * 先看 Profile 自己的 `ip`，再按 `hosts.ip` 排序后逐个比对；命中的才算数。**不做
 * “没配置就放行”的兜底**：profile 必须声明自己的 `ip` 或至少一个 host，否则任何
 * 上报地址都无法验证，连接一律拒绝。
 */
bool matchProfileIp(Registry reg, Store store, ProfileContext profile, const(string)[] candidates,
    out string matched) {
  if (candidates.length == 0)
    return false;

  auto own = attributeText(profile.data, "ip").strip;
  if (own.length && candidates.canFind(own)) {
    matched = own;
    return true;
  }

  Query hq;
  hq.pageSize = 100000;
  hq.addFilter("profile", profile.id);
  string[] allowed;
  foreach (host; dataOf(store.search(reg.find("hosts"), hq))) {
    auto ip = attributeText(host, "ip").strip;
    if (ip.length)
      allowed ~= ip;
  }
  // DB 不保证顺序；同一台机器多个地址都命中时取排序后的第一个，身份才稳定。
  allowed.sort;
  foreach (ip; allowed) {
    if (candidates.canFind(ip)) {
      matched = ip;
      return true;
    }
  }
  return false;
}

/// `ip` 头里的合法地址字面量，保持上报顺序。
string[] ipHeaderAddresses(string header) {
  string[] ips;
  foreach (part; header.split(',')) {
    auto ip = part.strip;
    if (ip.length && isIpLiteral(ip))
      ips ~= ip;
  }
  return ips;
}

/// 只接受 IP 字面量：既避免把主机名当身份，也不触发 DNS 解析。
bool isIpLiteral(string text) {
  if (text.indexOf(':') >= 0) {
    foreach (c; text) {
      auto hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
      if (!hex && c != ':' && c != '.')
        return false;
    }
    return true;
  }
  auto parts = text.split('.');
  if (parts.length != 4)
    return false;
  foreach (part; parts) {
    if (part.length == 0 || part.length > 3)
      return false;
    foreach (c; part)
      if (c < '0' || c > '9')
        return false;
    if (part.length > 1 && part[0] == '0')
      return false;
    if (part.length == 3 && part > "255")
      return false;
  }
  return true;
}
