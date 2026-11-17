# Changelog

## v0.0.9 (unreleased)

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
- **监控**：延长 agent 日志读取超时，避免大日志或慢磁盘被误判为读取失败。
- **测试**：`dub test` 通过 35 个模块；新增 ZIP bundle、Micdn 路由、最长前缀回归测试，
  并在本机存在 `haproxy` 时用 `haproxy -c` 校验生成的完整配置。

## v0.0.8 (2026-11-07)

- **D 后端替换 JVM/Scala 后端**：新增 `target/d/bashub`，使用模块化 vibe 与 libpq，
  静态资源注册表生成查询计划，保留 PostgreSQL `bas.*` 表结构。
- **能力域 API**：统一到 `/api/bashub/{ems,config,micdn,monitor}`，补齐 JSON:API CRUD、
  CAS 会话、资源授权、CORS、安全响应头和 schema 检查。
- **管理台 SPA**：`packages/web` 提供项目、端点、代理、证书、组件、Micdn、平台特性和
  节点监控页面，并增加节点详情、实例内存、历史聚合与项目级筛选。
- **组件详情**：Micdn 组件目录增加详情页，展示组件基本信息和各 Project 的版本、
  context path 部署情况。
- **配置分发**：输出 `server.xml`、反代配置、证书、setline peers/manifest、Micdn 配置、
  EMS 菜单和主机脚本；证书按 endpoint 拆分，私钥不回显。
- **节点监控**：出站 WebSocket、中继、master 选举、日志读取、实例启停、健康采样和
  180 天运行历史。
- **发行**：deb/rpm 打包、systemd 服务、当前 PostgreSQL schema 与 AUR 包定义。
- **测试**：`dub test` 通过 33 个模块，`pnpm build:web` 通过类型检查和生产构建。

