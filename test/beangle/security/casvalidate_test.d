/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.security.casvalidate_test;
/// CAS serviceValidate XML 契约：成功、失败、两种属性写法、无效 XML 与校验 URL。

import beangle.commons.net.curl : HttpGetResult;
import beangle.security.cas : CasConfig;
import beangle.security.casvalidate : CasTicketValidator, parseCasValidation;

import std.algorithm.searching : canFind, startsWith;

private enum successXml = `<cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
  <cas:authenticationSuccess>
    <cas:user>zhangsan</cas:user>
    <cas:attributes>
      <cas:userName>张三</cas:userName>
      <cas:authorities>admin,teacher</cas:authorities>
      <cas:permissions>profile:read,profile:write</cas:permissions>
    </cas:attributes>
  </cas:authenticationSuccess>
</cas:serviceResponse>`;

@("parseCasValidation 读取 user 与 attributes 属性")
unittest {
  auto result = parseCasValidation(successXml);
  assert(result.valid);
  assert(result.user == "zhangsan");
  assert(result.attributes["userName"] == "张三");
  assert(result.attributes["authorities"] == "admin,teacher");
  assert(result.attributes["permissions"] == "profile:read,profile:write");
  assert(result.code is null && result.message is null);
}

@("parseCasValidation 兼容 <attribute name value> 与 sso 命名空间")
unittest {
  auto xml = `<sso:serviceResponse xmlns:sso="http://www.yale.edu/tp/cas">
  <sso:authenticationSuccess>
    <sso:user>lisi</sso:user>
    <sso:attributes>
      <sso:attribute name="uid" value="1001"/>
    </sso:attributes>
  </sso:authenticationSuccess>
</sso:serviceResponse>`;
  auto result = parseCasValidation(xml);
  assert(result.valid);
  assert(result.user == "lisi");
  assert(result.attributes["uid"] == "1001");
}

@("parseCasValidation 保留失败 code 与消息")
unittest {
  auto xml = `<cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
  <cas:authenticationFailure code="INVALID_TICKET">Ticket ST-1 not recognized</cas:authenticationFailure>
</cas:serviceResponse>`;
  auto result = parseCasValidation(xml);
  assert(!result.valid);
  assert(result.code == "INVALID_TICKET");
  assert(result.message == "Ticket ST-1 not recognized");
  assert(result.user.length == 0);
}

@("parseCasValidation 对非 CAS/破损 XML 统一返回 Invalid Cas response xml.")
unittest {
  auto wrong = parseCasValidation(`<root><authenticationSuccess><user>a</user></authenticationSuccess></root>`);
  assert(!wrong.valid);
  assert(wrong.message == "Invalid Cas response xml.");

  auto broken = parseCasValidation(`<cas:serviceResponse`);
  assert(!broken.valid);
  assert(broken.message == "Invalid Cas response xml.");
}

@("CasTicketValidator 拼 serviceValidate URL 并解析响应")
unittest {
  string requested;
  auto validator = new CasTicketValidator(CasConfig.of("https://cas.example/cas"),
      (string url) {
        requested = url;
        return HttpGetResult(200, cast(ubyte[]) successXml.dup);
      });

  auto result = validator.validate("ST-1", "https://app.example/home?x=1");
  assert(result.valid && result.user == "zhangsan");
  assert(requested.startsWith("https://cas.example/cas/serviceValidate?ticket=ST-1&service="));
  assert(requested.canFind("https%3A%2F%2Fapp.example%2Fhome%3Fx%3D1"));
}

@("CasTicketValidator 空 ticket 不发请求，HTTP 失败也返回 invalid")
unittest {
  int calls;
  auto validator = new CasTicketValidator(CasConfig.of("https://cas.example/cas"), (string url) {
    calls++;
    return HttpGetResult(500, cast(ubyte[]) "down".dup);
  });

  auto empty = validator.validate("", "https://app.example/");
  assert(!empty.valid && calls == 0);

  auto failed = validator.validate("ST-2", "https://app.example/");
  assert(!failed.valid && failed.code == "failed" && calls == 1);
}
