/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.route_test;
/// 路由契约：URL 形状一旦不对，前端整片页面就是 404。
/// 通用 CRUD 由 beangle.jsonapi 提供，这里验的是 bas hub 自己的端点与装配（资源名是路由参数）。

import bashub.config;
import bashub.demo;
import bashub.resources;
import bashub.route;
import bashub.store;
import bashub.api : resourceApiGroup;
import bashub.agent.channel : Envelope, parse;
import bashub.agent.history : AgentHistoryStore, AgentSample;
import bashub.agent.registry : AgentRegistry;

import beangle.jsonapi.router : RouteOptions;
import beangle.data.resource : Registry;
import beangle.data.value : jsonText;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json, parseJson, parseJsonString;
import vibe.http.common : HTTPMethod;
import vibe.http.server : HTTPServerRequestHandler, createTestHTTPServerRequest, createTestHTTPServerResponse,
  TestHTTPResponseMode;
import vibe.inet.message : InetHeaderMap;
import vibe.inet.url : URL;
import vibe.stream.memory : createMemoryOutputStream, createMemoryStream;

import std.algorithm.searching : canFind, endsWith, startsWith;
import std.base64 : Base64;
import std.digest : LetterCase, toHexString;
import std.digest.sha : sha256Of;
import std.string : indexOf;

private struct Exchange {
  int status;
  string body;
  string contentType;
}

private final class FakeAgentHistory : AgentHistoryStore {
  string profileId;
  string profile;
  int daysCount;

  void record(string profileId, const(AgentSample)[] samples) {
  }

  Json query(string profileId, string profile, int daysCount) {
    this.profileId = profileId;
    this.profile = profile;
    this.daysCount = daysCount;
    return Json([
      "profile": Json(profile),
      "from": Json("2026-04-25T00:00:00+08:00"),
      "to": Json("2026-10-22T00:00:00+08:00"),
      "days": Json(cast(long) daysCount),
      "samples": Json([Json([
        "at": Json("2026-10-22T08:00:00+08:00"),
        "servers": Json(["platform.server1": Json("running")])
      ])])
    ]);
  }
}

private Exchange call(HTTPServerRequestHandler router, HTTPMethod method, string url, string body = null) {
  InetHeaderMap headers;
  headers["Accept"] = "application/vnd.api+json";
  if (body.length > 0)
    headers["Content-Type"] = "application/vnd.api+json";
  auto req = createTestHTTPServerRequest(URL(url), method, headers,
      body.length > 0 ? createMemoryStream(cast(ubyte[]) body.dup) : null);
  auto output = createMemoryOutputStream();
  auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);
  router.handleRequest(req, res);
  Exchange ex;
  ex.status = cast(int) res.statusCode;
  ex.body = cast(string) output.data;
  ex.contentType = res.contentType;
  return ex;
}

private Exchange callWithHeaders(HTTPServerRequestHandler router, HTTPMethod method, string url,
    string[string] headers) {
  InetHeaderMap requestHeaders;
  foreach (key, value; headers)
    requestHeaders[key] = value;
  auto req = createTestHTTPServerRequest(URL(url), method, requestHeaders);
  auto output = createMemoryOutputStream();
  auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);
  router.handleRequest(req, res);
  Exchange ex;
  ex.status = cast(int) res.statusCode;
  ex.body = cast(string) output.data;
  ex.contentType = res.contentType;
  return ex;
}

private Exchange upload(HTTPServerRequestHandler router, string url, string body,
    string contentType = "multipart/form-data; boundary=bashub-test") {
  InetHeaderMap headers;
  headers["Accept"] = "application/vnd.api+json";
  headers["Content-Type"] = contentType;
  auto req = createTestHTTPServerRequest(URL(url), HTTPMethod.POST, headers,
      createMemoryStream(cast(ubyte[]) body.dup));
  auto output = createMemoryOutputStream();
  auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);
  router.handleRequest(req, res);
  Exchange ex;
  ex.status = cast(int) res.statusCode;
  ex.body = cast(string) output.data;
  ex.contentType = res.contentType;
  return ex;
}

private string multipartBody(string appId, string xml) {
  return "--bashub-test\r\n" ~
    "Content-Disposition: form-data; name=\"app\"\r\n\r\n" ~ appId ~ "\r\n" ~
    "--bashub-test\r\n" ~
    "Content-Disposition: form-data; name=\"menufile\"; filename=\"menus.xml\"\r\n" ~
    "Content-Type: application/xml\r\n\r\n" ~ xml ~ "\r\n" ~
    "--bashub-test--\r\n";
}

private HTTPServerRequestHandler newRouter(bool authRequired = false, AgentRegistry agents = null) {
  auto reg = hubRegistry();
  return newRouterWith(reg, createHubStore(reg, demoDao(reg)), authRequired, agents);
}

private HTTPServerRequestHandler newRouterWith(Registry reg, Store store, bool authRequired = false,
    AgentRegistry agents = null) {
  HubConfig cfg;
  cfg.emsBase = "https://sas.openurp.net";
  cfg.appName = "bas-hub";
  cfg.authRequired = authRequired;
  return buildHubRouter(cfg, reg, store, null, agents);
}

@("API is grouped under /api/bashub by capability")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/configs");
  assert(ex.status == 200, ex.body);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/hub/configs");
  // URLRouter 未匹配时不会自动改写状态码；空响应表示旧前缀确实没有注册处理器。
  assert(ex.body.length == 0, ex.body);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/openurp.prod/config/server",
      ["Authorization": "Bearer fedcba9876543210fedcba9876543210"]);
  assert(ex.body.length == 0, ex.body);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/server",
      ["Authorization": "Bearer fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 200, ex.body);
}

@("configs is readable before login")
unittest {
  auto ex = call(newRouter(), HTTPMethod.GET, "http://localhost/api/bashub/ems/configs");
  assert(ex.status == 200);
  auto doc = parseJson(ex.body);
  assert(doc["ems_base"].get!string == "https://sas.openurp.net");
  assert(doc["app_name"].get!string == "bas-hub");
}

@("API groups keep ems, config and micdn resources separate")
unittest {
  auto router = newRouter();

  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search");
  assert(ex.status == 200, ex.body);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/menus/search");
  assert(ex.status == 200, ex.body);
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/channels/search");
  assert(ex.status == 200, ex.body);
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/resources/search");
  assert(ex.status == 200, ex.body);
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/apps/search");
  assert(ex.status == 200, ex.body);
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/app-groups/search");
  assert(ex.status == 200, ex.body);

  // 平台配置资源不再挂在 ems 下。
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/profiles/search");
  assert(ex.status == 404, ex.body);
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/apps/search");
  assert(ex.status == 404, ex.body);
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/app-groups/search");
  assert(ex.status == 404, ex.body);

  // micdn 资源既不在 ems，也不在 config 的通用 CRUD 里。
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/cdn-components/search");
  assert(ex.status == 404, ex.body);
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/cdn-components/search");
  assert(ex.status == 404, ex.body);

  // 旧的无域前缀不再兜底
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/profiles/search");
  assert(ex.body.length == 0, ex.body);
}

