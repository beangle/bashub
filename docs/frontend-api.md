# 后端 API 契约

后端**只提供 API**，页面由独立部署的 SPA 渲染。D 侧路由按能力域分组：

| 用途 | 前缀 | 实现包 | 风格 |
|---|---|---|---|
| EMS | `/api/bashub/ems` | `bashub.route` + `beangle.jsonapi` | 应用/分组/菜单/channel/资源 JSON:API、运行时配置与会话 |
| 平台配置与分发 | `/api/bashub/config` | `bashub.route` + `bashub.project.*` | 平台配置 JSON:API、文本/XML 配置下载 |
| Micdn | `/api/bashub/micdn` | `bashub.project.micdnconfig` | 聚合 JSON 与 XML |
| 监控 | `/api/bashub/monitor` | `bashub.agent.*` | JSON、SSE 与 WebSocket |

URL 契约由 `test/bashub/route_test.d` 覆盖，路由变更以该测试为准。

前端页面路由、列表页资源与这些接口的逐页对应见
[`frontend-routes.md`](frontend-routes.md)。

## 通用约定

- 请求头：`Accept: application/vnd.api+json`（JSON:API 文档），写操作另加 `Content-Type: application/vnd.api+json`。
- URL 后缀（`.json` / `.jsonapi`）在路由前被剥掉，只影响响应格式；两者都可省略。
- JSON/XHR 请求未登录返回 `401`，响应体为
  `{"errors":[{"status":401,"meta":{"redirectUrl":"<CAS 登录地址>"}}]}`；浏览器导航请求直接 302。
- 已登录但无权访问返回 `403`，响应体是标准 JSON:API 错误文档。
- `GET /api/bashub/ems/configs` 不校验登录；其余管理接口默认要求登录。应用文件的
  `<app auth="required">` 是缺省值；只有本机开发才可显式写 `<app auth="none">`，且监听地址必须是
  `localhost` / `127.0.0.1` / `[::1]`，否则 bashub 拒绝启动。
- API 路径必须带能力域；不注册 `/api/bashub/{project}`、`/api/bashub/{resource}` 这类无域别名。
- EMS 权限资源名使用应用内路径 `/{能力域}/{资源}`，不包含可部署变化的 `/api/bashub` 根前缀，
  例如 `/ems/apps`、`/ems/app-groups`、`/ems/menus`、`/config/projects`。
- 分页参数用 `page[number]` / `page[size]`；两者缺失时后端读 cookie `pageSize`，再缺省为 20。
- 排序用 `sort`（`-` 前缀表示倒序）。过滤用 `filter[<属性>]`（如 `filter[project.name]=demo`）；
  多值可用逗号或分号分隔，文本 2–3 个按 `or`，4 个以上及非文本列按 `in`。
- 显式算子写成 `filter[<属性>][<op>]`，支持 `between`、`ge`、`gt`、`le`、`lt`、`in`、`nin`、`eq`、`ne`。
- 列表响应为 JSON:API 文档，分页信息在 `meta.page`：`{number, size, total}`。
- 上传接口是 `multipart/form-data`，**不要设置 `Content-Type`**（boundary 由浏览器生成）。
- 跨域由 `<api cors-origins="...">` 白名单控制（也接受主机名）；同源请求不下发 CORS 头，
  允许来源的预检回 204，不允许的来源回 403。API 响应带 `Cache-Control: no-store`，并统一带
  `X-Content-Type-Options: nosniff`、`Referrer-Policy`；HTTPS 下带 HSTS。

## 前端客户端

SPA 统一使用 `@beangle/ems-app` 的 `EmsJsonApiClient`（`packages/web/src/api/client.ts`），它负责内容协商、
`page[...]`/`filter[...]` 查询串、`URP_SID` 追加与 401/302 跳 CAS。后端接受会话 cookie、
`Authorization: Bearer <CAS session id>` 和 `URP_SID` 查询参数三种登录凭证：

