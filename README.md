# bashub — BAS 控制台（前端 SPA / D 后端）

BAS 控制台这一个产品的 monorepo，两部分各自独立构建：

| 部分 | 位置 | 构建 | 产物 |
|---|---|---|---|
| 前端 SPA | `packages/web` | pnpm + vite | `packages/web/dist`、`release/bashub-web.zip` |
| D 后端 | `src/beangle`、`src/bashub` | dub | `target/d/bashub`（`/api/hub`、`/api/{profile}`、`/repo`） |

```bash
pnpm build:web                              # 前端 → packages/web/dist
dub test --compiler=ldc2                    # D 后端：跑测试
dub build -b release --compiler=ldc2        # D 后端 → target/d/bashub
./target/d/bashub -f bashub.xml             # 起 D 后端（缺省读 ./bashub.xml）
```

控制台 API 与部署配置分发由 D 后端唯一实现，目标是**低功耗运行**。原 JVM 后端已于 2026-10
退役；数据库仍是同一套 `bas.*` 表（含 `public.next_id()` 主键生成器）。完整的功能盘点、
后续增强项见 [`docs/roadmap.md`](docs/roadmap.md)。

D 代码分两块：**`beangle.*` 是可复用的框架**（数据面「资源注册表 → 查询计划 → SQL」、协议面
「JSON:API 文档渲染 → 服务层 → CRUD 路由」、会话面「会话模型 → 内存缓存 → CAS 客户端」），
**`bashub.*` 是业务**（BAS 控制台这一份，只留自己的资源定义、演示数据与配置分发端点）。
包名按最终归属切好，框架将来搬到 beangle 的 D 项目时只是挪目录。

## 为什么用 D 实现

传统 JVM 后端真正「重」的部分不是业务，而是框架带来的动态性：Hibernate 的会话/脏检查/延迟加载、
Spring 的容器与代理解析、Freemarker 反射取属性、JPA 注解推导表名。这些在 D 里全都不需要：

| 关注点 | 传统 JVM 实现 | D 实现（`beangle.*` 框架 + `bashub.*` 业务） |
|---|---|---|
| 表/列/关系 | 实体注解 + 运行期反射推导 | `resources.d` 一张静态注册表（`Registry`） |
| 查询 | OQL 字符串 + 参数绑定 | `plan.d` 生成普通 SQL，参数是 `?` 占位 |
| 缓存 | 一级/二级缓存、实体缓存 | 一律不缓存，每个请求现查 |
| 主键 | Hibernate `AutoIncrementGenerator` | 直接 `select public.next_id('bas.cfg_x')`，同一个生成器 |
| 渲染 | Freemarker + 反射 | 手写 JSON:API 渲染（`document.d`），只有实际用到的子集 |
| 结果 | 实体对象（`Entity`） | `Json[string]` 的一行，没有对象、没有会话 |
| 组装 | Spring 容器、XML bean | `app.d` 里几行显式装配 |
| 会话 | Spring Security + CAS + Caffeine/Redis | `beangle.security.cas`（CAS 会话服务的 D 版客户端）+ 进程内存缓存 + 定时心跳 |

实测（release 构建，本机 x86_64）：可执行文件 4.4 MB，启动后 RSS ≈ 12 MB，
压 200 次列表请求后 RSS ≈ 14 MB。

## 代码在哪

D 侧的包分成两块：**`beangle.data`** 与 **`beangle.jsonapi`** 是可复用的框架（所以不叫
`bashub`），**`bashub.*`** 是 BAS 控制台的业务（将来别的业务也往这里加）。

框架按「数据面 / 协议面 / 会话面 / 部署面」分开——不是所有东西都是 JSON:API 语义：`value`（行）、
`resource`（表/列/关系映射）、`query`（查询对象）、`plan`（SQL 生成）、`dao`（后端）都与协议
无关，放进 `beangle.data`；只有文档渲染、服务层与 CRUD 路由是 JSON:API 的，放进
`beangle.jsonapi`；会话与账户模型、内存缓存、CAS 会话客户端与两者都无关，放进
`beangle.security`；部署期常量（ems 的 base/cas/会话 cookie 名）与两者也都无关，放进
`beangle.ems`。

