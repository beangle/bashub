# Changelog

## v0.0.9 (unreleased)

- **项目上下文移到抽屉标题**：主机、群集和应用部署的编辑/新建抽屉不再显示不可修改的「配置」下拉，当前 Project 直接显示在抽屉标题旁，表单栅格可用空间更大。
- **无上下文的后台任务**：`cfg_webapps.context_path` 改为可空；没有上下文的部署不参与 HAProxy/Nginx 路由生成。新增迁移 `20261124-01-webapp-context-nullable.sql`。
- **应用部署表单**：新建/修改时「运行在」必填；「代理点」和上下文路径可选（后台任务可以没有上下文）；对外路径可留空（按上下文回退）。字段布局调整为「运行在 + 解压执行」「上下文 + 代理点」「对外路径」「扩展库」；对外路径减少行数。
- **群集内嵌服务管理**：群集编辑抽屉直接展示该群集的服务表，可新增/编辑/删除，不再先跳到独立服务页；独立服务列表保留为高级查询入口。
- **平台功能删除**：平台功能详情页增加删除入口，删除前先清理该功能的平台脚本，避免外键冲突。
- **服务表单收紧**：主机下拉限制为当前 Project；移除服务「代理端口」，代理统一使用服务 HTTP 端口；堆上限默认 0 且可留空。
- **代理点证书编辑入口**：代理点表单移除只能填公钥的 `certificate` 字段，统一到 Project 详情「证书」页的公钥/私钥编辑器维护。
- **逐节点操作错误**：代理应用和 Micdn reload 失败时不再只显示节点 IP，而是弹出每台节点的 `error` 与 Agent/helper 返回的 `detail`，可直接看到缺少 haproxy、helper 失败等具体原因。
- **主机硬件现状**：Host 的详细系统版本、CPU 型号和体系结构折叠到只读 `hardware` JSON；
  表单只保留名称、IP、Project、组网分组、操作系统、内存、CPU 核心数和系统特性。新增
  `POST /api/bashub/config/hosts/{id}/adopt-agent`，从在线 Agent 回填 hardware，且只回填空的
  memory/cores，不覆盖人工配置。
- **Micdn 清理策略**：生成 `<prune at="03:30" npm-dev-keep="1" maven-snapshot-keep="1"/>`，
  由各 micdn 按本地时区执行；不再由 bashub 起定时器。
- **共享上游令牌**：`<snapshot download-token>` 同时下发为客户 micdn 的 `<snapshot token>` 和
  `<dev token>`，用于代理中心 micdn 的 SNAPSHOT/dev 下载；不落库、界面不展示。
- **人工 reload**：新增 `micdn:reload` 原语、`POST /api/bashub/micdn/projects/{id}/reload`
  和 Project 详情页 Micdn 卡片按钮；agent 下载 `micdn.xml` 后交给本机 root oneshot 安装并
  restart，不再 POST `/admin/config`。
- **代理应用**：新增 `proxy:apply` 原语、`POST .../proxy/apply` 和 Project 代理页
  「应用到节点」，按 endpoint `ips` 逐节点触发。
- **不再生成 `<micdn remote>`**：该属性已从 micdn 配置中移除。
- **代理 ZIP bundle**：新增 `GET /api/bashub/config/{project}/proxy-bundle?engine=haproxy|nginx`，
  支持 `cert-dir` 按部署目录生成证书路径；HAProxy bundle 额外包含
  `config/bas-routes.map`，使用 `map_beg` 做最长前缀路由；map 条目按路径字典倒排，
  方便人工检查。
  一次返回 `manifest.json`、`config/haproxy.cfg` 或 `config/nginx.conf`、证书和私钥；
  manifest 记录每个文件的 role、相对路径和 SHA-256。
- **不再生成代理状态页**：HAProxy 删除 `stats socket`、`/status` 和硬编码
  `stats auth`；Nginx 删除 `stub_status` location。状态采集不再由代理配置默认暴露。
- **HAProxy 兼容性**：移除 `ssl-default-bind-ciphers PROFILE=SYSTEM` 等 OpenSSL
  3-only 默认值，并把 map 的 `http-request` 放到 `redirect` 之前，兼容 HAProxy 3.4.1。
- **Micdn 后端**：HAProxy 配置现在会输出 map 中引用的 `backend micdn`，此前只有路由
  条目而没有 backend，reload 后会因未知 backend 失败。
- **完整代理配置**：HAProxy 配置直接内联 backend 和 `use_backend` 规则，不再依赖
  `/var/lib/setline/haproxy` 的 map/片段；Nginx 配置包含完整 upstream 和 location。
- **HAProxy 语法修复**：`bind ... ciphers/protocols` 保留空格，`server` 行补上名字，
  避免 `bundle.pemciphers` 和 `server expects <name>` 错误。
- **HAProxy 兼容默认值**：恢复 `/var/run/haproxy.pid`、HTTPS 下才设置
  `X-Forwarded-Port`、backend 默认 `balance roundrobin`、server 默认 `check`；
  Micdn 固定路径补回 `/blob`、`/static`；`/std/spa` 改由 webapp/www 配置推导。