@("generic resource API group follows database table prefix")
unittest {
  foreach (item; hubRegistry().all) {
    auto group = resourceApiGroup(item);
    if (item.table.startsWith("bas.ems_"))
      assert(group == "ems", item.path ~ ": " ~ item.table);
    else if (item.table.startsWith("bas.cfg_"))
      assert(group == "config", item.path ~ ": " ~ item.table);
    else if (item.table.startsWith("bas.cdn_"))
      assert(group == "micdn", item.path ~ ": " ~ item.table);
    else
      assert(false, "unclassified resource table: " ~ item.table);
  }
}

@("agent handshake rejects a missing or wrong key before upgrade")
unittest {
  auto router = newRouter();
  string[string] emptyHeaders;
  auto ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/channel", emptyHeaders);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/channel", ["Authorization": "Bearer wrong"]);
  assert(ex.status == 401);

  // 正确的 key 会进入协议升级校验；这条测试请求没有 Upgrade 头，因此是 400，而不是 401
  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/channel",
      ["Authorization": "Bearer fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 400);
}

@("agents/status lists only the online connections")
unittest {
  auto agents = new AgentRegistry();
  auto router = newRouter(false, agents);

  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/monitor/agents/status");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["agents"].get!(Json[]).length == 0);

  auto prod = agents.attach("openurp.prod", "1002");
  prod.host = "app1";
  // agent 只上报 gav/context；标题由 hub 按配置里的 webapp → artifact 反查补上
  prod.basReport = parseJsonString(`{
    "instances":[{"id":"prod-farm.app1","pid":100,"http.port":8080,"webapps":[
      {"id":"bas","uri":"gav://org.beangle.bashub:bas-web:0.0.8","context":"/bas"},
      {"id":"otk","uri":"gav://org.beangle.otk:beangle-otk-ws:war:0.0.30","context":"/api/tools"}
    ]}],
    "declared":[
      {"id":"prod-farm.app1","http.port":8080},
      {"id":"prod-farm.app2","http.port":8081,"webapps":[
        {"uri":"gav://org.beangle.bashub:bas-web:0.0.8","context":"/bas"}
      ]}
    ]
  }`);
  agents.attach("openurp.demo").host = "app0";
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/monitor/agents/status");
  assert(ex.status == 200);
  auto list = parseJson(ex.body)["agents"].get!(Json[]);
  assert(list.length == 2);
  assert(list[0]["profile"].get!string == "openurp.demo");
  assert(list[1]["host"].get!string == "app1");
  assert(list[1]["profileId"].get!string == "1002", "前端用 profileId 跳到配置详情");
  assert(list[1]["profileTitle"].get!string == "生产配置", "卡片大标题用 profile 的说明");
  // 卡片大标题：按 profile 的 org 前缀补上机构展示信息
  assert(list[0]["org"]["name"].get!string == "openurp");
  assert(list[0]["org"]["title"].get!string == "OpenURP 高校教务");
  assert(list[1]["org"]["shortTitle"].get!string == "URP");
  // webapp 标题按配置反查：/bas 命中 artifact 6001，未配置的 /api/tools 不加 title
  auto webapps = list[1]["basReport"]["instances"][0]["webapps"].get!(Json[]);
  assert(webapps[0]["title"].get!string == "BAS 控制台");
  assert(webapps[1]["title"].type == Json.Type.undefined);
  // 停止的实例来自 declared，也要按同样的规则补标题
  auto declared = list[1]["basReport"]["declared"].get!(Json[]);
  auto stoppedApps = declared[1]["webapps"].get!(Json[]);
  assert(stoppedApps[0]["title"].get!string == "BAS 控制台");
}

@("agents/status fills titles for declared-only stopped instances") unittest {
  auto agents = new AgentRegistry();
  auto router = newRouter(false, agents);

  auto person = agents.attach("openurp.prod", "1002");
  person.host = "app1";
  // 全部停止：instances 为空，只剩 declared；标题仍要按 profile 的 webapp 配置补上
  person.basReport = parseJsonString(`{
    "instances":[],
    "declared":[{"id":"prod-farm.app1","http.port":8080,"webapps":[
      {"uri":"gav://org.beangle.bashub:bas-web:0.0.8","context":"/bas"}
    ]}]
  }`);

  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/monitor/agents/status");
  assert(ex.status == 200);
  auto list = parseJson(ex.body)["agents"].get!(Json[]);
  assert(list.length == 1);
  auto declared = list[0]["basReport"]["declared"].get!(Json[]);
  auto webapps = declared[0]["webapps"].get!(Json[]);
  assert(webapps[0]["title"].get!string == "BAS 控制台");
}

@("agents/summary returns health counts without full snapshots") unittest {
  auto agents = new AgentRegistry();
  auto router = newRouter(false, agents);
  auto session = agents.attach("openurp.prod");
  session.host = "app1";
  Envelope hello;
  assert(parse(`{"type":"hello","at":"2026-10-16T10:00:00+08:00",
      "body":{"host":"app1","supports":["hello","report:health","agent:log"]}}`, hello));
  session.accept(hello);
  Envelope health;
  assert(parse(`{"type":"report:health","at":"2026-10-16T10:00:01+08:00",
      "body":{"servers":[{"id":"platform.server1","state":"running"},
        {"id":"portal.server1","state":"stopped"}]}}`, health));
  session.accept(health);

  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/monitor/agents/summary");
  assert(ex.status == 200, ex.body);
  auto item = parseJson(ex.body)["agents"].get!(Json[])[0];
  assert(item["running"].get!long == 1);
  assert(item["stopped"].get!long == 1);
  assert(item["health"].get!(Json[]).length == 2);
  assert(item["os"].type == Json.Type.undefined);
  assert(item["basReport"].type == Json.Type.undefined);
}

