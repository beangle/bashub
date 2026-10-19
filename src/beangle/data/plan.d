/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data.plan;
/// 查询计划：把「资源定义 + 查询参数」翻成一张与数据库无关的计划（from/join/where/order/limit）。
/// 计划本身是纯数据，SQL 文本与参数由本模块生成——两者都能在没有数据库的情况下测。
///
/// 关系（`org.name` 这类）要靠注册表解析目标表，所以调用方把 `Registry` 传进来，不用全局单例。

import beangle.data.query;
import beangle.data.resource;

import std.array : appender, join, split;
import std.conv : to;
import std.string : endsWith, indexOf, startsWith, strip;

/// 基础表的别名。所有列都写成 `t.<列>`。
enum baseAlias = "t";

/// 一个条件项。`between` 固定两个值，`in` / `not in` 可有多个值，其余通常一个值。
struct CondTerm {
  string op;
  string[] values;
}

/// 一列上的条件组。同一个过滤参数里的多个文本 token 可能以 `or` 组合。
struct Cond {
  string column;
  CondTerm[] terms;
  string joiner = "and";
}

struct Join {
  string table;
  /// 别名（用关系 attr），SQL 里 `left join bas.cfg_organizations org on org.id = t.org_id`
  string name;
  string on;
}

struct Plan {
  string from;
  Join[] joins;
  Cond[] conds;
  string[] orders;
  string[] selectList;
  /// 0 = 不分页
  size_t limit;
  size_t offset;
}

/// 由资源与查询构造计划；未知的过滤/排序键抛 QueryException。
Plan buildPlan(Registry reg, const Resource res, const Query q) {
  if (res.path.length == 0)
    throw new QueryException("resource", "unknown resource");

  Plan p;
  p.from = res.table ~ " " ~ baseAlias;

  p.selectList ~= baseAlias ~ "." ~ res.keyColumn ~ " as " ~ res.keyColumn;
  foreach (c; res.columns) {
    auto expr = c.expr.length > 0 ? c.expr : c.key;
    p.selectList ~= baseAlias ~ "." ~ expr ~ " as " ~ c.key;
  }
  foreach (r; res.rels)
    p.selectList ~= baseAlias ~ "." ~ r.column ~ " as " ~ r.attr;

  foreach (f; q.filters) {
    auto key = stripAlias(res, f.key);
    auto parameter = "filter[" ~ f.key ~ "]" ~ (f.op.length == 0 ? "" : "[" ~ f.op ~ "]");
    if (!reg.allowsFilter(res, key))
      throw new QueryException(parameter, "unsupported filter field: " ~ f.key);
    addFilter(p, reg, res, key, f.op, f.value, parameter);
  }

  if (q.sorts.length == 0) {
    p.orders ~= baseAlias ~ "." ~ res.sortDefault;
  } else {
    foreach (s; q.sorts) {
      auto field = stripAlias(res, s.field);
      p.orders ~= orderOf(p, reg, res, SortKey(field, s.desc));
    }
  }
  // 与 Scala 侧一致：末位补一个主键，保证分页稳定
  bool orderedByKey = false;
  foreach (o; p.orders) {
    if (o.startsWith(baseAlias ~ "." ~ res.keyColumn))
      orderedByKey = true;
  }
  if (!orderedByKey)
    p.orders ~= baseAlias ~ "." ~ res.keyColumn;

  // 与 she 的 QueryHelper 一致：始终分页（缺省 1/20），这样 search 永远带 `meta.page`。
  p.limit = q.pageSize;
  p.offset = (q.pageNumber - 1) * q.pageSize;
  return p;
}

/// 前端查询串会以实体别名开头（`profile.name`）；别名不是关系名，先剥掉再解析。
private string stripAlias(const Resource res, string key) {
  auto dot = key.indexOf('.');
  if (dot < 0)
    return key;
  auto prefix = key[0 .. dot];
  if (prefix == baseAlias || prefix == res.path || prefix == res.type || prefix == resourceAlias(res))
    return key[dot + 1 .. $];
  return key;
}

