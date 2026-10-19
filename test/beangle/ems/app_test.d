/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.ems.app_test;
/// EmsApp 的移植部分：app-name → path、清单元素与 `${home}${path}.xml` 的合并。

import beangle.ems.app : EmsApp, appPathOf, mergeAppFile, readEmsApp;

import test.beangle.tempdir : uniqueTempDir;

import std.file : mkdirRecurse, rmdirRecurse, write;
import std.path : buildPath;
import std.typecons : Nullable;

@("appPathOf：`-` 与 `.` 都换成 `/`（对齐 scala EmsAppTest）")
unittest {
  assert(appPathOf("platform-testwebapp") == "/platform/testwebapp");
  assert(appPathOf("bas") == "/bas");
}

@("readEmsApp：从 bashub.xml 形态的文档里读 <ems app-name> 与 props/prop")
unittest {
  auto xml = `<?xml version="1.0" encoding="UTF-8"?>
<bashub listen="0:1"><ems app-name="platform-testwebapp"><props>
  <prop key="logo"> /static/logo.png </prop></props></ems></bashub>`;
  auto app = readEmsApp(xml);
  assert(!app.isNull);
  assert(app.get.name == "platform-testwebapp");
  assert(app.get.path == "/platform/testwebapp");
  assert(app.get.properties["name"] == "platform-testwebapp");
  assert(app.get.properties["logo"] == "/static/logo.png");
}

@("readEmsApp：没有 <ems app-name> 给 null，不把进程带走")
unittest {
  assert(readEmsApp(`<bashub/>`).isNull);
  assert(readEmsApp(`<bashub><ems/></bashub>`).isNull);
  assert(readEmsApp(`<beangle><ems app-name=""><props/></ems></beangle>`).isNull);
}

@("mergeAppFile：叠加 `${home}${path}.xml` 的属性与 props/prop")
unittest {
  auto home = uniqueTempDir("bashub-app-home-");
  scope (exit) rmdirRecurse(home);
  mkdirRecurse(buildPath(home, "platform"));
  write(buildPath(home, "platform/testwebapp.xml"),
      `<app enabled="true"><props><prop key="title"> 测试应用 </prop></props></app>`);

  auto app = readEmsApp(`<bashub><ems app-name="platform-testwebapp"/></bashub>`);
  assert(mergeAppFile(app, home).get.properties["enabled"] == "true");
  assert(mergeAppFile(app, home).get.properties["title"] == "测试应用");
  // 没有那份 xml 时原样返回
  assert(mergeAppFile(app, home ~ "/nope").get.properties["name"] == "platform-testwebapp");
  assert(mergeAppFile(Nullable!EmsApp(), home).isNull);
}
