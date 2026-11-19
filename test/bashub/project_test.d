/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.project_test;
/// Project 配置分发：配置名与来源 IP 的解析、server.xml 的关键结构。

import test.bashub.fixture : testDao;
import bashub.project.distribution : loadProjectData;
import bashub.project.micdnconfig : BoundComponent, MicdnConfigException, MicdnState, defaultMicdnConfig,
  loadMicdnState, maskSecret, normalizeComponentSpec,
  normalizeMicdnConfig, micdnServerBases, renderMicdnXml;
import bashub.project.proxy : ProxyBackend, ProxyModel, ProxyServer, ProxyWebapp, renderHaproxy, renderHaproxyMap, renderHaproxyMapForEndpoint, renderNginx, renderProxy, renderProxyForEndpoint;
import bashub.project.resolver : ProjectContext, findProject, ipHeaderAddresses, matchHostIp,
  resolveHostProject, resolveSetlineProject;
import bashub.project.script : FeatureScript, HostScriptModel, ScriptFeature, loadHostScriptModel, orderScripts,
  renderBashScript, renderHostScript;
import bashub.project.server : renderServerXml;
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
  return createHubStore(reg, testDao(reg));
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
  assert(renderServerXml(store, reg, project, false).canFind(`token="download-secret"`));
  assert(xml.canFind(`<repository remote="http://10.0.0.31:8888/maven" token="download-secret"/>`));
  assert(xml.canFind(`<snapshot-repo remote="http://10.0.0.31:8888/maven" token="download-secret"/>`));
  assert(xml.canFind(`<native-repo remote="http://10.0.0.31:8888/native" token="download-secret"/>`));
  assert(xml.canFind(`<proxy name="edge-web" ip="10.0.0.20" domain="www.openurp.net"/>`));
  assert(xml.canFind(`<proxy name="edge-ip" ip="10.0.0.30,10.0.0.10"/>`));
  assert(xml.canFind(`endpoints="edge-web,edge-ip"`));
  assert(!xml.canFind("<hub"));

  assert(xml.canFind(`<engine name="tomcat" type="tomcat-server" version="10.1.42"`));
  assert(!xml.canFind("undertow"));
  assert(xml.canFind(`jsp-support="true" websocket-support="true"`));
  assert(xml.canFind(`<listener class-name="org.beangle.bas.listener.StartupListener"/>`));
  assert(xml.canFind(`<jar uri="org.beangle:beangle-webmvc:4.6.0"/>`));

  assert(xml.canFind(`<host name="host01" ip="10.0.0.11" agent-group="default_group"/>`));
  assert(xml.canFind(`<host name="host02" ip="10.0.0.12" agent-group="default_group"/>`));
  assert(xml.canFind(`<farm name="prod-farm" engine="tomcat" max-heap-size="2048M">`));
  assert(xml.canFind(`<server name="app1" host="host01" http="8080" proxy-http-port="9080"`));
  assert(xml.canFind(`<auto-start>`));
  assert(xml.canFind(`<wait-for ref="prod-farm.app2"/>`));
  assert(xml.canFind(`<wait-for url="https://db.example/health" timeout="30"/>`));

  assert(xml.canFind(`uri="gav://org.beangle.bashub:bas-web:war:0.0.8"`));
  assert(xml.canFind(`path="/bas" run-at="prod-farm.app1,prod-farm.app2"`));
  assert(xml.canFind(`<url path="/bas"/>`));

  ProjectContext demo;
  assert(findProject(reg, store, "beangle.demo", demo));
  auto demoXml = renderServerXml(store, reg, demo);
  assert(!demoXml.canFind("setline-"));
  // demo 没有 micdn server host：server.xml 不生成 repo 元素。
  assert(!demoXml.canFind("<repository"));
  assert(!demoXml.canFind("<snapshot-repo"));
  assert(!demoXml.canFind("<native-repo"));
}

@("server.xml omits repos when the project has no micdn host") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext demo;
  assert(findProject(reg, store, "beangle.demo", demo));
  // 没有 micdn server host：三个 repo 元素都不生成，也不使用 hub token 兜底。
  auto xml = renderServerXml(store, reg, demo, false);
  assert(!xml.canFind("<repository"));
  assert(!xml.canFind("<snapshot-repo"));
  assert(!xml.canFind("<native-repo"));
}

