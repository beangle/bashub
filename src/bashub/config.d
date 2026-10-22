/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.config;
/// 运行配置。监听可来自应用文件或命令行；日志、接口与授权刷新使用内置缺省；
/// EMS 常量与数据库全部来自 `ems.home`。
/// 不再读取独立的 bashub 配置文件，因此没有可热加载的部分。

import beangle.ems : Ems;
import beangle.ems.app : appFileAttribute;
import beangle.ems.datasource : findDatasource, postgresConnInfo;
import std.conv : ConvException, to;
import std.string : indexOf, lastIndexOf, strip, toLower;

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
  string apiPrefix = "/api/bashub";
  /// 是否要求登录；缺省必须登录，只有显式 `auth="none"` 才关闭。
  bool authRequired = true;
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
  /// 会话 cookie 名（ems 的 `Ems.sid.name`）
  string sessionIdName = "EMS_SID";
  /// 组件最新版本刷新间隔（分钟）；0 表示关闭周期刷新
  uint artifactRefreshMinutes = 360;
  /// 节点轻量健康采样间隔（秒）；0 表示关闭 `report:health` 下发
  uint agentHealthIntervalSeconds = 300;
  /// 健康采样窗口：bashub 主机时区当天分钟数，含 start、不含 end；允许跨午夜
  ushort agentHealthStartMinute = 7 * 60;
  ushort agentHealthEndMinute = 22 * 60;

  bool hasDb() const { return dbUrl.length > 0; }

  bool hasCas() const { return casServer.length > 0; }
}

/** 从 EMS profile 构造运行配置；没有 EMS 部署句柄就拒绝启动。 */
HubConfig loadBashub(Ems ems) {
  if (ems is null)
    throw new Exception("ems deployment is required; use --ems.profile=<profile> or --ems.home=<dir>");

  HubConfig cfg;
  cfg.emsBase = ems.base;
  cfg.emsInnerApi = ems.innerApi;
  cfg.casServer = ems.cas;
  cfg.sessionIdName = ems.sid.name;
  cfg.dbUrl = emsDbUrl(cfg.appName, ems.env.home);
  auto listen = appFileAttribute(ems.env.home, cfg.appName, "listen");
  if (listen.length > 0)
    cfg.listen = parseListen(listen).toString;
  auto auth = appFileAttribute(ems.env.home, cfg.appName, "auth").strip.toLower;
  if (auth.length > 0) {
    if (auth == "required" || auth == "true" || auth == "1")
      cfg.authRequired = true;
    else if (auth == "none" || auth == "false" || auth == "0")
      cfg.authRequired = false;
    else
      throw new Exception("unknown auth value in " ~ cfg.appName ~ ".xml: " ~ auth);
  }
  auto healthInterval = appFileAttribute(ems.env.home, cfg.appName, "agent-health-interval");
  if (healthInterval.length > 0)
    cfg.agentHealthIntervalSeconds = parseUIntAttr(healthInterval, "agent-health-interval");
  auto healthStart = appFileAttribute(ems.env.home, cfg.appName, "agent-health-start");
  if (healthStart.length > 0)
    cfg.agentHealthStartMinute = parseClockAttr(healthStart, "agent-health-start");
  auto healthEnd = appFileAttribute(ems.env.home, cfg.appName, "agent-health-end");
  if (healthEnd.length > 0)
    cfg.agentHealthEndMinute = parseClockAttr(healthEnd, "agent-health-end");
  if (cfg.authorityUrl.length == 0 && cfg.emsInnerApi.length > 0)
    cfg.authorityUrl = cfg.emsInnerApi ~ "/platform/security/func/" ~ cfg.appName ~ "/resources.json";
  return cfg;
}

/// 命令行覆盖应用文件里的监听地址；空串表示命令行未指定。
void applyListenOverride(ref HubConfig cfg, string listen) {
  if (listen.length == 0)
    return;
  cfg.listen = parseListen(listen).toString;
}

/** `auth="none"` 只允许本机调试；非回环监听必须登录，避免误把管理面暴露到网络。 */
void validateBashubConfig(HubConfig cfg) {
  if (!cfg.authRequired) {
    auto addr = parseListen(cfg.listen);
    auto host = addr.host.strip.toLower;
    if (host != "127.0.0.1" && host != "localhost" && host != "::1" && host != "[::1]")
      throw new Exception("auth=\"none\" is only allowed on a loopback listen address; got " ~ cfg.listen);
  }
  if (cfg.agentHealthIntervalSeconds > 0
      && (cfg.agentHealthIntervalSeconds < 60 || cfg.agentHealthIntervalSeconds > 24 * 60 * 60))
    throw new Exception("agent-health-interval must be 0 or between 60 and 86400 seconds");
  if (cfg.agentHealthStartMinute >= 24 * 60 || cfg.agentHealthEndMinute >= 24 * 60)
    throw new Exception("agent-health-start/end must be HH:MM");
  if (cfg.agentHealthIntervalSeconds > 0 && cfg.agentHealthStartMinute == cfg.agentHealthEndMinute)
    throw new Exception("agent-health-start and agent-health-end must differ");
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

private uint parseUIntAttr(string value, string key) {
  try {
    return value.to!uint;
  } catch (ConvException) {
    throw new Exception(key ~ " must be a non-negative integer: " ~ value);
  }
}

private ushort parseClockAttr(string value, string key) {
  auto colon = value.indexOf(':');
  if (colon <= 0 || colon + 1 >= value.length)
    throw new Exception(key ~ " must be HH:MM: " ~ value);
  auto hour = parseUIntAttr(value[0 .. colon], key);
  auto minute = parseUIntAttr(value[colon + 1 .. $], key);
  if (hour >= 24 || minute >= 60)
    throw new Exception(key ~ " must be HH:MM: " ~ value);
  return cast(ushort) (hour * 60 + minute);
}
