/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.config_test;
/// bashub.xml 解析：一份配置读错，起的就是另一套服务。

import bashub.config;

import beangle.ems : loadEms;

import test.beangle.tempdir : uniqueTempDir;

import std.file : mkdirRecurse, rmdirRecurse, write;
import std.path : buildPath;
import std.string : endsWith;
import std.exception : assertThrown;

@("parse bashub.xml")
unittest {
  auto content = `<?xml version="1.0" encoding="UTF-8"?>
<bashub listen="0.0.0.0:9000" log-level="debug" log-file="/tmp/bashub.log">
  <db url="host=db port=5432 user=bashub dbname=bas"/>
  <api prefix="/api/hub" auth="required"/>
  <ems base="https://sas.openurp.net" app-name="bas-hub" session-id-name="EMS_SID"/>
  <artifacts refresh-minutes="120"/>
</bashub>`;
  auto cfg = parseBashub(content);
  assert(cfg.listen == "0.0.0.0:9000");
  assert(cfg.logLevel == "debug");
  assert(cfg.logFile == "/tmp/bashub.log");
  assert(cfg.dbUrl == "host=db port=5432 user=bashub dbname=bas");
  assert(cfg.apiPrefix == "/api/hub");
  assert(cfg.authRequired);
  assert(cfg.emsBase == "https://sas.openurp.net");
  assert(cfg.appName == "bas-hub");
  assert(cfg.sessionIdName == "EMS_SID");
  assert(cfg.artifactRefreshMinutes == 120);
  assert(cfg.repoHome == "~/.m2");
  assert(cfg.snapshotUsertoken.length == 0);
  assert(!cfg.hasCas); // 没配 cas 就仍走演示用户
  assert(cfg.hasDb);
}

@("artifact refresh interval must be a non-negative integer")
unittest {
  assert(parseBashub(`<bashub><artifacts refresh-minutes="0"/></bashub>`).artifactRefreshMinutes == 0);
  assertThrown!Exception(parseBashub(`<bashub><artifacts refresh-minutes="-1"/></bashub>`));
  assertThrown!Exception(parseBashub(`<bashub><artifacts refresh-minutes="soon"/></bashub>`));
}

@("安全配置：授权域、刷新间隔与 CORS 来源")
unittest {
  auto cfg = parseBashub(`<bashub>
    <api prefix="/api/hub" auth="required"
         authority-url="http://ems-inner/api/platform/security/func/bas-hub/resources.json"
         authority-refresh-minutes="7"
         cors-origins="https://hub.example.com, sas.openurp.net"/>
  </bashub>`);
  assert(cfg.authRequired);
  assert(cfg.authorityUrl.endsWith("/resources.json"));
  assert(cfg.authorityRefreshSeconds == 420);
  assert(cfg.corsOrigins == ["https://hub.example.com", "sas.openurp.net"]);

  assert(parseBashub(`<bashub><api authority-refresh-minutes="0"/></bashub>`).authorityRefreshSeconds == 0);
  assertThrown!Exception(parseBashub(`<bashub><api authority-refresh-minutes="-1"/></bashub>`));
  assertThrown!Exception(parseBashub(`<bashub><api authority-refresh-minutes="soon"/></bashub>`));
}

@("配了 ems 内网地址时自动推出 resources.json")
unittest {
  auto ems = loadEms("/tmp/ems-bas", [
    "base": "https://sas.openurp.net",
    "inner_base": "http://10.0.0.8",
  ]);
  auto cfg = parseBashub(`<bashub><ems app-name="bas-hub"/></bashub>`, ems);
  assert(cfg.emsInnerApi == "http://10.0.0.8/api");
  assert(cfg.authorityUrl == "http://10.0.0.8/api/platform/security/func/bas-hub/resources.json");
  assert(cfg.corsOrigins == ["localhost", "127.0.0.1"]);
}

@("defaults when the optional elements are absent")
unittest {
  auto cfg = parseBashub(`<bashub/>`);
  assert(cfg.listen == "127.0.0.1:8080");
  assert(!cfg.hasDb);
  assert(!cfg.authRequired);
  assert(cfg.apiPrefix == "/api/hub");
  assert(cfg.repoHome == "~/.m2");
  assert(cfg.artifactRefreshMinutes == 360);
}

