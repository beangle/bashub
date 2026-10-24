/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.project.resolver;
/// `/api/bashub/{group}/{project}` 的共同入口：按 `org.name` 定位 Project。鉴权由调用方决定：
/// `config/server`、`micdn.xml`、节点通道走 `Project.key`，proxy/menus/script 仍按 `ip` 头。
/// 后续 server/proxy/menus/micdn/script 都从这里拿同一个 Project 上下文，避免各端点
/// 对「配置怎么找」出现不同口径。

import beangle.data.query : Query;
import beangle.data.resource : Registry, Resource;
import beangle.data.value : jsonText;
import beangle.jsonapi.document : attributeText, relationshipIds;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.algorithm : canFind, sort;
import std.array : split;
import std.string : indexOf, replace, strip;

/// 已定位到配置记录（是否通过 IP / 会话校验由调用方决定）的 Project。
struct ProjectContext {
  string id;
  /// JSON:API 的 `data` 对象
  Json data;
}

/// setline 下载配置：只匹配 proxy_setting.ip（内部地址），不回退 Host.ip。
bool resolveSetlineProject(Registry reg, Store store, string qualifiedName, string ipHeader,
    out ProjectContext context) {
  if (!findProject(reg, store, qualifiedName, context))
    return false;
  auto requested = ipHeaderAddresses(ipHeader);
  if (requested.length == 0)
    return false;
  auto proxies = loadAll(store, reg.find("proxy-settings"), ["project": context.id]);
  if (proxies.length == 0)
    return false;
  auto configured = splitIps(attributeText(proxies[0], "ip"));
  foreach (ip; requested)
    if (configured.canFind(ip))
      return true;
  return false;
}

/// agent / EMS 菜单：只按该 Project 下的 Host.ip 匹配，返回命中的 host ip。
bool resolveHostProject(Registry reg, Store store, string qualifiedName, string ipHeader,
    out ProjectContext context, out string matched) {
  if (!findProject(reg, store, qualifiedName, context))
    return false;
  return matchHostIp(reg, store, context, ipHeaderAddresses(ipHeader), matched);
}

/// 只按配置名找 Project，不校验来源；调用方自己决定用 Bearer 还是 `ip` 头鉴权。
bool findProject(Registry reg, Store store, string qualifiedName, out ProjectContext context) {
  auto dot = qualifiedName.indexOf('.');
  if (dot <= 0 || dot >= qualifiedName.length - 1)
    return false;

  Query q;
  q.pageSize = 2;
  q.addFilter("org.name", qualifiedName[0 .. dot]);
  q.addFilter("name", qualifiedName[dot + 1 .. $]);
  auto projects = dataOf(store.search(reg.find("projects"), q));
  if (projects.length == 0)
    return false;

  auto project = projects[0];
  auto id = jsonText(project["id"]);
  if (id.length == 0)
    return false;

  return accept(id, project, context);
}

/// 只按 JSON:API 主键找 Project；管理台查看配置用它，鉴权由会话负责。
bool findProjectById(Registry reg, Store store, string id, out ProjectContext context) {
  if (!id.length)
    return false;
  Json document;
  if (!store.fetch(reg.find("projects"), id, Query.init, document))
    return false;
  auto project = document["data"];
  auto actualId = jsonText(project["id"]);
  if (actualId.length == 0)
    return false;
  return accept(actualId, project, context);
}

/// 一次取完某个 Project 下的资源。配置分发端点的数据量很小，不做分页与缓存。
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

private bool accept(string id, Json project, out ProjectContext context) {
  context.id = id;
  context.data = project;
  return true;
}

/// Scala 侧 `Strings.split(ips, " ")` 的等价物：空白分隔，忽略空项。
private string[] splitIps(string text) {
  string[] ips;
  foreach (part; text.replace(",", " ").split) {
    auto ip = part.strip;
    if (ip.length > 0)
      ips ~= ip;
  }
  return ips;
}

/**
 * 从上报地址里挑出属于该 Project 的 Host，作为「project + host ip」身份。
 * 只比较 Host.ip；Project/Proxy 的 ip 不参与 agent 身份。
 */
bool matchHostIp(Registry reg, Store store, ProjectContext project, const(string)[] candidates,
    out string matched) {
  if (candidates.length == 0)
    return false;

  Query hq;
  hq.pageSize = 100000;
  hq.addFilter("project", project.id);
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