private string resourceAlias(const Resource res) {
  if (res.entityAlias.length > 0)
    return res.entityAlias;
  switch (res.path) {
  case "platform-features":
    return "platformFeature";
  case "app-groups":
    return "appGroup";
  default:
    return res.path.endsWith("s") ? res.path[0 .. $ - 1] : res.path;
  }
}

private string orderOf(ref Plan p, Registry reg, const Resource res, SortKey s) {
  auto dot = s.field.indexOf('.');
  if (dot < 0) {
    if (auto r = reg.findRel(res, s.field)) {
      ensureJoin(p, reg, r);
      auto target = reg.find(r.target);
      return s.field ~ "." ~ target.keyColumn ~ (s.desc ? " desc" : "");
    }
    auto c = reg.findColumnByName(res, s.field);
    if (c is null && s.field != res.keyColumn)
      throw new QueryException("sort", "unsupported sort field: " ~ s.field);
    return baseAlias ~ "." ~ (c is null ? s.field : c.key) ~ (s.desc ? " desc" : "");
  }
  auto name = s.field[0 .. dot];
  auto sub = s.field[dot + 1 .. $];
  auto r = reg.findRel(res, name);
  if (r is null)
    throw new QueryException("sort", "unsupported sort field: " ~ s.field);
  ensureJoin(p, reg, r);
  auto target = reg.find(r.target);
  if (sub == target.keyColumn)
    return name ~ "." ~ sub ~ (s.desc ? " desc" : "");
  auto c = reg.findColumnByName(target, sub);
  if (c is null)
    throw new QueryException("sort", "unsupported sort field: " ~ s.field);
  return name ~ "." ~ c.key ~ (s.desc ? " desc" : "");
}

private void addFilter(ref Plan p, Registry reg, const Resource res, string key, string op, string value,
    string parameter) {
  auto dot = key.indexOf('.');
  if (dot < 0) {
    if (auto r = reg.findRel(res, key)) {
      // 关系过滤给的是 id，不是可模糊匹配的文本（对应 Conditions.parse 里属性类型非 String 的分支）
      addCond(p, condOf(baseAlias ~ "." ~ r.column, value, Kind.id_, op, null, parameter));
      return;
    }
    auto c = reg.findColumnByName(res, key);
    if (c is null) {
      if (key == res.keyColumn) {
        addCond(p, condOf(baseAlias ~ "." ~ key, value, Kind.id_, op, null, parameter));
        return;
      }
      throw new QueryException(parameter, "unsupported filter field: " ~ key);
    }
    addCond(p, condOf(baseAlias ~ "." ~ c.key, value, c.kind, op, c, parameter));
    return;
  }
  auto name = key[0 .. dot];
  auto sub = key[dot + 1 .. $];
  auto r = reg.findRel(res, name);
  if (r is null)
    throw new QueryException(parameter, "unsupported filter field: " ~ key);
  ensureJoin(p, reg, r);
  auto target = reg.find(r.target);
  if (sub == target.keyColumn) {
    addCond(p, condOf(name ~ "." ~ sub, value, Kind.id_, op, null, parameter));
    return;
  }
  auto c = reg.findColumnByName(target, sub);
  if (c is null)
    throw new QueryException(parameter, "unsupported filter field: " ~ key);
  addCond(p, condOf(name ~ "." ~ c.key, value, c.kind, op, c, parameter));
}

private void addCond(ref Plan p, Cond cond) {
  if (cond.terms.length > 0)
    p.conds ~= cond;
}

/// 文本枚举过滤传名字，SQL/内存行里存的是下标；数字也照常接受。
private string filterText(const(Column)* c, string value, string parameter) {
  if (c is null || c.names.length == 0)
    return value;
  foreach (i, name; c.names) {
    if (name == value)
      return i.to!string;
  }
  try {
    value.to!long;
    return value;
  } catch (Exception e) {
    throw new QueryException(parameter, "unknown value for `" ~ c.attr ~ "`: " ~ value);
  }
}

