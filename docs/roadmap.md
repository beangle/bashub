# D 后端功能与迁移 Roadmap

> 盘点基线：`0.0.8`，2026-10-17。原 JVM 后端已于 2026-10 退役，本文件记录 D 后端已覆盖的
> 对外功能、后续增强项，以及保留下来供诊断使用的迁移基线。

## 状态口径

| 状态 | 含义 |
|---|---|
| ✅ | D 侧行为已对齐，并有测试或真实库验证 |
| 🟡 | 主路径可用，但仍有明确缺口 |
| ⬜ | 尚未开始 |
| ⏸ | 有意不移植；需求变化时再评估 |

目标不是复刻 Hibernate、Spring、Freemarker 的运行方式，而是在同一套 `bas.*` 数据库上，
用静态资源注册表、直接 SQL、手写 JSON/XML 输出实现同样的外部行为。

## 功能盘点

### 1. Hub 管理台 `/api/bashub`

#### 1.1 JSON:API 基础能力

| 功能 | 状态 | 说明 |
|---|---|---|
| 资源 CRUD | ✅ | `search` / `POST` / `GET` / `PATCH` / `DELETE`，18 个资源均可用 |
| 分页、排序、基础过滤 | ✅ | 对齐 `page[...]`、`sort`、`filter[...]` 的常用语义 |
| 关系写入与 `include` | ✅ | to-one、to-many、多值子表、嵌套 include |
| 派生属性 | ✅ | `qualifiedName`、`qualifiedTitle`、`gav`、`updatable`、`entryUrl` 等 |
| JSON 数组列 | ✅ | 如 `webapps.urls` |
| 多值过滤 `filter[x]=a,b` | ✅ | 文本 2–3 个用 `like ... or ...`，4 个以上与数字用 `in (...)` |
| 显式算子 `filter[x][op]` | ✅ | `between`、`ge`、`gt`、`le`、`lt`、`in`、`nin`、`eq`、`ne` |
| 日期时间结束上界 | ✅ | `datetime` 的 `le` / `lt` / `between` 右端补到当天或当段的上界 |
| `pageSize` cookie | ✅ | 仅在 `pageSize` / `page[size]` 都缺失时作为后备 |
| 必填字段校验 | ✅ | 创建校验全部必填项，PATCH 只校验提交字段；支持列、关系和 URI 列表 |
| 约束冲突错误映射 | ✅ | 唯一键/外键 → 409，非空/检查约束 → 400，并带字段或约束名 |

#### 1.2 管理台资源

以下普通资源已具备统一 CRUD：

`organizations`、`platforms`、`profiles`、`engines`、`farms`、`servers`、`hosts`、
`artifacts`、`webapps`、`platform-features`、`platform-feature-scripts`、`app-groups`、
`apps`、`channels`、`resources`、`menus`、`cdn-components`。

| 资源特化 | 状态 | 说明 |
|---|---|---|
| `profiles` 默认值 | ✅ | 生成 key、默认本地/远程仓库、HTTPS 开关 |
| `profiles` 重置凭证 | ✅ | `POST /profiles/{id}/reset-key` |
| `resources` 默认值 | ✅ | 新建默认 `Private` / 启用 |
| `channels` 默认值与唯一性 | ✅ | 默认 `pc` / `iframe` / 启用；同 app + 端类型唯一 |
| `engines.listeners/jars` | ✅ | 分隔符字符串规范化 |
| `platform-feature-scripts.scripts` | ✅ | 写入时去掉 `\r` |
| `webapps.urls` | ✅ | 数组读写 |
| `webapps` 升级 | ✅ | `POST /webapps/upgrade` |
| `artifacts.resolveSupport` 默认值 | ✅ | 新建时置 `true`（与原后端一样覆盖请求值） |
| `artifacts` 版本刷新 | ✅ | `POST /artifacts/update-version` |
| `artifacts` 定时版本刷新 | ✅ | `<artifacts refresh-minutes>` 周期刷新，缺省 360 分钟，0 关闭 |
| `artifacts` 部署情况 | ✅ | `GET /artifacts/{id}/webapps`，对应原 `ArtifactAction.info` |
| `hosts` 部署应用 | ✅ | `GET /hosts/{id}/webapps` |
| `hosts.featureLogos` | ✅ | 按主机平台过滤 |
| `menus` 位置重排 | ✅ | `indexno` 按同级位置重排整棵子树 |
| `menus` 入口资源 | ✅ | 入口资源自动并入资源集合 |
| `menus` 禁用级联 | ✅ | 禁用父菜单时级联禁用子孙 |
| 菜单 XML 导入/导出 | ✅ | `GET /menus/export`、`POST /menus/import` |
| `resources` 引用菜单 | ✅ | `GET /resources/{id}/menus`，对应原 `ResourceAction.info` |

