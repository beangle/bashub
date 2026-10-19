/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.ems.datasource;
/// 从 ems 的应用文件（`${home}${path}.xml`，即 scala `EmsApp.getAppFile`）或 `${home}/resources.xml`
/// （`Ems.getResourceFile`）里读 `<datasource>`，并把它变成 libpq 连接串
/// （scala `AppDataSourceFactory` + `org.beangle.jdbc.ds.DataSourceUtils.parseXml`）。
///
/// 为什么值得移植：scala 应用从来不自己写库连接，这份 XML 就是部署时的唯一真相
/// （本机 `~/.ems/bas/bas/hub.xml` 就是一份）。两条实现路线读同一份文件，运维才不用维护两套。
///
/// 与 scala 的三处差别（README 的裁剪清单里也记着）：
/// - **只认 PostgreSQL**：D 侧 DAO 只有 postgres 后端（`beangle.data.dao.postgres`），driver 不是
///   postgres 就记一条警告、当作没有配置——scala 借 JDBC 驱动还能吃 mysql/oracle/dm 这些。
/// - **不解密**：值形如 `ENC(...)` 时原样保留并警告（scala 会拿 `Ems.decryptor` 解），所以配了密文的
///   部署得先把明文填进来。
/// - **不联网**：应用文件与 `resources.xml` 都没有就当作没有配置（scala 还会问
///   `EmsApi.getDatasourceUrl`）。

import beangle.commons.xml : children, elementText, getAttrs, isNamedElement, parseRoot;
import beangle.ems.app : appPathOf, readAppFile;

import dxml.dom : DOMEntity;

import std.algorithm.searching : canFind, endsWith, startsWith;
import std.array : appender, join;
import std.file : exists, read;
import std.path : buildPath;
import std.string : indexOf, strip;
import std.typecons : Nullable;

import vibe.core.log : logWarn;

/// 一份 `<datasource>`（scala `org.beangle.jdbc.ds.DatasourceConfig` 里我们会用到的那几个字段）。
///
/// 别的直接子元素（`serverName`/`databaseName`/`portNumber`/`maximumPoolSize`…）与 `props/prop`
/// 一并进 `props`，与 scala `DataSourceUtils.parseXml` 的口径一致——两种写法在真实文件里都有
/// （`~/.ems/bas/bas/hub.xml` 用子元素，`webapp.xml` 用 `props/prop`）。
struct Datasource {
  string name;
  string driver;
  /// `<url>` 元素（`props/prop` 里那个 `url` 留在 `props` 里，两者都认，见 `datasourceUrl`）
  string url;
  string user;
  string password;
  /// `<schema>`：pg 里就是 `search_path`（scala 把 schema 交给 `PGSimpleDataSource.setSchema`）
  string schema;
  string[string] props;
}

/// 在 XML 文本里找 `<datasource name="...">`，取最后一个匹配（scala 是「后一个覆盖前一个」）。
///
/// `name` 传空串表示「不挑名字」，与 scala `DataSourceUtils.parseXml(is, null)` 同义；
/// 找不到（包括文件里一个 `<datasource>` 都没有）返回空值。
Nullable!Datasource readDatasource(string xmlText, string name = "default") {
  auto root = parseRoot(xmlText);
  typeof(root) found;
  if (!findDatasourceNode(root, name, found))
    return Nullable!Datasource();
  return Nullable!Datasource(parseDatasource(found));
}

/// 按 scala `AppDataSourceFactory` 的顺序找数据源：先应用文件 `${home}${path}.xml`，再
/// `${home}/resources.xml`；两处都没有就返回空值。
///
/// scala 的第一道判据是「文件内容里有 `</datasource>`」——等价于「这份文件里能找到数据源」，
/// 所以这里直接用 `readDatasource` 的结果决定要不要往下走。差别在于：应用文件里只有别的名字的
/// 数据源时 scala 会拿着空配置去建连接池（启动直接报错），这里选择继续找 `resources.xml`。
Nullable!Datasource findDatasource(string home, string appName, string name = "default") {
  auto text = readAppFile(home, appPathOf(appName));
  if (!text.isNull) {
    auto appDs = readDatasource(text.get, name);
    if (!appDs.isNull)
      return appDs;
  }
  auto resFile = buildPath(home, "resources.xml");
  if (exists(resFile)) {
    auto homeDs = readDatasource(cast(string) read(resFile), name);
    if (!homeDs.isNull)
      return homeDs;
  }
  return Nullable!Datasource();
}

