/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.profile_test;
/// Profile 配置分发：配置名与来源 IP 的解析、server.xml 的关键结构。

import bashub.demo : demoDao;
import bashub.profile.distribution : loadProfileData;
import bashub.profile.micdnconfig : BoundComponent, MicdnConfigException, MicdnState, defaultMicdnConfig,
  loadMicdnState, maskSecret, normalizeComponentSpec, normalizeMicdnConfig, renderMicdnXml;
import bashub.profile.proxy : renderProxy;
import bashub.profile.resolver : ProfileContext, findProfile, ipHeaderAddresses, matchProfileIp,
  resolveProfile;
import bashub.profile.script : FeatureScript, HostScriptModel, ScriptFeature, loadHostScriptModel, orderScripts,
  renderBashScript, renderHostScript;
import bashub.profile.server : renderServerXml;
import bashub.profile.peers : renderPeers;
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

@("profile accepts the profile ip or one of its host ips")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProfileContext profile;

  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.10", profile));
  assert(profile.id == "1002");
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));
  assert(!resolveProfile(reg, store, "openurp.prod", "192.168.1.1", profile));
  assert(!resolveProfile(reg, store, "openurp.prod", "", profile));
  assert(!resolveProfile(reg, store, "prod", "10.0.0.10", profile));
  assert(!resolveProfile(reg, store, "openurp.missing", "10.0.0.10", profile));
}

@("agent ip header matches profile or host ips and returns the canonical address") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProfileContext profile;
  assert(findProfile(reg, store, "openurp.prod", profile));

  string matched;
  assert(matchProfileIp(reg, store, profile, ipHeaderAddresses("10.0.0.10"), matched));
  assert(matched == "10.0.0.10");
  // 多网卡全部上报：取配置里命中的那个
  assert(matchProfileIp(reg, store, profile, ipHeaderAddresses("127.0.0.1, 10.0.0.11"), matched));
  assert(matched == "10.0.0.11");
  assert(!matchProfileIp(reg, store, profile, ipHeaderAddresses("192.168.1.1"), matched));
  assert(ipHeaderAddresses("localhost").length == 0, "主机名不是身份");
  assert(ipHeaderAddresses("").length == 0);
}

@("agent ip must be declared by the profile or one of its hosts") unittest {
  Registry reg;
  auto store = newStore(reg);
  // profile 没有任何 ip / host 时不做兜底：无法验证的地址一律拒绝
  ProfileContext unknown;
  unknown.id = "999999";
  unknown.data = parseJsonString(`{"id":"999999","attributes":{}}`);
  string matched;
  assert(!matchProfileIp(reg, store, unknown, ["10.0.0.10"], matched));
}

@("server.xml keeps the basctl contract")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProfileContext profile;
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));

  auto data = loadProfileData(store, reg, profile);
  assert(data.engines.length == 1);
  assert(attributeText(data.engines[0], "name") == "tomcat");
  assert(data.artifacts.length == 1);
  assert(attributeText(data.artifacts[0], "artifactId") == "bas-web");
  assert(data.servers.length == 2);

  auto xml = renderServerXml(store, reg, profile);
  assert(xml.canFind(`version="6.0.0"`));
  assert(xml.canFind(`<repository remote="https://repo.openurp.net/maven2"/>`));
  assert(xml.canFind(`<snapshot-repo remote="${bas_remote_url}/maven" token="download-secret"/>`));
  assert(!xml.canFind("<hub"));
  assert(xml.canFind(`setline-hostname="prod.openurp.net"`));

  assert(xml.canFind(`<engine name="tomcat" type="tomcat-server" version="10.1.42"`));
  assert(!xml.canFind("undertow"));
  assert(xml.canFind(`jsp-support="true" websocket-support="true"`));
  assert(xml.canFind(`<listener class-name="org.beangle.bas.listener.StartupListener"/>`));
  assert(xml.canFind(`<jar uri="org.beangle:beangle-webmvc:4.6.0"/>`));

  assert(xml.canFind(`<host name="host01" ip="10.0.0.11" setline-listen-port="8080" setline-admin-port="10080"/>`));
  assert(xml.canFind(`<host name="host02" ip="10.0.0.12" setline-listen-port="8082" setline-admin-port="10081"/>`));
  assert(xml.canFind(`<farm name="prod-farm" engine="tomcat" max-heap-size="2048M">`));
  assert(xml.canFind(`<server name="app1" host="host01" http="8080" proxy-http-port="9080"`));

  assert(xml.canFind(`uri="gav://org.beangle.bashub:bas-web:war:0.0.8"`));
  assert(xml.canFind(`path="/bas" run-at="prod-farm.app1,prod-farm.app2"`));
  assert(xml.canFind(`<url path="/bas"/>`));

  ProfileContext demo;
  assert(resolveProfile(reg, store, "beangle.demo", "127.0.0.1", demo));
  assert(!renderServerXml(store, reg, demo).canFind("setline-"));
}

