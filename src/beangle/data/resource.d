/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data.resource;
/// 资源定义：一张表怎么变成「资源」（列、to-one 关系、派生属性）只有这一处真相。
/// 与 Scala 侧靠 JPA 注解 + 运行期反射推导表名不同，表名、列名、属性名都写下来，
/// 没有反射、没有代理，`Registry` 建好之后是只读的。
/// 列上的 `attr` 是协议层对外的属性名（如 JSON:API 的 `httpPort`），`key` 是行键（`http_port`），
/// 两者可以不同——数据面只认 `key`，翻译由协议层负责。

import std.string : indexOf;

/// 列值在文档里的呈现方式。id 与外键一律字符串（JSON:API 规定 id 是字符串）。
enum Kind {
  id_,
  text,
  number,
  boolean,
  /// `date` / `datetime` 在 SQL 参数里仍用 ISO 文本，过滤时对 datetime 补结束上界。
  date,
  datetime,
  /// 库里是 `jsonb`，协议层是字符串数组（前端用「一行一个」的文本域编辑）
  jsonArray,
  /// 库里是 `jsonb`，协议层保持原样的 JSON 对象/数组（结构化配置）
  jsonDocument
}

/// 一列：`key` 是行键（= SQL 别名 = 库列名，小写），`attr` 是 JSON:API 属性名。
struct Column {
  string key;
  string attr;
  Kind kind;
  /// 只读列（如服务端生成的凭证）在写入时忽略，而不是报错
  bool writable = true;
  /// SQL 表达式，缺省用 `key`；保留字（如 `key`）在这里写带引号的形式
  string expr;
  /// 文本枚举：JSON:API 属性名 → 库里存的是下标（0 起）。空数组表示不是枚举。
  ///
  /// Scala 侧靠 JPA 的 ordinal 映射（如 `Scope`：Public=0/Protected=1/Private=2），
  /// D 侧没有反射，就在列定义里把顺序写出来：读的时候下标转名字，写的时候名字转下标。
  string[] names;
}

/// to-one 关系：外键在本地表。`attr` 同时是行键（SQL 里写成 `t.org_id as org`）。
struct Relation {
  string attr;
  string column;
  /// 目标资源的 path
  string target;
}

/// 派生属性：`templateText` 里 `{name}` 取本行、`{org.name}` 取关系行（关系行由 `needs` 预取）。
/// 模板里写的是 **JSON:API 属性名**，渲染时用 `Registry.keyOfAttr` 翻成行键。
struct Derived {
  string attr;
  string[] needs;
  string templateText;
}

/// 多值子表：`cfg_engines_listeners(engine_id, value_)` 这类「值不是另一个资源」的集合。
/// 协议层呈现为**属性**（字符串数组），不是 relationships。
struct ValueList {
  /// JSON:API 属性名（也是行键）
  string attr;
  string table;
  /// 子表里指向本资源 id 的列
  string ownerColumn;
  /// 值列
  string valueColumn;
}

/// to-many 关联：通过关联表连到另一个资源（`cfg_farms_servers`、`ems_menus_resources` 等）。
/// 协议层呈现为 `relationships[attr].data = [{type,id}, ...]`。
struct ManyRelation {
  string attr;
  string target;
  string joinTable;
  /// 关联表里指向本资源 id 的列
  string sourceColumn;
  /// 关联表里指向目标 id 的列
  string targetColumn;
  /// 反向 FK（如 `cfg_servers.farm_id`）只能读；写入会改到目标的业务列，默认拒绝。
  bool writable = true;
}

/// 一个资源。`table` 带 schema（如 `bas.cfg_profiles`）。
struct Resource {
  string path;
  string type;
  string table;
  string keyColumn = "id";
  Column[] columns;
  Relation[] rels;
  Derived[] derived;
  /// 缺省排序列（客户端一般还会带 sort 参数）
  string sortDefault = "id";
  /// 多值子表（listeners/jars 之类）
  ValueList[] valueLists;
  /// to-many 关联（servers/targets/resources 之类）
  ManyRelation[] manyRels;
  /// 前端查询串里的实体别名（`filter[profile.name]` 的 `profile`）；空则按资源名推导。
  string entityAlias;
  /// JSON:API 属性名或关系名：创建时必须提供非空值；更新时仅当请求里出现才校验。
  string[] required;
}

