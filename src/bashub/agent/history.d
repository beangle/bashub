/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.agent.history;
/// 节点运行历史的持久层。只记录轻量的 `id/state` 采样，不把 OS 与 webapps 快照写进历史表。
///
/// 每个 project 每个采样点一行，`servers` 是 `{server_id: state}` 的 JSONB 对象。这样写入时
/// 不需要为每台 server 生成主键，读取时按 project + 时间范围一次取回整组 server 的状态，
/// SPA 再在本地按 server/天聚合。采样时间以 bashub 收到报文的时刻为准，不信任 agent 的 `at`。

import beangle.data.dao.pq : PGconn, close, exec, open;

import core.time : days;
import vibe.core.log : logWarn;
import vibe.data.json : Json, parseJson;

import std.conv : ConvException, to;
import std.datetime : Clock;
import std.string : strip;

/// 一个 server 的采样状态。
struct AgentSample {
  string id;
  string state;
}

/// 历史存储接口；测试与没有启用数据库的场景可以注入空实现或 null。
interface AgentHistoryStore {
  /// 写入一个 project 的一次快照；同一 project/分钟重复上报会用最新合并结果覆盖。
  void record(string projectId, const(AgentSample)[] samples);

  /// 读取最近 `days` 天的原始采样；返回 `{project, from, to, days, samples:[{at, servers}]}`。
  Json query(string projectId, string projectName, int daysCount);
}

/// PostgreSQL 实现：与 DAO 共用同一个连接串，但独立持有连接，避免历史写入阻塞资源 CRUD。
final class PostgresAgentHistoryStore : AgentHistoryStore {
  private PGconn* db;
  private long lastPurgeDay = -1;

  this(string connInfo) {
    db = open(connInfo);
  }

  ~this() {
    close(db);
  }

  void record(string projectId, const(AgentSample)[] samples) {
    auto pid = projectId.strip;
    if (pid.length == 0 || samples.length == 0)
      return;
    try {
      pid.to!long;
    } catch (ConvException) {
      return;
    }

    auto servers = Json.emptyObject;
    bool[string] seen;
    foreach (sample; samples) {
      auto id = sample.id.strip;
      auto state = sample.state.strip;
      if (id.length == 0 || id.length > 255 || state.length == 0 || state.length > 16)
        continue;
      if (state != "running" && state != "stopped" && state != "error")
        continue;
      if ((id in seen) !is null)
        continue;
      seen[id] = true;
      servers[id] = Json(state);
    }
    if (seen.length == 0)
      return;

    // 同一 project 的多台 agent 会分别触发采样：同一分钟的行用最新合并结果覆盖，
    // 这样每个采样点都是「该 project 所有 server 此刻的状态」。
    exec(db, "insert into bas.mon_server_samples (id, project_id, sampled_at, servers) values "
        ~ "(public.next_id('bas.mon_server_samples'), $1, date_trunc('minute', now()), $2::jsonb) "
        ~ "on conflict (project_id, sampled_at) do update set servers = excluded.servers",
        [pid, servers.toString]);

    // 清理是低频维护，不跟每次采样绑定；按 UTC 日只做一次。失败只记录，不影响本次采样。
    auto today = Clock.currTime().toUnixTime / 86400;
    if (today != lastPurgeDay) {
      try {
        exec(db, "delete from bas.mon_server_samples where sampled_at < now() - interval '180 days'", null);
        lastPurgeDay = today;
      } catch (Exception e) {
        logWarn("agent history purge failed: %s", e.msg);
      }
    }
  }

  Json query(string projectId, string projectName, int daysCount) {
    auto pid = projectId.strip;
    if (pid.length == 0)
      throw new Exception("missing project id");

    auto boundedDays = daysCount < 1 ? 1 : daysCount > 180 ? 180 : daysCount;
    auto sql = "select coalesce(jsonb_agg(jsonb_build_object("
      ~ "'at', to_char(sampled_at, 'YYYY-MM-DD\"T\"HH24:MI:SSTZH:TZM'), "
      ~ "'servers', servers) order by sampled_at), '[]'::jsonb)::text as samples "
      ~ "from bas.mon_server_samples where project_id = $1 "
      ~ "and sampled_at >= now() - ($2 || ' days')::interval";

    auto samples = Json.emptyArray;
    foreach (row; exec(db, sql, [pid, boundedDays.to!string])) {
      auto text = row["samples"].toString;
      if (text.length)
        samples = parseJson(text);
    }

    auto now = Clock.currTime();
    auto since = now - days(cast(long) boundedDays);
    auto doc = Json.emptyObject;
    doc["projectId"] = Json(pid);
    doc["project"] = Json(projectName);
    doc["from"] = Json(since.toISOExtString);
    doc["to"] = Json(now.toISOExtString);
    doc["days"] = Json(cast(long) boundedDays);
    doc["samples"] = samples;
    return doc;
  }
}