@("micdn server registrations normalize host and stay out of micdn.xml")
unittest {
  auto raw = defaultMicdnConfig();
  raw["servers"] = Json([
    Json(["name": Json("cdn02"), "host": Json("2001:db8::2")]),
    Json(["name": Json("cdn01"), "host": Json(" 10.0.0.31 ")]),
  ]);
  auto config = normalizeMicdnConfig(raw);
  assert(config["servers"].length == 2);
  assert(config["servers"][0]["host"].get!string == "10.0.0.31");
  assert(config["servers"][1]["host"].get!string == "2001:db8::2");
  auto xml = renderMicdnXml(config, [], "prod", "fedcba9876543210fedcba9876543210");
  assert(!xml.canFind("host"));
  assert(!xml.canFind("cdn01"));

  auto invalid = defaultMicdnConfig();
  invalid["servers"] = Json([
    Json(["name": Json("cdn01"), "host": Json("0.0.0.0")]),
  ]);
  auto error = expectConfigError({ normalizeMicdnConfig(invalid); });
  assert(error.field == "servers[0].host");

  invalid["servers"] = Json([
    Json(["name": Json("cdn01"), "host": Json("127.0.0.1:8888")]),
  ]);
  error = expectConfigError({ normalizeMicdnConfig(invalid); });
  assert(error.field == "servers[0].host");
}

@("proxy config groups webapps by their target server set")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;
  assert(findProject(reg, store, "openurp.prod", project));

  auto nginx = renderProxyForEndpoint(store, reg, project, "edge-web");
  assert(nginx.canFind("worker_connections 60000;"));
  assert(nginx.canFind("upstream prod-farm{"));
  assert(nginx.canFind("server 10.0.0.11:9080 check inter 5s;"));
  assert(nginx.canFind("server 10.0.0.12:9081;"));
  assert(nginx.canFind("location /bas {"));
  assert(nginx.canFind("proxy_pass http://prod-farm;"));
  assert(nginx.canFind("ssl_certificate /etc/nginx/certs/edge-web.pem;"));
  assert(nginx.canFind("ssl_certificate_key /etc/nginx/certs/edge-web.key.pem;"));
  assert(nginx.canFind("server_name  www.openurp.net;"));
  assertThrown!Exception(renderProxyForEndpoint(store, reg, project, "missing"));

  auto haproxy = renderProxyForEndpoint(store, reg, project, "edge-ip");
  assert(haproxy.canFind("# HAProxy main configuration"));
  assert(!haproxy.canFind("setline.json"));
  assert(!haproxy.canFind(`"agent"`));
  assert(haproxy.canFind("frontend main"));
  assert(haproxy.canFind("bind *:80"));
  assert(!haproxy.canFind("ssl crt /etc/setline/certs/edge-ip.bundle.pem"));
  assert(haproxy.canFind("backend prod-farm"));
  assert(haproxy.canFind("server app1 10.0.0.11:9080 check inter 5s"));
  auto hmap = renderHaproxyMapForEndpoint(store, reg, project, "edge-ip");
  assert(hmap.canFind("/bas  prod-farm"));
  assert(haproxy.all!isASCII);
  assert(!haproxy.canFind("setline.map"));
  assert(!haproxy.canFind("setline_route"));
  assert(!haproxy.canFind("stats"));
  assert(!haproxy.canFind("PROFILE=SYSTEM"));
  assert(!nginx.canFind("/status"));
  assert(haproxy.indexOf("use_backend") >= 0);
}