| 方法 | 用途 |
|---|---|
| `get` / `post` / `patch` / `delete` | JSON:API 读写 |
| `upload(path, formData)` | multipart 上传（菜单 XML） |
| `getPlain(path, {query})` | 取非 JSON:API 结构的普通 JSON（如 `{xml}`） |

`packages/web/src/api/resource.ts` 在此基础上提供了通用资源的 `listResource` / `saveResource` /
`removeResource` / `callResourceAction` / `uploadResourceFile`，各页面由 `src/resources/index.ts` 的元数据驱动。
`resourceApiPath()` 按主表前缀选择能力域：`bas.ems_*` 资源（`apps`、`app-groups`、
`channels`、`menus`、`resources`）走 `ems`，`bas.cfg_*` 资源走 `config`。

## `/api/bashub/ems`

### 配置 `configs`

- `GET /api/bashub/ems/configs.json`（**不校验登录**，登录前就要可读，否则前端无从得知 CAS 地址）

按 ems-app 的约定**只下发 `ems_base`**，CAS 地址由前端在该地址后拼 `/cas`：

```json
{
  "ems_base": "https://sas.openurp.net",
  "app_name": "bas-hub",
  "logoUrl": "https://sas.openurp.net/api/platform/config/domains/logo"
}
```

### 会话 `sessions`

- `GET /api/bashub/ems/sessions`：当前登录用户 `{code, name}`
- `POST /api/bashub/ems/sessions/logout`：清理本地会话与 cookie，返回 `{"logoutUrl": "<CAS 登出地址>"}`；
  前端随后跳转 CAS `/logout?service=<当前页面>`，不做后通道单点登出
- 浏览器登录跳转 `{cas}/login?service=<当前页面>`；CAS 回跳带 `ticket` 时，后端用
  `{cas}/serviceValidate` 校验，并把 CAS 的 `authorities` / `permissions` 映射到当前账户。

### 资源（JSON:API）

`ems` 域只暴露 EMS 自身的数据；`configs`、`sessions` 虽不是 CRUD 资源，也作为 EMS 运行时接口保留在这里。

| 操作 | 方法与 URL |
|---|---|
| 查询列表 | `GET /api/bashub/ems/{resource}/search` |
| 新建 | `POST /api/bashub/ems/{resource}` |
| 查看 | `GET /api/bashub/ems/{resource}/{id}` |
| 修改 | `PATCH /api/bashub/ems/{resource}/{id}` |
| 删除 | `DELETE /api/bashub/ems/{resource}/{id}` |

| `{resource}` | 实体 | 说明 |
|---|---|---|
| `apps` | App | EMS 应用登记（`bas.ems_apps`），只登记应用本身（名称/标题/分组/artifactId/依赖项），部署上下文与嵌入方式在 `channels` |
| `app-groups` | AppGroup | EMS 应用分组（`bas.ems_app_groups`） |
| `channels` | Channel | 应用端；`base` 为部署上下文，`channelType` 取 `pc`/`mobile`，`embedMode` 取 `iframe`/`wujie`；同一应用下 `channelType` 唯一 |
| `resources` | Resource | `scope` 为枚举名；新建默认 `Private`/启用；`GET /api/bashub/ems/resources/{id}/menus?include=entry,resources` 返回引用该资源的菜单 |
| `menus` | Menu | 见下方专用端点；下发去掉空参数尾巴的 `entryUrl`；`indexno` 由 `move` 重排 |

写操作请求体：

```json
{ "data": { "type": "channels", "attributes": { "base": "/portal", "channelType": "pc", "embedMode": "iframe" } } }
```

关联用 JSON:API 的 `relationships`（`{data:{type,id}}` 或 `{data:[{type,id}...]}`）；后端按 id 从库中取实体。

### 菜单 XML：`menus`

- `GET /api/bashub/ems/menus/export?app={appId}` → `{ "xml": "<project>...</project>" }`
- `POST /api/bashub/ems/menus/import`（multipart，字段 `app` + `menufile`）→ `{ "success": true }`

## `/api/bashub/config`

### 资源（JSON:API）

平台配置资源都挂在 `config` 域下，并提供统一 CRUD：

