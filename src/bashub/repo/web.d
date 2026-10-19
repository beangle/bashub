/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.repo.web;
/// `/repo/native` 的 HTTP 适配：下载、SNAPSHOT 别名重定向、HEAD 探测与 Basic 令牌上传。

import bashub.config : HubConfig;
import bashub.repo.manifest : WarCoordinates, readWarCoordinates, repositoryPath;
import bashub.repo.native : NativeRepo, UploadResult;

import eventcore.driver : IOMode;

import std.array : appender;
import std.base64 : Base64;
import std.conv : to;
import std.file : exists, getSize, remove, tempDir, timeLastModified;
import std.path : baseName, buildPath;
import std.random : unpredictableSeed;
import std.stdio : File;
import std.string : startsWith, strip;

import vibe.core.file : openFile;
import vibe.core.path : toNativeString;
import vibe.core.log : logError;
import vibe.core.stream : pipe;
import vibe.http.common : HTTPStatus;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.inet.message : toRFC822DateTimeString;

private enum string nativePrefix = "/repo/native/";
private enum string uploadPrefix = "/repo/native/upload/";

/** 原生发行包 HTTP 服务。 */
class NativeService {
  private NativeRepo repo;
  private string usertoken;

  this(HubConfig cfg) {
    this.repo = new NativeRepo(cfg.repoHome);
    this.usertoken = cfg.snapshotUsertoken;
  }

  /// `HEAD /repo/native/{path}`：存在性探测；别名请求用 `latest` 头带出实际文件名。
  void head(HTTPServerRequest req, HTTPServerResponse res) {
    access(req, res, true);
  }

  /// `GET /repo/native/{path}`：真实文件直接输出；SNAPSHOT 别名先重定向到时间戳文件。
  void download(HTTPServerRequest req, HTTPServerResponse res) {
    access(req, res, false);
  }

  /// `POST /repo/native/upload/{path}`：Basic 令牌认证后把请求体写入仓库。
  void upload(HTTPServerRequest req, HTTPServerResponse res) {
    if (!authorized(req.headers.get("Authorization", ""), usertoken)) {
      res.writeBody("", HTTPStatus.forbidden);
      return;
    }

    auto path = resourcePath(req, uploadPrefix);
    auto tmpFile = tempUploadPath();
    scope (exit)
      if (exists(tmpFile))
        remove(tmpFile);

    auto output = File(tmpFile, "wb");
    try {
      auto buffer = new ubyte[64 * 1024];
      if (req.bodyReader !is null) {
        while (!req.bodyReader.empty) {
          auto n = req.bodyReader.read(buffer, IOMode.once);
          if (n == 0)
            break;
          output.rawWrite(buffer[0 .. n]);
        }
      }
    } finally {
      output.close();
    }

    auto result = repo.upload(tmpFile, path);
    if (result.ok) {
      res.writeBody("", HTTPStatus.ok);
    } else {
      logError("Native upload failed: %s", result.message);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }

  /// 管理台上传 WAR/JAR：multipart 字段 `warfile`，坐标来自 MANIFEST.MF。
  UploadResult uploadWar(HTTPServerRequest req, out string path) {
    auto file = "warfile" in req.files;
    if (file is null)
      return UploadResult(false, "没有发现上传的 war 文件");

    auto tmpFile = file.tempPath.toNativeString;
    string error;
    WarCoordinates coords;
    if (!readWarCoordinates(tmpFile, coords, error))
      return UploadResult(false, error);
    path = repositoryPath(coords, file.filename.name);
    return repo.upload(tmpFile, path);
  }

  private void access(HTTPServerRequest req, HTTPServerResponse res, bool headRequest) {
    auto path = resourcePath(req, nativePrefix);
    auto file = repo.resolve(path);
    if (file.length == 0) {
      res.writeBody("", HTTPStatus.notFound);
      return;
    }

    auto relative = repo.relativePath(file);
    if (headRequest) {
      if (path != relative)
        res.headers["latest"] = baseName(file);
      res.headers["Last-Modified"] = toRFC822DateTimeString(timeLastModifiedUtc(file));
      res.headers["Content-Type"] = "application/octet-stream";
      res.headers["Content-Length"] = getSize(file).to!string;
      res.statusCode = HTTPStatus.ok;
      // 只提交响应头；HEAD 的 body 由 HTTP 层丢弃
      res.bodyWriter;
      return;
    }

    if (path != relative) {
      res.redirect(nativePrefix ~ relative);
      return;
    }

    try {
      auto input = openFile(file);
      scope (exit) input.close();
      res.headers["Content-Type"] = "application/octet-stream";
      res.headers["Content-Length"] = input.size.to!string;
      input.pipe(res.bodyWriter);
    } catch (Exception e) {
      logError("Send native artifact %s failed: %s", file, e.msg);
      res.writeBody("", HTTPStatus.internalServerError);
    }
  }
}

private string resourcePath(HTTPServerRequest req, string prefix) {
  auto path = decodePath(req.requestPath.toString());
  if (!path.startsWith(prefix))
    return "";
  return path[prefix.length .. $];
}

/// URL 路径百分号解码；不把 `+` 当空格（构件名里的 `+` 必须保留）。
private string decodePath(string encoded) {
  auto decoded = appender!string;
  size_t i = 0;
  while (i < encoded.length) {
    if (encoded[i] == '%' && i + 2 < encoded.length && isHex(encoded[i + 1]) && isHex(encoded[i + 2])) {
      decoded.put(cast(char) ((hex(encoded[i + 1]) << 4) | hex(encoded[i + 2])));
      i += 3;
    } else {
      decoded.put(encoded[i]);
      i++;
    }
  }
  return decoded.data;
}

private bool isHex(char ch) {
  return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F');
}

private uint hex(char ch) {
  if (ch >= '0' && ch <= '9')
    return ch - '0';
  if (ch >= 'a' && ch <= 'f')
    return ch - 'a' + 10;
  return ch - 'A' + 10;
}

/// Basic 解码后必须与 `snapshot.usertoken` 完全相同。
private bool authorized(string header, string expected) {
  if (expected.length == 0 || !header.startsWith("Basic "))
    return false;
  try {
    auto decoded = cast(string) Base64.decode(strip(header[6 .. $]));
    return decoded == expected;
  } catch (Exception) {
    return false;
  }
}

private string tempUploadPath() {
  foreach (attempt; 0 .. 100) {
    auto path = buildPath(tempDir(), "bashub-native-" ~ unpredictableSeed.to!string ~ ".tmp");
    if (!exists(path))
      return path;
  }
  throw new Exception("cannot allocate native upload temp file");
}

private auto timeLastModifiedUtc(string file) {
  return timeLastModified(file).toUTC();
}
