/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.web.http;
/// 通用 HTTP 外壳：CORS 与安全响应头。放在 `beangle.web` 而不是业务路由里，
/// 后续 bashub 的其他前端（管理台、门户）可以直接复用同一份口径。
///
/// CORS 行为对齐 beangle webmvc 的 `CorsInterceptor`：允许完整 origin 或主机名；
/// 同源请求不下发 CORS 头；预检成功返回 204；不允许的来源直接 403。

import beangle.security.web : requestOrigin, requestScheme;

import std.algorithm : canFind;
import std.array : join;
import std.conv : to;
import std.string : indexOf, split, startsWith, strip, toLower;

import vibe.http.common : HTTPStatus, httpMethodString;
import vibe.http.server : HTTPServerRequest, HTTPServerRequestHandler, HTTPServerResponse;

/// 中间件包一层；内层通常是 URLRouter（或它的后缀规范化包装）。
class WebAccessMiddleware : HTTPServerRequestHandler {
  private HTTPServerRequestHandler inner;
  private string[] allowedOrigins;
  private string[] allowedMethods = ["GET", "POST", "HEAD", "OPTIONS", "PATCH", "DELETE", "PUT"];
  private string[] allowedHeaders = ["authorization", "content-type", "accept", "origin", "x-requested-with",
    "last-event-id"];
  private int preflightMaxAge = 1800;
  private bool allowCredentials = true;

  this(HTTPServerRequestHandler inner, string[] allowedOrigins = null) {
    this.inner = inner;
    if (allowedOrigins !is null)
      this.allowedOrigins = allowedOrigins;
  }

  void handleRequest(HTTPServerRequest req, HTTPServerResponse res) {
    applySecurityHeaders(req, res);

    auto origin = req.headers.get("Origin", "").strip;
    if (origin.length == 0) {
      inner.handleRequest(req, res);
      return;
    }

    auto requestMethod = methodName(req);
    auto preflight = requestMethod == "OPTIONS" && req.headers.get("Access-Control-Request-Method", "").length > 0;
    if (!isCorsRequest(req, origin)) {
      inner.handleRequest(req, res);
      return;
    }
    if (!originAllowed(origin)) {
      res.writeBody("", HTTPStatus.forbidden);
      return;
    }

    if (preflight) {
      auto wantedMethod = req.headers.get("Access-Control-Request-Method", "").strip.toLower;
      auto wantedHeaders = req.headers.get("Access-Control-Request-Headers", "").strip.toLower;
      if (!methodAllowed(wantedMethod) || !headersAllowed(wantedHeaders)) {
        res.writeBody("", HTTPStatus.forbidden);
        return;
      }
      setCorsHeaders(res, origin);
      res.headers["Access-Control-Allow-Methods"] = allowedMethods.join(",");
      res.headers["Access-Control-Allow-Headers"] = allowedHeaders.join(",");
      if (preflightMaxAge > 0)
        res.headers["Access-Control-Max-Age"] = preflightMaxAge.to!string;
      res.writeBody("", HTTPStatus.noContent);
      return;
    }

    if (!methodAllowed(requestMethod)) {
      res.writeBody("", HTTPStatus.forbidden);
      return;
    }
    setCorsHeaders(res, origin);
    inner.handleRequest(req, res);
  }

  private void applySecurityHeaders(HTTPServerRequest req, HTTPServerResponse res) @safe {
    res.headers["X-Content-Type-Options"] = "nosniff";
    res.headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    if (req.requestPath.toString.startsWith("/api/"))
      res.headers["Cache-Control"] = "no-store";
    if (requestScheme(req) == "https")
      res.headers["Strict-Transport-Security"] = "max-age=31536000";
  }

  private void setCorsHeaders(HTTPServerResponse res, string origin) @safe {
    res.headers["Access-Control-Allow-Origin"] = origin;
    if (allowCredentials)
      res.headers["Access-Control-Allow-Credentials"] = "true";
    res.headers["Vary"] = "Origin";
  }

  private bool isCorsRequest(HTTPServerRequest req, string origin) @safe {
    return requestOrigin(req).toLower != origin.toLower;
  }

  private bool originAllowed(string origin) @safe {
    if (origin.indexOf('%') >= 0)
      return false;
    if (allowedOrigins.canFind(origin))
      return true;
    auto host = hostOf(origin);
    return host.length > 0 && allowedOrigins.canFind(host);
  }

  private string hostOf(string origin) @safe {
    auto text = origin.strip;
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

  private bool methodAllowed(string method) @safe {
    auto wanted = method.strip.toLower;
    foreach (allowed; allowedMethods) {
      if (allowed.toLower == wanted)
        return true;
    }
    return false;
  }

  private bool headersAllowed(string requested) @safe {
    if (requested.length == 0)
      return true;
    foreach (header; requested.split(",")) {
      auto name = header.strip.toLower;
      if (name.length > 0 && !allowedHeaders.canFind(name))
        return false;
    }
    return true;
  }

  private string methodName(HTTPServerRequest req) @safe {
    return httpMethodString(req.method);
  }
}

/// 测试与装配用：把内层路由包上 CORS/安全头。
HTTPServerRequestHandler withWebAccess(HTTPServerRequestHandler inner, string[] allowedOrigins = null) {
  return new WebAccessMiddleware(inner, allowedOrigins);
}