- **Micdn 路由**：Project 登记 Micdn 服务器后，所有 endpoint 的 bundle 都固定追加
  `/asset`、`/www`、`/maven`、`/npm`、`/native` 等路径，后端端口取 Micdn 的 `listen`。
- **Micdn www 挂载路径**：www 文档的 `mountName`（如 `m/edu/learning`）
  也会作为 micdn 代理路径下发，不再只依赖 webapp 的 `urls`。
- **Micdn 节点字段**：`servers[].adminListen` 改为语义明确的 `servers[].host`；
  代理端口统一取 `micdn.listen`，并提供迁移脚本。`host` 只接受节点地址，填写
  `host:port` 会被拒绝，避免生成 `[host:port]:listen`。SPA 将节点收缩为基础页的
  单个 IP 输入并移除名称；新增 `20261117-01-micdn-server-host-port.sql` 清理历史端口。
- **最长前缀优先**：所有代理路由按路径长度从长到短生成，确保 `/api/edu/exam`
  优先于 `/api/edu`，避免考务请求被泛教学路由截获。
- **管理台下载**：Project 详情页增加代理 ZIP 下载，使用登录会话，不需要 Project key；
  `cert-dir` 让机器 bundle 的证书路径与 basctl 的部署目录一致。
- **私钥状态修复**：`private_key` 不再依赖通用资源查询的列清单，保存私钥后立即返回
  `keySet=true`，重新打开证书页也不会显示“未设置”。
- **证书到期**：保存证书时解析 X.509 `notAfter` 并返回 `certificateNotAfter`；解析失败可在
  证书编辑框手工填写。管理台证书页显示到期时间；Endpoint 列表日常不显示日期，只在
  到期前 30 天于入口列显示 `⚠ 到期日期`。
- **组件目录**：管理台将静态包与文档拆成两个目录，分别搜索和新建，并增加序号、
  自动部署说明。
- **本地 Micdn 仓库**：server.xml 的 `repository` / `snapshot-repo` / `native-repo` 改指 Project
  的本地 micdn（`servers[].host` + `listen`），没有 host 时三个元素都不生成；不再使用 Project 的
  `remoteRepo`。下载 key 缺失时自动生成 `qualifiedName.<随机串>`，同一 Project 的所有 micdn
  节点共用并写入 server.xml/micdn.xml；Micdn 配置页提供「生成/重新生成」下载密钥按钮。
- **区块标题行合并**：Project 详情的「概览」说明、各详情卡片的标题与说明，以及 Micdn 配置/组件目录/绑定编辑器的标题与说明合并到同一行。
- **静态组件详情**：部署表增加 Project Logo，表格样式与构件详情统一，静态组件不显示版本列。
- **标题行合并**：各列表/详情页的标题与灰色说明合并到同一行，返回链接和右侧操作保持同一标题行，减少纵向占用。
- **详情页事实行压缩**：组件、构件、Project 详情的事实项改为“标题在左、内容在右”的横向排列，减少三列卡片的垂直占用。
- **组件版本列**：组件目录列表增加实际版本列；组件详情部署表改用紧凑常规表格并显示真实 jar/npm 版本。
- **仓库固定启用**：Maven、NPM、Native 默认全部启用，移除“是否启用”开关；旧 `declared` 字段在保存时归一化丢弃。
- **Blob 配置移到基础页**：Blob 存储卡片并入「基础」页，移除独立 Blob 页签；不可改的 bucket 身份/目录/公开读取规则写在卡片标题中，只保留上传大小上限。
- **仓库鉴权操作位置**：下载密钥的「生成/重新生成」按钮移到输入框下方。
- **Blob 公开读取固定**：图片同站匿名读取始终开启，移除配置页的开关和说明文案；旧 `publicImages` 字段在下一次保存时归一化丢弃。
- **Blob 身份与目录固定**：Micdn 的 `<bucket name>` 改用 Project 的 `qualifiedName`，不再用显示名；
  Blob 本地目录固定为 `~/blob`，移除配置页的目录输入；旧 `blob.base` 在下一次保存时归一化丢弃。
- **Micdn home 固定**：`micdn.xml` 根属性 `home` 固定为 `~`，maven/npm/native/static/www 的 base 固定为 `~/...`；移除配置页 Home 输入，旧 `home` 在下一次保存时归一化丢弃。
- **Micdn 日志固定**：`micdn.xml` 始终写 `log-file="/var/log/micdn/micdn.log"`，日志级别固定 `info`；移除配置页的日志文件、console 和日志级别选项。
- **Micdn 基础页合并**：Maven / NPM / Native 合并为基础页里的一个紧凑「仓库」区块，
  移除独立页签；Native 保留启用开关和只读中心上游，上游输入区压缩为两行。
- **NPM 开发版上游固定**：Micdn 配置页把当前 origin 的 `/npm` 保存到 `npm.devRemote`，与
  Maven SNAPSHOT 一样只读展示，渲染直接使用存储值；不再自定义开发版上游。
