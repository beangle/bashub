/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.app;
/// 进程入口：读 `-f bashub.xml` → 建资源表/Dao → 装路由 → 起 HTTP。
/// 与 Scala 侧的差别在「没有 Spring/Tomcat 容器」：这里一个进程、一个事件循环，
/// 配置只在启动时读一次（没有热加载，见 README 的裁剪清单）。

import beangle.data.dao : Dao, DaoException;
import beangle.data.dao.postgres : DbDao;
import beangle.data.resource : Registry;
import beangle.commons.sysprops : systemVars;
import beangle.commons.net.curl : curlGet;
import beangle.ems : emsFromEnvironment;
import beangle.jsonapi.store : Store;
import beangle.security.cas : CasConfig, CasSessionRepo;
import beangle.security.session : SessionRepo;

import bashub.agent.registry : AgentRegistry;
import bashub.artifactversion : refreshAllArtifactVersions;
import bashub.config;
import bashub.logging;
import bashub.resources;
import bashub.route;
import bashub.security : HubSecurity;
import bashub.store;

import vibe.core.args : setCommandLineArgs;
import vibe.core.core : runApplication, setTimer;
import vibe.core.log : logError, logInfo, logWarn;
import vibe.http.server : HTTPListener, HTTPServerSettings, listenHTTP;

import core.time : minutes;
import std.file : exists;
import std.functional : toDelegate;
import std.getopt : GetOptException, getopt;
import std.path : expandTilde;
import std.stdio : stderr, writeln;

/// 启动阶段失败（systemd 据此不重启）。
enum ExitStartupError = 2;
/// `--check-schema` 发现漂移。
enum ExitSchemaDrift = 3;

/// bashub 自己的命令行：配置文件路径、部署选项，以及「不是 bashub 的那些参数」。
struct HubArgs {
  string configFile;
  string[string] options;
  bool checkSchema;
  bool help;
  /// 剩下的（含 argv[0]），原样交回 vibe
  string[] rest;
}

/** bashub 自己解析命令行，再把剩下的交回 vibe。
 *
 * 命令行采用 D/POSIX 形式：`--ems.profile=bas` 或 `--ems.profile bas`。只有明确支持的
 * 选项才会被消费；未知选项（包括 JVM 风格的 `-Dkey=value`）由 getopt 直接报错，
 * 不会悄悄落到 vibe 的参数解析里。编译期开 `VibeDisableCommandLineParsing`
 * （见 dub.json），解析完再 `setCommandLineArgs` 把剩余参数交回 vibe。
 */
HubArgs parseArgs(string[] args) {
  HubArgs parsed;
  string emsProfile;
  string emsHome;
  string emsBase;
  getopt(args,
      "f|file", &parsed.configFile,
      "check-schema", &parsed.checkSchema,
      "h|help", &parsed.help,
      "ems.profile", &emsProfile,
      "ems.home", &emsHome,
      "ems.base", &emsBase);
  if (emsProfile.length)
    parsed.options["ems.profile"] = emsProfile;
  if (emsHome.length)
    parsed.options["ems.home"] = emsHome;
  if (emsBase.length)
    parsed.options["ems.base"] = emsBase;
  parsed.rest = args;
  return parsed;
}

private void printUsage() {
  writeln("Usage: bashub [-f <bashub.xml>] [--check-schema]");
  writeln("              [--ems.profile=<name>] [--ems.home=<dir>] [--ems.base=<dir>]");
  writeln();
  writeln("  -f, --file <path>    配置文件路径（缺省 ./bashub.xml）");
  writeln("  --check-schema       只检查库表/列是否与资源定义一致，然后退出");
  writeln("  --ems.profile=<name> 指定 ems 部署 profile，如 --ems.profile=bas");
  writeln("  --ems.home=<dir>     直接指定 ems home，如 --ems.home=/data/ems/bas");
  writeln("  --ems.base=<dir>     指定 ems base，缺省 ~/.ems");
  writeln("  -h, --help           显示帮助");
}

