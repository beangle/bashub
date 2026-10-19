/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.jsonapi.router;
/// 通用 CRUD 路由与请求处理。URL 契约（与 beangle 的 she `JsonApiWS` 一致）：
///
///   - `GET    {prefix}/{resource}/search` 列表：过滤、`page[number]`/`page[size]`、`sort`、`include`
///   - `POST   {prefix}/{resource}`        新建
///   - `GET    {prefix}/{resource}/{id}`   详情
///   - `PATCH  {prefix}/{resource}/{id}`   修改
///   - `DELETE {prefix}/{resource}/{id}`   删除
///
/// 资源不逐个写处理器：路由里资源名是参数，注册表里找不到就是 404，
/// 所以「支持哪些资源」只由 `Registry` 决定。应用自己的端点挂在同一个 router 上（见 `buildJsonApiRouter`）。

import beangle.data.dao;
import beangle.jsonapi.document;
import beangle.data.query;
import beangle.data.resource;
import beangle.jsonapi.store;
import beangle.data.value;

import vibe.core.log;
import vibe.core.path : InetPath;
import vibe.data.json : Json;
import vibe.http.common : HTTPStatus;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerRequestHandler, HTTPServerResponse;

import std.string : indexOf;

/// JSON:API 的响应媒体类型（客户端按它解析，缺了会走错分支）。
enum jsonApiContentType = "application/vnd.api+json; charset=UTF-8";

/// 应用注入的请求守卫：返回 false 表示已经写好响应（401/403/302 等）。
alias RequestGuard = bool delegate(HTTPServerRequest req, HTTPServerResponse res);

/// 挂载参数：前缀与登录策略。应用想换一套就传别的值，不用改这里。
struct RouteOptions {
  string prefix = "/api";
  /// 是否要求登录（预演阶段只判「有没有凭证」，真正的 CAS 校验由应用/网关负责）
  bool authRequired = false;
  /// 未登录时写进 `errors[0].meta.redirectUrl` 的地址
  string loginRedirectUrl;
  /// 会话 cookie 名；与 `Ems.sid.name` 同一个来源，别在路由层再写死一个
  string sessionIdName = "URP_SID";
  /// 真正的认证/授权回调；为空时退回「请求里有没有凭证」的预演逻辑
  RequestGuard guard;
}

/** `{prefix}` 下通用 CRUD 的处理器。
 *
 * 公开（而不是藏在 free function 里）是为了让应用能：复用同一套错误映射与媒体类型；
 * 或者覆写某一个动作（如详情要多带点东西）。
 */
class JsonApiService {
  private Registry reg;
  private Store store;
  private RouteOptions opts;

  this(Registry reg, Store store, in RouteOptions opts) {
    this.reg = reg;
    this.store = store;
    this.opts = opts;
  }

  /// `GET {prefix}/{resource}/search`
  void search(HTTPServerRequest req, HTTPServerResponse res) {
    if (!checkAuth(req, res))
      return;
    auto res0 = resourceOf(req, res);
    if (res0.path.length == 0)
      return;
    try {
      writeJsonApi(res, store.search(res0, parseQuery(collectParams(req), req.cookies.get("pageSize", ""))),
          HTTPStatus.ok);
    } catch (Exception e) {
      reportError(res, e);
    }
  }

  /// `GET {prefix}/{resource}/{id}`
  void fetch(HTTPServerRequest req, HTTPServerResponse res) {
    if (!checkAuth(req, res))
      return;
    auto res0 = resourceOf(req, res);
    if (res0.path.length == 0)
      return;
    auto id = idOf(req);
    try {
      Json doc;
      if (!store.fetch(res0, id, parseQuery(collectParams(req), req.cookies.get("pageSize", "")), doc))
        writeNotFound(res, res0, id);
      else
        writeJsonApi(res, doc, HTTPStatus.ok);
    } catch (Exception e) {
      reportError(res, e);
    }
  }

  /// `POST {prefix}/{resource}`
  void create(HTTPServerRequest req, HTTPServerResponse res) {
    if (!checkAuth(req, res))
      return;
    auto res0 = resourceOf(req, res);
    if (res0.path.length == 0)
      return;
    auto body = requestBody(req, res);
    if (body.type == Json.Type.undefined)
      return;
    try {
      writeJsonApi(res, store.create(res0, body), HTTPStatus.created);
    } catch (Exception e) {
      reportError(res, e);
    }
  }

