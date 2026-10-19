/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.artifactversion;
/// Maven `maven-metadata.xml` 的最小读取与版本刷新：只取 `<versioning><latest>`。
/// 网络请求留给调用方，方便测试解析与刷新逻辑而不必访问 Maven Central。

import beangle.commons.xml : children, elementText, parseRoot;
import beangle.data.query : Query;
import beangle.data.resource : Registry;
import beangle.data.value : Row, jsonGet, jsonText;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.string : replace, strip;

/// 返回 metadata XML；失败返回空串。服务端用 `curlGet`，测试可以直接给假数据。
alias ArtifactMetadataLoader = string delegate(string url);

/// 返回 `<latest>` 的文本；没有这个元素时返回空串。
string latestFromMetadata(string xml) {
  auto root = parseRoot(xml);
  foreach (versioning; children(root, "versioning")) {
    foreach (latest; children(versioning, "latest")) {
      auto text = elementText(latest).strip;
      if (text.length > 0)
        return text;
    }
  }
  return "";
}

/// Maven Central 上某个组件的 metadata 地址。
string artifactMetadataUrl(string groupId, string artifactId) {
  return "https://repo1.maven.org/maven2/" ~ groupId.replace(".", "/") ~ "/" ~ artifactId ~
    "/maven-metadata.xml";
}

/** 刷新指定组件的最新版本；返回实际发生变化的行数。
 *
 * 单个组件取不到 metadata、XML 坏了或版本没变都只跳过，不打断其余组件。
 */
size_t refreshArtifactVersions(Registry reg, Store store, const string[] ids, ArtifactMetadataLoader load) {
  auto res = reg.find("artifacts");
  if (res.path.length == 0 || load is null)
    return 0;

  size_t updated;
  foreach (id; ids) {
    Json doc;
    if (!store.fetch(res, id, Query.init, doc))
      continue;
    auto attrs = jsonGet(jsonGet(doc, "data"), "attributes");
    auto groupId = jsonText(jsonGet(attrs, "groupId"));
    auto artifactId = jsonText(jsonGet(attrs, "artifactId"));
    if (groupId.length == 0 || artifactId.length == 0)
      continue;

    string xml;
    try {
      xml = load(artifactMetadataUrl(groupId, artifactId));
    } catch (Exception e) {
      continue;
    }
    if (xml.length == 0)
      continue;

    string latest;
    try {
      latest = latestFromMetadata(xml).strip;
    } catch (Exception e) {
      continue;
    }
    auto current = jsonText(jsonGet(attrs, "latestVersion"));
    if (latest.length == 0 || latest == current)
      continue;

    Row values;
    values["latest_version"] = Json(latest);
    if (store.updateColumns(res, id, values))
      updated++;
  }
  return updated;
}

/// 刷新全部组件；周期任务用这个入口。
size_t refreshAllArtifactVersions(Registry reg, Store store, ArtifactMetadataLoader load) {
  auto res = reg.find("artifacts");
  if (res.path.length == 0 || load is null)
    return 0;

  auto q = Query.init;
  q.pageSize = 0; // 不分页
  auto doc = store.search(res, q);
  string[] ids;
  foreach (ref item; doc["data"]) {
    auto id = jsonText(jsonGet(item, "id"));
    if (id.length > 0)
      ids ~= id;
  }
  return refreshArtifactVersions(reg, store, ids, load);
}
