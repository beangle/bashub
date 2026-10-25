/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.route;
/// `/api/bashub/{ems,config,micdn,monitor}` 下的路由：hub 自己的端点在这里，
/// 通用 CRUD（`{resource}/search`、`{resource}/{id}`）交给 beangle.jsonapi 的 `JsonApiService`。
///
/// 资源名是路由参数，所以「支持哪些资源」只由 `hubRegistry()` 决定，路由不用跟着改。

import beangle.data.dao : DaoException;
import beangle.data.query : Query, QueryException, parseQuery;
import beangle.jsonapi.document : attributeText, errorDocument, okDocument, unauthorizedDocument;
import beangle.data.resource : Registry, Resource;
import beangle.jsonapi.router : JsonApiService, RouteOptions, collectParams, requireAuth, withFormatSuffix,
  writeJsonApi;
import beangle.jsonapi.store : Store, StoreException;
import beangle.data.value : Row, jsonGet, jsonText, rowGet;
import beangle.commons.net.curl : curlGet;
import beangle.security.session : Session, SessionRepo, nowSeconds;

import bashub.artifactversion : refreshArtifactVersions;
import bashub.agent.channel : bearer;
import bashub.agent.registry : AgentRegistry, AgentSession, RequestOutcome;
import bashub.agent.socket : HealthSchedule, HeartbeatInterval, serveAgentSocket;
import bashub.api : ApiPrefixes, hubApiPrefixes, resourceApiGroup;
import bashub.config : HubConfig;
import bashub.menus : MenuXmlException, exportMenus, importMenus;
import bashub.project.menus : renderEmsMenus;
import bashub.project.manifest : renderSetlineManifest;
import bashub.project.micdnconfig : MicdnConfigException, MicdnProjectView, MicdnState, loadMicdnProject, loadMicdnState,
  micdnProjectDocument, normalizeComponentSpec, plainComponent, renderMicdnXml, saveMicdnProject,
  validateComponentName, validateMountName;
import bashub.project.proxy : renderProxy;
import bashub.project.resolver : ProjectContext, dataOf, findProject, findProjectById, ipHeaderAddresses,
  loadAll, matchHostIp, resolveHostProject, resolveSetlineProject;
import bashub.project.script : renderHostScript;
import bashub.project.server : renderServerXml;
import bashub.project.peers : renderPeers;
import bashub.security : HubSecurity;
import bashub.store : projectKey;

import core.time : seconds;
import vibe.data.json : Json;
import vibe.core.core : sleep;
import vibe.core.path : toNativeString;
import vibe.core.log : logDebug, logError, logWarn;
import vibe.http.common : HTTPStatus;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerRequestHandler, HTTPServerResponse;
import beangle.security.web : SecurityContext, requestOrigin;
import beangle.web.http : withWebAccess;

import std.algorithm : canFind, endsWith, sort;
import std.array : appender, join;
import std.base64 : Base64;
import std.conv : ConvException, to;
import std.file : read;
import std.functional : toDelegate;
import std.string : indexOf, replace, split, startsWith, strip, toLower;

/// `log/follow` 的轮询节拍与窗口。agent 侧仍是普通 `log:read`，SSE 只存在于 hub ↔ 浏览器之间。
private enum int LogFollowIntervalSeconds = 3;
private enum int LogFollowDefaultTail = 200;
private enum long LogFollowMaxTail = 2000;
private enum int LogReadTimeoutSeconds = 5;
/// service:* 可能包含一次 stop（默认等 15s）再加启动与依赖解析，给足两分钟。
private enum int ServiceTimeoutSeconds = 120;
/// 来自 agent 的日志窗口上限；不能信任对端会遵守 basctl 侧的限制。
private enum long MaxAgentLogLines = 2000;
private enum size_t MaxAgentLogLineBytes = 4096;
private enum size_t MaxAgentLogBytes = 256 * 1024;

/// `log:read` 的解包结果；只保留跟随需要的那几个字段。
private struct AgentLogWindow {
  long total;
  long from;
  long to;
  string[] lines;
}

/// `result.data = {total, from, to, lines}`；字段缺失或类型不对就当作坏的 agent 应答。
private bool decodeLogWindow(Json data, out AgentLogWindow window) {
  if (data.type != Json.Type.object)
    return false;
  auto total = data["total"];
  auto from = data["from"];
  auto to = data["to"];
  auto lines = data["lines"];
  if (total.type != Json.Type.int_ || from.type != Json.Type.int_ || to.type != Json.Type.int_
      || lines.type != Json.Type.array)
    return false;

  AgentLogWindow parsed;
  parsed.total = total.get!long;
  parsed.from = from.get!long;
  parsed.to = to.get!long;
  if (parsed.total < 0 || parsed.from < 0 || parsed.to < 0)
    return false;
  if (lines.length > MaxAgentLogLines)
    return false;
  size_t usedBytes;
  foreach (ref item; lines) {
    if (item.type != Json.Type.string)
      return false;
    auto line = item.get!string;
    if (line.length > MaxAgentLogLineBytes)
      return false;
    usedBytes += line.length + 1;
    if (usedBytes > MaxAgentLogBytes)
      return false;
    parsed.lines ~= line;
  }
  window = parsed;
  return true;
}

/// SSE 事件负载；`reset=true` 让客户端替换旧窗口（首次取尾部或日志轮转）。
private Json logPayload(AgentLogWindow window, bool reset) {
  Json[] lines;
  foreach (line; window.lines)
    lines ~= Json(line);
  auto doc = Json.emptyObject;
  doc["total"] = Json(window.total);
  doc["from"] = Json(window.from);
  doc["to"] = Json(window.to);
  doc["lines"] = Json(lines);
  doc["reset"] = Json(reset);
  return doc;
}

/// 写一条 SSE 事件并立刻 flush；模板参数是为了接住 `bodyWriter` 的 `InterfaceProxy`。
private void writeSseEvent(T)(T sink, string event, Json data, long id, bool withId = true) {
  if (withId)
    sink.write("id: " ~ id.to!string ~ "\n");
  sink.write("event: " ~ event ~ "\n");
  sink.write("data: " ~ data.toString ~ "\n\n");
  sink.flush();
}

/// SSE 注释行：浏览器会忽略内容，只用来保活。
private void writeSseComment(T)(T sink, string text) {
  sink.write(": " ~ text ~ "\n\n");
  sink.flush();
}

/// 流内错误：不用 `event: error`，避免和 EventSource 自己的连接错误事件同名。
private void writeSseFailure(T)(T sink, string outcome, string error) {
  auto doc = Json.emptyObject;
  doc["outcome"] = Json(outcome);
  doc["error"] = Json(error);
  writeSseEvent(sink, "failure", doc, 0, false);
}

/** bas hub 自己的端点（不落在通用 CRUD 上的那几个）。 */
class HubService {
  private HubConfig cfg;
  private Registry reg;
  private Store store;
  private RouteOptions opts;
  private ApiPrefixes api;
  private SessionRepo sessions;
  private AgentRegistry agents;
  private HubSecurity security;

  this(HubConfig cfg, Registry reg, Store store, in RouteOptions opts, in ApiPrefixes api,
      SessionRepo sessions = null, AgentRegistry agents = null, HubSecurity security = null) {
    this.cfg = cfg;
    this.reg = reg;
    this.store = store;
    this.opts = opts;
    this.api = api;
    this.sessions = sessions;
    this.agents = agents is null ? new AgentRegistry() : agents;
    this.security = security;
  }

