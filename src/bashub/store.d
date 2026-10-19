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
import beangle.jsonapi.document : RelIndex;
import beangle.jsonapi.store : Store, StoreException;
import beangle.data.value : Row, isBlank, jsonGet, jsonText, rowGet;

import bashub.present : decorateHub;

import vibe.data.json : Json;

import std.algorithm : canFind;
import std.digest : toHexString;
import std.random : uniform;
import std.string : endsWith, replace, strip, toLower;

/// 建服务层，并装上 bas hub 的默认值钩子。
Store createHubStore(Registry reg, Dao dao) {
  auto store = new Store(reg, dao);
  store.fillDefaults = (const Resource res, ref Row values) { fillHubDefaults(res, values); };
  store.beforeWrite = (const Resource res, string id, bool creating, ref Row values) {
    normalizeHubWrite(store, res, id, values);
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
private void normalizeHubWrite(Store store, const Resource res, string id, ref Row values) {
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
  if (res.path == "profiles") {
    normalizeProfileCertificate(values);
  }
}

/// PEM 只保留一份稳定的换行；同时挡住把管理台脱敏值误写回数据库。
private void normalizeProfileCertificate(ref Row values) {
  if (auto value = "ssl_certificate" in values) {
    auto pem = normalizePem(jsonText(*value));
    if (pem.length > 0 && !pem.canFind("-----BEGIN CERTIFICATE-----"))
      throw new StoreException("sslCertificate", "证书必须是 PEM 格式（包含 BEGIN CERTIFICATE）");
    values["ssl_certificate"] = Json(pem);
  }
  if (auto value = "ssl_certificate_key" in values) {
    auto pem = normalizePem(jsonText(*value));
    if (pem.length > 0 && !pem.canFind("PRIVATE KEY-----"))
      throw new StoreException("sslCertificateKey", "私钥必须是 PEM 格式（包含 PRIVATE KEY）");
    values["ssl_certificate_key"] = Json(pem);
  }
}

private string normalizePem(string value) {
  auto text = value.replace("\r\n", "\n").replace("\r", "\n").strip;
  if (text.length > 0 && !text.endsWith("\n"))
    text ~= "\n";
  return text;
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
