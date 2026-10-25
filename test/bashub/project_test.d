/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.project_test;
/// Project 配置分发：配置名与来源 IP 的解析、server.xml 的关键结构。

import bashub.demo : demoDao;
import bashub.project.distribution : loadProjectData;
import bashub.project.micdnconfig : BoundComponent, MicdnConfigException, MicdnState, defaultMicdnConfig,
  loadMicdnState, maskSecret, normalizeComponentSpec, normalizeMicdnConfig, renderMicdnXml;
import bashub.project.proxy : renderProxy;
import bashub.project.resolver : ProjectContext, findProject, ipHeaderAddresses, matchHostIp,
  resolveHostProject, resolveSetlineProject;
import bashub.project.script : FeatureScript, HostScriptModel, ScriptFeature, loadHostScriptModel, orderScripts,
  renderBashScript, renderHostScript;
import bashub.project.server : renderServerXml;
import bashub.project.peers : renderPeers;
import bashub.resources : hubRegistry;
import bashub.store : createHubStore;

import beangle.jsonapi.document : attributeText;
import beangle.data.query : Query;
import beangle.data.resource : Registry;
import beangle.data.value : Row, jsonGet;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json, parseJsonString;

import std.algorithm.searching : all, canFind;
import std.ascii : isASCII;
import std.exception : assertThrown;
import std.string : indexOf;

private Store newStore(out Registry reg) {
  reg = hubRegistry();
  return createHubStore(reg, demoDao(reg));
}

private MicdnConfigException expectConfigError(scope void delegate() action) {
  try {
    action();
  } catch (MicdnConfigException e) {
    return e;
  }
  assert(false, "expected MicdnConfigException");
}

@("setline accepts only the proxy ip") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;

  // demo 的 openurp.prod 代理内部 IP 是 10.0.0.10；Host 是 .11/.12，不能替代。
  assert(resolveSetlineProject(reg, store, "openurp.prod", "10.0.0.10", project));
  assert(project.id == "1002");
  assert(!resolveSetlineProject(reg, store, "openurp.prod", "10.0.0.11", project));
  assert(!resolveSetlineProject(reg, store, "openurp.prod", "192.168.1.1", project));
  assert(!resolveSetlineProject(reg, store, "openurp.prod", "", project));
  assert(!resolveSetlineProject(reg, store, "prod", "10.0.0.10", project));
  assert(!resolveSetlineProject(reg, store, "openurp.missing", "10.0.0.10", project));
}

@("agent ip header matches host ips and returns the canonical address") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;
  assert(findProject(reg, store, "openurp.prod", project));

  string matched;
  assert(matchHostIp(reg, store, project, ipHeaderAddresses("10.0.0.11"), matched));
  assert(matched == "10.0.0.11");
  // 多网卡全部上报：取配置里命中的那个
  assert(matchHostIp(reg, store, project, ipHeaderAddresses("127.0.0.1, 10.0.0.12"), matched));
  assert(matched == "10.0.0.12");
  // proxy 的内部 IP 不参与 agent 身份
  assert(!matchHostIp(reg, store, project, ipHeaderAddresses("10.0.0.10"), matched));
  assert(!matchHostIp(reg, store, project, ipHeaderAddresses("192.168.1.1"), matched));
  assert(ipHeaderAddresses("localhost").length == 0, "主机名不是身份");
  assert(ipHeaderAddresses("").length == 0);
}

@("agent ip must be declared by the project or one of its hosts") unittest {
  Registry reg;
  auto store = newStore(reg);
  // project 没有任何 ip / host 时不做兜底：无法验证的地址一律拒绝
  ProjectContext unknown;
  unknown.id = "999999";
  unknown.data = parseJsonString(`{"id":"999999","attributes":{}}`);
  string matched;
  assert(!matchHostIp(reg, store, unknown, ["10.0.0.10"], matched));
}