```
src/beangle/data/           框架·数据面（与协议无关）
  value.d       Row = Json[string]（列 → 值）与取值小工具
  resource.d    Column/Relation/Derived/Resource + Registry（资源 → 表/列/关系，启动时建好即只读）
  query.d       查询对象与查询串解析（page[...]/sort/filter[...]/include），对齐 she 的 QueryHelper
  plan.d        资源 + 查询 → 与库无关的计划（from/join/where/order/limit）并生成 SQL
  dao/          Dao 接口 + 两个后端：postgres.d（libpq 直连）、pq.d（最小 libpq 绑定）、
                memory.d（内存/可 seed）

src/beangle/jsonapi/        框架·JSON:API 协议面
  document.d    行 → data/included/meta.page/errors（纯函数）
  store.d       服务层：查询/写入 → Dao → 文档；fillDefaults 钩子补服务端默认值
  router.d      JsonApiService + buildJsonApiRouter：CRUD 路由与统一错误映射

src/beangle/commons/
  io/javaprops.d `java.util.Properties` 文本格式解析
  xml.d         dxml 上的最小解析辅助（属性、子元素、元素文本；标准库没有 XML）
  sysprops.d    环境变量与命令行部署选项合并成一张表
  net/curl.d    最小 HTTP 客户端：交给宿主 curl 取状态码与响应体（TLS 交给它）

src/beangle/ems/            框架·部署面（与协议无关）
  package.d     Ems：base/cas/api/innerApi/key/sid/hostname
  env.d         EmsEnv + PropertyReader：home + conf.properties → 一整套地址
  app.d         EmsApp：`<ems app-name="...">` → name/path、读 `${home}${path}.xml`
  datasource.d  从应用文件/`resources.xml` 读 `<datasource>` → libpq 连接串

src/beangle/security/       框架·会话面（与协议无关）
  session.d     Profile/DefaultAccount/Agent/Session + SessionRepo 契约（时间用 epoch 秒）
  sessionjson.d 会话 JSON 解码：CAS 会话的唯一报文格式
  sessioncache.d CacheSessionRepo：内存缓存 + 回源 + 访问心跳
  cas.d         CasConfig/CasSessionRepo：会话查询、续期、过期与登出的 URL 与语义

src/bashub/                 业务：BAS 控制台这一份
  app.d         进程入口：读配置 → 建 Registry/Dao/Store → 起 HTTP
  config.d      bashub.xml 解析（监听地址、库连接串、接口前缀、ems 地址；缺省值取自 beangle.ems）
  resources.d   管理台资源的定义（表名/列/关系/集合/派生属性）
  demo.d        内存后端的演示数据（只供测试显式使用）
  store.d       服务层装配 + bashub 的 fillDefaults（配置的 key）
  profile/      Profile 名称/IP 校验、配置分发共享快照、server.xml / haproxy / nginx /
                EMS 菜单 / micdn 资产清单 / 主机脚本
  repo/         原生发行包仓库：正式版/SNAPSHOT 两套根、最新快照解析、SHA-1 暂存与 HTTP 读写
  menus.d       应用资源/菜单 XML 的导入导出
  route.d       bashub 自己的端点 configs/sessions + 把通用 CRUD 挂上同一张 router
  logging.d     日志落到文件或控制台
```

依赖是单向的：`beangle.jsonapi → beangle.data`，`beangle.security → beangle.commons.net`，
`beangle.ems.datasource → beangle.ems.app`，`beangle.ems → beangle.commons`（`io`/`xml`），
业务侧再用 `bashub.config → beangle.ems(.datasource)` 取缺省；
数据面里 `resource ← query/plan ← dao`，`document` 只依赖 `resource` 与 `value`——所以文档渲染、
计划生成、参数解析、会话缓存、环境推导都能脱离 HTTP 与数据库单独测（CAS 客户端注入一个取数
函数就能整条脱网测，ems 的推导只吃「home + 一份 properties 表」）。业务侧（`src/bashub/`）里
没有一处 SQL，也没有一处查询参数解析。

