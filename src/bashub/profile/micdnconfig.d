/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.profile.micdnconfig;
/// 以 Profile 为中心的 micdn 配置聚合。
///
/// 数据库里只保存三段结构：可复用组件目录、Profile 段设置、Profile 对组件的绑定。
/// 本模块负责把三者归一、校验并渲染成稳定的 micdn.xml；页面只读写这一个聚合。

import bashub.profile.resolver : dataOf, loadAll;

import beangle.commons.xml : escapeXml;
import beangle.data.query : Query;
import beangle.data.resource : Registry, Resource;
import beangle.data.value : Row, jsonGet, jsonText;
import beangle.jsonapi.document : attributeText, relationshipId;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json, parseJson;

import std.algorithm : canFind, sort;
import std.array : appender, split;
import std.conv : ConvException, to;
import std.string : indexOf, lastIndexOf, strip, toLower;

/// 配置或组件不合法。`field` 供 API 的 400 响应定位到具体属性。
class MicdnConfigException : Exception {
  string field;

  this(string field, string msg, string file = __FILE__, size_t line = __LINE__) @safe {
    super(msg, file, line);
    this.field = field;
  }
}

/// 一个绑定到 Profile 的组件，已经展开组件规格。
struct BoundComponent {
  string bindingId;
  string componentId;
  string kind;
  string name;
  string mountName;
  long sortno;
  Json spec;
}

/// 聚合读取的中间状态；保存时也用它拿到旧密钥与旧绑定。
struct MicdnState {
  Json config;
  BoundComponent[] components;
  Json[] catalog;
  string[] bindingIds;
}

/// 一个 Profile 的完整配置视图。
struct MicdnProfileView {
  Json profile;
  MicdnState state;
  string profileKey;
}

private immutable string[] logLevels = [
  "trace", "debugv", "debug-v", "debug", "diagnostic", "verbose",
  "info", "warn", "warning", "error", "critical", "fatal",
];

/// 前端/接口使用的空配置。缺省不声明 maven/npm/native，也不挂任何组件。
Json defaultMicdnConfig() {
  auto root = Json.emptyObject;
  root["home"] = Json("");
  root["listen"] = Json("0.0.0.0:8888");
  root["logFile"] = Json("console");
  root["logLevel"] = Json("info");

  auto maven = Json.emptyObject;
  maven["declared"] = Json(false);
  maven["base"] = Json("");
  maven["remotes"] = Json.emptyArray;
  maven["snapshotRemote"] = Json("");
  root["maven"] = maven;

  auto npm = Json.emptyObject;
  npm["declared"] = Json(false);
  npm["base"] = Json("");
  npm["remotes"] = Json.emptyArray;
  npm["devRemote"] = Json("");
  root["npm"] = npm;

  auto native = Json.emptyObject;
  native["declared"] = Json(false);
  native["base"] = Json("");
  root["native"] = native;

  auto auth = Json.emptyObject;
  auth["publishKey"] = Json("");
  auth["downloadKey"] = Json("");
  auth["maxSize"] = Json("64M");
  root["auth"] = auth;

  auto staticCfg = Json.emptyObject;
  staticCfg["base"] = Json("");
  root["static"] = staticCfg;

  auto www = Json.emptyObject;
  www["base"] = Json("");
  root["www"] = www;

  auto blob = Json.emptyObject;
  blob["base"] = Json("");
  blob["maxSize"] = Json("100M");
  blob["publicImages"] = Json(true);
  root["blob"] = blob;
  root["servers"] = Json.emptyArray;
  return root;
}

/// 把任意输入归一成固定形状；未知字段丢弃，缺失字段补默认值。
Json normalizeMicdnConfig(Json input) {
  auto source = input.type == Json.Type.object ? input : Json.emptyObject;
  auto result = defaultMicdnConfig();
  copyText(source, result, "home");
  copyText(source, result, "listen");
  copyText(source, result, "logFile");
  copyText(source, result, "logLevel");
  if (field(result, "listen").length == 0)
    result["listen"] = Json("0.0.0.0:8888");
  if (field(result, "logFile").length == 0)
    result["logFile"] = Json("console");
  if (field(result, "logLevel").length == 0)
    result["logLevel"] = Json("info");

  normalizeMaven(source, result);
  normalizeNpm(source, result);
  normalizeNative(source, result);
  normalizeAuth(source, result);
  normalizeRepoSection(source, result, "static");
  normalizeRepoSection(source, result, "www");
  normalizeBlob(source, result);
  normalizeServers(source, result);
  return result;
}

/// 合并密钥：请求未出现的 key 沿用旧值；显式空串表示清空。
Json mergeMicdnSecrets(Json input, Json existing) {
  auto result = copyJson(input.type == Json.Type.object ? input : Json.emptyObject);
  auto oldAuth = jsonGet(existing, "auth");
  auto auth = jsonGet(result, "auth");
  if (auth.type != Json.Type.object)
    auth = Json.emptyObject;
  foreach (key; ["publishKey", "downloadKey", "maxSize"]) {
    if (jsonGet(auth, key).type == Json.Type.undefined) {
      auto value = jsonGet(oldAuth, key);
      if (value.type != Json.Type.undefined)
        auth[key] = value;
    }
  }
  result["auth"] = auth;
  return result;
}

