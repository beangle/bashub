/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.jsonapi.store_test;
/// 服务层端到端（内存后端）：查询 → 计划 → 行 → 文档，以及写入往返。

import beangle.data.query;
import beangle.data.resource;
import beangle.jsonapi.store;

import test.beangle.fixture;

import vibe.data.json : Json, parseJsonString;

import std.exception : assertThrown;

@("search returns a paged collection")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  auto doc = store.search(reg.find("organizations"), parseQuery(["page[size]": "1"]));
  assert(doc["data"].length == 1);
  assert(doc["meta"]["page"]["total"].get!long == 2);
  assert(doc["meta"]["page"]["size"].get!long == 1);
  // 默认排序是 name
  assert(doc["data"][0]["attributes"]["name"].get!string == "beangle");
}

@("string filter is a contains match, like the console expects")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  auto doc = store.search(reg.find("organizations"), parseQuery(["filter[name]": "urp"]));
  assert(doc["data"].length == 1);
  assert(doc["data"][0]["attributes"]["name"].get!string == "openurp");
}

@("multi-value and explicit filters share plan semantics in memory")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  auto orgs = reg.find("organizations");

  auto doc = store.search(orgs, parseQuery(["filter[name]": "beangle,openurp"]));
  assert(doc["meta"]["page"]["total"].get!long == 2);

  doc = store.search(orgs, parseQuery(["filter[name][in]": "beangle;openurp"]));
  assert(doc["meta"]["page"]["total"].get!long == 2);

  doc = store.search(orgs, parseQuery(["filter[name][ne]": "beangle"]));
  assert(doc["meta"]["page"]["total"].get!long == 1);
  assert(doc["data"][0]["attributes"]["name"].get!string == "openurp");

  doc = store.search(orgs, parseQuery([QueryParam("filter[name]", "beangle"),
      QueryParam("filter[name]", "openurp")]));
  assert(doc["meta"]["page"]["total"].get!long == 2);

  auto profiles = reg.find("profiles");
  doc = store.search(profiles, parseQuery(["filter[httpPort][between]": "80,80"]));
  assert(doc["meta"]["page"]["total"].get!long == 2);
  doc = store.search(profiles, parseQuery(["filter[httpPort][gt]": "80"]));
  assert(doc["meta"]["page"]["total"].get!long == 0);

  doc = store.search(profiles,
      parseQuery(["filter[updatedAt][between]": "2024-01-01,2024-01-31"]));
  assert(doc["meta"]["page"]["total"].get!long == 1);
  assert(doc["data"][0]["attributes"]["name"].get!string == "demo");
}

@("search expands derived attributes and include")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  auto doc = store.search(reg.find("profiles"), parseQuery(["filter[name]": "demo", "include": "org"]));
  assert(doc["data"].length == 1);
  assert(doc["data"][0]["attributes"]["qualifiedName"].get!string == "beangle.demo");
  assert(doc["included"].length == 1);
  assert(doc["included"][0]["type"].get!string == "organizations");
  assert(doc["included"][0]["id"].get!string == "1");
}

@("search joins for a relation filter")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  auto doc = store.search(reg.find("profiles"), parseQuery(["filter[org.name]": "openurp"]));
  assert(doc["meta"]["page"]["total"].get!long == 1);
  assert(doc["data"][0]["attributes"]["name"].get!string == "prod");
}

@("fetch returns one document, missing id returns false")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  Json doc;
  assert(store.fetch(reg.find("profiles"), "1001", Query.init, doc));
  assert(doc["data"]["id"].get!string == "1001");
  assert(doc["data"]["attributes"]["qualifiedName"].get!string == "beangle.demo");
  assert(!store.fetch(reg.find("profiles"), "999999", Query.init, doc));
}