测试与源码一一对应：`test/beangle/data/`（查询参数、计划）、`test/beangle/jsonapi/`（文档、
服务层、路由）、`test/beangle/security/`（报文兼容、会话语义、CAS 客户端）、`test/beangle/ems/`
（环境推导、常量、应用清单、数据源）、`test/beangle/commons/`（properties 解析、XML 取值、环境变量合并）
共 18 个模块，
夹具在 `test/beangle/fixture.d`、`test/beangle/tempdir.d`（临时目录；这份 Phobos 没有
`mkdirTempDir`）与 `test/beangle/security/fake_cas.d`（假 CAS，前后场共用）；
`test/bashub/` 是业务的 11 个模块（配置解析、服务层装配、路由契约、会话端点、Profile 配置分发、
组件版本刷新、节点通道协议、在线登记册、原生仓库布局、原生仓库 HTTP 契约、WAR 坐标解析）。

## 已经做了什么

一个进程、一个事件循环，`dub` 构建，`bashub.xml` 配置：

- **JSON:API 读写**：`GET {prefix}/{resource}/search`、`POST {prefix}/{resource}`、
  `GET|PATCH|DELETE {prefix}/{resource}/{id}`，URL 形状与 bashub 的 `docs/frontend-api.md` 一致。
- **查询语义与 she 的 `QueryHelper`/`Conditions` 对齐**：`pageIndex`>`page[number]`、
  `pageSize`>`page[size]`（缺省 1/20）、`orderBy`>`sort`（`-` 前缀倒序）、
  字符串过滤的 `^`/`$`/`null` 锚点、非字符串走 `=`、关系过滤按 id 全等、未知键 400。
- **关系与派生属性**：to-one、to-many、多值子表（`listeners`/`jars`）、`jsonb` 字符串数组
  （`webapps.urls`）、`include=servers.host` 嵌套展开，以及 `qualifiedName` / `qualifiedTitle`
  这类 `{org.name}.{name}` 模板派生属性。前端查询串里的实体别名（`filter[profile.name]`）
  与引用主键（`filter[webapp.profile.id]`）也按 she 的口径解析。
- **资源**：管理台的 organizations、platforms、profiles、engines、farms、servers、hosts、
  artifacts、webapps、platform-features、platform-feature-scripts、app-groups、apps、channels、
  resources、menus、asset-groups、assets 都有统一 CRUD（在 `resources.d` 里加一条 `Resource`
  就多一个资源，路由不用改）。
- **`configs` / `sessions`**：`GET {prefix}/configs`（免登录，前端据此知道 ems 地址）、
  `GET {prefix}/sessions`、`POST {prefix}/sessions/logout`。
- **Profile 配置分发**：`GET /api/{profile}/config/server` 用
  `Authorization: Bearer <profile>:<Profile.key>` 鉴权（也兼容只发 key 的旧客户端），
  下载端点也接受用户名是 Profile 名的 HTTP Basic，不再依赖可伪造的 `ip` 头；server.xml 只收窄到
  本 Profile 的 farms/hosts/webapps 及其引用到的 engines、servers、artifacts。管理台另用
  `GET /api/hub/profiles/{id}/config/server`（登录会话鉴权）查看同一份结果。
  `GET /api/{profile}/config/proxy` 按 `proxyEngine` 输出 haproxy / nginx；HAProxy 主配置
  只按请求 `path` 做 `map_beg` 路由，只有带 targets 的 webapp 参与，按 farm + server 集合分组。
  proxy 下载使用同样的 Bearer 凭证。
  Profile 的 `sslCertificate` / `sslCertificateKey` 保存 PEM 公钥证书与私钥；管理台只回显公钥，
  私钥始终脱敏。setline 用同一凭证分别拉取 `GET /api/{profile}/config/certificate` 与
  `config/certificate-key`，落成 `/etc/setline/certs/cert.pem`、`key.pem` 和 haproxy 的
  `bundle.pem`。未配置证书时两个端点返回空 Body。
  `GET /api/{profile}/config/setline-peers` 输出 sidecar 的 peer 列表（JSON）：
  `peers` 由 Profile 下的 web 节点以及 Micdn 配置中登记的服务器合并生成；Micdn 服务器
  使用各自的 `adminListen`。没有节点时返回空数组。`setline pull` 直接把这组 peers 写回
  节点自己的 `setline.conf`，`setline.json` 仍只保存本机监听与路由。各节点自己的 setline
  仍需把读入口开到 sidecar 可达，并把 sidecar 主机 IP 写进 `peerReaders`。
  `GET /api/{profile}/ems/menus/{appName}`
  按部署 artifact 找到 EMS 应用并输出资源/菜单 XML。`GET /api/{profile}/micdn/asset` 按
  Profile 关联的静态资源组输出资产清单；`GET /api/{profile}/script/{host}` 按 Host 平台与
  特性依赖生成检查脚本。真实库的 server.xml 已通过 basctl 的 `bas-1.0.0.xsd`。