/// 校验并返回固定形状的组件规格。
Json normalizeComponentSpec(string kind, Json input) {
  if (kind.length == 0)
    throw new MicdnConfigException("kind", "组件类型不能为空");
  auto spec = input.type == Json.Type.object ? copyJson(input) : Json.emptyObject;
  switch (kind) {
  case "static_bundle":
    auto rawSources = jsonGet(spec, "sources");
    if (rawSources.type != Json.Type.array || rawSources.length == 0)
      throw new MicdnConfigException("spec.sources", "static bundle 至少需要一个来源");
    Json[] sources;
    bool hasDir;
    bool hasArchive;
    foreach (ref item; rawSources) {
      auto source = normalizeSource(item, "spec.sources");
      auto sourceKind = source["kind"].get!string;
      if (sourceKind != "jar" && sourceKind != "npm" && sourceKind != "dir")
        throw new MicdnConfigException("spec.sources.kind",
            "static bundle 来源必须是 jar、npm 或 dir");
      if (sourceKind == "dir")
        hasDir = true;
      else
        hasArchive = true;
      sources ~= source;
    }
    if (hasDir && hasArchive)
      throw new MicdnConfigException("spec.sources", "static bundle 不能混用 dir 与 jar/npm");
    sources.sort!((a, b) => sourceBefore(a, b));
    spec["sources"] = Json(sources);
    return spec;
  case "www_doc":
    auto source = normalizeSource(jsonGet(spec, "source"), "spec.source");
    auto sourceKind = source["kind"].get!string;
    if (sourceKind != "npm" && sourceKind != "zip")
      throw new MicdnConfigException("spec.source.kind", "www doc 的来源必须是 npm 或 zip");
    spec["source"] = source;
    auto tryFile = field(spec, "tryFile");
    if (tryFile.indexOf('/') >= 0 || tryFile.indexOf('\\') >= 0)
      throw new MicdnConfigException("spec.tryFile", "try-file 只能是单个文件名，不能包含路径");
    spec["tryFile"] = Json(tryFile);
    auto autoDeploy = flag(spec, "autoDeploy", false);
    if (autoDeploy && sourceKind != "zip")
      throw new MicdnConfigException("spec.autoDeploy", "只有 zip 来源支持自动部署");
    spec["autoDeploy"] = Json(autoDeploy);
    spec["autoGzip"] = Json(flag(spec, "autoGzip", true));
    return spec;
  default:
    throw new MicdnConfigException("kind", "未知组件类型: " ~ kind);
  }
}

/// 校验组件名称；static 是单段名，www 可以是 `a/b`。
void validateComponentName(string kind, string name) {
  if (name.strip.length == 0)
    throw new MicdnConfigException("name", "组件名称不能为空");
  if (kind == "www_doc")
    validateDocName(name, "name");
  else
    validateSingleName(name, "name");
}

/// 绑定挂载名：static 单段，www 可为多段。
void validateMountName(string kind, string mountName) {
  if (kind == "www_doc")
    validateDocName(mountName, "mountName");
  else
    validateSingleName(mountName, "mountName");
}

/// 读取 Profile 的完整 Micdn 聚合。Profile 不存在返回 false。
bool loadMicdnProfile(Store store, Registry reg, string profileId, out MicdnProfileView view) {
  Json profileDoc;
  if (!store.fetch(reg.find("profiles"), profileId, Query.init, profileDoc))
    return false;

  MicdnState state;
  if (!loadMicdnState(store, reg, profileId, state))
    return false;

  auto profile = Json.emptyObject;
  auto profileKey = attributeText(profileDoc["data"], "key");
  auto cleanKey = profileKey.strip;
  profile["id"] = Json(profileId);
  profile["name"] = Json(attributeText(profileDoc["data"], "name"));
  profile["qualifiedName"] = Json(attributeText(profileDoc["data"], "qualifiedName"));
  profile["title"] = Json(attributeText(profileDoc["data"], "title"));
  profile["ip"] = Json(attributeText(profileDoc["data"], "ip"));
  profile["keyMasked"] = Json(maskSecret(cleanKey));
  profile["keySet"] = Json(cleanKey.length > 0);

  view = MicdnProfileView(profile, state, profileKey);
  return true;
}