@("agents/history validates and forwards the query") unittest {
  auto history = new FakeAgentHistory();
  auto router = newRouter(false, new AgentRegistry(history));

  auto noHistory = newRouter(false, new AgentRegistry());
  auto ex = call(noHistory, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/history?days=180");
  assert(ex.status == 503, ex.body);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/history?days=0");
  assert(ex.status == 400, ex.body);
  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/history?days=181");
  assert(ex.status == 400, ex.body);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/missing.prod/history?days=180");
  assert(ex.status == 404, ex.body);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/history?days=180");
  assert(ex.status == 200, ex.body);
  assert(history.profileId == "1002");
  assert(history.profile == "openurp.prod");
  assert(history.daysCount == 180);
  auto samples = parseJson(ex.body)["samples"].get!(Json[]);
  assert(samples.length == 1);
  assert(samples[0]["servers"]["platform.server1"].get!string == "running");
}

@("agents/log validates the instance and reports an offline node")
unittest {
  auto router = newRouter(false, new AgentRegistry());

  auto ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/log?instance=platform.server1");
  assert(ex.status == 404, ex.body);
  assert(parseJson(ex.body)["errors"][0]["status"].get!string == "404");

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/log?instance=..%2Fetc%2Fpasswd");
  assert(ex.status == 400);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/log?instance=platform.server1&from=x");
  assert(ex.status == 400);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/log?instance=platform.server1&tail=-1");
  assert(ex.status == 400);
}

@("agents/log/follow validates parameters and requires log:read")
unittest {
  auto agents = new AgentRegistry();
  auto router = newRouter(false, agents);

  auto ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/log/follow?instance=platform.server1");
  assert(ex.status == 404, ex.body);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/log/follow?instance=..%2Fetc%2Fpasswd");
  assert(ex.status == 400, ex.body);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/log/follow?instance=platform.server1&tail=-1");
  assert(ex.status == 400, ex.body);

  auto session = agents.attach("openurp.prod");
  Envelope hello;
  assert(parse(`{"type":"hello","at":"2026-10-16T10:00:00+08:00",
      "body":{"host":"app1","supports":["hello","report:os","report:bas"]}}`, hello));
  session.accept(hello);
  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/log/follow?instance=platform.server1");
  assert(ex.status == 409, ex.body);
  assert(parseJson(ex.body)["errors"][0]["detail"].get!string == "unsupported:log:read");
}

@("agents/agent-log validates parameters and requires agent:log")
unittest {
  auto agents = new AgentRegistry();
  auto router = newRouter(false, agents);

  auto ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/agent-log?tail=100");
  assert(ex.status == 404, ex.body);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/agent-log?from=x");
  assert(ex.status == 400, ex.body);

  auto session = agents.attach("openurp.prod");
  Envelope hello;
  assert(parse(`{"type":"hello","at":"2026-10-16T10:00:00+08:00",
      "body":{"host":"app1","supports":["hello","report:os","report:bas"]}}`, hello));
  session.accept(hello);
  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/agent-log?tail=100");
  assert(ex.status == 409, ex.body);
  assert(parseJson(ex.body)["errors"][0]["detail"].get!string == "unsupported:agent:log");
}

@("agents/report queues report:now only when the agent supports it")
unittest {
  auto agents = new AgentRegistry();
  auto router = newRouter(false, agents);

  auto ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/report");
  assert(ex.status == 404, ex.body);

  auto session = agents.attach("openurp.prod");
  Envelope hello;
  assert(parse(`{"type":"hello","at":"2026-10-16T10:00:00+08:00",
      "body":{"host":"app1","supports":["hello","report:os","report:bas"]}}`, hello));
  session.accept(hello);

  ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/report");
  assert(ex.status == 409, ex.body);
  assert(session.takeOutbound().length == 0);

  assert(parse(`{"type":"hello","at":"2026-10-16T10:00:01+08:00",
      "body":{"host":"app1","supports":["hello","report:now"]}}`, hello));
  session.accept(hello);
  ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/report");
  assert(ex.status == 202, ex.body);
  auto messages = session.takeOutbound();
  assert(messages.length == 1);
  assert(parseJson(messages[0])["type"].get!string == "report:now");
}


@("agent commands need ?agent= when one profile has several agents") unittest {
  auto agents = new AgentRegistry();
  auto router = newRouter(false, agents);

  auto a = agents.attach("openurp.prod", "1002", "10.0.0.10");
  auto b = agents.attach("openurp.prod", "1002", "10.0.0.11");
  Envelope hello;
  assert(parse(`{"type":"hello","at":"2026-10-16T10:00:00+08:00",
      "body":{"host":"app1","supports":["hello","report:now"]}}`, hello));
  a.accept(hello);
  assert(parse(`{"type":"hello","at":"2026-10-16T10:00:00+08:00",
      "body":{"host":"app2","supports":["hello","report:now"]}}`, hello));
  b.accept(hello);

  auto ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/report");
  assert(ex.status == 409, ex.body);
  assert(parseJson(ex.body)["errors"][0]["detail"].get!string.canFind("?agent="));

  ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/report?agent=10.0.0.11");
  assert(ex.status == 202, ex.body);
  assert(a.takeOutbound().length == 0);
  assert(b.takeOutbound().length == 1);

  ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/report?agent=10.0.0.99");
  assert(ex.status == 404, ex.body);
}

@("agents/service validates the action, instance and agent capability")
unittest {
  auto agents = new AgentRegistry();
  auto router = newRouter(false, agents);
  auto body = `{"instance":"platform.server1"}`;

  auto ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/service/reload", body);
  assert(ex.status == 400, ex.body);

  ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/service/restart", `{}`);
  assert(ex.status == 400, ex.body);

  ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/service/restart",
      `{"instance":"../etc/passwd"}`);
  assert(ex.status == 400, ex.body);

  ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/service/restart", body);
  assert(ex.status == 404, ex.body);

  auto session = agents.attach("openurp.prod");
  Envelope hello;
  assert(parse(`{"type":"hello","at":"2026-10-16T10:00:00+08:00",
      "body":{"host":"app1","supports":["hello","report:os","report:bas"]}}`, hello));
  session.accept(hello);
  ex = call(router, HTTPMethod.POST,
      "http://localhost/api/bashub/monitor/agents/openurp.prod/service/restart", body);
  assert(ex.status == 409, ex.body);
  assert(parseJson(ex.body)["errors"][0]["detail"].get!string == "unsupported:service:restart");
}

@("configs.json keeps the webmvc suffix working")
unittest {
  auto ex = call(newRouter(), HTTPMethod.GET, "http://localhost/api/bashub/ems/configs.json");
  assert(ex.status == 200, ex.body);
  assert(parseJson(ex.body)["app_name"].get!string == "bas-hub");

  ex = call(newRouter(), HTTPMethod.GET, "http://localhost/api/bashub/ems/sessions.json");
  assert(ex.status == 200, ex.body);
}

@("profile config/server requires the profile key and returns server.xml")
unittest {
  auto router = newRouter();
  auto ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/server",
      ["Authorization": "Bearer fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "application/xml");
  assert(!ex.body.canFind("<hub"));
  assert(ex.body.canFind(`<webapp uri="gav://org.beangle.bashub:bas-web:war:0.0.8"`));
  assert(ex.body.canFind(`<snapshot-repo remote="${bas_remote_url}/maven" token="download-secret"/>`));
  assert(!ex.body.canFind("undertow"));

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/server", ["Authorization": "Bearer wrong"]);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/server", ["ip": "10.0.0.11"]);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/server", string[string].init);
  assert(ex.status == 401);
}

