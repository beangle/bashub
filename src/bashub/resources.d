/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module bashub.resources;
/// BAS 控制台的资源定义：JSON:API 的「资源 → 表/列/关系」只有这一处真相。
/// 表名/列名/属性名全部写死，没有运行期反射；加一个资源只是在这里加一条 `Resource`，路由不用改。

import beangle.data.resource : Column, Derived, Kind, ManyRelation, Registry, Relation, Resource, ValueList;

import std.string : endsWith;

/// 管理台资源：与前端 `packages/web/src/resources/index.ts` 及 `db-0.0.8.xml` 对齐。
/// 自定义动作（版本刷新、菜单导入导出、静态包 gav/location 拆分）仍由应用端点承担。
Registry hubRegistry() {
  auto items = [
    Resource(
      "organizations", "organizations", "bas.cfg_organizations", "id",
      [
        Column("name", "name", Kind.text),
        Column("title", "title", Kind.text),
        Column("short_title", "shortTitle", Kind.text),
        Column("logo_url", "logoUrl", Kind.text),
      ],
      [], [],
      "name"),
    Resource(
      "platforms", "platforms", "bas.cfg_platforms", "id",
      [
        Column("name", "name", Kind.text),
        Column("major_version", "majorVersion", Kind.text),
        Column("fonticon", "fonticon", Kind.text),
      ],
      [], [],
      "name"),
    Resource(
      "profiles", "profiles", "bas.cfg_profiles", "id",
      [
        Column("name", "name", Kind.text),
        Column("title", "title", Kind.text),
        Column("bas_version", "basVersion", Kind.text),
        Column("ip", "ip", Kind.text),
        Column("hostname", "hostname", Kind.text),
        Column("http_port", "httpPort", Kind.number),
        Column("https_port", "httpsPort", Kind.number),
        Column("enable_https", "enableHttps", Kind.boolean),
        Column("force_https", "forceHttps", Kind.boolean),
        Column("maxconn", "maxconn", Kind.number),
        Column("proxy_engine", "proxyEngine", Kind.text),
        Column("local_repo", "localRepo", Kind.text),
        Column("remote_repo", "remoteRepo", Kind.text),
        Column("ssl_ciphers", "sslCiphers", Kind.text),
        Column("ssl_protocols", "sslProtocols", Kind.text),
        Column("ssl_certificate", "sslCertificate", Kind.text),
        Column("ssl_certificate_key", "sslCertificateKey", Kind.text),
        Column("key", "key", Kind.text, true, "\"key\""),
      ],
      [Relation("org", "org_id", "organizations")],
      [
        Derived("qualifiedName", ["org"], "{org.name}.{name}"),
        Derived("qualifiedTitle", ["org"], "{org.shortTitle}{title}"),
      ],
      "name",
      []),
    Resource(
      "engines", "engines", "bas.cfg_engines", "id",
      [
        Column("name", "name", Kind.text),
        Column("typ", "typ", Kind.text),
        Column("version", "version", Kind.text),
        Column("remark", "remark", Kind.text),
        Column("jsp_support", "jspSupport", Kind.boolean),
        Column("websocket_support", "websocketSupport", Kind.boolean),
      ],
      [Relation("profile", "profile_id", "profiles")],
      [],
      "name",
      [
        ValueList("listeners", "bas.cfg_engines_listeners", "engine_id", "value_"),
        ValueList("jars", "bas.cfg_engines_jars", "engine_id", "value_"),
      ]),
    Resource(
      "farms", "farms", "bas.cfg_farms", "id",
      [
        Column("name", "name", Kind.text),
        Column("max_heap_size", "maxHeapSize", Kind.number),
        Column("server_options", "serverOptions", Kind.text),
        Column("proxy_options", "proxyOptions", Kind.text),
      ],
      [
        Relation("engine", "engine_id", "engines"),
        Relation("profile", "profile_id", "profiles"),
      ],
      [],
      "name",
      [],
      [
        ManyRelation("hosts", "hosts", "bas.cfg_farms_hosts", "farm_id", "host_id"),
        ManyRelation("servers", "servers", "bas.cfg_servers", "farm_id", "id", false),
      ]),
    Resource(
      "servers", "servers", "bas.cfg_servers", "id",
      [
        Column("name", "name", Kind.text),
        Column("http_port", "httpPort", Kind.number),
        Column("max_heap_size", "maxHeapSize", Kind.number),
        Column("proxy_http_port", "proxyHttpPort", Kind.number),
        Column("proxy_options", "proxyOptions", Kind.text),
      ],
      [
        Relation("farm", "farm_id", "farms"),
        Relation("host", "host_id", "hosts"),
      ],
      [Derived("qualifiedName", ["farm"], "{farm.name}.{name}")],
      "name"),
    Resource(
      "hosts", "hosts", "bas.cfg_hosts", "id",
      [
        Column("name", "name", Kind.text),
        Column("ip", "ip", Kind.text),
        Column("memory", "memory", Kind.number),
        Column("cores", "cores", Kind.number),
        Column("cpu", "cpu", Kind.text),
        Column("platform_version", "platformVersion", Kind.text),
        Column("arch", "arch", Kind.number),
      ],
      [
        Relation("profile", "profile_id", "profiles"),
        Relation("platform", "platform_id", "platforms"),
      ],
      [],
      "name",
      [],
      [ManyRelation("features", "platform-features", "bas.cfg_hosts_features", "host_id", "platform_feature_id")]),
    Resource(
      "artifacts", "artifacts", "bas.cfg_artifacts", "id",
      [
        Column("artifact_id", "artifactId", Kind.text),
        Column("classifier", "classifier", Kind.text),
        Column("context_path", "contextPath", Kind.text),
        Column("description", "description", Kind.text),
        Column("group_id", "groupId", Kind.text),
        Column("latest_version", "latestVersion", Kind.text),
        Column("packaging", "packaging", Kind.text),
        Column("title", "title", Kind.text),
        Column("arch", "arch", Kind.number),
        Column("jsp_support", "jspSupport", Kind.boolean),
        Column("resolve_support", "resolveSupport", Kind.boolean),
        Column("websocket_support", "websocketSupport", Kind.boolean),
      ],
      [Relation("profile", "profile_id", "profiles")],
      [],
      "artifact_id"),
    Resource(
      "webapps", "webapps", "bas.cfg_webapps", "id",
      [
        Column("version", "version", Kind.text),
        Column("context_path", "contextPath", Kind.text),
        Column("urls", "urls", Kind.jsonArray),
        Column("unpack", "unpack", Kind.boolean),
        Column("libs", "libs", Kind.text),
      ],
      [
        Relation("artifact", "artifact_id", "artifacts"),
        Relation("profile", "profile_id", "profiles"),
      ],
      [],
      "context_path",
      [],
      [ManyRelation("targets", "servers", "bas.cfg_webapps_targets", "webapp_id", "server_id")]),
    Resource(
      "platform-features", "platformFeatures", "bas.cfg_platform_features", "id",
      [
        Column("name", "name", Kind.text),
        Column("version", "version", Kind.text),
        Column("logo", "logo", Kind.text),
        Column("description", "description", Kind.text),
      ],
      [],
      [],
      "name",
      [],
      [
        ManyRelation("dependencies", "platform-features", "bas.cfg_platform_features_dependencies",
            "from_feature_id", "platform_feature_id"),
      ]),
    Resource(
      "platform-feature-scripts", "platformFeatureScripts", "bas.cfg_platform_feature_scripts", "id",
      [Column("scripts", "scripts", Kind.text)],
      [
        Relation("feature", "feature_id", "platform-features"),
        Relation("platform", "platform_id", "platforms"),
      ],
      [],
      "id"),
    Resource(
      "app-groups", "appGroups", "bas.ems_app_groups", "id",
      [
        Column("name", "name", Kind.text),
        Column("title", "title", Kind.text),
      ],
      [], [], "name"),
    Resource(
      "apps", "apps", "bas.ems_apps", "id",
      [
        Column("artifact_id", "artifactId", Kind.text),
        Column("name", "name", Kind.text),
        Column("title", "title", Kind.text),
        Column("services", "services", Kind.text),
      ],
      [Relation("group", "group_id", "app-groups")],
      [Derived("qualifiedTitle", ["group"], "{group.title}.{title}")],
      "name"),
    Resource(
      "channels", "channels", "bas.ems_channels", "id",
      [
        Column("base", "base", Kind.text),
        Column("channel_type", "channelType", Kind.text),
        Column("embed_mode", "embedMode", Kind.text),
        Column("enabled", "enabled", Kind.boolean),
      ],
      [Relation("app", "app_id", "apps")],
      [],
      "base"),
    Resource(
      "resources", "resources", "bas.ems_resources", "id",
      [
        Column("name", "name", Kind.text),
        Column("title", "title", Kind.text),
        Column("scope", "scope", Kind.number, true, "\"scope\"", ["Public", "Protected", "Private"]),
        Column("actions", "actions", Kind.text),
        Column("enabled", "enabled", Kind.boolean),
        Column("remark", "remark", Kind.text),
      ],
      [Relation("app", "app_id", "apps")],
      [],
      "name"),
    Resource(
      "menus", "menus", "bas.ems_menus", "id",
      [
        Column("name", "name", Kind.text),
        Column("en_name", "enName", Kind.text),
        Column("indexno", "indexno", Kind.text),
        Column("fonticon", "fonticon", Kind.text),
        Column("params", "params", Kind.text),
        Column("enabled", "enabled", Kind.boolean),
        Column("remark", "remark", Kind.text),
      ],
      [
        Relation("app", "app_id", "apps"),
        Relation("parent", "parent_id", "menus"),
        Relation("entry", "entry_id", "resources"),
      ],
      [Derived("entryUrl", ["entry"], "{entry.name}?{params}")],
      "indexno",
      [],
      [ManyRelation("resources", "resources", "bas.ems_menus_resources", "menu_id", "resource_id")]),
    Resource(
      "cdn-components", "cdnComponents", "bas.cdn_components", "id",
      [
        Column("kind", "kind", Kind.text),
        Column("name", "name", Kind.text),
        Column("mount_name", "mountName", Kind.text),
        Column("remark", "remark", Kind.text),
        Column("spec", "spec", Kind.jsonDocument),
      ],
      [],
      [],
      "name"),
    Resource(
      "profile-micdn", "profileMicdn", "bas.cfg_profile_micdn", "profile_id",
      [Column("config", "config", Kind.jsonDocument)],
      [],
      [],
      "profile_id"),
    Resource(
      "profile-micdn-components", "profileMicdnComponents", "bas.cfg_profile_micdn_components", "id",
      [Column("sortno", "sortno", Kind.number)],
      [
        Relation("profile", "profile_id", "profiles"),
        Relation("component", "component_id", "cdn-components"),
      ],
      [],
      "sortno"),
  ];
  foreach (ref item; items) {
    item.entityAlias = aliasOf(item.path);
    item.required = requiredOf(item.path);
  }
  return new Registry(items);
}

