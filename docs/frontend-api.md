# 后端 API 契约

后端**只提供 API**，页面由独立部署的 SPA 渲染。D 侧路由分三组：

| 用途 | 前缀 | 实现包 | 风格 |
|---|---|---|---|
| 管理台接口 | `/api/hub` | `bashub.route` + `beangle.jsonapi` | 手写 JSON:API（复数资源名） |
| 配置分发（给客户端） | `/api/{profile}` | `bashub.profile.*` | 直接渲染文本/XML |
| Maven 构件仓库 | `/repo` | `bashub.repo.*` | 直接处理 HTTP |

URL 契约由 `test/bashub/route_test.d` 覆盖，路由变更以该测试为准。

## 通用约定

- 请求头：`Accept: application/vnd.api+json`（JSON:API 文档），写操作另加 `Content-Type: application/vnd.api+json`。
- URL 后缀（`.json` / `.jsonapi`）在路由前被剥掉，只影响响应格式；两者都可省略。
- JSON/XHR 请求未登录返回 `401`，响应体为
  `{"errors":[{"status":401,"meta":{"redirectUrl":"<CAS 登录地址>"}}]}`；浏览器导航请求直接 302。
- 已登录但无权访问返回 `403`，响应体是标准 JSON:API 错误文档。
- `GET /api/hub/configs` 不校验登录；其余管理接口受 `<api auth="required">` 控制。
- 分页参数用 `page[number]` / `page[size]`；两者缺失时后端读 cookie `pageSize`，再缺省为 20。
- 排序用 `sort`（`-` 前缀表示倒序）。过滤用 `filter[<属性>]`（如 `filter[profile.name]=demo`）；
  多值可用逗号或分号分隔，文本 2–3 个按 `or`，4 个以上及非文本列按 `in`。
- 显式算子写成 `filter[<属性>][<op>]`，支持 `between`、`ge`、`gt`、`le`、`lt`、`in`、`nin`、`eq`、`ne`。
- 列表响应为 JSON:API 文档，分页信息在 `meta.page`：`{number, size, total}`。
- 上传接口是 `multipart/form-data`，**不要设置 `Content-Type`**（boundary 由浏览器生成）。
- 跨域由 `<api cors-origins="...">` 白名单控制（也接受主机名）；同源请求不下发 CORS 头，
  允许来源的预检回 204，不允许的来源回 403。API 响应带 `Cache-Control: no-store`，并统一带
  `X-Content-Type-Options: nosniff`、`Referrer-Policy`；HTTPS 下带 HSTS。

## 前端客户端

SPA 统一使用 `@beangle/ems-app` 的 `EmsJsonApiClient`（`packages/web/src/api/client.ts`），它负责内容协商、
`page[...]`/`filter[...]` 查询串、`URP_SID` 追加与 401/302 跳 CAS：

| 方法 | 用途 |
|---|---|
| `get` / `post` / `patch` / `delete` | JSON:API 读写 |
| `upload(path, formData)` | multipart 上传（菜单 XML、SNAPSHOT war） |
| `getPlain(path, {query})` | 取非 JSON:API 结构的普通 JSON（如 `{xml}`） |

`packages/web/src/api/resource.ts` 在此基础上提供了通用资源的 `listResource` / `saveResource` /
`removeResource` / `callResourceAction` / `uploadResourceFile`，各页面由 `src/resources/index.ts` 的元数据驱动。

## `/api/hub`

### 配置 `configs`

- `GET /api/hub/configs.json`（**不校验登录**，登录前就要可读，否则前端无从得知 CAS 地址）

按 ems-app 的约定**只下发 `ems_base`**，CAS 地址由前端在该地址后拼 `/cas`：

```json
{
  "ems_base": "https://sas.openurp.net",
  "app_name": "bas-hub",
  "logoUrl": "https://sas.openurp.net/api/platform/config/domains/logo"
}
```