- **ems 部署常量**（`beangle.ems`）：宿主配了 `ems.home`（或 `ems.base`/`ems.profile`）就按
  ems 规则读 `home/conf.properties`，推出 base/cas/portal/api/`inner_base` 与两个会话
  cookie 常量，再拿它们当 `bashub.xml` 的缺省——所以「换一套 ems 部署」= 换一个 `ems.home`，
  `session_id_name` 这类量不用在 `bashub.xml` 里再抄一遍（抄错一份就是「拿不到会话」）。
  `EmsApp` 的清单解析（`<ems app-name>` → `/platform/testwebapp`）也一并移植了，供将来用。
- **数据源取自 ems**（`beangle.ems.datasource`）：`bashub.xml` 没写 `<db url="...">` 时，
  按 ems 数据源顺序读 `${home}${path}.xml`（path 由 `app-name` 推）
  与 `${home}/resources.xml`，把 `<datasource name="default">` 的字段翻译成 libpq 连接串
  （`serverName`/`portNumber`/`databaseName`/`user`/`password`，缺省 localhost:5432；`<schema>`
  映射成 `search_path`，`application_name` 填应用名）。真实部署里库连接就写在这份 XML 上，
  两条实现路线读同一份文件——本机 `--ems.profile=bas` 起来就连的是 `~/.ems/bas/bas/hub.xml` 那个库。
- **CAS 会话集成**（`sessions` 端点）：配了 `<ems cas="...">`（或由 ems 常量推出 cas）就按
  `Ems.sid.name`（缺省 `EMS_SID`）cookie 读会话——
  未命中回源 `GET {cas}/session/{id}?format=application/json`（JSON 解码）、
  `access` 续期并攒心跳、过 tti 就
  `GET {cas}/session/{id}/expire` 作废、`sessions/logout` 只 `evict`（CAS 那边的会话让它自己过期）。
  心跳每 3 分钟（`flushIntervalSeconds`）打一次
  `/session/{id}/access?time=`，只报「这次真推进了 lastAccessAt」的会话。
- **登录与资源授权**（M4）：有 `EMS_SID` 就直接读会话；没有会话但带 `ticket` 时调用
  `{cas}/serviceValidate`，把 CAS 的 `authorities`/`permissions` 映射进账户。JSON 请求未登录回
  401 + `errors[0].meta.redirectUrl`，浏览器导航回 302 到 `{cas}/login?service=...`；已登录但
  Private 资源角色不命中回 403，root 直接放行。资源名沿用原 action 名，取
  `/api/hub/{resource}`，因此 ems `resources.json` 可以直接复用；未登记资源按
  `unknownIsProtected` 只要求登录。`configs` 不挂 guard，保持登录前可读。
- **CORS 与安全响应头**：同源不下发 CORS 头；允许来源的预检回 204，不允许的来源回 403；
  `<api cors-origins="https://hub.example.com,https://sas.openurp.net">` 可覆盖缺省的本机来源，
  ems base 的主机名会自动加入。API 响应带 `Cache-Control: no-store`，所有响应带
  `X-Content-Type-Options: nosniff` 与 `Referrer-Policy`；反代声明 HTTPS 时加 HSTS。
- **定制动作 `POST {prefix}/profiles/{id}/reset-key`**：重置通道凭证（重置即吊销），
  返回 `{"id":…,"key":"…"}`，找不到 404。这是「应用自定义端点」的样板：挂在同一张 router 上、
  复用框架的鉴权与错误文档，只改一列时用 `Store.updateColumns`。
