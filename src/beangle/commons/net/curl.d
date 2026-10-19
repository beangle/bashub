/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.commons.net.curl;
/// 最小 HTTP 客户端：交给宿主的 `curl` 取一个 URL 的状态码与响应体。
///
/// 为什么不用 `vibe.http.client`：本工程按 Beangle D 路线的惯例把 vibe-stream 的 TLS 关掉了
/// （`dub.json` 的 `notls` 省掉静态 OpenSSL），而 CAS 一定是 https——所以交给宿主 curl
/// （micdn 的 `micdn.web.curl` 也是这个路子，这里只要它「取回响应体」那一半）。

import std.conv : to;
import std.file : exists, read, remove, tempDir;
import std.path : buildPath;
import std.process : execute;
import std.string : strip;
import std.typecons : Tuple;

import core.atomic : atomicOp;
import core.time : Duration, seconds;

import vibe.core.log : logWarn;

/** 一次 GET 的结果；`status` 为 0 表示压根没拿到响应（连不上、超时、起不了 curl）。 */
struct HttpGetResult {
  int status;
  ubyte[] body;

  /// 与 scala 侧 `Response.isOk` 同口径：只有 200 算成功（404、302 都算没有）。
  bool isOk() const @safe pure nothrow {
    return status == 200;
  }
}

/// 临时文件名只求进程内不重名，所以用一个自增序号就够。
private shared uint tempSeq;

private string tempBodyPath() {
  auto n = atomicOp!"+="(tempSeq, 1);
  return buildPath(tempDir(), "bashub-curl-" ~ n.to!string ~ ".tmp");
}

/// `execute` 的返回类型（这个 phobos 里没有具名的 ProcessResult）。
private alias ProcessResult = Tuple!(int, "status", string, "output");

/** GET `url`；响应体先落临时文件再读回，免得二进制体和状态码在 stdout 里混成一团。 */
HttpGetResult curlGet(string url, Duration connectTimeout = 5.seconds, Duration maxTimeout = 30.seconds) {
  auto tmpPath = tempBodyPath();
  scope (exit) {
    if (exists(tmpPath))
      remove(tmpPath);
  }

  ProcessResult run;
  try {
    run = execute([
      "curl", "--silent", "--show-error", "--location",
      "--connect-timeout", connectTimeout.total!"seconds".to!string,
      "--max-time", maxTimeout.total!"seconds".to!string,
      "--output", tmpPath,
      "--write-out", "%{http_code}",
      url
    ]);
  } catch (Exception e) { // 宿主没装 curl：当作「没拿到响应」，别把调用方拖垮
    logWarn("curl %s failed to start: %s", url, e.msg);
    return HttpGetResult(0, null);
  }

  HttpGetResult res;
  if (run.status == 0) {
    auto code = run.output.strip;
    res.status = code.length > 0 ? code.to!int : 0;
  } else {
    logWarn("curl %s exit %s: %s", url, run.status, run.output.strip);
  }
  if (res.status == 200 && exists(tmpPath))
    res.body = cast(ubyte[]) read(tmpPath);
  return res;
}
