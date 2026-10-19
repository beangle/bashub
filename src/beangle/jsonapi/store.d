/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.jsonapi.store;
/// 服务层：把「资源定义 + 查询/写入请求」编成对 Dao 的调用，再渲染成 JSON:API 文档。
/// Scala 侧的对应物是 `EntityAction` + `JsonAPIHelper` + 各 `*WS` 的 `afterPopulate`，
/// 这里没有实体与反射，只有「行」与显式的列映射。

import beangle.data.dao;
import beangle.jsonapi.document;
import beangle.data.plan;
import beangle.data.query;
import beangle.data.resource;
import beangle.data.value;

import vibe.data.json : Json;

import std.algorithm : canFind;
import std.array : appender, join, split;
import std.conv : to, ConvException;
import std.string : indexOf, strip;

/** 写入数据非法（属性名不认识、id 不是数字等）——web 层转成 400。 */
class StoreException : Exception {
  string attribute;

  this(string attribute, string msg, string file = __FILE__, size_t line = __LINE__) @safe {
    super(msg, file, line);
    this.attribute = attribute;
  }
}

/** 建行前的默认值钩子：应用在这里补「服务端生成」的列（凭证、序号之类）。
 *
 * 传 `ref Row values` 而不是返回新行：调用方刚解析完请求体，正是要改的那份。
 */
alias FillDefaults = void delegate(const Resource res, ref Row values);

/** 写入前的应用钩子：可以补值、规范化，也可以在落库前抛 `StoreException` 做业务校验。 */
alias BeforeWrite = void delegate(const Resource res, string id, bool creating, ref Row values);

/** 写入后的应用钩子：主行与集合都已落库，仍在同一个事务里；适合同步反向关系。 */
alias AfterWrite = void delegate(const Resource res, string id, bool creating, Json body);

class Store {
  private Registry reg;
  private Dao dao;

  /// 建行前的默认值钩子（可空）
  FillDefaults fillDefaults;
  /// 写入前钩子（可空）
  BeforeWrite beforeWrite;
  /// 写入后钩子（可空）
  AfterWrite afterWrite;
  /// 文档属性装饰钩子（可空）：应用在这里补 gav、updatable 之类无法用模板表达的字段。
  DecorateAttributes decorateAttributes;

  this(Registry reg, Dao dao) {
    this.reg = reg;
    this.dao = dao;
  }

  /// 供健康检查/日志用的后端名。
  string backend() const {
    return dao.backend;
  }

  /// 列表：计划 → 取行 → 预取关系行 → JSON:API 集合文档。
  Json search(const Resource res, const Query q) {
    auto plan = buildPlan(reg, res, q);
    long total;
    auto rows = dao.select(res, plan, total);
    foreach (ref row; rows)
      normalizeEnums(res, row);
    loadCollections(res, rows);
    auto idx = loadRelIndex(res, rows);
    auto included = collectIncluded(res, q.includes, rows, idx);
    return listDocument(reg, res, rows, idx, PageMeta(q.pageNumber, q.pageSize, total), included, decorateAttributes);
  }

  /// 详情；不存在返回 false（调用方转 404）。
  bool fetch(const Resource res, string id, const Query q, out Json document) {
    auto row = dao.findById(res, id);
    if (row.length == 0)
      return false;
    normalizeEnums(res, row);
    auto rows = [row];
    loadCollections(res, rows);
    auto idx = loadRelIndex(res, rows);
    auto included = collectIncluded(res, q.includes, rows, idx);
    document = oneDocument(reg, res, rows[0], idx, included, decorateAttributes);
    return true;
  }

  /// 取数据库原始行（不经过属性装饰、密钥脱敏和关系展开）。
  ///
  /// 只给必须在服务端读取敏感列（如私钥）的机器配置端点使用；管理台仍走 `fetch`。
  bool fetchRaw(const Resource res, string id, out Row row) {
    row = dao.findById(res, id);
    return row.length > 0;
  }

  /// 新建：补默认值、落库，然后重新读一遍（拿到库端默认值与派生属性）。
  Json create(const Resource res, Json body) {
    auto write = parseWrite(res, body, true);
    if (fillDefaults !is null)
      fillDefaults(res, write.values);
    if (beforeWrite !is null)
      beforeWrite(res, "", true, write.values);
    validateRequired(res, write, true);
    string id;
    dao.transaction({
      id = dao.insert(res, write.values);
      applyCollections(res, id, write);
      if (afterWrite !is null)
        afterWrite(res, id, true, body);
    });
    Json doc;
    if (!fetch(res, id, Query.init, doc))
      throw new StoreException(null, "created row cannot be read back: " ~ res.path ~ "/" ~ id);
    return doc;
  }