@("server.xml keeps the basctl contract")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;
  assert(findProject(reg, store, "openurp.prod", project));

  auto data = loadProjectData(store, reg, project);
  assert(data.engines.length == 1);
  assert(attributeText(data.engines[0], "name") == "tomcat");
  assert(data.artifacts.length == 1);
  assert(attributeText(data.artifacts[0], "artifactId") == "bas-web");
  assert(data.servers.length == 2);

  auto xml = renderServerXml(store, reg, project);
  assert(xml.canFind(`version="6.0.0"`));
  // Project 自己的 micdn 下载凭证优先于 hub.xml 的全局 token
  assert(renderServerXml(store, reg, project, false, "hub-secret").canFind(`token="download-secret"`));
  assert(xml.canFind(`<repository remote="https://repo.openurp.net/maven2"/>`));
  assert(xml.canFind(`<snapshot-repo remote="${bas_remote_url}/maven" token="download-secret"/>`));
  assert(!xml.canFind("<hub"));
  assert(xml.canFind(`setline-hostname="prod.openurp.net"`));

  assert(xml.canFind(`<engine name="tomcat" type="tomcat-server" version="10.1.42"`));
  assert(!xml.canFind("undertow"));
  assert(xml.canFind(`jsp-support="true" websocket-support="true"`));
  assert(xml.canFind(`<listener class-name="org.beangle.bas.listener.StartupListener"/>`));
  assert(xml.canFind(`<jar uri="org.beangle:beangle-webmvc:4.6.0"/>`));

  assert(xml.canFind(`<host name="host01" ip="10.0.0.11" agent-group="default_group" setline-listen-port="8080" setline-admin-port="10080"/>`));
  assert(xml.canFind(`<host name="host02" ip="10.0.0.12" agent-group="default_group" setline-listen-port="8082" setline-admin-port="10081"/>`));
  assert(xml.canFind(`<farm name="prod-farm" engine="tomcat" max-heap-size="2048M">`));
  assert(xml.canFind(`<server name="app1" host="host01" http="8080" proxy-http-port="9080"`));

  assert(xml.canFind(`uri="gav://org.beangle.bashub:bas-web:war:0.0.8"`));
  assert(xml.canFind(`path="/bas" run-at="prod-farm.app1,prod-farm.app2"`));
  assert(xml.canFind(`<url path="/bas"/>`));

  ProjectContext demo;
  assert(findProject(reg, store, "beangle.demo", demo));
  assert(!renderServerXml(store, reg, demo).canFind("setline-"));
}

@("server.xml falls back to the hub maven token") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext demo;
  assert(findProject(reg, store, "beangle.demo", demo));
  // 该 project 没有 micdn auth；用 hub.xml 的 maven-download-token 兜底
  auto xml = renderServerXml(store, reg, demo, false, "hub-secret");
  assert(xml.canFind(`token="hub-secret"`));
  // 预览遮掉令牌
  assert(renderServerXml(store, reg, demo, true, "hub-secret").canFind(`token="********"`));
}

@("server.xml rejects invalid host setline ports") unittest {
  Registry reg;
  auto store = newStore(reg);
  auto hosts = reg.find("hosts");
  ProjectContext project;
  // 本用例只验证端口校验，避免受 hostname/按域名分组状态影响。
  store.updateColumns(reg.find("proxy-settings"), "9002", ["proxy_by_hostname": Json(false)]);
  scope (exit)
    store.updateColumns(reg.find("proxy-settings"), "9002", ["proxy_by_hostname": Json(true)]);

  foreach (value; ["0", "70000", "not-a-port"]) {
    assert(store.updateColumns(hosts, "2001", ["setline_admin_port": Json(value)]));
    assert(findProject(reg, store, "openurp.prod", project));
    assertThrown!Exception(renderServerXml(store, reg, project));
  }
}

@("server.xml requires the project hostname only when proxyByHostname is enabled") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;
  scope (exit) {
    store.updateColumns(reg.find("projects"), "1002", ["hostname": Json("prod.openurp.net")]);
    store.updateColumns(reg.find("proxy-settings"), "9002", ["proxy_by_hostname": Json(true)]);
  }

  assert(store.updateColumns(reg.find("projects"), "1002", ["hostname": Json("")]));
  assert(store.updateColumns(reg.find("proxy-settings"), "9002",
      ["proxy_by_hostname": Json(false)]));
  assert(findProject(reg, store, "openurp.prod", project));
  auto xml = renderServerXml(store, reg, project);
  assert(!xml.canFind("setline-hostname"));
  assert(xml.canFind(`setline-listen-port="8080"`));

  assert(store.updateColumns(reg.find("proxy-settings"), "9002",
      ["proxy_by_hostname": Json(true)]));
  assert(findProject(reg, store, "openurp.prod", project));
  assertThrown!Exception(renderServerXml(store, reg, project));
}

