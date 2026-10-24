/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.menus;
/// 菜单 XML 的导入/导出（scala `MenuWS` + `MenuServiceImpl`）。
///
/// XML 只描述「应用自己的资源与菜单」：资源按名字合并，菜单按 `(indexno,name)` 合并。
/// 导入不清空未出现在 XML 里的资源/菜单，与 scala 的增量合并口径一致。

import beangle.commons.xml : children, escapeXml, getAttrs, parseRoot;
import beangle.data.query : Query, parseQuery;
import beangle.data.resource : Registry, Resource;
import beangle.data.value : isBlank, jsonGet, jsonText;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.algorithm : canFind, sort;
import std.array : Appender, appender;
import std.string : strip, toLower;

/// 菜单动作的业务错误；`status` 直接给 web 层转成 HTTP 状态。
class MenuXmlException : Exception {
  int status;

  this(int status, string msg, string file = __FILE__, size_t line = __LINE__) @safe {
    super(msg, file, line);
    this.status = status;
  }
}

/// `GET menus/export?app=...` 的响应体：`{ "xml": "..." }`。
Json exportMenus(Registry reg, Store store, string appId) {
  auto result = Json.emptyObject;
  result["xml"] = Json(renderMenusXml(reg, store, appId));
  return result;
}

/// 指定应用的资源与菜单树，输出为菜单 XML 文本。
string renderMenusXml(Registry reg, Store store, string appId) {
  requireApp(reg, store, appId);
  auto resources = searchAll(store, reg.find("resources"), appId, "name");
  auto menus = searchAll(store, reg.find("menus"), appId, "indexno");

  string[string] resourceNames;
  Json[string] byId;
  string[][string] childrenByParent;
  foreach (ref doc; resources)
    resourceNames[jsonText(field(doc, "id", "resource.id"))] =
      jsonText(field(field(doc, "attributes", "resource"), "name", "resource.attributes"));

  foreach (ref doc; menus)
    byId[jsonText(field(doc, "id", "menu.id"))] = doc;

  foreach (ref doc; menus) {
    auto id = jsonText(field(doc, "id", "menu.id"));
    auto parent = relationshipId(doc, "parent");
    childrenByParent[parent] ~= id;
  }
  foreach (parent, ref childIds; childrenByParent)
    childIds.sort!((a, b) => menuLess(byId, a, b));

  auto sortedResources = resources.dup;
  sortedResources.sort!((a, b) =>
      jsonText(field(field(a, "attributes", "resource"), "name", "resource.attributes")) <
      jsonText(field(field(b, "attributes", "resource"), "name", "resource.attributes")));

  auto xml = appender!string;
  xml.put("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<project>\n  <resources>\n");
  foreach (ref resource; sortedResources) {
    auto attrs = field(resource, "attributes", "resource");
    auto name = jsonText(field(attrs, "name", "resource.attributes"));
    xml.put("    <resource name=\"" ~ escapeXml(name) ~ "\" title=\"" ~
        escapeXml(jsonText(field(attrs, "title", "resource.attributes"))) ~ "\"");
    auto scopeName = jsonText(field(attrs, "scope", "resource.attributes"));
    if (scopeName.length > 0 && scopeName != "Public")
      xml.put(" scope=\"" ~ escapeXml(scopeName) ~ "\"");
    if (jsonText(field(attrs, "enabled", "resource.attributes")) == "false")
      xml.put(" enabled=\"false\"");
    xml.put("/>\n");
  }
  xml.put("  </resources>\n");
  string[] roots;
  if (auto found = "" in childrenByParent)
    roots = *found;
  foreach (id; roots)
    appendMenu(xml, byId, childrenByParent, resourceNames, id, "  ");
  xml.put("</project>");
  return xml.data;
}

/// `POST menus/import`：按 XML 增量合并资源与菜单。
void importMenus(Registry reg, Store store, string appId, string xmlText) {
  requireApp(reg, store, appId);

  auto root = parseRoot(xmlText);
  auto resources = searchAll(store, reg.find("resources"), appId, "name");
  foreach (container; children(root, "resources")) {
    foreach (elem; children(container, "resource")) {
      auto attrs = getAttrs(elem);
      auto name = attrOf(attrs, "name");
      auto title = attrOf(attrs, "title");
      if (name.length == 0)
        throw new MenuXmlException(400, "resource name must not be empty");
      if (resourceExists(resources, name))
        continue;
      auto scopeName = attrOf(attrs, "scope");
      auto enabled = attrOf(attrs, "enabled");
      auto data = Json.emptyObject;
      data["type"] = Json("resources");
      auto values = Json.emptyObject;
      values["name"] = Json(name);
      values["title"] = Json(title);
      values["scope"] = Json(scopeName.length == 0 ? "Private" : scopeName);
      values["enabled"] = Json(enabled.length == 0 ? true : enabled.toLower == "true");
      data["attributes"] = values;
      auto relationships = Json.emptyObject;
      relationships["app"] = relationshipObject("apps", appId);
      data["relationships"] = relationships;
      auto body = Json.emptyObject;
      body["data"] = data;
      auto created = store.create(reg.find("resources"), body);
      resources ~= created["data"];
    }
  }

  auto menus = searchAll(store, reg.find("menus"), appId, "indexno");
  importMenuLevel(reg, store, appId, root, null, resources, menus);
}