  /// 修改；不存在返回 false。
  bool update(const Resource res, string id, Json body, out Json document) {
    auto write = parseWrite(res, body, false);
    if (beforeWrite !is null)
      beforeWrite(res, id, false, write.values);
    validateRequired(res, write, false);
    bool hit;
    dao.transaction({
      hit = dao.update(res, id, write.values);
      if (hit) {
        applyCollections(res, id, write);
        if (afterWrite !is null)
          afterWrite(res, id, false, body);
      }
    });
    if (!hit)
      return false;
    return fetch(res, id, Query.init, document);
  }

  /// 删除；返回是否命中。
  bool remove(const Resource res, string id) {
    bool hit;
    dao.transaction({
      if (dao.findById(res, id).length == 0)
        return;
      foreach (vl; res.valueLists)
        dao.replaceValues(res, vl, id, []);
      foreach (mr; res.manyRels) {
        if (mr.writable)
          dao.replaceMany(res, mr, id, []);
      }
      hit = dao.remove(res, id);
    });
    return hit;
  }

  /// 应用自己的动作直接改若干列（`values` 用行键），返回是否命中。
  ///
  /// 通用 CRUD 走 `update()`（JSON:API 请求体 → 行键）；像「重置凭证」这种只改一列的定制动作
  /// 由应用直接用这个，不必为了改一列去凑一份 JSON:API 文档。
  bool updateColumns(const Resource res, string id, Row values) {
    return dao.update(res, id, values);
  }

  /// 按指定主键写入：不存在则插入，存在则更新。用于 `profile_id` 这类天然主键。
  bool upsertColumns(const Resource res, string id, Row values) {
    if (dao.findById(res, id).length == 0) {
      values[res.keyColumn] = Json(id);
      dao.insert(res, values);
      return true;
    }
    return dao.update(res, id, values);
  }

  /// 直接插入一行，返回新 id；调用方负责事务边界。
  string insertColumns(const Resource res, Row values) {
    return dao.insert(res, values);
  }

  /// 直接删除一行；调用方负责事务边界。
  bool removeColumns(const Resource res, string id) {
    return dao.remove(res, id);
  }

  /// 在一个事务里执行应用自己的聚合写操作。
  void transaction(void delegate() work) {
    dao.transaction(work);
  }

  /// 预取所有 to-one 关系行，供「派生属性」与 `include` 使用。
  /// 一次查询取一批 id，不随列表长度放大查询次数。
  RelIndex loadRelIndex(const Resource res, Row[] rows) {
    RelIndex idx;
    foreach (rel; res.rels) {
      auto target = reg.find(rel.target);
      if (target.path.length == 0)
        continue;
      auto ids = appender!(string[])();
      foreach (row; rows) {
        auto id = jsonText(rowGet(row, rel.attr));
        if (id.length > 0 && !ids.data.canFind(id))
          ids.put(id);
      }
      if (ids.data.length == 0)
        continue;
      RowIndex byId;
      auto trows = dao.selectByIds(target, ids.data);
      foreach (ref trow; trows) {
        normalizeEnums(target, trow);
        byId[jsonText(rowGet(trow, target.keyColumn))] = trow;
      }
      idx[res.type ~ ":" ~ rel.attr] = byId;
    }
    return idx;
  }

  /// 读出来的枚举下标转成 JSON:API 的名字（`2` → `Private`）；越界就原样保留，交给前端显示异常值。
  private void normalizeEnums(const Resource res, ref Row row) {
    foreach (c; res.columns) {
      if (c.names.length == 0)
        continue;
      auto v = rowGet(row, c.key);
      if (isBlank(v))
        continue;
      try {
        auto idx = jsonText(v).to!long;
        if (idx >= 0 && idx < c.names.length)
          row[c.key] = Json(c.names[cast(size_t) idx]);
      } catch (ConvException e) {
        // 库里的值不是数字（手工改过表）：保持原样，不在读路径上放大成 500
      }
    }
  }

