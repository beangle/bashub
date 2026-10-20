/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.config_test;
/// 运行配置从 ems.home/profile 推导；不再读取独立的 bashub 配置文件。

import bashub.config;

import beangle.ems : loadEms;

import test.beangle.tempdir : uniqueTempDir;

import std.file : mkdirRecurse, rmdirRecurse, write;
import std.path : buildPath;
import std.string : endsWith;
import std.exception : assertThrown;

@("loadBashub requires an ems deployment")
unittest {
  assertThrown!Exception(loadBashub(null));
}

@("loadBashub applies ems constants and built-in runtime defaults")
unittest {
  auto ems = loadEms("/tmp/ems-bas", [
    "base": "https://sas.openurp.net",
    "inner_base": "http://10.0.0.8",
    "session_id_name": "OpenURP_SID",
  ]);
  auto cfg = loadBashub(ems);
  assert(cfg.listen == "127.0.0.1:8080");
  assert(cfg.apiPrefix == "/api/hub");
  assert(!cfg.authRequired);
  assert(cfg.artifactRefreshMinutes == 360);
  assert(cfg.emsBase == "https://sas.openurp.net");
  assert(cfg.emsInnerApi == "http://10.0.0.8/api");
  assert(cfg.authorityUrl.endsWith("/platform/security/func/bas-hub/resources.json"));
  assert(cfg.casServer == "https://sas.openurp.net/cas");
  assert(cfg.sessionIdName == "OpenURP_SID");
  assert(cfg.hasCas);
}

@("parse listen address")
unittest {
  auto a = parseListen("127.0.0.1:8080");
  assert(a.host == "127.0.0.1" && a.port == 8080);
  assert(parseListen(":9000").host == "127.0.0.1");
  assert(parseListen("9000").port == 9000);
  assert(a.toString == "127.0.0.1:8080");
}

@("loadBashub reads the default datasource from <ems.home>/bas/hub.xml")
unittest {
  auto home = uniqueTempDir("bashub-ems-db-");
  scope (exit) rmdirRecurse(home);
  // app-name `bas-hub` → `${home}/bas/hub.xml`（EmsApp.path 的规则）
  mkdirRecurse(buildPath(home, "bas"));
  write(buildPath(home, "bas/hub.xml"), `<app><resources><datasource name="default">
    <serverName>localhost</serverName><databaseName>bas</databaseName><driver>postgresql</driver>
    <user>openurp</user><password>openurp</password></datasource></resources></app>`);

  auto ems = loadEms(home, ["base": "https://sas.openurp.net"]);
  auto cfg = loadBashub(ems);
  assert(cfg.hasDb);
  assert(cfg.dbUrl ==
      "host=localhost port=5432 dbname=bas user=openurp password=openurp application_name=bas-hub");
  assert(emsDbUrl("bas-hub", home ~ "/nope").length == 0);
}

@("loadBashub reads listen from the application file root attribute")
unittest {
  auto home = uniqueTempDir("bashub-ems-listen-");
  scope (exit) rmdirRecurse(home);
  mkdirRecurse(buildPath(home, "bas"));
  write(buildPath(home, "bas/hub.xml"), `<app listen="0.0.0.0:8899"/>`);

  auto ems = loadEms(home, ["base": "https://sas.openurp.net"]);
  assert(loadBashub(ems).listen == "0.0.0.0:8899");
}
