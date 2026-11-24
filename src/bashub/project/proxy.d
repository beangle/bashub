/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.project.proxy;
/// `GET /api/bashub/config/{project}/proxy`：按 endpoint engine 输出 haproxy / nginx 配置。
/// 分组口径与 Scala `ConfigWS.prepareProxyData` 一致：只有带 targets 的 webapp 参与，
/// 同一个 farm 内按 server 集合拆后端；多个 server 的集合命名为 `farm2`、`farm3`…。

import bashub.project.distribution : ProjectData, loadProjectData;
import bashub.project.micdnconfig : MicdnProjectView, loadMicdnProject;
import bashub.project.resolver : ProjectContext;

import beangle.data.resource : Registry;
import beangle.data.value : jsonText;
import beangle.jsonapi.document : attributeBool, attributeLong, attributeStrings, attributeText, hasAttribute,
  relationshipId, relationshipIds;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.algorithm : canFind, sort;
import std.array : appender, join, split;
import std.conv : to;
import std.string : indexOf, lastIndexOf, replace, startsWith, strip;

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
  Json project;
  Json proxy;
  string hostname;
  string endpointName;
  string engine;
  /// bundle 配置中引用的证书目录；由调用方按部署位置指定。
  string certificateDir;
  /// HAProxy 路由 map 的部署路径。
  string routeMap;
  ProxyWebapp[] webapps;
  ProxyBackend[] backends;
  string[string] backendByWebapp;
  /// 每个 endpoint 都追加同一份 micdn 代理，路径来自 Project 的 micdn 配置。
  ProxyBackend micdnBackend;
  string[] micdnPaths;
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

/// 未指定时的证书落点：放在各自代理配置目录下。
private string defaultCertificateDir(string engine) {
  return engine == "haproxy" ? "/etc/haproxy/certs" : "/etc/nginx/certs";
}

private Json objGet(Json obj, string key) {
  auto value = obj[key];
  return value.type == Json.Type.undefined || value.type == Json.Type.null_
      ? Json.emptyObject : value;
}

private string field(Json obj, string key) {
  auto value = obj[key];
  return value.type == Json.Type.string ? jsonText(value) : "";
}

private bool flag(Json obj, string key, bool fallback) {
  auto value = obj[key];
  return value.type == Json.Type.bool_ ? value.get!bool : fallback;
}

/// 把 Project 的 micdn 服务追加为所有 endpoint 共享的代理路径。
private void attachMicdn(ref ProxyModel model, const MicdnProjectView view) {
  auto config = view.state.config;
  auto servers = objGet(config, "servers");
  if (servers.type != Json.Type.array || servers.length == 0)
    return;
  auto listen = field(config, "listen");
  auto colon = listen.lastIndexOf(':');
  if (colon <= 0 || colon + 1 >= listen.length)
    return;
  ushort port;
  try
    port = listen[colon + 1 .. $].to!ushort;
  catch (Exception)
    return;
  ProxyServer[] targets;
  foreach (ref item; servers) {
    auto host = field(item, "host").strip;
    if (host.length == 0)
      continue;
    ProxyServer target;
    target.name = field(item, "name");
    target.ip = host;
    target.port = port;
    targets ~= target;
  }
  if (targets.length == 0)
    return;
  ProxyBackend backend;
  backend.name = "micdn";
  backend.servers = targets;
  model.micdnBackend = backend;

  bool staticBound, wwwBound;
  foreach (ref component; view.state.components) {
    if (component.kind == "static_bundle")
      staticBound = true;
    else if (component.kind == "www_doc") {
      wwwBound = true;
      // www doc 的 mountName 是 micdn 的对外路径（如 m/edu/learning），不是 webapp URL。
      auto mount = component.mountName.strip;
      if (mount.length > 0) {
        auto path = mount.startsWith("/") ? mount : "/" ~ mount;
        if (!model.micdnPaths.canFind(path))
          model.micdnPaths ~= path;
      }
    }
  }
  if (staticBound)
    model.micdnPaths ~= "/asset";
  if (wwwBound)
    model.micdnPaths ~= "/www";
  // maven/npm/native 在 micdn 配置中固定启用；代理路径必须始终包含。
  model.micdnPaths ~= "/maven";
  model.micdnPaths ~= "/npm";
  model.micdnPaths ~= "/native";
  // blob/static 由 micdn 提供；/std/spa 不是固定 micdn 路径，来自 webapp 或 www mount。
  model.micdnPaths ~= "/blob";
  model.micdnPaths ~= "/static";

}

