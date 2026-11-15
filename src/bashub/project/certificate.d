/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

/// PEM X.509 证书的 notAfter 读取。只依赖 DER 结构，不启动 openssl。
module bashub.project.certificate;

import std.ascii : isDigit;
import std.base64 : Base64;
import std.string : indexOf, replace, strip;

/// 读取 PEM 中第一张证书的 notAfter，返回 `YYYY-MM-DDTHH:MM:SSZ`。
/// 证书链只取第一张；格式无法识别时返回空串，由调用方允许人工填写。
string certificateNotAfter(string pem) {
  auto begin = pem.indexOf("-----BEGIN CERTIFICATE-----");
  if (begin < 0)
    return "";
  auto bodyStart = begin + "-----BEGIN CERTIFICATE-----".length;
  auto end = pem.indexOf("-----END CERTIFICATE-----", bodyStart);
  if (end < 0)
    return "";
  auto body = pem[bodyStart .. end].replace("\r", "").replace("\n", "").replace(" ", "").strip;
  if (body.length == 0)
    return "";
  try {
    auto der = Base64.decode(body);
    return notAfterFromDer(der);
  } catch (Exception) {
    return "";
  }
}

private struct Tlv {
  ubyte tag;
  size_t start;
  size_t end;
}

/// 读取一个 DER TLV；越界或长度非法时抛异常。
private Tlv readTlv(const(ubyte)[] der, size_t offset) {
  if (offset + 2 > der.length)
    throw new Exception("truncated DER");
  auto tag = der[offset];
  auto pos = offset + 1;
  auto first = der[pos++];
  size_t length;
  if (first < 0x80)
    length = first;
  else {
    auto count = first & 0x7f;
    if (count == 0 || count > 4 || pos + count > der.length)
      throw new Exception("invalid DER length");
    foreach (_; 0 .. count)
      length = (length << 8) | der[pos++];
  }
  if (pos + length > der.length)
    throw new Exception("truncated DER value");
  return Tlv(tag, pos, pos + length);
}

private string notAfterFromDer(const(ubyte)[] der) {
  auto certificate = readTlv(der, 0);
  if (certificate.tag != 0x30)
    return "";
  auto tbs = readTlv(der, certificate.start);
  if (tbs.tag != 0x30)
    return "";
  auto pos = tbs.start;
  auto first = readTlv(der, pos);
  // [0] version 可选；没有它时第一项是 serial。
  if (first.tag == 0xa0)
    pos = first.end;
  auto serial = readTlv(der, pos);
  if (serial.tag != 0x02)
    return "";
  pos = serial.end;
  auto signature = readTlv(der, pos);
  if (signature.tag != 0x30)
    return "";
  pos = signature.end;
  auto issuer = readTlv(der, pos);
  if (issuer.tag != 0x30)
    return "";
  pos = issuer.end;
  auto validity = readTlv(der, pos);
  if (validity.tag != 0x30)
    return "";
  auto notBefore = readTlv(der, validity.start);
  if (notBefore.tag != 0x17 && notBefore.tag != 0x18)
    return "";
  auto notAfter = readTlv(der, notBefore.end);
  if (notAfter.tag != 0x17 && notAfter.tag != 0x18)
    return "";
  return parseTime(der[notAfter.start .. notAfter.end], notAfter.tag == 0x17);
}

private string parseTime(const(ubyte)[] raw, bool utc) {
  string text;
  foreach (ch; raw)
    text ~= cast(char) ch;
  if (!text.endsWith("Z"))
    return "";
  text = text[0 .. $ - 1];
  string year;
  string rest;
  if (utc) {
    if (text.length != 12 && text.length != 10)
      return "";
    auto yy = text[0 .. 2];
    auto value = yy.to!int;
    year = value >= 50 ? "19" ~ yy : "20" ~ yy;
    rest = text[2 .. $];
  } else {
    if (text.length != 14 && text.length != 12)
      return "";
    year = text[0 .. 4];
    rest = text[4 .. $];
  }
  foreach (ch; year ~ rest)
    if (!isDigit(ch))
      return "";
  if (rest.length != 10 && rest.length != 8)
    return "";
  auto month = rest[0 .. 2];
  auto day = rest[2 .. 4];
  auto hour = rest[4 .. 6];
  auto minute = rest[6 .. 8];
  auto second = rest.length == 10 ? rest[8 .. 10] : "00";
  return year ~ "-" ~ month ~ "-" ~ day ~ "T" ~ hour ~ ":" ~ minute ~ ":" ~ second ~ "Z";
}

// `to!int`/`endsWith` 只在内部小工具里用，避免主模块引入无关依赖。
private import std.conv : to;
private import std.string : endsWith;

unittest {
  // 只验证明文时间解析；真实 PEM 在 route 测试中用动态生成证书覆盖。
  auto utc = parseTime(cast(const(ubyte)[]) "250101000000Z", true);
  assert(utc == "2025-01-01T00:00:00Z");
  auto generalized = parseTime(cast(const(ubyte)[]) "20500101000000Z", false);
  assert(generalized == "2050-01-01T00:00:00Z");
}
