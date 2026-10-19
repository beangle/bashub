/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.config;
/// bashub.xml 的解析结果。一份配置只有「监听地址、数据库连接串、接口前缀」三件事，没有可热加载的部分。

import beangle.commons.xml : children, getAttrs, parseRoot, readConfigText;
import beangle.ems : Ems, emsFromEnvironment;
import beangle.ems.app : mergeAppFile, readEmsApp;
import beangle.ems.datasource : findDatasource, postgresConnInfo;
import std.conv : ConvException, to;
import std.string : lastIndexOf, split, strip;

import vibe.core.log : logInfo;

/** 监听地址：`host:port`，缺省 host 为 127.0.0.1。 */
struct ListenAddr {
  string host = "127.0.0.1";
  ushort port = 8080;

  string toString() const { return host ~ ":" ~ port.to!string; }
}

/** 运行时配置。 */
struct HubConfig {
  string listen = "127.0.0.1:8080";
  /// libpq 连接串（如 `host=127.0.0.1 port=5432 user=bashub dbname=bas`）；留空则不可用数据库
  string dbUrl;
  string apiPrefix = "/api/hub";
  /// 是否要求登录（预演阶段只判有无会话头，不做 CAS）
  bool authRequired = false;
  string logLevel = "info";
  string logFile = "console";
  /// 前端运行时配置下发的 ems 地址与名称
  string emsBase;
  /// 内网 ems API（scala `Ems.innerApi`），远程授权域从它取
  string emsInnerApi;
  string appName = "bas-hub";
  /// ems 资源授权域地址；空则不做远程授权（所有资源只要求登录）
  string authorityUrl;
  /// 授权域刷新间隔（秒）；0 表示只在启动时取一次
  uint authorityRefreshSeconds = 300;
  /// 允许跨域的前端来源（完整 origin 或主机名）；缺省含本机开发地址
  string[] corsOrigins = ["localhost", "127.0.0.1"];
  /// CAS 会话服务根地址（如 `https://sas.openurp.net/cas`）；留空则 `sessions` 走演示数据
  string casServer;
  /// 会话 cookie 名（ems 的 `Ems.sid.name`）；配了 ems 就用它的，否则用 scala 侧的缺省值
  string sessionIdName = "EMS_SID";
  /// native 发行包仓库 home（scala `NativeHelper.default` 的 `~/.m2`）
  string repoHome = "~/.m2";
  /// `POST /repo/native/upload/{path}` 的 `snapshot.usertoken`；空表示禁用上传
  string snapshotUsertoken;
  /// 组件最新版本刷新间隔（分钟）；0 表示关闭周期刷新
  uint artifactRefreshMinutes = 360;

  bool hasDb() const { return dbUrl.length > 0; }

  bool hasCas() const { return casServer.length > 0; }
}

/** 取属性（缺省值带默认）。std 的 AA `in` 返回指针，这里统一收口，免得每处都写 `(*v).strip`。 */
private string attrOf(string[string] attrs, string key, string def = "") {
  if (auto v = key in attrs)
    return (*v).strip;
  return def;
}

/** 解析 bashub.xml 文本。
 *
 * `ems` 非空时（宿主配了 `ems.home`/`ems.base`/`ems.profile`）用它当缺省：ems 地址、cas 地址、
 * 会话 cookie 名都从 ems 常量推出来，bashub.xml 里的属性仍然优先。空则一切照旧——没跑在 ems
 * 部署下的机器不该因为这次改动换行为。
 */
