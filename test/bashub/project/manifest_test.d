/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.project.manifest_test;

import bashub.project.manifest : renderSetlineManifest, sha256Hex;

import vibe.data.json : parseJson;

@("setline manifest hashes every downloadable response deterministically") unittest {
  auto text = renderSetlineManifest("peers\n", "proxy\n", "certificate\n", "key\n");
  assert(text == renderSetlineManifest("peers\n", "proxy\n", "certificate\n", "key\n"));
  auto root = parseJson(text);
  assert(root["version"].get!int == 1);
  assert(root["resources"]["peers"].get!string == sha256Hex("peers\n"));
  assert(root["resources"]["proxy"].get!string == sha256Hex("proxy\n"));
  assert(root["resources"]["certificate"].get!string == sha256Hex("certificate\n"));
  assert(root["resources"]["certificate-key"].get!string == sha256Hex("key\n"));
  assert(root["resources"]["peers"].get!string.length == 64);
}