/// 读取配置、绑定和组件目录，供 XML 分发与页面聚合共用。
bool loadMicdnState(Store store, Registry reg, string profileId, out MicdnState state) {
  Json config;
  readMicdnConfig(store, reg, profileId, config);

  auto catalog = loadAll(store, reg.find("cdn-components"));
  Json[string] byId;
  foreach (ref component; catalog) {
    auto id = jsonText(jsonGet(component, "id"));
    if (id.length > 0)
      byId[id] = component;
  }

  Query bindingQuery;
  bindingQuery.pageSize = 100000;
  bindingQuery.addFilter("profile", profileId);
  auto bindings = dataOf(store.search(reg.find("profile-micdn-components"), bindingQuery));

  BoundComponent[] components;
  string[] bindingIds;
  foreach (ref binding; bindings) {
    auto bindingId = jsonText(jsonGet(binding, "id"));
    auto componentId = relationshipId(binding, "component");
    if (componentId.length == 0)
      throw new MicdnConfigException("component", "绑定 " ~ bindingId ~ " 没有组件");
    if (auto found = componentId in byId) {
      auto kind = attributeText(*found, "kind");
      auto mountName = attributeText(*found, "mountName");
      if (mountName.length == 0)
        throw new MicdnConfigException("mountName", "组件 " ~ componentId ~ " 缺少挂载名");
      validateMountName(kind, mountName);
      auto spec = normalizeComponentSpec(kind, jsonGet(jsonGet(*found, "attributes"), "spec"));
      components ~= BoundComponent(bindingId, componentId, kind, attributeText(*found, "name"),
          mountName, attributeText(binding, "sortno").to!long, spec);
      bindingIds ~= bindingId;
    } else {
      throw new MicdnConfigException("component", "绑定的组件不存在: " ~ componentId);
    }
  }

  sortBindings(components);
  state = MicdnState(config, components, catalog, bindingIds);
  return true;
}

/// 只读取并归一 Micdn 配置，不加载组件与绑定。配置行缺失时返回缺省配置。
void readMicdnConfig(Store store, Registry reg, string profileId, out Json config) {
  config = defaultMicdnConfig();
  Json configDoc;
  if (store.fetch(reg.find("profile-micdn"), profileId, Query.init, configDoc)) {
    auto attrs = jsonGet(jsonGet(configDoc, "data"), "attributes");
    config = normalizeMicdnConfig(jsonGet(attrs, "config"));
  }
}