@("create fills defaults and generates the profile key")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  auto body = parseJsonString(`{"data":{"type":"profiles","attributes":{"name":"test","title":"测试"},
      "relationships":{"org":{"data":{"type":"organizations","id":"2"}}}}}`);
  auto doc = store.create(reg.find("profiles"), body);
  assert(doc["data"]["attributes"]["name"].get!string == "test");
  // 新建的 key 是 32 位十六进制，与 Scala 侧 16 字节随机数同形
  auto key = doc["data"]["attributes"]["key"].get!string;
  assert(key.length == 32);
  assert(isHex(key));
  assert(doc["data"]["relationships"]["org"]["data"]["id"].get!string == "2");
  assert(doc["data"]["attributes"]["qualifiedName"].get!string == "openurp.test");
}

@("update changes only the given attributes")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  Json doc;
  auto body = parseJsonString(`{"data":{"type":"profiles","attributes":{"title":"改过的名字"}}}`);
  assert(store.update(reg.find("profiles"), "1001", body, doc));
  assert(doc["data"]["attributes"]["title"].get!string == "改过的名字");
  assert(doc["data"]["attributes"]["name"].get!string == "demo");

  assert(!store.update(reg.find("profiles"), "999999", body, doc));
}

@("remove reports hits and misses")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  assert(store.remove(reg.find("profiles"), "1001"));
  assert(!store.remove(reg.find("profiles"), "1001"));
  assert(store.search(reg.find("profiles"), Query.init)["meta"]["page"]["total"].get!long == 1);
}

@("collections load as value attributes and to-many relationships")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("profiles");
  auto dao = fixtureDao(reg);
  dao.seedValues(res, "tags", "1001", ["alpha", "beta"]);
  dao.seedMany(res, "members", "1001", ["1", "2"]);
  auto store = new Store(reg, dao);

  Json doc;
  assert(store.fetch(res, "1001", Query.init, doc));
  auto tags = doc["data"]["attributes"]["tags"].get!(Json[]);
  assert(tags.length == 2);
  assert(tags[0].get!string == "alpha");
  auto members = doc["data"]["relationships"]["members"]["data"].get!(Json[]);
  assert(members.length == 2);
  assert(members[0]["type"].get!string == "organizations");
  assert(members[1]["id"].get!string == "2");
}

@("PATCH replaces value lists, to-many links and json arrays")
unittest {
  auto reg = fixtureRegistry();
  auto res = reg.find("profiles");
  auto store = fixtureStore(reg);
  auto body = parseJsonString(`{"data":{"attributes":{"tags":"alpha\nbeta","urls":"https://a\nhttps://b"},
      "relationships":{"members":{"data":[{"type":"organizations","id":"2"}]}}}}`);
  Json doc;
  assert(store.update(res, "1001", body, doc));

  auto tags = doc["data"]["attributes"]["tags"].get!(Json[]);
  assert(tags.length == 2);
  assert(tags[1].get!string == "beta");
  auto urls = doc["data"]["attributes"]["urls"].get!(Json[]);
  assert(urls.length == 2);
  assert(urls[0].get!string == "https://a");
  auto members = doc["data"]["relationships"]["members"]["data"].get!(Json[]);
  assert(members.length == 1);
  assert(members[0]["id"].get!string == "2");

  auto clear = parseJsonString(`{"data":{"attributes":{"tags":""},
      "relationships":{"members":{"data":[]}}}}`);
  assert(store.update(res, "1001", clear, doc));
  assert(doc["data"]["attributes"]["tags"].get!(Json[]).length == 0);
  assert(doc["data"]["relationships"]["members"]["data"].get!(Json[]).length == 0);
}

@("unknown attributes are rejected instead of silently dropped")
unittest {
  auto reg = fixtureRegistry();
  auto store = fixtureStore(reg);
  auto body = parseJsonString(`{"data":{"type":"organizations","attributes":{"nope":"x"}}}`);
  assertThrown!StoreException(store.create(reg.find("organizations"), body));
  assertThrown!StoreException(store.create(reg.find("organizations"), Json.emptyObject));
}

private bool isHex(string text) {
  foreach (c; text) {
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
      return false;
  }
  return true;
}