private void ensureJoin(ref Plan p, Registry reg, const(Relation)* r) {
  foreach (j; p.joins) {
    if (j.name == r.attr)
      return;
  }
  auto target = reg.find(r.target);
  p.joins ~= Join(target.table, r.attr, r.attr ~ "." ~ target.keyColumn ~ " = " ~ baseAlias ~ "." ~ r.column);
}

/// 与 beangle 的 Conditions.parse 同口径；显式算子则按 QueryHelper.buildCondition 处理。
private Cond condOf(string column, string raw, Kind kind, string op, const(Column)* c, string parameter) {
  if (op.length > 0)
    return explicitCond(column, raw, op, c, parameter);

  auto tokens = splitValues(raw);
  if (tokens.length == 0)
    return Cond.init;

  CondTerm[] terms;
  bool allEquals = true;
  bool allLikes = true;
  foreach (token; tokens) {
    CondTerm term;
    if (token == "null") {
      term = CondTerm("is null", null);
    } else if (kind != Kind.text) {
      term = CondTerm("=", [filterValue(kind, c, token, false, parameter)]);
    } else {
      term = textTerm(token);
    }
    terms ~= term;
    if (term.op != "=")
      allEquals = false;
    if (term.op != "like")
      allLikes = false;
  }

  if (terms.length == 1)
    return Cond(column, terms);
  if (allEquals) {
    string[] values;
    foreach (term; terms)
      values ~= term.values[0];
    return Cond(column, [CondTerm("in", values)]);
  }
  if (allLikes && terms.length >= 4) {
    string[] values;
    foreach (term; terms)
      values ~= unlike(term.values[0]);
    return Cond(column, [CondTerm("in", values)]);
  }
  return Cond(column, terms, "or");
}

private Cond explicitCond(string column, string raw, string op, const(Column)* c, string parameter) {
  auto kind = c is null ? Kind.id_ : c.kind;

  if (op == "between") {
    auto values = splitValues(raw);
    if (values.length != 2)
      return Cond.init;
    return Cond(column, [CondTerm("between", [
        filterValue(kind, c, values[0], false, parameter),
        filterValue(kind, c, values[1], true, parameter),
    ])]);
  }
  if (op == "in" || op == "nin") {
    auto values = splitValues(raw);
    if (values.length == 0)
      return Cond.init;
    string[] mapped;
    foreach (value; values)
      mapped ~= filterValue(kind, c, value, false, parameter);
    return Cond(column, [CondTerm(op == "in" ? "in" : "not in", mapped)]);
  }
  if (op == "ge" || op == "gt" || op == "le" || op == "lt" || op == "eq" || op == "ne" || op == "like") {
    string sqlOp;
    if (op == "ge")
      sqlOp = ">=";
    else if (op == "gt")
      sqlOp = ">";
    else if (op == "le")
      sqlOp = "<=";
    else if (op == "lt")
      sqlOp = "<";
    else if (op == "eq")
      sqlOp = "=";
    else if (op == "ne")
      sqlOp = "!=";
    else
      sqlOp = "like";
    auto end = op == "le" || op == "lt";
    return Cond(column, [CondTerm(sqlOp, [filterValue(kind, c, raw, end, parameter)])]);
  }
  // QueryHelper 对未知算子返回 None；这里同样忽略，保持前端兼容。
  return Cond.init;
}