@("root element must be bashub")
unittest {
  assertThrown!Exception(parseBashub(`<micdn listen="0:1"/>`));
}

@("parse listen address")
unittest {
  auto a = parseListen("127.0.0.1:8080");
  assert(a.host == "127.0.0.1" && a.port == 8080);
  assert(parseListen(":9000").host == "127.0.0.1");
  assert(parseListen("9000").port == 9000);
  assert(a.toString == "127.0.0.1:8080");
}

@("配了 ems 就用 ems 常量当缺省，bashub.xml 里的属性仍然优先")
unittest {
  auto ems = loadEms("/tmp/ems-bas", [
    "base": "https://sas.openurp.net",
    "session_id_name": "OpenURP_SID",
  ]);
  auto cfg = parseBashub(`<bashub><ems app-name="bas-hub"/></bashub>`, ems);
  assert(cfg.emsBase == "https://sas.openurp.net");
  assert(cfg.casServer == "https://sas.openurp.net/cas");
  assert(cfg.sessionIdName == "OpenURP_SID");
  assert(cfg.hasCas);

  // 显式写成空串就是「不要这个缺省」
  auto explicitCfg = parseBashub(`<bashub><ems cas=""/></bashub>`, ems);
  assert(!explicitCfg.hasCas);
  assert(explicitCfg.sessionIdName == "OpenURP_SID");

  // 不传 ems 时一切照旧
  assert(parseBashub(`<bashub/>`).sessionIdName == "EMS_SID");
}

@("bashub.xml 没写 <db> 时，从 ems 应用文件里读 <datasource>（scala AppDataSourceFactory 的顺序）")
unittest {
  auto home = uniqueTempDir("bashub-ems-db-");
  scope (exit) rmdirRecurse(home);
  // app-name `bas-hub` → `${home}/bas/hub.xml`（EmsApp.path 的规则）
  mkdirRecurse(buildPath(home, "bas"));
  write(buildPath(home, "bas/hub.xml"), `<app><resources><datasource name="default">
    <serverName>localhost</serverName><databaseName>bas</databaseName><driver>postgresql</driver>
    <user>openurp</user><password>openurp</password></datasource></resources></app>`);
  write(buildPath(home, "bashub.xml"), `<bashub><ems app-name="bas-hub"/></bashub>`);

  auto ems = loadEms(home, ["base": "https://sas.openurp.net"]);
  auto cfg = loadBashub(buildPath(home, "bashub.xml"), ems);
  assert(cfg.hasDb);
  assert(cfg.dbUrl ==
      "host=localhost port=5432 dbname=bas user=openurp password=openurp application_name=bas-hub");

  // bashub.xml 里写了连接串就以它为准（ems 那份只当缺省）
  write(buildPath(home, "explicit.xml"),
      `<bashub><db url="host=other port=5432 dbname=bas"/><ems app-name="bas-hub"/></bashub>`);
  assert(loadBashub(buildPath(home, "explicit.xml"), ems).dbUrl == "host=other port=5432 dbname=bas");

  // 没有 ems 就没有这个缺省，`<db>` 也不写就是「没有可用数据库」
  assert(!loadBashub(buildPath(home, "bashub.xml"), null).hasDb);
  assert(emsDbUrl("bas-hub", home ~ "/nope").length == 0);
}

@("native 仓库可显式配置；上传令牌缺省从 ems 应用文件读")
unittest {
  auto home = uniqueTempDir("bashub-ems-native-");
  scope (exit) rmdirRecurse(home);
  mkdirRecurse(buildPath(home, "bas"));
  write(buildPath(home, "bas/hub.xml"),
      `<app><props><prop key="snapshot.usertoken"> from-app-file </prop></props></app>`);

  auto ems = loadEms(home, ["base": "https://sas.openurp.net"]);
  auto cfg = parseBashub(`<bashub><ems app-name="bas-hub"/></bashub>`, ems);
  assert(cfg.snapshotUsertoken == "from-app-file");

  auto explicitCfg = parseBashub(
      `<bashub><ems app-name="bas-hub"/><repo home="/srv/m2" token="explicit"/></bashub>`, ems);
  assert(explicitCfg.repoHome == "/srv/m2");
  assert(explicitCfg.snapshotUsertoken == "explicit");
}
