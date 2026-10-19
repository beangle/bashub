/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.commons.xml_test;
/// dxml 上的几个取值辅助：属性、子元素、元素文本。

import beangle.commons.xml : children, elementText, escapeXml, getAttrs, parseRoot;

import std.exception : assertThrown;
import std.string : strip;

@("取属性、子元素与元素文本")
unittest {
  auto root = parseRoot(`<bashub listen="0:1"><ems app-name="bas-hub"><props>
    <prop key="a">  1  </prop></props></ems></bashub>`);
  assert(root.name == "bashub");
  assert(getAttrs(root)["listen"] == "0:1");
  auto ems = children(root, "ems")[0];
  assert(getAttrs(ems)["app-name"] == "bas-hub");
  auto props = children(ems, "props")[0];
  assert(children(props, "prop")[0].elementText.strip == "1");
}

@("自闭合标签也算元素；空文档抛异常")
unittest {
  auto root = parseRoot(`<bashub><ems app-name="x"/></bashub>`);
  assert(children(root, "ems")[0].name == "ems");
  assertThrown!Exception(parseRoot(""));
}

@("CDATA 也算元素文本")
unittest {
  auto root = parseRoot(`<app><title><![CDATA[ a < b ]]></title></app>`);
  assert(children(root, "title")[0].elementText.strip == "a < b");
}

@("属性与文本中的 XML 实体按标准解码")
unittest {
  auto root = parseRoot(`<app path="/a?x=1&amp;y=2" quote="&quot;&apos;">` ~
      `A &lt; B &#65; &#x42;</app>`);
  assert(getAttrs(root)["path"] == "/a?x=1&y=2");
  assert(getAttrs(root)["quote"] == "\"'");
  assert(root.elementText == "A < B A B");
}

@("CDATA 中的实体文本不重复解码")
unittest {
  auto root = parseRoot(`<app><![CDATA[&amp;]]></app>`);
  assert(root.elementText == "&amp;");
}

@("escapeXml 转义文本与双引号属性")
unittest {
  auto value = `A&B <x> "q" 's'`;
  assert(escapeXml(value) == `A&amp;B &lt;x&gt; &quot;q&quot; 's'`);

  auto root = parseRoot(`<app value="` ~ escapeXml(value) ~ `">` ~ escapeXml(value) ~ `</app>`);
  assert(getAttrs(root)["value"] == value);
  assert(root.elementText == value);
}