private void importMenuLevel(Root)(Registry reg, Store store, string appId, ref Root root, string parentId,
    Json[] resources, ref Json[] menus) {
  foreach (elem; children(root, "menu")) {
    auto attrs = getAttrs(elem);
    auto indexno = attrOf(attrs, "indexno");
    auto name = attrOf(attrs, "name");
    if (name.length == 0)
      throw new MenuXmlException(400, "menu name must not be empty");

    auto existingIndex = findMenuIndex(menus, indexno, name);
    auto exists = existingIndex != size_t.max;
    auto existingId = exists ? jsonText(menus[existingIndex]["id"]) : "";
    auto enName = attrOf(attrs, "enName");
    if (enName.length == 0)
      enName = name;
    auto enabled = attrOf(attrs, "enabled");
    auto entryName = attrOf(attrs, "entry");
    auto entryId = findResourceId(resources, entryName);
    if (entryName.length > 0 && entryId.length == 0)
      throw new MenuXmlException(400, "menu entry resource not found: " ~ entryName);

    string[] resourceIds;
    if (exists) {
      foreach (id; relationshipIds(menus[existingIndex]["relationships"], "resources"))
        resourceIds ~= id;
    }
    auto linkedNames = splitNames(attrOf(attrs, "resources"));
    if (entryName.length > 0)
      linkedNames ~= entryName;
    foreach (linkedName; linkedNames) {
      auto id = findResourceId(resources, linkedName);
      if (id.length == 0)
        throw new MenuXmlException(400, "menu resource not found: " ~ linkedName);
      if (!resourceIds.canFind(id))
        resourceIds ~= id;
    }

    auto data = Json.emptyObject;
    data["type"] = Json("menus");
    auto values = Json.emptyObject;
    values["name"] = Json(name);
    values["enName"] = Json(enName);
    values["indexno"] = Json(indexno);
    auto params = attrOf(attrs, "params");
    values["params"] = params.length == 0 ? Json(null) : Json(params);
    values["enabled"] = Json(enabled.length == 0 ? true : enabled.toLower == "true");
    if ("fonticon" in attrs)
      values["fonticon"] = Json(attrOf(attrs, "fonticon"));
    data["attributes"] = values;

    auto relationships = Json.emptyObject;
    relationships["app"] = relationshipObject("apps", appId);
    relationships["parent"] = parentId.length == 0 ? nullRelationship() : relationshipObject("menus", parentId);
    relationships["entry"] = entryId.length == 0 ? nullRelationship() : relationshipObject("resources", entryId);
    relationships["resources"] = manyRelationshipObject("resources", resourceIds);
    data["relationships"] = relationships;
    auto body = Json.emptyObject;
    body["data"] = data;

    Json saved;
    if (!exists)
      saved = store.create(reg.find("menus"), body);
    else if (!store.update(reg.find("menus"), existingId, body, saved))
      throw new MenuXmlException(404, "menu not found: " ~ existingId);

    auto savedId = jsonText(saved["data"]["id"]);
    if (!exists)
      menus ~= saved["data"];
    else {
      auto idx = findMenuIndexById(menus, savedId);
      if (idx != size_t.max)
        menus[idx] = saved["data"];
    }
    foreach (container; children(elem, "children"))
      importMenuLevel(reg, store, appId, container, savedId, resources, menus);
  }
}

private Json[] searchAll(Store store, Resource res, string appId, string sortBy) {
  auto q = parseQuery(["filter[app]": appId, "sort": sortBy]);
  q.pageSize = 100000;
  return store.search(res, q)["data"].get!(Json[]);
}

private void requireApp(Registry reg, Store store, string appId) {
  if (appId.length == 0)
    throw new MenuXmlException(400, "app is required");
  Json app;
  if (!store.fetch(reg.find("apps"), appId, Query.init, app))
    throw new MenuXmlException(404, "app not found");
}

private bool resourceExists(Json[] resources, string name) {
  foreach (ref doc; resources) {
    if (jsonText(doc["attributes"]["name"]) == name)
      return true;
  }
  return false;
}

private string findResourceId(Json[] resources, string name) {
  if (name.length == 0)
    return "";
  foreach (ref doc; resources) {
    if (jsonText(doc["attributes"]["name"]) == name)
      return jsonText(doc["id"]);
  }
  return "";
}

private size_t findMenuIndex(Json[] menus, string indexno, string name) {
  foreach (i, doc; menus) {
    auto attrs = doc["attributes"];
    if (jsonText(attrs["indexno"]) == indexno && jsonText(attrs["name"]) == name)
      return i;
  }
  return size_t.max;
}

private size_t findMenuIndexById(Json[] menus, string id) {
  foreach (i, doc; menus) {
    if (jsonText(doc["id"]) == id)
      return i;
  }
  return size_t.max;
}