@("peers contains web and micdn nodes")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;

  assert(findProject(reg, store, "beangle.demo", project));
  auto text = renderPeers(store, reg, project);
  auto config = parseJsonString(text);
  assert(config["peers"].length == 0);

  assert(findProject(reg, store, "openurp.prod", project));
  text = renderPeers(store, reg, project);
  config = parseJsonString(text);
  assert(config["peers"].length == 2);

  assert(store.updateColumns(reg.find("proxy-settings"), "9002", ["proxy_engine": Json("haproxy")]));
  assert(findProject(reg, store, "openurp.prod", project));
  text = renderPeers(store, reg, project);
  config = parseJsonString(text);
  assert(config["peers"].length == 2);
  assert(config["peers"][0]["name"].get!string == "host01");
  assert(config["peers"][0]["url"].get!string == "http://10.0.0.11:8080");
  assert(config["peers"][1]["name"].get!string == "host02");
  assert(config["peers"][1]["url"].get!string == "http://10.0.0.12:8082");
  assert(config["agent"].type == Json.Type.undefined);
  assert(!text.canFind("adminListen"));
  assert(!text.canFind(`"listen"`));

  Json configDoc;
  assert(store.fetch(reg.find("project-micdn"), "1002", Query.init, configDoc));
  auto micdnConfig = jsonGet(jsonGet(configDoc["data"], "attributes"), "config");
  micdnConfig["servers"] = Json([
    Json(["name": Json("cdn02"), "adminListen": Json("10.0.0.32:8081")]),
    Json(["name": Json("cdn01"), "adminListen": Json("10.0.0.31:8081")]),
  ]);
  assert(store.updateColumns(reg.find("project-micdn"), "1002", ["config": micdnConfig]));

  text = renderPeers(store, reg, project);
  config = parseJsonString(text);
  assert(config["peers"].length == 4);
  assert(config["peers"][0]["name"].get!string == "cdn01");
  assert(config["peers"][0]["url"].get!string == "http://10.0.0.31:8081");
  assert(config["peers"][1]["name"].get!string == "cdn02");
  assert(config["peers"][1]["url"].get!string == "http://10.0.0.32:8081");
}

@("peers reject invalid host setline listen ports") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;

  foreach (value; [0L, 65536L]) {
    assert(store.updateColumns(reg.find("hosts"), "2001", ["setline_listen_port": Json(value)]));
    assert(findProject(reg, store, "openurp.prod", project));
    assertThrown!Exception(renderPeers(store, reg, project));
  }
}

@("peers skip hosts without setline listen ports") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;
  Json updated;

  assert(store.update(reg.find("webapps"), "7001",
      parseJsonString(`{"data":{"type":"webapps","relationships":{"targets":{"data":[
        {"type":"servers","id":"5001"}]}}}}`), updated));
  assert(store.update(reg.find("hosts"), "2002",
      parseJsonString(`{"data":{"type":"hosts","attributes":{
        "setlineListenPort":null,"setlineAdminPort":null}}}`), updated));
  assert(findProject(reg, store, "openurp.prod", project));

  auto config = parseJsonString(renderPeers(store, reg, project));
  assert(config["peers"].length == 1);
  assert(config["peers"][0]["name"].get!string == "host01");
}

@("micdn server registrations normalize adminListen and stay out of micdn.xml")
unittest {
  auto raw = defaultMicdnConfig();
  raw["servers"] = Json([
    Json(["name": Json("cdn02"), "adminListen": Json("[2001:db8::2]:8081")]),
    Json(["name": Json("cdn01"), "adminListen": Json(" 10.0.0.31:8081 ")]),
  ]);
  auto config = normalizeMicdnConfig(raw);
  assert(config["servers"].length == 2);
  assert(config["servers"][0]["name"].get!string == "cdn01");
  assert(config["servers"][0]["adminListen"].get!string == "10.0.0.31:8081");
  assert(config["servers"][1]["adminListen"].get!string == "[2001:db8::2]:8081");
  auto xml = renderMicdnXml(config, [], "prod", "fedcba9876543210fedcba9876543210");
  assert(!xml.canFind("adminListen"));
  assert(!xml.canFind("cdn01"));

  auto invalid = defaultMicdnConfig();
  invalid["servers"] = Json([
    Json(["name": Json("cdn01"), "adminListen": Json("0.0.0.0:8081")]),
  ]);
  auto error = expectConfigError({ normalizeMicdnConfig(invalid); });
  assert(error.field == "servers[0].adminListen");
}

