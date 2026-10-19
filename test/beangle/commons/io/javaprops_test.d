/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.commons.io.javaprops_test;
/// `conf.properties` 与 scala 侧共用，所以这里钉的是 JDK 的口径，而不是「顺手改一个更方便的」。

import beangle.commons.io.javaprops : parseJavaProperties;

import std.exception : assertThrown;

@("键值分隔：`=`、`:`、空白，以及值里的分隔符")
unittest {
  auto props = parseJavaProperties("a=1\nb:2\nc 3\nd=:4\ne==5");
  assert(props["a"] == "1");
  assert(props["b"] == "2");
  assert(props["c"] == "3");
  assert(props["d"] == ":4"); // 一个分隔符用掉之后，后面的 `:` 属于值
  assert(props["e"] == "=5");
}

@("注释、空行、缩进与键值周围的空白")
unittest {
  auto props = parseJavaProperties("# 注释\n! 也行\n\n   \n  key  =  value  \n");
  assert(props.length == 1);
  assert(props["key"] == "value  "); // 值右侧的空白是值的一部分
}

@("转义：\\uXXXX、\\t\\n、以及转义过的分隔符")
unittest {
  auto props = parseJavaProperties(
      "cn=\\u4e2d\\u6587\ntab=a\\tb\nsep=a\\:b\\=c\nback=a\\\\b\nother=\\q\nspan=a\\ b");
  assert(props["cn"] == "中文");
  assert(props["tab"] == "a\tb");
  assert(props["sep"] == "a:b=c");
  assert(props["back"] == "a\\b");
  assert(props["other"] == "q");
  assert(props["span"] == "a b"); // 转义过的空格留在键里，不算分隔符
}

@("续行：吃掉续行符与前导空白；偶数个反斜杠不是续行")
unittest {
  auto props = parseJavaProperties("key=a\\\n   b\ntail=end\\\n");
  assert(props["key"] == "ab");
  assert(props["tail"] == "end");
  auto even = parseJavaProperties("a=1\\\\\n2");
  assert(even["a"] == "1\\"); // 后一个反斜杠只是转义前一个
  assert(even["2"] == "");
}

@("注释行的续行符不生效")
unittest {
  auto props = parseJavaProperties("# 注释带反斜杠\\\nb=2");
  assert(props.length == 1);
  assert(props["b"] == "2");
}

@("空值与没有值的键（`key=`、`key`、`key = ` 都是空串）")
unittest {
  auto props = parseJavaProperties("a=\nb\nc = \n");
  assert(props["a"] == "");
  assert(props["b"] == "");
  assert(props["c"] == "");
}

@("重复的键以后者为准")
unittest {
  assert(parseJavaProperties("a=1\na=2")["a"] == "2");
}

@("空文档给空表")
unittest {
  assert(parseJavaProperties("").length == 0);
  assert(parseJavaProperties("\n\n").length == 0);
}

@("坏掉的 \\uXXXX 抛异常，不静默丢配置")
unittest {
  assertThrown!Exception(parseJavaProperties("a=\\u12"));
  assertThrown!Exception(parseJavaProperties("a=\\uzzzz"));
}
