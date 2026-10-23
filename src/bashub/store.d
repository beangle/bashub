/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.store;
/// BAS 控制台的服务层装配：在框架的 `Store` 上补本应用自己的默认值。
/// 通用逻辑都在 `beangle.data`（查询/计划/SQL/Dao）与 `beangle.jsonapi`（文档/写入解析）里，
/// 这里只有「bas hub 特有的一点」。

import beangle.data.dao : Dao;
import beangle.data.query : Query;
import beangle.data.resource : Registry, Resource;
import beangle.jsonapi.document : RelIndex, attributeBool, attributeText, relationshipId, relationshipIds;
import beangle.jsonapi.store : Store, StoreException;
import beangle.data.value : Row, isBlank, jsonGet, jsonText, rowGet;

import bashub.present : decorateHub;

import vibe.data.json : Json;

import std.algorithm : canFind;
import std.conv : ConvException, to;
import std.digest : toHexString;
import std.random : uniform;
import std.string : endsWith, replace, strip, toLower;

/// 建服务层，并装上 bas hub 的默认值钩子。
Store createHubStore(Registry reg, Dao dao) {
  auto store = new Store(reg, dao);
  store.fillDefaults = (const Resource res, ref Row values) { fillHubDefaults(res, values); };
  store.beforeWrite = (const Resource res, string id, bool creating, ref Row values) {
    normalizeHubWrite(store, reg, res, id, values);
  };
  store.afterWrite = (const Resource res, string id, bool creating, Json body) {
    validateHubAfterWrite(store, reg, res, id);
  };
  store.decorateAttributes = (const Resource res, Row row, RelIndex relIndex, ref Json attributes) {
    decorateHub(reg, dao, res, row, relIndex, attributes);
  };
  return store;
}

/// 新建时的默认值（对应 Scala 侧 `ProfileWS.fillDefaults`）：凭证与仓库地址由服务端给，
/// key 之后不再随请求改写——重置要显式走 `reset-key`。
void fillHubDefaults(const Resource res, ref Row values) {
  if (res.path == "resources") {
    // scala ResourceWS.fillDefaults：新建资源默认私有、启用（scope 的 2 = Private）
    if (isBlank(rowGet(values, "scope")))
      values["scope"] = Json(2L);
    if (isBlank(rowGet(values, "enabled")))
      values["enabled"] = Json(true);
    return;
  }
  if (res.path == "channels") {
    // scala ChannelWS.fillDefaults
    if (isBlank(rowGet(values, "enabled")))
      values["enabled"] = Json(true);
    if (isBlank(rowGet(values, "channel_type")))
      values["channel_type"] = Json("pc");
    if (isBlank(rowGet(values, "embed_mode")))
      values["embed_mode"] = Json("iframe");
    return;
  }
  if (res.path == "menus") {
    if (isBlank(rowGet(values, "enabled")))
      values["enabled"] = Json(true);
    return;
  }
  if (res.path == "artifacts") {
    // scala ArtifactWS.fillDefaults：新建组件默认需要解析，显式传 false 也按原语义覆盖。
    values["resolve_support"] = Json(true);
    return;
  }
  if (res.path != "profiles")
    return;
  if (isBlank(rowGet(values, "key")))
    values["key"] = Json(profileKey());
  // 行键是列名（`local_repo`），不是 JSON:API 属性名（`localRepo`）
  setDefault(values, "local_repo", "~/.m2/repository");
  setDefault(values, "remote_repo", "https://maven.aliyun.com/nexus/content/groups/public");
  setDefault(values, "enable_https", false);
  setDefault(values, "force_https", false);
}

/// 写入前的 BAS 特化：白名单枚举、唯一性、脚本文本规范化。
private void normalizeHubWrite(Store store, Registry reg, const Resource res, string id, ref Row values) {
  if (res.path == "channels") {
    if (auto value = "channel_type" in values)
      values["channel_type"] = Json(normalizeChannelType(jsonText(*value)));
    if (auto value = "embed_mode" in values)
      values["embed_mode"] = Json(normalizeEmbedMode(jsonText(*value)));
    ensureChannelUnique(store, res, id, values);
    return;
  }
  if (res.path == "platform-feature-scripts") {
    // scala 侧脚本按行保存；Windows 换行会把 \r 一起带进页面与执行器。
    if (auto value = "scripts" in values)
      values["scripts"] = Json(jsonText(*value).replace("\r", ""));
    return;
  }
  if (res.path == "hosts") {
    normalizeHostSetlinePorts(store, reg, id, values);
    return;
  }
  if (res.path == "servers") {
    validateServerTargetHost(store, reg, id, values);
    return;
  }
}