@("proxy config groups webapps by their target server set")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;
  assert(findProject(reg, store, "openurp.prod", project));

  auto nginx = renderProxy(store, reg, project);
  assert(nginx.canFind("worker_connections 60000;"));
  assert(nginx.canFind("upstream prod-farm{"));
  assert(nginx.canFind("server 10.0.0.11:9080 check inter 5s;"));
  assert(nginx.canFind("server 10.0.0.12:9081;"));
  assert(nginx.canFind("location /bas {"));
  assert(nginx.canFind("proxy_pass http://prod-farm;"));
  assert(nginx.canFind("ssl_certificate /etc/setline/certs/cert.pem;"));
  assert(nginx.canFind("ssl_certificate_key /etc/setline/certs/key.pem;"));
  assert(!nginx.canFind("/etc/nginx/prod.openurp.net"));

  assert(store.updateColumns(reg.find("proxy-settings"), "9002", ["proxy_engine": Json("haproxy")]));
  assert(findProject(reg, store, "openurp.prod", project));
  auto haproxy = renderProxy(store, reg, project);
  assert(haproxy.canFind("# HAProxy main configuration."));
  assert(!haproxy.canFind("setline.json"));
  assert(!haproxy.canFind(`"agent"`));
  assert(haproxy.canFind("frontend main"));
  assert(haproxy.canFind("bind *:80"));
  assert(haproxy.canFind("ssl crt /etc/setline/certs/bundle.pem"));
  assert(haproxy.canFind("map_beg(/var/lib/setline/haproxy/setline.map)"));
  assert(haproxy.canFind("use_backend %[path,map_beg(/var/lib/setline/haproxy/setline.map)]"));
  assert(haproxy.canFind("# setline path routes: backends and map are written by the setline agent " ~
      "to /var/lib/setline/haproxy"));
  assert(haproxy.all!isASCII);
  assert(!haproxy.canFind("setline_path"));
  assert(!haproxy.canFind("setline_route"));
  auto firstLookup = haproxy.indexOf("use_backend");
  assert(firstLookup >= 0);
  assert(haproxy.indexOf("use_backend", firstLookup + 1) < 0);
  assert(!haproxy.canFind("path_beg"));
  assert(!haproxy.canFind("acl "));
  assert(!haproxy.canFind("backend prod-farm"));
  assert(!haproxy.canFind("server 10_0_0_11_9080"));
}

