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
import bashub.project.resolver : dataOf;

import vibe.data.json : Json;

import std.algorithm : canFind;
import std.array : join;
import std.conv : ConvException, to;
import std.digest : toHexString;
import std.random : uniform;
import std.string : endsWith, replace, split, strip, toLower;

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

/// 新建时的默认值（对应 Scala 侧 `ProjectWS.fillDefaults`）：凭证与仓库地址由服务端给，
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
  if (res.path != "projects")
    return;
  if (isBlank(rowGet(values, "key")))
    values["key"] = Json(projectKey());
  // 行键是列名（`local_repo`），不是 JSON:API 属性名（`localRepo`）
  setDefault(values, "local_repo", "~/.m2/repository");
  setDefault(values, "remote_repo", "https://maven.aliyun.com/nexus/content/groups/public");
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
  if (res.path == "endpoints") {
    if (auto value = "name" in values) {
      auto name = jsonText(*value).strip;
      if (name.length == 0 || name.canFind(","))
        throw new StoreException("name", "endpoint 名称不能为空或包含逗号");
      values["name"] = Json(name);
    }
    if (auto value = "domain" in values)
      values["domain"] = Json(jsonText(*value).strip.toLower);
    if (auto value = "ips" in values) {
      string[] ips;
      foreach (part; jsonText(*value).split(",")) {
        auto ip = part.strip;
        if (ip.length == 0)
          throw new StoreException("ips", "endpoint 内网 IP 不能为空");
        if (ips.canFind(ip))
          throw new StoreException("ips", "endpoint 内网 IP 不能重复");
        ips ~= ip;
      }
      if (ips.length == 0)
        throw new StoreException("ips", "endpoint 至少需要一个内网 IP");
      values["ips"] = Json(ips.join(","));
    }
    return;
  }
  if (res.path == "webapps") {
    // 扩展库输入框允许换行粘贴；容器按逗号/分号拆分，保存时把换行折成逗号。
    if (auto value = "libs" in values)
      values["libs"] = Json(jsonText(*value).replace("\r\n", "\n").replace("\r", "").replace("\n", ",").strip);
    return;
  }
}

private void validateHubAfterWrite(Store store, Registry reg, const Resource res, string id) {
  if (res.path == "endpoints")
    validateEndpointUniqueness(store, reg, id);
  if (res.path == "webapps") {
    validateWebappTargets(store, reg, id);
    validateWebappEndpoints(store, reg, id);
  }
}

/// 同一 project 下 domain 唯一；无域名 endpoint 的 IP 集合两两不相交。
private void validateEndpointUniqueness(Store store, Registry reg, string id) {
  Json document;
  if (!store.fetch(reg.find("endpoints"), id, Query.init, document))
    return;
  auto endpoint = jsonGet(document, "data");
  auto projectId = relationshipId(endpoint, "project");
  if (projectId.length == 0)
    return;
  auto currentName = attributeText(endpoint, "name");
  auto currentDomain = attributeText(endpoint, "domain").strip.toLower;
  auto currentIps = endpointIps(endpoint);
  Query query;
  query.addFilter("project", projectId);
  foreach (item; dataOf(store.search(reg.find("endpoints"), query))) {
    auto otherId = jsonText(item["id"]);
    if (otherId == id)
      continue;
    auto otherName = attributeText(item, "name");
    auto otherDomain = attributeText(item, "domain").strip.toLower;
    if (currentDomain.length && otherDomain == currentDomain)
      throw new StoreException("domain", "域名 " ~ currentDomain ~ " 已被 endpoint " ~ otherName ~ " 使用");
    if (!currentDomain.length) {
      foreach (ip; currentIps)
        if (endpointIps(item).canFind(ip))
          throw new StoreException("ips", "无域名 endpoint 的 IP " ~ ip
              ~ " 已被 " ~ otherName ~ " 使用");
    }
  }
}

private string[] endpointIps(Json endpoint) {
  string[] ips;
  foreach (part; attributeText(endpoint, "ips").split(",")) {
    auto ip = part.strip;
    if (ip.length)
      ips ~= ip;
  }
  return ips;
}

/// webapp endpoints 必须存在且属于同一个 project。
private void validateWebappEndpoints(Store store, Registry reg, string id) {
  Json document;
  if (!store.fetch(reg.find("webapps"), id, Query.init, document))
    return;
  auto webapp = jsonGet(document, "data");
  auto projectId = relationshipId(webapp, "project");
  foreach (endpointId; relationshipIds(webapp, "endpoints")) {
    Json endpointDoc;
    if (!store.fetch(reg.find("endpoints"), endpointId, Query.init, endpointDoc))
      throw new StoreException("endpoints", "代理点不存在: " ~ endpointId);
    if (projectId.length && relationshipId(jsonGet(endpointDoc, "data"), "project") != projectId)
      throw new StoreException("endpoints", "代理点不属于当前项目: " ~ endpointId);
  }
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
  }
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

private void setDefault(ref Row values, string column, long value) {
  if (isBlank(rowGet(values, column)))
    values[column] = Json(value);
}

private void setDefault(ref Row values, string column, bool flag) {
  if (isBlank(rowGet(values, column)))
    values[column] = Json(flag);
}

/** 生成一台机器的通道凭证：16 字节随机数的十六进制（32 字符）。
 *
 * 与 Scala 侧 `Project.newKey()` 同形——格式一变等于吊销所有已下发的配置，别轻易动。
 */
string projectKey() {
  ubyte[16] bytes;
  static foreach (i; 0 .. 16)
    bytes[i] = uniform!ubyte;
  return toHexString(bytes[]).idup.toLower;
}