/// 主机的 setline listen/admin 端口必须同时出现或同时为空。
private void normalizeHostSetlinePorts(Store store, Registry reg, string id, ref Row values) {
  auto listenTouched = "setline_listen_port" in values;
  auto adminTouched = "setline_admin_port" in values;
  if (!listenTouched && !adminTouched)
    return;

  normalizeHostPort(values, "setline_listen_port", "setlineListenPort", "Setline 监听端口");
  normalizeHostPort(values, "setline_admin_port", "setlineAdminPort", "Setline 管理口端口");

  auto listen = effectiveHostPort(store, reg, id, values, "setline_listen_port", "setlineListenPort");
  auto admin = effectiveHostPort(store, reg, id, values, "setline_admin_port", "setlineAdminPort");
  if (listen.length == 0 && admin.length > 0)
    throw new StoreException("setlineListenPort", "Setline 监听端口和管理口端口必须同时填写或同时留空");
  if (listen.length > 0 && admin.length == 0)
    throw new StoreException("setlineAdminPort", "Setline 监听端口和管理口端口必须同时填写或同时留空");

  if (listen.length > 0) {
    auto profileId = effectiveHostProfileId(store, reg, id, values);
    Json profileDoc;
    if (profileId.length == 0 ||
        !store.fetch(reg.find("profiles"), profileId, Query.init, profileDoc))
      throw new StoreException("profile", "启用 Setline 的主机必须属于一个存在的配置");
    auto profile = jsonGet(profileDoc, "data");
    if (attributeBool(profile, "proxyByHostname")) {
      auto hostname = attributeText(profile, "hostname").strip;
      if (hostname.length == 0)
        throw new StoreException("setlineListenPort",
            "按域名分组时必须在所属配置中填写域名");
    }
  }

  if (listen.length == 0 && id.length > 0 && hostHasTargetedServer(store, reg, id))
    throw new StoreException("setlineListenPort",
        "该主机上的服务已被 Webapp 用作运行目标，不能关闭 Setline");
}

private void normalizeHostPort(ref Row values, string column, string attribute, string label) {
  auto value = column in values;
  if (value is null)
    return;
  auto text = jsonText(*value).strip;
  if (text.length == 0) {
    values[column] = Json(null);
    return;
  }
  long port;
  try {
    port = text.to!long;
  } catch (ConvException e) {
    throw new StoreException(attribute, label ~ "必须是 1-65535 之间的数字");
  }
  if (port < 1 || port > 65535)
    throw new StoreException(attribute, label ~ "必须在 1-65535 之间");
  values[column] = Json(port);
}

/// 取写入后的有效值：本次 PATCH 提供了就用本次值，否则读数据库里的现值。
private string effectiveHostPort(Store store, Registry reg, string id, ref Row values,
    string column, string attribute) {
  if (auto value = column in values)
    return isBlank(*value) ? "" : jsonText(*value).strip;
  if (id.length == 0)
    return "";
  Json document;
  if (!store.fetch(reg.find("hosts"), id, Query.init, document))
    return "";
  return attributeText(jsonGet(document, "data"), attribute).strip;
}

private string effectiveHostProfileId(Store store, Registry reg, string id, ref Row values) {
  if (auto value = "profile_id" in values)
    return isBlank(*value) ? "" : jsonText(*value).strip;
  if (id.length == 0)
    return "";
  Json document;
  if (!store.fetch(reg.find("hosts"), id, Query.init, document))
    return "";
  return relationshipId(jsonGet(document, "data"), "profile");
}

/// server 换主机时，如果它已经被 Webapp 选中，新主机也必须部署 setline。
private void validateServerTargetHost(Store store, Registry reg, string id, ref Row values) {
  auto hostId = rowGet(values, "host");
  if (id.length == 0 || isBlank(hostId) || !serverIsTargeted(store, reg, id))
    return;
  if (!hostHasSetline(store, reg, jsonText(hostId)))
    throw new StoreException("host", "该服务已被 Webapp 用作运行目标，只能迁移到已启用 Setline 的主机");
}

private void validateHubAfterWrite(Store store, Registry reg, const Resource res, string id) {
  if (res.path == "webapps")
    validateWebappTargets(store, reg, id);
}

