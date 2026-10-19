/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.repo.native_test;
/// scala `NativeHelperTest` 的 D 版：仓库根、SNAPSHOT 解析、校验文件先到与路径安全。

import bashub.repo.native;

import test.beangle.tempdir : uniqueTempDir;

import std.file : exists, mkdirRecurse, read, rmdirRecurse, write;
import std.path : baseName, buildPath, dirName;

private enum string versionDirName = "4.20.14-SNAPSHOT";
private enum string distName = "beangle-ems-portal-4.20.14-SNAPSHOT-linux-amd64.tar.gz";
private enum string distPath = "org/beangle/beangle-ems-portal/" ~ versionDirName ~ "/" ~ distName;
private enum string releaseName = "beangle-ems-portal-4.20.13-linux-amd64.tar.gz";
private enum string releasePath = "org/beangle/beangle-ems-portal/4.20.13/" ~ releaseName;
private enum string validSha1 = "0123456789abcdef0123456789abcdef01234567";

@("releases use <home>/repository and snapshots use <home>/snapshots")
unittest {
  auto dir = uniqueTempDir("bashub-native-roots-");
  scope (exit) rmdirRecurse(dir);
  auto repo = new NativeRepo(dir);

  assert(repo.rootOf(distPath) == repo.snapshotRoot);
  assert(repo.rootOf(releasePath) == repo.repositoryRoot);
  assert(repo.fileOf(distPath) == buildPath(repo.snapshotRoot, distPath));
  assert(repo.fileOf(releasePath) == buildPath(repo.repositoryRoot, releasePath));

  auto source = buildPath(dir, "dist.tar.gz");
  write(source, "native distribution");
  auto result = repo.upload(source, releasePath);
  assert(result.ok, result.message);
  auto stored = buildPath(repo.repositoryRoot, releasePath);
  assert(exists(stored));
  assert(repo.relativePath(stored) == releasePath);
  assert(repo.relativePath(buildPath(repo.snapshotRoot, distPath)) == distPath);
}

@("a checksum can arrive before its artifact and is moved into place later")
unittest {
  auto dir = uniqueTempDir("bashub-native-pending-");
  scope (exit) rmdirRecurse(dir);
  auto repo = new NativeRepo(dir);

  auto source = buildPath(dir, "dist.tar.gz");
  write(source, "native distribution");
  auto checksum = buildPath(dir, "dist.sha1");
  write(checksum, validSha1);

  auto result = repo.upload(checksum, distPath ~ ".sha1");
  assert(result.ok, result.message);
  auto artifact = buildPath(repo.snapshotRoot, distPath);
  assert(!exists(artifact));
  auto pending = buildPath(repo.snapshotRoot, ".pending", distPath ~ ".sha1");
  assert(exists(pending));

  result = repo.upload(source, distPath);
  assert(result.ok, result.message);
  assert(exists(artifact));
  assert(!exists(pending));
  auto adjacent = buildPath(dirName(artifact), baseName(artifact) ~ ".sha1");
  assert(cast(string) read(adjacent) == validSha1);
}

@("checksum upload validates SHA-1 and paths stay inside the repository")
unittest {
  auto dir = uniqueTempDir("bashub-native-safe-");
  scope (exit) rmdirRecurse(dir);
  auto repo = new NativeRepo(dir);

  auto checksum = buildPath(dir, "bad.sha1");
  write(checksum, "not-a-sha1");
  auto result = repo.upload(checksum, distPath ~ ".sha1");
  assert(!result.ok);
  result = repo.upload(checksum, "../outside.tar.gz");
  assert(!result.ok);

  assert(isSafe(distPath));
  assert(!isSafe("/etc/passwd"));
  assert(!isSafe("org/../../etc/passwd"));
  assert(repo.resolve("../outside.tar.gz").length == 0);
}

@("a SNAPSHOT alias resolves to the newest timestamped artifact and delta")
unittest {
  auto dir = uniqueTempDir("bashub-native-alias-");
  scope (exit) rmdirRecurse(dir);
  auto repo = new NativeRepo(dir);
  auto versionDir = buildPath(repo.snapshotRoot, "org", "beangle", "beangle-ems-portal", versionDirName);

  auto oldDelta = "beangle-ems-portal-4.20.13_4.20.14-SNAPSHOT-20260912.101500-1-linux-amd64.tar.gz.diff";
  auto newDelta = "beangle-ems-portal-4.20.13_4.20.14-SNAPSHOT-20260913.101500-1-linux-amd64.tar.gz.diff";
  auto newDist = "beangle-ems-portal-4.20.14-SNAPSHOT-20260913.101500-1-linux-amd64.tar.gz";
  foreach (name; [oldDelta, newDelta, newDist])
    seedFile(buildPath(versionDir, name), name);

  assert(baseName(repo.resolve(distPath)) == newDist);
  assert(repo.resolve(distPath ~ ".sha1").length == 0);
  auto deltaAlias = "org/beangle/beangle-ems-portal/" ~ versionDirName ~ "/" ~ newDelta;
  assert(baseName(repo.resolve(deltaAlias)) == newDelta);
  assert(repo.relativePath(repo.resolve(distPath)) ==
      "org/beangle/beangle-ems-portal/" ~ versionDirName ~ "/" ~ newDist);

  seedFile(buildPath(versionDir, newDist ~ ".sha1"), validSha1);
  assert(baseName(repo.resolve(distPath ~ ".sha1")) == newDist ~ ".sha1");
}

@("snapshot build numbers compare numerically")
unittest {
  auto dir = uniqueTempDir("bashub-native-build-");
  scope (exit) rmdirRecurse(dir);
  auto repo = new NativeRepo(dir);
  auto versionDir = buildPath(repo.snapshotRoot, "org", "beangle", "beangle-ems-portal", versionDirName);
  auto build9 = "beangle-ems-portal-4.20.14-SNAPSHOT-20260913.101500-9-linux-amd64.tar.gz";
  auto build10 = "beangle-ems-portal-4.20.14-SNAPSHOT-20260913.101500-10-linux-amd64.tar.gz";
  seedFile(buildPath(versionDir, build9), build9);
  seedFile(buildPath(versionDir, build10), build10);
  assert(baseName(repo.resolve(distPath)) == build10);
}

private void seedFile(string path, string content) {
  mkdirRecurse(dirName(path));
  write(path, content);
}
