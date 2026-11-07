# Release 0.0.8

发布日期：2026-11-07

GitHub tag：`v0.0.8`

AUR：`bashub 0.0.8-1`

这是 bashub 从 JVM/Scala 后端迁移到 D 原生后端后的首个发行版。控制台后端、管理台
SPA、数据库脚本和 deb/rpm 打包进入同一个仓库，后端以单个原生可执行文件运行，管理台
按 `packages/web` 独立构建和部署。

## 版本范围

### D 后端

- JVM/Scala 后端退役，运行入口改为 `target/d/bashub`，使用 LDC 编译，采用模块化
  vibe（`vibe-http`、`vibe-inet`、`vibe-stream:tls`）。
- 资源定义改为静态注册表，查询计划直接生成 PostgreSQL SQL；JSON:API 文档、服务层、
  CRUD 路由和 CAS 会话客户端均有 D 实现，不再依赖 Hibernate、Spring 或 Freemarker。
- API 根前缀统一为 `/api/bashub`，按 `ems`、`config`、`micdn`、`monitor` 四个能力域
  分组；EMS 鉴权资源名按 `/{能力域}/{资源}` 收敛。
- 数据库连接从 EMS 应用文件的默认数据源读取，使用 libpq 直连；启动时检查 schema，
  `--check-schema` 可在不启动 HTTP 的情况下单独检查。
- 支持从命令行或应用文件覆盖监听地址；`--ems.home`、`--ems.profile` 与环境变量
  共同确定部署配置，命令行优先。

### 管理台

- `packages/web` 提供独立的 Vue SPA，覆盖项目、端点、代理、证书、组件、Micdn 配置、
  平台特性和监控等管理页面。
- 增加节点运行详情、实例内存、部署目标筛选、项目级资源范围和历史页面，节点卡片、
  实例状态与进程信息在管理台中合并展示。
- 前端按 pnpm workspace 构建，产物为 `packages/web/dist`；需要单独执行
  `pnpm build:web` 或 `pnpm --filter @beangle/bashub-web package`。

### 配置分发

- Project 输出 `server.xml`，并分发 haproxy/nginx 反代配置、证书、setline peers 与
  manifest、Micdn 配置、EMS 菜单和主机检查脚本。
- 代理与证书从 Project 中拆出，按 endpoint 持久化；私钥不通过 Project 列表或详情回显，
  `setline` 通过专用端点获取证书和私钥。
- setline manifest 同时返回 peers、proxy、certificate、certificate-key 的 SHA-256，
  机器客户端可只下载变化项。
- 组件最新版本支持后台周期刷新和 `artifacts/update-version` 主动刷新；Micdn 组件、
  平台特性和主机的集合字段支持 JSON 配置。
- 增加 native engine 类型和原生构件执行路径，继续与 basctl 的 `<bas>` 配置格式对齐。

### 节点与监控

- basagent 通过出站 WebSocket 连接 hub，上报主机状态、实例状态、日志窗口和健康采样；
  支持立即上报、日志读取、实例启停与断线重连。
- 支持中继节点、同组 master 自动选举与多 master 拓扑；移动 master 后优先心跳和负载
  信息更完整的节点。
- 运行历史按 Project 和 agent 分开保存，支持按天聚合、可用率和单 server 视图；历史
  数据保留 180 天。
- 节点控制接口要求登录并通过 EMS 资源授权；SPA 会话可使用 Bearer token，浏览器导航
  仍可走 CAS 登录和 302 重定向。

### 打包与数据库

- `scripts/build_rpm.sh` 与 `scripts/build_deb.sh` 生成同一布局的安装包：`/usr/bin/bashub`、
  `/usr/lib/systemd/system/bashub.service`、`/var/lib/bas/.ems` 与
  `/var/log/bas/bashub`；服务以 `bas:beangle` 运行，并与 basctl 共用账号。
- AUR 包 `bashub` 使用同一安装布局，源码直接取自本标签；Arch 构建依赖 `ldc`、`dub`，
  运行时依赖 `postgresql-libs`、`curl`、`zlib` 和 `gcc-libs`。Arch 的 LDC 默认静态
  链接 D 运行时，因此安装包不依赖 `liblphobos`。
- PostgreSQL 当前结构位于 `db/postgresql/db.xml` 与 `db/postgresql/init/*.sql`；全新库按
  文件名顺序执行初始化脚本，旧库先备份再按现有迁移脚本和 `--check-schema` 核对。

## 测试

- `dub test --compiler=ldc2`：33 个模块通过。
- `pnpm build:web`：Vue 类型检查与生产构建通过。
- release 构建产物为 `target/d/bashub`；本机动态链接检查确认使用 libpq、D 运行时、
  zlib、gcc 运行时和 libc。

## 环境要求

- Linux x86_64；源码构建需要 `ldc2 >= 1.32`、`dub >= 1.34`。
- 运行时需要 PostgreSQL（含 `libpq`）、`curl`、D 运行时库；systemd 服务还需要
  可用的 `/var/lib/bas/.ems/<profile>` 配置。
- 前端单独构建需要 Node.js 20+ 与 pnpm 11+。
- hub 的数据库、CAS、EMS 地址与会话 cookie 均从 EMS profile 推导；没有 EMS profile
  时后端拒绝启动。

## 已知限制

- 安装包只包含 D 后端和 systemd unit；前端 SPA 需要按 `packages/web` 的发布流程单独
  构建和部署，并把 `/api/` 反代到 bashub。
- CAS 会话只保存在进程内存，重启即失效，多实例之间不共享；没有对未知会话做负缓存。
- 配置在启动时读取，没有 SIGHUP 热加载；修改监听、数据库或日志配置后需要重启。
- 选中的 Project 参与安全上下文，但尚未用于列表和数据范围过滤。
- 当前没有内建迁移执行器；旧库升级需要先备份，再按数据库目录中的脚本和 schema 检查
  结果处理。

## 安装

```bash
# Arch Linux（AUR）
yay -S bashub

# 源码构建
dub build --build=release-nobounds --compiler=ldc2
install -Dm755 target/d/bashub /usr/bin/bashub
install -Dm644 scripts/package/bashub.service /usr/lib/systemd/system/bashub.service
systemctl daemon-reload

# 准备好 /var/lib/bas/.ems/bas 后启动
systemctl enable --now bashub
```
