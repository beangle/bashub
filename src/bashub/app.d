/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.app;
/// 进程入口：按 EMS profile 建配置 → 建资源表/Dao → 装路由 → 起 HTTP。
/// 与 Scala 侧的差别在「没有 Spring/Tomcat 容器」：这里一个进程、一个事件循环，
/// 配置只在启动时读一次（没有热加载，见 README 的裁剪清单）。

import beangle.data.dao : Dao, DaoException;
import beangle.data.dao.postgres : DbDao;
import beangle.data.resource : Registry;
import beangle.commons.sysprops : systemVars;
import beangle.ems : emsFromEnvironment;
import beangle.jsonapi.store : Store;
import beangle.security.cas : CasConfig, CasSessionRepo;
import beangle.security.session : SessionRepo;

import bashub.agent.registry : AgentRegistry;
import bashub.agent.history : PostgresAgentHistoryStore;
import beangle.data.query : Query;
import beangle.data.value : jsonGet, jsonText;
import bashub.artifactversion : applyArtifactMetadata, artifactMetadataUrl;
import bashub.config;
import bashub.logging;
import bashub.resources;
import bashub.route;
import bashub.security : HubSecurity;
import bashub.store;

import vibe.core.args : setCommandLineArgs;
import vibe.core.core : runApplication, setTimer, Timer;
import vibe.core.log : logError, logInfo, logWarn;
import vibe.http.server : HTTPListener, HTTPServerSettings, listenHTTP;

import core.atomic : atomicOp;
import core.time : Duration, msecs, minutes;
import std.file : exists, readText, remove, tempDir;
import std.path : buildPath;
import std.process : Pid, spawnProcess, tryWait;
import std.getopt : GetOptException, getopt;
import std.stdio : stderr, writeln;

import vibe.data.json : Json;

/// 启动阶段失败（systemd 据此不重启）。
enum ExitStartupError = 2;
/// `--check-schema` 发现漂移。
enum ExitSchemaDrift = 3;

/// bashub 自己的命令行：EMS 部署选项，以及「不是 bashub 的那些参数」。
struct HubArgs {
  string[string] options;
  bool checkSchema;
  bool help;
  /// 命令行 `--listen`；空表示使用应用文件或内置缺省
  string listen;
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
  getopt(args,
      "check-schema", &parsed.checkSchema,
      "h|help", &parsed.help,
      "listen", &parsed.listen,
      "ems.profile", &emsProfile,
      "ems.home", &emsHome);
  if (emsProfile.length)
    parsed.options["ems.profile"] = emsProfile;
  if (emsHome.length)
    parsed.options["ems.home"] = emsHome;
  parsed.rest = args;
  return parsed;
}

