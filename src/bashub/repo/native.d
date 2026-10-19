/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.repo.native;
/// 原生发行包仓库（scala `NativeHelper`）：native-image 产物、增量补丁及其 SHA-1 校验文件。
///
/// 正式版落在 `<home>/repository`，路径里版本目录带 `-SNAPSHOT` 的落在 `<home>/snapshots`；
/// `home` 缺省是 `~/.m2`。构件坐标完全由上传路径决定，没有 pom/metadata 可解析。

import std.algorithm.searching : endsWith, startsWith;
import std.conv : to;
import std.file : SpanMode, copy, dirEntries, exists, isDir, mkdirRecurse, read, remove, rename;
import std.path : absolutePath, baseName, buildPath, dirName, expandTilde;
import std.string : lastIndexOf, replace, split, strip;

import vibe.core.log : logError, logInfo;

private enum string checksumSuffix = ".sha1";
private enum string snapshotMark = "-SNAPSHOT";
private enum size_t stampLength = 15; // yyyyMMdd.HHmmss

/// 上传结果：`ok` 与给 HTTP 层/调用方看的错误说明。
struct UploadResult {
  bool ok;
  string message;
}

/// `yyyyMMdd.HHmmss-N`，先比定长时间戳，再比构建号数值。
private struct SnapshotStamp {
  string text;
  ulong build;
}

/** 本地原生发行包仓库。 */
class NativeRepo {
  /// 仓库 home；真实根是它的 `repository` / `snapshots` 子目录。
  const string home;

  this(string home) {
    if (home.length == 0)
      throw new Exception("native repository home must not be empty");
    this.home = absolutePath(expandTilde(home));
  }

  /// scala `NativeHelper.default`：`~/.m2`。
  static NativeRepo defaultRepo() {
    return new NativeRepo("~/.m2");
  }

  /// 正式版本（非 SNAPSHOT）根：`<home>/repository`。
  string repositoryRoot() const {
    return buildPath(home, "repository");
  }

  /// 开发版根：`<home>/snapshots`。
  string snapshotRoot() const {
    return buildPath(home, "snapshots");
  }

  /// 按版本目录名选择仓库根；没有 `-SNAPSHOT` 就走正式仓库。
  string rootOf(string path) const {
    return parentOf(path).endsWith(snapshotMark) ? snapshotRoot() : repositoryRoot();
  }

  /// 仓库内相对路径 → 绝对文件路径。
  string fileOf(string path) const {
    return buildPath(rootOf(path), path);
  }

  /// 仓库内相对路径（用作下载 URL）；不在两个根下的文件只返回文件名。
  string relativePath(string file) const {
    auto absolute = absolutePath(file);
    foreach (root; [repositoryRoot(), snapshotRoot()]) {
      auto prefix = root ~ "/";
      if (absolute.startsWith(prefix))
        return absolute[prefix.length .. $].replace("\\", "/");
    }
    return baseName(file);
  }

  /** 解析请求路径：直接存在的文件优先；否则按 `-SNAPSHOT` 别名找最新时间戳文件。
   *
   * 返回空串表示不存在或路径非法（与 scala `resolve(): Option[File]` 的 None 同口径）。
   */
  string resolve(string path) const {
    if (!isSafe(path))
      return null;
    auto direct = fileOf(path);
    if (exists(direct))
      return direct;

    string artifactPath = path;
    string suffix;
    if (isChecksum(path)) {
      artifactPath = path[0 .. $ - checksumSuffix.length];
      suffix = checksumSuffix;
    }
    auto artifact = findLatest(artifactPath);
    if (artifact.length == 0)
      return null;
    auto target = artifact ~ suffix;
    return exists(target) ? target : null;
  }

  /** 查找最新时间戳构件，如 `x-1.0-SNAPSHOT-linux-amd64.tar.gz` →
   * `x-1.0-SNAPSHOT-20260913.101500-1-linux-amd64.tar.gz`。
   */
  string findLatest(string path) const {
    auto file = fileOf(path);
    auto name = baseName(file);
    auto anchor = name.lastIndexOf(snapshotMark);
    if (anchor < 0)
      return null;
    auto dir = dirName(file);
    if (!exists(dir) || !isDir(dir))
      return null;

    auto prefix = name[0 .. anchor + snapshotMark.length] ~ "-";
    auto suffix = name[anchor + snapshotMark.length .. $];
    string best;
    SnapshotStamp bestStamp;
    foreach (entry; dirEntries(dir, SpanMode.shallow)) {
      if (entry.isDir)
        continue;
      auto candidate = baseName(entry.name);
      if (candidate.length <= prefix.length + suffix.length)
        continue;
      if (!candidate.startsWith(prefix) || !candidate.endsWith(suffix))
        continue;
      SnapshotStamp stamp;
      if (!parseStamp(candidate[prefix.length .. candidate.length - suffix.length], stamp))
        continue;
      if (best.length == 0 || compareStamp(bestStamp, stamp) < 0) {
        best = candidate;
        bestStamp = stamp;
      }
    }
    return best.length == 0 ? null : buildPath(dir, best);
  }