- **BAS 写入特化**：资源新建默认 `Private`/启用；通道默认 `pc`/`iframe`/启用并保证
  「同应用 + 同端类型」唯一；平台特性脚本去掉 `\r`；`Profile.assetGroups` 保存后同步关联表
  的另一侧；菜单的 `indexno` 按位置重排整棵子树、入口资源自动并入 `resources`、禁用父菜单时
  级联禁用子孙。
- **菜单 XML**：`GET {prefix}/menus/export?app={id}` 导出资源与递归菜单，
  `POST {prefix}/menus/import`（multipart 字段 `app` + `menufile`）按资源名与
  `(indexno,name)` 增量合并，保留导入文件里的原始层级编号。
- **两种 Dao**：libpq 直连的 `DbDao` 与内存的 `MemoryDao`（带演示数据）。可执行程序只接受
  `DbDao`：**没配数据库或连不上时启动失败**，不会自动退回内存把配置错误伪装成正常启动；
  `MemoryDao` 只供测试显式使用。
- **原生发行包仓库**：`HEAD` / `GET /repo/native/{path}` 与 `POST /repo/native/upload/{path}`。
  SNAPSHOT 别名解析到最新 `时间戳-构建号` 文件，GET 302 到具体文件、HEAD 用 `latest` 头回带；
  `.sha1` 可以先于构件上传，暂存在 `<root>/.pending`，构件到达后自动归位。上传令牌
  `snapshot.usertoken` 从 `<repo token>` 或 ems 应用文件读取。
- **测试**：业务 12 个模块（配置解析、服务层装配、路由契约、会话端点、安全路由、Profile 配置分发、
  组件版本刷新、节点通道协议、在线登记册、原生仓库布局、原生仓库 HTTP 契约、WAR 坐标解析），框架 22 个模块（参数
  解析、计划、文档、服务层、路由、会话 JSON 报文兼容、会话语义、CAS 客户端、ems 环境
  推导与常量、应用清单、数据源、schema 漂移、properties 解析、XML 取值、环境变量合并、CAS XML、
  授权域、远程授权刷新、Web 安全上下文与测试夹具），合计 34 个模块，都是
  `dub test`。`sessionjson_test.d` 里钉的是真实序列化出来的兼容报文；
  `cas_test.d` 起一个独立线程的假 CAS，真 fork curl、真过 TCP。

## 怎么跑

```bash
dub build -b release --compiler=ldc2     # 出 target/d/bashub
./target/d/bashub -f bashub.xml          # 缺省读 ./bashub.xml
dub test --compiler=ldc2                 # 跑单测
```

命令行采用 D/POSIX 风格的长选项，`--key=value` 与 `--key value` 两种写法都支持：

```bash
./target/d/bashub -f bashub.xml --ems.profile=bas
./target/d/bashub -f bashub.xml --ems.home /data/ems/bas
./target/d/bashub -f bashub.xml --check-schema
```

`-f`/`--file` 指定配置文件；`--ems.profile`、`--ems.home`、`--ems.base` 覆盖同名环境变量。
JVM 的 `-Dkey=value` 不兼容：`std.getopt` 会把它当成未知选项并报错退出，不会忽略或透传给 vibe。

**为什么还要自己接管 argv**：bashub 需要先消费自己的选项，再把剩余参数交给 vibe。编译期开
`VibeDisableCommandLineParsing`（见 `dub.json`），进场用 `std.getopt` 严格解析，最后用
`setCommandLineArgs` 把「vibe 的」参数还给它。
副作用：vibe 那套 `vibe.conf`/`--disthost`/`--port` 形式的配置对 bashub 不再生效（本来也不靠它）。

宿主需要 `curl`：会话服务是 https，而 D 侧按 Beangle D 路线的惯例关掉了 vibe 的 TLS
（`dub.json` 的 `notls`），所以取会话走宿主 curl（与 micdn 同一个做法）。

`bashub.xml`：

