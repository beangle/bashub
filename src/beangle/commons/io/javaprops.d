/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.commons.io.javaprops;
/// `java.util.Properties` 文本格式的解析（scala `org.beangle.commons.io.IOs.readJavaProperties` 的 D 版）。
///
/// 为什么要自己写：ems 的 `conf.properties` 就是这个格式，scala 侧用 `Properties.load(InputStream)` 读，
/// 它的口径是「每个字节当一个 Latin-1 字符」+ `\uXXXX` 转义 + `\` 续行，而 D 的标准库没有对应的解析器
/// （`std.utf`/`std.csv`/`std.json` 都不是这个语义）。这里按 JDK `Properties.load0`/`LineReader` 的
/// 规则实现，转义、续行、注释的边界都与它一致——配置文件是两边共用的，差一个转义就是两套配置。
///
/// 与 JDK 一样只认 Latin-1：非 ASCII 的值请写成 `\uXXXX`（UTF-8 的中文在这里会被当字节读）。

import std.array : appender;
import std.conv : to;
import std.string : indexOf;
import std.utf : encode;

/// `Properties` 认的空白：只有这三种；`\n`/`\r` 是行分隔符，不算键值之间的空白。
private bool isSpaceChar(char c) @safe pure nothrow {
  return c == ' ' || c == '\t' || c == '\f';
}

/** 解析 `Properties` 文本；返回的 key/value 都是解转义之后的字符串（键值不会带 `\` 残留）。
 *
 * 重复的键以后者为准（JDK 的 `put` 语义），空文档返回空表。
 */
string[string] parseJavaProperties(string text) {
  string[string] props;
  foreach (line; logicalLines(text)) {
    size_t limit = line.length;
    // 先找键的结尾：第一个未转义的 `=`/`:`/空白；转义过的分隔符（`a\:b`）留在键里
    size_t keyLen = 0;
    size_t valueStart = limit;
    bool hasSep = false;
    bool precedingBackslash = false;
    while (keyLen < limit) {
      char c = line[keyLen];
      if (!precedingBackslash && (c == '=' || c == ':')) {
        valueStart = keyLen + 1;
        hasSep = true;
        break;
      }
      if (!precedingBackslash && isSpaceChar(c)) {
        valueStart = keyLen + 1;
        break;
      }
      precedingBackslash = (c == '\\') ? !precedingBackslash : false;
      keyLen++;
    }
    // 值前面的任意空白 + 至多一个分隔符：`key = value`、`key : value`、`key value` 等价
    while (valueStart < limit) {
      char c = line[valueStart];
      if (!isSpaceChar(c)) {
        if (!hasSep && (c == '=' || c == ':'))
          hasSep = true;
        else
          break;
      }
      valueStart++;
    }
    props[unescape(line[0 .. keyLen])] = unescape(line[valueStart .. limit]);
  }
  return props;
}

/** 折成逻辑行：注释（`#`/`!`）与 `\` 续行都在这一步处理掉，后面只剩「键=值」。
 *
 * 注释行整行丢弃，且它的续行符不生效——下一自然行重新算一个逻辑行（JDK 就是这个行为，
 * 照抄是为了同一份 conf.properties 在两侧解析出同样的表）。
 */
private string[] logicalLines(string text) {
  auto buf = appender!(string[])();
  auto cur = appender!(char[])();
  bool continuing = false; // 上一自然行以奇数个反斜杠收尾
  size_t i = 0;
  while (i < text.length) {
    size_t start = i;
    while (i < text.length && text[i] != '\n' && text[i] != '\r')
      i++;
    auto raw = text[start .. i];
    // 三种行尾都算一行：`\r\n` / `\r` / `\n`
    if (i < text.length) {
      if (text[i] == '\r' && i + 1 < text.length && text[i + 1] == '\n')
        i += 2;
      else
        i++;
    }

    // 自然行开头的空白一律是缩进：JDK 在每个逻辑行开头、以及每个续行开头都吃掉它
    size_t s = 0;
    while (s < raw.length && isSpaceChar(raw[s]))
      s++;
    auto body = raw[s .. $];
    if (!continuing && body.length > 0 && (body[0] == '#' || body[0] == '!'))
      continue;

    // 末尾反斜杠为奇数个才算续行；偶数个时最后一个只是转义前一个
    size_t bs = 0;
    while (bs < body.length && body[body.length - 1 - bs] == '\\')
      bs++;
    if ((bs % 2) == 1) {
      cur.put(body[0 .. body.length - 1]); // 只吃掉续行符本身
      continuing = true;
    } else {
      cur.put(body);
      if (cur.data.length > 0)
        buf.put(cur.data.idup);
      cur.clear();
      continuing = false;
    }
  }
  // 文件末尾带着续行符（没有下一行）：JDK 会把已经攒到的内容当一行返回
  if (cur.data.length > 0)
    buf.put(cur.data.idup);
  return buf.data;
}

/** 解 `\t`/`\n`/`\r`/`\f`/`\uXXXX`，其余 `\x` 退化成 `x`（JDK `loadConvert`）。
 *
 * `\uXXXX` 在 JDK 里是 UTF-16 码元，单独的高/低代理在 UTF-8 里没有对应字节，跳过；
 * 真要在配置里写 emoji 的代理对，请直接写 UTF-8（但那样 JDK 侧又读不对，所以两侧都别这么干）。
 */
private string unescape(string text) {
  if (text.indexOf('\\') < 0)
    return text.idup;
  auto buf = appender!(char[])();
  size_t i = 0;
  while (i < text.length) {
    char c = text[i++];
    if (c != '\\') {
      buf.put(c);
      continue;
    }
    if (i >= text.length) // 逻辑行里的 `\` 后面一定还有字符，这里只是兜底
      break;
    c = text[i++];
    switch (c) {
      case 't': buf.put('\t'); break;
      case 'r': buf.put('\r'); break;
      case 'n': buf.put('\n'); break;
      case 'f': buf.put('\f'); break;
      case 'u':
        if (i + 4 > text.length)
          throw new Exception("Malformed \\uxxxx encoding in properties: " ~ text);
        auto code = to!uint(text[i .. i + 4], 16);
        i += 4;
        if (code >= 0xD800 && code <= 0xDFFF)
          break;
        char[4] encoded;
        buf.put(encoded[0 .. encode(encoded, cast(dchar) code)]);
        break;
      default: buf.put(c); break;
    }
  }
  return buf.data.idup;
}
