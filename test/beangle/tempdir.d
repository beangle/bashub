/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.tempdir;
/// 测试用的唯一临时目录。这份 Phobos（2.112）没有 `std.file.mkdirTempDir`，
/// 而用例要的是「建好、用完删掉、并发跑不打架」，所以自己起一个名字。

import std.conv : to;
import std.file : exists, mkdirRecurse, tempDir;
import std.random : unpredictableSeed;

/// 在系统临时目录下建一个唯一目录，返回其绝对路径。
string uniqueTempDir(string prefix) {
  auto base = tempDir();
  foreach (attempt; 0 .. 100) {
    auto dir = base ~ "/" ~ prefix ~ unpredictableSeed.to!string;
    if (!exists(dir)) {
      mkdirRecurse(dir);
      return dir;
    }
  }
  throw new Exception("cannot create a temp dir under " ~ base);
}
