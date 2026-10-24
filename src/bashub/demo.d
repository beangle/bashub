/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.demo;
/// 内存后端的演示数据：与 `db/postgresql/init` 里的四张表对应。
/// 只供测试显式使用；可执行程序不会在数据库不可用时自动退回这里。

import beangle.data.dao.memory : MemoryDao;
import beangle.data.resource : Registry;
import beangle.data.value : Row;

import vibe.data.json : Json;

/// 灌好四张表演示数据的内存后端。
MemoryDao demoDao(Registry reg) {
  auto dao = new MemoryDao(reg);
  foreach (row; orgRows())
    dao.seed(reg.find("organizations"), row);
  foreach (row; platformRows())
    dao.seed(reg.find("platforms"), row);
  foreach (row; projectRows())
    dao.seed(reg.find("projects"), row);
  foreach (row; proxyRows())
    dao.seed(reg.find("proxy-settings"), row);
  foreach (row; hostRows())
    dao.seed(reg.find("hosts"), row);
  foreach (row; engineRows())
    dao.seed(reg.find("engines"), row);
  foreach (row; farmRows())
    dao.seed(reg.find("farms"), row);
  foreach (row; serverRows())
    dao.seed(reg.find("servers"), row);
  foreach (row; artifactRows())
    dao.seed(reg.find("artifacts"), row);
  foreach (row; webappRows())
    dao.seed(reg.find("webapps"), row);
  foreach (row; featureRows())
    dao.seed(reg.find("platform-features"), row);
  foreach (row; scriptRows())
    dao.seed(reg.find("platform-feature-scripts"), row);
  foreach (row; appGroupRows())
    dao.seed(reg.find("app-groups"), row);
  foreach (row; appRows())
    dao.seed(reg.find("apps"), row);
  foreach (row; channelRows())
    dao.seed(reg.find("channels"), row);
  foreach (row; resourceRows())
    dao.seed(reg.find("resources"), row);
  foreach (row; menuRows())
    dao.seed(reg.find("menus"), row);
  foreach (row; componentRows())
    dao.seed(reg.find("cdn-components"), row);
  foreach (row; projectMicdnRows())
    dao.seed(reg.find("project-micdn"), row);
  foreach (row; projectMicdnComponentRows())
    dao.seed(reg.find("project-micdn-components"), row);

  auto engines = reg.find("engines");
  dao.seedValues(engines, "listeners", "3001", ["org.beangle.bas.listener.StartupListener"]);
  dao.seedValues(engines, "jars", "3001", ["org.beangle:beangle-webmvc:4.6.0"]);
  dao.seedValues(engines, "listeners", "3002", []);

  auto farms = reg.find("farms");
  dao.seedMany(farms, "hosts", "4001", ["2001", "2002"]);
  dao.seedMany(farms, "servers", "4001", ["5001", "5002"]);

  auto webapps = reg.find("webapps");
  dao.seedMany(webapps, "targets", "7001", ["5001", "5002"]);

  auto features = reg.find("platform-features");
  dao.seedMany(features, "dependencies", "8002", ["8001"]);

  auto hosts = reg.find("hosts");
  dao.seedMany(hosts, "features", "2001", ["8001", "8002"]);

  auto menus = reg.find("menus");
  dao.seedMany(menus, "resources", "14002", ["13001", "13002"]);

  return dao;
}

private Row[] orgRows() {
  return [
    row("1", ["name": Json("beangle"), "title": Json("Beangle 社区"),
        "short_title": Json("Beangle"), "logo_url": Json("")]),
    row("2", ["name": Json("openurp"), "title": Json("OpenURP 高校教务"),
        "short_title": Json("URP"), "logo_url": Json("")]),
  ];
}

private Row[] platformRows() {
  return [
    row("1", ["name": Json("linux"), "major_version": Json("9"), "fonticon": Json("fa-linux")]),
    row("2", ["name": Json("windows"), "major_version": Json("2022"), "fonticon": Json("fa-windows")]),
  ];
}

