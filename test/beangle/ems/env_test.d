/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.ems.env_test;
/// ems 环境推导：这套规则与 scala 的 `EmsEnv` 逐条对齐（同一份 conf.properties 两侧要推出同一套地址）。

import beangle.ems.env : findHome, innerEnv, loadEnv, readConfig;

import test.beangle.tempdir : uniqueTempDir;

import std.file : mkdir, rmdirRecurse, write;
import std.path : buildPath;

@("没有 conf.properties 时按 base 推出一整套地址（对齐 scala EmsEnvTest）")
unittest {
  auto env = loadEnv("/tmp/ems", ["base": "localhost"]);
  assert(env.base == "http://localhost");
  assert(env.api == "http://localhost/api");
  assert(env.cas == "http://localhost/cas");
  assert(env.portal == "http://localhost/portal");
  assert(env.index == "http://localhost/portal");
  assert(env.blob == "http://localhost/blob");
  assert(env.webapp == "http://localhost");
  assert(env.staticUrl == "http://localhost/static");
  assert(env.key == "ems");
  assert(env.profile == "ems"); // profile 从 home 末段推出来
}

@("properties 覆盖模板；末尾斜杠去掉；非 http 的补 scheme")
unittest {
  auto env = loadEnv("/tmp/ems", [
    "base": "https://sas.openurp.net/",
    "cas": "https://cas.openurp.net/cas/",
    "api": "10.0.0.1/api",
    "key": "secret",
  ]);
  assert(env.base == "https://sas.openurp.net");
  assert(env.cas == "https://cas.openurp.net/cas");
  assert(env.api == "http://10.0.0.1/api");
  assert(env.portal == "https://sas.openurp.net/portal");
  assert(env.key == "secret");
}

@("inner_base 只换 base，其余地址跟着重推")
unittest {
  auto outer = loadEnv("/tmp/ems", ["base": "https://sas.openurp.net"]);
  assert(innerEnv(outer).api == outer.api); // 没配 inner_base 就原样返回

  auto env = loadEnv("/tmp/ems", ["base": "https://sas.openurp.net", "inner_base": "10.0.0.1"]);
  assert(env.api == "https://sas.openurp.net/api");
  assert(innerEnv(env).api == "http://10.0.0.1/api");
}

@("conf.properties 里的 base 就是 base；读不到的文件给空表")
unittest {
  auto dir = uniqueTempDir("bashub-ems-conf-");
  scope (exit) rmdirRecurse(dir);
  write(buildPath(dir, "conf.properties"),
      "# ems 部署配置\nbase=sas.openurp.net\nsession_id_name=OpenURP_SID\n");

  auto env = loadEnv(dir, readConfig(dir));
  assert(env.base == "http://sas.openurp.net");
  assert(env.properties["session_id_name"] == "OpenURP_SID");
  assert(readConfig(buildPath(dir, "nope")).length == 0);
}

@("findHome：ems.home 优先，其次 ems.base + profile 目录")
unittest {
  assert(findHome(["ems.home": "/data/ems/bas"]) == "/data/ems/bas");
  assert(findHome(["ems.home": "", "ems.base": "/data/ems", "ems.profile": "bas"]) == "/data/ems/bas");
  assert(findHome(["HOME": "/root", "ems.profile": "x"]) == "/root/.ems/x");

  auto base = uniqueTempDir("bashub-ems-home-");
  scope (exit) rmdirRecurse(base);
  mkdir(buildPath(base, "bas"));
  assert(findHome(["ems.base": base]) == buildPath(base, "bas"));

  auto empty = uniqueTempDir("bashub-ems-empty-");
  scope (exit) rmdirRecurse(empty);
  assert(findHome(["ems.base": empty]) == buildPath(empty, "local"));
}