@("server.xml rejects invalid host setline ports") unittest {
  Registry reg;
  auto store = newStore(reg);
  auto hosts = reg.find("hosts");
  ProfileContext profile;

  foreach (value; ["0", "70000", "not-a-port"]) {
    assert(store.updateColumns(hosts, "2001", ["setline_admin_port": Json(value)]));
    assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));
    assertThrown!Exception(renderServerXml(store, reg, profile));
  }
}

@("server.xml requires the profile hostname only when proxyByHostname is enabled") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProfileContext profile;

  assert(store.updateColumns(reg.find("profiles"), "1002",
      ["hostname": Json(""), "proxy_by_hostname": Json(false)]));
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));
  auto xml = renderServerXml(store, reg, profile);
  assert(!xml.canFind("setline-hostname"));
  assert(xml.canFind(`setline-listen-port="8080"`));

  assert(store.updateColumns(reg.find("profiles"), "1002",
      ["proxy_by_hostname": Json(true)]));
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));
  assertThrown!Exception(renderServerXml(store, reg, profile));
}

@("peers contains web and micdn nodes")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProfileContext profile;

  assert(resolveProfile(reg, store, "beangle.demo", "127.0.0.1", profile));
  auto text = renderPeers(store, reg, profile);
  auto config = parseJsonString(text);
  assert(config["peers"].length == 0);

  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));
  text = renderPeers(store, reg, profile);
  config = parseJsonString(text);
  assert(config["peers"].length == 2);

  assert(store.updateColumns(reg.find("profiles"), "1002", ["proxy_engine": Json("haproxy")]));
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));
  text = renderPeers(store, reg, profile);
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
  assert(store.fetch(reg.find("profile-micdn"), "1002", Query.init, configDoc));
  auto micdnConfig = jsonGet(jsonGet(configDoc["data"], "attributes"), "config");
  micdnConfig["servers"] = Json([
    Json(["name": Json("cdn02"), "adminListen": Json("10.0.0.32:8081")]),
    Json(["name": Json("cdn01"), "adminListen": Json("10.0.0.31:8081")]),
  ]);
  assert(store.updateColumns(reg.find("profile-micdn"), "1002", ["config": micdnConfig]));

  text = renderPeers(store, reg, profile);
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
  ProfileContext profile;

  foreach (value; [0L, 65536L]) {
    assert(store.updateColumns(reg.find("hosts"), "2001", ["setline_listen_port": Json(value)]));
    assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));
    assertThrown!Exception(renderPeers(store, reg, profile));
  }
}

