/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.commons.sysprops_test;

import beangle.commons.sysprops : systemVars;

@("systemVars：命令行选项覆盖环境变量，且不动传进来的那份表")
unittest {
  auto vars = ["ems.profile": "local", "PATH": "/usr/bin"];
  auto merged = systemVars(["ems.profile": "bas"], vars);
  assert(merged["ems.profile"] == "bas");
  assert(merged["PATH"] == "/usr/bin");
  assert(vars["ems.profile"] == "local");
}