private string filterValue(Kind kind, const(Column)* c, string raw, bool end, string parameter) {
  auto value = filterText(c, raw, parameter);
  if (kind != Kind.date && kind != Kind.datetime)
    return value;

  auto text = value.strip;
  if (kind == Kind.date) {
    if (!validDate(text))
      throw new QueryException(parameter, "invalid date: " ~ raw);
    return text;
  }
  if (text.length < 10 || !validDate(text[0 .. 10]))
    throw new QueryException(parameter, "invalid datetime: " ~ raw);

  auto date = text[0 .. 10];
  string rest;
  if (text.length > 10) {
    if (text[10] != 'T' && text[10] != ' ')
      throw new QueryException(parameter, "invalid datetime: " ~ raw);
    rest = text[11 .. $];
  }

  size_t zoneAt = rest.length;
  foreach (i, ch; rest) {
    if (ch == 'Z' || ((ch == '+' || ch == '-') && i > 0)) {
      zoneAt = i;
      break;
    }
  }
  auto clock = rest[0 .. zoneAt];
  auto zone = rest[zoneAt .. $];
  if (clock.length == 0)
    clock = "00:00:00";

  auto parts = clock.split(":");
  if (parts.length == 0 || parts.length > 3)
    throw new QueryException(parameter, "invalid datetime: " ~ raw);
  auto hourText = parts[0];
  auto minuteText = parts.length > 1 ? parts[1] : "00";
  auto secondText = parts.length > 2 ? parts[2] : "00";
  auto dot = secondText.indexOf('.');
  auto secondPart = dot < 0 ? secondText : secondText[0 .. dot];
  auto fraction = dot < 0 ? "" : secondText[dot + 1 .. $];
  if (hourText.length > 2 || minuteText.length > 2 || secondPart.length > 2 ||
      !allDigits(hourText) || !allDigits(minuteText) || !allDigits(secondPart) ||
      (fraction.length > 0 && (!allDigits(fraction) || fraction.length > 9)))
    throw new QueryException(parameter, "invalid datetime: " ~ raw);

  int hour = hourText.to!int;
  int minute = minuteText.to!int;
  int second = secondPart.to!int;
  if (hour > 23 || minute > 59 || second > 59)
    throw new QueryException(parameter, "invalid datetime: " ~ raw);
  if (end) {
    if (hour == 0)
      hour = 23;
    if (minute == 0)
      minute = 59;
    if (second == 0)
      second = 59;
    if (fraction.length == 0 || zeroFraction(fraction))
      fraction = "999999999";
  }

  return date ~ "T" ~ pad2(hour.to!string) ~ ":" ~ pad2(minute.to!string) ~ ":" ~
    pad2(second.to!string) ~ (fraction.length == 0 ? "" : "." ~ fraction) ~ zone;
}

private bool validDate(string text) {
  if (text.length != 10 || text[4] != '-' || text[7] != '-')
    return false;
  foreach (i, ch; text) {
    if (i != 4 && i != 7 && (ch < '0' || ch > '9'))
      return false;
  }
  return true;
}

private bool allDigits(string text) {
  if (text.length == 0)
    return false;
  foreach (ch; text) {
    if (ch < '0' || ch > '9')
      return false;
  }
  return true;
}

private bool zeroFraction(string text) {
  foreach (ch; text) {
    if (ch != '0')
      return false;
  }
  return true;
}

private string pad2(string text) {
  return text.length < 2 ? "0" ~ text : text;
}

/// 字符串过滤的锚点语义：`^abc` / `abc$` / `^abc$` / 普通包含；引号与转义先还原。
private CondTerm textTerm(string token) {
  auto value = token;
  bool head = false, tail = false;
  if (value.length > 0 && value[0] == '^') {
    value = value[1 .. $];
    head = true;
  }
  if (value.length > 0 && value[$ - 1] == '$') {
    value = value[0 .. $ - 1];
    tail = true;
  }
  value = escape(unquote(value));
  if (head && tail)
    return CondTerm("=", [value]);
  if (head)
    return CondTerm("like", [value ~ "%"]);
  if (tail)
    return CondTerm("like", ["%" ~ value]);
  return CondTerm("like", ["%" ~ value ~ "%"]);
}

/// 多值分隔符与 Scala 侧一致：半/全角逗号和分号；引号内的分隔符保留。
private string[] splitValues(string raw) {
  string[] values;
  string current;
  bool quoted;
  foreach (ch; raw) {
    if (ch == '"') {
      quoted = !quoted;
      current ~= ch;
    } else if (!quoted && (ch == ',' || ch == '，' || ch == ';' || ch == '；')) {
      auto value = current.strip;
      if (value.length > 0)
        values ~= value;
      current = "";
    } else {
      current ~= ch;
    }
  }
  auto value = current.strip;
  if (value.length > 0)
    values ~= value;
  return values;
}