/// 渲染项目代理；未指定 endpoint 时使用 default，否则第一个 endpoint。
string renderProxy(Store store, Registry reg, const ProjectContext context) {
  return renderProxyForEndpoint(store, reg, context, "");
}

private ProxyModel proxyModelForEndpoint(Store store, Registry reg, const ProjectContext context,
    string endpointName, string certificateDir, string routeMap) {
  auto data = loadProjectData(store, reg, context);
  string wanted = endpointName;
  if (wanted.length == 0 && data.endpoints.length > 0) {
    wanted = "default";
    bool hasDefault;
    foreach (endpoint; data.endpoints)
      if (attributeText(endpoint, "name") == "default") {
        hasDefault = true;
        break;
      }
    if (!hasDefault)
      wanted = attributeText(data.endpoints[0], "name");
  }
  if (wanted.length == 0)
    return ProxyModel.init;
  auto model = buildProxyModel(data, wanted);
  model.certificateDir = certificateDir.length ? certificateDir : defaultCertificateDir(model.engine);
  model.routeMap = routeMap.length ? routeMap
      : (model.engine == "haproxy" ? "/etc/haproxy/bas-routes.map" : "");
  MicdnProjectView micdn;
  if (loadMicdnProject(store, reg, context.id, micdn))
    attachMicdn(model, micdn);
  return model;
}

string renderProxyForEndpoint(Store store, Registry reg, const ProjectContext context,
    string endpointName, string certificateDir = "", string routeMap = "") {
  auto model = proxyModelForEndpoint(store, reg, context, endpointName, certificateDir, routeMap);
  if (model.engine == "nginx")
    return renderNginx(model);
  if (model.engine == "haproxy")
    return renderHaproxy(model);
  return "";
}

string renderHaproxyMapForEndpoint(Store store, Registry reg, const ProjectContext context,
    string endpointName, string routeMap = "") {
  auto model = proxyModelForEndpoint(store, reg, context, endpointName, "", routeMap);
  return model.engine == "haproxy" ? renderHaproxyMap(model) : "";
}

