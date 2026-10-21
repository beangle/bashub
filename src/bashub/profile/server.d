/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.profile.server;
/// `GET /api/bashub/config/{profile}/server`：把 Profile 的服务器、主机、webapp 与引擎
/// 渲染成 basctl 使用的 server.xml。原 Scala 版是 Freemarker 模板；这里没有模板运行时，
/// 但输出结构保持一致。

import bashub.profile.distribution : ProfileData, artifactGav, loadProfileData, webappGav;
import bashub.profile.micdnconfig : micdnDownloadKey;
import bashub.profile.resolver : ProfileContext;

import beangle.commons.xml : escapeXml;
import beangle.data.resource : Registry, Resource;
import beangle.data.value : jsonText;
import beangle.jsonapi.document : attributeBool, attributeLong, attributeStrings, attributeText, hasAttribute,
  relationshipId, relationshipIds;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.algorithm : sort;
import std.array : appender, join;
import std.conv : to;
import std.string : strip;

/// 渲染 server.xml；返回内容只依赖数据库，不读请求上下文。
///
/// SNAPSHOT 上游的令牌取 Profile 的 micdn `<auth download-key>`：有值才写 `token`，
/// 空值即匿名下载。`maskSecrets` 只用于 SPA 预览，机器下载端点必须传 false。
string renderServerXml(Store store, Registry reg, const ProfileContext context,
    bool maskSecrets = false) {
  auto data = loadProfileData(store, reg, context);
  auto farms = data.farms.dup;
  auto hosts = data.hosts.dup;
  auto webapps = data.webapps.dup;
  sort!((a, b) => attributeText(a, "name") < attributeText(b, "name"))(farms);
  sort!((a, b) => attributeText(a, "ip") < attributeText(b, "ip"))(hosts);
  sort!((a, b) => webappGav(a, data.artifactsById) < webappGav(b, data.artifactsById))(webapps);

  auto engineIds = data.enginesById.keys;
  sort!((a, b) => attributeText(data.enginesById[a], "name") <
      attributeText(data.enginesById[b], "name"))(engineIds);

  auto xml = appender!string;
  xml.put("<bas xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" ");
  xml.put("xsi:noNamespaceSchemaLocation=\"http://beangle.github.io/schema/bas-1.0.0.xsd\" version=\"");
  xml.put(escapeXml(attributeText(context.data, "basVersion")));
  xml.put("\">\n");
  xml.put("  <repository remote=\"");
  xml.put(escapeXml(attributeText(context.data, "remoteRepo")));
  xml.put("\"/>\n");
  xml.put("  <snapshot-repo remote=\"${bas_remote_url}/maven\"");
  auto downloadKey = micdnDownloadKey(store, reg, context.id);
  if (downloadKey.length > 0)
    putAttr(xml, "token", maskSecrets ? "********" : downloadKey);
  xml.put("/>\n");

  xml.put("  <engines>\n");
  foreach (engineId; engineIds) {
    auto engine = data.enginesById[engineId];
    auto typ = attributeText(engine, "typ");
    xml.put("    <engine");
    putAttr(xml, "name", attributeText(engine, "name"));
    putAttr(xml, "type", typ);
    putAttr(xml, "version", attributeText(engine, "version"));
    if (isJavaEngine(typ)) {
      if (typ == "tomcat-server")
        putAttr(xml, "jsp-support", boolText(attributeBool(engine, "jspSupport")));
      putAttr(xml, "websocket-support", boolText(attributeBool(engine, "websocketSupport")));
    }
    xml.put(">\n");
    foreach (listener; attributeStrings(engine, "listeners")) {
      xml.put("      <listener class-name=\"");
      xml.put(escapeXml(listener));
      xml.put("\"/>\n");
    }
    foreach (jar; attributeStrings(engine, "jars")) {
      xml.put("      <jar uri=\"");
      xml.put(escapeXml(jar));
      xml.put("\"/>\n");
    }
    xml.put("    </engine>\n");
  }
  xml.put("  </engines>\n\n");

  xml.put("  <hosts>\n");
  foreach (host; hosts) {
    xml.put("    <host");
    putAttr(xml, "name", attributeText(host, "name"));
    putAttr(xml, "ip", attributeText(host, "ip"));
    xml.put("/>\n");
  }
  xml.put("  </hosts>\n\n");

  xml.put("  <farms>\n");
  foreach (farm; farms) {
    xml.put("    <farm");
    putAttr(xml, "name", attributeText(farm, "name"));
    auto engineId = relationshipId(farm, "engine");
    putAttr(xml, "engine", engineId in data.enginesById ?
        attributeText(data.enginesById[engineId], "name") : "");
    putAttr(xml, "max-heap-size", numberText(farm, "maxHeapSize") ~ "M");
    xml.put(">\n");
    if (hasAttribute(farm, "serverOptions")) {
      xml.put("      <server-options>");
      xml.put(attributeText(farm, "serverOptions"));
      xml.put("</server-options>\n");
    }
    if (hasAttribute(farm, "proxyOptions")) {
      xml.put("      <proxy-options>\n      <![CDATA[");
      xml.put(attributeText(farm, "proxyOptions"));
      xml.put("]]>\n      </proxy-options>\n");
    }
    foreach (serverId; relationshipIds(farm, "servers")) {
      if (serverId !in data.serversById)
        continue;
      auto server = data.serversById[serverId];
      xml.put("      <server");
      putAttr(xml, "name", attributeText(server, "name"));
      auto hostId = relationshipId(server, "host");
      putAttr(xml, "host", hostId in data.hostsById ?
          attributeText(data.hostsById[hostId], "name") : "");
      putAttr(xml, "http", numberText(server, "httpPort"));
      auto maxHeap = attributeLong(server, "maxHeapSize");
      if (maxHeap > 0)
        putAttr(xml, "max-heap-size", maxHeap.to!string ~ "M");
      if (hasAttribute(server, "proxyHttpPort"))
        putAttr(xml, "proxy-http-port", numberText(server, "proxyHttpPort"));
      if (hasAttribute(server, "proxyOptions"))
        putAttr(xml, "proxy-options", attributeText(server, "proxyOptions"));
      xml.put("/>\n");
    }
    xml.put("    </farm>\n");
  }
  xml.put("  </farms>\n");

  xml.put("  <webapps>\n");
  foreach (webapp; webapps) {
    auto artifactId = relationshipId(webapp, "artifact");
    if (artifactId !in data.artifactsById)
      continue;
    auto artifact = data.artifactsById[artifactId];
    xml.put("    <webapp");
    putAttr(xml, "uri", "gav://" ~ artifactGav(artifact, attributeText(webapp, "version")));
    putAttr(xml, "path", attributeText(webapp, "contextPath"));
    string[] runAt;
    foreach (serverId; relationshipIds(webapp, "targets")) {
      if (serverId !in data.serversById)
        continue;
      auto server = data.serversById[serverId];
      auto farmId = relationshipId(server, "farm");
      auto farmName = farmId in data.farmsById ? attributeText(data.farmsById[farmId], "name") : "";
      runAt ~= farmName ~ "." ~ attributeText(server, "name");
    }
    putAttr(xml, "run-at", runAt.join(","));
    if (hasAttribute(webapp, "libs"))
      putAttr(xml, "libs", attributeText(webapp, "libs"));
    if (attributeBool(webapp, "unpack"))
      putAttr(xml, "unpack", "true");
    if (!attributeBool(artifact, "resolveSupport"))
      putAttr(xml, "resolve-support", "false");
    auto urls = attributeStrings(webapp, "urls");
    if (urls.length == 0) {
      xml.put("/>\n");
    } else {
      xml.put(">");
      foreach (url; urls) {
        xml.put(" <url path=\"");
        xml.put(escapeXml(url));
        xml.put("\"/>");
      }
      xml.put("</webapp>\n");
    }
  }
  xml.put("  </webapps>\n");
  xml.put("</bas>\n");
  return xml.data;
}

private bool isJavaEngine(string typ) {
  return typ == "tomcat-server" || typ == "tomcat" || typ == "undertow" || typ == "jetty";
}

private string numberText(Json resource, string attr) {
  return attributeLong(resource, attr).to!string;
}

private string boolText(bool value) {
  return value ? "true" : "false";
}

private void putAttr(A)(ref A xml, string name, string value) {
  xml.put(' ');
  xml.put(name);
  xml.put("=\"");
  xml.put(escapeXml(value));
  xml.put('"');
}
