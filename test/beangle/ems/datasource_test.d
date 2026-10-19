/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.ems.datasource_test;
/// 从 ems 应用文件里读 `<datasource>`：解析、按名字挑、以及变成 libpq 连接串。
/// 夹具照抄本机 `~/.ems/bas/bas/hub.xml` 的形态（那份就是 scala 侧真正在用的配置）。

import beangle.ems.datasource : findDatasource, postgresConnInfo, readDatasource;

import test.beangle.tempdir : uniqueTempDir;

import std.file : mkdirRecurse, rmdirRecurse, write;
import std.path : buildPath;

/// 一份真实形态的应用文件（`<resources>` 里套 `<datasource>`，字段是扁平子元素）
private enum basHubXml = `<?xml version="1.0"?>
<app secret="platform-ws">
  <resources>
    <datasource name="default">
      <serverName>localhost</serverName>
      <databaseName>bas</databaseName>
      <driver>postgresql</driver>
      <user>openurp</user>
      <password>openurp</password>
      <maximumPoolSize>10</maximumPoolSize>
    </datasource>
  </resources>
</app>`;

@("readDatasource：递归找到 <datasource>，扁平子元素与 props/prop 都进 props")
unittest {
  auto ds = readDatasource(basHubXml);
  assert(!ds.isNull);
  assert(ds.get.name == "default");
  assert(ds.get.driver == "postgresql");
  assert(ds.get.user == "openurp");
  assert(ds.get.password == "openurp");
  assert(ds.get.props["serverName"] == "localhost");
  assert(ds.get.props["databaseName"] == "bas");
  assert(ds.get.props["maximumPoolSize"] == "10");

  auto withProps = `<app><datasource name="default"><props>
    <prop name="serverName" value="db.internal"/>
    <prop name="databaseName" value="bas"/></props></datasource></app>`;
  auto p = readDatasource(withProps);
  assert(p.get.props["serverName"] == "db.internal");
  assert(p.get.props["databaseName"] == "bas");
}

@("readDatasource：多个 datasource 按 name 挑，名字为空取最后一个，找不到给空值")
unittest {
  auto xml = `<app>
    <datasource name="a"><driver>postgresql</driver><databaseName>db_a</databaseName></datasource>
    <datasource name="b"><driver>postgresql</driver><databaseName>db_b</databaseName></datasource></app>`;
  assert(readDatasource(xml, "a").get.props["databaseName"] == "db_a");
  assert(readDatasource(xml, "b").get.props["databaseName"] == "db_b");
  assert(readDatasource(xml, "").get.name == "b");
  assert(readDatasource(xml, "nope").isNull);
  assert(readDatasource(`<app><resources/></app>`).isNull);
}

@("readDatasource：ENC(...) 值原样保留（D 侧没有 PBE 解密器），不当密文解")
unittest {
  auto xml = `<app><datasource name="default"><driver>postgresql</driver>
    <databaseName>bas</databaseName><user>u</user><password>ENC(AAAA)</password></datasource></app>`;
  auto ds = readDatasource(xml);
  assert(ds.get.password == "ENC(AAAA)");
  // libpq 的值不含空白就原样拼，`(`/`)` 不用转义——所以解密之前也照样能看出它是个密文
  assert(postgresConnInfo(ds.get).get == "host=localhost port=5432 dbname=bas user=u password=ENC(AAAA)");
}

@("postgresConnInfo：serverName/databaseName → libpq 串，缺省 host/port 按 PG 的口径")
unittest {
  auto info = postgresConnInfo(readDatasource(basHubXml).get, "bas-hub");
  assert(!info.isNull);
  assert(info.get == "host=localhost port=5432 dbname=bas user=openurp password=openurp application_name=bas-hub");

  // 只给库名，host/port 走缺省
  auto minimal = readDatasource(`<app><datasource name="default"><databaseName>bas</databaseName></datasource></app>`);
  assert(postgresConnInfo(minimal.get).get == "host=localhost port=5432 dbname=bas");
}

@("postgresConnInfo：<url> 的 jdbc 形态与 libpq 形态都能用；portNumber 覆盖缺省端口")
unittest {
  auto jdbc = readDatasource(`<app><datasource name="default">
    <url>jdbc:postgresql://db.internal:5433/bas?ssl=true</url></datasource></app>`);
  assert(postgresConnInfo(jdbc.get).get == "host=db.internal port=5433 dbname=bas");

  auto bare = readDatasource(`<app><datasource name="default">
    <url>host=db.internal port=5433 dbname=bas</url></datasource></app>`);
  assert(postgresConnInfo(bare.get).get == "host=db.internal port=5433 dbname=bas");

  auto ported = readDatasource(`<app><datasource name="default"><driver>postgresql</driver>
    <portNumber>6432</portNumber><databaseName>bas</databaseName></datasource></app>`);
  assert(postgresConnInfo(ported.get).get == "host=localhost port=6432 dbname=bas");
}

@("postgresConnInfo：schema 映射成 search_path，值含空白时按 libpq 规则加引号")
unittest {
  auto xml = `<app><datasource name="default"><driver>postgresql</driver>
    <serverName>db host</serverName><databaseName>bas</databaseName><schema>bas_sch</schema>
    <user>u</user><password>p'w</password></datasource></app>`;
  assert(postgresConnInfo(readDatasource(xml).get).get ==
      `host='db host' port=5432 dbname=bas user=u password='p\'w' options='-c search_path=bas_sch'`);
}

@("postgresConnInfo：非 postgres driver 或看不懂的 url 都不给连接串（D 侧只有 postgres 后端）")
unittest {
  auto mysql = readDatasource(`<app><datasource name="default"><driver>mysql</driver>
    <serverName>db</serverName><databaseName>bas</databaseName><user>u</user></datasource></app>`);
  assert(postgresConnInfo(mysql.get).isNull);

  auto odd = readDatasource(`<app><datasource name="default"><driver>postgresql</driver>
    <url>db.internal/bas</url></datasource></app>`);
  assert(postgresConnInfo(odd.get).isNull);

  // driver 没写，但能从 jdbc url 推出来（scala parseXml 同规则）
  auto oracle = readDatasource(`<app><datasource name="default">
    <url>jdbc:oracle:thin:@db:1521:orcl</url></datasource></app>`);
  assert(postgresConnInfo(oracle.get).isNull);
}

@("findDatasource：先应用文件（${home}${path}.xml），再 ${home}/resources.xml")
unittest {
  auto home = uniqueTempDir("bashub-ems-ds-");
  scope (exit) rmdirRecurse(home);
  mkdirRecurse(buildPath(home, "bas"));
  // app-name `bas-hub` → path `/bas/hub`（scala EmsApp.path 的规则）
  write(buildPath(home, "bas/hub.xml"), basHubXml);
  write(buildPath(home, "resources.xml"), `<resources><datasource name="default">
    <driver>postgresql</driver><databaseName>home_db</databaseName></datasource></resources>`);

  assert(findDatasource(home, "bas-hub").get.props["databaseName"] == "bas");
  // 应用文件不在（path 推出来是 /other/app）就退回 resources.xml
  assert(findDatasource(home, "other-app").get.props["databaseName"] == "home_db");
  // 两边都没有这个名字的数据源
  assert(findDatasource(home, "bas-hub", "platform").isNull);
  assert(findDatasource(home ~ "/nope", "bas-hub").isNull);
}