  /// `GET /api/bashub/ems/configs`：登录前就要可读，前端据此知道 ems 地址与 CAS 前缀。
  void configs(HTTPServerRequest req, HTTPServerResponse res) {
    auto doc = Json.emptyObject;
    doc["ems_base"] = Json(cfg.emsBase);
    doc["app_name"] = Json(cfg.appName);
    doc["logoUrl"] = Json(cfg.emsBase ~ "/api/platform/config/domains/logo");
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// `GET /api/bashub/config/{project}/server`：basctl 拉取的 server.xml。
  ///
  /// 机器端点不属于 JSON:API，也不走浏览器登录；Project 名定位记录，`Authorization:
  /// Bearer <project>:<Project.key>` 证明这台机器有权取走配置。不再接受可伪造的 `ip:` 头。
  void projectServer(HTTPServerRequest req, HTTPServerResponse res) {
    auto projectName = req.params.get("project", "");
    ProjectContext project;
    if (!findProject(reg, store, projectName, project)) {
      res.writeBody("", HTTPStatus.notFound);
      return;
    }
    if (!projectTokenAccepted(req, projectName, attributeText(project.data, "key"))) {
      writeConfigUnauthorized(res);
      return;
    }
    try {
      res.headers["Cache-Control"] = "no-store";
      res.writeBody(renderServerXml(store, reg, project, false, cfg.mavenDownloadToken),
          HTTPStatus.ok, "application/xml");
    } catch (Exception e) {
      logError("Render server.xml failed: %s", e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// `GET /api/bashub/config/projects/{id}/server`：管理台查看最终 server.xml。
  ///
  /// 与机器下载端点分开：这里按登录会话鉴权，不要求 Project key，也不接受 `ip:` 头。
  void projectServerView(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    ProjectContext project;
    if (!findProjectById(reg, store, req.params.get("id", ""), project)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no projects with id " ~ req.params.get("id", "")),
          HTTPStatus.notFound);
      return;
    }
    try {
      res.headers["Cache-Control"] = "no-store";
      res.writeBody(renderServerXml(store, reg, project, true, cfg.mavenDownloadToken),
          HTTPStatus.ok, "application/xml");
    } catch (Exception e) {
      logError("Render server.xml failed: %s", e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// `GET /api/bashub/config/{project}/proxy`：按 Project 的 `proxyEngine` 输出 haproxy / nginx。
  /// 机器下载与 `config/server` 使用同一个 Project key；未知引擎与不存在的 Project 一样返回 404。
  void projectProxy(HTTPServerRequest req, HTTPServerResponse res) {
    auto projectName = req.params.get("project", "");
    ProjectContext project;
    if (!findProject(reg, store, projectName, project)) {
      res.writeBody("", HTTPStatus.notFound);
      return;
    }
    if (!projectTokenAccepted(req, projectName, attributeText(project.data, "key"))) {
      writeConfigUnauthorized(res);
      return;
    }
    try {
      auto text = renderProxy(store, reg, project);
      if (text.length == 0) {
        res.writeBody("", HTTPStatus.notFound);
        return;
      }
      res.writeBody(text, HTTPStatus.ok, "text/plain");
    } catch (Exception e) {
      logError("Render proxy config failed: %s", e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// `GET /api/bashub/config/{project}/certificate`：setline 拉取的 PEM 公钥证书。
  void projectCertificate(HTTPServerRequest req, HTTPServerResponse res) {
    writeProjectCertificate(req, res, false);
  }

  /// `GET /api/bashub/config/{project}/certificate-key`：setline 拉取的 PEM 私钥。
  void projectCertificateKey(HTTPServerRequest req, HTTPServerResponse res) {
    writeProjectCertificate(req, res, true);
  }

  private void writeProjectCertificate(HTTPServerRequest req, HTTPServerResponse res, bool privateKey) {
    ProjectContext project;
    auto projectName = req.params.get("project", "");
    if (!findProject(reg, store, projectName, project)) {
      res.writeBody("", HTTPStatus.notFound);
      return;
    }
    if (!projectTokenAccepted(req, projectName, attributeText(project.data, "key"))) {
      writeConfigUnauthorized(res);
      return;
    }

    Row row;
    auto text = "";
    if (store.fetchRaw(reg.find("project-certificates"), project.id, row))
      text = jsonText(rowGet(row, privateKey ? "private_key" : "certificate"));
    res.headers["Cache-Control"] = "no-store";
    res.writeBody(text, HTTPStatus.ok, "application/x-pem-file");
  }

  /// `GET /api/bashub/config/projects/{id}/certificate`：管理台读取公钥与私钥是否已设置。
  void projectCertificateInfo(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    ProjectContext project;
    if (!findProjectById(reg, store, id, project)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no projects with id " ~ id), HTTPStatus.notFound);
      return;
    }
    auto doc = Json.emptyObject;
    doc["certificate"] = Json("");
    doc["keySet"] = Json(false);
    Row row;
    if (store.fetchRaw(reg.find("project-certificates"), project.id, row)) {
      doc["certificate"] = Json(jsonText(rowGet(row, "certificate")));
      doc["keySet"] = Json(jsonText(rowGet(row, "private_key")).length > 0);
    }
    res.headers["Cache-Control"] = "no-store";
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// `PATCH /api/bashub/config/projects/{id}/certificate`：保存 PEM 公钥证书；私钥留空表示保持原值。
  void updateProjectCertificate(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    ProjectContext project;
    if (!findProjectById(reg, store, id, project)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no projects with id " ~ id), HTTPStatus.notFound);
      return;
    }
    auto body = requestJson(req, res);
    if (body.type == Json.Type.undefined)
      return;
    auto certificate = normalizePem(jsonText(jsonGet(body, "certificate")));
    if (certificate.length == 0 || !certificate.canFind("-----BEGIN CERTIFICATE-----")) {
      writeJsonApi(res, errorDocument(400, "证书格式非法", "certificate must be PEM with BEGIN CERTIFICATE",
          "certificate"), HTTPStatus.badRequest);
      return;
    }
    auto privateKey = normalizePem(jsonText(jsonGet(body, "privateKey")));
    if (privateKey.length > 0 && !privateKey.canFind("PRIVATE KEY-----")) {
      writeJsonApi(res, errorDocument(400, "私钥格式非法", "privateKey must be PEM with PRIVATE KEY", "privateKey"),
          HTTPStatus.badRequest);
      return;
    }
    Row values;
    values["certificate"] = Json(certificate);
    if (privateKey.length > 0)
      values["private_key"] = Json(privateKey);
    auto certificates = reg.find("project-certificates");
    store.upsertColumns(certificates, project.id, values);
    Row stored;
    auto doc = Json.emptyObject;
    doc["certificate"] = Json(certificate);
    doc["keySet"] = Json(store.fetchRaw(certificates, project.id, stored)
        && jsonText(rowGet(stored, "private_key")).length > 0);
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// PEM 只保留一份稳定的换行。
  private static string normalizePem(string value) {
    auto text = value.replace("\r\n", "\n").replace("\r", "\n").strip;
    return text.length > 0 && !text.endsWith("\n") ? text ~ "\n" : text;
  }

  /// `GET /api/bashub/config/{project}/setline-peers`：setline 的 peer 列表机器下载端点。
  void projectPeers(HTTPServerRequest req, HTTPServerResponse res) {
    auto projectName = req.params.get("project", "");
    ProjectContext project;
    if (!findProject(reg, store, projectName, project)) {
      res.writeBody("", HTTPStatus.notFound);
      return;
    }
    if (!projectTokenAccepted(req, projectName, attributeText(project.data, "key"))) {
      writeConfigUnauthorized(res);
      return;
    }
    writePeers(res, project, "attachment");
  }

  /// `GET /api/bashub/config/{project}/setline-manifest`：一次请求返回 setline 所需全部资源的 SHA-256。
  /// agent 先比清单，只下载变化项；值与对应下载端点的响应 Body 完全一致。
  void projectManifest(HTTPServerRequest req, HTTPServerResponse res) {
    auto projectName = req.params.get("project", "");
    ProjectContext project;
    if (!findProject(reg, store, projectName, project)) {
      res.writeBody("", HTTPStatus.notFound);
      return;
    }
    if (!projectTokenAccepted(req, projectName, attributeText(project.data, "key"))) {
      writeConfigUnauthorized(res);
      return;
    }

    Row row;
    auto certificate = "";
    auto certificateKey = "";
    if (store.fetchRaw(reg.find("project-certificates"), project.id, row)) {
      certificate = jsonText(rowGet(row, "certificate"));
      certificateKey = jsonText(rowGet(row, "private_key"));
    }
    try {
      auto peers = renderPeers(store, reg, project);
      auto proxy = renderProxy(store, reg, project);
      auto text = renderSetlineManifest(peers, proxy, certificate, certificateKey);
      res.headers["Cache-Control"] = "no-store";
      res.writeBody(text, HTTPStatus.ok, "application/json");
    } catch (Exception e) {
      logError("Render setline manifest failed: %s", e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// `GET /api/bashub/config/projects/{id}/proxy`：管理台查看最终代理配置。
  void projectProxyView(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    ProjectContext project;
    if (!findProjectById(reg, store, req.params.get("id", ""), project)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no projects with id " ~ req.params.get("id", "")),
          HTTPStatus.notFound);
      return;
    }
    try {
      auto text = renderProxy(store, reg, project);
      if (text.length == 0) {
        res.writeBody("", HTTPStatus.notFound);
        return;
      }
      res.headers["Cache-Control"] = "no-store";
      res.writeBody(text, HTTPStatus.ok, "text/plain");
    } catch (Exception e) {
      logError("Render proxy config failed: %s", e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// `GET /api/bashub/config/projects/{id}/setline-peers`：管理台查看 setline peers。
  void projectPeersView(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    ProjectContext project;
    if (!findProjectById(reg, store, req.params.get("id", ""), project)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no projects with id " ~ req.params.get("id", "")),
          HTTPStatus.notFound);
      return;
    }
    writePeers(res, project, "inline");
  }

  /// `GET /api/bashub/ems/{project}/menus/{appName}`：当前 Project 部署应用的资源与菜单 XML。
  void projectEmsMenus(HTTPServerRequest req, HTTPServerResponse res) {
    ProjectContext project;
    string matched;
    if (!resolveHostProject(reg, store, req.params.get("project", ""), req.headers.get("ip", ""),
        project, matched)) {
      res.writeBody("", HTTPStatus.notFound);
      return;
    }
    try {
      auto text = renderEmsMenus(store, reg, project, req.params.get("appName", ""));
      if (text.length == 0) {
        res.writeBody("", HTTPStatus.notFound);
        return;
      }
      res.writeBody(text, HTTPStatus.ok, "application/xml");
    } catch (Exception e) {
      logError("Render ems menus failed: %s", e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// `GET /api/bashub/micdn/{project}/micdn.xml`：micdn 拉取的完整配置。
  ///
  /// 只按 `{org.name}` 找 Project，不再要求 `ip` 头；令牌必须等于 `project.key`。
  /// 同时接受 `X-Micdn-Token`、`Authorization: Bearer` 和 `Authorization: Basic`
  /// （Basic 的用户名或口令任一等于 key，与 micdn 的鉴权约定一致）。
  void projectMicdnXml(HTTPServerRequest req, HTTPServerResponse res) {
    ProjectContext project;
    if (!findProject(reg, store, req.params.get("project", ""), project)
        || !micdnTokenAccepted(req, attributeText(project.data, "key"))) {
      writeMicdnUnauthorized(res);
      return;
    }
    try {
      res.headers["Cache-Control"] = "no-store";
      res.writeBody(renderMicdnXmlForProject(project.id, false, requestOrigin(req)), HTTPStatus.ok,
          "application/xml");
    } catch (Exception e) {
      logError("Render micdn.xml failed: %s", e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// `GET /api/bashub/micdn/projects/{id}`：管理台聚合视图（密钥脱敏）。
  void projectMicdn(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    MicdnProjectView view;
    try {
      if (!loadMicdnProject(store, reg, id, view)) {
        writeJsonApi(res, errorDocument(404, "记录不存在", "no projects with id " ~ id), HTTPStatus.notFound);
        return;
      }
      writeJsonApi(res, micdnProjectDocument(view, projectMicdnUrl(requestOrigin(req),
          jsonText(view.project["qualifiedName"]))), HTTPStatus.ok);
    } catch (Exception e) {
      writeMicdnError(res, e);
    }
  }

  /// `PATCH /api/bashub/micdn/projects/{id}`：一次保存配置与组件绑定。
  void updateProjectMicdn(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    auto body = requestJson(req, res);
    if (body.type == Json.Type.undefined)
      return;
    try {
      saveMicdnProject(store, reg, id, body);
      MicdnProjectView view;
      if (!loadMicdnProject(store, reg, id, view)) {
        writeJsonApi(res, errorDocument(404, "记录不存在", "no projects with id " ~ id), HTTPStatus.notFound);
        return;
      }
      writeJsonApi(res, micdnProjectDocument(view, projectMicdnUrl(requestOrigin(req),
          jsonText(view.project["qualifiedName"]))), HTTPStatus.ok);
    } catch (Exception e) {
      writeMicdnError(res, e);
    }
  }

  /// `GET /api/bashub/micdn/projects/{id}/micdn.xml`：下载真实配置（含密钥）。
  void downloadProjectMicdnXml(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    try {
      auto xml = renderMicdnXmlForProject(id, false, requestOrigin(req));
      if (xml.length == 0) {
        writeJsonApi(res, errorDocument(404, "记录不存在", "no projects with id " ~ id), HTTPStatus.notFound);
        return;
      }
      res.headers["Cache-Control"] = "no-store";
      res.writeBody(xml, HTTPStatus.ok, "application/xml");
    } catch (Exception e) {
      writeMicdnError(res, e);
    }
  }

  /// `GET /api/bashub/micdn/components`：可复用组件目录（bucket key 脱敏）。
  void cdnComponents(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    try {
      Json[] items;
      foreach (ref component; loadAll(store, reg.find("cdn-components")))
        items ~= plainComponent(component);
      items.sort!((a, b) => jsonText(a["name"]) < jsonText(b["name"]));
      auto doc = Json.emptyObject;
      doc["data"] = Json(items);
      writeJsonApi(res, doc, HTTPStatus.ok);
    } catch (Exception e) {
      writeMicdnError(res, e);
    }
  }

  /// `POST /api/bashub/micdn/components`：新建组件。
  void createCdnComponent(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto body = requestJson(req, res);
    if (body.type == Json.Type.undefined)
      return;
    try {
      auto kind = jsonText(jsonGet(body, "kind")).strip.toLower;
      auto name = jsonText(jsonGet(body, "name")).strip;
      auto mountName = jsonText(jsonGet(body, "mountName")).strip;
      validateComponentName(kind, name);
      validateMountName(kind, mountName);
      auto spec = normalizeComponentSpec(kind, jsonGet(body, "spec"));
      Row values;
      values["kind"] = Json(kind);
      values["name"] = Json(name);
      values["mount_name"] = Json(mountName);
      values["remark"] = Json(jsonText(jsonGet(body, "remark")));
      values["spec"] = spec;
      auto id = store.insertColumns(reg.find("cdn-components"), values);
      auto doc = Json.emptyObject;
      doc["data"] = componentById(id);
      writeJsonApi(res, doc, HTTPStatus.created);
    } catch (Exception e) {
      writeMicdnError(res, e);
    }
  }

  /// `PATCH /api/bashub/micdn/components/{id}`：修改组件；bucket key 留空时沿用旧值。
  void updateCdnComponent(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    auto body = requestJson(req, res);
    if (body.type == Json.Type.undefined)
      return;
    try {
      auto resDef = reg.find("cdn-components");
      Json current;
      if (!store.fetch(resDef, id, Query.init, current)) {
        writeJsonApi(res, errorDocument(404, "记录不存在", "no cdn-components with id " ~ id), HTTPStatus.notFound);
        return;
      }
      auto attrs = jsonGet(jsonGet(current, "data"), "attributes");
      auto oldKind = attributeText(current["data"], "kind");
      auto kind = jsonText(jsonGet(body, "kind")).strip.toLower;
      if (kind.length == 0)
        kind = oldKind;
      auto name = jsonText(jsonGet(body, "name")).strip;
      if (name.length == 0)
        name = attributeText(current["data"], "name");
      auto mountName = jsonText(jsonGet(body, "mountName")).strip;
      if (mountName.length == 0)
        mountName = attributeText(current["data"], "mountName");
      validateComponentName(kind, name);
      validateMountName(kind, mountName);

      auto inputSpec = jsonGet(body, "spec");
      if (inputSpec.type == Json.Type.undefined)
        inputSpec = jsonGet(attrs, "spec");
      auto spec = normalizeComponentSpec(kind, inputSpec);
      Row values;
      values["kind"] = Json(kind);
      values["name"] = Json(name);
      values["mount_name"] = Json(mountName);
      if (jsonGet(body, "remark").type != Json.Type.undefined)
        values["remark"] = Json(jsonText(jsonGet(body, "remark")));
      values["spec"] = spec;
      store.updateColumns(resDef, id, values);
      auto doc = Json.emptyObject;
      doc["data"] = componentById(id);
      writeJsonApi(res, doc, HTTPStatus.ok);
    } catch (Exception e) {
      writeMicdnError(res, e);
    }
  }

  /// `DELETE /api/bashub/micdn/components/{id}`：仍被 Project 引用时由外键拒绝。
  void deleteCdnComponent(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    try {
      if (!store.remove(reg.find("cdn-components"), id)) {
        writeJsonApi(res, errorDocument(404, "记录不存在", "no cdn-components with id " ~ id), HTTPStatus.notFound);
        return;
      }
      writeJsonApi(res, okDocument(), HTTPStatus.ok);
    } catch (Exception e) {
      writeMicdnError(res, e);
    }
  }

  /// 机器分发只依赖 Project 是否存在；配置为空时仍输出一份可启动的缺省 micdn.xml。
  private string renderMicdnXmlForProject(string projectId, bool maskSecrets, string origin = "") {
    Json project;
    if (!store.fetch(reg.find("projects"), projectId, Query.init, project))
      return "";
    MicdnState state;
    if (!loadMicdnState(store, reg, projectId, state))
      return "";
    auto data = project["data"];
    auto remoteUrl = origin.length > 0 ? projectMicdnUrl(origin, attributeText(data, "qualifiedName")) : "";
    return renderMicdnXml(state.config, state.components, attributeText(data, "name"),
        attributeText(data, "key"), maskSecrets, remoteUrl);
  }

  private string projectMicdnUrl(string origin, string qualifiedName) {
    return origin ~ api.micdn ~ "/" ~ qualifiedName ~ "/micdn.xml";
  }

  private void writePeers(HTTPServerResponse res, const ProjectContext project, string disposition) {
    try {
      auto text = renderPeers(store, reg, project);
      res.headers["Cache-Control"] = "no-store";
      res.headers["Content-Disposition"] = disposition ~ `; filename="setline-peers.json"`;
      res.writeBody(text, HTTPStatus.ok, "application/json");
    } catch (Exception e) {
      logError("Render setline peers failed: %s", e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// 机器配置下载接受 `Bearer <project>:<Project.key>` 或 Basic（用户名 project、口令 key），
  /// 也兼容旧客户端只发 `<Project.key>`。带 Project 名时同时校验 URL 与凭证绑定关系。
  private bool projectTokenAccepted(HTTPServerRequest req, string projectName, string projectKey) {
    auto expected = projectKey.strip;
    if (expected.length == 0)
      return false;
    auto authorization = req.headers.get("Authorization", "").strip;
    if (authorization.length > 7 && authorization[0 .. 6].toLower == "bearer"
        && authorization[6] == ' ')
      return tokenMatchesProject(authorization[7 .. $], projectName, expected);
    if (authorization.length > 6 && authorization[0 .. 5].toLower == "basic"
        && authorization[5] == ' ') {
      try {
        auto text = cast(string) Base64.decode(authorization[6 .. $].strip);
        auto colon = text.indexOf(':');
        return colon > 0 && tokenEquals(text[0 .. colon], projectName)
            && tokenEquals(text[colon + 1 .. $], expected);
      } catch (Exception)
        return false;
    }
    return false;
  }

  private void writeConfigUnauthorized(HTTPServerResponse res) {
    res.headers["WWW-Authenticate"] = `Bearer realm="basctl"`;
    res.headers["Cache-Control"] = "no-store";
    res.writeBody("config requires Authorization: Bearer <project>:<Project.key> or Basic <project>:<Project.key>",
        HTTPStatus.unauthorized, "text/plain; charset=utf-8");
  }

  private bool micdnTokenAccepted(HTTPServerRequest req, string projectKey) {
    auto expected = projectKey.strip;
    if (expected.length == 0)
      return false;
    if (tokenEquals(req.headers.get("X-Micdn-Token", ""), expected))
      return true;

    auto authorization = req.headers.get("Authorization", "").strip;
    if (authorization.length > 7 && authorization[0 .. 6].toLower == "bearer"
        && authorization[6] == ' ')
      return tokenEquals(authorization[7 .. $], expected);
    if (authorization.length > 6 && authorization[0 .. 5].toLower == "basic"
        && authorization[5] == ' ') {
      try {
        auto text = cast(string) Base64.decode(authorization[6 .. $].strip);
        auto colon = text.indexOf(':');
        if (colon < 0)
          return tokenEquals(text, expected);
        return tokenEquals(text[0 .. colon], expected) || tokenEquals(text[colon + 1 .. $], expected);
      } catch (Exception)
        return false;
    }
    return false;
  }

  private bool tokenEquals(string supplied, string expected) {
    auto actual = supplied.strip;
    if (actual.length != expected.length)
      return false;
    ubyte diff;
    foreach (i; 0 .. actual.length)
      diff |= cast(ubyte)(actual[i] ^ expected[i]);
    return diff == 0;
  }

  private bool tokenMatchesProject(string supplied, string projectName, string expected) {
    auto actual = supplied.strip;
    auto colon = actual.indexOf(':');
    if (colon > 0 && colon + 1 < actual.length)
      return tokenEquals(actual[0 .. colon], projectName)
          && tokenEquals(actual[colon + 1 .. $], expected);
    return tokenEquals(actual, expected);
  }

  private void writeMicdnUnauthorized(HTTPServerResponse res) {
    res.headers["WWW-Authenticate"] = `Basic realm="micdn"`;
    res.headers["Cache-Control"] = "no-store";
    res.writeBody("micdn config requires a token (Authorization: Bearer/Basic or X-Micdn-Token)",
        HTTPStatus.unauthorized, "text/plain; charset=utf-8");
  }

  private Json componentById(string id) {
    Json component;
    if (!store.fetch(reg.find("cdn-components"), id, Query.init, component))
      throw new MicdnConfigException("id", "组件不存在: " ~ id);
    return plainComponent(component["data"]);
  }

  private void writeMicdnError(HTTPServerResponse res, Exception e) {
    if (auto ce = cast(MicdnConfigException) e) {
      if (ce.field == "project") {
        writeJsonApi(res, errorDocument(404, "记录不存在", ce.msg), HTTPStatus.notFound);
        return;
      }
      writeJsonApi(res, errorDocument(400, "Micdn 配置不合法", ce.msg, ce.field), HTTPStatus.badRequest);
      return;
    }
    if (auto de = cast(DaoException) e) {
      if (de.msg.indexOf("duplicate key value violates unique constraint") >= 0) {
        writeJsonApi(res, errorDocument(409, "数据冲突", "名称或挂载名已存在"), HTTPStatus.conflict);
      } else if (de.msg.indexOf("violates foreign key constraint") >= 0) {
        writeJsonApi(res, errorDocument(409, "关联数据冲突", "组件仍被 Project 引用，或 Project 不存在"),
            HTTPStatus.conflict);
      } else {
        logError("Micdn data error: %s", de.msg);
        writeJsonApi(res, errorDocument(500, "数据访问失败", de.msg), HTTPStatus.internalServerError);
      }
      return;
    }
    logError("Micdn config error: %s", e.msg);
    writeJsonApi(res, errorDocument(500, "Micdn 配置处理失败", e.msg), HTTPStatus.internalServerError);
  }

  /// `GET /api/bashub/config/{project}/script/{host}`：按 Host.ip 生成该主机的检查脚本。
  void projectHostScript(HTTPServerRequest req, HTTPServerResponse res) {
    ProjectContext project;
    if (!resolveSetlineProject(reg, store, req.params.get("project", ""), req.headers.get("ip", ""), project)) {
      res.writeBody("", HTTPStatus.notFound);
      return;
    }
    try {
      auto text = renderHostScript(store, reg, project, req.params.get("host", ""));
      if (text.length == 0) {
        res.writeBody("", HTTPStatus.notFound);
        return;
      }
      res.writeBody(text, HTTPStatus.ok, "text/x-shellscript");
    } catch (Exception e) {
      logError("Render host script failed: %s", e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// `GET /api/bashub/monitor/agents/{project}/channel`：basctl 的出站 WebSocket。
  ///
  /// 鉴权在升级前完成：`Authorization: Bearer <project>:<Project.key>` 不对就直接 401，
  /// 也兼容只发 `<Project.key>` 的旧客户端。
  /// 这样未认证的连接拿不到一个字节的协议，也不会在登记册里留下任何痕迹。
  void projectAgents(HTTPServerRequest req, HTTPServerResponse res) {
    auto name = req.params.get("project", "");
    ProjectContext project;
    if (!findProject(reg, store, name, project)) {
      res.writeBody("", HTTPStatus.unauthorized);
      return;
    }

    string supplied;
    auto expected = attributeText(project.data, "key");
    if (expected.length == 0 || !bearer(req.headers.get("Authorization", ""), supplied)
        || !tokenMatchesProject(supplied, name, expected)) {
      res.writeBody("", HTTPStatus.unauthorized);
      return;
    }
    // 身份 = project + agent 上报的服务器 IP：同一 project 的多台机器各占一条连接。
    // 头里可以带多个地址（多网卡）；只接受 project / hosts 里声明过的那个，命中才放行。
    auto reportedIps = ipHeaderAddresses(req.headers.get("ip", ""));
    if (reportedIps.length == 0) {
      writeJsonApi(res, errorDocument(400, "请求参数非法",
          "agent must report a valid ip in the `ip` header; got: " ~ req.headers.get("ip", ""), "ip"),
          HTTPStatus.badRequest);
      return;
    }
    string agentIp;
    if (!matchHostIp(reg, store, project, reportedIps, agentIp)) {
      writeJsonApi(res, errorDocument(403, "来源 IP 未授权",
          "agent ip does not match any host of project " ~ name ~ ": " ~ reportedIps.join(","), "ip"),
          HTTPStatus.forbidden);
      return;
    }
    auto health = HealthSchedule(cfg.agentHealthIntervalSeconds, cfg.agentHealthStartMinute,
        cfg.agentHealthEndMinute);
    auto groupName = req.headers.get("X-Bas-Group", "").strip;
    if (groupName.length == 0)
      groupName = "default_group";
    // 自动组网：agent 都先以候选身份连 hub；组网模式复用 relay 循环。
    auto relay = req.headers.get("X-Bas-Role", "").strip == "relay"
        || req.headers.get("X-Bas-Group", "").length > 0;
    string[] allowed;
    if (relay) {
      Query hq;
      hq.pageSize = 100000;
      hq.addFilter("project", project.id);
      foreach (host; dataOf(store.search(reg.find("hosts"), hq))) {
        auto hostIp = attributeText(host, "ip").strip;
        if (hostIp.length)
          allowed ~= hostIp;
      }
    }
    ushort listenPort = 19080;
    try
      listenPort = attributeText(project.data, "agentListenPort").strip.to!ushort;
    catch (Exception) {
    }
    serveAgentSocket(agents, name, project.id, agentIp, req, res, health,
        HeartbeatInterval, relay, allowed, groupName, listenPort);
  }

  /// `org.name` → 机构展示信息（标题/简称/Logo）；监控卡片用它替掉主机名当大标题。
  private Json[string] organizationIndex() {
    Json[string] index;
    try {
      Query q;
      q.pageSize = 100000;
      foreach (org; dataOf(store.search(reg.find("organizations"), q))) {
        auto name = attributeText(org, "name");
        if (!name.length)
          continue;
        index[name] = Json([
            "name": Json(name),
            "title": Json(attributeText(org, "title")),
            "shortTitle": Json(attributeText(org, "shortTitle")),
            "logoUrl": Json(attributeText(org, "logoUrl")),
          ]);
      }
    } catch (Exception e) {
      // 机构信息只是展示增强，查不到不能把在线状态一起弄挂
      logWarn("Load organizations for agent cards failed: %s", e.msg);
    }
    return index;
  }

  /// 给在线节点补 `org`：project 名是 `org.name`，取第一个 `.` 之前的部分查机构。
  /// 配置里的 webapp 标题索引：agent 只报 context/uri，标题由 bashub 反查，不扩协议。
  private static struct WebappTitles {
    string[string] byContext;
    string[string] byGav;
  }

  /// `gav://group:artifact[:classifier]:version` → `group:artifact`（版本/分类不参与匹配）。
  private static string gavKey(string uri) {
    if (!uri.startsWith("gav://"))
      return "";
    auto parts = uri["gav://".length .. $].split(":");
    return parts.length >= 2 ? parts[0] ~ ":" ~ parts[1] : "";
  }

  private static string normalizeWebappContext(string context) {
    auto value = context.strip;
    if (value.length == 0)
      return "/";
    if (!value.startsWith("/"))
      value = "/" ~ value;
    if (value.length > 1 && value.endsWith("/"))
      value = value[0 .. $ - 1];
    return value;
  }

  /// 读该 project 的 webapp 配置：context / artifact(gav) → artifact.title。
  private WebappTitles webappTitles(string projectId) {
    WebappTitles index;
    Query q;
    q.pageSize = 100000;
    q.addFilter("project", projectId);
    q.includes = ["artifact"];
    auto document = store.search(reg.find("webapps"), q);

    string[string] artifactTitles;
    string[string] artifactGavs;
    foreach (ref item; document["included"]) {
      if (jsonText(item["type"]) != "artifacts")
        continue;
      auto id = jsonText(item["id"]);
      auto attrs = item["attributes"];
      artifactTitles[id] = jsonText(attrs["title"]);
      auto group = jsonText(attrs["groupId"]);
      auto name = jsonText(attrs["artifactId"]);
      if (group.length > 0 && name.length > 0)
        artifactGavs[id] = group ~ ":" ~ name;
    }

    foreach (ref row; document["data"]) {
      if (row.type != Json.Type.object)
        continue;
      auto artifactData = jsonGet(jsonGet(jsonGet(row, "relationships"), "artifact"), "data");
      auto artifactId = artifactData.type == Json.Type.object ? jsonText(artifactData["id"]) : "";
      auto title = "";
      if (auto found = artifactId in artifactTitles)
        title = *found;
      auto context = jsonText(jsonGet(jsonGet(row, "attributes"), "contextPath"));
      if (context.length > 0)
        index.byContext[normalizeWebappContext(context)] = title;
      if (auto gav = artifactId in artifactGavs)
        index.byGav[*gav] = title;
    }
    return index;
  }

  private static string webappTitleOf(const WebappTitles titles, string context, string uri) {
    auto gav = gavKey(uri);
    if (gav.length > 0) {
      if (auto found = gav in titles.byGav) {
        if ((*found).length > 0)
          return *found;
      }
    }
    if (auto found = normalizeWebappContext(context) in titles.byContext)
      return *found;
    return "";
  }

  /// 一组实例里有没有 webapps 数组；运行中的 instances 与声明的 declared 都要看。
  private static bool hasWebappArray(Json items) {
    foreach (ref item; items) {
      if (jsonGet(item, "webapps").type == Json.Type.array)
        return true;
    }
    return false;
  }

  /// 给一组实例的 webapp 补 `title`：先按 gav 反查，再按 context。
  private static void addWebappTitles(Json items, const WebappTitles titles) {
    foreach (ref instance; items) {
      if (instance.type != Json.Type.object)
        continue;
      auto webapps = instance["webapps"];
      if (webapps.type != Json.Type.array)
        continue;
      foreach (ref webapp; webapps) {
        if (webapp.type != Json.Type.object)
          continue;
        auto title = webappTitleOf(titles, jsonText(webapp["context"]), jsonText(webapp["uri"]));
        if (title.length > 0)
          webapp["title"] = Json(title);
      }
    }
  }

  /// 给 agent 上报的每个 webapp 补 `title`（运行中的 instances 与停止的 declared 都补）。
  private Json withWebappTitles(Json agentsJson) {
    WebappTitles[string] cache;
    foreach (ref item; agentsJson) {
      if (item.type != Json.Type.object)
        continue;
      auto report = item["basReport"];
      if (report.type != Json.Type.object)
        continue;
      auto instances = jsonGet(report, "instances");
      auto declared = jsonGet(report, "declared");
      if (!hasWebappArray(instances) && !hasWebappArray(declared))
        continue;
      auto projectId = jsonText(item["projectId"]);
      if (projectId.length == 0)
        continue;
      if (projectId !in cache)
        cache[projectId] = webappTitles(projectId);
      auto titles = projectId in cache;
      addWebappTitles(instances, *titles);
      addWebappTitles(declared, *titles);
    }
    return agentsJson;
  }

  /// 监控卡片的大标题用 project 的说明（title）；机构信息只留给 Logo。
  private Json withProjectInfo(Json agentsJson) {
    auto index = organizationIndex();
    string[string] titles;
    foreach (ref item; agentsJson) {
      auto projectName = jsonText(item["project"]);
      auto dot = projectName.indexOf('.');
      auto orgName = dot > 0 ? projectName[0 .. dot] : "";
      if (auto found = orgName in index)
        item["org"] = *found;
      auto projectId = jsonText(item["projectId"]);
      if (projectId.length == 0)
        continue;
      if (projectId !in titles) {
        ProjectContext context;
        titles[projectId] = findProjectById(reg, store, projectId, context)
            ? attributeText(context.data, "title") : "";
      }
      auto title = projectId in titles;
      if ((*title).length > 0)
        item["projectTitle"] = Json(*title);
    }
    return agentsJson;
  }

  /// `GET /api/bashub/monitor/agents/status`：在线节点现状，只在线的、只留最近一次。
  void agentStatus(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto doc = Json.emptyObject;
    doc["agents"] = withWebappTitles(withProjectInfo(agents.status));
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// `GET /api/bashub/monitor/agents/summary`：在线列表轻量摘要，不返回 OS 与 webapps。
  void agentSummary(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto doc = Json.emptyObject;
    doc["agents"] = withProjectInfo(agents.summary);
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// `GET /api/bashub/monitor/agents/{project}/history?days=180`
  /// 一次返回 project 的原始运行采样；按 server/天聚合与单 server 视图都在 SPA 本地完成。
  void agentHistory(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;

    long daysCount;
    if (!queryLong(req, "days", daysCount) || daysCount < 1 || daysCount > 180) {
      writeJsonApi(res, errorDocument(400, "请求参数非法", "days must be between 1 and 180", "days"),
          HTTPStatus.badRequest);
      return;
    }
    auto projectName = req.params.get("project", "");
    ProjectContext project;
    if (!findProject(reg, store, projectName, project)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no project with name " ~ projectName),
          HTTPStatus.notFound);
      return;
    }
    if (!agents.hasHistory) {
      writeJsonApi(res, errorDocument(503, "运行历史不可用", "agent history is not configured"),
          HTTPStatus.serviceUnavailable);
      return;
    }
    try {
      writeJsonApi(res, agents.history(project.id, projectName, cast(int) daysCount), HTTPStatus.ok);
    } catch (Exception e) {
      logError("Query agent history failed: %s", e.msg);
      writeJsonApi(res, errorDocument(500, "运行历史查询失败", e.msg), HTTPStatus.internalServerError);
    }
  }

  /**
   * 选一台在线 agent：`?agent=<ip>` 精确指定；只有一台时省略即可；多台且没指定返回 409。
   *
   * 返回 null 时响应已经写好（404 离线 / 409 需要指定）。
   */
  private AgentSession pickAgent(HTTPServerRequest req, HTTPServerResponse res, string project) {
    auto ip = req.query.get("agent", "").strip;
    if (ip.length) {
      auto session = agents.find(project, ip);
      if (session is null)
        writeJsonApi(res, errorDocument(404, "节点不在线", "agent offline: " ~ project ~ "@" ~ ip),
            HTTPStatus.notFound);
      return session;
    }
    auto sessions = agents.sessionsOf(project);
    if (sessions.length == 0) {
      writeJsonApi(res, errorDocument(404, "节点不在线", "agent offline: " ~ project), HTTPStatus.notFound);
      return null;
    }
    if (sessions.length == 1)
      return sessions[0];
    string[] ips;
    foreach (session; sessions)
      ips ~= session.ip;
    writeJsonApi(res, errorDocument(409, "请指定 agent",
        "multiple agents online for " ~ project ~ " (" ~ ips.join(",") ~ "); pass ?agent=<ip>", "agent"),
        HTTPStatus.conflict);
    return null;
  }

  /// 配置资源写入后，让在线 agent 重新拉 server.xml。
  void configChanged() {
    agents.refreshConfigAll();
  }

  /// `POST /api/bashub/monitor/agents/{project}/report`：要求在线 agent 立即刷新配置并上报。
  ///
  /// `report:now` 没有 body 回执，真正的 `report:os` / `report:bas` 会随后到达并覆盖快照；
  /// 因此这里只表示「指令已入队」，返回 202。
  void agentReportNow(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;

    auto project = req.params.get("project", "");
    auto session = pickAgent(req, res, project);
    if (session is null)
      return;
    if (!session.supportsPrimitive("config:refresh") && !session.supportsPrimitive("report:now")) {
      writeJsonApi(res, errorDocument(409, "节点不支持该指令", "unsupported:config:refresh"),
          HTTPStatus.conflict);
      return;
    }
    agents.reportNow(project, session.ip);
    writeJsonApi(res, okDocument(), HTTPStatus.accepted);
  }

  /// `POST /api/bashub/monitor/agents/{project}/service/{action}`：对在线节点上的实例执行启停。
  ///
  /// body 只有 `{"instance":"farm.server"}`，`action` 取 `start` / `stop` / `restart`。
  /// agent 按 `hello.supports` 的能力协商接收，动作完成后以 `result` 回执快照里的
  /// `{state, pid?}`；hub 等到回执再返回，不把「已入队」伪装成「已执行」。
  void agentService(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;

    auto action = req.params.get("action", "");
    if (action != "start" && action != "stop" && action != "restart") {
      writeJsonApi(res, errorDocument(400, "请求参数非法",
          "action must be start, stop or restart: " ~ action, "action"), HTTPStatus.badRequest);
      return;
    }

    auto body = requestJson(req, res);
    if (body.type == Json.Type.undefined)
      return;
    auto instance = jsonText(jsonGet(body, "instance")).strip;
    if (!plainName(instance)) {
      writeJsonApi(res, errorDocument(400, "请求参数非法",
          "instance must be a plain name: " ~ instance, "instance"), HTTPStatus.badRequest);
      return;
    }

    auto project = req.params.get("project", "");
    auto session = pickAgent(req, res, project);
    if (session is null)
      return;
    auto reply = agents.service(project, action, instance, ServiceTimeoutSeconds.seconds, session.ip);
    final switch (reply.outcome) {
    case RequestOutcome.ok: {
      auto doc = Json.emptyObject;
      doc["data"] = reply.data.type == Json.Type.object ? reply.data : Json.emptyObject;
      writeJsonApi(res, doc, HTTPStatus.ok);
      break;
    }
    case RequestOutcome.offline:
      writeJsonApi(res, errorDocument(404, "节点不在线", reply.error), HTTPStatus.notFound);
      break;
    case RequestOutcome.timeout:
      writeJsonApi(res, errorDocument(504, "节点应答超时", reply.error), HTTPStatus.gatewayTimeout);
      break;
    case RequestOutcome.failed:
      if (reply.error.startsWith("unsupported:"))
        writeJsonApi(res, errorDocument(409, "节点不支持该指令", reply.error), HTTPStatus.conflict);
      else if (reply.error.startsWith("bad-request"))
        writeJsonApi(res, errorDocument(400, "请求参数非法", reply.error), HTTPStatus.badRequest);
      else
        writeJsonApi(res, errorDocument(502, "节点应答失败", reply.error, null, serviceFailureMeta(reply.data)),
            HTTPStatus.badGateway);
      break;
    }
  }

  /// agent 返回的限长排错字段原样挂在 `errors[0].meta`，不把它们拼进 `detail`。
  private Json serviceFailureMeta(Json data) {
    auto meta = Json.emptyObject;
    if (data.type != Json.Type.object)
      return meta;
    foreach (name; ["detail", "logTail", "truncated"]) {
      auto value = data[name];
      if (value.type != Json.Type.undefined)
        meta[name] = value;
    }
    return meta;
  }

  /// `GET /api/bashub/monitor/agents/{project}/log`：向在线 agent 下发 `log:read` 并等待 `result`。
  void agentLog(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;

    auto instance = req.query.get("instance", "").strip;
    if (!plainName(instance)) {
      writeJsonApi(res, errorDocument(400, "请求参数非法", "instance must be a plain name: " ~ instance, "instance"),
          HTTPStatus.badRequest);
      return;
    }

    long from;
    long to;
    long tail;
    if (!queryLong(req, "from", from) || !queryLong(req, "to", to) || !queryLong(req, "tail", tail)
        || tail < 0) {
      writeJsonApi(res, errorDocument(400, "请求参数非法", "from/to/tail must be integers and tail >= 0"),
          HTTPStatus.badRequest);
      return;
    }

    auto project = req.params.get("project", "");
    auto session = pickAgent(req, res, project);
    if (session is null)
      return;
    auto reply = agents.logRead(project, instance, from, to, 5.seconds, tail, session.ip);
    final switch (reply.outcome) {
    case RequestOutcome.ok:
      writeJsonApi(res, reply.data, HTTPStatus.ok);
      break;
    case RequestOutcome.offline:
      writeJsonApi(res, errorDocument(404, "节点不在线", reply.error), HTTPStatus.notFound);
      break;
    case RequestOutcome.timeout:
      writeJsonApi(res, errorDocument(504, "节点应答超时", reply.error), HTTPStatus.gatewayTimeout);
      break;
    case RequestOutcome.failed:
      writeJsonApi(res, errorDocument(502, "节点应答失败", reply.error), HTTPStatus.badGateway);
      break;
    }
  }

  /// `GET /api/bashub/monitor/agents/{project}/agent-log`：读取 agent 自身 console 日志。
  void agentOwnLog(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;

    long from;
    long to;
    long tail;
    if (!queryLong(req, "from", from) || !queryLong(req, "to", to) || !queryLong(req, "tail", tail)
        || tail < 0) {
      writeJsonApi(res, errorDocument(400, "请求参数非法", "from/to/tail must be integers and tail >= 0"),
          HTTPStatus.badRequest);
      return;
    }

    auto project = req.params.get("project", "");
    auto session = pickAgent(req, res, project);
    if (session is null)
      return;
    auto reply = agents.agentLog(project, from, to, 5.seconds, tail, session.ip);
    final switch (reply.outcome) {
    case RequestOutcome.ok:
      writeJsonApi(res, reply.data, HTTPStatus.ok);
      break;
    case RequestOutcome.offline:
      writeJsonApi(res, errorDocument(404, "节点不在线", reply.error), HTTPStatus.notFound);
      break;
    case RequestOutcome.timeout:
      writeJsonApi(res, errorDocument(504, "节点应答超时", reply.error), HTTPStatus.gatewayTimeout);
      break;
    case RequestOutcome.failed:
      if (reply.error.startsWith("unsupported:"))
        writeJsonApi(res, errorDocument(409, "节点不支持该指令", reply.error), HTTPStatus.conflict);
      else
        writeJsonApi(res, errorDocument(502, "节点应答失败", reply.error), HTTPStatus.badGateway);
      break;
    }
  }

  /// `GET /api/bashub/monitor/agents/{project}/log/follow`：以 SSE 持续跟随实例日志。
  ///
  /// hub 仍按 `log:read` 的区间语义向 agent 拉取：首次取 `tail`，之后从 `上次 to + 1`
  /// 继续；检测到 `total` 回退就重新取尾部并下发 `reset=true`。对浏览器保持一条
  /// `text/event-stream`，每 3 秒轮询一次，空闲时发注释行保活。客户端断开后写流会报错，
  /// 这里直接结束循环，不留后台任务。
  void agentLogFollow(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;

    auto instance = req.query.get("instance", "").strip;
    if (!plainName(instance)) {
      writeJsonApi(res, errorDocument(400, "请求参数非法", "instance must be a plain name: " ~ instance, "instance"),
          HTTPStatus.badRequest);
      return;
    }

    long from;
    long tail;
    if (!queryLong(req, "from", from) || !queryLong(req, "tail", tail) || from < 0 || tail < 0) {
      writeJsonApi(res, errorDocument(400, "请求参数非法", "from/tail must be integers and >= 0"),
          HTTPStatus.badRequest);
      return;
    }

    auto project = req.params.get("project", "");
    auto session = pickAgent(req, res, project);
    if (session is null)
      return;
    if (!session.supportsPrimitive("log:read")) {
      writeJsonApi(res, errorDocument(409, "节点不支持该指令", "unsupported:log:read"), HTTPStatus.conflict);
      return;
    }

    long cursor = from;
    bool resumed;
    auto lastEventId = req.headers.get("Last-Event-ID", "").strip;
    if (lastEventId.length > 0) {
      try {
        auto eventId = lastEventId.to!long;
        if (eventId >= 0) {
          cursor = eventId + 1;
          resumed = true;
        }
      } catch (ConvException) {
        // 坏的重连头当作首次连接，重新取尾部。
      }
    }

    long tailWindow;
    if (cursor <= 0) {
      tailWindow = tail > 0 ? tail : LogFollowDefaultTail;
      if (tailWindow > LogFollowMaxTail)
        tailWindow = LogFollowMaxTail;
    }
    bool reset = !resumed;

    res.headers["Content-Type"] = "text/event-stream; charset=UTF-8";
    res.headers["Cache-Control"] = "no-cache";
    res.headers["X-Accel-Buffering"] = "no";
    auto sink = res.bodyWriter;

    try {
      sink.write("retry: " ~ (LogFollowIntervalSeconds * 1000).to!string ~ "\n\n");
      writeSseComment(sink, "connected");

      bool first = true;
      long lastTotal = -1;
      while (true) {
        if (!first && !res.connected)
          break;

        auto reply = agents.logRead(project, instance, cursor, 0, LogReadTimeoutSeconds.seconds,
            tailWindow, session.ip);
        if (reply.outcome != RequestOutcome.ok) {
          final switch (reply.outcome) {
          case RequestOutcome.offline:
            writeSseFailure(sink, "offline", reply.error);
            break;
          case RequestOutcome.timeout:
            writeSseFailure(sink, "timeout", reply.error);
            break;
          case RequestOutcome.failed:
            writeSseFailure(sink, "failed", reply.error);
            break;
          case RequestOutcome.ok:
            break;
          }
          break;
        }

        AgentLogWindow window;
        if (!decodeLogWindow(reply.data, window)) {
          writeSseFailure(sink, "bad-result", "agent returned a malformed log window");
          break;
        }

        // total 回退或游标越过文件尾：旧行号已经失效，重新取尾部。下一轮立即读。
        // 重连时 `Last-Event-ID` 可能来自轮转前的旧文件，所以第一轮也要做游标检查。
        bool rotated = cursor > window.total + 1 || (lastTotal >= 0 && window.total < lastTotal);
        if ((!first || resumed) && rotated) {
          cursor = 0;
          tailWindow = LogFollowDefaultTail;
          reset = true;
          lastTotal = -1;
          continue;
        }

        bool changed = (first && !resumed) || reset || window.lines.length > 0
            || (lastTotal >= 0 && window.total != lastTotal);
        if (changed)
          writeSseEvent(sink, "lines", logPayload(window, reset), window.to);
        else
          writeSseComment(sink, "keepalive");
        cursor = window.to + 1;
        if (cursor < 1)
          cursor = 1;
        lastTotal = window.total;
        reset = false;
        tailWindow = 0;
        first = false;

        if (!res.connected)
          break;
        sleep(LogFollowIntervalSeconds.seconds);
      }
    } catch (Exception e) {
      if (res.connected)
        logDebug("log follow %s/%s stopped: %s", project, instance, e.msg);
    }
  }

  /** `GET /api/bashub/ems/sessions`：当前登录用户。
   *
   * 配了 CAS 就从会话 cookie 里取会话（顺带 `access` 一次：续期、判过期）；
   * 没有会话且要鉴权就 401（前端据此跳 CAS），否则给演示用户——见 README 的裁剪清单。
   */
  void currentSession(HTTPServerRequest req, HTTPServerResponse res) {
    SecurityContext context;
    if (security !is null)
      context = security.contextOf(req);
    auto session = security !is null ? context.session : sessionOf(req);
    if (session is null) {
      if (opts.authRequired) {
        if (security !is null)
          security.writeUnauthenticated(req, res);
        else
          writeJsonApi(res, unauthorizedDocument(opts.loginRedirectUrl), HTTPStatus.unauthorized);
        return;
      }
      auto demo = Json.emptyObject;
      demo["code"] = Json("demo");
      demo["name"] = Json("演示用户");
      writeJsonApi(res, demo, HTTPStatus.ok);
      return;
    }
    auto doc = Json.emptyObject;
    doc["code"] = Json(session.principal.name);
    doc["name"] = Json(session.principal.description);
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// `POST /api/bashub/ems/sessions/logout`：只清本地缓存（scala `SessionWS.logout` 也只 evict，
  /// 不 expire——CAS 那边的会话让它自己按 tti 过期），再让前端去 CAS 登出。
  void logout(HTTPServerRequest req, HTTPServerResponse res) {
    auto doc = Json.emptyObject;
    if (security !is null) {
      doc["logoutUrl"] = Json(security.logout(req, res));
    } else {
      if (sessions !is null) {
        auto sid = sessionIdOf(req);
        if (sid.length > 0)
          sessions.evict(sid);
      }
      doc["logoutUrl"] = Json(cfg.emsBase ~ "/cas/logout");
    }
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// 请求里的会话：从 cookie 取 sid 并 `access` 一次（续期、过期则作废）。
  private Session sessionOf(HTTPServerRequest req) {
    if (sessions is null)
      return null;
    auto sid = sessionIdOf(req);
    if (sid.length == 0)
      return null;
    return sessions.access(sid, nowSeconds());
  }

  private string sessionIdOf(HTTPServerRequest req) {
    return req.cookies.get(cfg.sessionIdName, "");
  }

  private Json requestJson(HTTPServerRequest req, HTTPServerResponse res) {
    Json body;
    try {
      body = req.json;
    } catch (Exception e) {
      body = Json.undefined;
    }
    if (body.type == Json.Type.undefined || body.type == Json.Type.null_) {
      writeJsonApi(res, errorDocument(400, "请求体缺失或非法", "expect a JSON object"), HTTPStatus.badRequest);
      return Json.undefined;
    }
    return body;
  }

  /// `{"ids":["1","2"]}`；非数组返回 null，由调用方转 400。
  private string[] bodyIds(Json body) {
    auto ids = jsonGet(body, "ids");
    if (ids.type != Json.Type.array)
      return null;
    string[] result;
    foreach (ref item; ids) {
      auto id = jsonText(item);
      if (id.length > 0)
        result ~= id;
    }
    return result;
  }

  /** `POST /api/bashub/config/projects/{id}/reset-key`：重置通道凭证。
   *
   * 重置即**吊销**：机器丢了、人走了、配置外泄了，换一个 key 就作废，旧 key 的连接下次握手
   * 就被拒（已经在线的连接要等它自己重连）。返回新 key，前端直接显示给操作者去更新那台机器。
   * 对应 Scala 侧 `ProjectWS.resetKey`。
   */
  void resetKey(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    auto key = projectKey();
    Row values;
    values["key"] = Json(key);
    if (!store.updateColumns(reg.find("projects"), id, values)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no projects with id " ~ id), HTTPStatus.notFound);
      return;
    }
    ProjectContext project;
    if (findProjectById(reg, store, id, project))
      agents.supersede(attributeText(project.data, "qualifiedName"));
    // 与 Scala 侧同形：扁平的 `{id, key}`，不是 JSON:API 文档
    auto doc = Json.emptyObject;
    doc["id"] = Json(id);
    doc["key"] = Json(key);
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// `POST /api/bashub/config/webapps/upgrade`：把选中的应用版本提到组件的 `latestVersion`。
  void upgradeWebapps(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto body = requestJson(req, res);
    if (body.type == Json.Type.undefined)
      return;
    auto ids = bodyIds(body);
    if (ids is null) {
      writeJsonApi(res, errorDocument(400, "请求数据非法", "expect {\"ids\":[...]}", "ids"), HTTPStatus.badRequest);
      return;
    }

    auto webapps = reg.find("webapps");
    auto artifacts = reg.find("artifacts");
    foreach (id; ids) {
      Json webapp;
      if (!store.fetch(webapps, id, Query.init, webapp))
        continue;
      auto relationship = jsonGet(webapp["data"], "relationships");
      auto artifactData = jsonGet(jsonGet(relationship, "artifact"), "data");
      auto artifactId = jsonText(jsonGet(artifactData, "id"));
      if (artifactId.length == 0)
        continue;
      Json artifact;
      if (!store.fetch(artifacts, artifactId, Query.init, artifact))
        continue;
      auto latest = jsonText(jsonGet(artifact["data"]["attributes"], "latestVersion"));
      if (latest.length == 0)
        continue;
      Row values;
      values["version"] = Json(latest);
      store.updateColumns(webapps, id, values);
    }
    writeJsonApi(res, okDocument(), HTTPStatus.ok);
  }

  /// `GET /api/bashub/config/hosts/{id}/webapps`：部署到该主机上运行的应用。
  ///
  /// webapp 经 `targets` 指向 server，server 才指向 host；现有查询计划没有 to-many 过滤，
  /// 所以这里先取一页足够大的 webapp，再按 target.host 过滤。控制台的数据量很小。
  void hostWebapps(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    Json host;
    if (!store.fetch(reg.find("hosts"), id, Query.init, host)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no hosts with id " ~ id), HTTPStatus.notFound);
      return;
    }

    auto q = parseQuery(collectParams(req));
    q.pageSize = 100000;
    auto doc = store.search(reg.find("webapps"), q);
    auto filtered = appender!(Json[])();
    auto servers = reg.find("servers");
    foreach (ref webapp; doc["data"]) {
      auto targets = jsonGet(jsonGet(jsonGet(webapp, "relationships"), "targets"), "data");
      if (targets.type != Json.Type.array)
        continue;
      bool deployed = false;
      foreach (ref target; targets) {
        Json server;
        auto serverId = jsonText(jsonGet(target, "id"));
        if (!store.fetch(servers, serverId, Query.init, server))
          continue;
        auto serverRelationships = jsonGet(server["data"], "relationships");
        auto serverHostData = jsonGet(jsonGet(serverRelationships, "host"), "data");
        auto serverHost = jsonText(jsonGet(serverHostData, "id"));
        if (serverHost == id) {
          deployed = true;
          break;
        }
      }
      if (deployed)
        filtered.put(webapp);
    }
    doc["data"] = Json(filtered.data);
    doc["meta"]["page"]["number"] = Json(1L);
    doc["meta"]["page"]["size"] = Json(cast(long) filtered.data.length);
    doc["meta"]["page"]["total"] = Json(cast(long) filtered.data.length);
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// `GET /api/bashub/config/artifacts/{id}/webapps`：使用该组件部署的应用（原 `ArtifactAction.info`）。
  ///
  /// webapp 到 artifact 是 to-one 关系，直接走查询计划的关系过滤，分页/排序/其他过滤条件都保留。
  void artifactWebapps(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    Json artifact;
    if (!store.fetch(reg.find("artifacts"), id, Query.init, artifact)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no artifacts with id " ~ id), HTTPStatus.notFound);
      return;
    }

    auto q = parseQuery(collectParams(req));
    q.addFilter("artifact", id);
    auto doc = store.search(reg.find("webapps"), q);
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// `GET /api/bashub/ems/resources/{id}/menus`：引用该资源的菜单（原 `ResourceAction.info`）。
  ///
  /// `menus.resources` 是多对多，当前查询计划不做 to-many 过滤；控制台菜单量小，
  /// 先取全量再由关系行过滤。返回的是本次匹配的完整集合，`meta.page` 同步改为总数。
  void resourceMenus(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    Json resource;
    if (!store.fetch(reg.find("resources"), id, Query.init, resource)) {
      writeJsonApi(res, errorDocument(404, "记录不存在", "no resources with id " ~ id), HTTPStatus.notFound);
      return;
    }

    auto q = parseQuery(collectParams(req));
    q.pageNumber = 1;
    q.pageSize = 100000;
    auto doc = store.search(reg.find("menus"), q);
    auto filtered = appender!(Json[])();
    foreach (ref menu; doc["data"]) {
      auto resources = jsonGet(jsonGet(jsonGet(menu, "relationships"), "resources"), "data");
      if (resources.type != Json.Type.array)
        continue;
      foreach (ref used; resources) {
        if (jsonText(jsonGet(used, "id")) == id) {
          filtered.put(menu);
          break;
        }
      }
    }
    doc["data"] = Json(filtered.data);
    doc["meta"]["page"]["number"] = Json(1L);
    doc["meta"]["page"]["size"] = Json(cast(long) filtered.data.length);
    doc["meta"]["page"]["total"] = Json(cast(long) filtered.data.length);
    writeJsonApi(res, doc, HTTPStatus.ok);
  }

  /// `POST /api/bashub/config/artifacts/update-version`：从 Maven Central 刷新所选组件的最新版本。
  void updateArtifactVersions(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto body = requestJson(req, res);
    if (body.type == Json.Type.undefined)
      return;
    auto ids = bodyIds(body);
    if (ids is null) {
      writeJsonApi(res, errorDocument(400, "请求数据非法", "expect {\"ids\":[...]}", "ids"), HTTPStatus.badRequest);
      return;
    }

    refreshArtifactVersions(reg, store, ids, toDelegate(&mavenMetadata));
    writeJsonApi(res, okDocument(), HTTPStatus.ok);
  }

  /// `GET /api/bashub/ems/menus/export?app={id}`：导出应用的资源与菜单为 XML。
  void exportMenusXml(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    try {
      auto appId = req.query.get("app", "");
      writeJsonApi(res, exportMenus(reg, store, appId), HTTPStatus.ok);
    } catch (MenuXmlException e) {
      writeMenuError(res, e);
    } catch (Exception e) {
      writeJsonApi(res, errorDocument(400, "菜单导出失败", e.msg), HTTPStatus.badRequest);
    }
  }

  /// `POST /api/bashub/ems/menus/import`：multipart 字段 `app` + `menufile`。
  void importMenusXml(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    try {
      auto appId = req.form.get("app", "");
      auto file = "menufile" in req.files;
      if (file is null) {
        writeJsonApi(res, errorDocument(400, "菜单导入失败", "没有发现上传的菜单xml文件"),
            HTTPStatus.badRequest);
        return;
      }
      auto xml = cast(string) read(file.tempPath.toNativeString);
      importMenus(reg, store, appId, xml);
      writeJsonApi(res, okDocument(), HTTPStatus.ok);
    } catch (MenuXmlException e) {
      writeMenuError(res, e);
    } catch (Exception e) {
      writeJsonApi(res, errorDocument(400, "菜单导入失败", e.msg), HTTPStatus.badRequest);
    }
  }

  private void writeMenuError(HTTPServerResponse res, MenuXmlException e) {
    auto status = e.status == 404 ? HTTPStatus.notFound : HTTPStatus.badRequest;
    auto title = e.status == 404 ? "记录不存在" : "菜单数据非法";
    writeJsonApi(res, errorDocument(e.status, title, e.msg), status);
  }

  /// `POST /api/bashub/ems/menus`：菜单保存后按 `indexno` 请求值重排同级节点。
  void createMenu(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto body = requestJson(req, res);
    if (body.type == Json.Type.undefined)
      return;
    try {
      auto position = menuPosition(body, 0);
      setMenuIndex(body, "1");
      linkMenuEntry(body);
      auto doc = store.create(reg.find("menus"), body);
      auto id = jsonText(jsonGet(jsonGet(doc, "data"), "id"));
      moveMenu(id, position);
      Json saved;
      if (!store.fetch(reg.find("menus"), id, Query.init, saved))
        throw new StoreException(null, "created menu cannot be read back: " ~ id);
      writeJsonApi(res, saved, HTTPStatus.created);
    } catch (Exception e) {
      writeHubWriteError(res, e);
    }
  }

  /// `PATCH /api/bashub/ems/menus/{id}`：只有请求里带 `indexno` 时才调整位置。
  void updateMenu(HTTPServerRequest req, HTTPServerResponse res) {
    if (!requireAuth(req, res, opts))
      return;
    auto id = req.params.get("id", "");
    auto body = requestJson(req, res);
    if (body.type == Json.Type.undefined)
      return;
    try {
      Json existing;
      if (!store.fetch(reg.find("menus"), id, Query.init, existing)) {
        writeJsonApi(res, errorDocument(404, "记录不存在", "no menus with id " ~ id), HTTPStatus.notFound);
        return;
      }
      auto position = hasMenuPosition(body) ? menuPosition(body, 0) : -1;
      if (position > 0)
        setMenuIndex(body, "1");
      linkMenuEntry(body);
      Json updated;
      if (!store.update(reg.find("menus"), id, body, updated)) {
        writeJsonApi(res, errorDocument(404, "记录不存在", "no menus with id " ~ id), HTTPStatus.notFound);
        return;
      }
      if (position > 0)
        moveMenu(id, position);
      else
        propagateDisabled(reg.find("menus"), id);
      Json saved;
      if (!store.fetch(reg.find("menus"), id, Query.init, saved))
        throw new StoreException(null, "updated menu cannot be read back: " ~ id);
      writeJsonApi(res, saved, HTTPStatus.ok);
    } catch (Exception e) {
      writeHubWriteError(res, e);
    }
  }

  private void writeHubWriteError(HTTPServerResponse res, Exception e) {
    if (auto se = cast(StoreException) e) {
      writeJsonApi(res, errorDocument(400, "请求数据非法", se.msg, se.attribute), HTTPStatus.badRequest);
      return;
    }
    if (auto qe = cast(QueryException) e) {
      writeJsonApi(res, errorDocument(400, "查询参数非法", qe.msg, qe.parameter), HTTPStatus.badRequest);
      return;
    }
    writeJsonApi(res, errorDocument(500, "服务内部错误", e.msg), HTTPStatus.internalServerError);
  }

  private long menuPosition(Json body, long fallback) {
    auto attrs = jsonGet(jsonGet(body, "data"), "attributes");
    auto text = jsonText(jsonGet(attrs, "indexno")).strip;
    if (text.length == 0)
      return fallback;
    try {
      return text.to!long;
    } catch (ConvException e) {
      return fallback;
    }
  }

  /// `from` / `to` 缺省为 0（交给 agent 取自己的默认窗口）；有值但不是整数就拒绝。
  private bool queryLong(HTTPServerRequest req, string name, out long value) {
    auto text = req.query.get(name, "").strip;
    value = 0;
    if (text.length == 0)
      return true;
    try {
      value = text.to!long;
      return true;
    } catch (ConvException) {
      return false;
    }
  }

  /// 实例名只能是一层目录名，挡掉控制台借日志接口读任意文件。
  private bool plainName(string name) {
    if (name.length == 0 || name == "." || name == "..")
      return false;
    foreach (ch; name) {
      if (ch == '/' || ch == '\\' || ch == '\0')
        return false;
    }
    return true;
  }

  private bool hasMenuPosition(Json body) {
    auto attrs = jsonGet(jsonGet(body, "data"), "attributes");
    return attrs.type == Json.Type.object && ("indexno" in attrs) !is null;
  }

  private void setMenuIndex(Json body, string value) {
    auto data = jsonGet(body, "data");
    if (data.type != Json.Type.object)
      return;
    auto attrs = jsonGet(data, "attributes");
    if (attrs.type != Json.Type.object) {
      attrs = Json.emptyObject;
      data["attributes"] = attrs;
    }
    attrs["indexno"] = Json(value);
    data["attributes"] = attrs;
    body["data"] = data;
  }

  /// scala MenuWS.afterPopulate：入口资源必须同时出现在 resources 关联里。
  private void linkMenuEntry(Json body) {
    auto data = jsonGet(body, "data");
    auto rels = jsonGet(data, "relationships");
    if (rels.type != Json.Type.object)
      return;
    auto entryRel = jsonGet(rels, "entry");
    auto entryData = entryRel.type == Json.Type.object ? jsonGet(entryRel, "data") : Json.undefined;
    if (entryData.type != Json.Type.object)
      return;
    auto entryId = jsonText(jsonGet(entryData, "id"));
    if (entryId.length == 0)
      return;

    Json[] resources;
    auto resourcesRel = jsonGet(rels, "resources");
    auto resourcesData = resourcesRel.type == Json.Type.object ? jsonGet(resourcesRel, "data") : Json.undefined;
    if (resourcesData.type == Json.Type.array) {
      foreach (ref item; resourcesData)
        resources ~= item;
    }
    foreach (ref item; resources) {
      if (jsonText(jsonGet(item, "id")) == entryId)
        return;
    }
    auto item = Json.emptyObject;
    item["type"] = Json("resources");
    item["id"] = Json(entryId);
    resources ~= item;
    auto relation = Json.emptyObject;
    relation["data"] = Json(resources);
    rels["resources"] = relation;
    data["relationships"] = rels;
    body["data"] = data;
  }

  /// 重排同级节点并把父节点前缀递归应用到子树；与 scala `Hierarchicals.move` 同形。
  private void moveMenu(string id, long requested) {
    auto menus = reg.find("menus");
    Json doc;
    if (!store.fetch(menus, id, Query.init, doc))
      throw new StoreException(null, "menu not found: " ~ id);
    auto data = jsonGet(doc, "data");
    auto appId = relationId(data, "app");
    auto parentId = relationId(data, "parent");
    if (parentId == id)
      throw new StoreException("parent", "菜单不能以自身为父节点");
    if (parentId.length > 0) {
      Json parent;
      if (!store.fetch(menus, parentId, Query.init, parent))
        throw new StoreException("parent", "父菜单不存在: " ~ parentId);
    }

    Row parentValue;
    parentValue["parent"] = parentId.length == 0 ? Json(null) : Json(parentId);
    store.updateColumns(menus, id, parentValue);

    auto q = Query.init;
    q.pageSize = 100000;
    q.addFilter("app", appId);
    q.addFilter("parent", parentId.length == 0 ? "null" : parentId);
    auto siblings = store.search(menus, q);
    string[] ids;
    foreach (ref item; siblings["data"]) {
      auto siblingId = jsonText(jsonGet(item, "id"));
      if (siblingId.length > 0 && siblingId != id)
        ids ~= siblingId;
    }
    long position = requested < 1 ? cast(long) ids.length + 1 : requested;
    if (position > cast(long) ids.length + 1)
      position = cast(long) ids.length + 1;
    auto at = cast(size_t)(position - 1);
    ids = ids[0 .. at] ~ id ~ ids[at .. $];

    string prefix;
    if (parentId.length > 0) {
      Json parent;
      if (store.fetch(menus, parentId, Query.init, parent))
        prefix = jsonText(jsonGet(jsonGet(parent, "data"), "attributes")["indexno"]);
    }
    auto width = ids.length.to!string.length;
    foreach (i, siblingId; ids) {
      auto suffix = leftPad((i + 1).to!string, width);
      auto indexno = prefix.length == 0 ? suffix : prefix ~ "." ~ suffix;
      setIndexno(menus, siblingId, indexno);
      renumberChildren(menus, appId, siblingId);
    }
    propagateDisabled(menus, id);
  }

  private void renumberChildren(const Resource menus, string appId, string parentId) {
    auto q = Query.init;
    q.pageSize = 100000;
    q.addFilter("app", appId);
    q.addFilter("parent", parentId);
    auto children = store.search(menus, q);
    string[] ids;
    foreach (ref item; children["data"])
      ids ~= jsonText(jsonGet(item, "id"));
    Json parent;
    if (!store.fetch(menus, parentId, Query.init, parent))
      return;
    auto prefix = jsonText(jsonGet(jsonGet(parent, "data"), "attributes")["indexno"]);
    auto width = ids.length.to!string.length;
    foreach (i, childId; ids) {
      auto indexno = prefix ~ "." ~ leftPad((i + 1).to!string, width);
      setIndexno(menus, childId, indexno);
      renumberChildren(menus, appId, childId);
    }
  }

  private void setIndexno(const Resource menus, string id, string indexno) {
    Json current;
    if (!store.fetch(menus, id, Query.init, current))
      return;
    auto old = jsonText(jsonGet(jsonGet(current, "data"), "attributes")["indexno"]);
    if (old == indexno)
      return;
    Row value;
    value["indexno"] = Json(indexno);
    store.updateColumns(menus, id, value);
  }

  private void propagateDisabled(const Resource menus, string id) {
    Json doc;
    if (!store.fetch(menus, id, Query.init, doc))
      return;
    auto attrs = jsonGet(jsonGet(doc, "data"), "attributes");
    if (jsonText(jsonGet(attrs, "enabled")) != "false")
      return;
    disableChildren(menus, id);
  }

  private void disableChildren(const Resource menus, string parentId) {
    auto q = Query.init;
    q.pageSize = 100000;
    q.addFilter("parent", parentId);
    auto children = store.search(menus, q);
    foreach (ref item; children["data"]) {
      auto id = jsonText(jsonGet(item, "id"));
      Row value;
      value["enabled"] = Json(false);
      store.updateColumns(menus, id, value);
      disableChildren(menus, id);
    }
  }

  private string relationId(Json data, string attr) {
    auto rels = jsonGet(data, "relationships");
    if (rels.type != Json.Type.object)
      return "";
    auto rel = jsonGet(rels, attr);
    if (rel.type != Json.Type.object)
      return "";
    auto relData = jsonGet(rel, "data");
    if (relData.type != Json.Type.object)
      return "";
    return jsonText(jsonGet(relData, "id"));
  }

  private string leftPad(string text, size_t width) {
    auto sb = appender!string;
    foreach (i; text.length .. width)
      sb.put('0');
    sb.put(text);
    return sb.data;
  }
}

/// 组装 `/api/bashub` 下的路由：按能力域分组，具体端点先注册，其余交给资源名分派。
HTTPServerRequestHandler buildHubRouter(HubConfig cfg, Registry reg, Store store, SessionRepo sessions = null,
    AgentRegistry agents = null, HubSecurity security = null) {
  auto router = new URLRouter("");
  auto api = hubApiPrefixes(cfg.apiPrefix);
  auto opts = RouteOptions(api.root, cfg.authRequired, cfg.emsBase ~ "/cas", cfg.sessionIdName);
  if (security is null && (cfg.authRequired || sessions !is null))
    security = new HubSecurity(cfg, sessions);
  if (security !is null)
    opts.guard = (HTTPServerRequest req, HTTPServerResponse res) => security.guard(req, res);
  auto hub = new HubService(cfg, reg, store, opts, api, sessions, agents, security);

  // config：机器配置分发与配置详情
  router.get(api.config ~ "/:project/server", &hub.projectServer);
  router.get(api.config ~ "/:project/proxy", &hub.projectProxy);
  router.get(api.config ~ "/projects/:id/certificate", &hub.projectCertificateInfo);
  router.patch(api.config ~ "/projects/:id/certificate", &hub.updateProjectCertificate);
  router.get(api.config ~ "/:project/certificate", &hub.projectCertificate);
  router.get(api.config ~ "/:project/certificate-key", &hub.projectCertificateKey);
  router.get(api.config ~ "/:project/setline-peers", &hub.projectPeers);
  router.get(api.config ~ "/:project/setline-manifest", &hub.projectManifest);
  router.get(api.config ~ "/:project/script/:host", &hub.projectHostScript);
  router.get(api.config ~ "/projects/:id/server", &hub.projectServerView);
  router.get(api.config ~ "/projects/:id/proxy", &hub.projectProxyView);
  router.get(api.config ~ "/projects/:id/setline-peers", &hub.projectPeersView);

  // micdn：下载配置、管理台聚合视图与组件目录
  router.get(api.micdn ~ "/:project/micdn.xml", &hub.projectMicdnXml);
  router.get(api.micdn ~ "/projects/:id/micdn.xml", &hub.downloadProjectMicdnXml);
  router.get(api.micdn ~ "/projects/:id", &hub.projectMicdn);
  router.patch(api.micdn ~ "/projects/:id", &hub.updateProjectMicdn);
  router.get(api.micdn ~ "/components", &hub.cdnComponents);
  router.post(api.micdn ~ "/components", &hub.createCdnComponent);
  router.patch(api.micdn ~ "/components/:id", &hub.updateCdnComponent);
  router.delete_(api.micdn ~ "/components/:id", &hub.deleteCdnComponent);

  // monitor：在线节点、日志与实例启停
  router.get(api.monitor ~ "/agents/summary", &hub.agentSummary);
  router.get(api.monitor ~ "/agents/status", &hub.agentStatus);
  router.get(api.monitor ~ "/agents/:project/history", &hub.agentHistory);
  router.get(api.monitor ~ "/agents/:project/agent-log", &hub.agentOwnLog);
  router.get(api.monitor ~ "/agents/:project/log/follow", &hub.agentLogFollow);
  router.get(api.monitor ~ "/agents/:project/log", &hub.agentLog);
  router.post(api.monitor ~ "/agents/:project/service/:action", &hub.agentService);
  router.post(api.monitor ~ "/agents/:project/report", &hub.agentReportNow);
  router.get(api.monitor ~ "/agents/:project/channel", &hub.projectAgents);

  // ems：登录前配置、会话、EMS 菜单与管理台资源
  router.get(api.ems ~ "/configs", &hub.configs);
  router.get(api.ems ~ "/sessions", &hub.currentSession);
  router.post(api.ems ~ "/sessions/logout", &hub.logout);
  router.get(api.ems ~ "/:project/menus/:appName", &hub.projectEmsMenus);
  router.post(api.config ~ "/projects/:id/reset-key", &hub.resetKey);
  router.post(api.config ~ "/webapps/upgrade", &hub.upgradeWebapps);
  router.post(api.config ~ "/artifacts/update-version", &hub.updateArtifactVersions);
  router.get(api.config ~ "/hosts/:id/webapps", &hub.hostWebapps);
  router.get(api.config ~ "/artifacts/:id/webapps", &hub.artifactWebapps);
  router.get(api.ems ~ "/resources/:id/menus", &hub.resourceMenus);
  router.get(api.ems ~ "/menus/export", &hub.exportMenusXml);
  router.post(api.ems ~ "/menus/import", &hub.importMenusXml);
  router.post(api.ems ~ "/menus", &hub.createMenu);
  router.patch(api.ems ~ "/menus/:id", &hub.updateMenu);

  // 通用 CRUD 按资源表前缀拆分：ems_ → ems、cfg_ → config；cdn_ 由 Micdn 专用端点处理。
  string[] configResources;
  string[] emsResources;
  foreach (item; reg.all) {
    if (item.path != "cdn-components" && item.path != "project-micdn"
        && item.path != "project-micdn-components" && item.path != "project-certificates") {
      auto group = resourceApiGroup(item);
      if (group == "ems")
        emsResources ~= item.path;
      else if (group == "config")
        configResources ~= item.path;
    }
  }
  auto configOpts = opts;
  configOpts.prefix = api.config;
  (new JsonApiService(reg, store, configOpts, configResources, &hub.configChanged)).register(router);
  auto emsOpts = opts;
  emsOpts.prefix = api.ems;
  (new JsonApiService(reg, store, emsOpts, emsResources)).register(router);
  // `.json` / `.jsonapi` 必须在 match 之前剥掉（见 withFormatSuffix 的注释）
  auto origins = cfg.corsOrigins.dup;
  auto emsHost = hostOfUrl(cfg.emsBase);
  if (emsHost.length > 0 && !origins.canFind(emsHost))
    origins ~= emsHost;
  // CORS/安全头在 suffix 规范化之外，预检请求不会进到 URLRouter
  return withWebAccess(withFormatSuffix(router), origins);
}

/// `https://sas.openurp.net` → `sas.openurp.net`；空串/非法值返回空串。
private string hostOfUrl(string url) {
  auto text = url.strip;
  auto scheme = text.indexOf("://");
  if (scheme >= 0)
    text = text[scheme + 3 .. $];
  auto slash = text.indexOf('/');
  if (slash >= 0)
    text = text[0 .. slash];
  auto colon = text.indexOf(':');
  if (colon >= 0)
    text = text[0 .. colon];
  return text;
}

/// 周期刷新与手动刷新共用：状态非 200 或取不到内容都当作「本次跳过」。
private string mavenMetadata(string url) {
  auto metadata = curlGet(url);
  return metadata.isOk ? cast(string) metadata.body : null;
}
