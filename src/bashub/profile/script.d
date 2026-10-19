/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.profile.script;
/// `GET /api/{profile}/script/{host}`：生成主机检查脚本。
/// 与 Scala `ScriptWS` 同口径：按 Profile + Host.ip 找机器，递归收集特性的依赖，
/// 让依赖排在前面，再取该平台对应的脚本。排序遇到同优先级时按 id 固定，避免集合顺序漂移。

import bashub.profile.resolver : ProfileContext, loadAll;

import beangle.data.query : Query;
import beangle.data.resource : Registry;
import beangle.data.value : jsonText;
import beangle.jsonapi.document : attributeText, relationshipId, relationshipIds;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.algorithm : canFind, sort;
import std.array : appender;
import std.string : replace, strip, toLower;

/// 一个平台特性及其依赖。
struct ScriptFeature {
  string id;
  string name;
  string[] dependencies;
}

/// 某特性在某平台上的脚本；多个候选时取 id 最小的那条。
struct FeatureScript {
  string id;
  string featureId;
  string scripts;
}

/// 最终进入模板的一项。
struct ScriptItem {
  string featureName;
  string scripts;
}

/// 与 HTTP / 数据库无关的脚本模型。
struct HostScriptModel {
  string platformName;
  ScriptItem[] scripts;
}

/// 读取 Host、平台、特性与脚本并生成模型；Host 或平台不存在时返回 false。
bool loadHostScriptModel(Store store, Registry reg, const ProfileContext context, string hostIp,
    out HostScriptModel model) {
  auto ip = hostIp.strip;
  if (ip.length == 0)
    return false;

  Json host;
  bool found;
  foreach (candidate; loadAll(store, reg.find("hosts"), ["profile": context.id])) {
    if (attributeText(candidate, "ip") == ip) {
      host = candidate;
      found = true;
      break;
    }
  }
  if (!found)
    return false;

  auto platformId = relationshipId(host, "platform");
  if (platformId.length == 0)
    return false;
  Json platform;
  if (!store.fetch(reg.find("platforms"), platformId, Query.init, platform))
    return false;
  model.platformName = attributeText(platform["data"], "name");

  ScriptFeature[string] featureById;
  foreach (item; loadAll(store, reg.find("platform-features"))) {
    ScriptFeature feature;
    feature.id = jsonText(item["id"]);
    feature.name = attributeText(item, "name");
    feature.dependencies = relationshipIds(item, "dependencies");
    featureById[feature.id] = feature;
  }

  FeatureScript[] scripts;
  foreach (item; loadAll(store, reg.find("platform-feature-scripts"))) {
    if (relationshipId(item, "platform") != platformId)
      continue;
    FeatureScript script;
    script.id = jsonText(item["id"]);
    script.featureId = relationshipId(item, "feature");
    script.scripts = attributeText(item, "scripts");
    scripts ~= script;
  }

  auto roots = relationshipIds(host, "features");
  model.scripts = orderScripts(roots, featureById, scripts);
  return true;
}

/// 纯函数：依赖递归收集、优先级排序、平台脚本选取。
ScriptItem[] orderScripts(string[] rootIds, ScriptFeature[string] featureById,
    const FeatureScript[] scripts) {
  ScriptFeature[] collected;
  bool[string] visited;
  auto roots = rootIds.dup;
  roots.sort;
  foreach (id; roots)
    collectFeature(id, featureById, collected, visited);

  int[string] priorities;
  foreach (feature; collected)
    priorities[feature.id] = 1;
  int maxValue = cast(int) collected.length;
  foreach (feature; collected)
    cascadePriority(feature.id, featureById, priorities, maxValue);

  auto ordered = collected.dup;
  ordered.sort!((a, b) {
    auto pa = priorities.get(a.id, 1);
    auto pb = priorities.get(b.id, 1);
    return pa == pb ? a.id < b.id : pa > pb;
  });

  FeatureScript[string] chosen;
  foreach (script; scripts) {
    if (script.featureId !in featureById)
      continue;
    if (auto current = script.featureId in chosen) {
      if (script.id < current.id)
        chosen[script.featureId] = script;
    } else {
      chosen[script.featureId] = script;
    }
  }

  ScriptItem[] items;
  foreach (feature; ordered) {
    auto script = feature.id in chosen;
    if (script is null)
      continue;
    ScriptItem item;
    item.featureName = feature.name;
    item.scripts = script.scripts.replace("#!/bin/bash", "echo '正在检查" ~ feature.name ~ "....'");
    items ~= item;
  }
  return items;
}

/// 生成 bash 文本；格式对齐 Scala 的 `script/index.ftl`。
string renderBashScript(const HostScriptModel model) {
  auto platformName = model.platformName.toLower;
  auto sudoerGroup = platformName.canFind("fedora") || platformName.canFind("centos") ? "wheel" : "sudo";

  auto script = appender!string;
  script.put("#!/bin/bash\n\n");
  script.put("if [ \"$(id -u)\" == \"0\" ]; then\n");
  script.put("  echo \"检查脚本只能运行在拥有普通权限的sudoer用户下。\"\n");
  script.put("  exit 1\n");
  script.put("fi\n\n");
  script.put("if [[ ! \"$(id)\" == *\"(" ~ sudoerGroup ~ ")\"*  ]]; then\n");
  script.put("  echo \"当前用户不是sudoer,请使用root进行添加.\"\n");
  script.put("  me=\"$(whoami)\"\n");
  script.put("  echo \"Using:usermod -aG " ~ sudoerGroup ~ " $me\"\n");
  script.put("  exit 1\n");
  script.put("fi\n");
  foreach (item; model.scripts)
    script.put("\n" ~ item.scripts ~ "\n");
  return script.data;
}

/// 组合读取与渲染；Host / 平台不存在时返回空串，没有匹配脚本仍返回基础脚本。
string renderHostScript(Store store, Registry reg, const ProfileContext context, string hostIp) {
  HostScriptModel model;
  if (!loadHostScriptModel(store, reg, context, hostIp, model))
    return "";
  return renderBashScript(model);
}

private void collectFeature(string id, ScriptFeature[string] featureById, ref ScriptFeature[] collected,
    ref bool[string] visited) {
  if (id in visited)
    return;
  visited[id] = true;
  auto feature = id in featureById;
  if (feature is null)
    return;
  collected ~= *feature;
  auto dependencies = feature.dependencies.dup;
  dependencies.sort;
  foreach (dependency; dependencies)
    collectFeature(dependency, featureById, collected, visited);
}

private void cascadePriority(string id, ScriptFeature[string] featureById, ref int[string] priorities,
    int maxValue) {
  auto feature = id in featureById;
  if (feature is null)
    return;
  auto dependencies = feature.dependencies.dup;
  dependencies.sort;
  foreach (dependency; dependencies) {
    if (dependency !in featureById)
      continue;
    auto oldValue = priorities.get(dependency, 1);
    if (oldValue < maxValue) {
      priorities[dependency] = oldValue + 1;
      cascadePriority(dependency, featureById, priorities, maxValue);
    }
  }
}
