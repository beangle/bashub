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
- 详情页统一为“标题 + 返回链接 + 右侧操作按钮”的单行标题结构，返回链接不再单独占用一行；组件/构件详情页移除重复返回按钮。
- Project 详情页「节点与服务」改为表格，运行中在上、已停止在下；列包含节点、群集、服务、HTTP 端口、堆和状态。
- 在线节点页在 Project 标题下方增加紧凑摘要，展示 BAS 统计（0 停止时省略）、Micdn 节点 IP/组件状态、代理 IP/引擎版本/状态；代理状态来自 agent 上报的 `proxyState`，服务停止时显示「已停止」；Micdn 不再重复显示 `1/1 在线`；Micdn 状态来自 agent 上报的 `micdn.active`，服务停止时显示「已停止」；
  全部在线时提供 Reload micdn 和「应用到节点」，否则禁用。

- CentOS 7 使用 polkit 0.112 的 JavaScript 规则；不使用无法限定 unit 的宽泛 `.pkla`。

### Blob 身份与目录

Micdn `<bucket name>` 使用 Project 的 `qualifiedName`（例如 `openurp.prod`），不再使用显示名称；
Blob 本地目录固定为 `~/blob`，配置页不再提供目录输入；图片同站匿名读取固定开启，配置页不再提供开关。
旧配置里的 `blob.base` / `publicImages` 会在下一次保存时
被归一化丢弃。

### 区块标题行合并

Project 详情的「概览」、各详情卡片的标题与说明，以及 Micdn 配置/组件目录/绑定编辑器的标题与说明合并到同一行，减少纵向占用。

### 平台功能删除

平台功能详情页提供删除入口；删除功能时先删除其平台脚本，再删除功能本身。

### 项目上下文标题

主机、群集和应用部署的编辑/新建抽屉不再把不可更改的「配置」放在表单里，当前 Project 显示在抽屉标题旁，释放表单栅格空间。

### 上下文与代理点绑定

应用部署填写上下文后必须选择代理点；选择代理点后必须填写上下文。列表不再显示代理点、解压执行两列。

### 外部路由

Project 代理详情增加外部路由入口，页面为独立路由 `/config/projects/{id}/external-routes`，不占菜单。每条路由配置 `path -> host:port`，可启用/停用；启用的路由进入 HAProxy map 和 Nginx location。

### HAProxy 路由 map 预览

Project 详情的代理页在 HAProxy 类型下增加 `bas-routes.map` 只读预览和复制。后端新增管理台接口 `GET /api/bashub/config/projects/{id}/proxy-map`。

### 应用部署临时下线

`cfg_webapps.enabled` 默认 true，界面名「启用」。关闭后保留配置和端口，但不生成 server.xml、不生成代理路由，也不参与告警和统计。迁移文件：`db/postgresql/migrate/20261124-02-webapp-enabled.sql`。

### 无上下文的后台任务

`cfg_webapps.context_path` 改为可空；没有上下文的部署视为后台任务，不生成任何代理路由。迁移文件：`db/postgresql/migrate/20261124-01-webapp-context-nullable.sql`。

### 代理配置应用状态

`cfg_endpoints.proxy_applied` 记录每个代理 IP 最近一次成功应用的 bundle hash（`proxy/apply` 成功后写入，
jsonb：`ip -> {hash, at}`）。`GET /config/projects/{id}/proxy-state` 用当前生成的 manifest hash 对比，
返回 `applied` / `pending` / `unknown`；首次升级后没有记录显示未知，应用一次后才有基准。判断不访问客户机，
只在 hub 侧计算；手工在 hub 外应用或直接改客户机文件不会被发现，此时需要重新应用一次。
迁移文件：`db/postgresql/migrate/20261128-01-endpoint-proxy-applied.sql`。

### 部署配置对账

`/monitor/agents/status` 给每个运行实例补 `deployment`：hub 配置、agent 已下发的 `server.xml`（`declared`）与
实际运行实例（`instances`）三方对账。新增/移入目标显示待加载，删除/移出目标显示待删除，版本、组件、上下文、
`urls` 或端口变化显示待重启，配置还没到节点显示未下发。实例页与节点/项目概览只展示提示，不自动重启；
判定粒度是 server，离线节点只能标未知。`libs`/`unpack` 等 agent 未上报的字段目前看不出来。

### 部署组件限定

新建部署或更换组件时，只能选当前项目自己的组件或通用组件（`artifact.project` 为空）；PC 表单与手机端
换组件候选都按此过滤，后端在写入时校验，跨项目引用返回 400。已经部署、且本次没有更换组件的历史数据
不受影响，仍可修改版本、上下文与运行目标。手机端部署项目页同时提供「新增」入口，走同一套候选过滤与后端校验；项目页不再提供批量「全部升级」，版本在详情逐个调整；详情页可「卸载部署」，
删除配置并解除运行目标/代理点关联（已运行实例不会自动停止）。