/// 渲染 Profile 的 micdn.xml；`profileName` / `profileKey` 用于生成唯一的 blob bucket。
/// maskSecrets=true 时只用于页面预览，bucket key 保留首尾各两个字符。
/// `remoteUrl` 由下载请求的 origin 推导，不进入 Profile 配置。
string renderMicdnXml(Json rawConfig, const BoundComponent[] components, string profileName,
    string profileKey, bool maskSecrets = false, string remoteUrl = "") {
  auto config = normalizeMicdnConfig(rawConfig);
  validateMicdnConfig(config);
  validateBlobIdentity(profileName, profileKey);

  BoundComponent[] staticBundles;
  BoundComponent[] wwwDocs;
  foreach (ref component; components) {
    normalizeComponentSpec(component.kind, component.spec);
    switch (component.kind) {
    case "static_bundle":
      staticBundles ~= component;
      break;
    case "www_doc":
      wwwDocs ~= component;
      break;
    default:
      break;
    }
  }
  staticBundles.sort!((a, b) => nameBefore(a.mountName, b.mountName));
  sortBindings(wwwDocs);

  auto xml = appender!string;
  xml.put(`<?xml version="1.0" encoding="UTF-8"?>`);
  xml.put("\n<micdn");
  putAttr(xml, "listen", field(config, "listen"));
  putAttr(xml, "remote", remoteUrl.strip);
  putAttr(xml, "home", field(config, "home"));
  auto logFile = field(config, "logFile");
  if (logFile != "console")
    putAttr(xml, "log-file", logFile);
  auto logLevel = field(config, "logLevel");
  if (logLevel != "info")
    putAttr(xml, "log-level", logLevel);
  xml.put(">\n");

  auto maven = jsonGet(config, "maven");
  if (flag(maven, "declared", false)) {
    xml.put("  <maven");
    putAttr(xml, "base", effectiveBase(config, "maven", "/maven"));
    xml.put(">\n");
    foreach (url; textList(jsonGet(maven, "remotes"))) {
      xml.put("    <remote");
      putAttr(xml, "url", url);
      xml.put("/>\n");
    }
    auto snapshot = field(maven, "snapshotRemote");
    if (snapshot.length > 0) {
      xml.put("    <snapshot");
      putAttr(xml, "remote", snapshot);
      xml.put("/>\n");
    }
    xml.put("  </maven>\n");
  }

  auto npm = jsonGet(config, "npm");
  if (flag(npm, "declared", false)) {
    xml.put("  <npm");
    putAttr(xml, "base", effectiveBase(config, "npm", "/npm"));
    xml.put(">\n");
    foreach (url; textList(jsonGet(npm, "remotes"))) {
      xml.put("    <remote");
      putAttr(xml, "url", url);
      xml.put("/>\n");
    }
    auto dev = field(npm, "devRemote");
    if (dev.length > 0) {
      xml.put("    <dev");
      putAttr(xml, "remote", dev);
      xml.put("/>\n");
    }
    xml.put("  </npm>\n");
  }

  auto nativeCfg = jsonGet(config, "native");
  if (flag(nativeCfg, "declared", false)) {
    xml.put("  <native");
    putAttr(xml, "base", effectiveBase(config, "native", "/native"));
    xml.put("/>\n");
  }

  auto auth = jsonGet(config, "auth");
  auto publishKey = field(auth, "publishKey");
  auto downloadKey = field(auth, "downloadKey");
  if (publishKey.length > 0 || downloadKey.length > 0) {
    auto publish = maskSecrets && publishKey.length > 0 ? "********" : publishKey;
    auto download = maskSecrets && downloadKey.length > 0 ? "********" : downloadKey;
    xml.put("  <auth");
    if (publish.length > 0)
      putAttr(xml, "publish-key", publish);
    if (download.length > 0)
      putAttr(xml, "download-key", download);
    putAttr(xml, "max-size", field(auth, "maxSize"));
    xml.put("/>\n");
  }

  auto blob = jsonGet(config, "blob");
  auto key = profileKey.strip;
  if (key.length > 0) {
    xml.put("  <blob");
    putAttr(xml, "base", effectiveBase(config, "blob", "/blob"));
    putAttr(xml, "max-size", field(blob, "maxSize"));
    xml.put(">\n");
    xml.put("    <bucket");
    putAttr(xml, "name", profileName.strip);
    putAttr(xml, "key", maskSecrets ? maskSecret(key) : key);
    if (!flag(blob, "publicImages", true))
      putAttr(xml, "publicImages", "false");
    xml.put("/>\n");
    xml.put("  </blob>\n");
  }

  auto staticCfg = jsonGet(config, "static");
  if (staticBundles.length > 0) {
    xml.put("  <static");
    putAttr(xml, "base", effectiveBase(config, "static", "/asset"));
    xml.put(">\n");
    foreach (ref bundle; staticBundles) {
      xml.put("    <bundle");
      putAttr(xml, "name", bundle.mountName);
      xml.put(">\n");
      Json[] sources;
      foreach (ref source; jsonGet(bundle.spec, "sources"))
        sources ~= source;
      sources.sort!((a, b) => sourceBefore(a, b));
      foreach (ref source; sources) {
        auto kind = field(source, "kind");
        auto ref_ = field(source, "ref");
        auto inner = field(source, "inner");
        xml.put("      <" ~ kind);
        if (kind == "jar")
          putAttr(xml, "gav", ref_);
        else if (kind == "npm")
          putAttr(xml, "package", ref_);
        else if (kind == "dir")
          putAttr(xml, "location", ref_);
        if (inner.length > 0 && kind != "dir")
          putAttr(xml, "dir", inner);
        xml.put("/>\n");
      }
      xml.put("    </bundle>\n");
    }
    xml.put("  </static>\n");
  }

  auto www = jsonGet(config, "www");
  if (wwwDocs.length > 0) {
    xml.put("  <www");
    putAttr(xml, "base", effectiveBase(config, "www", "/www"));
    xml.put(">\n");
    foreach (ref doc; wwwDocs) {
      auto source = jsonGet(doc.spec, "source");
      auto kind = field(source, "kind");
      auto ref_ = field(source, "ref");
      auto inner = field(source, "inner");
      xml.put("    <doc");
      putAttr(xml, "name", doc.mountName);
      if (kind == "npm")
        putAttr(xml, "npm", ref_);
      else
        putAttr(xml, "zip", ref_);
      if (inner.length > 0 && !(kind == "npm" && inner == "dist"))
        putAttr(xml, "inner", inner);
      auto tryFile = field(doc.spec, "tryFile");
      if (tryFile.length > 0)
        putAttr(xml, "try-file", tryFile);
      if (flag(doc.spec, "autoDeploy", false))
        putAttr(xml, "auto-deploy", "true");
      if (!flag(doc.spec, "autoGzip", true))
        putAttr(xml, "auto-gzip", "false");
      xml.put("/>\n");
    }
    xml.put("  </www>\n");
  }

  xml.put("</micdn>\n");
  return xml.data;
}

/// 页面聚合：配置（脱敏）、绑定、组件目录和预览 XML。
Json micdnProfileDocument(const MicdnProfileView view, string remoteUrl = "") {
  auto doc = Json.emptyObject;
  doc["profile"] = view.profile;
  doc["config"] = sanitizeConfig(view.state.config);

  Json[] bindings;
  foreach (ref component; view.state.components) {
    auto item = Json.emptyObject;
    item["id"] = Json(component.bindingId);
    item["componentId"] = Json(component.componentId);
    item["kind"] = Json(component.kind);
    item["name"] = Json(component.name);
    item["mountName"] = Json(component.mountName);
    item["sortno"] = Json(component.sortno);
    item["spec"] = component.spec;
    bindings ~= item;
  }
  doc["bindings"] = Json(bindings);

  Json[] catalog;
  foreach (ref resource; view.state.catalog)
    catalog ~= plainComponent(resource);
  doc["components"] = Json(catalog);
  auto profileName = jsonText(view.profile["name"]);
  doc["xml"] = Json(renderMicdnXml(view.state.config, view.state.components, profileName, view.profileKey,
      true, remoteUrl));
  return doc;
}

