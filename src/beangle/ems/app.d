/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.ems.app;
/// 应用清单（scala `org.beangle.ems.app.EmsApp`）：`<ems app-name="platform-testwebapp"/>`
/// → 应用名与 path（`/platform/testwebapp`），供前端 `app_name`、blob/资源定位用。
///
/// 口径差别：scala 从 classpath 扫 `beangle.xml`，D 没有 classpath，改成「宿主把 XML 文本交进来」；
/// 只要文档里有 `<ems app-name=...>` 元素即可解析。
///
/// 没移植的部分（README 的裁剪清单里也记着）：`redis` 配置、blob 仓库、classpath/HTTP 取资源，
/// 以及清单值的 PBE 解密（命中 `ENC(...)` 就原样保留，见 `beangle.ems.datasource`）。
/// `${home}${path}.xml` 这份文件的读取入口是 `readAppFile`（scala `getAppFile`）；里面的
/// `<datasource>` 由 `beangle.ems.datasource` 解析。

import beangle.commons.xml : children, elementText, getAttrs, parseRoot;

import dxml.dom : DOMEntity;

import std.file : exists, read;
import std.string : replace, strip;
import std.typecons : Nullable;

/// 应用清单：名字、path 与合并出来的属性（scala `EmsApp.properties`）。
struct EmsApp {
  string name;
  /// path 一定以 `/` 开头（`platform-testwebapp` → `/platform/testwebapp`）
  string path;
  string[string] properties;
}

/// `platform-testwebapp` → `/platform/testwebapp`（scala `readProperties` 里那两行）
string appPathOf(string name) {
  return "/" ~ name.replace("-", "/").replace(".", "/");
}

/// scala `EmsApp.getAppFile` 的路径规则：`${home}${path}.xml`。
///
/// 用 `~` 拼而不是 `buildPath`：`path` 以 `/` 开头，`buildPath` 会把它当绝对路径吃掉前缀。
string appFilePath(string home, string appPath) {
  return home ~ appPath ~ ".xml";
}

/// 读 `${home}${path}.xml`；文件不存在返回空值（scala `EmsApp.getAppFile: Option[File]`）。
///
/// 单独给一个入口，是因为这份文件不只放清单属性：`<datasource>`（见 `beangle.ems.datasource`）
/// 等应用级配置都从它取——scala 侧应用从来不自己写库连接，认准这一份文件就够。
Nullable!string readAppFile(string home, string appPath) {
  auto file = appFilePath(home, appPath);
  if (!exists(file))
    return Nullable!string();
  return Nullable!string(cast(string) read(file));
}

/** 从 XML 文本里读第一个 `<ems app-name="...">` 与它的 `props/prop`；没有 app-name 就返回空值。
 *
 * scala 缺清单时是 `printStackTrace` + `System.exit(1)`；D 侧不该因为一份清单缺失就把进程带走，
 * 所以这里返回空 `Nullable`，由调用方决定退回什么缺省。
 */
Nullable!EmsApp readEmsApp(string xmlText) {
  auto root = parseRoot(xmlText);
  foreach (ems; children(root, "ems")) {
    auto name = getAttrs(ems).get("app-name", "").strip;
    if (name.length == 0)
      continue;
    EmsApp app;
    app.name = name;
    app.path = appPathOf(name);
    app.properties["name"] = name;
    mergeProps(app, ems);
    return Nullable!EmsApp(app);
  }
  return Nullable!EmsApp();
}

/** 在清单上叠加 `${home}${path}.xml` 的属性与 `props/prop`（scala `readProperties` 的后半段）。
 *
 * 用 `~` 拼而不是 `buildPath`：`path` 以 `/` 开头，`buildPath` 会把它当绝对路径直接吃掉前缀。
 * scala 侧合并之后还会用 `Ems.decryptor` 把每个值解一遍密文，D 侧没移植 PBE，值原样保留。
 */
Nullable!EmsApp mergeAppFile(Nullable!EmsApp manifest, string home) {
  if (manifest.isNull)
    return manifest;
  auto app = manifest.get;
  auto file = appFilePath(home, app.path);
  if (!exists(file))
    return Nullable!EmsApp(app);
  auto root = parseRoot(cast(string) read(file));
  foreach (key, value; getAttrs(root))
    app.properties[key] = value.strip;
  mergeProps(app, root);
  return Nullable!EmsApp(app);
}

/// 把 `props/prop` 折进清单属性（清单元素与 `${home}${path}.xml` 这两处形状一样，抽出来共用）
private void mergeProps(T)(ref EmsApp app, ref DOMEntity!T node) {
  foreach (props; children(node, "props")) {
    foreach (prop; children(props, "prop")) {
      auto key = getAttrs(prop).get("key", "").strip;
      if (key.length > 0)
        app.properties[key] = prop.elementText.strip;
    }
  }
}