### 组件版本缓存与刷新

- `cfg_artifacts` 新增 `versions`(jsonb)：Maven metadata 的 `<versions>` 列表由周期刷新与
  「刷新最新版本」写入；`GET /config/artifacts/{id}/versions` 改为只读缓存，手机端打开部署详情、
  切换组件不再实时访问 Maven Central。迁移文件：`db/postgresql/migrate/20261127-02-artifact-versions-cache.sql`。
- 周期刷新不再阻塞事件循环：改为独立 `curl` 子进程（一次一个，单个连接 5 秒 / 总 30 秒超时）+ 定时轮询回收，
  事件循环只做写库。新增应用配置 `artifact-refresh-minutes`（0 关闭，缺省 360，上限 7 天）。
- 刷新入口收敛：组件列表页不再提供批量「刷新最新版本」，改为组件详情页的单组件刷新；批量刷新只由周期任务执行。

### 资源编辑页与详情页

资源列表的「新建」「编辑」改为独立全页表单，不再使用抽屉；普通配置资源的详情从列表数据锚点直接打开抽屉；跨实体、长关系的复杂详情仍使用独立详情页。列表分页、排序、筛选写入 URL，表单带 `returnTo`，保存/取消/后退回到原位置。抽屉只保留给只读详情和简易查看。

### 应用部署表单

新建/修改应用部署时「运行在」必填；「代理点」和上下文路径可选，后台任务可以没有上下文；对外路径可留空并回退到上下文。表单按「运行在 + 解压执行」「上下文 + 代理点」「对外路径」「扩展库」排列，对外路径压缩为两行。

### 群集内嵌服务管理

群集编辑页内直接展示服务表，可在当前上下文新增、编辑、删除服务。

### 服务表单

服务编辑抽屉的主机下拉限制为当前 Project；移除「代理端口」，代理统一转发服务的 HTTP 端口；堆上限默认 0、可留空。

### 代理点证书编辑入口

代理点表单不再直接编辑 `certificate` 字段；证书与私钥统一在 Project 详情「证书」页编辑，避免只能填公钥造成不一致。

### 逐节点操作错误

代理应用和 Micdn reload 失败时，界面弹出每个节点的错误信息及 Agent/helper 返回的 `detail`，不再只显示“应用失败”和节点 IP。

### 主机硬件现状

Host 的详细系统版本、CPU 型号和体系结构不再单独占字段，统一存入 `hardware` JSON；表单只保留名称、IP、Project、组网分组、操作系统、内存、CPU 核心数与系统特性。主机详情可「从 Agent 更新」，只回填空的 memory/cores，不覆盖人工配置。

### 静态组件详情

静态组件详情页的部署表增加 Project Logo，表格样式与构件详情统一；静态组件不显示版本列。

### 标题行合并

各列表/详情页把标题和灰色说明合并到同一行；返回链接与操作按钮仍在标题行内，减少页面纵向占用。

### 详情页与组件列表

组件、构件、Project 详情的事实项改为左侧标题、右侧内容；组件目录增加实际版本列，组件详情的部署表改用紧凑常规表格，jar/npm 版本取真实坐标而不是整段 ref。

### 仓库固定启用

Maven、NPM、Native 固定启用，配置页不再提供“是否启用”开关；旧 `declared` 字段会在下一次保存时被归一化丢弃。

### Micdn 配置页布局

Blob 存储并入「基础」页，不再单独占一个页签；不可修改的默认值（home、日志、bucket 身份、Blob 目录、公开读取）写在各自标题行中。仓库鉴权的「生成/重新生成」按钮移到下载密钥输入框下方。

### Micdn home 固定

Micdn 的 `home` 固定为 `~`，maven/npm/native/static/www 的 base 固定为 `~/...`；配置页不再提供 Home 输入，旧 `home` 会在下一次保存时被归一化丢弃。

### Micdn 日志文件

Micdn 的日志文件固定为 `/var/log/micdn/micdn.log`，日志级别固定为 `info`，下发的 `micdn.xml`
始终写 `log-file="/var/log/micdn/micdn.log"`；配置页不再提供日志文件、console 或日志级别选项。

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

- 数据库有迁移：按 `db/postgresql/migrate/` 的文件顺序执行；本版本新增 `20261124-01`、`20261124-02`、
  `20261125-01`、`20261127-01`、`20261127-02`、`20261128-01`（组件版本缓存、打包类型去 `bin`、代理应用状态等）。
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