HubConfig parseBashub(string content, Ems ems = null) {
  HubConfig cfg;
  if (ems !is null) {
    cfg.emsBase = ems.base;
    cfg.emsInnerApi = ems.innerApi;
    cfg.casServer = ems.cas;
    cfg.sessionIdName = ems.sid.name;
  }
  auto root = parseRoot(content);
  if (root.name != "bashub")
    throw new Exception("root element must be <bashub>, but found <" ~ root.name ~ ">");

  auto attrs = getAttrs(root);
  cfg.listen = attrOf(attrs, "listen", cfg.listen);
  cfg.logLevel = attrOf(attrs, "log-level", cfg.logLevel);
  cfg.logFile = attrOf(attrs, "log-file", cfg.logFile);

  foreach (db; children(root, "db")) {
    auto a = getAttrs(db);
    cfg.dbUrl = attrOf(a, "url", cfg.dbUrl);
  }

  foreach (api; children(root, "api")) {
    auto a = getAttrs(api);
    cfg.apiPrefix = attrOf(a, "prefix", cfg.apiPrefix);
    cfg.authRequired = attrOf(a, "auth") == "required";
    cfg.authorityUrl = attrOf(a, "authority-url", cfg.authorityUrl);
    auto origins = attrOf(a, "cors-origins", "");
    if (origins.length > 0) {
      cfg.corsOrigins = null;
      foreach (origin; origins.split(",")) {
        auto text = origin.strip;
        if (text.length > 0)
          cfg.corsOrigins ~= text;
      }
    }
    auto refresh = attrOf(a, "authority-refresh-minutes", "");
    if (refresh.length > 0) {
      try {
        cfg.authorityRefreshSeconds = refresh.to!uint * 60;
      } catch (ConvException e) {
        throw new Exception("api authority-refresh-minutes must be a non-negative integer: " ~ refresh);
      }
    }
  }

  foreach (emsElem; children(root, "ems")) {
    auto a = getAttrs(emsElem);
    cfg.emsBase = attrOf(a, "base", cfg.emsBase);
    cfg.appName = attrOf(a, "app-name", cfg.appName);
    cfg.casServer = attrOf(a, "cas", cfg.casServer);
    cfg.sessionIdName = attrOf(a, "session-id-name", cfg.sessionIdName);
  }

  foreach (repo; children(root, "repo")) {
    auto a = getAttrs(repo);
    cfg.repoHome = attrOf(a, "home", cfg.repoHome);
    cfg.snapshotUsertoken = attrOf(a, "token", cfg.snapshotUsertoken);
  }

  foreach (artifacts; children(root, "artifacts")) {
    auto text = attrOf(getAttrs(artifacts), "refresh-minutes", cfg.artifactRefreshMinutes.to!string);
    try {
      cfg.artifactRefreshMinutes = text.to!uint;
    } catch (ConvException e) {
      throw new Exception("artifacts refresh-minutes must be a non-negative integer: " ~ text);
    }
  }

  // scala `EmsApp.properties` 从 `${ems.home}${app.path}.xml` 的根属性/`props` 取这个令牌
  if (cfg.snapshotUsertoken.length == 0 && ems !is null)
    cfg.snapshotUsertoken = emsAppProperty(ems.env.home, cfg.appName, "snapshot.usertoken");
  if (cfg.authorityUrl.length == 0 && cfg.emsInnerApi.length > 0)
    cfg.authorityUrl = cfg.emsInnerApi ~ "/platform/security/func/" ~ cfg.appName ~ "/resources.json";
  return cfg;
}

/// 从 ems 应用文件读一个属性；文件不存在或属性缺失都返回空串。
private string emsAppProperty(string home, string appName, string key) {
  auto manifest = readEmsApp(`<beangle><ems app-name="` ~ appName ~ `"/></beangle>`);
  auto merged = mergeAppFile(manifest, home);
  return merged.isNull ? "" : merged.get.properties.get(key, "");
}

/** 读并解析配置文件；ems 常量按环境变量取（没配就是缺省）。 */
HubConfig loadBashub(string configFile) {
  return loadBashub(configFile, emsFromEnvironment());
}

/** 同上，但 ems 常量由调用方给（app.d 建好之后顺手把「用了哪套 ems」打进日志）。
 *
 * 顺带补上 `<db>` 的缺省：`bashub.xml` 里没写连接串时，从 ems 的应用文件（scala
 * `EmsApp.getAppFile`）或 `resources.xml` 里读 `<datasource>`——真实部署里库连接就写在那一份
 * XML 上，两条实现路线读同一份文件，运维才不用维护两套。
 */
HubConfig loadBashub(string configFile, Ems ems) {
  auto cfg = parseBashub(readConfigText(configFile), ems);
  if (!cfg.hasDb && ems !is null)
    cfg.dbUrl = emsDbUrl(cfg.appName, ems.env.home);
  return cfg;
}

/** 从 ems 部署里取库连接串；空串 = 没有可用的（调用方按缺少数据库拒绝启动）。
 *
 * 只记「解析到了哪个数据源」，不打印连接串本身——里面有密码。
 */
string emsDbUrl(string appName, string home, string datasourceName = "default") {
  auto ds = findDatasource(home, appName, datasourceName);
  if (ds.isNull)
    return "";
  auto info = postgresConnInfo(ds.get, appName);
  if (info.isNull)
    return "";
  logInfo("Datasource '%s' resolved from ems home %s", datasourceName, home);
  return info.get;
}

/** `host:port` / `:port` / `port` → ListenAddr。 */
ListenAddr parseListen(string listen) {
  auto text = listen.strip();
  auto idx = text.lastIndexOf(':');
  ListenAddr addr;
  if (idx < 0) {
    addr.port = text.to!ushort;
    return addr;
  }
  auto host = text[0 .. idx].strip();
  if (host.length > 0)
    addr.host = host;
  addr.port = text[idx + 1 .. $].strip.to!ushort;
  return addr;
}
