/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.profile.proxy;
/// `GET /api/bashub/{profile}/config/proxy`：按 `proxyEngine` 输出 haproxy / nginx 配置。
/// 分组口径与 Scala `ConfigWS.prepareProxyData` 一致：只有带 targets 的 webapp 参与，
/// 同一个 farm 内按 server 集合拆后端；多个 server 的集合命名为 `farm2`、`farm3`…。

import bashub.profile.distribution : ProfileData, loadProfileData;
import bashub.profile.resolver : ProfileContext;

import beangle.data.resource : Registry;
import beangle.data.value : jsonText;
import beangle.jsonapi.document : attributeBool, attributeLong, attributeStrings, attributeText, hasAttribute,
  relationshipId, relationshipIds;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.algorithm : sort;
import std.array : appender, join, split;
import std.conv : to;
import std.string : replace, strip;

/// 反代后端里的一台 server。
struct ProxyServer {
  string id;
  string name;
  string farmId;
  string farmName;
  string ip;
  string options;
  long port;

  string qualifiedName() const {
    return farmName.length > 0 ? farmName ~ "." ~ name : name;
  }
}

/// 参与反代路由的 webapp。
struct ProxyWebapp {
  string id;
  string contextPath;
  string[] urlPaths;
  string farmId;
  string farmName;
  ProxyServer[] servers;
}

/// 一个 upstream / backend。
struct ProxyBackend {
  string name;
  string options;
  ProxyServer[] servers;
  string[] webappIds;
}

/// 模板渲染所需的全部数据。
struct ProxyModel {
  Json profile;
  ProxyWebapp[] webapps;
  ProxyBackend[] backends;
  string[string] backendByWebapp;
}

private struct ServerGroup {
  string key;
  string sortKey;
  ProxyServer[] servers;
  string[] webappIds;
}

private struct FarmGroup {
  string id;
  string name;
  string options;
  ServerGroup[] groups;
}

/// setline pull 的证书落点。公钥/私钥分开给 nginx；haproxy 读拼接后的 bundle。
private enum certificateDir = "/etc/setline/certs";

/// 按 `profile.proxyEngine` 渲染；未知引擎返回空串（路由按 404 处理）。
string renderProxy(Store store, Registry reg, const ProfileContext context) {
  auto data = loadProfileData(store, reg, context);
  auto engine = attributeText(context.data, "proxyEngine").strip;
  auto model = buildProxyModel(data);
  if (engine == "nginx")
    return renderNginx(model);
  if (engine == "haproxy")
    return renderHaproxy(model);
  return "";
}

/// 从共享 Profile 快照建立反代模型。
ProxyModel buildProxyModel(ProfileData data) {
  ProxyModel model;
  model.profile = data.profile.data;

  auto apps = data.webapps.dup;
  sort!((a, b) => attributeText(a, "contextPath") < attributeText(b, "contextPath"))(apps);

  ProxyWebapp[] normalApps;
  ProxyWebapp[] rootApps;
  foreach (app; apps) {
    ProxyWebapp item;
    item.id = jsonText(app["id"]);
    item.contextPath = attributeText(app, "contextPath").strip;
    item.servers = targetServers(app, data);
    if (item.servers.length == 0)
      continue;
    item.urlPaths = urlPaths(app);
    item.farmId = item.servers[0].farmId;
    item.farmName = item.servers[0].farmName;
    if (item.contextPath.length < 2)
      rootApps ~= item;
    else
      normalApps ~= item;
  }
  model.webapps = normalApps ~ rootApps;

  FarmGroup[] farms;
  foreach (app; model.webapps) {
    auto farm = findFarmGroup(farms, app.farmId);
    if (farm is null) {
      auto created = FarmGroup(app.farmId, app.farmName, farmOptions(data, app.farmId));
      farms ~= created;
      farm = &farms[$ - 1];
    }
    auto key = serverGroupKey(app.servers);
    auto group = findServerGroup(*farm, key);
    if (group is null) {
      ServerGroup created;
      created.key = key;
      created.sortKey = app.servers[0].qualifiedName() ~ "|" ~ key;
      created.servers = app.servers;
      farm.groups ~= created;
      group = &farm.groups[$ - 1];
    }
    group.webappIds ~= app.id;
  }

  foreach (farm; farms) {
    auto groups = farm.groups.dup;
    sort!((a, b) => a.sortKey < b.sortKey)(groups);
    ProxyBackend[] farmBackends;
    int index = 1;
    foreach (group; groups) {
      string name;
      if (group.servers.length == 1) {
        name = group.servers[0].qualifiedName().replace(".", "_");
      } else {
        index++;
        name = farm.name ~ index.to!string;
      }
      ProxyBackend backend;
      backend.name = name;
      backend.options = farm.options;
      backend.servers = group.servers;
      backend.webappIds = group.webappIds;
      farmBackends ~= backend;
    }
    if (farmBackends.length == 1)
      farmBackends[0].name = farm.name;
    foreach (backend; farmBackends) {
      model.backends ~= backend;
      foreach (webappId; backend.webappIds)
        model.backendByWebapp[webappId] = backend.name;
    }
  }
  return model;
}