@("SPA can view server, proxy and setline config by profile id without the machine token")
unittest {
  auto reg = hubRegistry();
  auto store = createHubStore(reg, demoDao(reg));
  auto router = newRouterWith(reg, store);
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/1002/server");
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "application/xml");
  assert(!ex.body.canFind("<hub"));
  assert(!ex.body.canFind("download-secret"));
  assert(ex.body.canFind(`<snapshot-repo remote="${bas_remote_url}/maven" token="********"/>`));

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/1002/proxy");
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "text/plain");
  assert(ex.body.canFind("upstream prod-farm{"));

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/1002/setline-peers");
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "application/json", ex.contentType);
  assert(parseJson(ex.body)["peers"].length == 2);

}

@("profile config/proxy requires the profile key and returns the selected proxy config")
unittest {
  auto router = newRouter();
  auto ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/proxy",
      ["Authorization": "Bearer fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "text/plain");
  assert(ex.body.canFind("upstream prod-farm{"));
  assert(ex.body.canFind("location /bas {"));

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/proxy",
      ["Authorization": "Bearer openurp.prod:fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 200, ex.body);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/proxy",
      ["Authorization": "Bearer beangle.demo:fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/proxy", ["Authorization": "Bearer wrong"]);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/proxy", ["ip": "10.0.0.11"]);
  assert(ex.status == 401);
}

@("profile config/setline-peers requires the profile key and follows the profile")
unittest {
  auto reg = hubRegistry();
  auto store = createHubStore(reg, demoDao(reg));
  auto router = newRouterWith(reg, store);
  auto ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/setline-peers",
      ["Authorization": "Bearer openurp.prod:fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "application/json");
  auto config = parseJson(ex.body);
  assert(config["peers"].length == 2);
  assert(config["agent"].type == Json.Type.undefined);
  assert(config["peers"][0]["name"].get!string == "host01");
  assert(config["peers"][0]["url"].get!string == "http://10.0.0.11:8080");
  assert(config["peers"][1]["url"].get!string == "http://10.0.0.12:8082");
  assert(!ex.body.canFind("adminListen"));

  auto basic = cast(string) Base64.encode(cast(const(ubyte)[])
      "openurp.prod:fedcba9876543210fedcba9876543210");
  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/setline-peers", ["Authorization": "Basic " ~ basic]);
  assert(ex.status == 200, ex.body);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/setline-peers", ["Authorization": "Bearer wrong"]);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/beangle.demo/setline-peers",
      ["Authorization": "Bearer 0123456789abcdef0123456789abcdef"]);
  assert(ex.status == 200, ex.body);
  assert(parseJson(ex.body)["peers"].length == 0);
}

@("profile config/setline-manifest requires the key and hashes every downloaded body")
unittest {
  auto router = newRouter();
  auto auth = ["Authorization": "Bearer openurp.prod:fedcba9876543210fedcba9876543210"];
  auto ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/setline-manifest", auth);
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "application/json");
  auto resources = parseJson(ex.body)["resources"];

  string sha256Lower(string text) {
    return toHexString!(LetterCase.lower)(sha256Of(text)).idup;
  }
  auto peers = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/setline-peers", auth);
  auto proxy = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/proxy", auth);
  auto cert = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/certificate", auth);
  auto key = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/certificate-key", auth);
  assert(resources["peers"].get!string == sha256Lower(peers.body));
  assert(resources["proxy"].get!string == sha256Lower(proxy.body));
  assert(resources["certificate"].get!string == sha256Lower(cert.body));
  assert(resources["certificate-key"].get!string == sha256Lower(key.body));

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/setline-manifest",
      ["Authorization": "Bearer openurp.prod:wrong"]);
  assert(ex.status == 401);
}

@("profile ems menus resolve the app from deployed artifacts and return xml")
unittest {
  auto router = newRouter();
  auto ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/openurp.prod/menus/bas", ["ip": "10.0.0.11"]);
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "application/xml");
  assert(ex.body.canFind(`<resource name="/setting/config.action" title="配置管理" scope="Protected"/>`));
  assert(ex.body.canFind(`<menu indexno="1" name="设置" enName="setting"`));

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/openurp.prod/menus/missing", ["ip": "10.0.0.11"]);
  assert(ex.status == 404);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/openurp.prod/menus/bas", ["ip": "192.168.1.1"]);
  assert(ex.status == 404);
}

@("profile micdn.xml renders the complete profile configuration")
unittest {
  auto router = newRouter();
  auto profileKey = "fedcba9876543210fedcba9876543210";
  auto ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.prod/micdn.xml", ["Authorization": "Bearer " ~ profileKey]);
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "application/xml");
  assert(ex.body.canFind(
      `<micdn listen="0.0.0.0:8888" remote="http://localhost/api/bashub/micdn/openurp.prod/micdn.xml" home="/var/lib/micdn">`));
  assert(ex.body.canFind(`<maven base="/var/lib/micdn/maven">`));
  assert(ex.body.canFind(`<remote url="https://repo1.maven.org/maven2"/>`));
  assert(ex.body.canFind(`<auth publish-key="publish-secret" download-key="download-secret" max-size="64M"/>`));
  assert(ex.body.canFind(`<blob base="/var/lib/micdn/blob" max-size="50M">`));
  assert(ex.body.canFind(`<bucket name="prod" key="fedcba9876543210fedcba9876543210"/>`));
  assert(ex.body.canFind(`<static base="/var/cache/micdn/asset">`));
  assert(ex.body.canFind(`<bundle name="bas">`));
  assert(ex.body.canFind(`<jar gav="org.beangle.bashub:bas-web:0.0.8"/>`));
  assert(ex.body.canFind(`<www base="/var/cache/micdn/www">`));
  assert(ex.body.canFind(`<doc name="manual" npm="@beangle/manual@1.0.0" try-file="index.html"/>`));

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.prod/micdn.xml", ["X-Micdn-Token": profileKey]);
  assert(ex.status == 200, ex.body);

  auto basicValue = "prod:" ~ profileKey;
  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.prod/micdn.xml",
      ["Authorization": "Basic " ~ cast(string) Base64.encode(cast(const(ubyte)[]) basicValue)]);
  assert(ex.status == 200, ex.body);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.prod/micdn.xml", ["ip": "10.0.0.11"]);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.prod/micdn.xml", ["Authorization": "Bearer wrong"]);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.prod/micdn.xml", string[string].init);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.missing/micdn.xml", ["Authorization": "Bearer " ~ profileKey]);
  assert(ex.status == 401);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.prod/micdn.xml",
      ["Authorization": "Bearer " ~ profileKey, "X-Forwarded-Proto": "https",
       "X-Forwarded-Host": "hub.example.com"]);
  assert(ex.status == 200, ex.body);
  assert(ex.body.canFind(
      `remote="https://hub.example.com/api/bashub/micdn/openurp.prod/micdn.xml"`));
}