private string attrOf(string[string] attrs, string key) {
  if (auto value = key in attrs)
    return (*value).strip;
  return "";
}

private string[] splitNames(string text) {
  string[] names;
  size_t start = 0;
  foreach (i, c; text) {
    if (c == ',' || c == ';' || c == ' ' || c == '\t' || c == '\r' || c == '\n') {
      auto item = text[start .. i].strip;
      if (item.length > 0)
        names ~= item;
      start = i + 1;
    }
  }
  auto item = text[start .. $].strip;
  if (item.length > 0)
    names ~= item;
  return names;
}

private Json relationshipObject(string type, string id) {
  auto result = Json.emptyObject;
  auto data = Json.emptyObject;
  data["type"] = Json(type);
  data["id"] = Json(id);
  result["data"] = data;
  return result;
}

private Json nullRelationship() {
  auto result = Json.emptyObject;
  result["data"] = Json(null);
  return result;
}

private Json manyRelationshipObject(string type, string[] ids) {
  auto items = appender!(Json[])();
  foreach (id; ids) {
    auto data = Json.emptyObject;
    data["type"] = Json(type);
    data["id"] = Json(id);
    items.put(data);
  }
  auto result = Json.emptyObject;
  result["data"] = Json(items.data);
  return result;
}

private string relationshipId(Json doc, string name) {
  auto relationships = jsonGet(doc, "relationships");
  auto relationship = jsonGet(relationships, name);
  auto data = jsonGet(relationship, "data");
  return data.type == Json.Type.object ? jsonText(jsonGet(data, "id")) : "";
}

private Json field(Json owner, string key, string context) {
  if (owner.type != Json.Type.object)
    throw new Exception("expected object at " ~ context);
  return jsonGet(owner, key);
}

private string[] relationshipIds(Json relationships, string name) {
  string[] ids;
  auto relationship = jsonGet(relationships, name);
  auto data = jsonGet(relationship, "data");
  if (data.type != Json.Type.array)
    return ids;
  foreach (ref item; data)
    ids ~= jsonText(jsonGet(item, "id"));
  return ids;
}

private bool menuLess(Json[string] byId, string a, string b) {
  assert(a in byId, "missing menu id in export index: " ~ a);
  assert(b in byId, "missing menu id in export index: " ~ b);
  auto ai = jsonText(field(field(byId[a], "attributes", "menu"), "indexno", "menu.attributes"));
  auto bi = jsonText(field(field(byId[b], "attributes", "menu"), "indexno", "menu.attributes"));
  return ai != bi ? ai < bi : a < b;
}

private void appendMenu(ref Appender!string xml, Json[string] byId, string[][string] childrenByParent,
    string[string] resourceNames, string id, string indent) {
  assert(id in byId, "missing menu id in export index: " ~ id);
  auto menu = byId[id];
  auto attrs = field(menu, "attributes", "menu");
  auto entryId = relationshipId(menu, "entry");
  auto entryName = entryId in resourceNames ? resourceNames[entryId] : "";

  xml.put(indent ~ "<menu indexno=\"" ~
      escapeXml(jsonText(field(attrs, "indexno", "menu.attributes"))) ~
      "\" name=\"" ~ escapeXml(jsonText(field(attrs, "name", "menu.attributes"))) ~
      "\" enName=\"" ~ escapeXml(jsonText(field(attrs, "enName", "menu.attributes"))) ~ "\"");
  if (entryName.length > 0)
    xml.put(" entry=\"" ~ escapeXml(entryName) ~ "\"");
  auto params = field(attrs, "params", "menu.attributes");
  if (!isBlank(params))
    xml.put(" params=\"" ~ escapeXml(jsonText(params)) ~ "\"");
  auto fonticon = field(attrs, "fonticon", "menu.attributes");
  if (!isBlank(fonticon))
    xml.put(" fonticon=\"" ~ escapeXml(jsonText(fonticon)) ~ "\"");
  if (jsonText(field(attrs, "enabled", "menu.attributes")) == "false")
    xml.put(" enabled=\"false\"");

  string[] names;
  foreach (resourceId; relationshipIds(field(menu, "relationships", "menu"), "resources")) {
    if (resourceId != entryId) {
      if (auto name = resourceId in resourceNames)
        names ~= *name;
    }
  }
  names.sort;
  if (names.length > 0) {
    xml.put(" resources=\"");
    foreach (i, name; names) {
      if (i > 0)
        xml.put(",");
      xml.put(escapeXml(name));
    }
    xml.put("\"");
  }

  string[] childIds;
  if (auto found = id in childrenByParent)
    childIds = *found;
  if (childIds.length == 0) {
    xml.put("/>\n");
    return;
  }
  xml.put(">\n" ~ indent ~ "  <children>\n");
  foreach (childId; childIds)
    appendMenu(xml, byId, childrenByParent, resourceNames, childId, indent ~ "    ");
  xml.put(indent ~ "  </children>\n" ~ indent ~ "</menu>\n");
}
