/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data.dao.memory;
/// 内存 DAO：把资源定义当表、把行放在内存里，用同一套 Plan 语义过滤/排序/分页。
/// 存在的意义有两个：应用没有可用库时也能把整条链路（路由 → 计划 → 文档）跑通；
/// 同时它是 `Plan` 语义的一份可执行说明书——postgres 后端生成的 SQL 应该给出一样的结果。
///
/// 行由应用用 `seed()` 灌入，本模块不认识任何具体业务表。

import beangle.data.dao;
import beangle.data.plan;
import beangle.data.resource;
import beangle.data.schema : SchemaIssue;
import beangle.data.value;

import vibe.data.json : Json;

import std.algorithm : sort;
import std.array : appender;
import std.conv : to;
import std.regex : matchFirst, regex;
import std.string : endsWith, indexOf, startsWith;

class MemoryDao : Dao {
  private Registry reg;
  /// path|id → 行
  private Row[string] rows;
  /// path|attr|id → 多值子表的值
  private string[][string] valueStore;
  /// path|attr|id → to-many 关联的目标 id
  private string[][string] manyStore;
  private long[string] sequences;

  this(Registry reg) {
    this.reg = reg;
  }

  string backend() const {
    return "memory";
  }

  SchemaIssue[] checkSchema(Registry reg) {
    return null;
  }

  /// 预置一行；返回它的 id（缺列用 undefined，与 db 侧的「不写这列」等价）。
  string seed(const Resource res, Row row) {
    auto id = jsonText(rowGet(row, res.keyColumn));
    if (id.length == 0)
      throw new DaoException("seed row of " ~ res.path ~ " has no " ~ res.keyColumn);
    rows[slot(res.path, id)] = row;
    // 读 AA 里可能不存在的键要用 get：新 druntime 下 `aa[missing]` 会抛 RangeError
    auto n = id.to!long;
    if (n > sequences.get(res.path, 0L))
      sequences[res.path] = n;
    return id;
  }

  /// 当前表里的全部行（测试与调试用）。
  Row[] allRows(const Resource res) {
    Row[] list;
    foreach (key, row; rows) {
      if (key.startsWith(res.path ~ "|"))
        list ~= row;
    }
    return list;
  }

  Row[] select(const Resource res, const Plan p, out long total) {
    auto matched = filterRows(res, p);
    total = matched.length;
    if (p.limit > 0) {
      auto start = p.offset < matched.length ? p.offset : matched.length;
      auto end = start + p.limit < matched.length ? start + p.limit : matched.length;
      return matched[start .. end];
    }
    return matched;
  }

  Row[] selectByIds(const Resource res, const string[] ids) {
    Row[] list;
    foreach (id; ids) {
      if (auto row = slot(res.path, id) in rows)
        list ~= *row;
    }
    return list;
  }

  Row findById(const Resource res, string id) {
    if (auto row = slot(res.path, id) in rows)
      return *row;
    return emptyRow();
  }

  /// 测试用：预置多值子表（`cfg_engines_listeners` 这类）。
  void seedValues(const Resource res, string attr, string ownerId, const string[] values) {
    valueStore[storeSlot(res.path, attr, ownerId)] = values.dup;
  }

  /// 测试用：预置 to-many 关联（`cfg_farms_servers` 这类）。
  void seedMany(const Resource res, string attr, string ownerId, const string[] targetIds) {
    manyStore[storeSlot(res.path, attr, ownerId)] = targetIds.dup;
  }

  string[][string] selectValues(const Resource res, const ValueList vl, const string[] ownerIds) {
    string[][string] grouped;
    foreach (id; ownerIds) {
      if (auto values = storeSlot(res.path, vl.attr, id) in valueStore)
        grouped[id] = *values;
    }
    return grouped;
  }

  string[][string] selectMany(const Resource res, const ManyRelation mr, const string[] ownerIds) {
    string[][string] grouped;
    foreach (id; ownerIds) {
      if (auto values = storeSlot(res.path, mr.attr, id) in manyStore)
        grouped[id] = *values;
    }
    return grouped;
  }

  void replaceValues(const Resource res, const ValueList vl, string ownerId, const string[] values) {
    valueStore[storeSlot(res.path, vl.attr, ownerId)] = values.dup;
  }