// 跑 dub test 时由测试运行器提供 main，此处不编译（与 micdn 同一手法）。
version (unittest) {
} else {
int main(string[] args) {
  HubArgs parsedArgs;
  try {
    parsedArgs = parseArgs(args);
  } catch (GetOptException e) {
    stderr.writeln("bashub: " ~ e.msg);
    printUsage();
    return ExitStartupError;
  }
  if (parsedArgs.help) {
    printUsage();
    return 0;
  }
  setCommandLineArgs(parsedArgs.rest);

  auto configFile = parsedArgs.configFile;
  if (configFile is null)
    configFile = "bashub.xml";
  configFile = expandTilde(configFile);
  if (!exists(configFile)) {
    stderr.writeln("bashub: config file[" ~ configFile ~ "] not exists!");
    return ExitStartupError;
  }

  HubConfig cfg;
  // 环境变量 + 命令行部署选项（后者覆盖前者）
  auto ems = emsFromEnvironment(systemVars(parsedArgs.options));
  try {
    cfg = loadBashub(configFile, ems);
    applyBashubLogging(cfg.logFile, cfg.logLevel);
  } catch (Exception e) {
    stderr.writeln("bashub: " ~ e.msg);
    return ExitStartupError;
  }
  // 部署配置最容易搞混的就是「到底读了哪个 ems」，起服务时留一条
  if (ems !is null)
    logInfo("Ems deployment: %s (base %s, cookie %s)", ems.env.home, ems.base, ems.sid.name);

  auto reg = hubRegistry();
  if (parsedArgs.checkSchema)
    return runSchemaCheck(cfg, reg);

  Store store;
  try {
    auto dao = createDao(cfg);
    logInfo("Data backend: %s", dao.backend);
    try {
      warnSchemaDrift(dao, reg);
    } catch (Exception e) {
      logWarn("Schema check failed: %s", e.msg);
    }
    store = createHubStore(reg, dao);
  } catch (Exception e) {
    logError("Init data access failed: %s", e.msg);
    return ExitStartupError;
  }

  HTTPListener listener;
  try {
    auto addr = parseListen(cfg.listen);
    auto settings = new HTTPServerSettings;
    settings.bindAddresses = [addr.host];
    settings.port = addr.port;
    settings.serverString = null;
    auto sessions = createSessionRepo(cfg);
    HubSecurity security;
    if (cfg.authRequired || sessions !is null) {
      security = new HubSecurity(cfg, sessions);
      if (cfg.authRequired)
        security.warmup();
    }
    listener = listenHTTP(settings,
        buildHubRouter(cfg, reg, store, sessions, new AgentRegistry(), security));
    logInfo("bashub listening on %s, api prefix %s", addr.toString, cfg.apiPrefix);
    scheduleArtifactRefresh(cfg, reg, store);
  } catch (Exception e) {
    logError("Start http failed: %s", e.msg);
    return ExitStartupError;
  }
  scope (exit)
    listener.stopListening();

  // 只把未消费的参数交给 vibe，避免它再解析 bashub 自己的选项
  runApplication(&parsedArgs.rest);
  return 0;
}

/// `--check-schema`：不退回内存后端，连接失败或发现漂移都返回非零。
private int runSchemaCheck(HubConfig cfg, Registry reg) {
  if (!cfg.hasDb()) {
    stderr.writeln("bashub: no database configured, cannot check schema");
    return ExitStartupError;
  }
  DbDao dao;
  try {
    dao = new DbDao(cfg.dbUrl);
  } catch (DaoException e) {
    stderr.writeln("bashub: connect database failed: " ~ e.msg);
    return ExitStartupError;
  }

  try {
    auto issues = dao.checkSchema(reg);
    if (issues.length == 0) {
      writeln("schema ok");
      return 0;
    }
    foreach (issue; issues)
      stderr.writeln("schema drift: " ~ issue.toString);
    return ExitSchemaDrift;
  } catch (Exception e) {
    stderr.writeln("bashub: check schema failed: " ~ e.msg);
    return ExitStartupError;
  }
}

/// 正常启动时只记录漂移，不因为多一个待迁移列就拒绝服务。
private void warnSchemaDrift(Dao dao, Registry reg) {
  foreach (issue; dao.checkSchema(reg))
    logWarn("Schema drift: %s", issue.toString);
}

/// 组件版本周期刷新。只在真实数据库后端启用：内存演示数据没有长期维护的意义。
private void scheduleArtifactRefresh(HubConfig cfg, Registry reg, Store store) {
  if (cfg.artifactRefreshMinutes == 0 || store.backend != "postgres")
    return;
  setTimer(cfg.artifactRefreshMinutes.minutes, {
    auto updated = refreshAllArtifactVersions(reg, store, toDelegate(&mavenMetadata));
    if (updated > 0)
      logInfo("Refreshed %s artifact versions", updated);
  }, true);
  logInfo("Artifact version refresh scheduled every %s minutes", cfg.artifactRefreshMinutes);
}

/// 周期任务与手动 `/artifacts/update-version` 使用同一份 metadata 读取规则。
private string mavenMetadata(string url) {
  auto metadata = curlGet(url);
  return metadata.isOk ? cast(string) metadata.body : null;
}

/// 会话仓库：配了 `<ems cas="...">` 就用 CAS 的会话服务（内存缓存 + 心跳定时器），
/// 没配则返回 null，`sessions` 端点退回演示用户。
private SessionRepo createSessionRepo(HubConfig cfg) {
  if (!cfg.hasCas())
    return null;
  auto casConfig = CasConfig.of(cfg.casServer);
  auto repo = new CasSessionRepo(casConfig);
  repo.startHeartbeat(); // 事件循环起来之前建定时器也没问题（vibe 会排队）
  return repo;
}
}

/// 数据库是硬依赖：没有连接串就拒绝启动，连接失败也原样上抛。
///
/// 不再退回内存演示数据——那会把配置错误伪装成「服务已起来」，控制台看到的是假数据，
/// 排查时反而不知道请求到底有没有打到 PostgreSQL。
Dao createDao(HubConfig cfg) {
  if (!cfg.hasDb())
    throw new DaoException("no database configured: set <db url=\"...\"> in bashub.xml "
        ~ "or start with --ems.profile=<profile>");
  return new DbDao(cfg.dbUrl);
}