/// 保存整份 Profile 配置。`bindings` 缺省时沿用当前绑定。
void saveMicdnProfile(Store store, Registry reg, string profileId, Json body) {
  Json profile;
  if (!store.fetch(reg.find("profiles"), profileId, Query.init, profile))
    throw new MicdnConfigException("profile", "Profile 不存在: " ~ profileId);

  MicdnState oldState;
  if (!loadMicdnState(store, reg, profileId, oldState))
    throw new MicdnConfigException("profile", "Profile 不存在: " ~ profileId);

  auto rawConfig = jsonGet(body, "config");
  if (rawConfig.type != Json.Type.object)
    throw new MicdnConfigException("config", "缺少 config 对象");
  auto config = normalizeMicdnConfig(mergeMicdnSecrets(rawConfig, oldState.config));
  validateMicdnConfig(config);
  validateBlobIdentity(attributeText(profile["data"], "name"), attributeText(profile["data"], "key"));

  Json[string] catalogById;
  foreach (ref component; oldState.catalog) {
    auto id = jsonText(jsonGet(component, "id"));
    if (id.length > 0)
      catalogById[id] = component;
  }

  BoundComponent[] desired;
  auto rawBindings = jsonGet(body, "bindings");
  if (rawBindings.type == Json.Type.undefined) {
    desired = oldState.components;
  } else {
    if (rawBindings.type != Json.Type.array)
      throw new MicdnConfigException("bindings", "bindings 必须是数组");
    bool[string] componentIds;
    foreach (ref item; rawBindings) {
      auto componentId = firstText(item, "componentId", "component");
      if (componentId.length == 0)
        throw new MicdnConfigException("bindings.componentId", "绑定缺少 componentId");
      if (componentId in componentIds)
        throw new MicdnConfigException("bindings.componentId", "组件重复绑定: " ~ componentId);
      componentIds[componentId] = true;
      auto found = componentId in catalogById;
      if (found is null)
        throw new MicdnConfigException("bindings.componentId", "组件不存在: " ~ componentId);
      auto kind = attributeText(*found, "kind");
      auto mountName = attributeText(*found, "mountName");
      if (mountName.length == 0)
        throw new MicdnConfigException("bindings.componentId", "组件缺少挂载名: " ~ componentId);
      validateMountName(kind, mountName);
      auto spec = normalizeComponentSpec(kind, jsonGet(jsonGet(*found, "attributes"), "spec"));
      desired ~= BoundComponent("", componentId, kind, attributeText(*found, "name"),
          mountName, numberField(item, "sortno", 0), spec);
    }
  }
  sortBindings(desired);

  store.transaction({
    Row configValues;
    configValues["config"] = config;
    store.upsertColumns(reg.find("profile-micdn"), profileId, configValues);

    auto bindingRes = reg.find("profile-micdn-components");
    foreach (bindingId; oldState.bindingIds)
      store.removeColumns(bindingRes, bindingId);
    foreach (ref component; desired) {
      Row values;
      values["profile"] = Json(profileId);
      values["component"] = Json(component.componentId);
      values["sortno"] = Json(component.sortno);
      store.insertColumns(bindingRes, values);
    }
  });
}

/// 组件的 JSON:API 文档 → 页面使用的扁平静态对象。
Json plainComponent(Json resource) {
  auto attrs = jsonGet(resource, "attributes");
  auto kind = attributeText(resource, "kind");
  auto spec = normalizeComponentSpec(kind, jsonGet(attrs, "spec"));
  auto item = Json.emptyObject;
  item["id"] = jsonText(jsonGet(resource, "id"));
  item["kind"] = Json(kind);
  item["name"] = Json(attributeText(resource, "name"));
  auto mountName = attributeText(resource, "mountName");
  if (mountName.length == 0)
    throw new MicdnConfigException("mountName", "组件 " ~ item["id"].get!string ~ " 缺少挂载名");
  item["mountName"] = Json(mountName);
  item["remark"] = Json(attributeText(resource, "remark"));
  item["spec"] = spec;
  return item;
}

private void normalizeMaven(Json source, ref Json result) {
  auto section = objectAt(source, "maven");
  auto target = jsonGet(result, "maven");
  target["declared"] = Json(flag(section, "declared", false));
  target["base"] = Json(field(section, "base"));
  target["remotes"] = stringArrayJson(normalizeRemotes(jsonGet(section, "remotes")));
  target["snapshotRemote"] = Json(stripTrailingSlash(field(section, "snapshotRemote")));
  result["maven"] = target;
}

private void normalizeNpm(Json source, ref Json result) {
  auto section = objectAt(source, "npm");
  auto target = jsonGet(result, "npm");
  target["declared"] = Json(flag(section, "declared", false));
  target["base"] = Json(field(section, "base"));
  target["remotes"] = stringArrayJson(normalizeRemotes(jsonGet(section, "remotes")));
  target["devRemote"] = Json(stripTrailingSlash(field(section, "devRemote")));
  result["npm"] = target;
}

