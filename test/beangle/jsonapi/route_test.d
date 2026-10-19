/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.jsonapi.route_test;
/// 路由契约：URL 形状一旦不对，前端整片页面就是 404。
/// 这里直接对着 URLRouter 发请求，顺便验证「资源名是路由参数」这条设计。

import beangle.data.dao : DaoException;
import beangle.data.dao.memory : MemoryDao;
import beangle.data.resource : Registry, Resource;
import beangle.data.value : Row;
import beangle.jsonapi.router;
import beangle.jsonapi.store;

import test.beangle.fixture;

import vibe.data.json : Json, parseJson;
import vibe.http.common : HTTPMethod;
import vibe.http.server : HTTPServerRequestHandler, createTestHTTPServerRequest, createTestHTTPServerResponse, TestHTTPResponseMode;
import vibe.inet.message : InetHeaderMap;
import vibe.inet.url : URL;
import vibe.stream.memory : createMemoryOutputStream, createMemoryStream;

private struct Exchange {
  int status;
  string body;
}

private Exchange call(HTTPServerRequestHandler router, HTTPMethod method, string url, string body = null,
    string cookie = null) {
  InetHeaderMap headers;
  headers["Accept"] = "application/vnd.api+json";
  if (body.length > 0)
    headers["Content-Type"] = "application/vnd.api+json";
  if (cookie.length > 0)
    headers["Cookie"] = cookie;
  auto req = createTestHTTPServerRequest(URL(url), method, headers,
      body.length > 0 ? createMemoryStream(cast(ubyte[]) body.dup) : null);
  auto output = createMemoryOutputStream();
  auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);
  router.handleRequest(req, res);
  Exchange ex;
  ex.status = cast(int) res.statusCode;
  ex.body = cast(string) output.data;
  return ex;
}

private HTTPServerRequestHandler newRouter(RouteOptions opts = RouteOptions.init) {
  auto reg = fixtureRegistry();
  return buildJsonApiRouter(reg, fixtureStore(reg), opts);
}

private class ConstraintDao : MemoryDao {
  private string message;

  this(Registry reg, string message) {
    super(reg);
    this.message = message;
  }

  override string insert(const Resource res, Row values) {
    throw new DaoException(message);
  }
}

@("search/list/info/delete CRUD routes")
unittest {
  auto router = newRouter();

  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/profiles/search?page[size]=1");
  assert(ex.status == 200);
  auto doc = parseJson(ex.body);
  assert(doc["data"].length == 1);
  assert(doc["meta"]["page"]["total"].get!long == 2);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/profiles/1001");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["data"]["attributes"]["name"].get!string == "demo");

  ex = call(router, HTTPMethod.DELETE, "http://localhost/api/organizations/2");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["success"].get!bool == true);
}

@("post creates a row and returns 201")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/organizations",
      `{"data":{"type":"organizations","attributes":{"name":"neworg","title":"新机构"}}}`);
  assert(ex.status == 201);
  auto doc = parseJson(ex.body);
  assert(doc["data"]["attributes"]["name"].get!string == "neworg");
  // 新建后立刻能在列表里查到
  auto list = call(router, HTTPMethod.GET, "http://localhost/api/organizations/search?filter[name]=neworg");
  assert(list.status == 200);
  assert(parseJson(list.body)["meta"]["page"]["total"].get!long == 1);
  auto all = call(router, HTTPMethod.GET, "http://localhost/api/organizations/search");
  assert(parseJson(all.body)["meta"]["page"]["total"].get!long == 3);
}

@("repeated filters and pageSize cookie are honored")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET,
      "http://localhost/api/organizations/search?filter[name]=beangle&filter[name]=openurp");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["meta"]["page"]["total"].get!long == 2);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/organizations/search", null, "pageSize=1");
  auto doc = parseJson(ex.body);
  assert(doc["meta"]["page"]["size"].get!long == 1);
  assert(doc["data"].length == 1);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/organizations/search?page[size]=2", null, "pageSize=1");
  doc = parseJson(ex.body);
  assert(doc["meta"]["page"]["size"].get!long == 2);
}