### 配置凭证 `key`

- 新建配置时 `Profile.key` 自动生成（16 字节随机数的十六进制）；**新建之后不随请求改写**，只有显式
  重置才变——重置即吊销，旧 key 的连接下次握手就被拒。
- `POST /api/hub/profiles/{id}/reset-key` → `{"id":…,"key":"…"}`（返回新 key，前端直接显示给操作者）。
- key 也随 `GET /api/hub/profiles/{id}` 的 `attributes.key` 下发（配置详情页据此展示）。

### 会话 `sessions`

- `GET /api/hub/sessions`：当前登录用户 `{code, name}`
- `POST /api/hub/sessions/logout`：清理本地会话与 cookie，返回 `{"logoutUrl": "<CAS 登出地址>"}`；
  前端随后跳转 CAS `/logout?service=<当前页面>`，不做后通道单点登出
- 浏览器登录跳转 `{cas}/login?service=<当前页面>`；CAS 回跳带 `ticket` 时，后端用
  `{cas}/serviceValidate` 校验，并把 CAS 的 `authorities` / `permissions` 映射到当前账户。

### 资源（JSON:API）

以下资源都提供统一的 CRUD 路由（`search` 为复数资源下的列表）：

| 操作 | 方法与 URL |
|---|---|
| 查询列表 | `GET /api/hub/{resource}/search` |
| 新建 | `POST /api/hub/{resource}` |
| 查看 | `GET /api/hub/{resource}/{id}` |
| 修改 | `PATCH /api/hub/{resource}/{id}` |
| 删除 | `DELETE /api/hub/{resource}/{id}` |

写操作请求体：

```json
{ "data": { "type": "platforms", "attributes": { "name": "beangle", "majorVersion": "6" } } }
```

关联用 JSON:API 的 `relationships`（`{data:{type,id}}` 或 `{data:[{type,id}...]}`）；后端按 id 从库中取实体。

| `{resource}` | 实体 | 分组 | 端点/说明 |
|---|---|---|---|
| `organizations` | Organization | 平台配置 | |
| `platforms` | Platform | 平台配置 | |
| `profiles` | Profile | 平台配置 | 新建时填默认仓库；`sslCertificate` / `sslCertificateKey` 保存 PEM 公钥证书与私钥，编辑私钥时留空表示保持原值，管理台不回显私钥。Micdn 配置走专用聚合端点，不再是普通资源 |
| `engines` | Engine | 平台配置 | `type` 取 `tomcat-server`/`tomcat`/`undertow`/`jetty`/`any`（与 basctl 的 creator 同名）；`listeners`/`jars` 支持分隔符字符串；`jspSupport` 仅 `tomcat-server` 有效 |
| `farms` | Farm | 平台配置 | |
| `servers` | Server | 平台配置 | |
| `hosts` | Host | 平台配置 | `arch` 以 1 起的序号或枚举名提交；列表下发按 `platform` 过滤后的 `featureLogos`；`GET /hosts/{id}/webapps?include=artifact` 返回部署到该主机的应用 |
| `artifacts` | Artifact | 平台配置 | 下发计算属性 `gav`；`GET /artifacts/{id}/webapps?include=artifact` 返回使用该组件的部署；`POST /artifacts/update-version`（body `{"ids":[..]}`）从 Maven Central 的 `maven-metadata.xml` 刷新 `latestVersion` |
| `webapps` | Webapp | 平台配置 | `contextPath` 是部署上下文；`urls` 是对外 URL 前缀（一行一个，反代/setline 按它转发，留空按 `contextPath`）；下发 `gav/artifactName/updatable`。额外 `POST /webapps/upgrade`（body `{"ids":[..]}`） |
| `platform-features` | PlatformFeature | 平台配置 | 菜单是 `平台与功能` 页签组里的「平台功能」页签 |
| `platform-feature-scripts` | PlatformFeatureScript | — | 无独立列表页，在平台功能详情页维护；`scripts` 写入时去掉 `\r` |
| `app-groups` | AppGroup | 应用与菜单 | |
| `apps` | App | 应用与菜单 | 只登记应用本身（名称/标题/分组/artifactId/依赖项），部署上下文与嵌入方式在 `channels` |
| `channels` | Channel | 应用与菜单 | 应用端；`base` 为部署上下文，`channelType` 取 `pc`/`mobile`，`embedMode` 取 `iframe`/`wujie`；同一应用下 `channelType` 唯一 |
| `resources` | Resource | 应用与菜单 | `scope` 为枚举名；新建默认 `Private`/启用；`GET /resources/{id}/menus?include=entry,resources` 返回引用该资源的菜单 |
| `menus` | Menu | 应用与菜单 | 见下方专用端点；下发去掉空参数尾巴的 `entryUrl`；`indexno` 由 `move` 重排 |
| `cdn-components` | CdnComponent | Micdn | 可复用组件目录；`kind` 为 `static_bundle` / `www_doc`，`spec` 是结构化 JSON |