@("proxy model handles url overrides and single/multi-server groups")
unittest {
  auto reg = hubRegistry();
  auto dao = testDao(reg);
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
  dao.seedMany(webapps, "endpoints", "7002", ["9001"]);
  dao.seedMany(webapps, "endpoints", "7003", ["9001"]);
  dao.seedMany(webapps, "endpoints", "7004", ["9001"]);

  auto store = createHubStore(reg, dao);
  ProjectContext project;
  assert(findProject(reg, store, "openurp.prod", project));

  auto nginx = renderProxyForEndpoint(store, reg, project, "edge-web");
  assert(nginx.canFind("upstream prod-farm2{"));
  assert(nginx.canFind("upstream prod-farm_app1{"));
  assert(nginx.canFind("upstream prod-farm_app2{"));
  assert(nginx.canFind("upstream prod-farm_app3{"));
  assert(nginx.canFind("location /context1 {"));
  assert(nginx.canFind("proxy_pass http://prod-farm_app3;"));

  assert(findProject(reg, store, "openurp.prod", project));
  auto haproxy = renderProxyForEndpoint(store, reg, project, "edge-ip");
  assert(haproxy.canFind("backend prod-farm"));
  auto hmap = renderHaproxyMapForEndpoint(store, reg, project, "edge-ip");
  assert(hmap.canFind("/bas  prod-farm"));
  assert(!haproxy.canFind("setline.map"));
  assert(!haproxy.canFind("setline_route"));
  assert(!haproxy.canFind("stats"));
  assert(!haproxy.canFind("PROFILE=SYSTEM"));
  assert(!nginx.canFind("/status"));
}

@("micdn project state renders every configured section")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProjectContext project;
  assert(findProject(reg, store, "openurp.prod", project));

  MicdnState state;
  assert(loadMicdnState(store, reg, project.id, state));
  // maven/npm/native 的 base 不可配置，即使旧配置塞了值也必须落回 home 下的默认目录。
  state.config["maven"]["base"] = Json("/tmp/not-micdn");
  auto xml = renderMicdnXml(state.config, state.components,
      attributeText(project.data, "name"), attributeText(project.data, "key"));
  assert(xml.canFind(`<maven base="/var/lib/micdn/maven">`));
  assert(!xml.canFind("/tmp/not-micdn"));
  assert(xml.canFind(`<static base="/var/lib/micdn/asset">`));
  assert(xml.canFind(`<jar gav="org.beangle.bashub:bas-web:0.0.8"/>`));
  assert(xml.canFind(`<www base="/var/lib/micdn/www">`));
  assert(xml.canFind(`<doc name="manual" npm="@beangle/manual@1.0.0" try-file="index.html"/>`));
  assert(xml.canFind(`<blob base="/var/lib/micdn/blob" max-size="50M">`));
  assert(xml.canFind(`<bucket name="prod" key="fedcba9876543210fedcba9876543210"/>`));
}

@("micdn render omits every optional section when nothing is configured")
unittest {
  auto xml = renderMicdnXml(defaultMicdnConfig(), [], "", "");
  assert(xml.canFind(`<micdn listen="0.0.0.0:8888">`));
  assert(xml.canFind(`<prune at="03:30" npm-dev-keep="1" maven-snapshot-keep="1"/>`));
  foreach (section; ["maven", "npm", "native", "auth", "static", "www", "blob"])
    assert(!xml.canFind("<" ~ section), section ~ "\n" ~ xml);
}