@("json/jsonapi url suffix is stripped")
unittest {
  auto router = newRouter();
  foreach (suffix; [".json", ".jsonapi"]) {
    auto ex = call(router, HTTPMethod.GET, "http://localhost/api/profiles/search" ~ suffix);
    assert(ex.status == 200, suffix ~ " -> " ~ ex.body);
    assert(parseJson(ex.body)["meta"]["page"]["total"].get!long == 2);

    ex = call(router, HTTPMethod.GET, "http://localhost/api/profiles/1001" ~ suffix);
    assert(ex.status == 200, suffix ~ " -> " ~ ex.body);
    assert(parseJson(ex.body)["data"]["attributes"]["name"].get!string == "demo");
  }
}

@("patch updates and 404s on a missing id")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.PATCH, "http://localhost/api/organizations/1",
      `{"data":{"type":"organizations","attributes":{"title":"改名"}}}`);
  assert(ex.status == 200);
  assert(parseJson(ex.body)["data"]["attributes"]["title"].get!string == "改名");

  ex = call(router, HTTPMethod.PATCH, "http://localhost/api/organizations/9999",
      `{"data":{"type":"organizations","attributes":{"title":"x"}}}`);
  assert(ex.status == 404);
  assert(parseJson(ex.body)["errors"][0]["status"].get!string == "404");
}

@("unknown resource and unknown filter give 404/400")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/nothings/search");
  assert(ex.status == 404);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/organizations/search?filter[nope]=1");
  assert(ex.status == 400);
  assert(parseJson(ex.body)["errors"][0]["source"]["parameter"].get!string == "filter[nope]");
}

@("missing body is a 400, and authRequired writes the login redirect")
unittest {
  auto router = newRouter();
  // 没有 Content-Type / 空体：vibe 的 req.json 返回 undefined
  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/organizations");
  assert(ex.status == 400);
  // 体是合法 JSON 但没有 JSON:API 的 data
  ex = call(router, HTTPMethod.POST, "http://localhost/api/organizations", `{"foo":1}`);
  assert(ex.status == 400);
  // 体不是 JSON：也要是 400，而不是 500
  ex = call(router, HTTPMethod.POST, "http://localhost/api/organizations", `{"data":}`);
  assert(ex.status == 400);

  auto guarded = newRouter(RouteOptions("/api", true, "https://sas.openurp.net/cas"));
  ex = call(guarded, HTTPMethod.GET, "http://localhost/api/profiles/search");
  assert(ex.status == 401);
  auto doc = parseJson(ex.body);
  assert(doc["errors"][0]["meta"]["redirectUrl"].get!string == "https://sas.openurp.net/cas");
}

@("database constraints map to 409 or 400 instead of 500")
unittest {
  auto reg = fixtureRegistry();
  auto duplicate = new ConstraintDao(reg,
      `insert into bas.cfg_organizations failed: ERROR: duplicate key value violates unique constraint "uk_org_name"`);
  auto router = buildJsonApiRouter(reg, new Store(reg, duplicate));
  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/organizations",
      `{"data":{"type":"organizations","attributes":{"name":"beangle","title":"重复"}}}`);
  assert(ex.status == 409);
  assert(parseJson(ex.body)["errors"][0]["detail"].get!string == "违反唯一约束: uk_org_name");

  auto missing = new ConstraintDao(reg,
      `insert into bas.cfg_organizations failed: ERROR: null value in column "name" of relation "cfg_organizations" violates not-null constraint`);
  router = buildJsonApiRouter(reg, new Store(reg, missing));
  ex = call(router, HTTPMethod.POST, "http://localhost/api/organizations",
      `{"data":{"type":"organizations","attributes":{"title":"缺名称"}}}`);
  assert(ex.status == 400);
  assert(parseJson(ex.body)["errors"][0]["source"]["parameter"].get!string == "name");

  auto referenced = new ConstraintDao(reg,
      `insert into bas.cfg_organizations failed: ERROR: insert or update violates foreign key constraint "fk_org"`);
  router = buildJsonApiRouter(reg, new Store(reg, referenced));
  ex = call(router, HTTPMethod.POST, "http://localhost/api/organizations",
      `{"data":{"type":"organizations","attributes":{"name":"x"}}}`);
  assert(ex.status == 409);
}