| 操作 | 方法与 URL |
|---|---|
| 查询列表 | `GET /api/bashub/config/{resource}/search` |
| 新建 | `POST /api/bashub/config/{resource}` |
| 查看 | `GET /api/bashub/config/{resource}/{id}` |
| 修改 | `PATCH /api/bashub/config/{resource}/{id}` |
| 删除 | `DELETE /api/bashub/config/{resource}/{id}` |

| `{resource}` | 实体 | 说明 |
|---|---|---|
| `organizations` | Organization | 机构 |
| `platforms` | Platform | 操作系统平台 |
| `projects` | Project | 新建时填默认仓库；`hostname` 是项目域名。代理/SETLINE 字段在 `proxy-settings`。证书不放在 project 资源里（避免列表/详情每次携带大字段）：公钥与「私钥是否已设置」走专用端点 `/api/bashub/config/projects/{id}/certificate`。Micdn 配置走专用聚合端点，不再是普通资源 |
| `proxy-settings` | ProxySetting | 每个项目一份；`project` 关联必填，`ip` 是 setline 下载鉴权的内部 IP（多个用空格/逗号分隔），`proxyByHostname` 为 `true` 时才把项目 `hostname` 输出为 server.xml 的 `setline-hostname` |
| `engines` | Engine | `type` 取 `tomcat-server`/`tomcat`/`undertow`/`jetty`/`any`（与 basctl 的 creator 同名）；`listeners`/`jars` 支持分隔符字符串；`jspSupport` 仅 `tomcat-server` 有效 |
| `farms` | Farm | 群集 |
| `servers` | Server | 群集实例；派生 `qualifiedName`（`群集.服务`）、`hostIp` 与 `displayName`（`群集.服务 (IP)`），供部署选择器显示 |
| `hosts` | Host | `arch` 以 1 起的序号或枚举名提交；`setlineListenPort` / `setlineAdminPort` 是成对的主机级 setline 端口（1-65535），都为空表示该主机不部署 setline；listen 供 peer agent 读取 `/_setline/routes`，admin 供 basctl 在本机推路由；两个端口下发到 server.xml 的 `<host>`，不生成 `<setline>`；列表下发按 `platform` 过滤后的 `featureLogos`；`GET /api/bashub/config/hosts/{id}/webapps?include=artifact` 返回部署到该主机的应用 |
| `artifacts` | Artifact | 下发计算属性 `gav`；`GET /api/bashub/config/artifacts/{id}/webapps?include=artifact` 返回使用该组件的部署；`POST /api/bashub/config/artifacts/update-version`（body `{"ids":[..]}`）从 Maven Central 的 `maven-metadata.xml` 刷新 `latestVersion` |
| `webapps` | Webapp | `contextPath` 是部署上下文；`urls` 是对外 URL 前缀（一行一个，反代/setline 按它转发，留空按 `contextPath`）；`targets` 只能选择位于同时配置了 `Host.setlineListenPort` 与 `Host.setlineAdminPort` 的主机上的 server，否则无法生成有效的 `run-at`；下发 `gav/artifactName/updatable`。额外 `POST /api/bashub/config/webapps/upgrade`（body `{"ids":[..]}`） |
| `platform-features` | PlatformFeature | 菜单是 `平台与功能` 页签组里的「平台功能」页签 |
| `platform-feature-scripts` | PlatformFeatureScript | 无独立列表页，在平台功能详情页维护；`scripts` 写入时去掉 `\r` |

### 配置凭证 `key`

- 新建配置时 `Project.key` 自动生成（16 字节随机数的十六进制）；**新建之后不随请求改写**，只有显式
  重置才变——重置即吊销，旧 key 的连接下次握手就被拒。
- `POST /api/bashub/config/projects/{id}/reset-key` → `{"id":…,"key":"…"}`（返回新 key，前端直接显示给操作者）。
- key 也随 `GET /api/bashub/config/projects/{id}` 的 `attributes.key` 下发（配置详情页据此展示）。

## `/api/bashub/micdn`