@("profile micdn aggregate masks secrets and preserves them on save")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/micdn/profiles/1002");
  assert(ex.status == 200, ex.body);
  auto doc = parseJson(ex.body);
  assert(doc["profile"]["qualifiedName"].get!string == "openurp.prod");
  assert(doc["config"]["auth"]["publishKeySet"].get!bool);
  assert(doc["config"]["auth"]["downloadKeySet"].get!bool);
  assert(doc["config"]["auth"].length == 3);
  assert(doc["config"]["blob"].length == 3);
  assert(doc["config"]["blob"]["declared"].type == Json.Type.undefined);
  assert(doc["config"]["remote"].type == Json.Type.undefined);
  assert(doc["profile"]["keyMasked"].get!string == "fe**10");
  assert(doc["bindings"].get!(Json[]).length == 2);
  assert(doc["components"].get!(Json[]).length == 2);
  assert(doc["xml"].get!string.canFind(
      `remote="http://localhost/api/bashub/micdn/openurp.prod/micdn.xml"`));
  assert(doc["xml"].get!string.canFind(`publish-key="********"`));
  assert(doc["xml"].get!string.canFind(`<bucket name="prod" key="fe**10"/>`));
  assert(!doc["xml"].get!string.canFind("publish-secret"));
  assert(!doc["xml"].get!string.canFind("fedcba9876543210fedcba9876543210"));

  auto config = doc["config"];
  config["home"] = Json("/srv/micdn");
  auto savedBindings = doc["bindings"].get!(Json[]);
  savedBindings[0]["mountName"] = Json("ignored-mount");
  auto body = Json.emptyObject;
  body["config"] = config;
  body["bindings"] = Json(savedBindings);
  ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/micdn/profiles/1002", body.toString);
  assert(ex.status == 200, ex.body);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.prod/micdn.xml",
      ["Authorization": "Bearer fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 200, ex.body);
  assert(ex.body.canFind(`home="/srv/micdn"`));
  assert(ex.body.canFind(`publish-key="publish-secret"`));
  assert(ex.body.canFind(`download-key="download-secret"`));
  assert(ex.body.canFind(`<bucket name="prod" key="fedcba9876543210fedcba9876543210"/>`));
  assert(ex.body.canFind(`<bundle name="bas">`));
  assert(!ex.body.canFind("ignored-mount"));

  auto cleared = doc["config"];
  cleared["auth"] = Json(["maxSize": Json("64M"), "publishKey": Json(""), "downloadKey": Json("")]);
  body["config"] = cleared;
  ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/micdn/profiles/1002", body.toString);
  assert(ex.status == 200, ex.body);
  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/micdn/openurp.prod/micdn.xml",
      ["Authorization": "Bearer fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 200, ex.body);
  assert(!ex.body.canFind("<auth"));
}

@("profile micdn returns 404 for missing profiles")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/micdn/profiles/9999");
  assert(ex.status == 404, ex.body);

  ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/micdn/profiles/9999",
      `{"config":{"listen":"0.0.0.0:8888","logLevel":"info"}}`);
  assert(ex.status == 404, ex.body);
}

@("profile micdn emits blob from the profile key without a saved config row")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/micdn/profiles/1001");
  assert(ex.status == 200, ex.body);
  auto doc = parseJson(ex.body);
  assert(doc["profile"]["keySet"].get!bool);
  assert(doc["config"]["blob"].length == 3);
  assert(doc["xml"].get!string.canFind(`<blob base="/blob" max-size="100M">`));
  assert(doc["xml"].get!string.canFind(`<bucket name="demo" key="01**ef"/>`));
}

@("webapp libs folds pasted newlines into commas")
unittest {
  auto reg = hubRegistry();
  auto store = createHubStore(reg, demoDao(reg));
  auto router = newRouterWith(reg, store);
  auto body = parseJsonString(`{"data":{"type":"webapps","id":"7001","attributes":{"libs":"a:b:1\nc:d:2"}}}`);
  auto ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/config/webapps/7001", body.toString);
  assert(ex.status == 200, ex.body);
  assert(parseJson(ex.body)["data"]["attributes"]["libs"].get!string == "a:b:1,c:d:2");
}

@("servers expose qualified name and host ip for deployment pickers")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/servers/search?filter[server.farm.id]=4001&include=farm,host");
  assert(ex.status == 200, ex.body);
  auto rows = parseJson(ex.body)["data"].get!(Json[]);
  assert(rows.length == 2);
  // 应用部署的「运行在」用 qualifiedName + hostIp 显示，避免不同群集的同名 server 混淆
  assert(rows[0]["attributes"]["qualifiedName"].get!string == "prod-farm.app1");
  assert(rows[0]["attributes"]["hostIp"].get!string == "10.0.0.11");
  assert(rows[0]["attributes"]["displayName"].get!string == "prod-farm.app1 (10.0.0.11)");
}

