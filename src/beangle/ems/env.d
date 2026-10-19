/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.ems.env;
/// ems 的部署常量（scala `org.beangle.ems.app.EmsEnv`）：一个 home + 一份 `conf.properties`
/// 推出 base/cas/portal/index/api/blob/webapp/static/key 与两个会话 cookie 常量。
///
/// 为什么 D 侧要再算一遍：security 侧真正需要的量（cookie 名、cas 地址，见 `Ems.sid`）原来靠宿主
/// 应用手填，两边部署一改就对不上；这里照 scala 的规则推导，宿主只要给一个 home。
///
/// 两处不得不改的口径：scala 读 JVM 系统属性（`-Dems.home`），D 没有系统属性，改读同名环境变量；
/// scala 会 `System.setProperty("ems.profile", profile)`，D 只把 profile 留在字段里（没有属性可设）。

import beangle.commons.io.javaprops : parseJavaProperties;

import std.file : SpanMode, dirEntries, exists, isDir, read;
import std.path : baseName, buildPath;
import std.process : environment;
import std.string : endsWith, replace, startsWith;

import vibe.core.log : logWarn;

/// ems 的部署环境（scala `EmsEnv` 的 12 个字段，一一对应）。
struct EmsEnv {
  string home;
  string profile;
  string base;
  string cas;
  string portal;
  string index;
  string api;
  string blob;
  string webapp;
  /// scala 里这个字段叫 `static`，D 的关键字冲突所以改名
  string staticUrl;
  string key;
  /// `conf.properties` 原文（scala 也挂在 env 上，sid 之类都从它取）
  string[string] properties;
}

/// 进程环境变量表（`std.process.environment` 的 AA 形态，便于测试注入一份假的）。
string[string] processEnv() {
  return environment.toAA();
}

/// 定位 `ems.home`：优先同名环境变量，其次 `ems.base`（缺省 `~/.ems`）下的一个 profile 目录。
/// profile 用 `ems.profile` 指定；没指定就取第一个，一个都没有就退回 `local`（与 scala `findHome` 同规则）。
string findHome(string[string] vars) {
  auto home = vars.get("ems.home", null);
  if (home !is null && home.length > 0)
    return home;

  auto base = vars.get("ems.base", null);
  if (base is null || base.length == 0) {
    auto userHome = vars.get("HOME", null);
    if (userHome is null || userHome.length == 0)
      userHome = ".";
    base = buildPath(userHome, ".ems");
  }

  auto profile = vars.get("ems.profile", null);
  if (profile !is null && profile.length > 0)
    return buildPath(base, profile);

  auto profiles = listProfiles(base);
  if (profiles.length == 0) {
    logWarn("Cannot find ems.profile in %s, using local", base);
    return buildPath(base, "local");
  }
  if (profiles.length > 1)
    logWarn("Choose first of %s, set ems.profile to select one", profiles);
  return buildPath(base, profiles[0]);
}

/// 一个 base 下的 profile 候选。只认目录——scala 取的是 `list()` 的第一个元素，撞上文件就直接坏掉。
private string[] listProfiles(string base) {
  if (!exists(base) || !isDir(base))
    return null;
  string[] dirs;
  foreach (entry; dirEntries(base, SpanMode.shallow)) {
    if (entry.isDir)
      dirs ~= entry.name.baseName;
  }
  return dirs;
}

/// 读 `home/conf.properties`；文件不存在就是空表（scala 同口径：不报错，全部走缺省）。
string[string] readConfig(string home) {
  auto file = buildPath(home, "conf.properties");
  if (!exists(file))
    return null;
  return parseJavaProperties(cast(string) read(file));
}

/// 由 base 与 properties 推出整套地址（scala `EmsEnv.readEnv`）。
EmsEnv readEnv(string home, string base, string[string] properties) {
  auto reader = PropertyReader(base, properties);
  EmsEnv env;
  env.home = home;
  env.profile = baseName(home); // scala 从 home 末段推 profile，同时回写 JVM 系统属性
  env.base = base;
  env.cas = reader.find("cas", "{base}/cas");
  env.portal = reader.find("portal", "{base}/portal");
  env.index = reader.find("index", "{base}/portal");
  env.api = reader.find("api", "{base}/api");
  env.blob = reader.find("blob", "{base}/blob");
  env.webapp = reader.find("webapp", "{base}");
  env.staticUrl = reader.find("static", "{base}/static");
  env.key = reader.readKey();
  env.properties = properties;
  return env;
}

/// scala `EmsEnv.apply`：base 从 properties 里读（缺省 `http://localhost`）。
EmsEnv loadEnv(string home, string[string] properties) {
  return readEnv(home, readBase(properties), properties);
}

/// scala `EmsEnv.inner`：配了 `inner_base` 就按它再推一遍（内网地址与对外地址不同时用）。
EmsEnv innerEnv(EmsEnv env) {
  auto innerBase = env.properties.get("inner_base", null);
  if (innerBase is null || innerBase.length == 0)
    return env;
  return readEnv(env.home, normalize(innerBase), env.properties);
}

private string readBase(string[string] properties) {
  auto base = properties.get("base", null);
  if (base is null || base.length == 0) {
    logWarn("Cannot find base in conf.properties, using http://localhost");
    return "http://localhost";
  }
  return normalize(base);
}

/// 去掉末尾多写的斜杠；不是 `http` 开头就补 `http://`（scala `normalize`）。
private string normalize(string value) {
  auto url = value;
  if (url.endsWith("/"))
    url = url[0 .. $ - 1];
  if (!url.startsWith("http"))
    url = "http://" ~ url;
  return url;
}

/// scala `PropertyReader`：properties 里给了就用它，否则用 `{base}` 模板；末尾斜杠去掉、补 `http://`。
struct PropertyReader {
  string base;
  string[string] properties;

  string find(string name, string defaults) {
    auto result = properties.get(name, null);
    if (result is null)
      result = defaults.replace("{base}", base);
    if (result.endsWith("/"))
      result = result[0 .. $ - 1];
    if (!result.startsWith("http"))
      result = "http://" ~ result;
    return result;
  }

  /// 缺省 `ems`（scala `readKey`）
  string readKey() {
    return properties.get("key", "ems");
  }
}
