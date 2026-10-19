/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data.dao.postgres;
/// 直连 PostgreSQL 的 DAO：每条请求现拼 SQL 现查，没有实体、没有会话、没有一二级缓存。
/// 控制台的写操作都是「改一行」，用不着 Hibernate 的脏检查与延迟加载。
///
/// 主键沿用 beangle 自己的生成器 `public.next_id('<schema>.<table>')`（见 data-hibernate 的
/// AutoIncrementGenerator），因此新建出来的 id 与 Scala 侧写出的同源，两边可以交替读写同一批表。

import beangle.data.dao;
import beangle.data.dao.pq;
import beangle.data.plan;
import beangle.data.resource;
import beangle.data.schema;
import beangle.data.value : isBlank;
import beangle.data.value;

import vibe.data.json : Json, parseJson;

import std.array : appender, join;
import std.conv : to, ConvException;
import std.format : format;
import std.string : lastIndexOf;

class DbDao : Dao {
  private PGconn* db;

  this(string connStr) {
    try {
      db = open(connStr);
    } catch (PgException e) {
      throw new DaoException("connect postgres failed: " ~ e.msg);
    }
  }

  ~this() {
    close(db);
  }

  string backend() const {
    return "postgres";
  }

  SchemaIssue[] checkSchema(Registry reg) {
    string[][string] actual;
    try {
      foreach (shape; expectedTables(reg)) {
        auto dot = shape.table.lastIndexOf('.');
        string sql;
        string[] args;
        if (dot < 0) {
          sql = "select column_name from information_schema.columns " ~
            "where table_name = ? and table_schema = current_schema()";
          args = [shape.table];
        } else {
          sql = "select column_name from information_schema.columns " ~
            "where table_schema = ? and table_name = ?";
          args = [shape.table[0 .. dot], shape.table[dot + 1 .. $]];
        }
        foreach (row; run(sql, args))
          actual[shape.table] ~= row[0].toString;
      }
    } catch (Exception e) {
      throw new DaoException("check schema failed: " ~ e.msg);
    }
    return beangle.data.schema.checkSchema(reg, actual);
  }

  private PgResult run(string sql, const(string)[] args) {
    try {
      return exec(db, pgPlaceholders(sql), args);
    } catch (PgException e) {
      throw new DaoException(e.msg);
    }
  }

  Json[string][] select(const Resource res, const Plan p, out long total) {
    Json[string][] rows;
    try {
      foreach (row; run(planSql(p), planValues(p)))
        rows ~= toRow(res, row);
      if (p.limit > 0) {
        foreach (counted; run(countSql(p), planValues(p)))
          total = counted[0].toString.to!long;
      } else {
        total = rows.length;
      }
    } catch (DaoException e) {
      throw e;
    } catch (Exception e) {
      throw new DaoException("query " ~ res.path ~ " failed: " ~ e.msg);
    }
    return rows;
  }

  Json[string][] selectByIds(const Resource res, const string[] ids) {
    Json[string][] rows;
    if (ids.length == 0)
      return rows;
    auto sql = "select " ~ selectList(res) ~ " from " ~ res.table ~ " " ~ baseAlias ~
      " where " ~ baseAlias ~ "." ~ res.keyColumn ~ " in (" ~ marks(ids.length) ~ ")";
    try {
      foreach (row; run(sql, ids))
        rows ~= toRow(res, row);
    } catch (Exception e) {
      throw new DaoException("load " ~ res.path ~ " by ids failed: " ~ e.msg);
    }
    return rows;
  }

  Json[string] findById(const Resource res, string id) {
    auto rows = selectByIds(res, [id]);
    return rows.length == 0 ? emptyRow() : rows[0];
  }

  string insert(const Resource res, Json[string] values) {
    try {
      string id;
      if (auto provided = res.keyColumn in values)
        id = isBlank(*provided) ? "" : jsonText(*provided);
      if (id.length == 0) {
        long nextId = 0;
        foreach (row; run("select public.next_id(?) as id", [res.table]))
          nextId = row[0].toString.to!long;
        id = nextId.to!string;
      }

      auto cols = appender!(string[])();
      auto marks = appender!(string[])();
      auto args = appender!(string[])();
      cols.put(res.keyColumn);
      marks.put("?");
      args.put(id);
      foreach (key, value; values) {
        if (key == res.keyColumn)
          continue;
        cols.put(writeColumnOf(res, key));
        marks.put(placeholderOf(res, key));
        args.put(sqlText(value));
      }
      auto sql = format("insert into %s (%s) values (%s)", res.table, cols.data.join(", "), marks.data.join(", "));
      run(sql, args.data);
      return id;
    } catch (DaoException e) {
      throw e;
    } catch (Exception e) {
      throw new DaoException("insert into " ~ res.table ~ " failed: " ~ e.msg);
    }
  }