@("profile certificates live outside profile and are downloadable by token")
unittest {
  auto reg = hubRegistry();
  auto store = createHubStore(reg, demoDao(reg));
  auto cert = "-----BEGIN CERTIFICATE-----\nCERT\n-----END CERTIFICATE-----";
  auto cert2 = "-----BEGIN CERTIFICATE-----\nCERT2\n-----END CERTIFICATE-----";
  auto key = "-----BEGIN PRIVATE KEY-----\nKEY\n-----END PRIVATE KEY-----";
  assert(store.upsertColumns(reg.find("profile-certificates"), "1002", [
    "certificate": Json(cert), "private_key": Json(key),
  ]));
  auto router = newRouterWith(reg, store);

  // profile 资源不再携带证书大字段
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/1002");
  assert(ex.status == 200, ex.body);
  auto attributes = parseJson(ex.body)["data"]["attributes"];
  assert(attributes["sslCertificate"].type == Json.Type.undefined);
  assert(attributes["sslCertificateKey"].type == Json.Type.undefined);

  // 管理台专用端点：回公钥与「私钥是否已设置」，绝不回私钥原文
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/1002/certificate");
  assert(ex.status == 200, ex.body);
  auto info = parseJson(ex.body);
  assert(info["certificate"].get!string == cert);
  assert(info["keySet"].get!bool);
  assert(!ex.body.canFind("PRIVATE KEY"));

  // PATCH 只换公钥：私钥留空保持原值
  auto body = Json.emptyObject;
  body["certificate"] = Json(cert2);
  ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/config/profiles/1002/certificate",
      body.toString);
  assert(ex.status == 200, ex.body);
  auto cert2Pem = cert2 ~ "\n";
  auto updated = parseJson(ex.body);
  assert(updated["certificate"].get!string == cert2Pem);
  assert(updated["keySet"].get!bool);

  // 非法 PEM 拒绝
  body["certificate"] = Json("not a certificate");
  ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/config/profiles/1002/certificate",
      body.toString);
  assert(ex.status == 400, ex.body);

  // setline 的机器端点仍按 Profile key 下载
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/openurp.prod/certificate");
  assert(ex.status == 401, ex.body);
  ex = callWithHeaders(router, HTTPMethod.GET, "http://localhost/api/bashub/config/openurp.prod/certificate",
      ["Authorization": "Bearer openurp.prod:fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 200, ex.body);
  assert(ex.body == cert2Pem);
  ex = callWithHeaders(router, HTTPMethod.GET, "http://localhost/api/bashub/config/openurp.prod/certificate-key",
      ["Authorization": "Bearer openurp.prod:fedcba9876543210fedcba9876543210"]);
  assert(ex.status == 200, ex.body);
  assert(ex.body == key);
  ex = callWithHeaders(router, HTTPMethod.GET, "http://localhost/api/bashub/config/openurp.prod/certificate-key",
      ["Authorization": "Bearer openurp.prod:wrong"]);
  assert(ex.status == 401, ex.body);
}

@("cdn component CRUD validates static and www specs")
unittest {
  auto router = newRouter();

  auto create = parseJsonString(`{"kind":"static_bundle","name":"test-bundle","mountName":"demo-bundle","remark":"测试",
      "spec":{"sources":[{"kind":"jar","ref":"org.example:demo:1.0.0","inner":""}]}}`);
  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/micdn/components", create.toString);
  assert(ex.status == 201, ex.body);
  auto bundle = parseJson(ex.body)["data"];
  auto bundleId = bundle["id"].get!string;
  assert(bundle["kind"].get!string == "static_bundle");
  assert(bundle["mountName"].get!string == "demo-bundle");
  assert(bundle["spec"]["sources"].get!(Json[]).length == 1);

  auto noMount = parseJsonString(`{"kind":"static_bundle","name":"missing-mount",
      "spec":{"sources":[{"kind":"jar","ref":"org.example:demo:1.0.0"}]}}`);
  ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/micdn/components", noMount.toString);
  assert(ex.status == 400, ex.body);
  assert(parseJson(ex.body)["errors"][0]["source"]["parameter"].get!string == "mountName");

  auto mixed = parseJsonString(`{"kind":"static_bundle","name":"bad-bundle","mountName":"bad-bundle",
      "spec":{"sources":[
        {"kind":"jar","ref":"org.example:demo:1.0.0"},
        {"kind":"dir","ref":"/srv/static"}]}}`);
  ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/micdn/components", mixed.toString);
  assert(ex.status == 400, ex.body);
  assert(parseJson(ex.body)["errors"][0]["source"]["parameter"].get!string.canFind("spec.sources"));

  auto badWww = parseJsonString(`{"kind":"www_doc","name":"bad-doc","mountName":"bad-doc",
      "spec":{"source":{"kind":"npm","ref":"demo@1.0.0"},"autoDeploy":true}}`);
  ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/micdn/components", badWww.toString);
  assert(ex.status == 400, ex.body);

  auto retiredBucket = parseJsonString(`{"kind":"blob_bucket","name":"retired","mountName":"retired",
      "spec":{"key":"old","publicImages":true}}`);
  ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/micdn/components", retiredBucket.toString);
  assert(ex.status == 400, ex.body);
  assert(parseJson(ex.body)["errors"][0]["source"]["parameter"].get!string == "kind");

  ex = call(router, HTTPMethod.DELETE, "http://localhost/api/bashub/micdn/components/" ~ bundleId);
  assert(ex.status == 200, ex.body);
  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/micdn/components");
  assert(ex.status == 200, ex.body);
  foreach (component; parseJson(ex.body)["data"].get!(Json[]))
    assert(component["id"].get!string != bundleId);
}

@("profile host script resolves the host ip and returns shell text")
unittest {
  auto router = newRouter();
  auto ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/script/10.0.0.11", ["ip": "10.0.0.12"]);
  assert(ex.status == 200, ex.body);
  assert(ex.contentType == "text/x-shellscript");
  assert(ex.body.canFind("#!/bin/bash"));
  assert(ex.body.canFind("java -version"));
  assert(ex.body.canFind("node --version"));
  assert(ex.body.indexOf("java -version") < ex.body.indexOf("node --version"));

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/script/10.0.0.12", ["ip": "10.0.0.11"]);
  assert(ex.status == 200, ex.body);
  assert(ex.body.canFind("#!/bin/bash"));
  assert(!ex.body.canFind("java -version"));

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/script/10.0.0.10", ["ip": "10.0.0.11"]);
  assert(ex.status == 404);

  ex = callWithHeaders(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/openurp.prod/script/10.0.0.11", ["ip": "192.168.1.1"]);
  assert(ex.status == 404);
}

@("search/list/info/delete CRUD routes")
unittest {
  auto router = newRouter();

  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/search?page[size]=1");
  assert(ex.status == 200);
  auto doc = parseJson(ex.body);
  assert(doc["data"].length == 1);
  assert(doc["meta"]["page"]["total"].get!long == 2);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/1001");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["data"]["attributes"]["name"].get!string == "demo");

  ex = call(router, HTTPMethod.DELETE, "http://localhost/api/bashub/config/hosts/2001");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["success"].get!bool == true);
}

@("relation filters, include and derived attributes go through the framework")
unittest {
  auto router = newRouter();
  // 属性名（camelCase）过滤：前端发的就是这种
  auto ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/profiles/search?filter%5Borg.name%5D=openurp&include=org");
  assert(ex.status == 200);
  auto doc = parseJson(ex.body);
  assert(doc["meta"]["page"]["total"].get!long == 1);
  assert(doc["data"][0]["attributes"]["qualifiedName"].get!string == "openurp.prod");
  assert(doc["included"][0]["type"].get!string == "organizations");

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/hosts/search?filter%5Bprofile%5D=1002&sort=name");
  assert(parseJson(ex.body)["meta"]["page"]["total"].get!long == 2);

  // 前端统一带实体别名与引用主键（`filter[profile.name]` / `filter[webapp.profile.id]`）
  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/profiles/search?filter%5Bprofile.name%5D=demo&sort=profile.name");
  assert(parseJson(ex.body)["meta"]["page"]["total"].get!long == 1);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/resources/search?filter%5Bresource.scope%5D=Private");
  assert(parseJson(ex.body)["meta"]["page"]["total"].get!long == 1);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/platform-feature-scripts/search" ~
      "?filter%5BplatformFeatureScript.feature.id%5D=8001");
  assert(ex.status == 200, ex.body);
  assert(parseJson(ex.body)["meta"]["page"]["total"].get!long == 1);

  ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/webapps/search?filter%5Bwebapp.profile.id%5D=1002" ~
      "&include=artifact,targets,targets.host");
  auto webapps = parseJson(ex.body);
  assert(webapps["meta"]["page"]["total"].get!long == 1);
  assert(webapps["data"][0]["attributes"]["urls"].get!(Json[]).length == 1);
  assert(webapps["data"][0]["relationships"]["targets"]["data"].get!(Json[]).length == 2);
  bool includedServer;
  bool includedHost;
  foreach (item; webapps["included"].get!(Json[])) {
    if (item["type"].get!string == "servers")
      includedServer = true;
    if (item["type"].get!string == "hosts")
      includedHost = true;
  }
  assert(includedServer);
  assert(includedHost);
}

