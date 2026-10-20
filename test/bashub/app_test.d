/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.app_test;

import bashub.app : createDao, parseArgs;
import bashub.config : HubConfig, applyListenOverride;

import beangle.data.dao : DaoException;

import std.algorithm : canFind;
import std.getopt : GetOptException;

@("a missing database is a startup error, not an in-memory fallback") unittest {
  try {
    createDao(HubConfig());
    assert(false, "createDao must reject a missing database");
  } catch (DaoException error) {
    assert(error.msg.canFind("no database configured"));
    assert(error.msg.canFind("--ems.profile"));
  }
}

@("D-style command line options are parsed and removed from vibe arguments") unittest {
  auto parsed = parseArgs(["bashub", "--check-schema",
      "--listen=0.0.0.0:8888", "--ems.profile=bas", "--ems.home", "/data/ems/bas", "--ems.base=/tmp/ems"]);
  assert(parsed.checkSchema);
  assert(parsed.listen == "0.0.0.0:8888");
  assert(parsed.options["ems.profile"] == "bas");
  assert(parsed.options["ems.home"] == "/data/ems/bas");
  assert(parsed.options["ems.base"] == "/tmp/ems");
  assert(parsed.rest == ["bashub"]);
}

@("JVM-style -D options are rejected") unittest {
  try {
    parseArgs(["bashub", "-Dems.profile=bas"]);
    assert(false, "parseArgs must reject -D options");
  } catch (GetOptException error) {
    assert(error.msg.canFind("-Dems.profile=bas"));
  }
}

@("command-line listen overrides the application file value") unittest {
  HubConfig cfg;
  cfg.listen = "10.0.0.8:8080";
  applyListenOverride(cfg, "0.0.0.0:8888");
  assert(cfg.listen == "0.0.0.0:8888");
  applyListenOverride(cfg, "");
  assert(cfg.listen == "0.0.0.0:8888");
}
