/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.store_test;
/// bas hub 特有的服务层行为：演示数据装配 + `fillDefaults`（配置的 key 由服务端生成）。
/// 通用查询/写入语义在 `beangle.data` / `beangle.jsonapi` 自己的测试里，这里不重复。

import beangle.data.query : Query, parseQuery;
import beangle.data.dao : DaoException;
import beangle.data.dao.memory : MemoryDao;
import beangle.data.resource : Registry, Resource, ValueList;
import beangle.data.value : Row, jsonText;
import beangle.jsonapi.store : Store, StoreException;

import bashub.demo : demoDao;
import bashub.resources : hubRegistry;
import bashub.store : createHubStore;

import vibe.data.json : Json, parseJsonString;

import std.exception : assertThrown;
import std.string : replace;

private Store newStore(out Registry reg) {
  reg = hubRegistry();
  return createHubStore(reg, demoDao(reg));
}

@("demo data covers the console resources")
unittest {
  Registry reg;
  auto store = newStore(reg);
  assert(store.search(reg.find("organizations"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("platforms"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("profiles"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("engines"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("farms"), Query.init)["meta"]["page"]["total"].get!long == 1);
  assert(store.search(reg.find("servers"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("hosts"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("artifacts"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("webapps"), Query.init)["meta"]["page"]["total"].get!long == 1);
  assert(store.search(reg.find("platform-features"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("app-groups"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("apps"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("channels"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("resources"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("menus"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("cdn-components"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.search(reg.find("profile-micdn"), Query.init)["meta"]["page"]["total"].get!long == 1);
  assert(store.search(reg.find("profile-micdn-components"), Query.init)["meta"]["page"]["total"].get!long == 2);
  assert(store.backend == "memory");
}

@("demo collections, nested includes and enum names render")
unittest {
  Registry reg;
  auto store = newStore(reg);

  auto engines = store.search(reg.find("engines"), parseQuery(["filter[name]": "tomcat"]));
  assert(engines["data"][0]["attributes"]["listeners"].get!(Json[]).length == 1);
  assert(engines["data"][0]["attributes"]["jars"].get!(Json[]).length == 1);

  auto farms = store.search(reg.find("farms"), parseQuery(["include": "hosts,servers,servers.host"]));
  auto farm = farms["data"][0];
  assert(farm["relationships"]["hosts"]["data"].get!(Json[]).length == 2);
  assert(farm["relationships"]["servers"]["data"].get!(Json[]).length == 2);
  bool hasServer;
  bool hasHostRelation;
  foreach (item; farms["included"].get!(Json[])) {
    if (item["type"].get!string == "servers")
      hasServer = true;
    if (item["type"].get!string == "hosts" && jsonText(item["relationships"]["profile"]["data"]["id"]) == "1002")
      hasHostRelation = true;
  }
  assert(hasServer);
  assert(hasHostRelation);

  auto resources = store.search(reg.find("resources"), parseQuery(["filter[scope]": "Private"]));
  assert(resources["meta"]["page"]["total"].get!long == 1);
  assert(resources["data"][0]["attributes"]["scope"].get!string == "Private");
}

@("profile key is generated server side and is 32 hex chars")
unittest {
  Registry reg;
  auto store = newStore(reg);
  auto doc = store.create(reg.find("profiles"),
      parseJsonString(`{"data":{"type":"profiles","attributes":{"name":"test","title":"测试",
      "basVersion":"0.0.8","ip":"127.0.0.1"},
      "relationships":{"org":{"data":{"type":"organizations","id":"2"}}}}}`));
  assert(doc["data"]["attributes"]["name"].get!string == "test");
  auto key = doc["data"]["attributes"]["key"].get!string;
  assert(key.length == 32);
  assert(isHex(key));
  // 与 Scala 侧 fillDefaults 同形：仓库地址与 https 开关也由服务端给默认值
  assert(doc["data"]["attributes"]["localRepo"].get!string == "~/.m2/repository");
  assert(doc["data"]["attributes"]["enableHttps"].get!bool == false);
  // 派生属性也在新建后的回读里出现
  assert(doc["data"]["attributes"]["qualifiedName"].get!string == "openurp.test");
}

@("a supplied key is kept; only a blank one is generated")
unittest {
  Registry reg;
  auto store = newStore(reg);
  auto doc = store.create(reg.find("profiles"),
      parseJsonString(`{"data":{"type":"profiles","attributes":{"name":"test","title":"测试",
      "basVersion":"0.0.8","ip":"127.0.0.1",
      "key":"ffffffffffffffffffffffffffffffff"}}}`));
  // 与 Scala 侧 fillDefaults 同口径：只在为空时生成，显式给的就留着
  assert(doc["data"]["attributes"]["key"].get!string == "ffffffffffffffffffffffffffffffff");
}

@("resource and channel writes get the same defaults and uniqueness as scala")
unittest {
  Registry reg;
  auto store = newStore(reg);

  auto resource = store.create(reg.find("resources"),
      parseJsonString(`{"data":{"type":"resources","attributes":{"name":"/probe/default.action","title":"默认值"},
      "relationships":{"app":{"data":{"type":"apps","id":"11001"}}}}}`));
  assert(resource["data"]["attributes"]["scope"].get!string == "Private");
  assert(resource["data"]["attributes"]["enabled"].get!bool);

  auto channel = store.create(reg.find("channels"),
      parseJsonString(`{"data":{"type":"channels","attributes":{"base":"/mobile","channelType":" MOBILE "},
      "relationships":{"app":{"data":{"type":"apps","id":"11001"}}}}}`));
  assert(channel["data"]["attributes"]["channelType"].get!string == "mobile");
  assert(channel["data"]["attributes"]["embedMode"].get!string == "iframe");
  assert(channel["data"]["attributes"]["enabled"].get!bool);

  assertThrown!StoreException(store.create(reg.find("channels"),
      parseJsonString(`{"data":{"type":"channels","attributes":{"base":"/dup","channelType":"pc"},
      "relationships":{"app":{"data":{"type":"apps","id":"11001"}}}}}`)));
}

@("new artifacts resolve support by default like scala")
unittest {
  Registry reg;
  auto store = newStore(reg);
  auto body = `{"data":{"type":"artifacts","attributes":{
    "title":"新组件","artifactId":"new-artifact","groupId":"org.example","packaging":"jar",
    "latestVersion":"1.0.0","arch":1}}}`;

  auto created = store.create(reg.find("artifacts"), parseJsonString(body));
  assert(created["data"]["attributes"]["resolveSupport"].get!bool);

  auto explicitFalse = body.replace(`"arch":1`, `"arch":1,"resolveSupport":false`);
  created = store.create(reg.find("artifacts"), parseJsonString(explicitFalse));
  assert(created["data"]["attributes"]["resolveSupport"].get!bool);
}

@("required fields are enforced on create and on provided update values")
unittest {
  Registry reg;
  auto store = newStore(reg);
  bool failed;
  try {
    store.create(reg.find("channels"),
        parseJsonString(`{"data":{"type":"channels","attributes":{"channelType":"mobile"},
        "relationships":{"app":{"data":{"type":"apps","id":"11001"}}}}}`));
  } catch (StoreException e) {
    failed = true;
    assert(e.attribute == "base");
  }
  assert(failed);

  Json doc;
  failed = false;
  try {
    store.update(reg.find("channels"), "12001",
        parseJsonString(`{"data":{"type":"channels","attributes":{"base":"  "}}}`), doc);
  } catch (StoreException e) {
    failed = true;
    assert(e.attribute == "base");
  }
  assert(failed);

  // PATCH 不要求把没改的必填字段再带一遍
  assert(store.update(reg.find("channels"), "12001",
      parseJsonString(`{"data":{"type":"channels","attributes":{"enabled":false}}}`), doc));
}

@("platform feature scripts drop carriage returns on create and update")
unittest {
  Registry reg;
  auto store = newStore(reg);
  auto script = store.create(reg.find("platform-feature-scripts"),
      parseJsonString(`{"data":{"type":"platform-feature-scripts","attributes":{"scripts":"a\r\nb\r\n"},
      "relationships":{"feature":{"data":{"type":"platform-features","id":"8001"}},
      "platform":{"data":{"type":"platforms","id":"1"}}}}}`));
  auto id = jsonText(script["data"]["id"]);
  assert(script["data"]["attributes"]["scripts"].get!string == "a\nb\n");

  Json updated;
  assert(store.update(reg.find("platform-feature-scripts"), id,
      parseJsonString(`{"data":{"type":"platform-feature-scripts","attributes":{"scripts":"x\r\ny"}}}`),
      updated));
  assert(updated["data"]["attributes"]["scripts"].get!string == "x\ny");
}

@("computed attributes match the console contract")
unittest {
  Registry reg;
  auto store = newStore(reg);

  auto artifacts = store.search(reg.find("artifacts"), parseQuery(["filter[artifactId]": "bas-web"]));
  auto artifact = artifacts["data"][0]["attributes"];
  assert(artifact["gav"].get!string == "org.beangle.bashub:bas-web:war:0.0.8");

  auto hosts = store.search(reg.find("hosts"), parseQuery(["filter[name]": "host01"]));
  auto logos = hosts["data"][0]["attributes"]["featureLogos"].get!(Json[]);
  assert(logos.length == 2);
  assert(logos[0]["name"].get!string == "JDK");
  assert(logos[1]["name"].get!string == "Node.js");

  hosts = store.search(reg.find("hosts"), parseQuery(["filter[name]": "host02"]));
  assert(hosts["data"][0]["attributes"]["featureLogos"].get!(Json[]).length == 0);

  Json webapp;
  assert(store.fetch(reg.find("webapps"), "7001", Query.init, webapp));
  assert(webapp["data"]["attributes"]["artifactName"].get!string == "bas-web");
  assert(webapp["data"]["attributes"]["gav"].get!string == "org.beangle.bashub:bas-web:war:0.0.8");
  assert(webapp["data"]["attributes"]["updatable"].get!bool == false);

  Row latest;
  latest["latest_version"] = Json("0.0.9");
  assert(store.updateColumns(reg.find("artifacts"), "6001", latest));
  assert(store.fetch(reg.find("webapps"), "7001", Query.init, webapp));
  assert(webapp["data"]["attributes"]["updatable"].get!bool == true);

  Json menu;
  assert(store.fetch(reg.find("menus"), "14002", Query.init, menu));
  assert(menu["data"]["attributes"]["entryUrl"].get!string == "/setting/config.action");

  Json component;
  assert(store.fetch(reg.find("cdn-components"), "17001", Query.init, component));
  assert(component["data"]["attributes"]["kind"].get!string == "static_bundle");
  assert(component["data"]["attributes"]["spec"]["sources"].get!(Json[]).length == 1);

  Json micdn;
  assert(store.fetch(reg.find("profile-micdn"), "1002", Query.init, micdn));
  assert(micdn["data"]["attributes"]["config"]["listen"].get!string == "0.0.0.0:8888");
}

@("a failed collection write rolls back the main row")
unittest {
  auto reg = hubRegistry();
  auto dao = new FailingDao(reg);
  auto store = new Store(reg, dao);
  bool failed;
  try {
    store.create(reg.find("engines"),
        parseJsonString(`{"data":{"type":"engines","attributes":{"name":"broken","typ":"tomcat",
        "version":"10","listeners":["a"]}}}`));
  } catch (DaoException e) {
    failed = true;
  }
  assert(failed);
  assert(dao.allRows(reg.find("engines")).length == 0);
}

/// 强制集合写入失败，验证主行不会留在库里。
private class FailingDao : MemoryDao {
  this(Registry reg) {
    super(reg);
  }

  override void replaceValues(const Resource res, const ValueList vl, string ownerId, const string[] values) {
    throw new DaoException("forced value-list failure");
  }
}

private bool isHex(string text) {
  foreach (c; text) {
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
      return false;
  }
  return true;
}
