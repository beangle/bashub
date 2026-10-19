/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data.query;
/// 查询参数解析（纯函数）：`page[number]` / `page[size]` / `sort` / `filter[...]` / `include`。
/// 参数名与优先级对齐 she 的 QueryHelper：`pageIndex`>`page[number]`、`pageSize`>`page[size]`、
/// `orderBy`>`sort`；过滤键就是 JSON:API 属性路径（如 `org.name`），不带实体别名前缀。

import std.algorithm : splitter;
import std.conv : to, ConvException;
import std.string : endsWith, indexOf, startsWith, strip;

/** 查询参数非法（未知过滤键、排序键、分页参数不是数字）——web 层转成 400 + JSON:API errors。 */
class QueryException : Exception {
  /// 出错的参数名，写进 `errors[0].source.parameter`
  string parameter;

  this(string parameter, string msg, string file = __FILE__, size_t line = __LINE__) @safe {
    super(msg, file, line);
    this.parameter = parameter;
  }
}

struct SortKey {
  string field;
  bool desc;
}

/// 请求参数的一次出现。`req.query` 允许同名多值，不能先折成字典再解析过滤条件。
struct QueryParam {
  string name;
  string value;
}

/// 一条过滤子句。`op` 为空表示沿用 Scala `Conditions.parse` 的隐式语义；
/// 否则是 `filter[attr][op]` 里的显式算子。
struct FilterClause {
  string key;
  string op;
  string value;
}

struct Query {
  size_t pageNumber = 1;
  size_t pageSize = 20;
  SortKey[] sorts;
  FilterClause[] filters;
  string[] includes;

  /// 追加一条过滤。同名同算子的多次出现按 Scala 的参数数组口径用逗号合并。
  void addFilter(string key, string value, string op = "") {
    auto name = key.strip;
    auto raw = value.strip;
    if (name.length == 0 || raw.length == 0)
      return;
    foreach (ref clause; filters) {
      if (clause.key == name && clause.op == op) {
        clause.value ~= "," ~ raw;
        return;
      }
    }
    filters ~= FilterClause(name, op, raw);
  }
}

/// 解析查询串。未知参数忽略（`Accept`/`_` 之类不该让请求失败）。
///
/// `fallbackPageSize` 只在 `pageSize` 与 `page[size]` 都缺失时使用，对应
/// QueryHelper 从 cookie 读取 `pageSize` 的行为。
Query parseQuery(QueryParam[] params, string fallbackPageSize = null) {
  Query q;
  string sortText;
  string pageIndexText;
  string pageNumberText;
  string pageSizeText;
  string pageLengthText;

  foreach (param; params) {
    auto k = param.name.strip;
    auto v = param.value.strip;
    if (k == "orderBy")
      sortText = v; // orderBy 覆盖 sort（QueryHelper 里 sort 是两条参数的后备）
    else if (k == "sort" && sortText.length == 0)
      sortText = v;
    else if (k == "filter[" ~ "]") {
      // 空键名没有意义，直接忽略
    } else if (k.startsWith("filter[") && k.endsWith("]")) {
      auto inner = k["filter[".length .. $ - 1].strip;
      auto opAt = inner.indexOf("][");
      if (opAt >= 0) {
        q.addFilter(inner[0 .. opAt].strip, v, inner[opAt + 2 .. $].strip);
      } else {
        q.addFilter(inner, v);
      }
    } else if (k == "include") {
      foreach (item; v.splitter(',')) {
        auto name = item.strip();
        if (name.length > 0)
          q.includes ~= name;
      }
    } else if (k == "pageIndex" && pageIndexText.length == 0)
      pageIndexText = v;
    else if (k == "page[number]" && pageNumberText.length == 0)
      pageNumberText = v;
    else if (k == "pageSize" && pageSizeText.length == 0)
      pageSizeText = v;
    else if (k == "page[size]" && pageLengthText.length == 0)
      pageLengthText = v;
  }

  foreach (item; sortText.splitter(',')) {
    auto field = item.strip();
    if (field.length == 0)
      continue;
    if (field.startsWith("-"))
      q.sorts ~= SortKey(field[1 .. $], true);
    else
      q.sorts ~= SortKey(field, false);
  }

  // 与 QueryHelper 一致：只有 pageIndex/page[number] 优先，pageSize/page[size] 其次；非法值回落缺省。
  auto index = pageIndexText.length > 0 ? pageIndexText : pageNumberText;
  auto size = pageSizeText.length > 0 ? pageSizeText : pageLengthText;
  if (size.length == 0 && fallbackPageSize !is null)
    size = fallbackPageSize.strip;
  if (index.length > 0)
    q.pageNumber = toPositive("pageIndex", index, 1);
  if (size.length > 0)
    q.pageSize = toPositive("pageSize", size, 20);
  return q;
}

/// 便捷入口：字典本身只有一个值，供内部构造查询与现有测试使用。
Query parseQuery(string[string] params, string fallbackPageSize = null) {
  QueryParam[] items;
  foreach (key, value; params)
    items ~= QueryParam(key, value);
  return parseQuery(items, fallbackPageSize);
}

/// 0 或负数回落缺省（QueryHelper 里 `<1` 视为缺省）。非数字则 400。
/// 这里按 `long` 解析：`page[size]=-3` 在 Scala 侧能读出 -3 再回落，不该报 400。
private size_t toPositive(string key, string value, size_t fallback) {
  long n;
  try {
    n = value.to!long;
  } catch (ConvException e) {
    throw new QueryException(key, "not a number: " ~ value);
  }
  return n < 1 ? fallback : n.to!size_t;
}