/** `<datasource>` → libpq 连接串（如 `host=localhost port=5432 dbname=bas user=openurp`）。
 *
 * 字段口径对齐 scala `DataSourceUtils.parseXml` + `DataSourceFactory.postInit`：
 * `url` 优先（`jdbc:postgresql://host:port/db` 或直接就是 `key=value` 串），否则用 `serverName`
 * （缺省 localhost）/`portNumber`（缺省 5432）/`databaseName`；`schema` 映射成
 * `options=-c search_path=`；`applicationName` 对应 scala 的 `setApplicationName(EmsApp.name)`，
 * 填的是应用名（在 `pg_stat_activity` 里能认出是哪条路线连的）。
 *
 * driver 不是 postgres、或 `url` 是看不懂的形态时返回空值——由调用方决定退回什么缺省。
 */
Nullable!string postgresConnInfo(const Datasource ds, string applicationName = null) {
  auto driver = effectiveDriver(ds);
  if (driver.length > 0 && driver != "postgresql" && driver != "pgsql") {
    logWarn("Datasource '%s' uses driver '%s'; bashub only opens postgresql, skipped.", ds.name, driver);
    return Nullable!string();
  }

  auto url = datasourceUrl(ds);
  auto parts = appender!(string[])();
  if (url.length > 0) {
    string[] fragments;
    if (!parseUrl(url, fragments)) {
      logWarn("Cannot read datasource '%s' url '%s'; use jdbc:postgresql://host:port/db or a key=value string.",
          ds.name, url);
      return Nullable!string();
    }
    parts.put(fragments);
  } else {
    parts.put("host=" ~ connValue(ds.props.get("serverName", "localhost")));
    parts.put("port=" ~ connValue(ds.props.get("portNumber", "5432")));
    auto dbname = ds.props.get("databaseName", "");
    if (dbname.length > 0)
      parts.put("dbname=" ~ connValue(dbname));
  }
  if (ds.user.length > 0)
    parts.put("user=" ~ connValue(ds.user));
  if (ds.password.length > 0)
    parts.put("password=" ~ connValue(ds.password));
  if (ds.schema.length > 0)
    parts.put("options=" ~ connValue("-c search_path=" ~ ds.schema));
  if (applicationName !is null && applicationName.length > 0)
    parts.put("application_name=" ~ connValue(applicationName));
  if (parts.data.length == 0) {
    logWarn("Datasource '%s' has no usable connection field; skipped.", ds.name);
    return Nullable!string();
  }
  return Nullable!string(parts.data.join(" "));
}

/// 递归找最后一个匹配的 `<datasource>`（`name` 为空串时匹配任意名字）。
private bool findDatasourceNode(T)(ref DOMEntity!T node, string name, ref DOMEntity!T found) {
  bool ok = false;
  foreach (c; node.children) {
    if (!isNamedElement(c.type))
      continue;
    if (c.name == "datasource") {
      auto dsName = getAttrs(c).get("name", "").strip;
      if (name.length == 0 || dsName == name) {
        found = c; // 后一个覆盖前一个，与 scala 的循环同口径
        ok = true;
      }
    }
    if (findDatasourceNode(c, name, found))
      ok = true;
  }
  return ok;
}

/// 一个 `<datasource>` 元素 → Datasource（scala `DataSourceUtils.parseXml(xml: Node)`）
private Datasource parseDatasource(T)(ref DOMEntity!T elem) {
  Datasource ds;
  ds.name = getAttrs(elem).get("name", "").strip;
  ds.url = childText(elem, "url");
  ds.driver = childText(elem, "driver");
  ds.user = childText(elem, "user");
  ds.password = childText(elem, "password");
  ds.schema = childText(elem, "schema");

  // 不移植 `Ems.decryptor`（PBE）：命中密文时原样保留，只提醒一句——拿着 `ENC(...)` 当密码去连库，
  // 报出来的错会离真正的原因很远。
  warnEncrypted("url", ds.url);
  warnEncrypted("user", ds.user);
  warnEncrypted("password", ds.password);

  // `props/prop` 这里用 name/value（jdbc 的写法），与 `EmsApp` 的 key/文本不同
  foreach (props; children(elem, "props")) {
    foreach (prop; children(props, "prop")) {
      auto attrs = getAttrs(prop);
      auto key = attrs.get("name", "").strip;
      if (key.length > 0)
        ds.props[key] = attrs.get("value", "").strip;
    }
  }

  // 其余的扁平子元素进 props：`serverName`/`databaseName`/`maximumPoolSize` 都是这种（scala 的 `xml \ "_"`）
  enum processed = ["url", "driver", "user", "password", "schema", "catalog", "props"];
  foreach (c; elem.children) {
    if (!isNamedElement(c.type) || processed.canFind(c.name))
      continue;
    auto text = c.elementText.strip;
    if (text.length > 0)
      ds.props[c.name] = text;
  }
  return ds;
}