Micdn 配置是 Profile 的聚合资源，不通过通用 CRUD 编辑：

| 端点 | 说明 |
|---|---|
| `GET /api/hub/profiles/{id}/micdn` | 配置、绑定、组件目录和脱敏 XML |
| `PATCH /api/hub/profiles/{id}/micdn` | 一次保存 `config` 与 `bindings` |
| `GET /api/hub/profiles/{id}/micdn.xml` | 下载含真实密钥的 XML（`no-store`） |
| `GET/POST /api/hub/cdn-components` | 组件目录列表/新建 |
| `PATCH/DELETE /api/hub/cdn-components/{id}` | 组件修改/删除 |

`config.servers` 登记运行 micdn 的节点，每项为 `{name, adminListen}`，例如
`{"name":"cdn01","adminListen":"10.0.0.31:8081"}`。该字段不写入 `micdn.xml`，只用于生成
`/config/setline-peers` 的 peer 列表；`adminListen` 不能使用 `0.0.0.0`、`*` 或 `::` 这类不可拨号地址。

### 菜单 XML：`menus`

- `GET /api/hub/menus/export?app={appId}` → `{ "xml": "<profile>...</profile>" }`
- `POST /api/hub/menus/import`（multipart，字段 `app` + `menufile`）→ `{ "success": true }`

### 构件上传：`snapshots`

- `POST /api/hub/snapshots/upload`（multipart，字段 `warfile`）→ `{ "success": true, "path": "..." }`
- 坐标取自 `META-INF/MANIFEST.MF` 的 `Implementation-Vendor-Id` / `Implementation-Title` /
  `Implementation-Version`；版本含 `-SNAPSHOT` 时落到仓库的 `snapshots`，否则落 `repository`。

## `/api/{profile}`（机器分发）

`{profile}` 为配置名。`config/server`、`config/proxy`、`config/setline-peers`、
`config/certificate`、`config/certificate-key`、`micdn.xml` 与节点通道用 Profile 令牌鉴权；
推荐发 `Authorization: Bearer <profile>:<Profile.key>`，
同时校验 URL 中的 Profile 与凭证前缀。HTTP 配置下载也接受 Basic（用户名 `<profile>`、
口令 `<Profile.key>`），便于 `curl -u <profile>` 交互输入。旧客户端只发 `<Profile.key>`
仍然可用。
管理台查看最终配置走 `/api/hub/profiles/{id}/config/*`，按登录会话鉴权。其余机器端点仍按
请求头 `ip` 匹配 Profile 或所属 Host 的 IP。这些端点由 `bashub.profile.*` 直接渲染文本/XML，
不依赖 Freemarker 模板运行时，不属于 JSON:API。