private void printUsage() {
  writeln("Usage: bashub [--ems.home=<dir>] [--ems.profile=<name>]");
  writeln("              [--listen=<host:port>] [--check-schema]");
  writeln();
  writeln("  --check-schema       只检查库表/列是否与资源定义一致，然后退出");
  writeln("  --listen=<host:port> 覆盖应用文件中的监听地址；内置缺省 127.0.0.1:8080");
  writeln("  --ems.home=<dir>     ems 根目录（缺省 ~/.ems），project 在它下面");
  writeln("  --ems.profile=<name> 选择 ems 根目录下的 profile，如 --ems.profile=bas");
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

  // 环境变量 + 命令行部署选项（后者覆盖前者）
  auto ems = emsFromEnvironment(systemVars(parsedArgs.options));
  if (ems is null) {
    stderr.writeln("bashub: specify --ems.profile=<profile> or --ems.home=<dir>");
    return ExitStartupError;
  }

  HubConfig cfg;
  try {
    cfg = loadBashub(ems);
    applyListenOverride(cfg, parsedArgs.listen);
    validateBashubConfig(cfg);
    applyBashubLogging(cfg.logFile, cfg.logLevel);
  } catch (Exception e) {
    stderr.writeln("bashub: " ~ e.msg);
    return ExitStartupError;
  }
  // 部署配置最容易搞混的就是「到底读了哪个 ems」，起服务时留一条
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
    settings.webSocketPayloadMaxLength = 256 * 1024;
    auto sessions = createSessionRepo(cfg);
    HubSecurity security;
    if (cfg.authRequired || sessions !is null) {
      security = new HubSecurity(cfg, sessions);
      if (cfg.authRequired)
        security.warmup();
    }
    auto agentHistory = new PostgresAgentHistoryStore(cfg.dbUrl);
    listener = listenHTTP(settings,
        buildHubRouter(cfg, reg, store, sessions, new AgentRegistry(agentHistory), security));
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
///
/// metadata 交给独立 curl 子进程拉取，事件循环只做「轮询 + 写库」：单个组件最多 30 秒、
/// 上百个组件串行时会把整个服务卡住几十分钟（见 `curlGet` 的同步 `execute`）。
private void scheduleArtifactRefresh(HubConfig cfg, Registry reg, Store store) {
  if (cfg.artifactRefreshMinutes == 0 || store.backend != "postgres")
    return;
  setTimer(cfg.artifactRefreshMinutes.minutes, {
    if (activeRefresh !is null)
      return; // 上一轮还没跑完，跳过这一轮
    activeRefresh = new ArtifactRefreshRunner(reg, store, { activeRefresh = null; });
    activeRefresh.start();
  }, true);
  logInfo("Artifact version refresh scheduled every %s minutes", cfg.artifactRefreshMinutes);
}

/// 异步版本刷新：一次只跑一个 curl（不跟手动刷新抢带宽），每 200ms 回收结果并写库。
private final class ArtifactRefreshRunner {
  private static immutable size_t Concurrency = 1;
  private static immutable Duration PollInterval = 200.msecs;

  private static struct Job {
    string id;
    string bodyPath;
    Pid pid;
    bool done;
  }

  private Registry reg;
  private Store store;
  private void delegate() onDone;
  private string[] ids;
  private string[] urls;
  private Job[] jobs;
  private size_t next;
  private size_t running;
  private size_t updated;
  private Timer ticker;
  private bool ticking;

  this(Registry reg, Store store, void delegate() onDone) {
    this.reg = reg;
    this.store = store;
    this.onDone = onDone;
  }

  void start() {
    auto res = reg.find("artifacts");
    if (res.path.length == 0) {
      finish();
      return;
    }
    Json doc;
    try {
      auto q = Query.init;
      q.pageSize = 0;
      doc = store.search(res, q);
    } catch (Exception e) {
      logWarn("Artifact refresh: list failed: %s", e.msg);
      finish();
      return;
    }
    foreach (ref item; doc["data"]) {
      auto id = jsonText(jsonGet(item, "id"));
      auto attrs = jsonGet(item, "attributes");
      auto groupId = jsonText(jsonGet(attrs, "groupId"));
      auto artifactId = jsonText(jsonGet(attrs, "artifactId"));
      if (id.length == 0 || groupId.length == 0 || artifactId.length == 0)
        continue;
      ids ~= id;
      urls ~= artifactMetadataUrl(groupId, artifactId);
    }
    if (ids.length == 0) {
      finish();
      return;
    }
    ticker = setTimer(PollInterval, &tick, true);
    ticking = true;
    pump();
  }

  private void pump() {
    while (running < Concurrency && next < ids.length) {
      auto bodyPath = nextBodyPath();
      Pid pid;
      try {
        pid = spawnProcess([
          "curl", "--silent", "--show-error", "--fail", "--location",
          "--connect-timeout", "5", "--max-time", "30",
          "--output", bodyPath, urls[next],
        ]);
      } catch (Exception e) {
        logWarn("Artifact refresh: start curl failed: %s", e.msg);
        next++;
        continue;
      }
      jobs ~= Job(ids[next], bodyPath, pid, false);
      running++;
      next++;
    }
  }

  private void tick() {
    foreach (ref job; jobs) {
      if (job.done)
        continue;
      bool terminated;
      int status;
      try {
        auto result = tryWait(job.pid);
        terminated = result.terminated;
        status = result.status;
      } catch (Exception e) {
        logWarn("Artifact refresh: wait failed: %s", e.msg);
        job.done = true;
        running--;
        removeTemp(job.bodyPath);
        continue;
      }
      if (!terminated)
        continue;
      job.done = true;
      running--;
      string xml;
      try {
        if (status == 0 && exists(job.bodyPath))
          xml = readText(job.bodyPath);
      } catch (Exception e) {
        logWarn("Artifact refresh: read %s failed: %s", job.bodyPath, e.msg);
      }
      removeTemp(job.bodyPath);
      if (xml.length == 0)
        continue;
      try {
        if (applyArtifactMetadata(reg, store, job.id, xml))
          updated++;
      } catch (Exception e) {
        logWarn("Artifact refresh: apply %s failed: %s", job.id, e.msg);
      }
    }
    pump();
    if (next >= ids.length && running == 0) {
      logInfo("Refreshed %s artifact versions", updated);
      finish();
    }
  }

  private void finish() {
    if (ticking) {
      ticker.stop();
      ticking = false;
    }
    if (onDone !is null)
      onDone();
  }

  private static void removeTemp(string path) {
    if (!exists(path))
      return;
    try
      remove(path);
    catch (Exception e) {
    }
  }
}

private shared uint refreshSeq;
private __gshared ArtifactRefreshRunner activeRefresh;

private string nextBodyPath() {
  import std.conv : to;
  auto n = atomicOp!"+="(refreshSeq, 1);
  return buildPath(tempDir(), "bashub-versions-" ~ n.to!string ~ ".xml");
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
    throw new DaoException("no database configured: add <datasource name=\"default\"> "
        ~ "to the EMS application file (bas/hub.xml) or resources.xml, "
        ~ "and start with --ems.profile=<profile>");
  return new DbDao(cfg.dbUrl);
}