@("peers skip hosts without setline listen ports") unittest {
  Registry reg;
  auto store = newStore(reg);
  ProfileContext profile;
  Json updated;

  assert(store.update(reg.find("webapps"), "7001",
      parseJsonString(`{"data":{"type":"webapps","relationships":{"targets":{"data":[
        {"type":"servers","id":"5001"}]}}}}`), updated));
  assert(store.update(reg.find("hosts"), "2002",
      parseJsonString(`{"data":{"type":"hosts","attributes":{
        "setlineListenPort":null,"setlineAdminPort":null}}}`), updated));
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));

  auto config = parseJsonString(renderPeers(store, reg, profile));
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
  ProfileContext profile;
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));

  auto nginx = renderProxy(store, reg, profile);
  assert(nginx.canFind("worker_connections 60000;"));
  assert(nginx.canFind("upstream prod-farm{"));
  assert(nginx.canFind("server 10.0.0.11:9080 check inter 5s;"));
  assert(nginx.canFind("server 10.0.0.12:9081;"));
  assert(nginx.canFind("location /bas {"));
  assert(nginx.canFind("proxy_pass http://prod-farm;"));
  assert(nginx.canFind("ssl_certificate /etc/setline/certs/cert.pem;"));
  assert(nginx.canFind("ssl_certificate_key /etc/setline/certs/key.pem;"));
  assert(!nginx.canFind("/etc/nginx/prod.openurp.net"));

  assert(store.updateColumns(reg.find("profiles"), "1002", ["proxy_engine": Json("haproxy")]));
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));
  auto haproxy = renderProxy(store, reg, profile);
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
    "id": Json("7002"), "artifact": Json("6001"), "profile": Json("1002"), "version": Json("0.0.8"),
    "context_path": Json("/single1"), "urls": Json(Json[].init), "unpack": Json(false), "libs": Json(""),
  ];
  Row single2 = [
    "id": Json("7003"), "artifact": Json("6001"), "profile": Json("1002"), "version": Json("0.0.8"),
    "context_path": Json("/single2"), "urls": Json(Json[].init), "unpack": Json(false), "libs": Json(""),
  ];
  Row root = [
    "id": Json("7004"), "artifact": Json("6001"), "profile": Json("1002"), "version": Json("0.0.8"),
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
  ProfileContext profile;
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));

  auto nginx = renderProxy(store, reg, profile);
  assert(nginx.canFind("upstream prod-farm2{"));
  assert(nginx.canFind("upstream prod-farm_app1{"));
  assert(nginx.canFind("upstream prod-farm_app2{"));
  assert(nginx.canFind("upstream prod-farm_app3{"));
  assert(nginx.canFind("location /context1 {"));
  assert(nginx.canFind("proxy_pass http://prod-farm_app3;"));

  assert(store.updateColumns(reg.find("profiles"), "1002", ["proxy_engine": Json("haproxy")]));
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));
  auto haproxy = renderProxy(store, reg, profile);
  assert(haproxy.canFind("map_beg(/var/lib/setline/haproxy/setline.map)"));
  assert(haproxy.canFind("use_backend %[path,map_beg(/var/lib/setline/haproxy/setline.map)]"));
  assert(!haproxy.canFind("setline_route"));
  assert(!haproxy.canFind("path_beg"));
  assert(!haproxy.canFind("backend prod-farm2"));
}

@("micdn profile state renders every configured section")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProfileContext profile;
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));

  MicdnState state;
  assert(loadMicdnState(store, reg, profile.id, state));
  auto xml = renderMicdnXml(state.config, state.components,
      attributeText(profile.data, "name"), attributeText(profile.data, "key"));
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

@("micdn blob follows the profile key")
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

@("host script resolves the host by profile and ip")
unittest {
  Registry reg;
  auto store = newStore(reg);
  ProfileContext profile;
  assert(resolveProfile(reg, store, "openurp.prod", "10.0.0.11", profile));

  auto text = renderHostScript(store, reg, profile, "10.0.0.11");
  assert(text.canFind("#!/bin/bash"));
  assert(text.canFind("java -version"));
  assert(text.canFind("node --version"));

  auto noFeatures = renderHostScript(store, reg, profile, "10.0.0.12");
  assert(noFeatures.canFind("#!/bin/bash"));
  assert(!noFeatures.canFind("java -version"));

  assert(renderHostScript(store, reg, profile, "10.0.0.10").length == 0);
  assert(renderHostScript(store, reg, profile, "192.168.1.1").length == 0);
}