```xml
<bashub listen="127.0.0.1:18080" log-level="info">
  <db url="host=127.0.0.1 port=5432 user=bashub dbname=bas"/>   <!-- 可省略：由 ems profile 提供 -->
  <!-- auth="required" 时挂登录/权限；authority-url 缺省由 ems innerApi 推出 -->
  <api prefix="/api/hub" auth="none"
       authority-refresh-minutes="5"
       cors-origins="https://hub.example.com,https://sas.openurp.net"/>
  <!-- 不配 cas 则 sessions 给演示用户；配了 cas 后会话固定按 JSON 读取 -->
  <ems base="https://sas.openurp.net" app-name="bas-hub"
       cas="https://sas.openurp.net/cas" session-id-name="EMS_SID"/>
  <!-- native 仓库；token 未写时从 ems 应用文件的 snapshot.usertoken 读 -->
  <repo home="~/.m2" token="..."/>
  <!-- 组件最新版本刷新间隔（分钟）；0 关闭，缺省 360 -->
  <artifacts refresh-minutes="360"/>
</bashub>
```

`<ems>` 里的每一项都可以省：配了 `ems.home`（或 `ems.base`/`ems.profile`，环境变量或 `--ems.*` 都行）时，
`base`/`cas`/`session-id-name` 由 `~/.ems/<profile>/conf.properties` 推出来；这几项写进 `bashub.xml` 就覆盖它。

数据库结构检查可以独立执行，不启动 HTTP：

```bash
./target/d/bashub -f bashub.xml --check-schema
# 全部存在 → "schema ok"；漂移 → 逐条列出并以退出码 3 结束
```

**测「取会话」**（接真 CAS，不需要别的应用配合）：

```bash
# 1) 只留 api 段，让 base/cas/cookie 名全由 ems 推出来
cat > /tmp/bashub-sess.xml <<'EOF'
<bashub listen="127.0.0.1:18080" log-level="info">
  <api prefix="/api/hub" auth="required"/>
</bashub>
EOF
./target/d/bashub -f /tmp/bashub-sess.xml --ems.profile=bas
# INFO - Session repo: https://sas.openurp.net/cas/session/{id}?format=application/json (cookie URP_SID, ...)

# 2) 从浏览器（登录过 sas 的任意应用）拿 URP_SID 这个 cookie 的值；先直接问一次 CAS：
curl -s "https://sas.openurp.net/cas/session/$SID?format=application/json" | jq .

# 3) 带 cookie 打 bashub：命中 → 真实账号，无效/没有 → 401 + meta.redirectUrl
curl -s -i -H 'Accept: application/vnd.api+json' -H "Cookie: URP_SID=$SID" \
  http://127.0.0.1:18080/api/hub/sessions
```

`auth="none"` 时第 3 步拿不到会话是给演示用户（200）而不是 401。

试一下：

```bash
curl -s -H 'Accept: application/vnd.api+json' \
  'http://127.0.0.1:18080/api/hub/profiles/search?filter%5Borg.name%5D=beangle&include=org'
```

## 功能边界（尚未实现与已补齐）

按「先铺骨架、后补业务」的顺序，下面这些**没有实现**，其中前几项是真实缺口而非有意裁剪：

- **认证/授权边界**：票据登录只在当次请求生效，不抢写 CAS 域的共享 cookie；退出登录清本地
  会话和 cookie，随后由前端重定向到 CAS `/logout?service=...`，不做后通道单点登出。选中的
  Profile 参与安全上下文，但还没有把它用于列表/数据范围过滤。资源未在 ems 登记时只要求登录（与原后端
  `unknownIsProtected=true` 一致），不会因为远端资源表暂不可用而退回匿名可写。
- **会话缓存的可换后端**：原 JVM 后端能换 Caffeine/Redis，这里只有进程内存一层
  （重启即失效，多实例不共享）；也没有容量上限与惰性淘汰。认不出的 sid 每次都回源一次
  （与原后端一致），没做负缓存——拿乱码 sid 打这个端点就是拿它打 CAS。
- **会话报文只做 JSON**：CAS 的 `/session/{id}` 返回完整 JSON，bashub 不再维护第二套二进制协议。
  JSON 口径下 `DefaultAccount.isRoot` 恒为 false（原后端的 getter 进不了属性表），
  普通授权仍按 `authorities` / `permissions` 判定。