/** 资源注册表：进程内一张只读表，启动时建好，之后不再变。
 *
 * 显式传入而不是做成全局单例：同一进程里可以并存多套资源定义（测试夹具、多库接入），
 * 也不会有「谁先初始化」的隐藏顺序。
 */
class Registry {
  private Resource[] items;
  private Resource[string] byPath;

  /// 建表；path 重复直接抛，免得运行期出现「时好时坏」的资源解析。
  this(Resource[] defs) {
    foreach (d; defs) {
      if (d.path.length == 0)
        throw new Exception("resource path must not be empty");
      if (d.path in byPath)
        throw new Exception("duplicate resource path: " ~ d.path);
      byPath[d.path] = d;
      items ~= d;
    }
  }

  /// 全部资源（按注册顺序）。
  const(Resource)[] all() const {
    return items;
  }

  /// 按 path 找资源；找不到返回默认值（`path` 为空表示没有）。
  /// 返回的是**副本**（调用方拿到 Resource 值，再按需传给别的函数）。为了这个副本，
  /// 以及 `resolves` 里要调 `find`，这里的方法都不带 `const`——`Registry` 建好即只读，
  /// 让 D 的 const 在这里传染一圈不划算。
  Resource find(string path) {
    if (auto p = path in byPath)
      return *p;
    return Resource.init;
  }

  /// 按关系名找关系定义；没有返回 null。
  const(Relation)* findRel(const Resource res, string attr) const {
    foreach (ref r; res.rels) {
      if (r.attr == attr)
        return &r;
    }
    return null;
  }

  /// 按行键找列；没有返回 null。
  const(Column)* findColumn(const Resource res, string key) const {
    foreach (ref c; res.columns) {
      if (c.key == key)
        return &c;
    }
    return null;
  }

  /// 按行键**或** JSON:API 属性名找列；没有返回 null。
  /// 前端发的是属性名（`filter[httpPort]`），派生模板里常写行键，两种写法都收。
  const(Column)* findColumnByName(const Resource res, string name) const {
    foreach (ref c; res.columns) {
      if (c.key == name || c.attr == name)
        return &c;
    }
    return null;
  }

  /// 关系的目标资源；关系不存在返回默认资源。
  Resource targetOf(const Resource res, string relAttr) {
    auto rel = findRel(res, relAttr);
    return rel is null ? Resource.init : find(rel.target);
  }

  /// JSON:API 属性名 → 行键。找不到就原样返回，模板里直接写行键也能用。
  string keyOfAttr(const Resource res, string attr) const {
    foreach (c; res.columns) {
      if (c.attr == attr)
        return c.key;
    }
    return attr;
  }

  /// 过滤键是否可用：列 key、关系 attr、主键，或 `关系.列`（如 `org.name`）。
  ///
  /// 不设白名单：Scala 侧的过滤是对实体属性来的，属性存在就能过滤；列出「允许的键」只会
  /// 和前端表单越走越远。认不出的键在这里拒掉，比在 SQL 里报错更早也更清楚。
  bool allowsFilter(const Resource res, string key) {
    return resolves(res, key);
  }

  /// 排序键是否可用（与过滤同一套解析规则）。
  bool allowsSort(const Resource res, string key) {
    return resolves(res, key);
  }

  private bool resolves(const Resource res, string key) {
    auto dot = key.indexOf('.');
    if (dot < 0)
      return findColumnByName(res, key) !is null || findRel(res, key) !is null || key == res.keyColumn;
    auto name = key[0 .. dot];
    auto sub = key[dot + 1 .. $];
    auto rel = findRel(res, name);
    if (rel is null)
      return false;
    auto target = find(rel.target);
    return sub == target.keyColumn || findColumnByName(target, sub) !is null;
  }
}