  /// 列表/详情共用的集合预取：每个集合一条查询，不按行逐个查。
  private void loadCollections(const Resource res, Row[] rows) {
    if (rows.length == 0)
      return;
    auto ids = appender!(string[])();
    foreach (row; rows) {
      auto id = jsonText(rowGet(row, res.keyColumn));
      if (id.length > 0 && !ids.data.canFind(id))
        ids.put(id);
    }
    if (ids.data.length == 0)
      return;

    string[] none;
    foreach (vl; res.valueLists) {
      auto grouped = dao.selectValues(res, vl, ids.data);
      foreach (ref row; rows) {
        auto id = jsonText(rowGet(row, res.keyColumn));
        auto values = id in grouped;
        row[vl.attr] = jsonStringArray(values is null ? none : *values);
      }
    }
    foreach (mr; res.manyRels) {
      auto grouped = dao.selectMany(res, mr, ids.data);
      foreach (ref row; rows) {
        auto id = jsonText(rowGet(row, res.keyColumn));
        auto values = id in grouped;
        row[mr.attr] = jsonStringArray(values is null ? none : *values);
      }
    }
  }

  /// 集合只在请求明确带上时替换；没带的集合保持原样。
  private void applyCollections(const Resource res, string ownerId, ref WriteSet write) {
    foreach (vl; res.valueLists) {
      if (auto values = vl.attr in write.valueLists)
        dao.replaceValues(res, vl, ownerId, *values);
    }
    foreach (mr; res.manyRels) {
      if (auto ids = mr.attr in write.manyRels)
        dao.replaceMany(res, mr, ownerId, *ids);
    }
  }

  /// `include=a,b`：把关系行也塞进 `included`（按 type:id 去重，顺序稳定）。
  /// 名称可以带点（`servers.host`），to-one 与 to-many 都按第一段展开。
  private Json[] collectIncluded(const Resource res, const string[] includes, Row[] rows, RelIndex idx) {
    Json[] included;
    bool[string] seen;
    foreach (name; includes)
      collectInclude(res, name, rows, idx, included, seen);
    return included;
  }

  private void collectInclude(const Resource res, string path, Row[] rows, RelIndex idx,
      ref Json[] included, ref bool[string] seen) {
    auto dot = path.indexOf('.');
    auto head = dot < 0 ? path : path[0 .. dot];
    auto rest = dot < 0 ? "" : path[dot + 1 .. $];

    if (auto rel = reg.findRel(res, head)) {
      auto target = reg.find(rel.target);
      Row[] targets;
      foreach (row; rows) {
        auto id = jsonText(rowGet(row, rel.attr));
        if (id.length == 0)
          continue;
        if (auto index = (res.type ~ ":" ~ rel.attr) in idx) {
          if (auto trow = id in *index)
            targets ~= *trow;
        }
      }
      auto targetIdx = appendIncluded(target, targets, included, seen);
      if (rest.length > 0 && targets.length > 0)
        collectInclude(target, rest, targets, targetIdx, included, seen);
      return;
    }

    auto many = findManyByAttr(res, head);
    if (many is null)
      return;
    auto target = reg.find(many.target);
    auto ids = appender!(string[])();
    foreach (row; rows) {
      auto linked = rowGet(row, many.attr);
      if (linked.type != Json.Type.array)
        continue;
      foreach (ref item; linked) {
        auto id = jsonText(item);
        if (id.length > 0 && !ids.data.canFind(id))
          ids.put(id);
      }
    }
    Row[] targetRows = dao.selectByIds(target, ids.data);
    foreach (ref targetRow; targetRows)
      normalizeEnums(target, targetRow);
    auto targetIdx = appendIncluded(target, targetRows, included, seen);
    if (rest.length > 0 && targetRows.length > 0)
      collectInclude(target, rest, targetRows, targetIdx, included, seen);
  }

  private RelIndex appendIncluded(const Resource target, Row[] rows, ref Json[] included, ref bool[string] seen) {
    auto relIndex = loadRelIndex(target, rows);
    foreach (row; rows) {
      auto id = jsonText(rowGet(row, target.keyColumn));
      if (id.length == 0)
        continue;
      auto key = target.type ~ ":" ~ id;
      if (key in seen)
        continue;
      seen[key] = true;
      included ~= resourceObject(reg, target, row, relIndex, decorateAttributes);
    }
    return relIndex;
  }