/// Webapp.targets 最终会写成 server.xml 的 run-at；目标 server 所在主机必须部署 setline。
private void validateWebappTargets(Store store, Registry reg, string id) {
  Json document;
  if (!store.fetch(reg.find("webapps"), id, Query.init, document))
    return;
  auto webapp = jsonGet(document, "data");
  foreach (serverId; relationshipIds(webapp, "targets")) {
    Json serverDoc;
    if (!store.fetch(reg.find("servers"), serverId, Query.init, serverDoc))
      throw new StoreException("targets", "运行目标服务不存在: " ~ serverId);
    auto server = jsonGet(serverDoc, "data");
    auto hostId = relationshipId(server, "host");
    if (hostId.length == 0 || !hostHasSetline(store, reg, hostId)) {
      auto serverName = attributeText(server, "name");
      if (serverName.length == 0)
        serverName = serverId;
      throw new StoreException("targets", "服务 " ~ serverName ~ " 所在主机未启用 Setline");
    }
  }
}

private bool hostHasSetline(Store store, Registry reg, string hostId) {
  Json document;
  if (hostId.length == 0 || !store.fetch(reg.find("hosts"), hostId, Query.init, document))
    return false;
  auto host = jsonGet(document, "data");
  return attributeText(host, "setlineListenPort").strip.length > 0
      && attributeText(host, "setlineAdminPort").strip.length > 0;
}

private bool hostHasTargetedServer(Store store, Registry reg, string hostId) {
  Query q;
  q.pageSize = 100000;
  q.addFilter("host", hostId);
  bool[string] serverIds;
  foreach (server; documentRows(store.search(reg.find("servers"), q)))
    serverIds[jsonText(jsonGet(server, "id"))] = true;
  if (serverIds.length == 0)
    return false;
  foreach (webapp; allRows(store, reg.find("webapps")))
    foreach (serverId; relationshipIds(webapp, "targets"))
      if (serverId in serverIds)
        return true;
  return false;
}

private bool serverIsTargeted(Store store, Registry reg, string serverId) {
  foreach (webapp; allRows(store, reg.find("webapps")))
    if (relationshipIds(webapp, "targets").canFind(serverId))
      return true;
  return false;
}

private Json[] documentRows(Json document) {
  Json[] rows;
  auto data = jsonGet(document, "data");
  if (data.type != Json.Type.array)
    return rows;
  foreach (ref row; data)
    rows ~= row;
  return rows;
}

private Json[] allRows(Store store, const Resource res) {
  Query q;
  q.pageSize = 100000;
  return documentRows(store.search(res, q));
}

private string normalizeChannelType(string value) {
  auto text = value.strip.toLower;
  return text == "mobile" ? text : "pc";
}

private string normalizeEmbedMode(string value) {
  auto text = value.strip.toLower;
  return text == "wujie" ? text : "iframe";
}

/// 同一应用下每个端类型唯一（scala ChannelWS.afterPopulate）。
private void ensureChannelUnique(Store store, const Resource res, string id, ref Row values) {
  auto appId = jsonText(rowGet(values, "app"));
  auto channelType = jsonText(rowGet(values, "channel_type"));
  if ((appId.length == 0 || channelType.length == 0) && id.length > 0) {
    Json current;
    if (store.fetch(res, id, Query.init, current)) {
      auto data = jsonGet(current, "data");
      if (appId.length == 0)
        appId = relationId(data, "app");
      if (channelType.length == 0)
        channelType = jsonText(jsonGet(jsonGet(data, "attributes"), "channelType"));
    }
  }
  if (appId.length == 0 || channelType.length == 0)
    return;

  auto q = Query.init;
  q.pageSize = 100000;
  q.addFilter("app", appId);
  q.addFilter("channelType", channelType);
  auto found = store.search(res, q);
  foreach (ref item; found["data"]) {
    if (jsonText(jsonGet(item, "id")) != id)
      throw new StoreException("channelType", "该应用下此端类型已存在");
  }
}

private string relationId(Json data, string attr) {
  auto rels = jsonGet(data, "relationships");
  if (rels.type != Json.Type.object)
    return "";
  auto rel = jsonGet(rels, attr);
  if (rel.type != Json.Type.object)
    return "";
  auto relData = jsonGet(rel, "data");
  if (relData.type != Json.Type.object)
    return "";
  return jsonText(jsonGet(relData, "id"));
}

private void setDefault(ref Row values, string column, string text) {
  if (isBlank(rowGet(values, column)))
    values[column] = Json(text);
}

private void setDefault(ref Row values, string column, bool flag) {
  if (isBlank(rowGet(values, column)))
    values[column] = Json(flag);
}

/** 生成一台机器的通道凭证：16 字节随机数的十六进制（32 字符）。
 *
 * 与 Scala 侧 `Profile.newKey()` 同形——格式一变等于吊销所有已下发的配置，别轻易动。
 */
string profileKey() {
  ubyte[16] bytes;
  static foreach (i; 0 .. 16)
    bytes[i] = uniform!ubyte;
  return toHexString(bytes[]).idup.toLower;
}