@("post creates a row and returns 201")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/config/organizations",
      `{"data":{"type":"organizations","attributes":{"name":"neworg","title":"新机构"}}}`);
  assert(ex.status == 201);
  auto doc = parseJson(ex.body);
  assert(doc["data"]["attributes"]["name"].get!string == "neworg");
  // 新建后立刻能在列表里查到
  auto list = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/organizations/search?filter[name]=neworg");
  assert(list.status == 200);
  assert(parseJson(list.body)["meta"]["page"]["total"].get!long == 1);
  auto all = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/organizations/search");
  assert(parseJson(all.body)["meta"]["page"]["total"].get!long == 3);
}

@("patch updates and 404s on a missing id")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/config/organizations/1",
      `{"data":{"type":"organizations","attributes":{"title":"改名"}}}`);
  assert(ex.status == 200);
  assert(parseJson(ex.body)["data"]["attributes"]["title"].get!string == "改名");

  ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/config/organizations/9999",
      `{"data":{"type":"organizations","attributes":{"title":"x"}}}`);
  assert(ex.status == 404);
  assert(parseJson(ex.body)["errors"][0]["status"].get!string == "404");
}

@("unknown resource and unknown filter give 404/400")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/nothings/search");
  assert(ex.status == 404);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/organizations/search?filter[nope]=1");
  assert(ex.status == 400);
  assert(parseJson(ex.body)["errors"][0]["source"]["parameter"].get!string == "filter[nope]");
}

@("sessions endpoints")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/sessions");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["code"].get!string == "demo");

  ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/ems/sessions/logout");
  assert(ex.status == 200);
  assert(parseJson(ex.body)["logoutUrl"].get!string == "https://sas.openurp.net/cas/logout");
}

@("reset-key rotates the profile key and returns the new one")
unittest {
  auto router = newRouter();
  auto before = parseJson(call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/1001").body);
  auto oldKey = before["data"]["attributes"]["key"].get!string;

  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/config/profiles/1001/reset-key");
  assert(ex.status == 200);
  // 与 Scala 侧 ProfileWS.resetKey 同形：扁平的 {id, key}
  auto doc = parseJson(ex.body);
  assert(doc["id"].get!string == "1001");
  auto key = doc["key"].get!string;
  assert(key.length == 32);
  assert(isHex(key));
  // 重置即吊销：key 真的换了，而且落到了行上（详情里读到的就是新 key）
  assert(key != oldKey);
  auto after = parseJson(call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/profiles/1001").body);
  assert(after["data"]["attributes"]["key"].get!string == key);
}

@("reset-key 404s on a missing profile")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/config/profiles/9999/reset-key");
  assert(ex.status == 404);
  assert(parseJson(ex.body)["errors"][0]["status"].get!string == "404");
}

@("webapps upgrade copies the artifact latest version")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/config/webapps/7001",
      `{"data":{"type":"webapps","attributes":{"version":"0.0.7"}}}`);
  assert(ex.status == 200);
  assert(parseJson(ex.body)["data"]["attributes"]["version"].get!string == "0.0.7");

  ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/config/webapps/upgrade", `{"ids":["7001"]}`);
  assert(ex.status == 200);
  assert(parseJson(ex.body)["success"].get!bool);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/webapps/7001");
  assert(parseJson(ex.body)["data"]["attributes"]["version"].get!string == "0.0.8");
}

@("host webapps only returns deployments targeting that host")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/hosts/2001/webapps?include=artifact");
  assert(ex.status == 200, ex.body);
  auto doc = parseJson(ex.body);
  assert(doc["data"].length == 1);
  assert(jsonText(doc["data"][0]["id"]) == "7001");
  assert(doc["data"][0]["attributes"]["gav"].get!string == "org.beangle.bashub:bas-web:war:0.0.8");
  bool hasArtifact;
  foreach (item; doc["included"]) {
    if (jsonText(item["type"]) == "artifacts" && jsonText(item["id"]) == "6001")
      hasArtifact = true;
  }
  assert(hasArtifact);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/hosts/9999/webapps");
  assert(ex.status == 404);
}

@("artifact webapps lists deployments using that artifact")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/config/artifacts/6001/webapps?include=artifact");
  assert(ex.status == 200, ex.body);
  auto doc = parseJson(ex.body);
  assert(doc["meta"]["page"]["total"].get!long == 1);
  assert(jsonText(doc["data"][0]["id"]) == "7001");
  assert(doc["data"][0]["attributes"]["gav"].get!string == "org.beangle.bashub:bas-web:war:0.0.8");
  bool hasArtifact;
  foreach (item; doc["included"]) {
    if (jsonText(item["type"]) == "artifacts" && jsonText(item["id"]) == "6001")
      hasArtifact = true;
  }
  assert(hasArtifact);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/artifacts/6002/webapps");
  assert(ex.status == 200, ex.body);
  assert(parseJson(ex.body)["meta"]["page"]["total"].get!long == 0);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/config/artifacts/9999/webapps");
  assert(ex.status == 404);
}

@("resource menus lists menus using that resource")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/resources/13002/menus?include=entry,resources");
  assert(ex.status == 200, ex.body);
  auto doc = parseJson(ex.body);
  assert(doc["meta"]["page"]["total"].get!long == 1);
  assert(jsonText(doc["data"][0]["id"]) == "14002");
  assert(doc["data"][0]["attributes"]["entryUrl"].get!string == "/setting/config.action");

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/resources/13001/menus");
  assert(ex.status == 200, ex.body);
  assert(parseJson(ex.body)["meta"]["page"]["total"].get!long == 1);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/resources/9999/menus");
  assert(ex.status == 404);
}

@("reset-key needs a credential when auth is required")
unittest {
  auto ex = call(newRouter(true), HTTPMethod.POST,
      "http://localhost/api/bashub/config/profiles/1001/reset-key");
  assert(ex.status == 401);
  assert(parseJson(ex.body)["errors"][0]["meta"]["redirectUrl"].get!string == "https://sas.openurp.net/cas");
}

