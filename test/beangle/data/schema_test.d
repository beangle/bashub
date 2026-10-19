/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.data.schema_test;

import beangle.data.resource : Column, Kind, Registry, Resource;
import beangle.data.schema : checkSchema, expectedTables;

import test.beangle.fixture : fixtureRegistry;

import std.algorithm : canFind;

@("expected tables include main tables, value lists and join tables")
unittest {
  auto tables = expectedTables(fixtureRegistry());
  string[] names;
  foreach (shape; tables) {
    names ~= shape.table;
    if (shape.table == "bas.cfg_profiles") {
      assert(shape.columns.canFind("id"));
      assert(shape.columns.canFind("org_id"));
      assert(shape.columns.canFind("key")); // 双引号只是 SQL 转义，不是列名的一部分
    }
  }
  assert(names.canFind("bas.cfg_organizations"));
  assert(names.canFind("test.cfg_profile_tags"));
  assert(names.canFind("test.cfg_profile_members"));
}

@("schema check reports missing tables and columns only")
unittest {
  string[][string] actual;
  actual["bas.cfg_organizations"] = ["id", "name", "title", "short_title"];
  actual["bas.cfg_profiles"] =
    ["id", "name", "title", "http_port", "updated_at", "urls", "key", "org_id"];
  actual["test.cfg_profile_tags"] = ["profile_id", "value_"];

  auto issues = checkSchema(fixtureRegistry(), actual);
  assert(issues.length == 2);
  assert(issues[0].table == "bas.cfg_profiles");
  assert(issues[0].column == "enable_https");
  assert(issues[0].toString == "缺少列: bas.cfg_profiles.enable_https");
  assert(issues[1].table == "test.cfg_profile_members");
  assert(issues[1].column.length == 0);
  assert(issues[1].toString == "表不存在: test.cfg_profile_members");
}

@("complex SQL expressions are not treated as physical column names")
unittest {
  auto reg = new Registry([
    Resource(
      "things", "things", "bas.things", "id",
      [Column("name", "name", Kind.text, true, "lower(name)")],
      [], [], "id")
  ]);
  string[][string] actual;
  actual["bas.things"] = ["id"];
  assert(checkSchema(reg, actual).length == 0);
}