- **ems 里那些「要网络 / 要加解密」的部分**：`Ems.decryptor`（PBE）没移植，所以 `EmsApp` 合并
  `${home}${path}.xml`、以及读 `<datasource>` 字段时**都不会**把 `ENC(...)` 解一遍密文（值原样
  保留并记一条警告，配了密文的部署得先填明文）；`redis` 配置、blob 仓库、classpath 与 HTTP 取资源
  （`${innerApi}/platform/config/files/...`）、`Ems key plain` 那条命令行、`System.exit(1)`
  （缺清单现在只返回空值，由调用方退回缺省）都没做；`Org`/`Domain`/`Theme` 这几个纯数据类也没搬。
- **数据源只认 PostgreSQL**：`<datasource>` 的 `<driver>` 不是 `postgresql`/`pgsql` 时记警告并
  当作没有配置（原 JVM 后端借 JDBC 驱动还能吃 mysql/oracle/dm）；也没移植「应用文件与 `resources.xml`
  都没有时去问 `EmsApi.getDatasourceUrl`」那一步（要网络）；`<url>` 只认
  `jdbc:postgresql://host[:port]/db` 与现成的 `key=value` 串，JDBC 的查询参数不搬。
- **节点通道的写指令**：`log:read` 已接到 `GET /api/hub/agents/{profile}/log`，带请求号等待
  `result`、超时与断连唤醒；`GET .../log/follow` 用 SSE 持续跟随，首次取尾部后按游标增量拉取，
  轮转时下发 `reset=true`，断线重连按 `Last-Event-ID` 续传；`POST /api/hub/agents/{profile}/report`
  要求节点立即刷新快照。`POST /api/hub/agents/{profile}/service/{action}`（`start` / `stop` /
  `restart`）按实例下发 `service:*`，等到 agent 回执后再返回最终状态。
  SPA 的 `/agents` 页面展示在线节点、系统/实例快照与能力，并支持立即上报、区间读日志、SSE 跟随，
  以及实例的重启 / 停止（带二次确认）。
- **`/api/{profile}` 配置分发**：server.xml、反代配置、EMS 菜单、micdn 资产清单与主机脚本
  均已改为 D 侧直接渲染，不再依赖 Freemarker 模板运行时。
- **其余定制动作**：`profiles/{id}/reset-key`、`webapps/upgrade`、`hosts/{id}/webapps`、
  `artifacts/{id}/webapps`、`resources/{id}/menus`、`artifacts/update-version` 与
  `menus/export|import` 已做。
- **查询语义**：多值过滤（`filter[x]=a,b` → `in (...)` / `or`）、
  `filter[attr][op]` 显式算子、`pageSize` cookie 与日期时间结束上界均已对齐。
- **必填与约束错误**：创建时校验前端声明的必填列、关系和 URI 列表，PATCH 只校验实际提交的字段；
  PostgreSQL 唯一键/外键冲突返回 409，非空/检查约束返回 400，并带字段或约束名。
- **缓存、热加载、集群**：没有实体缓存，也没有 SIGHUP 重载（配置只在启动时读一次）。
- **`/repo` 原生发行包仓库**：已做 HEAD / GET / SNAPSHOT 别名与上传；正式版落 `repository`，
  SNAPSHOT 落 `snapshots`，`.sha1` 可先于构件到达。
- **multipart 构件上传**：`POST {prefix}/snapshots/upload`（字段 `warfile`）从 WAR/JAR 的
  `META-INF/MANIFEST.MF` 读取 `Implementation-Vendor-Id/Title/Version`，推导仓库路径后落盘。
- **schema 漂移**：启动时把资源定义所需的主表/子表/列与 `information_schema` 比较并告警；
  `--check-schema` 提供不启动服务的独立检查。
- **组件版本刷新**：`<artifacts refresh-minutes>` 周期任务与 `artifacts/update-version`
  共用 Maven metadata 解析；缺省 360 分钟，0 关闭。

输出侧已补：`artifacts.gav`、`webapps.gav/artifactName/updatable`、`hosts.featureLogos`、
`menus.entryUrl`、`assets.bundleUris`（`cdn_asset_bundles` 的 gav/location 双列转换）。
主行与集合的写入现在包在同一个 DAO 事务里，集合写失败会回滚主行。

## 与 bashub 行为对齐的几个细节

改这几处（`beangle.*` 框架、`bashub.*` 业务）时最容易踩的几条：