@("menus export emits resources and nested menus as xml")
unittest {
  auto ex = call(newRouter(), HTTPMethod.GET, "http://localhost/api/bashub/ems/menus/export?app=11001");
  assert(ex.status == 200, ex.body);
  auto xml = parseJson(ex.body)["xml"].get!string;
  assert(xml.startsWith("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<profile>"));
  assert(xml.canFind("<resource name=\"/setting/config.action\" title=\"配置管理\" scope=\"Protected\"/>"));
  assert(xml.canFind("<resource name=\"/setting/menu.action\" title=\"菜单管理\" scope=\"Private\"/>"));
  assert(xml.canFind("<menu indexno=\"1\" name=\"设置\" enName=\"setting\" params=\"\" fonticon=\"fa-cog\">"));
  assert(xml.canFind("<menu indexno=\"1.1\" name=\"配置管理\" enName=\"config\" " ~
      "entry=\"/setting/config.action\" params=\"\""));
  assert(xml.canFind("fonticon=\"fa-sliders\""));
  assert(xml.canFind("resources=\"/setting/menu.action\""));
  assert(xml.endsWith("</menu>\n</profile>"));
}

@("menus import merges resources and nested menus, then exports them back")
unittest {
  auto router = newRouter();
  auto xml = `<?xml version="1.0" encoding="UTF-8"?>
<profile>
  <resources>
    <resource name="/setting/new.action" title="新资源" scope="Public"/>
  </resources>
  <menu indexno="2" name="运维" enName="ops" fonticon="fa-tools">
    <children>
      <menu indexno="2.1" name="新资源" enName="new" entry="/setting/new.action"
            params="a=1&amp;b=2" resources="/setting/menu.action"/>
    </children>
  </menu>
</profile>`;
  auto ex = upload(router, "http://localhost/api/bashub/ems/menus/import", multipartBody("11001", xml));
  assert(ex.status == 200, ex.body);
  assert(parseJson(ex.body)["success"].get!bool);

  auto resources = parseJson(call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/resources/search?filter%5Bapp%5D=11001&page%5Bsize%5D=100").body)["data"];
  bool foundResource;
  foreach (ref item; resources) {
    auto attrs = item["attributes"];
    if (jsonText(attrs["name"]) == "/setting/new.action") {
      foundResource = true;
      assert(jsonText(attrs["title"]) == "新资源");
      assert(jsonText(attrs["scope"]) == "Public");
    }
  }
  assert(foundResource);

  auto menus = parseJson(call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/menus/search?filter%5Bapp%5D=11001&page%5Bsize%5D=100").body)["data"];
  string rootId;
  string childId;
  foreach (ref item; menus) {
    if (jsonText(item["attributes"]["indexno"]) == "2")
      rootId = jsonText(item["id"]);
    if (jsonText(item["attributes"]["indexno"]) == "2.1")
      childId = jsonText(item["id"]);
  }
  assert(rootId.length > 0 && childId.length > 0);
  auto detail = parseJson(call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/menus/" ~ childId ~ "?include=entry,resources").body);
  assert(jsonText(detail["data"]["relationships"]["parent"]["data"]["id"]) == rootId);
  assert(jsonText(detail["data"]["relationships"]["entry"]["data"]["id"]).length > 0);
  auto linked = detail["data"]["relationships"]["resources"]["data"].get!(Json[]);
  assert(linked.length == 2);

  ex = call(router, HTTPMethod.GET, "http://localhost/api/bashub/ems/menus/export?app=11001");
  assert(ex.status == 200, ex.body);
  auto exported = parseJson(ex.body)["xml"].get!string;
  assert(exported.canFind("<resource name=\"/setting/new.action\" title=\"新资源\"/>"));
  assert(exported.canFind("<menu indexno=\"2\" name=\"运维\" enName=\"ops\" fonticon=\"fa-tools\">"));
  assert(exported.canFind("params=\"a=1&amp;b=2\""));
  assert(exported.canFind("resources=\"/setting/menu.action\""));
}

@("menus import requires a file and an existing app")
unittest {
  auto router = newRouter();
  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/ems/menus/import");
  assert(ex.status == 400);

  ex = upload(router, "http://localhost/api/bashub/ems/menus/import", multipartBody("9999", "<profile/>"));
  assert(ex.status == 404);
}

@("menu indexno is a position and entry is linked into resources")
unittest {
  auto router = newRouter();
  auto body = `{"data":{"type":"menus","attributes":{
    "name":"置顶","enName":"top","indexno":"1","params":""},
    "relationships":{
      "app":{"data":{"type":"apps","id":"11001"}},
      "parent":{"data":null},
      "entry":{"data":{"type":"resources","id":"13001"}}}}}`;
  auto ex = call(router, HTTPMethod.POST, "http://localhost/api/bashub/ems/menus", body);
  assert(ex.status == 201, ex.body);
  auto created = parseJson(ex.body)["data"];
  auto id = jsonText(created["id"]);
  assert(jsonText(created["attributes"]["indexno"]) == "1");

  auto detail = parseJson(call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/menus/" ~ id ~ "?include=entry,resources").body);
  assert(jsonText(detail["data"]["relationships"]["entry"]["data"]["id"]) == "13001");
  bool entryLinked;
  foreach (ref item; detail["data"]["relationships"]["resources"]["data"]) {
    if (jsonText(item["id"]) == "13001")
      entryLinked = true;
  }
  assert(entryLinked);

  auto oldRoot = parseJson(call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/menus/14001").body)["data"];
  assert(jsonText(oldRoot["attributes"]["indexno"]) == "2");
  auto oldChild = parseJson(call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/menus/14002").body)["data"];
  assert(jsonText(oldChild["attributes"]["indexno"]) == "2.1");

  body = `{"data":{"type":"menus","attributes":{"indexno":"1"},
    "relationships":{"parent":{"data":{"type":"menus","id":"14001"}}}}}`;
  ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/ems/menus/" ~ id, body);
  assert(ex.status == 200, ex.body);
  auto moved = parseJson(ex.body)["data"];
  assert(jsonText(moved["attributes"]["indexno"]) == "2.1");

  oldChild = parseJson(call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/menus/14002").body)["data"];
  assert(jsonText(oldChild["attributes"]["indexno"]) == "2.2");
}

@("disabling a menu disables its subtree")
unittest {
  auto router = newRouter();
  auto body = `{"data":{"type":"menus","attributes":{"enabled":false}}}`;
  auto ex = call(router, HTTPMethod.PATCH, "http://localhost/api/bashub/ems/menus/14001", body);
  assert(ex.status == 200, ex.body);
  auto child = parseJson(call(router, HTTPMethod.GET,
      "http://localhost/api/bashub/ems/menus/14002").body)["data"];
  assert(child["attributes"]["enabled"].get!bool == false);
}

private bool isHex(string text) {
  foreach (c; text) {
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
      return false;
  }
  return true;
}