| URL | 说明 |
|---|---|
| `GET /api/{profile}/config/server` | 服务器/集群配置；`Authorization: Bearer <profile>:<profile.key>` 鉴权。不输出 `<setline>` 或通道凭证，地址与 token 由客户端 `conf/basctl.conf` 保存 |
| `GET /api/{profile}/config/proxy` | 反向代理配置（haproxy/nginx，按 `profile.proxyEngine` 选择模板）；使用同样的 Profile 令牌。只输出所选引擎自身的合法配置，不混入 setline agent 配置；HAProxy 按请求 `path` 做 `map_beg` 路由，不再生成 Host 分组查找、path ACL 或 inline backend |
| `GET /api/{profile}/config/certificate` | Profile 的 PEM 公钥证书（可含完整证书链）；使用同样的 Profile 令牌。未配置时返回空 Body |
| `GET /api/{profile}/config/certificate-key` | Profile 的 PEM 私钥；只允许机器令牌下载，`Cache-Control: no-store`。未配置时返回空 Body。管理台永远只返回固定掩码 |
| `GET /api/{profile}/config/setline-peers` | haproxy/nginx sidecar 的 peer 列表（JSON）；使用同样的 Profile 令牌。任何存在的 Profile 都有响应：`peers` 由 Profile 下带 server 的 host（URL `http://<host.ip>:8080`）与 Micdn 配置 `servers[]`（URL `http://<adminListen>`）合并生成，并按 URL 去重；没有 peer 时返回空数组。`setline pull` 把这组 peers 写回节点自己的 `setline.conf [agent] peers`。peer 指向的 `adminListen` 必须能被 sidecar 访问，且 sidecar 来源 IP 要写进对应 setline 的 `peerReaders` |
| `GET /api/{profile}/ems/menus/{appName}` | 应用菜单 |
| `GET /api/{profile}/micdn.xml` | 完整 micdn 配置（包含 maven/npm/native/auth/static/www/blob）；`X-Micdn-Token` 或 `Authorization: Bearer <profile.key>` 鉴权 |
| `GET /api/{profile}/script/{host}` | 主机脚本（按依赖排序） |
| `WS /api/{profile}/agents` | 节点通道：basctl 主动连上来的 WebSocket（**不是** HTTP 接口，握手用 `Authorization: Bearer <profile>:<Profile.key>`，兼容只发 key），见下 |
| `GET /api/hub/profiles/{id}/config/server` | 管理台查看最终 server.xml；登录会话鉴权 |
| `GET /api/hub/profiles/{id}/config/proxy` | 管理台查看所选引擎的最终代理配置；登录会话鉴权 |
| `GET /api/hub/profiles/{id}/config/setline-peers` | 管理台查看 setline peer 列表；登录会话鉴权 |

sidecar 的 `[agent] peers` 只负责“读哪些节点”。各 web 节点自己那份 setline 配置仍需让
`listen` 可被 sidecar 主机访问，并把 sidecar 主机地址写进 `peerReaders`；这条读链路按
来源地址放行，不带 token。peers 模式没有监听段，也不会常驻：`setline` 渲染
一轮后退出，由 `setline-agent.timer` 周期拉起并 apply。

## `/repo`