@("proxy model handles url overrides and single/multi-server groups")
unittest {
  auto reg = hubRegistry();
  auto dao = demoDao(reg);
  auto servers = reg.find("servers");
  dao.seed(servers, [
    "id": Json("5003"), "name": Json("app3"), "farm": Json("4001"), "host": Json("2001"),
    "http_port": Json(8082L), "max_heap_size": Json(0L), "proxy_http_port": Json(9082L),
    "proxy_options": Json(""),
  ]);

  auto webapps = reg.find("webapps");
  Row single1 = [
    "id": Json("7002"), "artifact": Json("6001"), "project": Json("1002"), "version": Json("0.0.8"),
    "context_path": Json("/single1"), "urls": Json(Json[].init), "unpack": Json(false), "libs": Json(""),
  ];
  Row single2 = [
    "id": Json("7003"), "artifact": Json("6001"), "project": Json("1002"), "version": Json("0.0.8"),
    "context_path": Json("/single2"), "urls": Json(Json[].init), "unpack": Json(false), "libs": Json(""),
  ];
  Row root = [
    "id": Json("7004"), "artifact": Json("6001"), "project": Json("1002"), "version": Json("0.0.8"),
    "context_path": Json("/"), "urls": Json([Json("/context1"), Json("/context2")]),
    "unpack": Json(false), "libs": Json(""),
  ];
  dao.seed(webapps, single1);
  dao.seed(webapps, single2);
  dao.seed(webapps, root);
  dao.seedMany(webapps, "targets", "7002", ["5001"]);
  dao.seedMany(webapps, "targets", "7003", ["5002"]);
  dao.seedMany(webapps, "targets", "7004", ["5003"]);

  auto store = createHubStore(reg, dao);
  ProjectContext project;
  assert(findProject(reg, store, "openurp.prod", project));

  auto nginx = renderProxy(store, reg, project);
  assert(nginx.canFind("upstream prod-farm2{"));
  assert(nginx.canFind("upstream prod-farm_app1{"));
  assert(nginx.canFind("upstream prod-farm_app2{"));
  assert(nginx.canFind("upstream prod-farm_app3{"));
  assert(nginx.canFind("location /context1 {"));
  assert(nginx.canFind("proxy_pass http://prod-farm_app3;"));

  assert(store.updateColumns(reg.find("proxy-settings"), "9002", ["proxy_engine": Json("haproxy")]));
  assert(findProject(reg, store, "openurp.prod", project));
  auto haproxy = renderProxy(store, reg, project);
  assert(haproxy.canFind("map_beg(/var/lib/setline/haproxy/setline.map)"));
  assert(haproxy.canFind("use_backend %[path,map_beg(/var/lib/setline/haproxy/setline.map)]"));
  assert(!haproxy.canFind("setline_route"));
  assert(!haproxy.canFind("path_beg"));
  assert(!haproxy.canFind("backend prod-farm2"));
}

@("micdn project state renders every configured section")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;
  assert(findProject(reg, store, "openurp.prod", project));

  MicdnState state;
  assert(loadMicdnState(store, reg, project.id, state));
  auto xml = renderMicdnXml(state.config, state.components,
      attributeText(project.data, "name"), attributeText(project.data, "key"));
  assert(xml.canFind(`<maven base="/var/lib/micdn/maven">`));
  assert(xml.canFind(`<static base="/var/cache/micdn/asset">`));
  assert(xml.canFind(`<jar gav="org.beangle.bashub:bas-web:0.0.8"/>`));
  assert(xml.canFind(`<www base="/var/cache/micdn/www">`));
  assert(xml.canFind(`<doc name="manual" npm="@beangle/manual@1.0.0" try-file="index.html"/>`));
  assert(xml.canFind(`<blob base="/var/lib/micdn/blob" max-size="50M">`));
  assert(xml.canFind(`<bucket name="prod" key="fedcba9876543210fedcba9876543210"/>`));
}

@("micdn render omits every optional section when nothing is configured")
unittest {
  auto xml = renderMicdnXml(defaultMicdnConfig(), [], "", "");
  assert(xml.canFind(`<micdn listen="0.0.0.0:8888">`));
  foreach (section; ["maven", "npm", "native", "auth", "static", "www", "blob"])
    assert(!xml.canFind("<" ~ section), section ~ "\n" ~ xml);
}

@("micdn render escapes XML attribute values")
unittest {
  auto config = defaultMicdnConfig();
  config["home"] = Json(`/srv/a&b"<demo>`);
  auto xml = renderMicdnXml(config, [], "", "", false, `https://example.test/a?x=1&y=2`);
  assert(xml.canFind(`home="/srv/a&amp;b&quot;&lt;demo&gt;"`));
  assert(xml.canFind(`remote="https://example.test/a?x=1&amp;y=2"`));
  assert(!xml.canFind(`/srv/a&b"<demo>`));
}

@("micdn component specs reject mismatched providers")
unittest {
  auto mixed = parseJsonString(`{"sources":[
    {"kind":"jar","ref":"org.example:demo:1.0.0"},
    {"kind":"dir","ref":"/srv/static"}]}`);
  auto ex = expectConfigError({ normalizeComponentSpec("static_bundle", mixed); });
  assert(ex.field == "spec.sources");

  auto zipSource = parseJsonString(`{"sources":[{"kind":"zip","ref":"/srv/static.zip"}]}`);
  ex = expectConfigError({ normalizeComponentSpec("static_bundle", zipSource); });
  assert(ex.field == "spec.sources.kind");

  auto npmAutoDeploy = parseJsonString(`{"source":{"kind":"npm","ref":"demo@1.0.0"},"autoDeploy":true}`);
  ex = expectConfigError({ normalizeComponentSpec("www_doc", npmAutoDeploy); });
  assert(ex.field == "spec.autoDeploy");

  auto zipAutoDeploy = parseJsonString(`{"source":{"kind":"zip","ref":"/srv/manual.zip"},"autoDeploy":true}`);
  auto spec = normalizeComponentSpec("www_doc", zipAutoDeploy);
  assert(spec["source"]["kind"].get!string == "zip");
  assert(spec["autoDeploy"].get!bool);
}

