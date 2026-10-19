/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.fixture;
/// 测试夹具：一张机构表 + 一张配置表，覆盖 7 种列类型、to-one/to-many、多值子表与派生属性。
/// 与任何具体应用的资源定义无关——本模块的用例都跑在这上面。

import beangle.data.dao.memory : MemoryDao;
import beangle.data.resource;
import beangle.jsonapi.store;
import beangle.data.value;

import vibe.data.json : Json;

import std.digest : toHexString;
import std.random : uniform;
import std.string : toLower;

/// fixture 用的资源定义。
Registry fixtureRegistry() {
  return new Registry([
    Resource(
      "organizations", "organizations", "bas.cfg_organizations", "id",
      [
        Column("name", "name", Kind.text),
        Column("title", "title", Kind.text),
        Column("short_title", "shortTitle", Kind.text),
      ],
      [], [], "name"),
    Resource(
      "profiles", "profiles", "bas.cfg_profiles", "id",
      [
        Column("name", "name", Kind.text),
        Column("title", "title", Kind.text),
        Column("http_port", "httpPort", Kind.number),
        Column("enable_https", "enableHttps", Kind.boolean),
        Column("updated_at", "updatedAt", Kind.datetime),
        Column("urls", "urls", Kind.jsonArray),
        Column("key", "key", Kind.text, false, "\"key\""),
      ],
      [Relation("org", "org_id", "organizations")],
      [
        Derived("qualifiedName", ["org"], "{org.name}.{name}"),
        Derived("qualifiedTitle", ["org"], "{org.shortTitle}{title}"),
      ],
      "name",
      [ValueList("tags", "test.cfg_profile_tags", "profile_id", "value_")],
      [ManyRelation("members", "organizations", "test.cfg_profile_members", "profile_id", "org_id")]),
  ]);
}

Row orgRow(string id, string name, string title) {
  Row row;
  row["id"] = Json(id);
  row["name"] = Json(name);
  row["title"] = Json(title);
  row["short_title"] = Json(name);
  return row;
}

/// 配置行：外键的行键是**关系名** `org`（对应 SQL 里的 `t.org_id as org`）。
Row profileRow(string id, string name, string title, string orgId, string updatedAt = "2024-01-31 12:00:00") {
  Row row;
  row["id"] = Json(id);
  row["name"] = Json(name);
  row["title"] = Json(title);
  row["http_port"] = Json(80L);
  row["enable_https"] = Json(true);
  row["updated_at"] = Json(updatedAt);
  row["key"] = Json("0123456789abcdef0123456789abcdef");
  row["org"] = orgId.length == 0 ? Json(null) : Json(orgId);
  return row;
}

/// 灌好演示数据的内存后端。
MemoryDao fixtureDao(Registry reg) {
  auto dao = new MemoryDao(reg);
  dao.seed(reg.find("organizations"), orgRow("1", "beangle", "Beangle 社区"));
  dao.seed(reg.find("organizations"), orgRow("2", "openurp", "OpenURP 教务"));
  dao.seed(reg.find("profiles"), profileRow("1001", "demo", "演示配置", "1"));
  dao.seed(reg.find("profiles"), profileRow("1002", "prod", "生产配置", "2", "2024-02-01 08:30:00"));
  return dao;
}

/// 装好演示数据与默认值钩子的服务层：应用侧照这个形状装配（见 README）。
Store fixtureStore(Registry reg) {
  auto store = new Store(reg, fixtureDao(reg));
  store.fillDefaults = (const Resource res, ref Row values) { fixtureDefaults(res, values); };
  return store;
}

/// 「服务端生成」的默认值：只读列（凭证）在钩子里补，而不是让客户端传。
private void fixtureDefaults(const Resource res, ref Row values) {
  if (res.path == "profiles" && isBlank(rowGet(values, "key")))
    values["key"] = Json(randomKey());
}

/// 16 字节随机数的十六进制（与 Scala 侧 Profile.key 同形）。
private string randomKey() {
  ubyte[16] bytes;
  static foreach (i; 0 .. 16)
    bytes[i] = uniform!ubyte;
  // toHexString 给的是大写，统一成小写（与 Scala 侧 hex 同形）
  return toHexString(bytes[]).idup.toLower;
}
