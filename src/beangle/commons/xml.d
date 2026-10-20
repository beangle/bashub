/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.commons.xml;
/// dxml DOM 上的最小解析辅助：属性表、按名取子元素、取元素文本。
/// 标准库没有 XML，所以框架侧（`beangle.*`）要用 XML 的模块都从这里取这几件小事，
/// 免得各写一份。

import dxml.dom;
import dxml.parser : EntityType;
import dxml.util : decodeXML;

import std.array : appender;

/** 起始标签与自闭合标签都算「元素」；其余（文本、注释、XML 声明）不算。 */
bool isNamedElement(EntityType t) @safe pure nothrow {
  return t == EntityType.elementStart || t == EntityType.elementEmpty;
}

/** 取属性表（同名属性后者覆盖前者）。 */
string[string] getAttrs(T)(ref DOMEntity!T dom) {
  string[string] a;
  foreach (at; dom.attributes)
    a[at.name] = decodeXML(at.value);
  return a;
}

/** 按名字取直接子元素。
 *
 * 返回数组而不是惰性 range：调用处大多只要「有没有」和「第一个」，而且 dxml 的 range 生命周期
 * 容易看走眼（它是切片视图，源一变就跟着变）。
 */
DOMEntity!T[] children(T)(ref DOMEntity!T dom, string path) {
  DOMEntity!T[] found;
  foreach (c; dom.children) {
    if (isNamedElement(c.type) && c.name == path)
      found ~= c;
  }
  return found;
}

/** 元素的文本内容：把所有文本/CDATA 子节点的文本拼起来（dxml 的 `.text` 只对文本节点有效）。
 *
 * 只拼直接子节点，不递归——`<prop key="a">text</prop>` 这种扁平的属性元素够用了。
 * 文本节点里的 XML 实体按标准解码；CDATA 原样保留。
 */
string elementText(T)(ref DOMEntity!T dom) {
  auto buf = appender!(char[])();
  foreach (c; dom.children) {
    if (c.type == EntityType.text)
      buf.put(decodeXML(c.text));
    else if (c.type == EntityType.cdata)
      buf.put(c.text);
  }
  return buf.data.idup;
}

/** 解析 XML 文本并返回根元素；空文档抛 Exception。
 *
 * 必须对内容类型做模板（dxml 的 `DOMEntity!R` 会按 `R` 决定怎么切片），
 * 写成 `DOMEntity!EntityType` 会去实例化一个无意义的 `takeExactly(EntityType, 42)`。
 */
auto parseRoot(R)(R content) {
  auto dom = parseDOM!simpleXML(content);
  if (dom.children.length == 0)
    throw new Exception("empty xml document");
  return dom.children[0];
}

/** XML 转义：用于元素文本或双引号属性。
 *
 * 与各业务模块原先的私有实现同口径：转义 `& < >` 与双引号，不额外改写单引号。
 */
string escapeXml(string text) {
  auto escaped = appender!string;
  foreach (c; text) {
    switch (c) {
    case '&':
      escaped.put("&amp;");
      break;
    case '<':
      escaped.put("&lt;");
      break;
    case '>':
      escaped.put("&gt;");
      break;
    case '"':
      escaped.put("&quot;");
      break;
    default:
      escaped.put(c);
    }
  }
  return escaped.data;
}
