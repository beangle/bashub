/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.security.casvalidate;
/// CAS service ticket 校验（scala `DefaultTicketValidator` 的 D 版）。
///
/// 只处理 `proxyValidate` / `serviceValidate` 的 XML 响应：`authenticationSuccess`
/// 下的 `<user>` 与属性、`authenticationFailure` 的 code/message。XML 用 dxml，不引
/// 第三方解析库；校验 URL 的拼装与 scala 保持同一顺序（ticket、service）。

import beangle.commons.net.curl : HttpGetResult, curlGet;
import beangle.commons.xml : children, elementText, getAttrs, parseRoot;
import beangle.security.cas : CasConfig;

import dxml.dom : DOMEntity;
import dxml.parser : EntityType;

import std.string : indexOf, strip;
import std.uri : encodeComponent;

/// 校验结果（scala `CasResponse`）。
struct CasValidation {
  bool valid;
  string code;
  string user;
  string[string] attributes;
  string message;
}

/// 测试可注入的 HTTP 取数函数。
alias CasHttpGet = HttpGetResult delegate(string url);

private HttpGetResult defaultGet(string url) {
  return curlGet(url);
}

/// 去掉 `cas:` / `sso:` 前缀，响应里两种命名空间都见过。
private string localName(string name) {
  auto colon = name.indexOf(':');
  return colon < 0 ? name : name[colon + 1 .. $];
}

/** 解析 CAS 校验响应。
 *
 * 与 scala 的 SAX 处理器同口径：`authenticationSuccess` 为真且 `<user>` 非空才算成功；
 * 失败的 XML 保留 code/message；不是 CAS XML 时返回 `Invalid Cas response xml.`。
 */
CasValidation parseCasValidation(string xml) {
  CasValidation result;
  try {
    auto root = parseRoot(xml);
    if (localName(root.name) != "serviceResponse") {
      result.message = "Invalid Cas response xml.";
      return result;
    }
    scanCasResponse(root, result);
  } catch (Exception) {
    result = CasValidation.init;
    result.message = "Invalid Cas response xml.";
    return result;
  }

  if (result.user.length > 0) {
    result.valid = true;
    result.code = null;
    result.message = null;
  } else if (result.message.length == 0) {
    result.message = "Invalid Cas response xml.";
  }
  return result;
}

/// 递归扫描：属性元素既可能是 `<attribute name value>`，也可能是 `<attributes><uid>...`。
private void scanCasResponse(T)(ref DOMEntity!T node, ref CasValidation result) {
  auto name = localName(node.name);
  if (name == "authenticationSuccess") {
    // 作用域只在这棵子树里
    foreach (c; node.children) {
      if (c.type != EntityType.elementStart && c.type != EntityType.elementEmpty)
        continue;
      scanSuccessChild(c, result);
    }
    return;
  }
  if (name == "authenticationFailure") {
    auto attrs = getAttrs(node);
    result.code = attrs.get("code", "").strip;
    result.message = elementText(node).strip;
    return;
  }
  foreach (c; node.children) {
    if (c.type == EntityType.elementStart || c.type == EntityType.elementEmpty)
      scanCasResponse(c, result);
  }
}

private void scanSuccessChild(T)(ref DOMEntity!T node, ref CasValidation result) {
  auto name = localName(node.name);
  if (name == "user") {
    result.user = elementText(node).strip;
    return;
  }
  if (name == "attributes") {
    foreach (c; node.children) {
      if (c.type != EntityType.elementStart && c.type != EntityType.elementEmpty)
        continue;
      scanAttribute(c, result);
    }
    return;
  }
  if (name == "attribute") {
    scanAttribute(node, result);
    return;
  }
  foreach (c; node.children) {
    if (c.type == EntityType.elementStart || c.type == EntityType.elementEmpty)
      scanSuccessChild(c, result);
  }
}

private void scanAttribute(T)(ref DOMEntity!T node, ref CasValidation result) {
  auto name = localName(node.name);
  auto attrs = getAttrs(node);
  if (name == "attribute") {
    auto key = attrs.get("name", "").strip;
    if (key.length > 0)
      result.attributes[key] = attrs.get("value", "").strip;
    return;
  }

  // 有些 CAS 用具名子元素放属性，例如 <education>本科</education>
  auto text = elementText(node).strip;
  if (name.length > 0 && text.length > 0)
    result.attributes[name] = text;
}

/// 校验一个 service ticket；HTTP 非 200 与解析失败都归为 invalid。
class CasTicketValidator {
  private CasConfig cfg;
  private CasHttpGet httpGet;

  this(CasConfig cfg, CasHttpGet httpGet = null) {
    this.cfg = cfg;
    this.httpGet = httpGet is null ? ((string url) => defaultGet(url)) : httpGet;
  }

  CasValidation validate(string ticket, string service) {
    if (ticket.length == 0)
      return CasValidation(false, "-1", null, null, "ticket and service parameters are required.");
    auto url = cfg.validateUrl ~ "?ticket=" ~ encodeComponent(ticket) ~ "&service=" ~ encodeComponent(service);
    auto response = httpGet(url);
    if (!response.isOk)
      return CasValidation(false, "failed", null, null, cast(string) response.body);
    return parseCasValidation(cast(string) response.body);
  }
}