private void normalizeNative(Json source, ref Json result) {
  auto section = objectAt(source, "native");
  auto target = jsonGet(result, "native");
  target["declared"] = Json(flag(section, "declared", false));
  target["base"] = Json(field(section, "base"));
  result["native"] = target;
}

private void normalizeAuth(Json source, ref Json result) {
  auto section = objectAt(source, "auth");
  auto target = jsonGet(result, "auth");
  target["publishKey"] = Json(field(section, "publishKey"));
  target["downloadKey"] = Json(field(section, "downloadKey"));
  auto maxSize = field(section, "maxSize");
  target["maxSize"] = Json(maxSize.length > 0 ? maxSize : "64M");
  result["auth"] = target;
}

private void normalizeRepoSection(Json source, ref Json result, string name) {
  auto target = jsonGet(result, name);
  target["base"] = Json(field(objectAt(source, name), "base"));
  result[name] = target;
}

private void normalizeBlob(Json source, ref Json result) {
  auto section = objectAt(source, "blob");
  auto target = jsonGet(result, "blob");
  target["base"] = Json(field(section, "base"));
  auto maxSize = field(section, "maxSize");
  target["maxSize"] = Json(maxSize.length > 0 ? maxSize : "100M");
  target["publicImages"] = Json(flag(section, "publicImages", true));
  result["blob"] = target;
}

/// Micdn 部署节点只服务配置分发，不写进 micdn.xml。每个节点登记自己的
/// setline adminListen，setline sidecar 再把它们作为 peers 读取路由表。
private void normalizeServers(Json source, ref Json result) {
  auto raw = jsonGet(source, "servers");
  if (raw.type == Json.Type.undefined || raw.type == Json.Type.null_) {
    result["servers"] = Json.emptyArray;
    return;
  }
  if (raw.type != Json.Type.array)
    throw new MicdnConfigException("servers", "servers 必须是数组");

  bool[string] names;
  bool[string] listeners;
  Json[] servers;
  foreach (size_t i, ref item; raw) {
    auto fieldName = "servers[" ~ i.to!string ~ "]";
    if (item.type != Json.Type.object)
      throw new MicdnConfigException(fieldName, "服务器必须是对象");
    auto name = field(item, "name");
    validateSingleName(name, fieldName ~ ".name");
    if (name.toLower in names)
      throw new MicdnConfigException(fieldName ~ ".name", "服务器名称重复: " ~ name);
    names[name.toLower] = true;

    auto adminListen = normalizeAdminListen(field(item, "adminListen"), fieldName ~ ".adminListen");
    if (adminListen in listeners)
      throw new MicdnConfigException(fieldName ~ ".adminListen", "adminListen 重复: " ~ adminListen);
    listeners[adminListen] = true;

    auto server = Json.emptyObject;
    server["name"] = Json(name);
    server["adminListen"] = Json(adminListen);
    servers ~= server;
  }
  sort!((a, b) => nameBefore(field(a, "name"), field(b, "name")))(servers);
  result["servers"] = Json(servers);
}

private string normalizeAdminListen(string text, string fieldName) {
  auto value = text.strip;
  if (value.length == 0)
    throw new MicdnConfigException(fieldName, "adminListen 不能为空");

  string host;
  string portText;
  if (value[0] == '[') {
    auto close = value.indexOf(']');
    if (close <= 1 || close + 1 >= value.length || value[close + 1] != ':')
      throw new MicdnConfigException(fieldName, "adminListen 必须是 host:port");
    host = value[1 .. close];
    portText = value[close + 2 .. $];
  } else {
    auto colon = value.lastIndexOf(':');
    if (colon <= 0 || colon + 1 >= value.length)
      throw new MicdnConfigException(fieldName, "adminListen 必须是 host:port");
    host = value[0 .. colon];
    portText = value[colon + 1 .. $];
  }
  if (host.length == 0 || host == "0.0.0.0" || host == "*" || host == "::"
      || host.indexOf("/") >= 0)
    throw new MicdnConfigException(fieldName, "adminListen 必须使用节点可达地址");

  ushort port;
  try {
    port = portText.to!ushort;
  } catch (ConvException e) {
    throw new MicdnConfigException(fieldName, "adminListen 端口必须是数字");
  }
  if (port == 0)
    throw new MicdnConfigException(fieldName, "adminListen 端口必须在 1-65535 之间");
  return (host.indexOf(':') >= 0 ? "[" ~ host ~ "]" : host) ~ ":" ~ port.to!string;
}