private Row[] projectRows() {
  return [
    row("1001", [
      "name": Json("demo"), "title": Json("演示配置"), "bas_version": Json("6.0.0"),
      "hostname": Json("demo.openurp.net"),
      "local_repo": Json("~/.m2/repository"), "remote_repo": Json("https://repo1.maven.org/maven2"),
      "key": Json("0123456789abcdef0123456789abcdef"), "org": Json("1"),
    ]),
    row("1002", [
      "name": Json("prod"), "title": Json("生产配置"), "bas_version": Json("6.0.0"),
      "hostname": Json("prod.openurp.net"),
      "local_repo": Json("/srv/m2"), "remote_repo": Json("https://repo.openurp.net/maven2"),
      "key": Json("fedcba9876543210fedcba9876543210"), "org": Json("2"),
    ]),
  ];
}

private Row[] proxyRows() {
  return [
    row("9001", [
      "project": Json("1001"), "ip": Json("127.0.0.1"),
      "proxy_by_hostname": Json(false),
      "http_port": Json(80L), "https_port": Json(443L),
      "enable_https": Json(true), "force_https": Json(false), "maxconn": Json(30000L),
      "proxy_engine": Json("haproxy"),
      "ssl_ciphers": Json(""), "ssl_protocols": Json(""),
    ]),
    row("9002", [
      "project": Json("1002"), "ip": Json("10.0.0.10"),
      "proxy_by_hostname": Json(true),
      "http_port": Json(80L), "https_port": Json(443L),
      "enable_https": Json(true), "force_https": Json(true), "maxconn": Json(60000L),
      "proxy_engine": Json("nginx"),
      "ssl_ciphers": Json(""), "ssl_protocols": Json(""),
    ]),
  ];
}

private Row[] hostRows() {
  return [
    row("2001", [
      "name": Json("host01"), "ip": Json("10.0.0.11"), "memory": Json(32L), "cores": Json(8L),
      "cpu": Json("Xeon Gold 6248"), "platform_version": Json("9.2"), "arch": Json(2L),
      "setline_listen_port": Json(8080L), "setline_admin_port": Json(10080L),
      "project": Json("1002"), "platform": Json("1"),
    ]),
    row("2002", [
      "name": Json("host02"), "ip": Json("10.0.0.12"), "memory": Json(16L), "cores": Json(4L),
      "cpu": Json("Xeon E5-2680"), "platform_version": Json("2022"), "arch": Json(2L),
      "setline_listen_port": Json(8082L), "setline_admin_port": Json(10081L),
      "project": Json("1002"), "platform": Json("2"),
    ]),
  ];
}

private Row[] engineRows() {
  return [
    row("3001", [
      "name": Json("tomcat"), "typ": Json("tomcat-server"), "version": Json("10.1.42"),
      "remark": Json("全量发行包"), "jsp_support": Json(true), "websocket_support": Json(true),
      "project": Json("1002"),
    ]),
    row("3002", [
      "name": Json("undertow"), "typ": Json("undertow"), "version": Json("2.3.18"),
      "remark": Json("嵌入式单应用"), "jsp_support": Json(false), "websocket_support": Json(true),
      "project": Json("1002"),
    ]),
  ];
}

private Row[] farmRows() {
  return [
    row("4001", [
      "name": Json("prod-farm"), "engine": Json("3001"), "project": Json("1002"),
      "max_heap_size": Json(2048L), "server_options": Json("-Xss512k"),
      "proxy_options": Json("balance roundrobin"),
    ]),
  ];
}

private Row[] serverRows() {
  return [
    row("5001", [
      "name": Json("app1"), "farm": Json("4001"), "host": Json("2001"),
      "http_port": Json(8080L), "max_heap_size": Json(0L), "proxy_http_port": Json(9080L),
      "proxy_options": Json("check inter 5s"),
    ]),
    row("5002", [
      "name": Json("app2"), "farm": Json("4001"), "host": Json("2002"),
      "http_port": Json(8081L), "max_heap_size": Json(1024L), "proxy_http_port": Json(9081L),
      "proxy_options": Json(""),
    ]),
  ];
}