Micdn 资源不挂在通用 CRUD 下，统一在 `/api/bashub/micdn` 暴露。Micdn 配置是 Project 的聚合资源：
`project-micdn`、`project-micdn-components` 的存储表是 `bas.cfg_*`，但作为 Project 的聚合配置，
不进入 config 通用 CRUD。

| 端点 | 说明 |
|---|---|
| `GET /api/bashub/micdn/projects/{id}` | 配置、绑定、组件目录和脱敏 XML |
| `PATCH /api/bashub/micdn/projects/{id}` | 一次保存 `config` 与 `bindings` |
| `GET /api/bashub/micdn/projects/{id}/micdn.xml` | 下载含真实密钥的 XML（`no-store`） |
| `GET/POST /api/bashub/micdn/components` | 组件目录列表/新建 |
| `PATCH/DELETE /api/bashub/micdn/components/{id}` | 组件修改/删除 |

`config.servers` 登记运行 micdn 的节点，每项为 `{name, adminListen}`，例如
`{"name":"cdn01","adminListen":"10.0.0.31:8081"}`。该字段不写入 `micdn.xml`，只用于生成
`/config/setline-peers` 的 peer 列表；`adminListen` 不能使用 `0.0.0.0`、`*` 或 `::` 这类不可拨号地址。

## 机器端点（config / ems / micdn / monitor）

`{project}` 为配置名。`server`、`proxy`、`setline-peers`、`certificate`、`certificate-key` 与
`/api/bashub/micdn/{project}/micdn.xml`、`/api/bashub/monitor/agents/{project}/channel` 使用 Project 令牌鉴权；
推荐发 `Authorization: Bearer <project>:<Project.key>`，
同时校验 URL 中的 Project 与凭证前缀。HTTP 配置下载也接受 Basic（用户名 `<project>`、
口令 `<Project.key>`），便于 `curl -u <project>` 交互输入。凭证形式仍接受只发
`<Project.key>`，但 URL 路径必须使用能力域前缀。
管理台查看最终配置走 `/api/bashub/config/projects/{id}/*`，按登录会话鉴权。其余机器端点按
登录令牌或 Project 令牌鉴权。这些端点由 `bashub.project.*` 直接渲染文本/XML，不依赖
Freemarker 模板运行时，不属于 JSON:API。