  void replaceMany(const Resource res, const ManyRelation mr, string ownerId, const string[] targetIds) {
    manyStore[storeSlot(res.path, mr.attr, ownerId)] = targetIds.dup;
  }

  /// 内存后端也遵守事务语义：失败时恢复 `work` 之前的全部状态。
  void transaction(void delegate() work) {
    auto savedRows = rows.dup;
    auto savedValues = valueStore.dup;
    auto savedMany = manyStore.dup;
    auto savedSequences = sequences.dup;
    try {
      work();
    } catch (Exception e) {
      rows = savedRows;
      valueStore = savedValues;
      manyStore = savedMany;
      sequences = savedSequences;
      throw e;
    }
  }

  string insert(const Resource res, Row values) {
    string id;
    if (auto provided = res.keyColumn in values)
      id = isBlank(*provided) ? "" : jsonText(*provided);
    if (id.length == 0) {
      auto next = sequences.get(res.path, 0L) + 1;
      sequences[res.path] = next;
      id = next.to!string;
    } else {
      auto n = id.to!long;
      if (n > sequences.get(res.path, 0L))
        sequences[res.path] = n;
    }
    Row row;
    foreach (c; res.columns) {
      auto v = rowGet(values, c.key);
      if (!isBlank(v))
        row[c.key] = v;
    }
    foreach (rel; res.rels) {
      auto v = rowGet(values, rel.attr);
      if (!isBlank(v))
        row[rel.attr] = v;
    }
    row[res.keyColumn] = Json(id);
    rows[slot(res.path, id)] = row;
    return id;
  }

  bool update(const Resource res, string id, Row values) {
    auto found = slot(res.path, id) in rows;
    if (found is null)
      return false;
    auto row = *found;
    foreach (k, v; values)
      row[k] = v;
    *found = row;
    return true;
  }

  bool remove(const Resource res, string id) {
    if (slot(res.path, id) in rows) {
      rows.remove(slot(res.path, id));
      foreach (vl; res.valueLists)
        valueStore.remove(storeSlot(res.path, vl.attr, id));
      foreach (mr; res.manyRels)
        manyStore.remove(storeSlot(res.path, mr.attr, id));
      return true;
    }
    return false;
  }

  private Row[] filterRows(const Resource res, const Plan p) {
    Row[] matched;
    foreach (key, row; rows) {
      if (!key.startsWith(res.path ~ "|"))
        continue;
      bool ok = true;
      foreach (c; p.conds) {
        if (!matchCond(res, row, c)) {
          ok = false;
          break;
        }
      }
      if (ok)
        matched ~= row;
    }
    // 排序：按 plan 的 orders 依次比，最后按 id 兜底
    if (p.orders.length > 0) {
      auto orders = p.orders;
      sort!((a, b) {
        foreach (o; orders) {
          auto desc = o.endsWith(" desc");
          auto expr = desc ? o[0 .. $ - 5] : o;
          int cmp = compareValues(exprValue(res, a, expr), exprValue(res, b, expr));
          if (cmp != 0)
            return desc ? cmp > 0 : cmp < 0;
        }
        return false;
      })(matched);
    }
    return matched;
  }

  private bool matchCond(const Resource res, Row row, const Cond c) {
    foreach (term; c.terms) {
      auto matched = matchTerm(res, row, c.column, term);
      if (c.joiner == "or") {
        if (matched)
          return true;
      } else if (!matched) {
        return false;
      }
    }
    return c.joiner != "or";
  }

  private bool matchTerm(const Resource res, Row row, string column, const CondTerm term) {
    auto value = exprValue(res, row, column);
    auto text = jsonText(value);
    if (term.op == "is null")
      return isBlank(value);
    if (term.op == "is not null")
      return !isBlank(value);
    if (term.op == "in" || term.op == "not in") {
      bool found;
      foreach (candidate; term.values) {
        if (comparableText(text) == comparableText(candidate)) {
          found = true;
          break;
        }
      }
      return term.op == "in" ? found : (!isBlank(value) && !found);
    }
    if (isBlank(value))
      return false;
    if (term.op == "=")
      return comparableText(text) == comparableText(term.values[0]);
    if (term.op == "!=")
      return comparableText(text) != comparableText(term.values[0]);
    if (term.op == "like")
      return likeMatch(term.values[0], text);
    if (term.op == ">=")
      return compareScalar(value, term.values[0]) >= 0;
    if (term.op == ">")
      return compareScalar(value, term.values[0]) > 0;
    if (term.op == "<=")
      return compareScalar(value, term.values[0]) <= 0;
    if (term.op == "<")
      return compareScalar(value, term.values[0]) < 0;
    if (term.op == "between")
      return compareScalar(value, term.values[0]) >= 0 && compareScalar(value, term.values[1]) <= 0;
    return false;
  }