  bool update(const Resource res, string id, Json[string] values) {
    auto sets = appender!(string[])();
    auto args = appender!(string[])();
    foreach (key, value; values) {
      if (key == res.keyColumn)
        continue;
      sets.put(writeColumnOf(res, key) ~ " = " ~ placeholderOf(res, key));
      args.put(sqlText(value));
    }
    // 只改集合（子表/关联表）时没有行内列可写，但仍要如实返回主行是否存在。
    if (sets.data.length == 0)
      return selectByIds(res, [id]).length > 0;
    args.put(id);
    // returning id：靠结果行数判断是否命中，省一次「先查后改」。
    auto sql = format("update %s set %s where %s = ? returning %s",
        res.table, sets.data.join(", "), res.keyColumn, res.keyColumn);
    try {
      return !run(sql, args.data).empty;
    } catch (Exception e) {
      throw new DaoException("update " ~ res.table ~ " failed: " ~ e.msg);
    }
  }

  bool remove(const Resource res, string id) {
    auto sql = format("delete from %s where %s = ? returning %s", res.table, res.keyColumn, res.keyColumn);
    try {
      return !run(sql, [id]).empty;
    } catch (Exception e) {
      throw new DaoException("delete from " ~ res.table ~ " failed: " ~ e.msg);
    }
  }

  string[][string] selectValues(const Resource res, const ValueList vl, const string[] ownerIds) {
    string[][string] grouped;
    if (ownerIds.length == 0)
      return grouped;
    auto sql = "select " ~ vl.ownerColumn ~ "::text, " ~ vl.valueColumn ~ " from " ~ vl.table ~
      " where " ~ vl.ownerColumn ~ " in (" ~ marks(ownerIds.length) ~ ")";
    try {
      foreach (row; run(sql, ownerIds))
        grouped[row[0].toString] ~= row[1].toString;
    } catch (Exception e) {
      throw new DaoException("load " ~ vl.table ~ " for " ~ res.path ~ " failed: " ~ e.msg);
    }
    return grouped;
  }

  string[][string] selectMany(const Resource res, const ManyRelation mr, const string[] ownerIds) {
    string[][string] grouped;
    if (ownerIds.length == 0)
      return grouped;
    auto sql = "select " ~ mr.sourceColumn ~ "::text, " ~ mr.targetColumn ~ "::text from " ~ mr.joinTable ~
      " where " ~ mr.sourceColumn ~ " in (" ~ marks(ownerIds.length) ~ ")";
    try {
      foreach (row; run(sql, ownerIds))
        grouped[row[0].toString] ~= row[1].toString;
    } catch (Exception e) {
      throw new DaoException("load " ~ mr.joinTable ~ " for " ~ res.path ~ " failed: " ~ e.msg);
    }
    return grouped;
  }

  void replaceValues(const Resource res, const ValueList vl, string ownerId, const string[] values) {
    auto sql = "delete from " ~ vl.table ~ " where " ~ vl.ownerColumn ~ " = ?";
    try {
      run(sql, [ownerId]);
      foreach (v; values)
        run("insert into " ~ vl.table ~ " (" ~ vl.ownerColumn ~ ", " ~ vl.valueColumn ~ ") values (?, ?)",
            [ownerId, v]);
    } catch (Exception e) {
      throw new DaoException("save " ~ vl.table ~ " for " ~ res.path ~ " failed: " ~ e.msg);
    }
  }

  void replaceMany(const Resource res, const ManyRelation mr, string ownerId, const string[] targetIds) {
    auto sql = "delete from " ~ mr.joinTable ~ " where " ~ mr.sourceColumn ~ " = ?";
    try {
      run(sql, [ownerId]);
      foreach (id; targetIds)
        run("insert into " ~ mr.joinTable ~ " (" ~ mr.sourceColumn ~ ", " ~ mr.targetColumn ~ ") values (?, ?)",
            [ownerId, id]);
    } catch (Exception e) {
      throw new DaoException("save " ~ mr.joinTable ~ " for " ~ res.path ~ " failed: " ~ e.msg);
    }
  }

  void transaction(void delegate() work) {
    try {
      run("begin", null);
      work();
      run("commit", null);
    } catch (Exception e) {
      try {
        run("rollback", null);
      } catch (Exception ignored) {
        // 连接已经断开时 rollback 也会失败；保留原始异常更有用。
      }
      throw e;
    }
  }
}

/// `jsonb` 列要显式 cast：参数按 text 绑定，Postgres 不会自动把 text 赋给 jsonb。
private string placeholderOf(const Resource res, string key) {
  foreach (c; res.columns) {
    if (c.key == key && (c.kind == Kind.jsonArray || c.kind == Kind.jsonDocument))
      return "?::jsonb";
  }
  return "?";
}

