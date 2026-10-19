/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.repo.web_test;
/// `/repo/native` 的 HTTP 契约：别名 HEAD/重定向、真实文件下载、Basic 上传与路由装配。

import bashub.config : HubConfig;
import bashub.demo : demoDao;
import bashub.repo.native : NativeRepo;
import bashub.repo.web : NativeService;
import bashub.resources : hubRegistry;
import bashub.route : buildHubRouter;
import bashub.store : createHubStore;

import test.beangle.tempdir : uniqueTempDir;

import std.base64 : Base64;
import std.file : exists, mkdirRecurse, rmdirRecurse, write;
import std.path : buildPath, dirName;

import vibe.http.common : HTTPMethod;
import vibe.http.server : HTTPServerRequest, HTTPServerRequestHandler, HTTPServerResponse,
  createTestHTTPServerRequest, createTestHTTPServerResponse, TestHTTPResponseMode;
import vibe.inet.message : InetHeaderMap;
import vibe.inet.url : URL;
import vibe.stream.memory : createMemoryOutputStream, createMemoryStream;

private enum string versionDirName = "4.20.14-SNAPSHOT";
private enum string aliasPath =
  "org/beangle/beangle-ems-portal/" ~ versionDirName ~ "/beangle-ems-portal-4.20.14-SNAPSHOT-linux-amd64.tar.gz";
private enum string actualName =
  "beangle-ems-portal-4.20.14-SNAPSHOT-20260913.101500-1-linux-amd64.tar.gz";
private enum string actualPath = "org/beangle/beangle-ems-portal/" ~ versionDirName ~ "/" ~ actualName;
private enum string releasePath =
  "org/beangle/beangle-ems-portal/4.20.13/beangle-ems-portal-4.20.13-linux-amd64.tar.gz";

private struct Exchange {
  int status;
  string body;
  string[string] headers;
}

@("HEAD reports the actual file name and GET redirects a SNAPSHOT alias")
unittest {
  auto dir = uniqueTempDir("bashub-native-web-");
  scope (exit) rmdirRecurse(dir);
  auto repo = new NativeRepo(dir);
  seedFile(buildPath(repo.snapshotRoot, actualPath), "native actual");

  HubConfig cfg;
  cfg.repoHome = dir;
  cfg.snapshotUsertoken = "secret";
  auto service = new NativeService(cfg);

  auto head = callDirect(service, HTTPMethod.HEAD, "/repo/native/" ~ aliasPath);
  assert(head.status == 200);
  assert(head.headers["latest"] == actualName);
  assert(head.headers["Last-Modified"].length > 0);

  auto redirect = callDirect(service, HTTPMethod.GET, "/repo/native/" ~ aliasPath);
  assert(redirect.status == 302);
  assert(redirect.headers["Location"] == "/repo/native/" ~ actualPath);

  auto actual = callDirect(service, HTTPMethod.GET, "/repo/native/" ~ actualPath);
  assert(actual.status == 200);
  assert(actual.body == "native actual");
}

@("Basic upload requires snapshot.usertoken and stores the request body")
unittest {
  auto dir = uniqueTempDir("bashub-native-upload-");
  scope (exit) rmdirRecurse(dir);
  HubConfig cfg;
  cfg.repoHome = dir;
  cfg.snapshotUsertoken = "secret";
  auto router = newRouter(cfg);

  auto denied = call(router, HTTPMethod.POST, "http://localhost/repo/native/upload/" ~ releasePath,
      "artifact bytes", ["Authorization": basic("wrong")]);
  assert(denied.status == 403);
  assert(!exists(buildPath(dir, "repository", releasePath)));

  auto accepted = call(router, HTTPMethod.POST, "http://localhost/repo/native/upload/" ~ releasePath,
      "artifact bytes", ["Authorization": basic("secret")]);
  assert(accepted.status == 200);
  assert(exists(buildPath(dir, "repository", releasePath)));
}

@("the hub router serves a real native artifact")
unittest {
  auto dir = uniqueTempDir("bashub-native-route-");
  scope (exit) rmdirRecurse(dir);
  HubConfig cfg;
  cfg.repoHome = dir;
  auto repo = new NativeRepo(dir);
  seedFile(buildPath(repo.repositoryRoot, releasePath), "native release");
  auto router = newRouter(cfg);

  auto response = call(router, HTTPMethod.GET, "http://localhost/repo/native/" ~ releasePath);
  assert(response.status == 200);
  assert(response.body == "native release");
}

private HTTPServerRequestHandler newRouter(HubConfig cfg) {
  cfg.apiPrefix = "/api/hub";
  cfg.emsBase = "https://sas.openurp.net";
  cfg.appName = "bas-hub";
  auto reg = hubRegistry();
  return buildHubRouter(cfg, reg, createHubStore(reg, demoDao(reg)));
}

private Exchange callDirect(NativeService service, HTTPMethod method, string path) {
  auto req = createTestHTTPServerRequest(URL("http://localhost" ~ path), method);
  auto output = createMemoryOutputStream();
  auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);
  if (method == HTTPMethod.HEAD)
    service.head(req, res);
  else
    service.download(req, res);
  return exchange(res, output.data);
}

private Exchange call(HTTPServerRequestHandler router, HTTPMethod method, string url, string body = null,
    string[string] requestHeaders = null) {
  InetHeaderMap headers;
  if (requestHeaders !is null)
    foreach (key, value; requestHeaders)
      headers[key] = value;
  if (body.length > 0)
    headers["Content-Type"] = "application/octet-stream";
  auto req = createTestHTTPServerRequest(URL(url), method, headers,
      body.length > 0 ? createMemoryStream(cast(ubyte[]) body.dup) : null);
  auto output = createMemoryOutputStream();
  auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);
  router.handleRequest(req, res);
  return exchange(res, output.data);
}

private Exchange exchange(HTTPServerResponse res, const(ubyte)[] body) {
  Exchange ex;
  ex.status = cast(int) res.statusCode;
  ex.body = cast(string) body;
  foreach (key, value; res.headers.byKeyValue)
    ex.headers[key] = value;
  return ex;
}

private string basic(string token) {
  return "Basic " ~ cast(string) Base64.encode(cast(const(ubyte)[]) token);
}

private void seedFile(string path, string content) {
  mkdirRecurse(dirName(path));
  write(path, content);
}
