/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.commons.sysprops;
/// 「系统属性」在 D 侧的对应物：scala 那边是 JVM 的 `-Dk=v` 加 `System.getenv`，D 没有属性表，
/// 于是约定**进程入口**把 D 风格的长选项收成一张表，和环境变量合成一份，命令行选项覆盖同名
/// 环境变量——这样「临时换一套 ems 部署跑一次」不必去改环境变量。
///
/// 与 JVM 的差别：JVM 的属性表与 env 是两张互不相干的表（scala 只读属性表），
/// 这里干脆合成一张，取值处只要问「这个键配了没有」。

import std.process : environment;

/// 环境变量 + 命令行选项（后者覆盖前者）。`vars` 为空时取当前进程环境，测试可以注入一份假的。
string[string] systemVars(string[string] options, string[string] vars = null) {
  string[string] merged = (vars is null) ? environment.toAA() : vars.dup;
  foreach (key, value; options)
    merged[key] = value;
  return merged;
}