  private int compareScalar(Json value, string expected) {
    if (value.type == Json.Type.int_) {
      try {
        auto left = value.get!long;
        auto right = expected.to!long;
        return left < right ? -1 : (left > right ? 1 : 0);
      } catch (Exception e) {
        // 数字列上给了非数字文本时按字符串比较，保持与 SQL 尽力执行相近的行为
      }
    }
    auto text = comparableText(jsonText(value));
    expected = comparableText(expected);
    return text < expected ? -1 : (text > expected ? 1 : 0);
  }

  /// PostgreSQL 可能返回带空格的 timestamp 文本；查询上界统一用 `T`，比较前先对齐。
  private string comparableText(string text) {
    if (text.length > 10 && text[4] == '-' && text[7] == '-' && (text[10] == ' ' || text[10] == 'T'))
      return text[0 .. 10] ~ "T" ~ text[11 .. $];
    return text;
  }

  /// `t.name` / `org.name` → 值。关系值靠外键去目标表里找。
  private Json exprValue(const Resource res, Row row, string expr) {
    auto dot = expr.indexOf('.');
    if (dot < 0)
      return columnValue(res, row, expr);
    auto prefix = expr[0 .. dot];
    auto column = expr[dot + 1 .. $];
    if (prefix == baseAlias)
      return columnValue(res, row, column);
    auto rel = reg.findRel(res, prefix);
    if (rel is null)
      return Json.undefined;
    auto target = reg.find(rel.target);
    auto fk = jsonText(rowGet(row, prefix));
    if (fk.length == 0)
      return Json.undefined;
    if (auto trow = slot(target.path, fk) in rows)
      return rowGet(*trow, column);
    return Json.undefined;
  }

  /// 行里取列值：行键就是列 key；关系外键在行里按关系名存，这里把物理列名兜回去。
  private Json columnValue(const Resource res, Row row, string name) {
    if (name in row)
      return rowGet(row, name);
    foreach (rel; res.rels) {
      if (rel.column == name)
        return rowGet(row, rel.attr);
    }
    return Json.undefined;
  }

  /// 空值排最后，其余按字符串比（数字型按数值比，与库里 order by 的直觉一致）。
  private int compareValues(Json a, Json b) {
    if (a.type == Json.Type.int_ && b.type == Json.Type.int_) {
      auto la = a.get!long;
      auto lb = b.get!long;
      return la < lb ? -1 : (la > lb ? 1 : 0);
    }
    auto sa = jsonText(a);
    auto sb = jsonText(b);
    if (sa.length == 0 && sb.length == 0)
      return 0;
    if (sa.length == 0)
      return 1;
    if (sb.length == 0)
      return -1;
    return sa < sb ? -1 : (sa > sb ? 1 : 0);
  }
}

private string slot(string path, string id) {
  return path ~ "|" ~ id;
}

private string storeSlot(string path, string attr, string id) {
  return path ~ "|" ~ attr ~ "|" ~ id;
}

/// SQL `like` → 正则：`%` 任意长、`_` 单字符，其余转义。
private bool likeMatch(string pattern, string value) {
  auto sb = appender!string;
  sb.put("^");
  foreach (c; pattern) {
    switch (c) {
    case '%':
      sb.put(".*");
      break;
    case '_':
      sb.put(".");
      break;
    default:
      if ("\\^$.|?*+()[]{}".indexOf(c) >= 0)
        sb.put("\\");
      sb.put(c);
      break;
    }
  }
  sb.put("$");
  return !matchFirst(value, regex(sb.data)).empty;
}
