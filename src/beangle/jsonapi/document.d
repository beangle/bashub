/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.jsonapi.document;
/// JSON:API 文档渲染（纯函数）：行（已按列类型转成 Json）→ `data` / `included` / `meta.page` / `errors`。
/// 前端只用到这套子集；sparse fieldsets、links、related 之类一概不做。

import beangle.data.resource;
import beangle.data.value;

import vibe.data.json : Json;

import std.array : appender;
import std.conv : to;
import std.string : indexOf, strip;

/// 目标 id → 目标行。
alias RowIndex = Json[string][string];
/// `资源type:关系名` → 目标 id → 目标行。派生属性与嵌套 include 都从这里取。
alias RelIndex = RowIndex[string];
/// 应用补充计算属性（如 gav、updatable）。框架只负责在文档成形前调用。
alias DecorateAttributes = void delegate(const Resource res, Row row, RelIndex relIndex, ref Json attributes);

/** 分页信息，对应 `meta.page`。 */
struct PageMeta {
  size_t number;
  size_t size;
  long total;
}

/// 一条资源对象。
Json resourceObject(Registry reg, const Resource res, Row row, RelIndex relIndex,
    DecorateAttributes decorate = null) {
  auto obj = Json.emptyObject;
  obj["type"] = Json(res.type);
  obj["id"] = Json(jsonText(rowGet(row, res.keyColumn)));

  auto attributes = Json.emptyObject;
  foreach (c; res.columns) {
    if (c.kind == Kind.id_)
      continue;
    auto v = rowGet(row, c.key);
    if (v.type == Json.Type.undefined)
      continue;
    attributes[c.attr] = v;
  }
  foreach (vl; res.valueLists) {
    auto v = rowGet(row, vl.attr);
    if (v.type != Json.Type.undefined)
      attributes[vl.attr] = v;
  }
  foreach (d; res.derived)
    attributes[d.attr] = Json(expandDerived(reg, res, d, row, relIndex));
  if (decorate !is null)
    decorate(res, row, relIndex, attributes);
  obj["attributes"] = attributes;

  auto relationships = Json.emptyObject;
  foreach (r; res.rels)
    relationships[r.attr] = relationshipObject(reg, r, row);
  foreach (mr; res.manyRels)
    relationships[mr.attr] = manyRelationshipObject(reg, mr, row);
  if (relationships.length > 0)
    obj["relationships"] = relationships;
  return obj;
}

private Json relationshipObject(Registry reg, const Relation r, Row row) {
  auto rel = Json.emptyObject;
  auto v = rowGet(row, r.attr);
  if (v.type == Json.Type.undefined || v.type == Json.Type.null_)
    rel["data"] = Json(null);
  else {
    auto id = Json.emptyObject;
    id["type"] = Json(reg.find(r.target).type);
    id["id"] = Json(jsonText(v));
    rel["data"] = id;
  }
  return rel;
}

/// to-many 关系：行里存的是目标 id 数组，文档里补上目标资源 type。
private Json manyRelationshipObject(Registry reg, const ManyRelation mr, Row row) {
  auto rel = Json.emptyObject;
  auto targetType = reg.find(mr.target).type;
  auto data = appender!(Json[])();
  auto v = rowGet(row, mr.attr);
  if (v.type == Json.Type.array) {
    foreach (ref item; v) {
      auto id = Json.emptyObject;
      id["type"] = Json(targetType);
      id["id"] = Json(jsonText(item));
      data.put(id);
    }
  }
  rel["data"] = Json(data.data);
  return rel;
}

/// 派生属性模板展开：`{name}` 取本行，`{org.name}` 取关系行；取不到就留空。
private string expandDerived(Registry reg, const Resource res, const Derived d, Row row, RelIndex relIndex) {
  auto sb = appender!string;
  auto text = d.templateText;
  size_t i = 0;
  while (i < text.length) {
    auto open = text.indexOf('{', i);
    if (open < 0) {
      sb.put(text[i .. $]);
      break;
    }
    auto close = text.indexOf('}', open);
    if (close < 0) {
      sb.put(text[i .. $]);
      break;
    }
    sb.put(text[i .. open]);
    auto expr = text[open + 1 .. close];
    auto dot = expr.indexOf('.');
    if (dot < 0) {
      sb.put(jsonText(rowGet(row, reg.keyOfAttr(res, expr))));
    } else {
      auto relName = expr[0 .. dot];
      auto sub = expr[dot + 1 .. $];
      sb.put(jsonText(relatedValue(reg, res, relName, sub, row, relIndex)));
    }
    i = close + 1;
  }
  return sb.data;
}

/// 关系行里的某个属性：`relIndex["<资源type>:<关系名>"][<外键值>][<属性>]`。
private Json relatedValue(Registry reg, const Resource res, string relName, string sub, Row row, RelIndex relIndex) {
  auto fk = jsonText(rowGet(row, relName));
  if (fk.length == 0)
    return Json.undefined;
  auto indexKey = res.type ~ ":" ~ relName;
  if (auto byId = indexKey in relIndex) {
    if (auto target = fk in *byId)
      return rowGet(*target, reg.keyOfAttr(reg.targetOf(res, relName), sub));
  }
  return Json.undefined;
}