  /// `PATCH {prefix}/{resource}/{id}`
  void update(HTTPServerRequest req, HTTPServerResponse res) {
    if (!checkAuth(req, res))
      return;
    auto res0 = resourceOf(req, res);
    if (res0.path.length == 0)
      return;
    auto id = idOf(req);
    auto body = requestBody(req, res);
    if (body.type == Json.Type.undefined)
      return;
    try {
      Json doc;
      if (!store.update(res0, id, body, doc))
        writeNotFound(res, res0, id);
      else
        writeJsonApi(res, doc, HTTPStatus.ok);
    } catch (Exception e) {
      reportError(res, e);
    }
  }

  /// `DELETE {prefix}/{resource}/{id}`
  void remove(HTTPServerRequest req, HTTPServerResponse res) {
    if (!checkAuth(req, res))
      return;
    auto res0 = resourceOf(req, res);
    if (res0.path.length == 0)
      return;
    auto id = idOf(req);
    try {
      if (!store.remove(res0, id))
        writeNotFound(res, res0, id);
      else
        writeJsonApi(res, okDocument(), HTTPStatus.ok);
    } catch (Exception e) {
      reportError(res, e);
    }
  }

  /// 把通用 CRUD 注册到一张已有的 router 上：应用自己的端点先注册，其余交给这里。
  /// 顺序有意义——`URLRouter` 按注册顺序匹配，具体路径要排在 `:resource` 参数路由前面。
  void register(URLRouter router) {
    auto p = opts.prefix;
    router.get(p ~ "/:resource/search", &search);
    router.post(p ~ "/:resource", &create);
    router.get(p ~ "/:resource/:id", &fetch);
    router.patch(p ~ "/:resource/:id", &update);
    router.delete_(p ~ "/:resource/:id", &remove);
  }

  /// 取路由参数里的资源；没有就 404（信息里带上资源名，便于定位拼错的 URL）。
  private Resource resourceOf(HTTPServerRequest req, HTTPServerResponse res) {
    auto path = req.params.get("resource", "");
    auto res0 = reg.find(path);
    if (res0.path.length == 0) {
      logInfo("Unknown resource: %s", path);
      writeJsonApi(res, errorDocument(404, "resource not found", "no such resource: " ~ path), HTTPStatus.notFound);
    }
    return res0;
  }

  private string idOf(HTTPServerRequest req) {
    return req.params.get("id", "");
  }

  /// 未登录处理复用模块级 `requireAuth`，应用自己的端点也能用同一份口径。
  private bool checkAuth(HTTPServerRequest req, HTTPServerResponse res) {
    return requireAuth(req, res, opts);
  }

  /// 读 JSON:API 请求体；不是 JSON / 是空体时写 400 并返回 `Json.undefined`。
  /// 畸形 JSON 会让 `req.json` 抛异常，客户端发错东西不该变成 500。
  private Json requestBody(HTTPServerRequest req, HTTPServerResponse res) {
    Json body;
    try {
      body = req.json;
    } catch (Exception e) {
      body = Json.undefined;
    }
    if (body.type == Json.Type.undefined || body.type == Json.Type.null_) {
      writeJsonApi(res, errorDocument(400, "请求体缺失或非法",
              "expect a JSON:API document with Content-Type: application/vnd.api+json"), HTTPStatus.badRequest);
      return Json.undefined;
    }
    return body;
  }

  private void writeNotFound(HTTPServerResponse res, const Resource r, string id) {
    writeJsonApi(res, errorDocument(404, "记录不存在", "no " ~ r.path ~ " with id " ~ id), HTTPStatus.notFound);
  }

  private void reportError(HTTPServerResponse res, Exception e) {
    if (auto qe = cast(QueryException) e)
      writeJsonApi(res, errorDocument(400, "查询参数非法", qe.msg, qe.parameter), HTTPStatus.badRequest);
    else if (auto se = cast(StoreException) e)
      writeJsonApi(res, errorDocument(400, "请求数据非法", se.msg, se.attribute), HTTPStatus.badRequest);
    else if (auto de = cast(DaoException) e) {
      if (de.msg.indexOf("duplicate key value violates unique constraint") >= 0) {
        auto constraint = quotedAfter(de.msg, `unique constraint "`);
        auto detail = constraint.length == 0 ? "记录已存在或与现有数据冲突" : "违反唯一约束: " ~ constraint;
        writeJsonApi(res, errorDocument(409, "数据冲突", detail), HTTPStatus.conflict);
      } else if (de.msg.indexOf("violates foreign key constraint") >= 0) {
        writeJsonApi(res, errorDocument(409, "关联数据冲突", "引用的记录不存在或仍被使用"),
            HTTPStatus.conflict);
      } else if (de.msg.indexOf("violates not-null constraint") >= 0) {
        auto column = quotedAfter(de.msg, `null value in column "`);
        writeJsonApi(res, errorDocument(400, "必填字段缺失", "缺少必填字段: " ~ column, column),
            HTTPStatus.badRequest);
      } else if (de.msg.indexOf("violates check constraint") >= 0) {
        writeJsonApi(res, errorDocument(400, "数据校验失败", "字段值不符合约束"), HTTPStatus.badRequest);
      } else {
        logError("Dao error: %s", de.msg);
        writeJsonApi(res, errorDocument(500, "数据访问失败", de.msg), HTTPStatus.internalServerError);
      }
    } else {
      logError("Unhandled error: %s", e.msg);
      writeJsonApi(res, errorDocument(500, "服务内部错误", e.msg), HTTPStatus.internalServerError);
    }
  }
}

