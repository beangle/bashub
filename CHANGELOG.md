# Changelog

## v0.0.8 (2026-11-07)

- **D 后端替换 JVM/Scala 后端**：新增 `target/d/bashub`，使用模块化 vibe 与 libpq，
  静态资源注册表生成查询计划，保留 PostgreSQL `bas.*` 表结构。
- **能力域 API**：统一到 `/api/bashub/{ems,config,micdn,monitor}`，补齐 JSON:API CRUD、
  CAS 会话、资源授权、CORS、安全响应头和 schema 检查。
- **管理台 SPA**：`packages/web` 提供项目、端点、代理、证书、组件、Micdn、平台特性和
  节点监控页面，并增加节点详情、实例内存、历史聚合与项目级筛选。
- **配置分发**：输出 `server.xml`、反代配置、证书、setline peers/manifest、Micdn 配置、
  EMS 菜单和主机脚本；证书按 endpoint 拆分，私钥不回显。
- **节点监控**：出站 WebSocket、中继、master 选举、日志读取、实例启停、健康采样和
  180 天运行历史。
- **发行**：deb/rpm 打包、systemd 服务、当前 PostgreSQL schema 与 AUR 包定义。
- **测试**：`dub test` 通过 33 个模块，`pnpm build:web` 通过类型检查和生产构建。

