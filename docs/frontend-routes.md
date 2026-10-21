# 前端路由与后端 API 对应表

本文整理 SPA 页面路由、资源列表和后端 API 的对应关系，便于定位页面请求、调整路由或在新增资源时同步修改。

## 基本约定

后端 API 根前缀缺省为 `/api/bashub`，并按能力域分组：

| 能力域 | 前缀 | 负责内容 |
|---|---|---|
| EMS | `/api/bashub/ems` | 菜单、channel、菜单关联资源，以及 EMS 运行时配置、会话和菜单 XML |
| 平台配置 | `/api/bashub/config` | Profile、构件、群集、主机等平台配置资源，以及配置分发、代理、证书、setline 和主机脚本 |
| Micdn | `/api/bashub/micdn` | Profile 的 Micdn 聚合配置、组件目录与 `micdn.xml` |
| 监控 | `/api/bashub/monitor` | 在线节点、立即上报、日志、SSE 跟随、实例启停与 WebSocket 通道 |

| 项目 | 约定 |
|---|---|
| SPA 基址 | `/bashub/`，由 `VITE_APP_BASE` 控制 |
| EMS API | `/api/bashub/ems` |
| 平台配置 API | `/api/bashub/config` |
| 机器配置 API | `/api/bashub/config/{profile}` |
| Micdn API | `/api/bashub/micdn` |
| 监控 API | `/api/bashub/monitor` |
| URL 后缀 | `.json` / `.jsonapi` 可省略，路由匹配前会剥离 |
| `{id}` | 数据库主键，用于管理台详情和 JSON:API 资源 |
| `{profile}` | 配置的 `qualifiedName`，例如 `orgName.profileName` |
| `{farmIds}` | 逗号分隔的群集 id，用于一次查询多个群集下的服务 |
| `{appId}` / `{appName}` | 前者是 EMS 应用的数据库 id，后者是 EMS 应用名 |

管理台 JSON:API 资源按归属拆分：

| 能力域 | 资源 |
|---|---|
| `/api/bashub/ems` | `channels`、`menus`、`resources` |
| `/api/bashub/config` | `organizations`、`platforms`、`profiles`、`engines`、`farms`、`servers`、`hosts`、`artifacts`、`webapps`、`platform-features`、`platform-feature-scripts`、`apps`、`app-groups` |

所有接口在本文中都写完整路径，不再省略能力域前缀。API 路径必须带能力域；不存在
`/api/bashub/{profile}`、`/api/bashub/{resource}` 这类无域兼容入口。

SPA 页面路由与 API 能力域不强制一一对应：一个页面可以同时调用多个域的接口。旧前端路由只会由 Vue Router
重定向到新页面，不是后端 API 别名。

## 启动期接口

| API | 用途 |
|---|---|
| `GET /api/bashub/ems/configs.json` | 登录前读取 EMS/CAS 等运行时配置，不校验登录 |
| `GET /api/bashub/ems/sessions` | 获取当前会话用户 |
| `POST /api/bashub/ems/sessions/logout` | 清理本地会话和 cookie，返回 CAS 登出地址 |

## 列表与配置页