  /// JSON:API 写入体 → 行键。未知属性一律拒绝，避免静默丢字段；只读列静默忽略。
  private WriteSet parseWrite(const Resource res, Json body, bool creating) {
    WriteSet write;
    auto data = jsonGet(body, "data");
    if (data.type != Json.Type.object)
      throw new StoreException("data", "request body must contain a JSON:API `data` object");

    if (auto attributes = "attributes" in data) {
      if (attributes.type != Json.Type.undefined) {
        foreach (string attr, ref Json value; *attributes) {
          if (findValueListByAttr(res, attr) !is null) {
            write.valueLists[attr] = parseStringList(attr, value);
            continue;
          }
          auto c = findColumnByAttr(res, attr);
          if (c is null)
            throw new StoreException(attr, "unknown attribute: " ~ attr);
          if (!c.writable)
            continue;
          if (c.names.length > 0)
            value = Json(enumOrdinal(c, attr, value));
          else
            value = normalizeColumnValue(c, attr, value);
          write.values[c.key] = value;
        }
      }
    }

    if (auto rels = "relationships" in data) {
      if (rels.type != Json.Type.undefined) {
        foreach (string attr, ref Json value; *rels) {
          auto rel = reg.findRel(res, attr);
          auto relData = jsonGet(value, "data");
          if (rel !is null) {
            if (relData.type == Json.Type.null_) {
              write.values[rel.attr] = Json(null);
            } else if (relData.type == Json.Type.object) {
              write.values[rel.attr] = Json(relationshipId(attr, relData));
            } else {
              throw new StoreException(attr, "relationship `" ~ attr ~ "` must be a to-one object");
            }
            continue;
          }
          auto many = findManyByAttr(res, attr);
          if (many !is null) {
            if (!many.writable)
              throw new StoreException(attr, "relationship `" ~ attr ~ "` is read-only");
            write.manyRels[attr] = parseRelationshipIds(attr, relData);
            continue;
          }
          throw new StoreException(attr, "unknown relationship: " ~ attr);
        }
      }
    }
    if (creating)
      write.values.remove(res.keyColumn);
    return write;
  }

  /// 必填校验放在默认值与 beforeWrite 之后，允许钩子补值；PATCH 只校验请求里出现的字段。
  private void validateRequired(const Resource res, ref WriteSet write, bool creating) {
    foreach (attr; res.required) {
      if (auto c = findColumnByAttr(res, attr)) {
        if (auto value = c.key in write.values) {
          if (isMissingValue(*value))
            throw new StoreException(attr, "attribute `" ~ attr ~ "` is required");
        } else if (creating) {
          throw new StoreException(attr, "attribute `" ~ attr ~ "` is required");
        }
        continue;
      }
      if (reg.findRel(res, attr) !is null) {
        if (auto value = attr in write.values) {
          if (isMissingValue(*value))
            throw new StoreException(attr, "relationship `" ~ attr ~ "` is required");
        } else if (creating) {
          throw new StoreException(attr, "relationship `" ~ attr ~ "` is required");
        }
        continue;
      }
      if (findValueListByAttr(res, attr) !is null) {
        if (auto values = attr in write.valueLists) {
          if ((*values).length == 0)
            throw new StoreException(attr, "attribute `" ~ attr ~ "` is required");
        } else if (creating) {
          throw new StoreException(attr, "attribute `" ~ attr ~ "` is required");
        }
        continue;
      }
      // 必填清单与资源定义不一致属于配置错误，不能悄悄放过。
      throw new StoreException(attr, "required field is not defined on resource `" ~ res.path ~ "`: " ~ attr);
    }
  }
}

private bool isMissingValue(Json value) {
  if (isBlank(value))
    return true;
  if (value.type == Json.Type.string)
    return value.get!string.strip.length == 0;
  if (value.type == Json.Type.array)
    return value.length == 0;
  return false;
}

/// 一次写入里的行值与集合变更。集合必须等主行落库拿到 id 后才能写。
private struct WriteSet {
  Row values;
  string[][string] valueLists;
  string[][string] manyRels;
}

/// 文本枚举 → 库里存的下标；名字不认识就 400（静默写 0 会把权限范围写错）。
private long enumOrdinal(const Column* c, string attr, Json value) {
  if (value.type != Json.Type.string)
    throw new StoreException(attr, "attribute `" ~ attr ~ "` must be one of: " ~ c.names.join(", "));
  auto name = value.get!string;
  foreach (i, candidate; c.names) {
    if (candidate == name)
      return cast(long) i;
  }
  throw new StoreException(attr, "unknown value for `" ~ attr ~ "`: " ~ name);
}