private string unquote(string value) {
  if (value.length > 1 && value[0] == '"' && value[$ - 1] == '"')
    return value[1 .. $ - 1];
  return value;
}

private string escape(string value) {
  auto sb = appender!string;
  for (size_t i = 0; i < value.length; ++i) {
    if (value[i] == '\\' && i + 1 < value.length) {
      auto next = value[i + 1];
      if (next == 'n') {
        sb.put('\n');
        ++i;
        continue;
      }
      if (next == 'r') {
        sb.put('\r');
        ++i;
        continue;
      }
      if (next == 't') {
        sb.put('\t');
        ++i;
        continue;
      }
    }
    sb.put(value[i]);
  }
  return sb.data;
}

private string unlike(string value) {
  if (value.length > 0 && value[0] == '%')
    value = value[1 .. $];
  if (value.length > 0 && value[$ - 1] == '%')
    value = value[0 .. $ - 1];
  return value;
}

private string termSql(string column, string op, const(string)[] values) {
  if (op == "is null" || op == "is not null")
    return column ~ " " ~ op;
  if (op == "between")
    return column ~ " between ? and ?";
  if (op == "in" || op == "not in") {
    auto marks = appender!(string[])();
    foreach (i; 0 .. values.length)
      marks.put("?");
    return column ~ " " ~ op ~ " (" ~ marks.data.join(", ") ~ ")";
  }
  return column ~ " " ~ op ~ " ?";
}

/// where 子句（不含 `where` 关键字）。值为 `?` 占位，顺序与 planValues 一致。
string whereSql(const Plan p) {
  auto parts = appender!(string[])();
  foreach (c; p.conds) {
    if (c.terms.length == 0)
      continue;
    if (c.terms.length == 1) {
      parts.put(termSql(c.column, c.terms[0].op, c.terms[0].values));
    } else {
      auto terms = appender!(string[])();
      foreach (term; c.terms)
        terms.put(termSql(c.column, term.op, term.values));
      parts.put("(" ~ terms.data.join(" " ~ c.joiner ~ " ") ~ ")");
    }
  }
  return parts.data.length == 0 ? "" : parts.data.join(" and ");
}

/// `?` 对应的参数，顺序与 whereSql 一致。
string[] planValues(const Plan p) {
  string[] values;
  foreach (c; p.conds)
    foreach (term; c.terms)
      values ~= term.values;
  return values;
}

/// 列表 SQL。
string planSql(const Plan p) {
  auto sb = appender!string;
  sb.put("select ");
  sb.put(p.selectList.join(", "));
  sb.put(" from ");
  sb.put(p.from);
  foreach (j; p.joins) {
    sb.put(" left join ");
    sb.put(j.table);
    sb.put(" ");
    sb.put(j.name);
    sb.put(" on ");
    sb.put(j.on);
  }
  auto where = whereSql(p);
  if (where.length > 0) {
    sb.put(" where ");
    sb.put(where);
  }
  if (p.orders.length > 0) {
    sb.put(" order by ");
    sb.put(p.orders.join(", "));
  }
  if (p.limit > 0) {
    sb.put(" limit ");
    sb.put(p.limit.to!string);
    sb.put(" offset ");
    sb.put(p.offset.to!string);
  }
  return sb.data;
}

/// 计数 SQL（分页信息用）。
string countSql(const Plan p) {
  auto sb = appender!string;
  sb.put("select count(*) as total from ");
  sb.put(p.from);
  foreach (j; p.joins) {
    sb.put(" left join ");
    sb.put(j.table);
    sb.put(" ");
    sb.put(j.name);
    sb.put(" on ");
    sb.put(j.on);
  }
  auto where = whereSql(p);
  if (where.length > 0) {
    sb.put(" where ");
    sb.put(where);
  }
  return sb.data;
}
