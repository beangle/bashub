# Release 0.0.9

发布日期：待定

计划 tag：`v0.0.9`

本版本把代理下发收敛为 **ZIP bundle**，并让管理台可以直接下载同一份 bundle；
HAProxy/Nginx 配置、证书和 Micdn 路径一次生成，不再要求节点常驻 setline agent。
同时把 Project 的 Maven/NPM/Native 上游收敛到本地 micdn：server.xml 指向节点本地仓库，
micdn.xml 负责中心上游、SNAPSHOT/NPM dev 和 native 回源。

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
- 修复 HAProxy 生成配置缺少 `backend micdn`：map 已有 micdn 路由，但主配置未输出
  对应 backend；Nginx 的 micdn upstream 保持原逻辑。
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
- Micdn 组件目录和组件管理增加详情页，展示基本信息及各 Project 的版本、context path。
- Micdn 服务器登记字段从 `adminListen` 改为 `host`，代理端口统一取 `listen`；
  `host` 只接受节点地址，填写 `host:port` 会明确报错；服务器只登记一个节点 IP，
  不再要求名称。新增 `20261117-01-micdn-server-host-port.sql` 清理历史数据中的端口。

### Micdn 配置与运维

- Project 的 `micdn.xml` 增加默认清理策略：

  ```xml
  <prune at="03:30" npm-dev-keep="1" maven-snapshot-keep="1"/>
  ```

  定时器在 micdn 本地执行，bashub 只负责下发配置；不写 `<prune>` 时只保留手动入口。

- 中心 micdn 的读令牌复用 bashub.xml 的 `<snapshot download-token>`：同一个值同时写入客户
  `micdn.xml` 的 `<snapshot token>` 与 `<dev token>`，不进入数据库、管理台不展示/不可编辑。
  该上游必须指向中心 micdn 或补同值鉴权的反代，避免把令牌发给外部 registry。

- 新增人工 reload（Project 详情页 Micdn 卡片上的「Reload micdn」按钮）：

  ```text
  POST /api/bashub/micdn/projects/{id}/reload
  ```

  按 `config.servers[].host` 找在线 agent，下发 `micdn:reload`；agent 用 Project key 拉取
  `micdn.xml`，交给本机 root oneshot 校验、原子安装并 restart micdn。不依赖管理端口，因此
  micdn 停止时也能应用。不自动执行。

### 代理应用

- 新增 `proxy:apply` 原语和：

  ```text
  POST /api/bashub/config/projects/{id}/proxy/apply
  ```

  管理台只发 `{engine, endpoint}`；按 endpoint 的 `ips` 找在线 agent，返回逐节点结果。
  agent 用 Project token 下载 bundle，再触发本机受 polkit 限制的
  `basproxy-apply@<engine>.service`；root helper 校验路径后执行
  `basctl proxy apply --bundle`，保留校验、原子替换、reload 和回滚。

- Project 详情页代理卡片增加「应用到节点」按钮，带确认和失败节点提示；目标节点未全部在线时按钮禁用。
- Project 详情页 Micdn 卡片增加「Reload micdn」；登记节点未全部在线时禁用。
- Project 详情页 BAS 服务卡片增加「打开监控」，带当前 Project 跳到在线节点页。
- 在线节点页在 Project 标题下方增加紧凑摘要，展示 BAS 统计（0 停止时省略）、Micdn 节点 IP/组件状态、代理 IP/引擎版本/状态；Micdn 不再重复显示 `1/1 在线`；
  全部在线时提供 Reload micdn 和「应用到节点」，否则禁用。

- CentOS 7 使用 polkit 0.112 的 JavaScript 规则；不使用无法限定 unit 的宽泛 `.pkla`。

### Micdn 默认日志文件

Micdn 配置的日志文件默认值改为 `/var/log/micdn/micdn.log`，下发的 `micdn.xml` 显式写
`log-file="/var/log/micdn/micdn.log"`；需要走 journal 时仍可手工改为 `console`。

### Micdn 配置页合并

Maven / NPM / Native 合并到「基础」页的一个紧凑「仓库」区块：每行一个仓库，Maven 保留正式版
上游和只读 SNAPSHOT 上游，NPM 保留正式版/开发版上游，Native 保留启用开关和只读中心 `/native`
上游；输入区压缩为两行，单独的「Maven / NPM / Native」页签移除。

### 默认上游恢复

Maven/NPM 正式版上游 label 旁提供「恢复默认」按钮，分别填入 central + aliyun 和
npmmirror + npmjs；仍需保存后生效。

### Native 上游