  /** 上传临时文件到仓库相对路径。SHA-1 先到时暂存在 `.pending`，构件到达后归位。 */
  UploadResult upload(string tmpFile, string path) const {
    if (!isSafe(path)) {
      logError("Failed upload %s due to illegal path", path);
      return UploadResult(false, "非法的上传路径");
    }
    return isChecksum(path) ? uploadChecksum(tmpFile, path) : uploadArtifact(tmpFile, path);
  }

  private UploadResult uploadChecksum(string tmpFile, string path) const {
    auto sha1 = strip(cast(string) read(tmpFile));
    if (!isSha1Hex(sha1)) {
      logError("Failed upload %s due to invalid SHA-1", path);
      return UploadResult(false, "不是合法的SHA-1校验文件");
    }
    auto artifactPath = path[0 .. $ - checksumSuffix.length];
    auto target = exists(fileOf(artifactPath))
      ? fileOf(path)
      : buildPath(pendingDir(path), path);
    saveChecksum(tmpFile, target);
    return UploadResult(true, "上传成功");
  }

  private UploadResult uploadArtifact(string tmpFile, string path) const {
    auto target = fileOf(path);
    mkdirRecurse(dirName(target));
    copy(tmpFile, target);
    movePendingChecksum(path, target);
    logInfo("Upload %s", target);
    return UploadResult(true, "上传成功");
  }

  /// 构件尚未上传时 SHA-1 的暂存目录，内部保持与仓库一致的目录结构。
  private string pendingDir(string path) const {
    return buildPath(rootOf(path), ".pending");
  }

  private void saveChecksum(string tmpFile, string target) const {
    mkdirRecurse(dirName(target));
    copy(tmpFile, target);
    logInfo("Upload %s", target);
  }

  /// 构件上传后，把先前暂存的 `.sha1` 移动到构件旁（scala `movePendingChecksum`）。
  private void movePendingChecksum(string path, string artifact) const {
    auto pending = buildPath(pendingDir(path), path ~ checksumSuffix);
    if (!exists(pending))
      return;
    auto target = buildPath(dirName(artifact), baseName(artifact) ~ checksumSuffix);
    if (exists(target))
      remove(target);
    rename(pending, target);
    logInfo("Upload %s", target);
  }
}

/// SHA-1 校验文件：`xxx.tar.gz.sha1`、`xxx.tar.gz.diff.sha1`。
bool isChecksum(string path) {
  return path.endsWith(checksumSuffix);
}

/// 上传/下载路径必须是仓库内相对路径：拒绝绝对路径和任意层 `..`。
bool isSafe(string path) {
  if (path.length == 0 || path.startsWith("/") || path.startsWith("\\"))
    return false;
  foreach (ch; path)
    if (ch == '\0')
      return false;
  foreach (segment; path.replace("\\", "/").split("/"))
    if (segment == "..")
      return false;
  return true;
}

private string parentOf(string path) {
  auto index = path.lastIndexOf('/');
  return index < 0 ? "" : path[0 .. index];
}

private bool isSha1Hex(string value) {
  if (value.length != 40)
    return false;
  foreach (ch; value)
    if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')))
      return false;
  return true;
}

private bool parseStamp(string text, out SnapshotStamp stamp) {
  if (text.length < stampLength + 2)
    return false;
  foreach (i; 0 .. 8)
    if (!isDigit(text[i]))
      return false;
  if (text[8] != '.')
    return false;
  foreach (i; 9 .. stampLength)
    if (!isDigit(text[i]))
      return false;
  if (text[stampLength] != '-')
    return false;
  if (text.length - stampLength - 1 > 9)
    return false;
  foreach (i; stampLength + 1 .. text.length)
    if (!isDigit(text[i]))
      return false;
  stamp.text = text;
  stamp.build = text[stampLength + 1 .. $].to!ulong;
  return true;
}

private bool isDigit(char ch) {
  return ch >= '0' && ch <= '9';
}

private int compareStamp(SnapshotStamp a, SnapshotStamp b) {
  auto left = a.text[0 .. stampLength];
  auto right = b.text[0 .. stampLength];
  if (left < right)
    return -1;
  if (left > right)
    return 1;
  return a.build < b.build ? -1 : (a.build > b.build ? 1 : 0);
}