/// 集合文档。
Json listDocument(Registry reg, const Resource res, Row[] rows, RelIndex relIndex, PageMeta page, Json[] included,
    DecorateAttributes decorate = null) {
  auto doc = Json.emptyObject;
  auto data = appender!(Json[])();
  foreach (row; rows)
    data.put(resourceObject(reg, res, row, relIndex, decorate));
  doc["data"] = Json(data.data);
  if (included.length > 0)
    doc["included"] = Json(included);
  auto meta = Json.emptyObject;
  auto p = Json.emptyObject;
  p["number"] = Json(page.number.to!long);
  p["size"] = Json(page.size.to!long);
  p["total"] = Json(page.total);
  meta["page"] = p;
  doc["meta"] = meta;
  return doc;
}

/// 单资源文档。
Json oneDocument(Registry reg, const Resource res, Row row, RelIndex relIndex, Json[] included,
    DecorateAttributes decorate = null) {
  auto doc = Json.emptyObject;
  doc["data"] = resourceObject(reg, res, row, relIndex, decorate);
  if (included.length > 0)
    doc["included"] = Json(included);
  return doc;
}

/// 资源对象的 attributes；不是对象时返回 undefined。
Json resourceAttributes(Json resource) {
  auto attributes = jsonGet(resource, "attributes");
  return attributes.type == Json.Type.object ? attributes : Json.undefined;
}

/// 读资源对象的属性文本；缺字段返回空串。
string attributeText(Json resource, string attr) {
  return jsonText(jsonGet(resourceAttributes(resource), attr));
}

/// 属性是否存在且非 null；区分「缺省」与「显式 false / 空串」时用。
bool hasAttribute(Json resource, string attr) {
  auto value = jsonGet(resourceAttributes(resource), attr);
  return value.type != Json.Type.undefined && value.type != Json.Type.null_;
}

/// 读布尔属性；缺省或无法识别时返回 fallback。
bool attributeBool(Json resource, string attr, bool fallback = false) {
  auto value = jsonGet(resourceAttributes(resource), attr);
  if (value.type == Json.Type.bool_)
    return value.get!bool;
  auto text = jsonText(value);
  if (text == "true")
    return true;
  if (text == "false")
    return false;
  return fallback;
}

/// 读数字属性；缺省或无法解析时返回 fallback。
long attributeLong(Json resource, string attr, long fallback = 0) {
  auto value = jsonGet(resourceAttributes(resource), attr);
  if (value.type == Json.Type.int_)
    return value.get!long;
  try {
    return jsonText(value).to!long;
  } catch (Exception e) {
    return fallback;
  }
}

/// 读字符串数组属性；去掉空白项，非数组返回空数组。
string[] attributeStrings(Json resource, string attr) {
  string[] values;
  auto value = jsonGet(resourceAttributes(resource), attr);
  if (value.type != Json.Type.array)
    return values;
  foreach (ref item; value) {
    auto text = jsonText(item).strip;
    if (text.length > 0)
      values ~= text;
  }
  return values;
}

/// 读 to-one 关系的 id；关系为空或格式不对返回空串。
string relationshipId(Json resource, string attr) {
  auto relationships = jsonGet(resource, "relationships");
  auto relation = jsonGet(relationships, attr);
  auto data = jsonGet(relation, "data");
  if (data.type != Json.Type.object)
    return "";
  return jsonText(jsonGet(data, "id"));
}

/// 读 to-many 关系的 id 列表；关系为空或格式不对返回空数组。
string[] relationshipIds(Json resource, string attr) {
  string[] ids;
  auto relationships = jsonGet(resource, "relationships");
  auto relation = jsonGet(relationships, attr);
  auto data = jsonGet(relation, "data");
  if (data.type != Json.Type.array)
    return ids;
  foreach (ref item; data) {
    auto id = jsonText(jsonGet(item, "id"));
    if (id.length > 0)
      ids ~= id;
  }
  return ids;
}

/// `errors[]`：400/404/500 用。
Json errorDocument(int status, string title, string detail = null, string parameter = null) {
  auto err = Json.emptyObject;
  err["status"] = Json(status.to!string);
  err["title"] = Json(title);
  if (detail.length > 0)
    err["detail"] = Json(detail);
  if (parameter.length > 0) {
    auto src = Json.emptyObject;
    src["parameter"] = Json(parameter);
    err["source"] = src;
  }
  auto doc = Json.emptyObject;
  doc["errors"] = Json([err]);
  return doc;
}

/// 未登录：与 bashub 同形（前端据此跳 CAS）。
Json unauthorizedDocument(string redirectUrl) {
  auto meta = Json.emptyObject;
  meta["redirectUrl"] = Json(redirectUrl);
  auto err = Json.emptyObject;
  err["status"] = Json("401");
  err["title"] = Json("请先登录");
  err["meta"] = meta;
  auto doc = Json.emptyObject;
  doc["errors"] = Json([err]);
  return doc;
}

/// 写操作成功。
Json okDocument() {
  auto doc = Json.emptyObject;
  doc["success"] = Json(true);
  return doc;
}
