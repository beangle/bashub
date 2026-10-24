/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.project.peers;
/// bashub 向 setline 发布的 peer 列表。peer 是运行 setline 的 web 节点或 micdn 节点，
/// setline 从 `<url>/_setline/routes` 读取路由表。

import bashub.project.distribution : loadProjectData;
import bashub.project.micdnconfig : readMicdnConfig;
import bashub.project.resolver : ProjectContext;

import beangle.data.resource : Registry;
import beangle.data.value : jsonGet, jsonText;
import beangle.jsonapi.document : attributeText, relationshipId;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.algorithm : sort;
import std.array : appender;
import std.conv : ConvException, to;
import std.string : indexOf, strip;

private struct SetlinePeer {
  string name;
  string url;
}

/// 输出 `{"peers": [...]}`。没有 peer 时给空数组，便于 setline pull 清空旧 peers。
string renderPeers(Store store, Registry reg, const ProjectContext context) {
  auto data = loadProjectData(store, reg, context);
  SetlinePeer[] peers;
  bool[string] urls;
  foreach (server; data.servers) {
    auto hostId = relationshipId(server, "host");
    if (hostId.length == 0 || hostId !in data.hostsById)
      continue;
    auto host = data.hostsById[hostId];
    auto ip = attributeText(host, "ip").strip;
    if (ip.length == 0)
      continue;

    SetlinePeer peer;
    peer.name = attributeText(host, "name").strip;
    if (peer.name.length == 0)
      peer.name = ip;
    ushort port;
    if (!hostSetlineListenPort(host, port))
      continue;
    peer.url = "http://" ~ (ip.indexOf(':') >= 0 ? "[" ~ ip ~ "]" : ip)
        ~ ":" ~ port.to!string;
    addPeer(peers, urls, peer);
  }

  Json micdnConfig;
  readMicdnConfig(store, reg, context.id, micdnConfig);
  foreach (ref server; jsonGet(micdnConfig, "servers")) {
    SetlinePeer peer;
    peer.name = jsonText(jsonGet(server, "name"));
    peer.url = "http://" ~ jsonText(jsonGet(server, "adminListen"));
    addPeer(peers, urls, peer);
  }
  sort!((a, b) => a.name < b.name || (a.name == b.name && a.url < b.url))(peers);

  auto out_ = appender!string;
  line(out_, "{");
  if (peers.length == 0) {
    line(out_, `  "peers": []`);
  } else {
    line(out_, `  "peers": [`);
    foreach (i, peer; peers) {
      auto comma = i + 1 < peers.length ? "," : "";
      line(out_, `    { "name": ` ~ jsonString(peer.name) ~ `, "url": ` ~ jsonString(peer.url) ~ ` }` ~ comma);
    }
    line(out_, `  ]`);
  }
  line(out_, "}");
  return out_.data;
}

/// Host.setlineListenPort 是 setline 数据面 `listen` 的端口；agent 从
/// `http://host:port/_setline/routes` 拉路由，不能拿 Host.setlineAdminPort
/// （本机 adminListen）代替。
private bool hostSetlineListenPort(Json host, out ushort port) {
  auto text = attributeText(host, "setlineListenPort").strip;
  if (text.length == 0)
    return false;
  try {
    port = text.to!ushort;
  } catch (ConvException e) {
    throw new Exception("Host.setlineListenPort must be a port number (1-65535): " ~ text);
  }
  if (port == 0)
    throw new Exception("Host.setlineListenPort must be a port number (1-65535): " ~ text);
  return true;
}

/// Web 节点和 micdn 节点可能落在同一台机器上；按 peer URL 去重，名称只作展示。
private void addPeer(ref SetlinePeer[] peers, ref bool[string] urls, SetlinePeer peer) {
  if (peer.name.length == 0 || peer.url.length == 0 || peer.url in urls)
    return;
  urls[peer.url] = true;
  peers ~= peer;
}

private void line(A)(ref A out_, string text) {
  out_.put(text);
  out_.put('\n');
}

private string jsonString(string text) {
  auto out_ = appender!string;
  out_.put('"');
  foreach (ch; text) {
    if (ch == '"' || ch == '\\')
      out_.put('\\');
    out_.put(ch);
  }
  out_.put('"');
  return out_.data;
}