#### 1.3 其他 Hub 端点

| 功能 | 状态 | 说明 |
|---|---|---|
| `GET /ems/configs` | ✅ | 登录前可读，下发 ems base / app name / logo |
| `GET /ems/sessions` | ✅ | 当前用户 |
| `POST /ems/sessions/logout` | ✅ | 本地会话清理与 CAS 登出地址 |
| `GET /monitor/agents/status` | ✅ | 在线节点快照，按 profile 排序；断连即从登记册摘除 |

### 2. 配置分发 `/api/bashub/config/{profile}`

部署配置直接输出文本，不再依赖模板运行时。

| 功能 | 状态 | 关键行为 |
|---|---|---|
| Profile 解析与令牌校验 | ✅ | `{profile}` 为 `org.name`；请求携带 Profile key，不再使用可伪造的 `ip` 头 |
| `GET /config/server` | ✅ | farms / hosts / webapps / 被引用的 engines、servers、artifacts；存在已启用 setline 的 Host 时在 Host 上输出 listen/admin 端口；`profile.proxyByHostname=true` 时输出 `setline-hostname`，默认省略并使用 `*` 组，不输出通道凭证 |
| `GET /config/proxy` | ✅ | 按 `proxyEngine` 输出 haproxy / nginx；用 Profile 令牌鉴权；haproxy 由 setline agent 生成 backend 与路由 map |
| `GET /config/certificate` / `config/certificate-key` | ✅ | Profile 分别保存 PEM 公钥证书与私钥；机器端点用 Profile 令牌下载，管理台私钥脱敏；setline pull 落成 nginx 的 cert/key 与 haproxy 的 bundle |
| `GET /config/setline-peers` | ✅ | 每个 Profile 都输出 sidecar peer 列表：web/Micdn 节点合并并按 URL 去重，没有节点时返回空数组；用 Profile 令牌鉴权 |
| `GET /api/bashub/ems/{profile}/menus/{appName}` | ✅ | 按 profile 与 artifact 找 App，再递归输出菜单和资源 XML |
| `GET /api/bashub/micdn/{profile}/micdn.xml` | ✅ | 按 Profile 输出完整 micdn 配置；用 `profile.key` 令牌鉴权；组件与绑定来自 `cdn_components` / `cfg_profile_micdn_components` |
| `GET /script/{host}` | ✅ | 找 Host，收集平台特性及依赖，按依赖优先级输出该平台脚本 |

这一组是 basctl 部署闭环的第一优先级。`server` 配置还承担节点通道地址与 Profile key 的
下发，必须先于 WebSocket 通道完成。

### 3. 节点通道 `/api/bashub/monitor/agents/{profile}/channel`

通道主体、`log:read` 与 `service:*` 已移植；启停动作由 basctl agent 执行，hub 等待 `result`。