/// 与前端 `packages/web/src/resources/index.ts` 的 `required: true` 对齐。
private string[] requiredOf(string path) {
  switch (path) {
  case "organizations":
    return ["name", "title"];
  case "platforms":
    return ["name"];
  case "profiles":
    return ["name", "title", "basVersion", "ip"];
  case "engines":
    return ["name", "typ", "version"];
  case "farms":
    return ["name", "profile", "engine", "maxHeapSize"];
  case "servers":
    return ["name", "farm", "host"];
  case "hosts":
    return ["name", "ip", "profile", "platform", "platformVersion", "memory", "arch", "cores", "cpu"];
  case "artifacts":
    return ["title", "artifactId", "groupId", "packaging", "latestVersion"];
  case "webapps":
    return ["artifact", "profile", "version", "contextPath"];
  case "platform-features":
    return ["name", "version", "logo"];
  case "apps":
    return ["name", "title", "group", "artifactId"];
  case "channels":
    return ["app", "base", "channelType", "embedMode"];
  case "app-groups":
    return ["name", "title"];
  case "menus":
    return ["app", "name", "enName", "indexno"];
  case "resources":
    return ["app", "name", "title"];
  case "cdn-components":
    return ["kind", "name", "mountName", "spec"];
  case "profile-micdn":
    return ["config"];
  case "profile-micdn-components":
    return ["profile", "component", "sortno"];
  default:
    return null;
  }
}

/// 前端 schema 的 alias 与复数是同一套，只有三个带连字符的例外。
private string aliasOf(string path) {
  switch (path) {
  case "platform-features":
    return "platformFeature";
  case "platform-feature-scripts":
    return "platformFeatureScript";
  case "app-groups":
    return "appGroup";
  case "cdn-components":
    return "cdnComponents";
  case "profile-micdn":
    return "profileMicdn";
  case "profile-micdn-components":
    return "profileMicdnComponents";
  default:
    return path.endsWith("s") ? path[0 .. $ - 1] : path;
  }
}
