/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.profile.menus;
/// `GET /api/bashub/ems/{profile}/menus/{appName}`：按 Profile 部署的 webapp 找到 EMS 应用，
/// 再输出该应用的资源与菜单 XML。应用匹配口径与 Scala `EmsWS.menus` 一致：
/// `webapp.artifact.groupId == app.group.name` 且 `artifact.artifactId == app.artifactId`。

import bashub.menus : renderMenusXml;
import bashub.profile.distribution : loadProfileData;
import bashub.profile.resolver : ProfileContext, loadAll;

import beangle.data.resource : Registry;
import beangle.data.value : jsonText;
import beangle.jsonapi.document : attributeText, relationshipId;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.algorithm : sort;
import std.string : strip;

/// 找不到与当前 Profile 匹配的应用时返回空串（路由按 404 处理）。
string renderEmsMenus(Store store, Registry reg, const ProfileContext context, string appName) {
  auto name = appName.strip;
  if (name.length == 0)
    return "";

  auto apps = loadAll(store, reg.find("apps"), ["name": name]);
  if (apps.length == 0)
    return "";
  sort!((a, b) => jsonText(a["id"]) < jsonText(b["id"]))(apps);

  string[string] groupNames;
  foreach (group; loadAll(store, reg.find("app-groups")))
    groupNames[jsonText(group["id"])] = attributeText(group, "name");

  auto data = loadProfileData(store, reg, context);
  foreach (app; apps) {
    auto groupName = groupNames.get(relationshipId(app, "group"), "");
    auto appArtifactId = attributeText(app, "artifactId");
    foreach (webapp; data.webapps) {
      auto artifactId = relationshipId(webapp, "artifact");
      if (artifactId !in data.artifactsById)
        continue;
      auto artifact = data.artifactsById[artifactId];
      if (appArtifactId == attributeText(artifact, "artifactId") &&
          groupName == attributeText(artifact, "groupId"))
        return renderMenusXml(reg, store, jsonText(app["id"]));
    }
  }
  return "";
}