@("micdn render escapes XML attribute values")
unittest {
  auto config = defaultMicdnConfig();
  config["home"] = Json(`/srv/a&b"<demo>`);
  auto xml = renderMicdnXml(config, [], "", "", false, `https://example.test/a?x=1&y=2`);
  assert(xml.canFind(`home="/srv/a&amp;b&quot;&lt;demo&gt;"`));
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
    BoundComponent("", "2", "static_bundle", "zeta", "zeta", zetaSpec),
    BoundComponent("", "1", "static_bundle", "alpha", "Alpha", alphaSpec),
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

@("proxy routes are emitted longest prefix first") unittest {
  auto proxy = Json(["attributes": Json([
    "maxconn": Json(30000), "httpPort": Json(80), "httpsPort": Json(443),
    "enableHttps": Json(false), "forceHttps": Json(false),
    "sslCiphers": Json(""), "sslProtocols": Json(""),
  ])]);
  auto model = ProxyModel(Json.emptyObject, proxy, "", "default", "haproxy");
  auto broad = ProxyWebapp("broad", "/api/edu", ["/api/edu"], "", "", []);
  auto narrow = ProxyWebapp("narrow", "/api/edu/exam", ["/api/edu/exam"], "", "", []);
  model.webapps = [broad, narrow];
  model.backendByWebapp["broad"] = "edu";
  model.backendByWebapp["narrow"] = "exam";
  auto map = renderHaproxyMap(model);
  auto exam = map.indexOf("/api/edu/exam  exam");
  auto edu = map.indexOf("/api/edu  edu");
  assert(exam >= 0 && edu >= 0);
  assert(exam < edu, map);
}

@("haproxy bind keeps spaces before ciphers and protocols") unittest {
  auto proxy = Json(["attributes": Json([
    "maxconn": Json(30000), "httpPort": Json(80), "httpsPort": Json(443),
    "enableHttps": Json(true), "forceHttps": Json(false),
    "sslCiphers": Json("ECDHE+AESGCM"), "sslProtocols": Json("no-tlsv10 no-tlsv11 alpn h2,http/1.1"),
  ])]);
  auto model = ProxyModel(Json.emptyObject, proxy, "", "default", "haproxy");
  model.certificateDir = "/etc/haproxy/certs";
  auto server = ProxyServer("s1", "app1", "f1", "farm", "10.0.0.11", "", 9080);
  auto backend = ProxyBackend("farm", "", [server], ["w1"]);
  model.backends = [backend];
  model.webapps = [ProxyWebapp("w1", "/", ["/"], "f1", "farm", [server])];
  model.backendByWebapp["w1"] = "farm";
  auto text = renderHaproxy(model);
  assert(text.canFind("bind *:443 ssl crt /etc/haproxy/certs/bundle.pem ciphers ECDHE+AESGCM no-tlsv10 no-tlsv11 alpn h2,http/1.1"));
  assert(text.canFind("server app1 10.0.0.11:9080 check"));
}

@("generated haproxy config passes the local haproxy parser") unittest {
  import std.file : remove, write;
  import std.process : execute;
  import std.uuid : randomUUID;

  auto probe = execute(["/bin/sh", "-c", "command -v haproxy >/dev/null 2>&1"]);
  if (probe.status != 0)
    return;

  auto proxy = Json(["attributes": Json([
    "maxconn": Json(30000), "httpPort": Json(80), "httpsPort": Json(443),
    "enableHttps": Json(false), "forceHttps": Json(false),
    "sslCiphers": Json(""), "sslProtocols": Json(""),
  ])]);
  auto model = ProxyModel(Json.emptyObject, proxy, "", "default", "haproxy");
  auto server = ProxyServer("s1", "app1", "f1", "farm", "127.0.0.1", "check inter 5s", 19080);
  model.backends = [ProxyBackend("farm", "balance roundrobin", [server], ["w1"])];
  model.webapps = [ProxyWebapp("w1", "/", ["/"], "f1", "farm", [server])];
  model.backendByWebapp["w1"] = "farm";
  auto mapPath = "/tmp/bashub-haproxy-check-" ~ randomUUID().toString ~ ".map";
  model.routeMap = mapPath;

  auto path = "/tmp/bashub-haproxy-check-" ~ randomUUID().toString ~ ".cfg";
  scope (exit) {
    remove(path);
    remove(mapPath);
  }
  write(mapPath, renderHaproxyMap(model));
  write(path, renderHaproxy(model));
  auto result = execute(["haproxy", "-c", "-f", path]);
  assert(result.status == 0, result.output ~ "\n---\n" ~ renderHaproxy(model));
}


@("configured alternate webapp path is emitted as a route") unittest {
  auto proxy = Json(["attributes": Json([
    "maxconn": Json(30000), "httpPort": Json(80), "httpsPort": Json(443),
    "enableHttps": Json(false), "forceHttps": Json(false),
    "sslCiphers": Json(""), "sslProtocols": Json(""),
  ])]);
  auto model = ProxyModel(Json.emptyObject, proxy, "", "default", "haproxy");
  auto server = ProxyServer("s1", "app1", "f1", "farm", "10.0.0.11", "", 9080);
  model.backends = [ProxyBackend("farm", "", [server], ["w1"])];
  model.webapps = [ProxyWebapp("w1", "/edu", ["/m/edu/learning"], "f1", "farm", [server])];
  model.backendByWebapp["w1"] = "farm";
  assert(renderHaproxyMap(model).canFind("/m/edu/learning  farm"));
  assert(renderNginx(model).canFind("location /m/edu/learning {"));
}

@("micdn server emits fixed static and blob routes") unittest {
  auto reg = hubRegistry();
  auto store = createHubStore(reg, testDao(reg));
  auto config = defaultMicdnConfig();
  config["listen"] = Json("0.0.0.0:8888");
  config["servers"] = Json([
    Json(["name": Json("cdn01"), "host": Json("10.0.0.31")]),
  ]);
  assert(store.updateColumns(reg.find("project-micdn"), "1002", ["config": config]));
  ProjectContext project;
  assert(findProject(reg, store, "openurp.prod", project));
  auto text = renderProxyForEndpoint(store, reg, project, "edge-ip");
  auto map = renderHaproxyMapForEndpoint(store, reg, project, "edge-ip");
  assert(map.canFind("/blob  micdn"));
  assert(map.canFind("/static  micdn"));
  assert(text.canFind("backend micdn"));
  assert(text.canFind("server s1 10.0.0.31:8888 check"));
  assert(!map.canFind("/std/spa  micdn"));
}


@("micdn render writes global upstream tokens and masks them in preview")
unittest {
  auto config = defaultMicdnConfig();
  config["maven"]["declared"] = Json(true);
  config["maven"]["snapshotRemote"] = Json("https://hub.example/maven");
  config["npm"]["declared"] = Json(true);
  config["npm"]["devRemote"] = Json("http://central/npm");

  auto xml = renderMicdnXml(config, [], "", "", false, "", "dev-token", "snap-token");
  assert(xml.canFind(`<snapshot remote="https://hub.example/maven" token="snap-token"/>`));
  assert(xml.canFind(`<dev remote="http://central/npm" token="dev-token"/>`));

  auto masked = renderMicdnXml(config, [], "", "", true, "", "dev-token", "snap-token");
  assert(masked.canFind(`token="********"`));
  assert(!masked.canFind("dev-token"));
  assert(!masked.canFind("snap-token"));
}


@("micdn render defaults formal remotes and uses stored snapshot") unittest {
  auto config = defaultMicdnConfig();
  config["maven"]["declared"] = Json(true);
  config["maven"]["snapshotRemote"] = Json("https://hub.example/maven");
  config["npm"]["declared"] = Json(true);
  config["native"]["declared"] = Json(true);
  auto xml = renderMicdnXml(config, [], "prod", "key", false, "",
      "", "snap-token", "https://hub.example/native");
  assert(xml.canFind(`<remote url="https://repo1.maven.org/maven2"/>`));
  assert(xml.canFind(`<remote url="https://maven.aliyun.com/nexus/content/groups/public"/>`));
  assert(xml.canFind(`<snapshot remote="https://hub.example/maven" token="snap-token"/>`));
  assert(xml.canFind(`<remote url="https://registry.npmmirror.com"/>`));
  assert(xml.canFind(`<remote url="https://registry.npmjs.org"/>`));
  assert(xml.canFind(`<native base="/native">`));
  assert(xml.canFind(`<remote url="https://hub.example/native" token="snap-token"/>`));
}


@("micdn server bases use host and listen port once each") unittest {
  auto config = defaultMicdnConfig();
  config["listen"] = Json("0.0.0.0:8888");
  config["servers"] = Json([
    Json(["host": Json("10.0.0.31")]),
    Json(["host": Json("10.0.0.31")]),
    Json(["host": Json("10.0.0.32")]),
    Json(["host": Json("0.0.0.0")]),
  ]);
  auto bases = micdnServerBases(config);
  assert(bases == ["http://10.0.0.31:8888", "http://10.0.0.32:8888"]);
  config["servers"] = Json.emptyArray;
  assert(micdnServerBases(config).length == 0);
}


@("micdn normalize drops legacy maven/npm/native/www/static base fields") unittest {
  auto raw = defaultMicdnConfig();
  raw["maven"]["base"] = Json("/legacy/maven");
  raw["npm"]["base"] = Json("/legacy/npm");
  raw["native"]["base"] = Json("/legacy/native");
  raw["www"]["base"] = Json("/legacy/www");
  raw["static"]["base"] = Json("/legacy/static");
  auto config = normalizeMicdnConfig(raw);
  assert(jsonGet(jsonGet(config, "maven"), "base").type == Json.Type.undefined);
  assert(jsonGet(jsonGet(config, "npm"), "base").type == Json.Type.undefined);
  assert(jsonGet(jsonGet(config, "native"), "base").type == Json.Type.undefined);
  assert(jsonGet(jsonGet(config, "www"), "base").type == Json.Type.undefined);
  assert(jsonGet(jsonGet(config, "static"), "base").type == Json.Type.undefined);
}