private Json normalizeSource(Json source, string fieldName) {
  if (source.type != Json.Type.object)
    throw new MicdnConfigException(fieldName, "来源必须是对象");
  auto kind = field(source, "kind").toLower;
  if (kind != "jar" && kind != "npm" && kind != "dir" && kind != "zip")
    throw new MicdnConfigException(fieldName ~ ".kind", "未知来源类型: " ~ kind);
  auto ref_ = field(source, "ref");
  if (ref_.length == 0)
    throw new MicdnConfigException(fieldName ~ ".ref", "来源缺少 ref");
  auto inner = stripLeadingSlash(field(source, "inner"));
  validateInner(inner, fieldName ~ ".inner");
  if (kind == "jar" && !validGav(ref_))
    throw new MicdnConfigException(fieldName ~ ".ref", "jar 必须使用 groupId:artifactId:version");
  if (kind == "dir" && inner.length > 0)
    throw new MicdnConfigException(fieldName ~ ".inner", "dir 来源不支持 inner");
  auto result = Json.emptyObject;
  result["kind"] = Json(kind);
  result["ref"] = Json(ref_);
  result["inner"] = Json(inner);
  return result;
}

private void validateMicdnConfig(Json config) {
  auto listen = field(config, "listen");
  auto colon = listen.lastIndexOf(':');
  if (colon <= 0) {
    throw new MicdnConfigException("listen", "listen 必须是 host:port");
  }
  try {
    auto port = listen[colon + 1 .. $].to!ushort;
    if (port == 0)
      throw new MicdnConfigException("listen", "listen 端口必须在 1-65535 之间");
  } catch (ConvException e) {
    throw new MicdnConfigException("listen", "listen 端口必须是数字");
  }

  auto logLevel = field(config, "logLevel").toLower;
  if (!logLevels.canFind(logLevel))
    throw new MicdnConfigException("logLevel", "不支持的日志级别: " ~ logLevel);

  auto maven = jsonGet(config, "maven");
  if (flag(maven, "declared", false)) {
    effectiveBase(config, "maven", "/maven");
    validateRemotes(jsonGet(maven, "remotes"), "maven.remotes");
  }
  auto npm = jsonGet(config, "npm");
  if (flag(npm, "declared", false)) {
    effectiveBase(config, "npm", "/npm");
    validateRemotes(jsonGet(npm, "remotes"), "npm.remotes");
  }
  if (flag(jsonGet(config, "native"), "declared", false))
    effectiveBase(config, "native", "/native");

  auto auth = jsonGet(config, "auth");
  validateSize(field(auth, "maxSize"), "auth.maxSize");
  auto blob = jsonGet(config, "blob");
  validateSize(field(blob, "maxSize"), "blob.maxSize");
}

/// Blob 的 bucket 身份固定来自 Profile：名称取 `profile.name`，密钥取 `profile.key`。
/// 没有 key 时不生成 Blob；有 key 时 Profile 名必须能作为 bucket 名。
private void validateBlobIdentity(string profileName, string profileKey) {
  if (profileKey.strip.length == 0)
    return;
  validateSingleName(profileName.strip, "profile.name");
}

private string effectiveBase(Json config, string sectionName, string defaultSubDir) {
  auto base = field(jsonGet(config, sectionName), "base");
  if (base.length > 0)
    return base;
  auto home = field(config, "home");
  if (home.length > 0)
    return home ~ defaultSubDir;
  return defaultSubDir;
}

private Json sanitizeConfig(Json config) {
  auto result = copyJson(config);
  auto auth = jsonGet(result, "auth");
  auto publishSet = field(auth, "publishKey").length > 0;
  auto downloadSet = field(auth, "downloadKey").length > 0;
  auto clean = Json.emptyObject;
  clean["maxSize"] = jsonGet(auth, "maxSize");
  clean["publishKeySet"] = Json(publishSet);
  clean["downloadKeySet"] = Json(downloadSet);
  result["auth"] = clean;
  return result;
}

private void validateRemotes(Json remotes, string fieldName) {
  foreach (url; textList(remotes)) {
    if (url.indexOf("://") <= 0)
      throw new MicdnConfigException(fieldName, "上游地址必须是完整 URL: " ~ url);
  }
}

private void validateSize(string text, string fieldName) {
  if (text.length == 0)
    throw new MicdnConfigException(fieldName, "大小不能为空");
  auto value = text.toLower;
  if (value[$ - 1] == 'm' || value[$ - 1] == 'g')
    value = value[0 .. $ - 1];
  if (value.length == 0)
    throw new MicdnConfigException(fieldName, "大小格式应为 64M、1G 或字节数");
  foreach (c; value) {
    if (c < '0' || c > '9')
      throw new MicdnConfigException(fieldName, "大小格式应为 64M、1G 或字节数");
  }
}

private string[] normalizeRemotes(Json value) {
  string[] result;
  foreach (url; textList(value)) {
    auto clean = stripTrailingSlash(url.strip);
    if (clean.length > 0)
      result ~= clean;
  }
  return result;
}

private string[] textList(Json value) {
  string[] result;
  if (value.type == Json.Type.array) {
    foreach (ref item; value) {
      auto text = jsonText(item).strip;
      if (text.length > 0)
        result ~= text;
    }
  } else if (value.type == Json.Type.string) {
    foreach (line; split(value.get!string, '\n')) {
      auto text = line.strip;
      if (text.length > 0)
        result ~= text;
    }
  }
  return result;
}