原生发行包（tar.gz/增量补丁）仓库的读写（`bashub.repo`），供代理下载/上传。快照（war/jar）的上传与
分发已交给 [micdn](https://github.com/beangle/micdn) 的 `/maven`（正式版与 SNAPSHOT 共用一个入口）。

## 节点通道（WebSocket）

### `/api/{profile}/agents`

生产机上的 basctl 主动拨一条出站 WebSocket 到这里，报主机与实例的**现状**，并接收固定原语
（立即上报 / 取日志 / 启停实例）。这条通道与「浏览器连服务端」的那条**不是一回事**：

- 谁连谁：**basctl 出站**（生产机多在 NAT 后面），不是浏览器连进来。
- 鉴权：**握手时就认**——推荐 `Authorization: Bearer <profile>:<Profile.key>`，URL 里的
  `{profile}` 同时参与校验；仍兼容只发 `<Profile.key>` 的旧客户端。
  未通过的连接在握手阶段被关掉，拿不到一个字节的协议。因此这一段路径**必须放行**（不能挂 CAS
  拦截器，升级请求不能被 302）。
- 端点：`ws(s)://<host>/api/{profile}/agents`；一个 profile 一条连接，重复登录踢掉旧连接。
- 消息协议、原语表、节拍：**唯一权威在 basctl 仓库**
  （[docs/channel-protocol.md](https://github.com/beangle/basctl/blob/main/docs/channel-protocol.md)），
  本仓库 D 侧的 `bashub.agent.*` 是服务端实现（信封编解码 + 现状快照 + 内存登记册 + 握手鉴权），
  行为以同一份协议文档为准。
- 读现状：`GET /api/hub/agents/status` → `{"agents":[…]}`，每项是「这台机器此刻的样子」
  （profile / host / basctl / bas / basHome / supports / connectedAt / lastSeenAt / os / basReport）。
  只在线的、只留最近一次；断连即摘除。控制台页面为 SPA 的 `/agents`。
  `basReport.instances` 只含运行中实例；`basReport.declared` 是本机 `server.xml` 声明的实例，
  控制台按 `id` 合并两者，停止后仍保留实例行并提供启动入口。
- 立即刷新：`POST /api/hub/agents/{profile}/report` → 202 表示 `report:now` 已入队；节点离线 404，
  agent 未申报该能力 409。随后到达的 `report:os` / `report:bas` 会覆盖现状。
- 读日志：`GET /api/hub/agents/{profile}/log?instance={farm.server}&from={from}&to={to}&tail={n}`。
  `instance` 必填且只能是一层普通目录名；`from` / `to` 可省略，省略时交给 agent 取默认窗口；
  `tail` 只在 `from` / `to` 都省略时生效，取最后 N 行。
  成功返回 `{total, from, to, lines:[…]}`；节点离线 404、5 秒无应答 504、agent 返回失败 502。
- 启停实例：`POST /api/hub/agents/{profile}/service/{action}`，`action` 取 `start` / `stop` /
  `restart`，body 为 `{"instance":"{farm.server}"}`。接口等到 agent 执行完才返回，成功为
  `{"data":{"state":"running"|"stopped","pid":123}}`；节点离线 404、未申报能力 409、
  2 分钟无应答 504、agent 执行失败 502。`stop` / `restart` 是破坏性动作，前端二次确认。
- 跟随日志：`GET /api/hub/agents/{profile}/log/follow?instance={farm.server}&tail={n}`，
  响应 `text/event-stream`。首次取最后 `tail` 行（缺省 200、上限 2000），之后 hub 每 3 秒向 agent
  发一次 `log:read`，增量用 `from=上次 to + 1`；浏览器侧只维持一条 SSE 连接。
  - `event: lines`，`data` 为 `{total, from, to, lines, reset}`。`reset=true` 表示首次尾部或
    日志轮转，客户端应替换现有窗口；`false` 表示追加。
  - 事件 `id` 是该窗口的 `to`。浏览器断线重连会自动带 `Last-Event-ID`，服务端从
    `Last-Event-ID + 1` 继续，避免重复推送。
  - 空闲时发送 `: keepalive` 注释；流内错误用 `event: failure`，不会与 EventSource 自己的
    连接错误事件同名。节点离线 404、agent 未申报 `log:read` 409。
  - agent 侧协议不变：仍是普通区间 `log:read`，SSE 只存在于 hub ↔ 浏览器之间。
- SPA 页面：`/agents` 展示在线节点、操作系统指标、运行实例与 `hello.supports`，支持立即上报、
  按区间读日志、SSE 跟随与实例重启 / 停止。跟随断线由 `EventSource` 自动重连；节点列表每 10 秒刷新一次。