/// 直接子元素的文本（scala 用的是后代查询 `\\`，真实文件里这几个字段都直接挂在 `<datasource>` 下）
private string childText(T)(ref DOMEntity!T elem, string label) {
  foreach (c; children(elem, label))
    return c.elementText.strip;
  return "";
}

/// 生效的 driver 名：`<driver>` 优先，其次从 `jdbc:` URL 里推（scala `parseXml` 同规则）
private string effectiveDriver(const Datasource ds) {
  if (ds.driver.length > 0)
    return ds.driver;
  auto url = datasourceUrl(ds);
  return url.startsWith("jdbc:") ? driverOfJdbcUrl(url) : "";
}

/// `url` 元素优先，其次 `props/prop` 里的 `url`——scala 里两者都进 Hikari 的 `jdbcUrl`
private string datasourceUrl(const Datasource ds) {
  return ds.url.length > 0 ? ds.url : ds.props.get("url", "");
}

/// `jdbc:postgresql://...` → `postgresql`（scala `Strings.substringBetween(url, "jdbc:", ":")`）
private string driverOfJdbcUrl(string url) {
  auto body = url["jdbc:".length .. $];
  auto idx = body.indexOf(':');
  return idx < 0 ? "" : body[0 .. idx];
}

/// `<url>` 两种形态 → libpq 片段：
/// - 已经是 `key=value` 串（libpq 串）→ 原样一段；
/// - `jdbc:postgresql://host[:port]/db[?...]` → 拆成 host/port/dbname。
/// 其余形态返回 false，由调用方当作没有配置。
private bool parseUrl(string url, out string[] parts) {
  if (!url.startsWith("jdbc:") && !url.canFind("//") && url.canFind('=')) {
    parts ~= url;
    return true;
  }
  auto body = url.startsWith("jdbc:") ? url["jdbc:".length .. $] : url;
  auto colon = body.indexOf(':');
  if (colon >= 0)
    body = body[colon + 1 .. $]; // 去掉 `postgresql:`
  if (!body.startsWith("//"))
    return false;
  body = body[2 .. $]; // 去掉 `//`

  auto slash = body.indexOf('/');
  auto hostPort = slash < 0 ? body : body[0 .. slash];
  auto dbname = slash < 0 ? "" : body[slash + 1 .. $];
  // JDBC 的查询参数名与 libpq 不同（`?user=x&ssl=true` 这类），硬套会更糟，先丢掉
  auto query = dbname.indexOf('?');
  if (query >= 0)
    dbname = dbname[0 .. query];

  auto portSep = hostPort.indexOf(':');
  if (portSep >= 0) {
    if (portSep > 0)
      parts ~= "host=" ~ connValue(hostPort[0 .. portSep]);
    parts ~= "port=" ~ connValue(hostPort[portSep + 1 .. $]);
  } else if (hostPort.length > 0) {
    parts ~= "host=" ~ connValue(hostPort);
  }
  if (dbname.length > 0)
    parts ~= "dbname=" ~ connValue(dbname);
  return true;
}

/// libpq conninfo 里的一个值：含空白/引号/反斜杠/等号时用单引号包住，内部 `'` 与 `\` 转义。
private string connValue(string value) {
  bool quote = value.length == 0;
  foreach (ch; value) {
    if (ch == ' ' || ch == '\t' || ch == '\'' || ch == '\\' || ch == '=') {
      quote = true;
      break;
    }
  }
  if (!quote)
    return value;
  auto buf = appender!string();
  buf.put('\'');
  foreach (ch; value) {
    if (ch == '\'' || ch == '\\')
      buf.put('\\');
    buf.put(ch);
  }
  buf.put('\'');
  return buf.data;
}

/// 值是否被 `ENC(...)` 包着（scala `Config.PBEProcessor`：只认「以 `ENC(` 开头、以 `)` 结尾」）
private bool isEncrypted(string value) {
  return value.length > 5 && value.startsWith("ENC(") && value.endsWith(")");
}

private void warnEncrypted(string key, string value) {
  if (isEncrypted(value))
    logWarn("Datasource %s is ENC(...); bashub has no PBE decryptor and keeps it as-is.", key);
}
