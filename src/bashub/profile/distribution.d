/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.profile.distribution;
/// 配置分发端点的共同数据快照。server/proxy/menus/micdn/script 面对的
/// 都是同一组 Profile、Farm、Host、Engine、Webapp、Artifact 与 Server；
/// 每次请求按资源各取一次，再建 id 索引，避免模板渲染时逐行回查。

import bashub.present : gavOf;
import bashub.profile.resolver : ProfileContext, loadAll;

import beangle.data.resource : Registry;
import beangle.data.value : jsonText;
import beangle.jsonapi.document : attributeText, relationshipId, relationshipIds;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

/// 一次配置分发请求的只读数据。
struct ProfileData {
  ProfileContext profile;
  Json[] farms;
  Json[] hosts;
  Json[] webapps;
  Json[] servers;
  Json[] engines;
  Json[] artifacts;
  Json[string] farmsById;
  Json[string] hostsById;
  Json[string] serversById;
  Json[string] enginesById;
  Json[string] artifactsById;
}

/// 取 Profile 下的主体（farm/host/webapp）以及它们引用到的全局配置。表都很小，
/// 配置分发又是低频请求；一次全取再按引用收窄，比逐条回查更可预测，也少很多往返。
ProfileData loadProfileData(Store store, Registry reg, const ProfileContext context) {
  ProfileData data;
  data.profile = context;
  data.farms = loadAll(store, reg.find("farms"), ["profile": context.id]);
  data.hosts = loadAll(store, reg.find("hosts"), ["profile": context.id]);
  data.webapps = loadAll(store, reg.find("webapps"), ["profile": context.id]);

  auto engineIds = referencedIds(data.farms, "engine", false);
  auto serverIds = referencedIds(data.farms, "servers", true);
  foreach (id; referencedIds(data.webapps, "targets", true).keys)
    serverIds[id] = true;
  auto artifactIds = referencedIds(data.webapps, "artifact", false);

  data.servers = onlyReferenced(loadAll(store, reg.find("servers")), serverIds);
  data.engines = onlyReferenced(loadAll(store, reg.find("engines")), engineIds);
  data.artifacts = onlyReferenced(loadAll(store, reg.find("artifacts")), artifactIds);

  data.farmsById = index(data.farms);
  data.hostsById = index(data.hosts);
  data.serversById = index(data.servers);
  data.enginesById = index(data.engines);
  data.artifactsById = index(data.artifacts);
  return data;
}

/// webapp 的 GAV；构件缺失时返回空串。
string webappGav(Json webapp, const Json[string] artifactsById) {
  auto artifactId = relationshipId(webapp, "artifact");
  if (artifactId !in artifactsById)
    return "";
  return artifactGav(artifactsById[artifactId], attributeText(webapp, "version"));
}

/// 构件 GAV；参数来自 JSON:API attributes。
string artifactGav(Json artifact, string ver) {
  return gavOf(attributeText(artifact, "groupId"), attributeText(artifact, "artifactId"),
      attributeText(artifact, "packaging"), attributeText(artifact, "classifier"), ver);
}

private Json[string] index(Json[] items) {
  Json[string] byId;
  foreach (item; items)
    byId[jsonText(item["id"])] = item;
  return byId;
}

/// 收集资源引用到的 id。`many` 区分 to-one / to-many 关系。
private bool[string] referencedIds(Json[] resources, string relation, bool many) {
  bool[string] ids;
  foreach (resource; resources) {
    if (many) {
      foreach (id; relationshipIds(resource, relation))
        ids[id] = true;
    } else {
      auto id = relationshipId(resource, relation);
      if (id.length > 0)
        ids[id] = true;
    }
  }
  return ids;
}

/// 保留 id 命中引用集合的资源。
private Json[] onlyReferenced(Json[] resources, bool[string] ids) {
  Json[] selected;
  foreach (resource; resources) {
    if (jsonText(resource["id"]) in ids)
      selected ~= resource;
  }
  return selected;
}