/// 行里关系用 attr 当键（`org`），写库时必须回到物理列（`org_id`）。
private string writeColumnOf(const Resource res, string key) {
  foreach (rel; res.rels) {
    if (rel.attr == key)
      return rel.column;
  }
  return key;
}

/// NULL 与空字符串在库里不是一回事；显式清空关系时必须绑定 NULL。
private string sqlText(Json value) {
  return isBlank(value) ? null : jsonText(value);
}

/// select 列表（与 plan.buildPlan 同一套别名约定）。
string selectList(const Resource res) {
  auto list = appender!(string[])();
  list.put(baseAlias ~ "." ~ res.keyColumn ~ " as " ~ res.keyColumn);
  foreach (c; res.columns) {
    auto expr = c.expr.length > 0 ? c.expr : c.key;
    list.put(baseAlias ~ "." ~ expr ~ " as " ~ c.key);
  }
  foreach (r; res.rels)
    list.put(baseAlias ~ "." ~ r.column ~ " as " ~ r.attr);
  return list.data.join(", ");
}

/// `?, ?, ?`
private string marks(size_t n) {
  auto sb = appender!string;
  foreach (i; 0 .. n) {
    if (i > 0)
      sb.put(", ");
    sb.put("?");
  }
  return sb.data;
}

/// 现有 DAO 用 `?` 写占位符，libpq 的 PQexecParams 要求 `$1`、`$2`。
/// 只转换引号外的问号，避免把 SQL 字符串或注释里的 `?` 当参数。
private string pgPlaceholders(string sql) {
  auto buf = appender!string();
  size_t parameter;
  bool single;
  bool doubleQuote;
  bool lineComment;
  bool blockComment;
  for (size_t i = 0; i < sql.length; ++i) {
    auto ch = sql[i];
    if (lineComment) {
      buf.put(ch);
      if (ch == '\n')
        lineComment = false;
      continue;
    }
    if (blockComment) {
      buf.put(ch);
      if (ch == '*' && i + 1 < sql.length && sql[i + 1] == '/') {
        buf.put(sql[++i]);
        blockComment = false;
      }
      continue;
    }
    if (single) {
      buf.put(ch);
      if (ch == '\'' && i + 1 < sql.length && sql[i + 1] == '\'') {
        buf.put(sql[++i]);
      } else if (ch == '\'') {
        single = false;
      }
      continue;
    }
    if (doubleQuote) {
      buf.put(ch);
      if (ch == '"' && i + 1 < sql.length && sql[i + 1] == '"') {
        buf.put(sql[++i]);
      } else if (ch == '"') {
        doubleQuote = false;
      }
      continue;
    }
    if (ch == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      buf.put(ch);
      buf.put(sql[++i]);
      lineComment = true;
      continue;
    }
    if (ch == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
      buf.put(ch);
      buf.put(sql[++i]);
      blockComment = true;
      continue;
    }
    if (ch == '\'') {
      single = true;
      buf.put(ch);
      continue;
    }
    if (ch == '"') {
      doubleQuote = true;
      buf.put(ch);
      continue;
    }
    if (ch == '?') {
      ++parameter;
      buf.put('$');
      buf.put(parameter.to!string);
      continue;
    }
    buf.put(ch);
  }
  return buf.data;
}

/// 行的列 → Json（id 与外键统一成字符串，JSON:API 规定 id 就是字符串）。
private Json[string] toRow(const Resource res, PgRow row) {
  Json[string] r;
  put(r, row, res.keyColumn, Kind.id_);
  foreach (c; res.columns)
    put(r, row, c.key, c.kind);
  foreach (rel; res.rels)
    put(r, row, rel.attr, Kind.id_);
  return r;
}

private void put(ref Json[string] r, PgRow row, string key, Kind kind) {
  auto d = row[key];
  r[key] = d.isNull() ? Json(null) : datumJson(d.toString, kind);
}

private Json datumJson(string text, Kind kind) {
  final switch (kind) {
  case Kind.id_:
  case Kind.text:
    return Json(text);
  case Kind.number:
    try {
      return Json(text.to!long);
    } catch (ConvException e) {
      return Json(text);
    }
  case Kind.date:
  case Kind.datetime:
    return Json(text);
  case Kind.boolean:
    // libpq 的布尔文本就是 `t`/`f`
    return Json(text == "t" || text == "true");
  case Kind.jsonArray:
  case Kind.jsonDocument:
    try {
      return parseJson(text);
    } catch (Exception e) {
      return Json.emptyArray;
    }
  }
}
