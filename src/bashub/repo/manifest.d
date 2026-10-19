/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.repo.manifest;
/// WAR/JAR 上传的坐标推导：从 `META-INF/MANIFEST.MF` 的 `Implementation-*`
/// 读取 groupId / artifactId / version，再拼出仓库里的相对路径。

import std.file : read;
import std.path : baseName;
import std.string : indexOf, replace, splitLines, strip;
import std.zip : ZipArchive;

/// MANIFEST.MF 中与仓库坐标对应的三项。
struct WarCoordinates {
  string groupId;
  string artifactId;
  string artifactVersion;
}

/// 读取构件坐标；找不到 MANIFEST 或缺字段时返回 false，并在 `error` 里说明原因。
bool readWarCoordinates(string file, out WarCoordinates coords, out string error) {
  try {
    auto zip = new ZipArchive(read(file));
    foreach (member; zip.directory) {
      if (baseName(member.name) != "MANIFEST.MF")
        continue;
      parseManifest(cast(string) zip.expand(member), coords);
      if (coords.groupId.length == 0 || coords.artifactId.length == 0 || coords.artifactVersion.length == 0) {
        error = "MANIFEST.MF 中缺少 Implementation-Vendor-Id/Implementation-Title/Implementation-Version";
        return false;
      }
      return true;
    }
    error = "上传的文件中没有找到 MANIFEST.MF";
    return false;
  } catch (Exception e) {
    error = "读取构件失败: " ~ e.msg;
    return false;
  }
}

/// 仓库相对路径：`groupId 的点换成目录 / artifactId / version / 原始文件名`。
string repositoryPath(WarCoordinates coords, string fileName) {
  return coords.groupId.replace(".", "/") ~ "/" ~ coords.artifactId ~ "/" ~ coords.artifactVersion ~ "/" ~
    baseName(fileName);
}

private void parseManifest(string text, ref WarCoordinates coords) {
  foreach (line; text.splitLines) {
    auto colon = line.indexOf(':');
    if (colon < 0)
      continue;
    auto key = line[0 .. colon].strip;
    auto value = line[colon + 1 .. $].strip;
    if (key == "Implementation-Vendor-Id")
      coords.groupId = value;
    else if (key == "Implementation-Title")
      coords.artifactId = value;
    else if (key == "Implementation-Version")
      coords.artifactVersion = value;
  }
}