- 关系外键在**行里**用的键是**关系名**（SQL 写成 `t.org_id as org`），而**过滤条件**里用的是
  物理列（`t.org_id`）；`MemoryDao` 负责把列名兜回关系名。
- 查询参数里写的是 **JSON:API 属性名**（`filter[httpPort]`、模板里的 `{org.shortTitle}`），
  计划生成时翻成行键（`http_port` / `short_title`）；行键写法也一并接受。
- `search` 永远分页，`meta.page` 永远存在（对应 she 里 `limit(getPageLimit)` 缺省 20）。
- 过滤不设白名单：属性存在就能过滤，认不出的键 400 而不是交给数据库报错。
- **部署常量只在 ems 里定义一处**：`bashub.xml` 的 `session-id-name` > `Ems.sid.name` > `EMS_SID`；
  `ems_base`/`cas` 同样先看 `bashub.xml`，没写才由 ems 常量推（`cas` 缺省 = `base + "/cas"`，
  配了 `ems.home` 就等于打开 CAS 会话；不想要就在 `bashub.xml` 里显式写 `cas=""`）。
  读的是 `ems.home/conf.properties`，按 **JDK Properties 口径**解析（每个字节当 Latin-1 字符 +
  `\uXXXX` + `\` 续行 + `#`/`!` 注释）——解析口径与 JVM 一致，差一个转义就会配错。
  `ems.home` 优先，其次 `ems.base`（缺省 `~/.ems`）下的一个 profile 目录（`ems.profile` 指定或取
  第一个，只认目录）；命令行没有 JVM 系统属性，改用**同名环境变量 +
  `--ems.home`/`--ems.base`/`--ems.profile` 命令行覆盖**（命令行优先）。
  三个 `ems.*` 都没配时 `emsFromEnvironment` 返回 null，一切缺省照旧（别让「本机装了 ems」
  悄悄改掉宿主的配置）。
- **库连接也是「一处定义」**：`bashub.xml` 的 `<db url>` > ems 应用文件 `${home}${path}.xml` 的
  `<datasource name="default">` > `${home}/resources.xml` > 没有（启动失败，不再退回内存演示数据）。
  解析口径：`<driver>` 空就从 `jdbc:` url 里推 driver 名、
  `props/prop` 用 `name`/`value`（注意 `EmsApp` 那边是 `key`/元素文本，两种写法都对）、
  `maximumPoolSize` 这类 Hikari 参数读进来但不搬（D 侧每条请求现查，没有连接池调参那回事）。
- **读 AA 里可能不存在的键要用 `.get(k, 默认值)`**：本机 ldc 1.42 的 druntime 下
  `aa[missing]` 会直接抛 `RangeError`（写入仍是插入语义）。
- **会话报文固定走 JSON**（`?format=application/json`）。现网 CAS 返回完整会话对象；
  id 是**带前缀的整个 cookie 值**（`URP-…`）、时间是 ISO_INSTANT 文本、
  `Map` 落成 `[[k,v],...]`、null/None 不落盘。`DefaultAccount.isRoot` 不在 JSON 属性表中，
  因此恒为 false；普通授权按 `authorities` / `permissions` 判定。
- `access` 的返回值有两个特殊值：`-1` 表示已过期（此时清缓存并打 `expire` 让 CAS 也删），
  `0` 表示时钟回拨（按 0 计、**不**更新 lastAccessAt）；只有 `> accessDelaySeconds`（20~60 秒
  随机）才记一次心跳。
- 会话客户端是**阻塞**的（curl 子进程）：现在跑在事件循环线程上，所以 CAS 慢会拖住整个进程；
  真上量要么换 libcurl 绑定、要么丢进 worker 线程（见上面「还没做」）。

## 许可证

整仓 **GPL-3.0**（`LICENSE`；前端 `packages/web/package.json` 是 `GPL-3.0-or-later`，与之一致）。
D 代码（`src/beangle`、`src/bashub`、`test`）全部采用同一套 **8 行短块**
  （7 行注释块 + 紧随其后的 1 个空行），署名 `Beangle`、年份取文件创建年；与 `micdn` 的短块写法一致
  （`micdn` 里另有 15 行完整块，两种都能用）。
