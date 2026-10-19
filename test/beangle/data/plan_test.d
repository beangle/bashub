/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.data.plan_test;
/// 查询计划与 SQL 生成：把 beangle `Conditions` 的过滤语义固定在测试里。

import beangle.data.plan;
import beangle.data.query;
import beangle.data.resource;

import test.beangle.fixture;

import std.algorithm : canFind;
import std.exception : assertNotThrown, assertThrown;
import std.string : indexOf, lastIndexOf;

@("plan keeps projections and always pages")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("organizations");
  auto plan = buildPlan(reg, res, parseQuery(["page[number]": "2", "page[size]": "10"]));
  assert(plan.from == "bas.cfg_organizations t");
  assert(plan.selectList.canFind("t.name as name"));
  assert(plan.selectList.canFind("t.id as id"));
  assert(plan.limit == 10);
  assert(plan.offset == 10);
  auto sql = planSql(plan);
  assert(sql.canFind("order by t.name"));
  assert(sql.canFind("limit 10 offset 10"));
}

@("string filters follow beangle's anchor syntax")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("organizations");
  assert(whereSql(buildPlan(reg, res, parseQuery(["filter[name]": "abc"]))) == "t.name like ?");
  assert(planValues(buildPlan(reg, res, parseQuery(["filter[name]": "abc"]))) == ["%abc%"]);

  assert(planValues(buildPlan(reg, res, parseQuery(["filter[name]": "^abc"]))) == ["abc%"]);
  assert(planValues(buildPlan(reg, res, parseQuery(["filter[name]": "abc$"]))) == ["%abc"]);
  assert(whereSql(buildPlan(reg, res, parseQuery(["filter[name]": "^abc$"]))) == "t.name = ?");
  assert(planValues(buildPlan(reg, res, parseQuery(["filter[name]": "^abc$"]))) == ["abc"]);

  // null → is null，且不占参数位
  auto nullPlan = buildPlan(reg, res, parseQuery(["filter[title]": "null"]));
  assert(whereSql(nullPlan) == "t.title is null");
  assert(planValues(nullPlan).length == 0);
}

@("number filters compare with =")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("profiles");
  auto plan = buildPlan(reg, res, parseQuery(["filter[httpPort]": "80"]));
  assert(whereSql(plan) == "t.http_port = ?");
  assert(planValues(plan) == ["80"]);
}

@("relation filters join the target table")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("profiles");
  auto plan = buildPlan(reg, res, parseQuery(["filter[org.name]": "beangle", "sort": "org"]));
  assert(plan.joins.length == 1);
  assert(plan.joins[0].table == "bas.cfg_organizations");
  assert(plan.joins[0].name == "org");
  assert(plan.joins[0].on == "org.id = t.org_id");
  assert(whereSql(plan) == "org.name like ?");
  assert(plan.orders[0] == "org.id");
  // 关系过滤与关系排序都要 join，但只 join 一次
  auto sql = planSql(plan);
  assert(sql.indexOf("left join bas.cfg_organizations org") == sql.lastIndexOf("left join bas.cfg_organizations org"));
  assert(countSql(plan).canFind("select count(*) as total from bas.cfg_profiles t"));
}

@("foreign key filters compare by id")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("profiles");
  auto plan = buildPlan(reg, res, parseQuery(["filter[org]": "1"]));
  assert(whereSql(plan) == "t.org_id = ?");
  assert(planValues(plan) == ["1"]);
}

@("implicit multi-value filters use or/in")
unittest {
  auto reg = fixtureRegistry();
  auto orgs = reg.find("organizations");

  auto two = buildPlan(reg, orgs, parseQuery(["filter[name]": "beangle,openurp"]));
  assert(whereSql(two) == "(t.name like ? or t.name like ?)");
  assert(planValues(two) == ["%beangle%", "%openurp%"]);

  auto four = buildPlan(reg, orgs, parseQuery(["filter[name]": "a,b,c,d"]));
  assert(whereSql(four) == "t.name in (?, ?, ?, ?)");
  assert(planValues(four) == ["a", "b", "c", "d"]);

  auto ports = buildPlan(reg, reg.find("profiles"), parseQuery(["filter[httpPort]": "80;8080"]));
  assert(whereSql(ports) == "t.http_port in (?, ?)");
  assert(planValues(ports) == ["80", "8080"]);
}

@("explicit filter operators map to SQL operators")
unittest {
  auto reg = fixtureRegistry();
  auto orgs = reg.find("organizations");

  assert(whereSql(buildPlan(reg, orgs, parseQuery(["filter[name][eq]": "beangle"]))) == "t.name = ?");
  assert(whereSql(buildPlan(reg, orgs, parseQuery(["filter[name][ne]": "beangle"]))) == "t.name != ?");
  assert(whereSql(buildPlan(reg, orgs, parseQuery(["filter[name][in]": "beangle,openurp"]))) ==
      "t.name in (?, ?)");
  assert(whereSql(buildPlan(reg, orgs, parseQuery(["filter[name][nin]": "a;b"]))) == "t.name not in (?, ?)");

  auto port = buildPlan(reg, reg.find("profiles"), parseQuery(["filter[httpPort][ge]": "8080"]));
  assert(whereSql(port) == "t.http_port >= ?");
  assert(planValues(port) == ["8080"]);

  auto between = buildPlan(reg, reg.find("profiles"), parseQuery(["filter[httpPort][between]": "80,8080"]));
  assert(whereSql(between) == "t.http_port between ? and ?");
  assert(planValues(between) == ["80", "8080"]);

  auto lt = buildPlan(reg, reg.find("profiles"), parseQuery(["filter[httpPort][lt]": "443"]));
  assert(whereSql(lt) == "t.http_port < ?");
  assert(planValues(lt) == ["443"]);
}

@("datetime end filters expand date-only values")
unittest {
  auto reg = fixtureRegistry();
  auto profiles = reg.find("profiles");

  auto le = buildPlan(reg, profiles, parseQuery(["filter[updatedAt][le]": "2024-01-31"]));
  assert(whereSql(le) == "t.updated_at <= ?");
  assert(planValues(le) == ["2024-01-31T23:59:59.999999999"]);

  auto lt = buildPlan(reg, profiles, parseQuery(["filter[updatedAt][lt]": "2024-01-31 12:30"]));
  assert(planValues(lt) == ["2024-01-31T12:30:59.999999999"]);

  auto between = buildPlan(reg, profiles,
      parseQuery(["filter[updatedAt][between]": "2024-01-01,2024-01-31"]));
  assert(planValues(between) == ["2024-01-01T00:00:00", "2024-01-31T23:59:59.999999999"]);

  auto ge = buildPlan(reg, profiles, parseQuery(["filter[updatedAt][ge]": "2024-01-01"]));
  assert(planValues(ge) == ["2024-01-01T00:00:00"]);
}

@("unknown keys are rejected")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("organizations");
  assertThrown!QueryException(buildPlan(reg, res, parseQuery(["filter[whatever]": "x"])));
  assertThrown!QueryException(buildPlan(reg, res, parseQuery(["sort": "whatever"])));
  assertNotThrown(buildPlan(reg, res, parseQuery(["sort": "-name"])));
}
