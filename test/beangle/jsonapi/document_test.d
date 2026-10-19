/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.jsonapi.document_test;
/// 文档渲染：结构对齐前端 `src/api/resource.ts` 的读法（data / included / meta.page / errors）。

import beangle.jsonapi.document;
import beangle.data.resource;
import beangle.data.value;

import test.beangle.fixture;

import vibe.data.json : Json;

@("resource object carries attributes, relationships and derived values")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("profiles");
  RelIndex idx;
  idx["profiles:org"] = ["1": orgRow("1", "beangle", "Beangle 社区")];
  auto obj = resourceObject(reg, res, profileRow("1001", "demo", "演示配置", "1"), idx);

  assert(obj["type"].get!string == "profiles");
  assert(obj["id"].get!string == "1001");
  assert(obj["attributes"]["name"].get!string == "demo");
  // 数字与布尔保持类型（不是字符串），前端表格才能按 number/boolean 渲染
  assert(obj["attributes"]["httpPort"].get!long == 80);
  assert(obj["attributes"]["enableHttps"].get!bool == true);
  // 派生属性：qualifiedName = org.name + "." + name
  assert(obj["attributes"]["qualifiedName"].get!string == "beangle.demo");
  assert(obj["attributes"]["qualifiedTitle"].get!string == "beangle演示配置");
  // 外键只以 relationships 出现，不重复出现在 attributes
  assert(jsonGet(obj["attributes"], "org").type == Json.Type.undefined);
  assert(obj["relationships"]["org"]["data"]["type"].get!string == "organizations");
  assert(obj["relationships"]["org"]["data"]["id"].get!string == "1");
}

@("null foreign key becomes a null relationship")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("profiles");
  auto obj = resourceObject(reg, res, profileRow("1001", "demo", "演示配置", ""), RelIndex.init);
  assert(obj["relationships"]["org"]["data"].type == Json.Type.null_);
  // 取不到关系行时派生属性留空，而不是崩掉
  assert(obj["attributes"]["qualifiedName"].get!string == ".demo");
}

@("collection document carries meta.page")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("organizations");
  auto doc = listDocument(reg, res, [orgRow("1", "beangle", "Beangle 社区")], RelIndex.init, PageMeta(2, 10, 33),
      null);
  assert(doc["data"].length == 1);
  assert(doc["meta"]["page"]["number"].get!long == 2);
  assert(doc["meta"]["page"]["size"].get!long == 10);
  assert(doc["meta"]["page"]["total"].get!long == 33);
  assert(jsonGet(doc, "included").type == Json.Type.undefined);
}

@("errors and unauthorized documents")
unittest {
  auto err = errorDocument(404, "记录不存在", "no organizations with id 9", "filter[whatever]");
  assert(err["errors"][0]["status"].get!string == "404");
  assert(err["errors"][0]["source"]["parameter"].get!string == "filter[whatever]");

  auto unauthorized = unauthorizedDocument("https://sas.openurp.net/cas");
  assert(unauthorized["errors"][0]["status"].get!string == "401");
  assert(unauthorized["errors"][0]["meta"]["redirectUrl"].get!string == "https://sas.openurp.net/cas");
  assert(okDocument()["success"].get!bool == true);
}
