/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.project.manifest;
/// setline 远程配置清单。清单只暴露各资源的 SHA-256，agent 据此跳过未变化的下载。

import std.array : appender;
import std.digest : LetterCase, toHexString;
import std.digest.sha : sha256Of;

/// 计算与下载响应 Body 完全一致的 SHA-256 小写十六进制。
string sha256Hex(string text) {
  return toHexString!(LetterCase.lower)(sha256Of(text)).idup;
}

/// 输出稳定、无时间戳的清单，避免内容未变时 agent 反复更新状态。
string renderSetlineManifest(string peers, string proxy, string certificate, string certificateKey) {
  auto out_ = appender!string;
  out_.put("{\n");
  out_.put("  \"version\": 1,\n");
  out_.put("  \"resources\": {\n");
  out_.put(`    "certificate": "`);
  out_.put(sha256Hex(certificate));
  out_.put("\",\n");
  out_.put(`    "certificate-key": "`);
  out_.put(sha256Hex(certificateKey));
  out_.put("\",\n");
  out_.put(`    "peers": "`);
  out_.put(sha256Hex(peers));
  out_.put("\",\n");
  out_.put(`    "proxy": "`);
  out_.put(sha256Hex(proxy));
  out_.put("\"\n");
  out_.put("  }\n");
  out_.put("}\n");
  return out_.data;
}