/// 从 PostgreSQL 错误文本里取 `marker "..."` 中的值；没有就返回空串。
private string quotedAfter(string text, string marker) {
  auto at = text.indexOf(marker);
  if (at < 0)
    return null;
  at += marker.length;
  auto end = text.indexOf('"', at);
  return end < 0 ? null : text[at .. end];
}

/// 建一个挂好通用 CRUD 的 router；应用可以在返回值上继续注册自己的端点。
HTTPServerRequestHandler buildJsonApiRouter(Registry reg, Store store, in RouteOptions opts = RouteOptions.init) {
  auto router = new URLRouter("");
  (new JsonApiService(reg, store, opts)).register(router);
  return withFormatSuffix(router);
}

/** 给路由套一层「URL 后缀规范化」。
 *
 * webmvc 侧的 URL 习惯（`/configs.json`、`/profiles.json`）前端和老客户端都还在用；D 侧的路由
 * 是按精确路径注册的。不能靠「最后挂 `*` 兜底」：`/configs.json`、`/profiles/search.json` 会
 * 先被 `:resource` / `:id` 这类参数路由匹配掉，根本轮不到兜底。所以要在 **match 之前** 把
 * `req.requestPath` 改掉，再交给 `URLRouter`。
 *
 * 没有后缀时行为完全不变（不分配、不重写）。
 */
HTTPServerRequestHandler withFormatSuffix(URLRouter router) {
  return new SuffixNormalizingRouter(router);
}

/// 去掉末尾的 `.json` / `.jsonapi`（大小写敏感，与 webmvc 一致）；没有就原样返回。
string stripFormatSuffix(string path) @safe {
  enum jsonapi = ".jsonapi";
  enum json = ".json";
  if (path.length > jsonapi.length && path[$ - jsonapi.length .. $] == jsonapi)
    return path[0 .. $ - jsonapi.length];
  if (path.length > json.length && path[$ - json.length .. $] == json)
    return path[0 .. $ - json.length];
  return path;
}

private final class SuffixNormalizingRouter : HTTPServerRequestHandler {
  private URLRouter inner;

  this(URLRouter inner) {
    this.inner = inner;
  }

  void handleRequest(HTTPServerRequest req, HTTPServerResponse res) @safe {
    auto path = req.requestPath.toString();
    auto stripped = stripFormatSuffix(path);
    if (stripped.length != path.length)
      req.requestPath = InetPath(stripped);
    inner.handleRequest(req, res);
  }
}

/// 鉴权：应用注入了 guard 就交给它（含 CAS 校验、权限判定）；
/// 否则退回预演逻辑：`authRequired` 为假一律放行，为真只看请求里有没有凭证。
/// 未登录时写与 bashub 同形的 401 文档（`errors[0].meta.redirectUrl`）并返回 false。
bool requireAuth(HTTPServerRequest req, HTTPServerResponse res, in RouteOptions opts) {
  if (opts.guard !is null)
    return opts.guard(req, res);
  if (!opts.authRequired)
    return true;
  auto authorization = req.headers.get("Authorization", "");
  auto sid = req.cookies.get(opts.sessionIdName, "");
  if (authorization.length > 0 || sid.length > 0)
    return true;
  writeJsonApi(res, unauthorizedDocument(opts.loginRedirectUrl), HTTPStatus.unauthorized);
  return false;
}

/// 写 JSON:API 响应（应用自己的端点也用这个，媒体类型与状态码只有这一处）。
void writeJsonApi(HTTPServerResponse res, Json doc, HTTPStatus status) {
  res.writeJsonBody(doc, cast(int) status, jsonApiContentType);
}

/// 请求里的查询参数，保留同名多值的每一次出现（重复的 `filter[...]` 不能再丢）。
QueryParam[] collectParams(HTTPServerRequest req) {
  QueryParam[] params;
  foreach (kv; req.query.byKeyValue())
    params ~= QueryParam(kv.key, kv.value);
  return params;
}
