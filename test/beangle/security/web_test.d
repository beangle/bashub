/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.security.web_test;
/// Web 安全上下文的纯函数契约：CAS service 规范化、登录地址、Profile 选择。

import beangle.security.cas : CasConfig;
import beangle.security.session;
import beangle.security.web : casLoginUrl, loginUrlFor, selectedProfile, serviceUrl, wantsJson;

import std.algorithm.searching : canFind, startsWith;

import vibe.http.common : HTTPMethod;
import vibe.http.server : HTTPServerRequest, createTestHTTPServerRequest;
import vibe.inet.message : InetHeaderMap;
import vibe.inet.url : URL;

private HTTPServerRequest requestOf(string url, string[string] headers = null) {
  InetHeaderMap values;
  if (headers !is null) {
    foreach (key, value; headers)
      values[key] = value;
  }
  return createTestHTTPServerRequest(URL(url), HTTPMethod.GET, values);
}

@("serviceUrl 去掉 ticket/renew/sid_name 并对 query 排序")
unittest {
  auto req = requestOf("http://localhost/api/bashub/profiles/search?z=2&ticket=ST-1&a=1&renew=true&sid_name=x&b=2");
  assert(serviceUrl(req) == "http://localhost/api/bashub/profiles/search?a=1&b=2&z=2");
}

@("serviceUrl 优先使用 X-Forwarded-Proto/Host/Port")
unittest {
  auto req = requestOf("http://internal:8080/api/bashub/sessions",
      ["X-Forwarded-Proto": "https", "X-Forwarded-Host": "hub.example.com", "X-Forwarded-Port": "443"]);
  assert(serviceUrl(req) == "https://hub.example.com/api/bashub/sessions");
}

@("casLoginUrl 保留已有 query，并编码 service")
unittest {
  auto cfg = CasConfig.of("https://cas.example/cas");
  auto url = casLoginUrl(cfg, "https://hub.example/api?x=1&y=2");
  assert(url.startsWith("https://cas.example/cas/login?service="));
  assert(url.canFind("https%3A%2F%2Fhub.example%2Fapi%3Fx%3D1%26y%3D2"));
}

@("loginUrlFor 没配 CAS 时退回 ems cas 前缀")
unittest {
  auto req = requestOf("http://localhost/api/bashub/sessions");
  assert(loginUrlFor(CasConfig.init, req, "https://sas.example/cas") == "https://sas.example/cas");
}

@("wantsJson 识别 Accept、后缀、format 与 X-Requested-With")
unittest {
  assert(wantsJson(requestOf("http://localhost/api/bashub/sessions", ["Accept": "application/vnd.api+json"])));
  assert(wantsJson(requestOf("http://localhost/api/bashub/sessions.json")));
  assert(wantsJson(requestOf("http://localhost/api/bashub/sessions?format=json")));
  assert(wantsJson(requestOf("http://localhost/api/bashub/sessions", ["X-Requested-With": "XMLHttpRequest"])));
  assert(!wantsJson(requestOf("http://localhost/api/bashub/sessions", ["Accept": "text/html"])));
}

@("selectedProfile 只接受账户上真实存在的 Profile")
unittest {
  auto profile = new Profile();
  profile.id = 42;
  profile.name = "prod";
  auto account = new DefaultAccount("tester", "测试用户");
  account.profiles = [profile];
  auto session = new Session("sid", account, nowSeconds(), new Agent(), 1800);

  assert(selectedProfile(session, requestOf("http://localhost/api/bashub/sessions?contextProfileId=42")) is profile);
  assert(selectedProfile(session, requestOf("http://localhost/api/bashub/sessions?contextProfileId=7")) is null);
  assert(selectedProfile(session, requestOf("http://localhost/api/bashub/sessions",
          ["Cookie": "beangle.security.profileId=42"])) is profile);
  assert(selectedProfile(null, requestOf("http://localhost/api/bashub/sessions?contextProfileId=42")) is null);
}