@("micdn static bundles and providers use deterministic ordering")
unittest {
  auto config = defaultMicdnConfig();
  config["home"] = Json("/srv/micdn");
  auto zetaSpec = parseJsonString(`{"sources":[
    {"kind":"npm","ref":"z-npm@1","inner":""},
    {"kind":"jar","ref":"z:jar:1","inner":""},
    {"kind":"jar","ref":"a:jar:1","inner":""}]}`);
  auto alphaSpec = parseJsonString(`{"sources":[
    {"kind":"npm","ref":"alpha@1","inner":""}]}`);
  BoundComponent[] components = [
    BoundComponent("", "2", "static_bundle", "zeta", "zeta", 10, zetaSpec),
    BoundComponent("", "1", "static_bundle", "alpha", "Alpha", 20, alphaSpec),
  ];

  auto xml = renderMicdnXml(config, components, "prod", "secret-key");
  assert(xml.indexOf(`<bundle name="Alpha">`) < xml.indexOf(`<bundle name="zeta">`));
  assert(xml.indexOf(`gav="a:jar:1"`) < xml.indexOf(`gav="z:jar:1"`));
  assert(xml.indexOf(`gav="z:jar:1"`) < xml.indexOf(`package="z-npm@1"`));
}

@("micdn masks secrets by keeping both ends")
unittest {
  assert(maskSecret("fedcba9876543210fedcba9876543210") == "fe**10");
  assert(maskSecret("abcd") == "**");
  assert(maskSecret("") == "");
}

@("micdn blob follows the project key")
unittest {
  auto xml = renderMicdnXml(defaultMicdnConfig(), [], "prod", "secret-key");
  assert(xml.canFind(`<blob base="/blob" max-size="100M">`));
  assert(xml.canFind(`<bucket name="prod" key="secret-key"/>`));

  auto masked = renderMicdnXml(defaultMicdnConfig(), [], "prod", "secret-key", true);
  assert(masked.canFind(`<bucket name="prod" key="se**ey"/>`));

  auto withoutKey = renderMicdnXml(defaultMicdnConfig(), [], "prod", "");
  assert(!withoutKey.canFind("<blob"));
}

@("host script orders dependencies before their dependents")
unittest {
  ScriptFeature[string] features;
  features["1"] = ScriptFeature("1", "JDK", []);
  features["2"] = ScriptFeature("2", "Node.js", ["1"]);
  auto scripts = [
    FeatureScript("11", "1", "java -version"),
    FeatureScript("12", "2", "node --version"),
  ];

  auto items = orderScripts(["2"], features, scripts);
  assert(items.length == 2);
  assert(items[0].featureName == "JDK");
  assert(items[1].featureName == "Node.js");

  HostScriptModel model;
  model.platformName = "CentOS";
  model.scripts = items;
  auto text = renderBashScript(model);
  assert(text.canFind("wheel"));
  assert(text.canFind("java -version"));
  assert(text.canFind("node --version"));
  assert(text.indexOf("java -version") < text.indexOf("node --version"));
}

@("host script resolves the host by project and ip")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;
  assert(resolveSetlineProject(reg, store, "openurp.prod", "10.0.0.10", project));

  auto text = renderHostScript(store, reg, project, "10.0.0.11");
  assert(text.canFind("#!/bin/bash"));
  assert(text.canFind("java -version"));
  assert(text.canFind("node --version"));

  auto noFeatures = renderHostScript(store, reg, project, "10.0.0.12");
  assert(noFeatures.canFind("#!/bin/bash"));
  assert(!noFeatures.canFind("java -version"));

  assert(renderHostScript(store, reg, project, "10.0.0.10").length == 0);
  assert(renderHostScript(store, reg, project, "192.168.1.1").length == 0);
}
