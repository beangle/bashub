/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.present;
/// BAS 的文档属性加工：只补前端确实会读、但表里没有对应列的字段。
/// 通用装饰钩子由 `beangle.jsonapi` 提供，这里认识 BAS 的资源名与版本规则。

import beangle.data.dao : Dao;
import beangle.data.plan : buildPlan;
import beangle.data.query : Query;
import beangle.data.resource : Registry, Resource;
import beangle.data.value : Row, isBlank, jsonText, rowGet;
import beangle.jsonapi.document : RelIndex;

import vibe.data.json : Json;

import std.algorithm : sort;
import std.array : appender;
import std.string : replace, split, strip;

/// 在一条资源对象的 attributes 成形后补充计算字段。
void decorateHub(Registry reg, Dao dao, const Resource res, Row row, RelIndex relIndex, ref Json attributes) {
  switch (res.path) {
  case "artifacts":
    attributes["gav"] = Json(gavOf(row, jsonText(rowGet(row, "latest_version"))));
    break;
  case "webapps":
    decorateWebapp(reg, dao, res, row, relIndex, attributes);
    break;
  case "hosts":
    decorateHost(reg, dao, row, attributes);
    break;
  case "menus":
    decorateMenu(reg, dao, res, row, relIndex, attributes);
    break;
  default:
    break;
  }
}

private void decorateWebapp(Registry reg, Dao dao, const Resource res, Row row, RelIndex relIndex,
    ref Json attributes) {
  auto artifact = relatedRow(reg, dao, res, "artifact", row, relIndex);
  auto ver = jsonText(rowGet(row, "version"));
  if (artifact.length == 0) {
    attributes["updatable"] = Json(false);
    return;
  }
  attributes["artifactName"] = Json(jsonText(rowGet(artifact, "artifact_id")));
  attributes["gav"] = Json(gavOf(artifact, ver));
  auto latest = jsonText(rowGet(artifact, "latest_version"));
  attributes["updatable"] = Json(versionIsNewer(latest, ver));
}

/// 列表只显示该主机操作系统有脚本的功能（对应 Scala 的 `feature.support(host.platform)`）。
private void decorateHost(Registry reg, Dao dao, Row row, ref Json attributes) {
  auto features = reg.find("platform-features");
  auto scripts = reg.find("platform-feature-scripts");
  auto ids = rowGet(row, "features");
  auto platformId = jsonText(rowGet(row, "platform"));
  if (features.path.length == 0 || scripts.path.length == 0 || ids.type != Json.Type.array ||
      platformId.length == 0) {
    attributes["featureLogos"] = Json.emptyArray;
    return;
  }

  Query q;
  q.pageSize = 100000;
  long total;
  auto scriptRows = dao.select(scripts, buildPlan(reg, scripts, q), total);
  bool[string] supported;
  foreach (script; scriptRows) {
    if (jsonText(rowGet(script, "platform")) == platformId)
      supported[jsonText(rowGet(script, "feature"))] = true;
  }

  string[] featureIds;
  foreach (ref item; ids) {
    auto id = jsonText(item);
    if (id.length > 0 && id in supported)
      featureIds ~= id;
  }
  auto featureRows = dao.selectByIds(features, featureIds);
  sort!((a, b) => jsonText(rowGet(a, "name")) < jsonText(rowGet(b, "name")))(featureRows);

  auto logos = appender!(Json[])();
  foreach (feature; featureRows) {
    auto item = Json.emptyObject;
    item["id"] = Json(jsonText(rowGet(feature, "id")));
    item["name"] = Json(jsonText(rowGet(feature, "name")));
    item["logo"] = Json(jsonText(rowGet(feature, "logo")));
    logos.put(item);
  }
  attributes["featureLogos"] = Json(logos.data);
}

/// 入口地址 = 资源权限名 + 可选参数；参数为空时不能留下孤零零的 `?`。
private void decorateMenu(Registry reg, Dao dao, const Resource res, Row row, RelIndex relIndex,
    ref Json attributes) {
  auto entry = relatedRow(reg, dao, res, "entry", row, relIndex);
  if (entry.length == 0) {
    attributes["entryUrl"] = Json("");
    return;
  }
  auto url = jsonText(rowGet(entry, "name"));
  auto params = jsonText(rowGet(row, "params")).strip;
  if (params.length > 0)
    url ~= "?" ~ params;
  attributes["entryUrl"] = Json(url);
}

private Row relatedRow(Registry reg, Dao dao, const Resource res, string relName, Row row, RelIndex relIndex) {
  auto id = jsonText(rowGet(row, relName));
  if (id.length == 0)
    return Row.init;
  auto indexKey = res.type ~ ":" ~ relName;
  if (auto byId = indexKey in relIndex) {
    if (auto target = id in *byId)
      return *target;
  }
  auto rel = reg.findRel(res, relName);
  if (rel is null)
    return Row.init;
  return dao.findById(reg.find(rel.target), id);
}

string gavOf(Row artifact, string ver) {
  return gavOf(jsonText(rowGet(artifact, "group_id")), jsonText(rowGet(artifact, "artifact_id")),
      jsonText(rowGet(artifact, "packaging")), jsonText(rowGet(artifact, "classifier")), ver);
}

/// 构件 GAV；classifier 为空时省略该段。
string gavOf(string groupId, string artifactId, string packaging, string classifier, string ver) {
  auto head = groupId ~ ":" ~ artifactId ~ ":" ~ packaging;
  return classifier.length == 0 ? head ~ ":" ~ ver : head ~ ":" ~ classifier ~ ":" ~ ver;
}

/// 与 Scala 的 `Version.isNewer` 同口径：逐段按等宽补零后比较，去掉旧版本的 `-SNAPSHOT`。
private bool versionIsNewer(string newVersion, string oldVersion) {
  if (newVersion == oldVersion)
    return false;
  auto oldParts = oldVersion.replace("-SNAPSHOT", "").split(".");
  auto newParts = newVersion.split(".");
  auto count = oldParts.length < newParts.length ? oldParts.length : newParts.length;
  int greater = 0;
  foreach (i; 0 .. count) {
    if (newParts[i] == oldParts[i])
      continue;
    auto width = newParts[i].length > oldParts[i].length ? newParts[i].length : oldParts[i].length;
    auto cmp = padLeft(newParts[i], width) < padLeft(oldParts[i], width) ? -1 : 1;
    if (cmp > 0) {
      greater = 1;
      break;
    }
    greater = -1;
    break;
  }
  return greater >= 0;
}

private string padLeft(string text, size_t width) {
  if (text.length >= width)
    return text;
  auto sb = appender!string;
  foreach (i; text.length .. width)
    sb.put('0');
  sb.put(text);
  return sb.data;
}