| 功能 | 状态 | 说明 |
|---|---|---|
| WebSocket 握手鉴权 | ✅ | 推荐 `Authorization: Bearer <profile>:<Profile.key>`（兼容只发 key），失败在升级前返回 401 |
| 单 profile 单连接 | ✅ | 新连接登记后旧连接以 1008 `superseded` 关闭 |
| `hello` 身份与能力协商 | ✅ | host / basctl / bas / basHome / supports，能力去重排序 |
| `report:os`、`report:bas` | ✅ | 整份替换现状快照，保留各自 `at` |
| `pong`、`result` | ✅ | `pong` 已接收；`result` 按请求号唤醒等待者，超时与断连都会收敛为错误 |
| Hub 下发 `ping` | ✅ | 每条连接 60s 一次 app 层 ping |
| Hub 下发 `report:now` | ✅ | `POST /api/bashub/monitor/agents/{profile}/report`；按 `hello.supports` 门禁 |
| Hub 下发 `log:read` | ✅ | `GET /api/bashub/monitor/agents/{profile}/log`；按能力门禁，5 秒超时，返回 `{total,from,to,lines}` |
| Hub 下发 `agent:log` | ✅ | `GET /api/bashub/monitor/agents/{profile}/agent-log`；读 agent 自身 console，按能力门禁 |
| 浏览器日志跟随 | ✅ | `GET /api/bashub/monitor/agents/{profile}/log/follow` SSE；首次 `tail`、增量游标、轮转 `reset`、`Last-Event-ID` 续传 |
| `service:start/stop/restart` | ✅ | `POST /api/bashub/monitor/agents/{profile}/service/{action}`；按 `hello.supports` 门禁，等待 agent 回执 |
| 在线节点登记与摘除 | ✅ | 只摘自己那条，旧连接迟到的关闭不会挤掉新连接 |

### 4. 原生发行包仓库（已迁至 micdn）

