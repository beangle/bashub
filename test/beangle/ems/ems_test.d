/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.ems.ems_test;
/// security 侧真正会取的那几个常量：会话 cookie 名、cas 地址、hostname、头像地址。

import beangle.ems : Ems, emsFromEnvironment, loadEms, md5Hex;

import std.base64 : Base64URLNoPadding;

@("sid 的缺省与覆盖（cookie 名不许别处再硬编码）")
unittest {
  auto ems = loadEms("/tmp/ems", ["base": "localhost"]);
  assert(ems.sid.name == "EMS_SID");
  assert(ems.sid.prefix == "EMS-");

  auto custom = loadEms("/tmp/ems", ["session_id_name": "OpenURP_SID", "session_id_prefix": "S-"]);
  assert(custom.sid.name == "OpenURP_SID");
  assert(custom.sid.prefix == "S-");
}

@("hostname、api/innerApi 与 isPlatform")
unittest {
  auto ems = loadEms("/tmp/ems", ["base": "https://sas.openurp.net:8443/"]);
  assert(ems.hostname == "sas.openurp.net:8443");
  assert(ems.api == "https://sas.openurp.net:8443/api");
  assert(ems.innerApi == ems.api);
  assert(ems.isPlatform("/cas"));
  assert(ems.isPlatform("/api/platform"));
  assert(ems.isPlatform("/portal"));
  assert(!ems.isPlatform("/api/bashub"));
}

@("avatarUrl 是 md5 的小写 hex（对齐 scala EmsTest 钉的形态）")
unittest {
  auto ems = loadEms("/tmp/ems", ["base": "https://sas.openurp.net"]);
  assert(md5Hex("admin") == "21232f297a57a5a743894a0e4a801fc3");
  assert(ems.avatarUrl("admin") ==
      "https://sas.openurp.net/api/platform/user/avatars/21232f297a57a5a743894a0e4a801fc3");
}

@("generateKey：32 字节随机、base64url 无 padding、两次不同")
unittest {
  auto a = Ems.generateKey();
  auto b = Ems.generateKey();
  assert(a != b);
  assert(a.length >= 32);
  assert(Base64URLNoPadding.decode(a).length == 32);
}

@("emsFromEnvironment：一个 ems.* 都没配就是 null（别偷偷改宿主行为）")
unittest {
  assert(emsFromEnvironment(["HOME": "/root"]) is null);
  assert(emsFromEnvironment(["ems.home": ""]) is null);

  auto ems = emsFromEnvironment(["ems.base": "/data/ems", "ems.profile": "bas"]);
  assert(ems !is null);
  assert(ems.base == "http://localhost"); // 那个目录下没有 conf.properties，全走缺省
  assert(ems.sid.name == "EMS_SID");
}
