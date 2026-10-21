/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.api;
/// bashub 的 API 能力域。所有端点都挂在 `/api/bashub/{group}` 下：
///
///   - `ems`     管理台资源、会话与 EMS 菜单
///   - `config`  平台配置资源、server.xml、代理、证书、setline 与主机脚本
///   - `micdn`   micdn.xml、Profile 聚合配置与组件目录
///   - `monitor` 在线节点、日志、上报与实例启停
///
/// 前缀只在装配路由时计算一次，处理器里不再手写 `/api/bashub/...`。

import std.algorithm.searching : canFind;
import std.string : strip;

/// 能力域段的登记顺序；新增能力域时同时扩展 `ApiPrefixes` 与路由装配。
enum string[] hubApiGroupNames = ["ems", "config", "micdn", "monitor"];

/// 只有 EMS 自身的数据放在 `/api/bashub/ems`；平台配置资源都放在 `/api/bashub/config`。
enum string[] emsResourcePaths = ["channels", "menus", "resources"];

struct ApiPrefixes {
  string root;
  string ems;
  string config;
  string micdn;
  string monitor;
}

/// 根前缀 → 四个能力域。末尾多余的 `/` 会去掉，避免拼出双斜杠。
ApiPrefixes hubApiPrefixes(string root) {
  auto base = normalizeApiRoot(root);
  return ApiPrefixes(base, base ~ "/ems", base ~ "/config", base ~ "/micdn", base ~ "/monitor");
}

/// 去掉首尾空白与末尾斜杠；空值回落到 bashub 的默认根前缀。
string normalizeApiRoot(string root) {
  auto base = root.strip;
  while (base.length > 1 && base[$ - 1] == '/')
    base = base[0 .. $ - 1];
  if (base.length == 0)
    base = "/api/bashub";
  return base;
}

/// 是否是可识别的 API 能力域；鉴权按域后的第一个资源段收口。
bool isApiGroup(string segment) {
  return hubApiGroupNames.canFind(segment);
}

/// 资源是否属于 EMS 能力域。菜单导入导出等专用端点也沿用同一判定。
bool isEmsResource(string path) {
  return emsResourcePaths.canFind(path);
}