| URL | 说明 |
|---|---|
| `GET /api/bashub/config/{project}/server` | 服务器/集群配置；`Authorization: Bearer <project>:<project.key>` 鉴权。`<snapshot-repo>` 的 `token` 取 Project 的 micdn `<auth download-key>`，为空时回退 hub.xml 的 `<snapshot download-token>`（兼容 `maven-download-token` 属性）；都没有则不写 `token`。存在已启用 setline 的 Host 时，在对应 `<host>` 上输出 `setline-listen-port` / `setline-admin-port`；`proxySetting.proxyByHostname=true` 时还要求 `project.hostname` 非空并输出 `setline-hostname="<project.hostname>"`，否则省略该属性，由 basctl 使用 `*` 默认组。不再生成 `<setline>`。setline 进程自己的 listen/adminListen 配置仍归节点管理。不输出通道凭证，地址与 token 由客户端 `conf/basctl.conf` 保存 |
| `GET /api/bashub/config/{project}/proxy` | 反向代理配置（haproxy/nginx，按 `project.proxyEngine` 选择模板）；使用同样的 Project 令牌。只输出所选引擎自身的合法配置，不混入 setline agent 配置；HAProxy 按请求 `path` 做 `map_beg` 路由，不再生成 Host 分组查找、path ACL 或 inline backend |
| `GET /api/bashub/config/{project}/certificate` | Project 的 PEM 公钥证书（可含完整证书链）；使用同样的 Project 令牌。未配置时返回空 Body |
| `GET /api/bashub/config/{project}/certificate-key` | Project 的 PEM 私钥；只允许机器令牌下载，`Cache-Control: no-store`。未配置时返回空 Body。管理台永远只返回固定掩码 |
| `GET /api/bashub/config/{project}/setline-peers` | haproxy/nginx sidecar 的 peer 列表（JSON）；使用同样的 Project 令牌。任何存在的 Project 都有响应：`peers` 由 Project 下带 server 且配置了 `setlineListenPort` 的 host（URL `http://<host.ip>:<host.setlineListenPort>`）与 Micdn 配置 `servers[]`（URL `http://<adminListen>`）合并生成，并按 URL 去重；没有 peer 时返回空数组。`setline pull` 把这组 peers 写回节点自己的 `setline.conf [agent] peers`。web 节点的端口来自 Host 的 setline `listen`；该 listen 地址必须能被 sidecar 访问，且 sidecar 来源 IP 要写进对应 setline 的 `peerReaders` |
| `GET /api/bashub/config/{project}/setline-manifest` | setline 的资源配置摘要（SHA-256）；使用同样的 Project 令牌 |
| `GET /api/bashub/ems/{project}/menus/{appName}` | 应用菜单 |
| `GET /api/bashub/micdn/{project}/micdn.xml` | 完整 micdn 配置（包含 maven/npm/native/auth/static/www/blob）；`X-Micdn-Token` 或 `Authorization: Bearer <project.key>` 鉴权 |
| `GET /api/bashub/config/{project}/script/{host}` | 主机脚本（按依赖排序） |
| `WS /api/bashub/monitor/agents/{project}/channel` | 节点通道：basctl 主动连上来的 WebSocket（**不是** HTTP 接口，握手用 `Authorization: Bearer <project>:<Project.key>`，兼容只发 key），见下 |
| `GET /api/bashub/config/projects/{id}/server` | 管理台查看最终 server.xml；登录会话鉴权 |
| `GET /api/bashub/config/projects/{id}/proxy` | 管理台查看所选引擎的最终代理配置；登录会话鉴权 |
| `GET /api/bashub/config/projects/{id}/setline-peers` | 管理台查看 setline peer 列表；登录会话鉴权 |
| `GET /api/bashub/config/projects/{id}/certificate` | 管理台读取 PEM 公钥证书与 `keySet`（私钥原文永不回显）；登录会话鉴权 |
| `PATCH /api/bashub/config/projects/{id}/certificate` | 保存公钥证书；`privateKey` 留空表示保持原私钥；登录会话鉴权 |

sidecar 的 `[agent] peers` 只负责“读哪些节点”。各 web 节点自己那份 setline 配置仍需让
`listen` 可被 sidecar 主机访问，并把 sidecar 主机地址写进 `peerReaders`；这条读链路按
来源地址放行，不带 token。peers 模式没有监听段，也不会常驻：`setline` 渲染
一轮后退出，由 `setline-agent.timer` 周期拉起并 apply。

## `/api/bashub/monitor`（节点与监控）

### `/api/bashub/monitor/agents/{project}/channel`

生产机上的 basctl 主动拨一条出站 WebSocket 到这里，报主机与实例的**现状**，并接收固定原语
（立即上报 / 取日志 / 启停实例）。这条通道与「浏览器连服务端」的那条**不是一回事**：

- 谁连谁：**basctl 出站**（生产机多在 NAT 后面），不是浏览器连进来。
- 鉴权：**握手时就认**——推荐 `Authorization: Bearer <project>:<Project.key>`，URL 里的
  `{project}` 同时参与校验；仍兼容只发 `<Project.key>` 的旧客户端。
  未通过的连接在握手阶段被关掉，拿不到一个字节的协议。因此这一段路径**必须放行**（不能挂 CAS
  拦截器，升级请求不能被 302）。
- 端点：`ws(s)://<host>/api/bashub/monitor/agents/{project}/channel`；**一个 project 可以有多条连接**
  （多台机器共用一个 project），按握手头 `ip: <addr>[,<addr>…]` 区分：hub 过滤掉非法地址，只保留与
  hosts 配置命中的那个作为 `project@ip` 身份。不同 IP 的连接并存，只有同一 IP 重新登录才顶替
  旧连接（1008 `superseded`）。头里没有合法 IP 返回 400，合法但不在该 project 的 `hosts.ip`
  里返回 403（不做“没配置就放行”的兜底）——不把多台机器折叠成一条连接。同一 `project@ip` 60 秒内
  反复被顶掉时记一条 WARN（`agent reconnected again …`），每分钟最多一条。