/// 让内存后端与 PostgreSQL 的读回类型一致：文本列统一字符串、数字列统一整数。
private Json normalizeColumnValue(const Column* c, string attr, Json value) {
  if (isBlank(value))
    return value;
  final switch (c.kind) {
  case Kind.id_:
  case Kind.text:
    return value.type == Json.Type.string ? value : Json(jsonText(value));
  case Kind.number:
    if (value.type == Json.Type.int_)
      return value;
    if (value.type == Json.Type.string) {
      try {
        return Json(value.get!string.to!long);
      } catch (ConvException e) {
        throw new StoreException(attr, "attribute `" ~ attr ~ "` must be a number");
      }
    }
    throw new StoreException(attr, "attribute `" ~ attr ~ "` must be a number");
  case Kind.date:
  case Kind.datetime:
    if (value.type == Json.Type.string)
      return value;
    throw new StoreException(attr, "attribute `" ~ attr ~ "` must be a date/time string");
  case Kind.boolean:
    if (value.type == Json.Type.bool_)
      return value;
    if (value.type == Json.Type.string) {
      auto text = value.get!string.strip;
      if (text == "true" || text == "false")
        return Json(text == "true");
    }
    throw new StoreException(attr, "attribute `" ~ attr ~ "` must be a boolean");
  case Kind.jsonArray:
    return jsonStringArray(parseStringList(attr, value));
  case Kind.jsonDocument:
    if (value.type == Json.Type.object || value.type == Json.Type.array)
      return value;
    throw new StoreException(attr, "attribute `" ~ attr ~ "` must be a JSON object or array");
  }
}

/// 按 JSON:API 属性名找列。
private const(Column)* findColumnByAttr(const Resource res, string attr) {
  foreach (ref c; res.columns) {
    if (c.attr == attr)
      return &c;
  }
  return null;
}

/// 按 JSON:API 属性名找多值子表。
private const(ValueList)* findValueListByAttr(const Resource res, string attr) {
  foreach (ref vl; res.valueLists) {
    if (vl.attr == attr)
      return &vl;
  }
  return null;
}

/// 按 JSON:API 关联名找 to-many 关系。
private const(ManyRelation)* findManyByAttr(const Resource res, string attr) {
  foreach (ref mr; res.manyRels) {
    if (mr.attr == attr)
      return &mr;
  }
  return null;
}

/// 前端 `lines` 控件发的是换行分隔的字符串；API 也接受字符串数组，两种都归一成数组。
private string[] parseStringList(string attr, Json value) {
  string[] values;
  if (isBlank(value))
    return values;
  if (value.type == Json.Type.string) {
    foreach (line; split(value.get!string, '\n')) {
      auto text = line.strip;
      if (text.length > 0)
        values ~= text;
    }
    return values;
  }
  if (value.type == Json.Type.array) {
    foreach (ref item; value) {
      if (item.type != Json.Type.string)
        throw new StoreException(attr, "attribute `" ~ attr ~ "` must be a string array");
      auto text = item.get!string.strip;
      if (text.length > 0)
        values ~= text;
    }
    return values;
  }
  throw new StoreException(attr, "attribute `" ~ attr ~ "` must be a string array or newline-separated text");
}

private string[] parseRelationshipIds(string attr, Json data) {
  string[] ids;
  if (isBlank(data))
    return ids;
  if (data.type != Json.Type.array)
    throw new StoreException(attr, "relationship `" ~ attr ~ "` must be an array");
  foreach (ref item; data) {
    if (item.type != Json.Type.object)
      throw new StoreException(attr, "relationship `" ~ attr ~ "` requires data[].id");
    ids ~= relationshipId(attr, item);
  }
  return ids;
}

private string relationshipId(string attr, Json data) {
  auto id = jsonText(jsonGet(data, "id"));
  if (id.length == 0)
    throw new StoreException(attr, "relationship `" ~ attr ~ "` requires data.id");
  return id;
}

private Json jsonStringArray(const string[] values) {
  auto items = appender!(Json[])();
  foreach (value; values)
    items.put(Json(value));
  return Json(items.data);
}