private ProxyServer[] targetServers(Json webapp, const ProfileData data) {
  ProxyServer[] servers;
  bool[string] seen;
  foreach (serverId; relationshipIds(webapp, "targets")) {
    if (serverId in seen || serverId !in data.serversById)
      continue;
    seen[serverId] = true;

    auto server = data.serversById[serverId];
    ProxyServer item;
    item.id = serverId;
    item.name = attributeText(server, "name");
    item.farmId = relationshipId(server, "farm");
    if (item.farmId in data.farmsById)
      item.farmName = attributeText(data.farmsById[item.farmId], "name");
    auto hostId = relationshipId(server, "host");
    if (hostId in data.hostsById)
      item.ip = attributeText(data.hostsById[hostId], "ip");
    item.options = attributeText(server, "proxyOptions").strip;
    item.port = hasAttribute(server, "proxyHttpPort") ?
        attributeLong(server, "proxyHttpPort") : attributeLong(server, "httpPort");
    servers ~= item;
  }
  sort!((a, b) => a.name < b.name || (a.name == b.name && a.id < b.id))(servers);
  return servers;
}

/// 显式 urls 优先；否则 contextPath；空或 `/` 统一成 `/`。
private string[] urlPaths(Json webapp) {
  auto declared = attributeStrings(webapp, "urls");
  if (declared.length > 0)
    return declared;
  auto path = attributeText(webapp, "contextPath").strip;
  return path.length == 0 || path == "/" ? ["/"] : [path];
}

private string farmOptions(const ProfileData data, string farmId) {
  if (farmId !in data.farmsById)
    return "";
  return attributeText(data.farmsById[farmId], "proxyOptions").strip;
}

private string serverGroupKey(ProxyServer[] servers) {
  string[] ids;
  foreach (server; servers)
    ids ~= server.id;
  sort(ids);
  return ids.join(",");
}

private FarmGroup* findFarmGroup(ref FarmGroup[] farms, string id) {
  foreach (ref farm; farms) {
    if (farm.id == id)
      return &farm;
  }
  return null;
}

private ServerGroup* findServerGroup(ref FarmGroup farm, string key) {
  foreach (ref group; farm.groups) {
    if (group.key == key)
      return &group;
  }
  return null;
}

