/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.security.cas;
/// ems/ids 侧 CAS 会话服务（`org.beangle.ids.cas.web.ws.SessionAction`）的客户端，
/// 也就是 scala `org.beangle.ems.app.cas.CasHttpSessionRepo` 的 D 版：四个 URL 模板与它一致，
/// 所以现网 CAS 不用改一行就能被这里读会话。
///
/// 报文格式固定为 JSON（`?format=application/json`）。现网 CAS 已确认能返回完整的会话对象，
/// 因此这里只保留一种文本解码路径，不再维护第二套二进制协议。
///
/// 对接的是**会话数据**（读会话 / 心跳续期 / 作废 / 按账号找会话），不是 CAS 登录流程：
/// 票据校验、302 跳转、单点登出都在网关侧（见 README）。

import beangle.commons.net.curl : HttpGetResult, curlGet;
import beangle.security.session;
import beangle.security.sessioncache : CacheSessionRepo;
import beangle.security.sessionjson : decodeSessionJson;

import std.array : replace;
import std.conv : to;
import std.string : stripRight;

import vibe.core.log : logWarn;

/// CAS 会话报文的 media type。
enum string casSessionMediaType = "application/json";

/** CAS 会话服务的地址与四个端点模板（scala `CasConfig` 加上 `HttpSessionRepo` 的四个地址）。 */
struct CasConfig {
  /// 服务根地址（末尾的斜杠已经去掉）
  string casServer;
  /// `CasConfig` 的三个协议路径（scala 缺省值）
  string loginUri = "/login";
  string logoutUri = "/logout";
  string validateUri = "/serviceValidate";
  /// `/session/{id}?format=<media type>`
  string getUrl;
  /// `/session/{id}/access?time={time}`
  string accessUrl;
  /// `/session/{principal}/ids`
  string findUrl;
  /// `/session/{id}/expire`
  string expireUrl;

  /// `{cas}/login`（不带 service 参数；跳转 URL 由 web 层拼）
  string loginUrl() const {
    return casServer ~ loginUri;
  }

  /// `{cas}/logout`（scala `CasConfig.logoutUrl`）
  string logoutUrl() const {
    return casServer ~ logoutUri;
  }

  /// `{cas}/serviceValidate`
  string validateUrl() const {
    return casServer ~ validateUri;
  }

  /// 按 scala 的模板拼四个 URL；会话报文固定使用 JSON。
  static CasConfig of(string server) {
    auto base = stripRight(server, "/");
    CasConfig cfg;
    cfg.casServer = base;
    cfg.getUrl = base ~ "/session/{id}?format=" ~ casSessionMediaType;
    cfg.accessUrl = base ~ "/session/{id}/access?time={time}";
    cfg.findUrl = base ~ "/session/{principal}/ids";
    cfg.expireUrl = base ~ "/session/{id}/expire";
    return cfg;
  }
}

/// 取一个 URL 的实现；默认走宿主 curl，测试里可以注入假的（见 `test/beangle/security/`）。
alias SessionHttpGet = HttpGetResult delegate(string url);

private HttpGetResult defaultHttpGet(string url) {
  return curlGet(url);
}

/** 拆 id 列表：scala `Strings.split(text)` 认的分隔符是 `,` `;` `\r` `\n` 和空格，并跳过空段。
 * 手写而不用 `splitter`：这里的分隔符就是一段 ASCII，按字节走最直白。
 */
private string[] splitIds(string text) {
  string[] ids;
  size_t start;
  foreach (i, c; text) {
    if (c == ',' || c == ';' || c == '\r' || c == '\n' || c == ' ') {
      if (i > start)
        ids ~= text[start .. i];
      start = i + 1;
    }
  }
  if (start < text.length)
    ids ~= text[start .. $];
  return ids;
}

class CasSessionRepo : CacheSessionRepo {
  private CasConfig cfg;
  private SessionHttpGet httpGet;

  this(CasConfig cfg, SessionHttpGet httpGet = null) {
    this.cfg = cfg;
    this.httpGet = (httpGet is null) ? ((string url) => defaultHttpGet(url)) : httpGet;
  }

  /// 从 CAS 取会话（scala `HttpSessionRepo.getInternal`）：非 200 就当没有这个会话。
  override protected Session fetch(string sessionId) {
    auto res = httpGet(replace(cfg.getUrl, "{id}", sessionId));
    if (!res.isOk())
      return null;
    try {
      return decodeSessionJson(cast(string) res.body);
    } catch (Exception e) {
      // 拿到 200 却解不开（网关回了登录页、或者报文被截断）：当没有会话，别把请求打成 500
      logWarn("Cannot decode session %s from CAS as %s (%s bytes): %s",
          sessionId, casSessionMediaType, res.body.length, e.msg);
      return null;
    }
  }

  /// 按账号找会话（scala `findByPrincipal`）：先取 id 列表，再逐个回源。
  override Session[] findByPrincipal(string principal) {
    auto res = httpGet(replace(cfg.findUrl, "{principal}", principal));
    if (!res.isOk())
      return null;
    Session[] found;
    foreach (sessionId; splitIds(cast(string) res.body)) {
      if (auto s = fetch(sessionId))
        found ~= s;
    }
    return found;
  }

  /// 心跳（scala `HttpSessionRepo.flush`）：`/session/{id}/access?time={lastAccessAt}`。
  override protected bool flush(Session session) {
    auto url = replace(cfg.accessUrl, "{id}", session.id);
    url = replace(url, "{time}", session.lastAccessAt.to!string);
    return httpGet(url).isOk();
  }

  /// 作废（scala `HttpSessionRepo.expire`）：先清本地缓存，再让 CAS 侧删掉。
  override void expire(string sessionId) {
    evict(sessionId);
    httpGet(replace(cfg.expireUrl, "{id}", sessionId));
  }
}