private Row[] artifactRows() {
  return [
    row("6001", [
      "artifact_id": Json("bas-web"), "group_id": Json("org.beangle.bashub"),
      "packaging": Json("war"), "classifier": Json(""), "latest_version": Json("0.0.8"),
      "title": Json("BAS 控制台"), "description": Json("配置管理控制台"),
      "context_path": Json("/bas"), "arch": Json(1L), "resolve_support": Json(true),
      "jsp_support": Json(false), "websocket_support": Json(true), "project": Json("1002"),
    ]),
    row("6002", [
      "artifact_id": Json("basctl"), "group_id": Json("org.beangle.basctl"),
      "packaging": Json("jar"), "classifier": Json(""), "latest_version": Json("0.0.8"),
      "title": Json("BAS 命令行"), "description": Json("节点代理与部署工具"),
      "context_path": Json(""), "arch": Json(2L), "resolve_support": Json(false),
      "jsp_support": Json(false), "websocket_support": Json(false), "project": Json(""),
    ]),
  ];
}

private Row[] webappRows() {
  return [
    row("7001", [
      "artifact": Json("6001"), "project": Json("1002"), "version": Json("0.0.8"),
      "context_path": Json("/bas"), "urls": Json([Json("/bas")]), "unpack": Json(false),
      "libs": Json(""),
    ]),
  ];
}

private Row[] featureRows() {
  return [
    row("8001", [
      "name": Json("JDK"), "version": Json("17"), "logo": Json("/images/jdk.svg"),
      "description": Json("Java 运行环境"),
    ]),
    row("8002", [
      "name": Json("Node.js"), "version": Json("20"), "logo": Json("/images/node.svg"),
      "description": Json("前端构建运行时"),
    ]),
  ];
}

private Row[] scriptRows() {
  return [
    row("9001", [
      "feature": Json("8001"), "platform": Json("1"), "scripts": Json("java -version"),
    ]),
    row("9002", [
      "feature": Json("8002"), "platform": Json("1"), "scripts": Json("node --version"),
    ]),
  ];
}

private Row[] appGroupRows() {
  return [
    row("10001", ["name": Json("org.beangle.bashub"), "title": Json("基础平台")]),
    row("10002", ["name": Json("org.beangle.ems"), "title": Json("教学管理")]),
  ];
}

private Row[] appRows() {
  return [
    row("11001", [
      "name": Json("bas"), "title": Json("基础平台"), "artifact_id": Json("bas-web"),
      "group": Json("10001"), "services": Json("PostgreSQL"),
    ]),
    row("11002", [
      "name": Json("ems"), "title": Json("教务系统"), "artifact_id": Json("ems-web"),
      "group": Json("10002"), "services": Json("PostgreSQL"),
    ]),
  ];
}

private Row[] channelRows() {
  return [
    row("12001", [
      "app": Json("11001"), "base": Json("/bas"), "channel_type": Json("pc"),
      "embed_mode": Json("iframe"), "enabled": Json(true),
    ]),
    row("12002", [
      "app": Json("11002"), "base": Json("/ems"), "channel_type": Json("pc"),
      "embed_mode": Json("wujie"), "enabled": Json(true),
    ]),
  ];
}

private Row[] resourceRows() {
  return [
    row("13001", [
      "app": Json("11001"), "name": Json("/setting/config.action"), "title": Json("配置管理"),
      "scope": Json(1L), "actions": Json(""), "enabled": Json(true), "remark": Json(""),
    ]),
    row("13002", [
      "app": Json("11001"), "name": Json("/setting/menu.action"), "title": Json("菜单管理"),
      "scope": Json(2L), "actions": Json(""), "enabled": Json(true), "remark": Json(""),
    ]),
  ];
}