/// nginx：每个 webapp 的每个 urlPath 一个 location，后端来自 server 集合。
string renderNginx(ProxyModel model) {
  auto profile = model.profile;
  auto maxconn = attributeLong(profile, "maxconn", 30000);
  auto httpPort = attributeLong(profile, "httpPort", 80);
  auto httpsPort = attributeLong(profile, "httpsPort", 443);
  auto hostname = attributeText(profile, "hostname").strip;
  auto sslProtocols = attributeText(profile, "sslProtocols").strip;
  auto sslCiphers = attributeText(profile, "sslCiphers").strip;
  if (sslProtocols.length == 0)
    sslProtocols = "TLSv1 TLSv1.1 TLSv1.2";
  if (sslCiphers.length == 0)
    sslCiphers = "HIGH:!aNULL:!MD5";
  auto enableHttps = attributeBool(profile, "enableHttps");
  auto forceHttps = attributeBool(profile, "forceHttps", true);

  auto out_ = appender!string;
  line(out_, "user nginx;");
  line(out_, "worker_processes auto;");
  line(out_, "worker_rlimit_nofile 65535;");
  line(out_, "error_log /var/log/nginx/error.log;");
  line(out_, "pid /run/nginx.pid;");
  line(out_, "");
  line(out_, "include /usr/share/nginx/modules/*.conf;");
  line(out_, "");
  line(out_, "events {");
  line(out_, "    worker_connections " ~ maxconn.to!string ~ ";");
  line(out_, "    multi_accept on;");
  line(out_, "    use epoll;");
  line(out_, "}");
  line(out_, "");
  line(out_, "http {");
  line(out_, "    sendfile            on;");
  line(out_, "    tcp_nopush          on;");
  line(out_, "    tcp_nodelay         on;");
  line(out_, "    keepalive_timeout   65;");
  line(out_, "    types_hash_max_size 2048;");
  line(out_, "    types_hash_bucket_size 1024;");
  line(out_, "");
  line(out_, "    include             /etc/nginx/mime.types;");
  line(out_, "    default_type        application/octet-stream;");
  line(out_, "");
  if (enableHttps) {
    line(out_, "    ssl_session_cache   shared:SSL:10m;");
    line(out_, "    ssl_session_timeout 10m;");
  }
  line(out_, "    include /etc/nginx/conf.d/*.conf;");

  auto backends = model.backends.dup;
  sort!((a, b) => a.name < b.name)(backends);
  foreach (backend; backends) {
    line(out_, "");
    line(out_, "    upstream " ~ backend.name ~ "{");
    if (backend.options.length > 0)
      putIndented(out_, backend.options, "        ");
    foreach (server; backend.servers) {
      auto text = "        server " ~ server.ip ~ ":" ~ server.port.to!string;
      if (server.options.length > 0)
        text ~= " " ~ server.options;
      line(out_, text ~ ";");
    }
    line(out_, "    }");
  }

  if (enableHttps && forceHttps) {
    line(out_, "");
    line(out_, "    server {");
    line(out_, "        listen " ~ httpPort.to!string ~ " default_server;");
    line(out_, "        listen [::]:" ~ httpPort.to!string ~ " default_server;");
    if (hostname.length > 0)
      line(out_, "        server_name  " ~ hostname ~ ";");
    line(out_, "        return 301 https://$server_name$request_uri;");
    line(out_, "    }");
  }

  line(out_, "");
  line(out_, "    server {");
  if (!(enableHttps && forceHttps))
    line(out_, "        listen " ~ httpPort.to!string ~ ";");
  if (enableHttps)
    line(out_, "        listen " ~ httpsPort.to!string ~ " ssl;");
  if (hostname.length > 0)
    line(out_, "        server_name  " ~ hostname ~ ";");
  if (enableHttps && hostname.length > 0) {
    line(out_, "        ssl_certificate " ~ certificateDir ~ "/cert.pem;");
    line(out_, "        ssl_certificate_key " ~ certificateDir ~ "/key.pem;");
    line(out_, "        ssl_protocols      " ~ sslProtocols ~ ";");
    line(out_, "        ssl_ciphers       " ~ sslCiphers ~ ";");
    line(out_, "        keepalive_timeout   70;");
  }
  line(out_, "        root         /usr/share/nginx/html;");
  line(out_, "        access_log off;");
  line(out_, "        proxy_set_header  X-Real-IP  $remote_addr;");
  line(out_, "        proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;");
  line(out_, "        proxy_set_header  X-Forwarded-Proto  $scheme;");
  line(out_, "        proxy_set_header  Host $host:$server_port;");
  line(out_, "");
  line(out_, "        include /etc/nginx/default.d/*.conf;");
  line(out_, "        location /status {");
  line(out_, "            stub_status on;");
  line(out_, "            access_log off;");
  line(out_, "        }");

  auto webapps = model.webapps.dup;
  sort!((a, b) => a.contextPath < b.contextPath)(webapps);
  foreach (webapp; webapps) {
    auto backend = model.backendByWebapp.get(webapp.id, "");
    if (backend.length == 0)
      continue;
    foreach (path; webapp.urlPaths) {
      line(out_, "        location " ~ path ~ " {");
      line(out_, "            proxy_pass http://" ~ backend ~ ";");
      line(out_, "        }");
    }
  }
  line(out_, "    }");
  line(out_, "}");
  return out_.data;
}