- **Micdn 仓库目录固定**：maven/npm/native 的 `base` 不再可配置，始终使用
  `{micdn.home}/maven`、`/npm`、`/native`；`www`/`static` 也固定为 `{micdn.home}/www`、
  `{micdn.home}/asset`。五个本地目录字段和输入框都已移除，旧配置里的 `base` 在下一次保存时被
  归一化丢弃。
- **默认上游恢复**：Maven/NPM 正式版上游 label 旁提供「恢复默认」，填入 central+aliyun /
  npmmirror+npmjs。
- **Native 上游展示**：Micdn 配置页 Native 行显示只读中心 `/native` 上游，提示本地缺失时回源。
- **Native 上游**：下发的 micdn.xml 在启用 native 时写中心 `{origin}/native` 上游和下载 token，
  本地 micdn 缺失 native 文件时按路径回源；目录列表仍来自本地。
- **NPM 默认上游**：正式版 remotes 为空时默认 `registry.npmmirror.com` + `registry.npmjs.org`，
  与 Maven 的 central + aliyun 对称。
- **Micdn 默认上游**：bashub 下发的 micdn.xml 在正式版 remotes 为空时写 central + aliyun，
  SNAPSHOT 由 Micdn 配置页按当前 origin 保存为 `maven.snapshotRemote`，下发时直接使用存储值。
- **Server 开机自启**：`cfg_servers` 增加 `auto_start`、`wait_for`；server.xml 输出
  `<auto-start>` / `<wait-for>`，管理台服务表单可配置，供 basagent 自动启动本机节点。
- **监控**：延长 agent 日志读取超时，避免大日志或慢磁盘被误判为读取失败。
- **详情页标题行统一**：返回链接移到标题/Project 名称之后，操作按钮保持在标题行最右侧；去掉单独占一行的返回链接，并清理组件/构件详情页重复的返回按钮。
- **BAS 服务表**：Project 详情页的「节点与服务」由分组卡片改为表格，按节点、群集、服务、端口、堆和状态展示；运行中的服务排在前面，已停止的排在后面。
- **监控代理服务状态**：agent 在 `report:health` 上报 `proxyState.haproxy/nginx`；监控摘要按实际服务状态显示「在线 / 已停止 / 节点离线」，不再用 agent 在线代替 haproxy/nginx 运行状态。
- **监控 Micdn 服务状态**：agent 在 `report:os` / `report:health` 上报 `micdn.active`；
  监控摘要和 Project 详情按实际服务状态显示「在线 / 已停止 / 节点离线」，不再把 agent 在线当作
  micdn 在线。
- **监控 Micdn 摘要**：去掉 Micdn 的 `1/1 在线` 重复提示，仅保留状态标签。
- **监控摘要**：Project 标题行保留刷新上报/运行历史/配置，标题下方合一展示 BAS 统计、Micdn
  节点 IP/组件/在线状态与 Reload、代理 IP/引擎版本/状态与 Apply；目标节点未全部在线时禁用操作。
- **代理版本**：节点 `report:os` 上报 `haproxy -v` / `nginx -v`，监控摘要显示对应引擎版本。
- **删除组件清理绑定**：删除 `cdn-components` 时在同一事务里从所有 Project 的
  `project-micdn.components` 中移除该组件，不再留下悬空绑定。
- **修复 reload 误判节点离线**：reload 现在按 Project 的 `qualifiedName` 查找 agent
  （与 `BAS_PRINCIPAL` 和监控登记一致），不再误用显示名称；offline 错误会带上 `@host`。
- **测试**：`dub test` 通过 35 个模块；新增 ZIP bundle、Micdn 路由、最长前缀回归测试，
  并在本机存在 `haproxy` 时用 `haproxy -c` 校验生成的完整配置。

## v0.0.8 (2026-11-07)

- **D 后端替换 JVM/Scala 后端**：新增 `target/d/bashub`，使用模块化 vibe 与 libpq，
  静态资源注册表生成查询计划，保留 PostgreSQL `bas.*` 表结构。
- **能力域 API**：统一到 `/api/bashub/{ems,config,micdn,monitor}`，补齐 JSON:API CRUD、
  CAS 会话、资源授权、CORS、安全响应头和 schema 检查。
- **管理台 SPA**：`packages/web` 提供项目、端点、代理、证书、组件、Micdn、平台特性和
  节点监控页面，并增加节点详情、实例内存、历史聚合与项目级筛选。
- **组件详情**：Micdn 组件目录和组件管理增加详情页，展示基本信息及各 Project 的版本、
  context path 部署情况。
- **配置分发**：输出 `server.xml`、反代配置、证书、setline peers/manifest、Micdn 配置、
  EMS 菜单和主机脚本；证书按 endpoint 拆分，私钥不回显。
- **节点监控**：出站 WebSocket、中继、master 选举、日志读取、实例启停、健康采样和
  180 天运行历史。
- **发行**：deb/rpm 打包、systemd 服务、当前 PostgreSQL schema 与 AUR 包定义。
- **测试**：`dub test` 通过 33 个模块，`pnpm build:web` 通过类型检查和生产构建。