下表“资源基路径”是页面通用 CRUD 的 JSON:API 基路径，具体方法见
[通用资源 CRUD](#通用资源-crud)。

| 前端路由 | 页面/资源 | 资源基路径 | 额外接口或说明 |
|---|---|---|---|
| `/home` | 概览，`HomeView` | 无 | 只提供页面导航；启动期使用 `configs` / `sessions` |
| `/org-config?tab=profiles` | 配置管理，`profiles` | `/api/bashub/config/profiles` | — |
| `/org-config?tab=organizations` | 机构管理，`organizations` | `/api/bashub/config/organizations` | — |
| `/engines` | 引擎管理，`engines` | `/api/bashub/config/engines` | — |
| `/farm-hosts?tab=farms` | 群集管理，`farms` | `/api/bashub/config/farms` | 行内“维护”跳到 `/servers?farm={id}` |
| `/farm-hosts?tab=hosts` | 主机管理，`hosts` | `/api/bashub/config/hosts` | 名称链接跳到 `/hosts/{id}` |
| `/servers`（含 `/servers?farm={id}`） | 服务管理，`servers` | `/api/bashub/config/servers` | 从属页面，不单独占菜单 |
| `/artifacts` | 组件管理，`artifacts` | `/api/bashub/config/artifacts` | 批量刷新版本：`POST /api/bashub/config/artifacts/update-version` |
| `/webapps` | 应用部署，`webapps` | `/api/bashub/config/webapps` | 批量升级：`POST /api/bashub/config/webapps/upgrade` |
| `/platform-ops?tab=platform-features` | 平台功能，`platform-features` | `/api/bashub/config/platform-features` | 名称链接跳到 `/platform-features/{id}` |
| `/platform-ops?tab=platforms` | 平台管理，`platforms` | `/api/bashub/config/platforms` | — |
| `/app-config?tab=apps` | 应用管理，`apps` | `/api/bashub/config/apps` | — |
| `/app-config?tab=channels` | 应用端，`channels` | `/api/bashub/ems/channels` | — |
| `/app-config?tab=app-groups` | 应用分组，`app-groups` | `/api/bashub/config/app-groups` | — |
| `/menu-config?tab=menus` | 菜单管理，`menus` | `/api/bashub/ems/menus` | 导出、导入及支持 `indexno` 重排的新增/修改接口见下文 |
| `/menu-config?tab=resources` | 资源管理，`resources` | `/api/bashub/ems/resources` | 列表 CSV 由前端生成，不调用后端 |

`ResourceTabsView` 只是带页签的容器；实际请求由当前页签对应的 `ResourceListView` 按上表发出。
前端 `resourceApiPath()` 按资源名选择 `ems` / `config`，因此同一个页签组可以调用两个域。
表单和筛选器中的引用下拉会调用对应资源的搜索接口，例如
`GET /api/bashub/config/profiles/search?page[size]=300&sort=name`。

## 详情与运维页

| 前端路由 | 页面 | 后端 API |
|---|---|---|
| `/profiles/:id` | 配置详情，`ProfileDetailView` | `GET /api/bashub/config/profiles/{id}?include=org`<br>`GET /api/bashub/config/farms/search?filter[farm.profile.id]={id}&include=engine`<br>`GET /api/bashub/config/hosts/search?filter[host.profile.id]={id}`<br>`GET /api/bashub/config/webapps/search?filter[webapp.profile.id]={id}&include=artifact`<br>`GET /api/bashub/config/servers/search?filter[server.farm.id]={farmIds}&include=farm,host`<br>`GET /api/bashub/monitor/agents/status`<br>`GET /api/bashub/config/profiles/{id}/proxy`<br>`GET /api/bashub/config/profiles/{id}/server`<br>`GET /api/bashub/config/profiles/{id}/setline-peers`<br>`GET /api/bashub/micdn/profiles/{id}` |
| `/profiles/:id/micdn` | Micdn 配置，`MicdnProfileView` | `GET /api/bashub/micdn/profiles/{id}`<br>`PATCH /api/bashub/micdn/profiles/{id}`<br>`GET /api/bashub/micdn/profiles/{id}/micdn.xml` |
| `/cdn-components` | Micdn 组件目录，`CdnComponentsView` | `GET /api/bashub/micdn/components`<br>`POST /api/bashub/micdn/components`<br>`PATCH /api/bashub/micdn/components/{id}`<br>`DELETE /api/bashub/micdn/components/{id}` |
| `/platform-features/:id` | 平台功能详情，`PlatformFeatureDetailView` | `GET /api/bashub/config/platform-features/{id}`、`PATCH /api/bashub/config/platform-features/{id}`<br>`GET /api/bashub/config/platform-features/search`<br>`GET /api/bashub/config/platforms/search`<br>`GET /api/bashub/config/platform-feature-scripts/search?filter[platformFeatureScript.feature.id]={id}`<br>`POST /api/bashub/config/platform-feature-scripts`<br>`PATCH /api/bashub/config/platform-feature-scripts/{id}`、`DELETE /api/bashub/config/platform-feature-scripts/{id}` |
| `/hosts/:id` | 主机详情，`HostDetailView` | `GET /api/bashub/config/hosts/{id}?include=profile,profile.org,platform,features`<br>`GET /api/bashub/config/servers/search?filter[server.host.id]={id}&include=farm`<br>`GET /api/bashub/config/hosts/{id}/webapps?include=artifact`<br>脚本下载：`GET /api/bashub/config/{profile}/script/{hostIp}.sh` |
| `/agents` | 在线节点，`AgentView` | `GET /api/bashub/monitor/agents/status`<br>`POST /api/bashub/monitor/agents/{profile}/report`<br>`POST /api/bashub/monitor/agents/{profile}/service/{action}`，`action` 为 `start` / `stop` / `restart`<br>`GET /api/bashub/monitor/agents/{profile}/log?instance=...`<br>SSE：`GET /api/bashub/monitor/agents/{profile}/log/follow?instance=...&tail=...` |

`/profiles/:id` 只有在存在群集时才请求 `servers/search`；`{farmIds}` 是这些群集 id 的逗号分隔值。
主机详情页的脚本下载使用机器端点，不在 `/hosts` 资源下；这里的 `{profile}` 是配置的
`qualifiedName`，`{hostIp}` 是该主机的 IP。

## 通用资源 CRUD

平台配置资源使用 `config` 域：

| 操作 | 方法与路径 | 说明 |
|---|---|---|
| 列表 | `GET /api/bashub/config/{resource}/search` | 支持 `page[size]`、`sort`、`filter[...]`、`include` |
| 新建 | `POST /api/bashub/config/{resource}` | JSON:API 文档 |
| 详情 | `GET /api/bashub/config/{resource}/{id}` | JSON:API 文档 |
| 修改 | `PATCH /api/bashub/config/{resource}/{id}` | JSON:API 文档 |
| 删除 | `DELETE /api/bashub/config/{resource}/{id}` | 成功返回空 JSON:API 文档 |

EMS 自身资源使用 `ems` 域：

| 操作 | 方法与路径 |
|---|---|
| 列表 | `GET /api/bashub/ems/{resource}/search` |
| 新建 | `POST /api/bashub/ems/{resource}` |
| 详情 | `GET /api/bashub/ems/{resource}/{id}` |
| 修改 | `PATCH /api/bashub/ems/{resource}/{id}` |
| 删除 | `DELETE /api/bashub/ems/{resource}/{id}` |

两个域都只暴露 `hubRegistry()` 中登记且属于该域的资源。Micdn 专用的 `cdn-components`、
`profile-micdn`、`profile-micdn-components` 不在任何管理台通用 CRUD 中，分别使用
`/api/bashub/micdn/components` 和 `/api/bashub/micdn/profiles/{id}`。

菜单新增与修改虽然仍使用 `POST /api/bashub/ems/menus`、`PATCH /api/bashub/ems/menus/{id}`，但由专用处理器
处理 `indexno` 并重排同级节点，不使用通用 CRUD 处理器。

### 专用查询与批量动作

| API | 使用页面 | 说明 |
|---|---|---|
| `POST /api/bashub/config/artifacts/update-version` | `/artifacts` | Body 为 `{"ids":[...]}`，从 Maven Central 刷新所选组件的最新版本 |
| `POST /api/bashub/config/webapps/upgrade` | `/webapps` | Body 为 `{"ids":[...]}`，把所选应用版本提升到组件的 `latestVersion` |
| `GET /api/bashub/config/hosts/{id}/webapps?include=artifact` | `/hosts/:id` | 查询部署到该主机上的应用 |
| `GET /api/bashub/ems/menus/export?app={appId}` | `/menu-config?tab=menus` | 返回 `{"xml":"..."}` |
| `POST /api/bashub/ems/menus/import` | `/menu-config?tab=menus` | `multipart/form-data`，字段 `app` + `menufile` |

不能把 `POST /api/bashub/{group}/{resource}/{action}` 当作所有资源的通用约定；批量动作是逐项登记的。

## 已有但未接入 SPA 的管理端点

| API | 用途 |
|---|---|
| `POST /api/bashub/config/profiles/{id}/reset-key` | 重置配置令牌，返回新 key |
| `GET /api/bashub/config/artifacts/{id}/webapps` | 查询使用某构件的应用部署 |
| `GET /api/bashub/ems/resources/{id}/menus` | 查询引用某资源的菜单 |

## 机器端点

以下接口供 basctl、setline、micdn 等客户端使用，不对应 SPA 页面：

| API | 使用方/用途 |
|---|---|
| `GET /api/bashub/config/{profile}/server` | basctl 拉取 `server.xml` |
| `GET /api/bashub/config/{profile}/proxy` | 下载 haproxy/nginx 代理配置 |
| `GET /api/bashub/config/{profile}/certificate` | 下载 HTTPS 公钥证书 |
| `GET /api/bashub/config/{profile}/certificate-key` | 下载 HTTPS 私钥 |
| `GET /api/bashub/config/{profile}/setline-peers` | setline 拉取 peer 列表 |
| `GET /api/bashub/config/{profile}/setline-manifest` | setline 拉取资源摘要清单 |
| `GET /api/bashub/config/{profile}/script/{host}` | 下载主机检查脚本 |
| `GET /api/bashub/ems/{profile}/menus/{appName}` | 拉取应用的 EMS 菜单与资源 XML |
| `GET /api/bashub/micdn/{profile}/micdn.xml` | micdn 下载完整配置 |
| `WS /api/bashub/monitor/agents/{profile}/channel` | basctl 建立节点通道 |

机器端点的鉴权和配置分发细节见 [`frontend-api.md`](frontend-api.md)。

## 旧 SPA 路由重定向

资源被页签组合并后，旧列表路径仍可由前端访问，并会带上原有查询条件重定向到新页签。这里只涉及浏览器页面路由，
不会在后端生成同名的无域 API：

| 旧前端路由 | 新前端路由 |
|---|---|
| `/profiles`、`/organizations` | `/org-config?tab=profiles`、`/org-config?tab=organizations` |
| `/platform-features`、`/platforms` | `/platform-ops?tab=platform-features`、`/platform-ops?tab=platforms` |
| `/farms`、`/hosts` | `/farm-hosts?tab=farms`、`/farm-hosts?tab=hosts` |
| `/apps`、`/channels`、`/app-groups` | `/app-config?tab=apps`、`/app-config?tab=channels`、`/app-config?tab=app-groups` |
| `/menus`、`/resources` | `/menu-config?tab=menus`、`/menu-config?tab=resources` |

`/profiles/:id`、`/hosts/:id`、`/platform-features/:id` 是详情页，不参与上述列表重定向。旧路径 `/profiles`
只是 SPA 重定向，对应 API 是 `/api/bashub/config/profiles/...`，而不是 `/api/bashub/profiles/...`。

## 维护来源

| 内容 | 来源 |
|---|---|
| API 能力域与 EMS 资源集合 | `src/bashub/api.d` |
| 前端路由 | `packages/web/src/router/index.ts` |
| 资源路径、页签组和表单元数据 | `packages/web/src/resources/index.ts` |
| 前端资源域选择 | `packages/web/src/api/prefix.ts` 的 `resourceApiPath()` |
| 前端 API 封装 | `packages/web/src/api/` |
| 后端路由注册 | `src/bashub/route.d` 的 `buildHubRouter` |
| 鉴权资源名 | `src/bashub/security.d` 的 `resourceNameOf` |
| 机器端点渲染 | `src/bashub/profile/` |

新增或调整路由时，至少同步更新能力域定义、路由定义、资源元数据、前端 API 封装和本文表格。