- 消息协议、原语表、节拍：**唯一权威在 basctl 仓库**
  （[docs/channel-protocol.md](https://github.com/beangle/basctl/blob/main/docs/channel-protocol.md)），
  本仓库 D 侧的 `bashub.agent.*` 是服务端实现（信封编解码 + 现状快照 + 内存登记册 + 握手鉴权），
  行为以同一份协议文档为准。
- 读完整现状：`GET /api/bashub/monitor/agents/status` → `{"agents":[…]}`，**每台机器一项**（同一 project
  可能有多项，按 `ip` 区分）：project / projectId / projectTitle / ip / host / org / basctl / bas / basHome /
  supports / connectedAt / lastSeenAt / os / basReport / health。`projectId` 供前端跳到配置详情；
  `projectTitle` 是 project 的说明，SPA 用它当卡片大标题（`org` 只用于 Logo 与兜底）。
  只在线的、只留最近一次；断连即摘除。`basReport.instances` 只含运行中实例；
  `basReport.declared` 是本机 `server.xml` 声明的实例，控制台按 `id` 合并两者，停止后仍保留实例行并
  提供启动入口。`basReport.instances[].webapps[].title` 与 `basReport.declared[].webapps[].title`
  都由 hub 读 project 的 webapp 配置反查 artifact.title 后补上（先按 gav，再按 context）：agent 只上报 gav/context，不扩协议，
  也不要求 SPA 有配置读取权限。`org` 是 project 所属机构的展示信息 `{name,title,shortTitle,logoUrl}`（按 project
  名的 `org.` 前缀从 `organizations` 查得），SPA 只用它的 Logo 与兜底标题；查不到就省略该字段。
- 读轻量摘要：`GET /api/bashub/monitor/agents/summary` → `{"agents":[…]}`，每台机器一项，只含
  project / projectId / projectTitle / ip / host / org / basctl / bas / supports / connectedAt / lastSeenAt / healthAt / health
  以及 `running` / `stopped` 计数，不携带 OS 与 webapps，供不需要实例明细的调用方使用。SPA 的实例表
  要显示 pid / 端口 / webapps，因此每 30 秒轮询的是完整 `/agents/status`；点节点的“刷新”会先让 agent
  重报再取一次。
- 读运行历史：`GET /api/bashub/monitor/agents/{project}/history?days=180`。`days` 取 1–180，
  缺省调用方传 180。返回 `{project, projectId, from, to, days, samples:[{at, servers:{id:state}}]}`，
  `samples` 按时间升序；页面一次取回整个 project 的所有 server 状态，再在 SPA 本地计算
  每个 server 的每日运行/停止/异常计数、可用率、最近状态和状态变化。单 server 视图直接复用
  这份数据，不再按 `instance` 单独请求。
  历史来自 `bas.mon_server_samples`，每个 project/采样点一行（`project_id + sampled_at + servers JSONB`），
  只在 hub 的 `<agent health-interval>` 采样窗口内由 `report:health` 触发写入：同一 project 下所有 agent 的
  health 先合并成一份（按 server id 取并集），同一分钟重复触发用最新合并结果覆盖，保留 180 天；
  历史存储未启用时返回 503，project 不存在返回 404，表未迁移或其他数据库查询失败返回 500。
- 授权：`/api/bashub/monitor/agents/*` 的 GET（在线状态、历史、日志）允许已登录用户查看；
  立即上报、启停实例等写操作要求 EMS 中 `bas-hub` 的 `/monitor/agents` 资源为 **Private**
  且已授权当前用户的角色。EMS 会话的 `authorities` 是角色 ID（如 `"42"`），JSON 会话也没有
  `isRoot`，因此不能按 `ROLE_ADMIN` 或 root 配置。资源未登记、资源不是 Private 或角色不命中时，
  写操作一律 403；资源授权缓存最长 300 秒刷新。其它 CAS 来源若在 `permissions` 中提供
  `/monitor/agents:*`，也可作为显式授权。
- 选 agent：同一 project 有多台在线 agent 时，写操作和日志类接口用 `?agent=<ip>` 指定目标
  （`ip` 取自 `/agents/status`）；只有一台时可以省略；多台且省略返回 409，附带可选地址列表。
- 立即刷新：`POST /api/bashub/monitor/agents/{project}/report[?agent=<ip>]` → 202 表示 `report:now`
  已入队；节点离线 404，agent 未申报该能力 409。随后到达的 `report:os` / `report:bas` 会覆盖现状。
- 读日志：`GET /api/bashub/monitor/agents/{project}/log?instance={farm.server}&from={from}&to={to}&tail={n}[&agent=<ip>]`。
  `instance` 必填且只能是一层普通目录名；`from` / `to` 可省略，省略时交给 agent 取默认窗口；
  `tail` 只在 `from` / `to` 都省略时生效，取最后 N 行。
  成功返回 `{total, from, to, lines:[…]}`；节点离线 404、5 秒无应答 504、agent 返回失败 502。
- 读 agent 日志：`GET /api/bashub/monitor/agents/{project}/agent-log?from={from}&to={to}&tail={n}[&agent=<ip>]`。
  窗口参数与实例日志相同，但没有 `instance`；返回同样的 `{total, from, to, lines:[…]}`。
- 启停实例：`POST /api/bashub/monitor/agents/{project}/service/{action}[?agent=<ip>]`，`action` 取 `start` / `stop` /
  `restart`，body 为 `{"instance":"{farm.server}"}`。接口等到 agent 执行完才返回，成功为
  `{"data":{"state":"running"|"stopped","pid":123}}`；节点离线 404、未申报能力 409、
  2 分钟无应答 504、agent 执行失败 502。`stop` / `restart` 是破坏性动作，前端二次确认。
- 启停失败详情：502 错误文档的 `errors[0].meta` 可带 `{detail?, logTail?, truncated?}`。`detail`
  最多 8 KiB，`logTail` 最多 100 行；完整内容继续通过实例日志接口读取。
- 跟随日志：`GET /api/bashub/monitor/agents/{project}/log/follow?instance={farm.server}&tail={n}[&agent=<ip>]`，
  响应 `text/event-stream`。首次取最后 `tail` 行（缺省 200、上限 2000），之后 hub 每 3 秒向 agent
  发一次 `log:read`，增量用 `from=上次 to + 1`；浏览器侧只维持一条 SSE 连接。
  - `event: lines`，`data` 为 `{total, from, to, lines, reset}`。`reset=true` 表示首次尾部或
    日志轮转，客户端应替换现有窗口；`false` 表示追加。
  - 事件 `id` 是该窗口的 `to`。浏览器断线重连会自动带 `Last-Event-ID`，服务端从
    `Last-Event-ID + 1` 继续，避免重复推送。
  - 空闲时发送 `: keepalive` 注释；流内错误用 `event: failure`，不会与 EventSource 自己的
    连接错误事件同名。节点离线 404、agent 未申报 `log:read` 409。
  - agent 侧协议不变：仍是普通区间 `log:read`，SSE 只存在于 hub ↔ 浏览器之间。
- SPA 页面：`/monitor/agents` 展示在线节点、实例状态、运行历史与 `hello.supports`；操作系统指标与
  webapps 明细按需加载。支持刷新节点快照（先下发 `report:now`，再读 `/agents/status`）、按区间读实例
  或 agent 日志、SSE 跟随与实例重启 / 停止。跟随断线由 `EventSource` 自动重连；节点快照每 30 秒自动刷新一次。
  多个 project 同时在线时**一次只展示一个**：右上角下拉切换，选择记在浏览器 localStorage，当前 project
  离线后自动退回列表里的第一个。运行历史是独立页面 `/monitor/agents/:project/history`；卡片头部的
  “配置”按 `projectId` 跳到该 project 的配置详情。
