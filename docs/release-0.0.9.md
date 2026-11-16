# Release 0.0.9

发布日期：待定

计划 tag：`v0.0.9`

本版本把代理下发收敛为 **ZIP bundle**，并让管理台可以直接下载同一份 bundle；
HAProxy/Nginx 配置、证书和 Micdn 路径一次生成，不再要求节点常驻 setline agent。

## 版本范围

### 代理 bundle

- 新增机器下载接口：

  ```text
  GET /api/bashub/config/{project}/proxy-bundle?engine=haproxy|nginx
  ```

  使用 Project token，返回 `application/zip`。

- 新增管理台下载接口：

  ```text
  GET /api/bashub/config/projects/{id}/proxy-bundle?engine=haproxy|nginx
  ```

  只使用登录会话，不需要 Project key。

- ZIP 内容：

  ```text
  manifest.json
  config/haproxy.cfg   或 config/nginx.conf
  config/bas-routes.map   # 仅 HAProxy
  certificate/cert.pem
  certificate/key.pem
  ```

  manifest 记录每个文件的 role、相对路径和 SHA-256。

- 机器接口支持 `cert-dir`，让配置里的证书路径与 basctl 实际安装目录一致；
  管理台下载使用代理默认目录。

### 代理配置

- HAProxy 主配置内联 backend 和 `use_backend`，不再依赖 setline map/fragment。
- HAProxy 路由使用 `map_beg`；map 条目按路径字典倒排，仅用于人工检查，匹配仍由
  HAProxy 选择最长前缀。
- 不再生成 HAProxy stats socket / `/status` 页面，也不再生成 Nginx `stub_status`；
  避免默认暴露状态和硬编码凭据。
- 移除 HAProxy `ssl-default-bind-ciphers PROFILE=SYSTEM` 等 OpenSSL 3-only 默认值，
  并把 `http-request` 放到 `redirect` 前，兼容 HAProxy 3.4.1。
- 修复 `bind` 的证书/密码套件空格和 `server` 缺少名字导致的 HAProxy 配置错误。
- 恢复 HAProxy 旧配置的 `/var/run/haproxy.pid`、HTTPS 条件
  `X-Forwarded-Port`、默认 `balance roundrobin` / `check`，并补回 Micdn 的
  `/blob`、`/static` 路径；`/std/spa` 由 webapp/www 配置推导。
- Nginx 主配置内联 upstream 和 location。
- 所有路由按最长前缀优先生成：

  ```text
  /api/edu/exam -> 考务
  /api/edu      -> 其他教学
  ```

- Project 登记 Micdn 服务器时，所有 endpoint 都追加 `/asset`、`/www`、`/maven`、
  `/npm`、`/native` 等路径，后端端口取 Micdn 的 `listen`。
- www 文档的 `mountName`（如 `m/edu/learning`）也会生成 micdn 路径。
- Micdn 服务器登记字段从 `adminListen` 改为 `host`，代理端口统一取 `listen`。

### 管理台

- Project 详情页增加“下载 ZIP”，使用登录会话。
- 静态包与文档拆成两个组件目录，分别搜索、新建和显示序号。
- 清理 setline-agent、Project key 下载等旧文案。

### 修复

- 修复保存代理私钥后仍显示“私钥未设置”的问题：`private_key` 从非资源列单独读取，
  不再受通用 JSON:API 列清单限制。
- 保存证书时解析 X.509 `notAfter`，证书页显示到期时间；Endpoint 列表日常不显示日期，
  只在到期前 30 天于入口列显示 `⚠ 到期日期`。无法解析时支持手工填写。新增
  `cfg_endpoints.certificate_not_after` 迁移。
- 延长 agent 日志读取超时，避免大日志或慢磁盘被误判为读取失败。

## 升级

- 数据库无迁移。
- `basctl proxy` 应升级到 0.0.3 及以上，使用 ZIP bundle。
- `GET /config/{project}/setline-manifest` 等旧机器端点为兼容保留，新客户端不再使用。
- 管理台需要重新构建 `packages/web`。

## 验证

```text
dub test: 35 modules passed（有 haproxy 时额外执行 haproxy -c）
vue-tsc --noEmit: 通过
pnpm build:web: 通过
```
