/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data.dao;
/// 数据访问接口：只有「按计划取行、按 id 取行、按 id 取一批行、增、改、删」六个动作。
/// 行是 `Json[string]`（列 key → 已按列类型转好的 Json），没有实体对象、没有会话、没有一级缓存——
/// 控制台的数据量小，每次请求现查最省事。

import beangle.data.plan;
import beangle.data.resource;
import beangle.data.schema : SchemaIssue;

import vibe.data.json : Json;

/** 数据访问错误（连接失败、SQL 失败）。 */
class DaoException : Exception {
  this(string msg, string file = __FILE__, size_t line = __LINE__) @safe {
    super(msg, file, line);
  }
}

interface Dao {
  /// 后端名（日志/健康检查用）。
  string backend() const;

  /// 执行列表计划；`total` 为不分页时的总数。
  Json[string][] select(const Resource res, const Plan p, out long total);

  /// 按 id 取一批（include 用）。
  Json[string][] selectByIds(const Resource res, const string[] ids);

  /// 取单条；不存在返回 `Json[string].init`。
  Json[string] findById(const Resource res, string id);

  /// 新建，返回新 id。
  string insert(const Resource res, Json[string] values);

  /// 修改；返回是否命中。
  bool update(const Resource res, string id, Json[string] values);

  /// 删除；返回是否命中。
  bool remove(const Resource res, string id);

  /// 取多值子表：ownerId → 值（保持子表里的顺序）。
  string[][string] selectValues(const Resource res, const ValueList vl, const string[] ownerIds);

  /// 取 to-many 关联：ownerId → 目标 id（保持关联表里的顺序）。
  string[][string] selectMany(const Resource res, const ManyRelation mr, const string[] ownerIds);

  /// 重写一个 owner 的多值子表；空数组 = 清空。
  void replaceValues(const Resource res, const ValueList vl, string ownerId, const string[] values);

  /// 重写一个 owner 的 to-many 关联；空数组 = 清空。
  void replaceMany(const Resource res, const ManyRelation mr, string ownerId, const string[] targetIds);

  /// 在一个事务里执行 `work`；异常时回滚并原样抛出。
  void transaction(void delegate() work);

  /// 检查资源定义所需的表/列是否都存在；内存后端返回空数组。
  SchemaIssue[] checkSchema(Registry reg);
}
