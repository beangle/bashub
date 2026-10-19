/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data.schema;
/// schema 漂移检查：把资源定义要求的主表、子表与列，和数据库里实际的列做比较。
/// 只报告「定义需要但库里没有」的表/列；多出来的列通常是后续版本留下的，不当作错误。

import beangle.data.resource : Column, Registry;

import std.algorithm : canFind;
import std.string : strip;

/// 一张表在资源定义里需要的列。
struct TableShape {
  string table;
  string[] columns;
}

/// 一条漂移：表不存在，或表里缺少定义所需的列。
struct SchemaIssue {
  string table;
  string column;
  string message;

  string toString() const {
    return column.length == 0 ? message ~ ": " ~ table : message ~ ": " ~ table ~ "." ~ column;
  }
}

/// 从注册表推导所有需要的表与列（含多值子表、关联表和 URI 子表）。
TableShape[] expectedTables(Registry reg) {
  TableShape[] tables;

  void add(string table, string column) {
    if (table.length == 0 || column.length == 0)
      return;
    foreach (ref shape; tables) {
      if (shape.table == table) {
        if (!shape.columns.canFind(column))
          shape.columns ~= column;
        return;
      }
    }
    tables ~= TableShape(table, [column]);
  }

  foreach (res; reg.all()) {
    add(res.table, res.keyColumn);
    foreach (c; res.columns)
      add(res.table, physicalColumn(c));
    foreach (rel; res.rels)
      add(res.table, rel.column);
    foreach (vl; res.valueLists) {
      add(vl.table, vl.ownerColumn);
      add(vl.table, vl.valueColumn);
    }
    foreach (mr; res.manyRels) {
      add(mr.joinTable, mr.sourceColumn);
      add(mr.joinTable, mr.targetColumn);
    }
  }
  return tables;
}

/// 比较资源定义与实际列。`actual` 的 key 是资源定义里的表名（可带 schema）。
SchemaIssue[] checkSchema(Registry reg, string[][string] actual) {
  SchemaIssue[] issues;
  foreach (shape; expectedTables(reg)) {
    auto found = shape.table in actual;
    if (found is null) {
      issues ~= SchemaIssue(shape.table, null, "表不存在");
      continue;
    }
    foreach (column; shape.columns) {
      if (!(*found).canFind(column))
        issues ~= SchemaIssue(shape.table, column, "缺少列");
    }
  }
  return issues;
}

/// 列定义里的 SQL 表达式。当前只接受列名或双引号包裹的保留字；复杂表达式无法从
/// `information_schema` 反推，跳过而不制造误报。
private string physicalColumn(const Column c) {
  auto expr = (c.expr.length > 0 ? c.expr : c.key).strip;
  if (expr.length >= 2 && expr[0] == '"' && expr[$ - 1] == '"')
    expr = expr[1 .. $ - 1];
  if (expr.length == 0)
    return "";
  foreach (ch; expr) {
    auto ok = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') ||
      ch == '_' || ch == '$';
    if (!ok)
      return "";
  }
  return expr;
}