原生发行包与 WAR/JAR 分发的职责已从 bashub 迁出，统一由
[micdn](https://github.com/beangle/micdn) 的 `/maven` 负责；bashub 不再暴露 `/repo`。

### 5. 安全、缓存与运行时

| 功能 | 状态 | 说明 |
|---|---|---|
| 内存会话缓存 | ✅ | 读取 CAS JSON 会话，含心跳与过期 |
| `CasHttpSessionRepo` 兼容 | ✅ | 以 Profile key / sid 读取真实会话 |
| 完整 CAS 登录流程 | ✅ | serviceValidate、JSON 401 / 浏览器 302；退出为本地 evict + 清 cookie，前端重定向到 CAS logout，不做后通道 SLO |
| 权限校验 | ✅ | Public/Protected/Private、root、`authorities` / `permissions`；未知资源只要求登录 |
| CORS | ✅ | 同源不加头、预检 204、来源白名单与安全响应头 |
| Caffeine / Redis 会话后端 | ⏸ | 当前明确只做进程内存 |
| 缓存淘汰与容量上限 | ⏸ | 低功耗部署下先不做多实例共享缓存 |
| 非 PostgreSQL 数据源 | ⏸ | 当前只实现 libpq / PostgreSQL |
| ems PBE 密文解密 | ⏸ | 配了 `ENC(...)` 的部署目前需先提供明文 |
| 远程 `EmsApi` 取配置/数据源 | ⏸ | 当前只读本地 ems 文件 |
| 热加载 / SIGHUP | ⏸ | 配置启动时读取一次 |
| 菜单 XML multipart 上传 | ✅ | `POST /api/bashub/ems/menus/import`（`app` + `menufile`） |
| 定时任务框架 | ✅ | 会话心跳 + 组件版本刷新；`<artifacts refresh-minutes>` 控制间隔，0 关闭 |

### 6. 数据库与 schema

| 功能 | 状态 | 说明 |
|---|---|---|
| 管理台 18 个资源的表映射 | ✅ | 与 `db/postgresql/db.xml` 对齐 |
| `0.0.8` schema 收尾 | ✅ | 增量脚本已归档；`init/` 与 `db.xml` 是当前全量；`cfg_webapps.urls`、`cfg_hosts.setline_listen_port` / `setline_admin_port` 已就位，旧 `cfg_profiles.setline_port` 已移除 |
| D 侧 schema 漂移检查 | ✅ | 启动时告警；`--check-schema` 只检查并返回退出码 3 |
| 约束冲突错误映射 | ✅ | 唯一键、外键转为 409，非空、检查约束转为 400 |

## 里程碑

### M0：管理台骨架（已完成）

- 18 个资源统一 CRUD、基础查询、关系与派生属性。
- `configs`、`sessions`、菜单、Profile key、批量升级/版本刷新等定制动作。
- ems 常量、数据源、CAS 会话读取。
- `0.0.8` schema 迁移。

### M1：部署配置分发闭环（已完成）

1. ✅ Profile 解析与 IP 校验。
2. ✅ `config/server` 文本输出。
3. ✅ `config/proxy` 的 haproxy / nginx 输出。
4. ✅ `ems/menus/{appName}`。
5. ✅ `micdn.xml`、`script/{host}`。

验收：同一 Profile、同一数据库、同一请求头下，输出与迁移前基线逐字对比（空白差异单独记录）；
`config/server` 缺失 Profile 返回 404、token 不匹配返回 401；仍走 IP 的其余端点保持原有 404 口径。

### M2：节点通道（已完成）

1. ✅ WebSocket 握手鉴权、连接登记、保活与断连摘除。
2. ✅ `hello`、`report:*`、`pong` 与 `ping`、`report:now`、`result` 请求等待表。
3. ✅ `agents/status`。
4. ✅ `log:read` 请求/应答、超时与断连唤醒。
5. ✅ `service:start/stop/restart` 请求/应答：按能力门禁，2 分钟超时；agent 执行后重报实例快照。

验收：用假 agent 覆盖握手拒绝、重连踢旧、心跳、快照覆盖与请求超时；用真实 basctl 完成一次
出站连接。

### M3：管理台补齐（已完成）

1. ✅ 多值过滤、显式过滤算子和 `pageSize` cookie。
2. ✅ 必填字段校验与数据库约束错误映射。
3. ✅ 除菜单 XML 外的通用 multipart 上传。
4. ✅ 组件最新版本定时刷新。
5. ✅ schema 漂移检查。

验收：前端不需要针对 D 后端增加分支；现有 SPA 的全部管理页面通过真实库回归。

### M4：登录与权限（已完成）

1. ✅ CAS 票据校验、302 登录跳转与 CAS logout。
2. ✅ 资源动作权限、Profile 上下文与超级管理员判定。
3. ✅ CORS 与安全响应头。

验收：未登录、会话过期、无权限、合法用户四条路径均有稳定测试；`configs` 仍保持免登录。

### M5：运维增强（按需）

- 缓存后端与多实例同步。
- 缓存容量上限、惰性淘汰与未知 sid 负缓存。
- 非 PostgreSQL 数据源、PBE 密文、远程 ems 配置。
- CAS/ems 出站请求目前走阻塞 curl；并发上量前改为 worker 线程或 libcurl 绑定。
- 节点状态的历史曲线、筛选与日志下载（基础页面 `/monitor/agents` 已接入）。
- Profile 数据范围过滤（当前只作为安全上下文，未用于列表查询）。
- 热加载、指标与更完整的定时任务。

这些不阻塞单机低功耗部署，只有实际部署提出要求时再做。

### 待验收留档

- 真实库 + SPA：18 个管理页完整回归，确认前端没有 D 后端专用分支。
- 真实 basctl：本机已完成一次出站连接、`report:now`、`agents/status` 与 `log:read`；生产环境仍需留档一次。
- 配置输出：同一 Profile/数据库/请求头下与迁移前基线对比 server.xml、代理、菜单、资产和脚本。
- 真实 CAS：登录、会话续期、过期、登出与前端重定向各跑一遍。

## 明确不追求的事项

- 不移植 Spring / CDI / Hibernate / Freemarker 的运行时模型。
- 不保留实体对象、一级/二级缓存、延迟加载和反射属性访问。
- 不要求原后端的类、方法、配置文件与 D 侧一一对应。
- 不为了兼容而保留已经由 micdn 取代的 Maven 分发路径。

## 迁移完成状态

1. ✅ 管理台 SPA 的所有现有页面只连 D 后端。
2. ✅ basctl 能通过 `/api/bashub/config/{profile}/server` 获取配置，通过
   `/api/bashub/monitor/agents/{profile}/channel` 建立通道。
3. ✅ 生产部署所需文本配置、菜单、静态资产和主机脚本均可由 D 输出。
4. ✅ 登录、会话、权限和登出行为与迁移前基线一致。
5. ✅ 原 JVM 后端已退役，代码与专用构建已删除。