/// 从共享 Project 快照建立反代模型；指定 endpoint 时只保留引用它的 webapp。
ProxyModel buildProxyModel(ProjectData data, string endpointName = "") {
  ProxyModel model;
  model.project = data.project.data;

  string wanted = endpointName;
  if (wanted.length == 0 && data.endpoints.length > 0)
    wanted = attributeText(data.endpoints[0], "name");

  string endpointId;
  foreach (endpoint; data.endpoints) {
    if (attributeText(endpoint, "name") == wanted) {
      endpointId = jsonText(endpoint["id"]);
      model.endpointName = wanted;
      model.hostname = attributeText(endpoint, "domain").strip;
      model.engine = attributeText(endpoint, "engine").strip;
      // 没有证书时不能生成引用证书文件的 TLS 配置；即使 enableHttps 打开也退回 HTTP。
      auto hasCertificate = attributeText(endpoint, "certificate").strip.length > 0;
      auto enableHttps = hasCertificate && attributeBool(endpoint, "enableHttps");
      auto forceHttps = enableHttps && attributeBool(endpoint, "forceHttps");
      model.proxy = Json([
        "attributes": Json([
          "maxconn": Json(attributeLong(endpoint, "maxconn", 30000)),
          "httpPort": Json(attributeLong(endpoint, "httpPort", 80)),
          "httpsPort": Json(attributeLong(endpoint, "httpsPort", 443)),
          "enableHttps": Json(enableHttps),
          "forceHttps": Json(forceHttps),
          "sslCiphers": Json(attributeText(endpoint, "sslCiphers")),
          "sslProtocols": Json(attributeText(endpoint, "sslProtocols")),
        ]),
      ]);
      break;
    }
  }
  if (wanted.length && endpointId.length == 0)
    throw new Exception("unknown endpoint " ~ wanted);

  auto apps = data.webapps.dup;
  sort!((a, b) => attributeText(a, "contextPath") < attributeText(b, "contextPath"))(apps);

  ProxyWebapp[] normalApps;
  ProxyWebapp[] rootApps;
  foreach (app; apps) {
    if (endpointId.length && !relationshipIds(app, "endpoints").canFind(endpointId))
      continue;
    ProxyWebapp item;
    item.id = jsonText(app["id"]);
    item.contextPath = attributeText(app, "contextPath").strip;
    // 没有上下文的 deployments 是后台任务，不参与任何代理路由。
    if (item.contextPath.length == 0)
      continue;
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

private ProxyServer[] targetServers(Json webapp, const ProjectData data) {
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
    item.port = attributeLong(server, "httpPort");
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

private string farmOptions(const ProjectData data, string farmId) {
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

private struct ProxyRoute {
  string path;
  string backend;
}

/// 所有代理路径按“最长前缀优先”排序：HAProxy 的 use_backend 是首个匹配生效，
/// 不能把 /api/edu 放在 /api/edu/exam 前面。
private ProxyRoute[] proxyRoutes(ProxyModel model) {
  ProxyRoute[] routes;
  if (model.micdnBackend.servers.length)
    foreach (path; model.micdnPaths) {
      ProxyRoute route;
      route.path = path;
      route.backend = "micdn";
      routes ~= route;
    }
  foreach (webapp; model.webapps) {
    auto backend = model.backendByWebapp.get(webapp.id, "");
    if (backend.length == 0)
      continue;
    foreach (path; webapp.urlPaths) {
      ProxyRoute route;
      route.path = path;
      route.backend = backend;
      routes ~= route;
    }
  }
  sort!((a, b) => a.path.length != b.path.length
      ? a.path.length > b.path.length : a.path < b.path)(routes);
  return routes;
}

/// nginx：每个 webapp 的每个 urlPath 一个 location，后端来自 server 集合。
string renderNginx(ProxyModel model) {
  auto project = model.project;
  auto proxy = model.proxy;
  auto maxconn = attributeLong(proxy, "maxconn", 30000);
  auto httpPort = attributeLong(proxy, "httpPort", 80);
  auto httpsPort = attributeLong(proxy, "httpsPort", 443);
  auto hostname = model.hostname;
  auto sslProtocols = attributeText(proxy, "sslProtocols").strip;
  auto sslCiphers = attributeText(proxy, "sslCiphers").strip;
  if (sslProtocols.length == 0)
    sslProtocols = "TLSv1 TLSv1.1 TLSv1.2";
  if (sslCiphers.length == 0)
    sslCiphers = "HIGH:!aNULL:!MD5";
  auto enableHttps = attributeBool(proxy, "enableHttps");
  auto forceHttps = attributeBool(proxy, "forceHttps", true);

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
      auto text = "        server " ~ hostPort(server.ip, server.port);
      if (server.options.length > 0)
        text ~= " " ~ server.options;
      line(out_, text ~ ";");
    }
    line(out_, "    }");
  }

  if (model.micdnBackend.servers.length) {
    line(out_, "");
    line(out_, "    upstream micdn{");
    foreach (server; model.micdnBackend.servers)
      line(out_, "        server " ~ hostPort(server.ip, server.port) ~ ";");
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
  if (enableHttps) {
    auto legacy = model.endpointName.length == 0 || model.endpointName == "default";
    auto cert = legacy ? model.certificateDir ~ "/cert.pem"
        : model.certificateDir ~ "/" ~ model.endpointName ~ ".pem";
    auto key = legacy ? model.certificateDir ~ "/key.pem"
        : model.certificateDir ~ "/" ~ model.endpointName ~ ".key.pem";
    line(out_, "        ssl_certificate " ~ cert ~ ";");
    line(out_, "        ssl_certificate_key " ~ key ~ ";");
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

  foreach (route; proxyRoutes(model)) {
    line(out_, "        location " ~ route.path ~ " {");
    line(out_, "            proxy_pass http://" ~ route.backend ~ ";");
    line(out_, "        }");
  }
  line(out_, "    }");
  line(out_, "}");
  return out_.data;
}

/// HAProxy map_beg 路由文件：最长前缀由 HAProxy 自己选择，文件顺序不影响匹配。
string renderHaproxyMap(ProxyModel model) {
  auto routes = proxyRoutes(model);
  // map_beg 自己选择最长前缀，这里的顺序只用于人工检查；倒排后更接近浏览器的
  // 路径习惯，/api/edu/exam 在 /api/edu 之前，/ 最后。
  sort!((a, b) => a.path > b.path)(routes);
  auto out_ = appender!string;
  foreach (route; routes)
    line(out_, route.path ~ "  " ~ route.backend);
  return out_.data;
}

/// haproxy：完整主配置，直接包含 backend 与 use_backend 路由。
string renderHaproxy(ProxyModel model) {
  auto project = model.project;
  auto proxy = model.proxy;
  auto maxconn = attributeLong(proxy, "maxconn", 30000);
  auto httpPort = attributeLong(proxy, "httpPort", 80);
  auto httpsPort = attributeLong(proxy, "httpsPort", 443);
  auto hostname = model.hostname;
  auto sslProtocols = attributeText(proxy, "sslProtocols").strip;
  auto sslCiphers = attributeText(proxy, "sslCiphers").strip;
  if (sslProtocols.length == 0)
    sslProtocols = "no-sslv3 no-tlsv10";
  auto enableHttps = attributeBool(proxy, "enableHttps");
  auto forceHttps = attributeBool(proxy, "forceHttps", true);

  auto out_ = appender!string;
  line(out_, "# HAProxy main configuration generated by bashub.");
  line(out_, "#   -f /etc/haproxy/haproxy.cfg");
  line(out_, "global");
  line(out_, "    log         127.0.0.1 local2");
  line(out_, "    chroot      /var/lib/haproxy");
  line(out_, "    pidfile     /var/run/haproxy.pid");
  line(out_, "    maxconn     " ~ maxconn.to!string);
  line(out_, "    user        haproxy");
  line(out_, "    group       haproxy");
  line(out_, "    daemon");
  line(out_, "    tune.ssl.default-dh-param 2048");
  line(out_, "    ssl-default-bind-options no-sslv3 no-tlsv10");
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
  line(out_, "frontend main");
  line(out_, "    bind *:" ~ httpPort.to!string);
  if (enableHttps) {
    auto bundle = (model.endpointName.length == 0 || model.endpointName == "default")
        ? model.certificateDir ~ "/bundle.pem"
        : model.certificateDir ~ "/" ~ model.endpointName ~ ".bundle.pem";
    auto bind = "    bind *:" ~ httpsPort.to!string ~ " ssl crt " ~ bundle;
    if (sslCiphers.length > 0)
      bind ~= " ciphers " ~ sslCiphers;
    if (sslProtocols.length > 0)
      bind ~= " " ~ sslProtocols;
    line(out_, bind);
    line(out_, "    http-request set-header X-Forwarded-Proto https if { ssl_fc }");
    line(out_, "    http-request set-header X-Forwarded-Port %[dst_port] if { ssl_fc }");
  }
  auto routes = proxyRoutes(model);
  auto routeMap = model.routeMap.length ? model.routeMap : "/etc/haproxy/bas-routes.map";
  line(out_, "    http-request set-var(req.backend) path,map_beg(" ~ routeMap ~ ")");
  if (enableHttps && forceHttps) {
    line(out_, "    redirect scheme https if !{ ssl_fc } { hdr_beg(host) " ~ hostname ~ " }");
  }
  line(out_, "");
  line(out_, "    use_backend %[var(req.backend)] if { var(req.backend) -m found }");
  foreach (route; routes)
    if (route.path == "/") {
      line(out_, "    default_backend " ~ route.backend);
      break;
    }
  line(out_, "");

  auto backends = model.backends.dup;
  if (model.micdnBackend.servers.length) {
    bool hasMicdn;
    foreach (backend; backends)
      if (backend.name == "micdn") {
        hasMicdn = true;
        break;
      }
    if (!hasMicdn)
      backends ~= model.micdnBackend;
  }
  sort!((a, b) => a.name < b.name)(backends);
  foreach (backend; backends) {
    line(out_, "");
    line(out_, "backend " ~ backend.name);
    if (!backend.options.canFind("balance "))
      line(out_, "    balance roundrobin");
    if (backend.options.length > 0)
      putIndented(out_, backend.options, "    ");
    foreach (index, server; backend.servers) {
      auto name = server.name.length > 0 ? server.name : "s" ~ (index + 1).to!string;
      auto options = server.options.strip;
      if (!options.canFind("check"))
        options = options.length > 0 ? options ~ " check" : "check";
      auto text = "    server " ~ name ~ " " ~ hostPort(server.ip, server.port) ~ " " ~ options;
      line(out_, text);
    }
  }
  return out_.data;
}

/// HAProxy/Nginx 的 IPv6 地址必须带方括号。
private string hostPort(string host, long port) {
  auto formatted = host.canFind(":") && !host.startsWith("[") ? "[" ~ host ~ "]" : host;
  return formatted ~ ":" ~ port.to!string;
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