private void sortBindings(ref BoundComponent[] components) {
  components.sort!((a, b) => a.sortno == b.sortno
      ? a.mountName < b.mountName
      : a.sortno < b.sortno);
}

/// Static bundle 与来源都使用固定排序，避免绑定表顺序或 JSON 数组顺序影响最终 XML。
private bool nameBefore(string left, string right) {
  auto leftLower = left.toLower;
  auto rightLower = right.toLower;
  return leftLower == rightLower ? left < right : leftLower < rightLower;
}

private int providerRank(string provider) {
  switch (provider) {
  case "jar":
    return 0;
  case "npm":
    return 1;
  case "dir":
    return 2;
  default:
    return 3;
  }
}

private bool sourceBefore(Json left, Json right) {
  auto leftProvider = field(left, "kind");
  auto rightProvider = field(right, "kind");
  auto leftRank = providerRank(leftProvider);
  auto rightRank = providerRank(rightProvider);
  if (leftRank != rightRank)
    return leftRank < rightRank;
  if (leftProvider != rightProvider)
    return leftProvider < rightProvider;
  auto leftRef = field(left, "ref");
  auto rightRef = field(right, "ref");
  if (leftRef != rightRef)
    return leftRef < rightRef;
  return field(left, "inner") < field(right, "inner");
}

/// 中间固定两个星号，保留首尾各两个字符，供页面与 XML 预览确认密钥已设置。
string maskSecret(string value) {
  if (value.length == 0)
    return "";
  if (value.length < 8)
    return "**";
  return value[0 .. 2] ~ "**" ~ value[$ - 2 .. $];
}

private Json objectAt(Json source, string name) {
  auto value = jsonGet(source, name);
  return value.type == Json.Type.object ? value : Json.emptyObject;
}

private void copyText(Json source, ref Json target, string key) {
  if (jsonGet(source, key).type != Json.Type.undefined)
    target[key] = Json(field(source, key));
}

private string field(Json obj, string key) {
  return jsonText(jsonGet(obj, key)).strip;
}

private string firstText(Json obj, string first, string second) {
  auto value = field(obj, first);
  return value.length > 0 ? value : field(obj, second);
}

private long numberField(Json obj, string key, long fallback) {
  auto value = jsonGet(obj, key);
  if (value.type == Json.Type.int_)
    return value.get!long;
  try {
    return field(obj, key).to!long;
  } catch (ConvException e) {
    return fallback;
  }
}

private bool flag(Json obj, string key, bool fallback) {
  auto value = jsonGet(obj, key);
  if (value.type == Json.Type.bool_)
    return value.get!bool;
  auto text = jsonText(value).toLower;
  if (text == "true" || text == "1" || text == "yes")
    return true;
  if (text == "false" || text == "0" || text == "no")
    return false;
  return fallback;
}

private Json copyJson(Json value) {
  auto text = value.toString;
  return parseJson(text);
}

private Json stringArrayJson(const string[] values) {
  Json[] items;
  foreach (value; values)
    items ~= Json(value);
  return Json(items);
}

private string stripTrailingSlash(string text) {
  while (text.length > 1 && text[$ - 1] == '/')
    text = text[0 .. $ - 1];
  return text;
}

private string stripLeadingSlash(string text) {
  while (text.length > 0 && text[0] == '/')
    text = text[1 .. $];
  return text;
}

private bool validGav(string gav) {
  auto parts = split(gav, ':');
  if (parts.length != 3)
    return false;
  foreach (part; parts) {
    if (part.length == 0)
      return false;
  }
  return true;
}

private void validateSingleName(string name, string fieldName) {
  if (name.length == 0 || name == "." || name == ".."
      || name.indexOf('/') >= 0 || name.indexOf('\\') >= 0)
    throw new MicdnConfigException(fieldName, "名称必须是非空单段路径");
}

private void validateDocName(string name, string fieldName) {
  if (name.length == 0 || name[0] == '/' || name[$ - 1] == '/')
    throw new MicdnConfigException(fieldName, "文档名不能以 / 开头或结尾");
  foreach (part; split(name, '/')) {
    if (part.length == 0 || part == "." || part == "..")
      throw new MicdnConfigException(fieldName, "文档名不能包含空段、. 或 ..");
  }
}

private void validateInner(string inner, string fieldName) {
  if (inner.length == 0)
    return;
  foreach (part; split(inner, '/')) {
    if (part.length == 0 || part == "." || part == "..")
      throw new MicdnConfigException(fieldName, "inner 不能包含空段、. 或 ..");
  }
}

private void putAttr(T)(ref T xml, string name, string value) {
  if (value.length == 0)
    return;
  xml.put(" ");
  xml.put(name);
  xml.put(`="`);
  xml.put(escapeXml(value));
  xml.put(`"`);
}