/// haproxy：主配置只保留监听与 setline 接线；backend 和路由 map 由 setline agent 生成。
string renderHaproxy(ProxyModel model) {
  auto profile = model.profile;
  auto maxconn = attributeLong(profile, "maxconn", 30000);
  auto httpPort = attributeLong(profile, "httpPort", 80);
  auto httpsPort = attributeLong(profile, "httpsPort", 443);
  auto hostname = attributeText(profile, "hostname").strip;
  auto sslProtocols = attributeText(profile, "sslProtocols").strip;
  auto sslCiphers = attributeText(profile, "sslCiphers").strip;
  if (sslProtocols.length == 0)
    sslProtocols = "no-sslv3 no-tlsv10";
  auto enableHttps = attributeBool(profile, "enableHttps");
  auto forceHttps = attributeBool(profile, "forceHttps", true);

  auto out_ = appender!string;
  line(out_, "# HAProxy main configuration. Start it with the setline fragment directory:");
  line(out_, "#   -f /etc/haproxy/haproxy.cfg -f /var/lib/setline/haproxy");
  line(out_, "global");
  line(out_, "    log         127.0.0.1 local2");
  line(out_, "    chroot      /var/lib/haproxy");
  line(out_, "    pidfile     /var/run/hapid");
  line(out_, "    maxconn     " ~ maxconn.to!string);
  line(out_, "    user        haproxy");
  line(out_, "    group       haproxy");
  line(out_, "    daemon");
  line(out_, "    tune.ssl.default-dh-param 2048");
  line(out_, "    ssl-default-bind-options no-sslv3 no-tlsv10");
  line(out_, "    ssl-default-bind-ciphers PROFILE=SYSTEM");
  line(out_, "    ssl-default-server-ciphers PROFILE=SYSTEM");
  line(out_, "    stats socket /var/lib/haproxy/stats");
  line(out_, "");
  line(out_, "defaults");
  line(out_, "    mode                    http");
  line(out_, "    log                     global");
  line(out_, "    option                  httplog");
  line(out_, "    option                  dontlognull");
  line(out_, "    option http-server-close");
  line(out_, "    option forwardfor       except 127.0.0.0/8");
  line(out_, "    option                  redispatch");
  line(out_, "    retries                 3");
  line(out_, "    timeout http-request    2m");
  line(out_, "    timeout queue           1m");
  line(out_, "    timeout connect         30s");
  line(out_, "    timeout client          2m");
  line(out_, "    timeout server          10m");
  line(out_, "    timeout http-keep-alive 60s");
  line(out_, "    timeout check           60s");
  line(out_, "    maxconn                 " ~ maxconn.to!string);
  line(out_, "");
  line(out_, "    stats refresh 30s");
  line(out_, "    stats uri /status");
  line(out_, "    stats realm haproxy-user");
  line(out_, "    stats auth admin:ChangeItNow");
  line(out_, "");
  line(out_, "frontend main");
  line(out_, "    bind *:" ~ httpPort.to!string);
  if (enableHttps) {
    auto bind = "    bind *:" ~ httpsPort.to!string ~ " ssl crt " ~ certificateDir ~ "/bundle.pem ";
    if (sslCiphers.length > 0)
      bind ~= "ciphers " ~ sslCiphers ~ " ";
    bind ~= sslProtocols;
    line(out_, bind);
    line(out_, "    http-request set-header X-Forwarded-Proto https if { ssl_fc }");
    line(out_, "    http-request set-header X-Forwarded-Port %[dst_port]");
  }
  if (enableHttps && forceHttps && hostname.length > 0) {
    line(out_, "    redirect scheme https if !{ ssl_fc } { hdr_beg(host) " ~ hostname ~ " }");
  }
  line(out_, "");

  line(out_, "    # setline path routes: backends and map are written by the setline agent to /var/lib/setline/haproxy");
  line(out_, "    use_backend %[path,map_beg(/var/lib/setline/haproxy/setline.map)] " ~
      "if { path,map_beg(/var/lib/setline/haproxy/setline.map) -m found }");
  return out_.data;
}

private void line(A)(ref A out_, string text) {
  out_.put(text);
  out_.put('\n');
}

private void putIndented(A)(ref A out_, string text, string indent) {
  foreach (lineText; text.split('\n')) {
    auto trimmed = lineText.strip;
    if (trimmed.length > 0)
      line(out_, indent ~ trimmed);
  }
}