private Row[] menuRows() {
  return [
    row("14001", [
      "app": Json("11001"), "name": Json("设置"), "en_name": Json("setting"), "indexno": Json("1"),
      "fonticon": Json("fa-cog"), "params": Json(""), "enabled": Json(true), "remark": Json(""),
      "parent": Json(null), "entry": Json(null),
    ]),
    row("14002", [
      "app": Json("11001"), "name": Json("配置管理"), "en_name": Json("config"), "indexno": Json("1.1"),
      "fonticon": Json("fa-sliders"), "params": Json(""), "enabled": Json(true), "remark": Json(""),
      "parent": Json("14001"), "entry": Json("13001"),
    ]),
  ];
}

private Row[] componentRows() {
  auto bundleSpec = Json.emptyObject;
  Json[] sources;
  auto jar = Json.emptyObject;
  jar["kind"] = Json("jar");
  jar["ref"] = Json("org.beangle.bashub:bas-web:0.0.8");
  jar["inner"] = Json("");
  sources ~= jar;
  bundleSpec["sources"] = Json(sources);

  auto wwwSpec = Json.emptyObject;
  auto npm = Json.emptyObject;
  npm["kind"] = Json("npm");
  npm["ref"] = Json("@beangle/manual@1.0.0");
  npm["inner"] = Json("dist");
  wwwSpec["source"] = npm;
  wwwSpec["tryFile"] = Json("index.html");
  wwwSpec["autoDeploy"] = Json(false);
  wwwSpec["autoGzip"] = Json(true);

  return [
    row("17001", ["kind": Json("static_bundle"), "name": Json("bas-static"), "mount_name": Json("bas"),
      "remark": Json("基础平台前端资源"), "spec": bundleSpec]),
    row("17002", ["kind": Json("www_doc"), "name": Json("manual"), "mount_name": Json("manual"),
      "remark": Json("使用手册"), "spec": wwwSpec]),
  ];
}

private Row[] projectMicdnRows() {
  auto config = Json.emptyObject;
  config["home"] = Json("/var/lib/micdn");
  config["listen"] = Json("0.0.0.0:8888");
  config["logFile"] = Json("console");
  config["logLevel"] = Json("info");

  auto maven = Json.emptyObject;
  maven["declared"] = Json(true);
  maven["base"] = Json("/var/lib/micdn/maven");
  maven["remotes"] = Json([Json("https://repo1.maven.org/maven2")]);
  maven["snapshotRemote"] = Json("");
  config["maven"] = maven;

  auto npm = Json.emptyObject;
  npm["declared"] = Json(true);
  npm["base"] = Json("/var/lib/micdn/npm");
  npm["remotes"] = Json([Json("https://registry.npmmirror.com")]);
  npm["devRemote"] = Json("");
  config["npm"] = npm;

  auto nativeCfg = Json.emptyObject;
  nativeCfg["declared"] = Json(false);
  nativeCfg["base"] = Json("");
  config["native"] = nativeCfg;

  auto auth = Json.emptyObject;
  auth["publishKey"] = Json("publish-secret");
  auth["downloadKey"] = Json("download-secret");
  auth["maxSize"] = Json("64M");
  config["auth"] = auth;

  config["static"] = Json(["base": Json("/var/cache/micdn/asset")]);
  config["www"] = Json(["base": Json("/var/cache/micdn/www")]);
  config["blob"] = Json([
    "base": Json("/var/lib/micdn/blob"), "maxSize": Json("50M"),
    "publicImages": Json(true),
  ]);
  auto item = row("1002", ["config": config]);
  item["project_id"] = Json("1002");
  return [item];
}

private Row[] projectMicdnComponentRows() {
  return [
    row("18001", ["project": Json("1002"), "component": Json("17001"), "sortno": Json(10L)]),
    row("18002", ["project": Json("1002"), "component": Json("17002"), "sortno": Json(20L)]),
  ];
}

/// 行里的外键用**关系名**当键（对应 SQL 的 `t.org_id as org`）。
private Row row(string id, Json[string] cols) {
  Row r;
  r["id"] = Json(id);
  foreach (k, v; cols)
    r[k] = v;
  return r;
}