启用 Native 时，下发的 `micdn.xml` 写入中心 `{origin}/native` 上游：

```xml
<native base="{micdn.home}/native">
  <remote url="https://bashub.example.com/native" token="中心下载token"/>
</native>
```

本地 micdn 缺失 native 文件时按完整路径回源并缓存；目录列表仍来自本地。Micdn 配置页的
Native 行显示只读中心 `/native` 上游。

### NPM 正式版默认上游

NPM 正式版 remotes 为空时默认写 `https://registry.npmmirror.com` 和
`https://registry.npmjs.org` 两个上游；配置了 remotes 则按配置下发。

### NPM 开发版上游

NPM 开发版上游与 Maven SNAPSHOT 一致：Micdn 配置页只读展示当前 origin 的 `/npm`，保存到
`npm.devRemote`；下发 `micdn.xml` 时直接使用该存储值，并继续带中心下载 token，不再允许自定义
开发版上游。

### Micdn 仓库目录

maven/npm/native/www/static 的 `base` 固定为 `{micdn.home}/maven`、`{micdn.home}/npm`、
`{micdn.home}/native`、`{micdn.home}/www`、`{micdn.home}/asset`，不再读取 Project 配置里的
`base`；配置字段、API 类型和本地目录输入框都已移除；旧配置里的 `base` 会在下一次保存时被归一化丢弃。
静态资源、www、blob 的目录配置仍保留。

### 本地 Micdn 仓库

- server.xml 不再写 Project 的公网远程仓库；`repository` / `snapshot-repo` / `native-repo`
  改为 Project 的本地 Micdn 地址：
  ```xml
  <repository remote="http://10.0.0.31:8888/maven" token="org.proj.a1b2c3"/>
  <snapshot-repo remote="http://10.0.0.31:8888/maven" token="org.proj.a1b2c3"/>
  <native-repo remote="http://10.0.0.31:8888/native" token="org.proj.a1b2c3"/>
  ```
  多个 Micdn 节点会把地址和同一个 token 按位置重复；没有 Micdn host 时三个元素都不生成。
- 下载 key 缺失时生成 `qualifiedName.<随机串>`，保存到 Project 的 Micdn `<auth download-key>`，
  同时下发到 `micdn.xml` 和 server.xml；Micdn 配置页的下载密钥旁提供「生成/重新生成」按钮，
  重新生成旧 key 会失效。
- 下发的 micdn.xml 在正式版 remotes 为空时默认 central + aliyun；Micdn 配置页把当前 origin 的
  `/maven` 保存到 `maven.snapshotRemote`，下发时直接使用存储值并带中心下载 token，不再在请求时
  猜测代理地址。
- Project 的 `remoteRepo` 字段、表单和数据库列移除。

### Server 开机自启

- 服务资源增加「开机自启」和「启动等待」；后者是 JSON 数组：

```json
[{"ref":"prod-farm.db"},{"url":"https://db.example/health","timeout":300},{"tcp":"db.example:5432","timeout":60}]
```

- 只有开启开机自启的 server 才在 server.xml 中生成 `<auto-start>`；
  `ref` 指向本机受管节点，`url`/`tcp` 是外部就绪条件。
- basagent 拉取到 server.xml 后调用 `basctl autostart`，逐个启动，不并发。

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
- 删除静态组件时同步清理所有 Project 的 Micdn 组件绑定，组件与绑定在同一事务内完成。
- 修复 reload 误判节点离线：现在按 Project 的 `qualifiedName` 查找 agent，与 `BAS_PRINCIPAL`
  和监控登记一致；offline 错误会带 `@host`。

## 升级

- 数据库无迁移。
- 本地 micdn 需要 **micdn 0.4.2** 及以上，才能使用 native `<remote>` 和 SNAPSHOT 上传自动 metadata；
  旧 micdn 会忽略这些新配置，native 缺失仍 404。
- `basctl proxy` 应升级到 0.0.3 及以上，使用 ZIP bundle；`proxy:apply` 还需要对应版本的
  basagent、`basproxy-apply@.service`、root helper 和 polkit 规则（安装包已带）。
- `micdn.xml` 的清理策略与共享 token 由 bashub 生成；修改 bashub.xml 后重启 bashub，
  再让 micdn reload 获取新配置。
- `GET /config/{project}/setline-manifest` 等旧机器端点为兼容保留，新客户端不再使用。
- 管理台需要重新构建 `packages/web`。

## 验证

```text
dub test: 35 modules passed（有 haproxy 时额外执行 haproxy -c）
vue-tsc --noEmit: 通过
pnpm build:web: 通过
```
