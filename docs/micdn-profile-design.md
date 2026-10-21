# Micdn 配置：以 Profile 为中心的重构设计

## 1. 现状与问题

当前 bashub 只建模了 micdn 的旧 `static` 资产清单：

- `asset-groups` 通过关联表挂到 `profiles`；
- `assets` 只有 `name`、`base` 和 `bundleUris`；
- `bundleUris` 只能表达 `jar` / `dir`，不能表达 static 的 `npm` provider；
- 当时只有旧的资产清单接口，输出 `<asset><contexts>...`，并没有完整的 `micdn.xml` 入口。

因此 `www`、`blob`、`maven`、`npm`、`native`、`auth` 和根配置都没有入口，也无法在页面上看到一个
Profile 最终会下发给 micdn 的完整内容。

不要在 `assets` 上继续追加字段。`assets` 的 `base` 是旧的 URL context 语义，与 micdn 新配置的
`<static base="..."><bundle name="...">` 不是同一层概念，继续叠加会把两种模型混在一起。

## 2. 目标

一个 Profile 就是一个 micdn 部署配置的聚合根：

1. 能配置 micdn 当前支持的全部元素；
2. 能预览、复制、下载最终 `micdn.xml`；
3. 可复用的资源组件不和 Profile 绑定死；
4. 同一个组件可以被多个 Profile 引用；挂载名属于组件目录，Profile 只设置引用顺序；
5. 不保存重复的 XML 文本，XML 由结构化数据确定性渲染；
6. 旧模型不兼容；`/micdn/asset` 与 `cdn_asset_*` 一并移除。

## 3. 三层模型

### 3.1 Provider

描述“内容从哪里来”，不包含 Profile：

| kind | 字段 | 生成的 micdn XML |
|---|---|---|
| `jar` | `ref`=GAV，`inner`=可选资源目录 | `<jar gav="..." dir="..."/>` |
| `npm` | `ref`=包规格，`inner`=包内目录 | `<npm package="..." dir="..."/>` |
| `dir` | `ref`=绝对路径 | `<dir location="..."/>` |
| `zip` | `ref`=zip 路径，`inner`=zip 内目录 | `<doc zip="..." inner="..."/>` |

static 的 provider 是 `jar` / `npm` / `dir`，www doc 的 provider 是 `npm` / `zip`。

### 3.2 Component

描述“可复用的内容组件”，包含稳定的部署挂载名，但不含 Profile 级顺序、上游仓库等信息：

- **Static Bundle**：目录名称 + bundle 挂载名 + 一组 provider；
- **WWW Doc**：目录名称 + doc 挂载路径 + 一个 provider + `try-file` / `auto-deploy` / `auto-gzip`。

组件是目录项，可以被任意 Profile 引用。

术语上，`bundle` 是 micdn `<static>` 下的部署单元，决定 URL 前缀 `/static/{mountName}/`；
`static source`（也可以叫 provider）是 bundle 内部的内容来源，对应 `<jar>` / `<npm>` / `<dir>`。
一个 bundle 可以有多个 source，例如同一个 `jquery-ui` bundle 同时放两个版本的 jar。不要把一个 source
当成一个独立 bundle，否则 URL 层级会变。

Blob 不是可复用组件。一个 Profile 最多有一个 bucket，bucket 的 `name` 固定取 `profile.name`，
`key` 固定取 `profile.key`，页面不提供单独编辑入口。Profile key 非空时自动输出 Blob；没有 key
时不输出。`publicImages`、`base`、`max-size` 属于 Profile 的 Blob 段设置。

组件目录中的 `name` 是管理台显示和检索用的标识；`mount_name` 是最终部署路径。两者允许不同，例如
`openurp-theme` 可以挂载为 `openurp`。修改 `mount_name` 会影响所有引用该组件的 Profile，这是组件的
部署语义，不是某个 Profile 的局部设置。

### 3.3 Profile 配置

描述“这个 Profile 如何部署组件”：

- micdn 根属性：`home`、`listen`、`log-file`、`log-level`；`remote` 在下载时按请求 origin 自动生成；
- 各服务段：`maven`、`npm`、`native`、`auth`、`static`、`www`、`blob`；
- 服务的 base、上游、容量和鉴权；
- 引用哪些 static/www 组件，以及这些组件在本 Profile 下的顺序；Blob 只保存 Profile 级参数。

## 4. 数据库设计

配置是文档型数据，只有组件身份和 Profile 绑定需要被关系查询，因此不需要把每个子数组都拆成表。
建议收敛为 3 张表。

### 4.1 组件目录

```sql
create table bas.cdn_components (
  id bigint primary key,
  kind varchar(32) not null,      -- static_bundle | www_doc
  name varchar(255) not null,
  mount_name varchar(255) not null,
  remark varchar(255),
  spec jsonb not null,
  unique (kind, name),
  unique (kind, mount_name)
);
```

`name` 是组件目录标识，`mount_name` 是部署挂载名，二者都必须显式保存，不允许在运行时用 `name`
代替 `mount_name`。

`spec` 按 `kind` 使用固定结构。`static_bundle`：

```json
{
  "sources": [
    {"kind": "jar", "ref": "org.webjars:jquery-ui:1.13.1", "inner": ""},
    {"kind": "dir", "ref": "/srv/static/local", "inner": ""}
  ]
}
```

`www_doc`：

```json
{
  "source": {"kind": "npm", "ref": "@xurp/manual@0.0.2", "inner": "dist"},
  "tryFile": "index.html",
  "autoDeploy": false,
  "autoGzip": true
}
```

### 4.2 Profile 配置

```sql
create table bas.cfg_profile_micdn (
  profile_id bigint primary key references bas.cfg_profiles(id),
  config jsonb not null
);
```

`config` 只保存各段自身的设置，不重复组件内容：

```json
{
  "home": "/var/lib/micdn",
  "listen": "0.0.0.0:8888",
  "logFile": "console",
  "logLevel": "info",
  "maven": {
    "declared": true,
    "base": "/var/lib/micdn/maven",
    "remotes": ["https://repo1.maven.org/maven2"],
    "snapshotRemote": ""
  },
  "npm": {
    "declared": true,
    "base": "/var/lib/micdn/npm",
    "remotes": ["https://registry.npmmirror.com"],
    "devRemote": ""
  },
  "native": {"declared": false, "base": ""},
  "auth": {"publishKey": "", "downloadKey": "", "maxSize": "64M"},
  "static": {"base": "/var/cache/micdn/asset"},
  "www": {"base": "/var/cache/micdn/www"},
  "blob": {
    "base": "/var/lib/micdn/blob",
    "maxSize": "50M",
    "publicImages": true
  }
}
```

### 4.3 Profile 与组件绑定

```sql
create table bas.cfg_profile_micdn_components (
  id bigint primary key,
  profile_id bigint not null references bas.cfg_profiles(id),
  component_id bigint not null references bas.cdn_components(id),
  sortno integer not null,
  unique (profile_id, component_id)
);
```

`cfg_profile_micdn.profile_id` 直接作为主键，一个 Profile 只有一份配置。绑定表保留独立 `id` 作为通用
JSON:API 资源主键，同时用 `unique (profile_id, component_id)` 阻止同一组件在一个 Profile 内重复绑定。
挂载名只存在组件目录中；Profile 不提供覆盖入口。绑定保持关系表而不是塞进 JSON，是为了让数据库拦住
“组件删了、Profile 还引用”的悬挂数据。

不建议把所有内容压成一张 JSON 大表：组件会被多个 Profile 引用，删除组件时没有外键保护，最终只能在渲染期
报错。现在的 3 张表已经去掉了所有嵌套子表，复杂度足够低。

当前通用 JSON:API 的 `Kind.jsonArray` 只表达字符串数组，不适合这里的对象结构。组件和 Profile 配置应由
专用聚合服务读写；如果以后要让它们走通用资源页，再补一个 `Kind.jsonDocument`，不要用文本拼接模拟 JSON。

## 5. 渲染规则

新增一个纯渲染函数：

```text
renderMicdnConfig(profileId) -> XML
```

按固定顺序输出，保证同一份数据每次渲染结果稳定：

1. `<micdn>` 根属性；
2. `<maven>`；
3. `<npm>`；
4. `<native>`；
5. `<auth>`；
6. `<blob>`；
7. `<static>`；
8. `<www>`。

规则：

- `declared=false` 的 `maven` / `npm` / `native` 不输出；
- `auth` 两个 key 都为空时不输出；
- static / www 没有绑定任何组件时不输出对应段；
- `remote` 不保存到 Profile：下载时按请求 origin + `/api/bashub/micdn/{profile}/micdn.xml` 自动生成，反代后的 `X-Forwarded-Proto/Host/Port` 参与计算；
- Profile `key` 非空时输出唯一 bucket，bucket 的 name/key 取 Profile 的 name/key；key 为空时不输出 Blob；
- 各段的 base 留空时使用 `home + 默认子目录`；`home` 也为空时直接使用默认子目录（例如 `/blob`），与 micdn 的解析规则一致；
- static bundle 按挂载名字母排序，bundle 内的 provider 固定按 `jar` → `npm` → `dir`、再按 `ref` / `inner` 排序；
- www doc 按 `sortno` 再按挂载路径排序；
- remotes 保持配置顺序；
- 空的可选属性不输出，默认值不手工展开；
- 属性值统一 XML 转义；
- Profile 不存在、数据不一致时返回 500，不生成“半份”配置。

示意输出：

```xml
<micdn listen="0.0.0.0:8888" remote="https://hub.example.com/api/bashub/micdn/openurp.prod/micdn.xml" home="/var/lib/micdn">
  <maven base="/var/lib/micdn/maven">
    <remote url="https://repo1.maven.org/maven2"/>
  </maven>
  <npm base="/var/lib/micdn/npm">
    <remote url="https://registry.npmmirror.com"/>
  </npm>
  <auth publish-key="..." max-size="64M"/>
  <static base="/var/cache/micdn/asset">
    <bundle name="bootstrap">
      <jar gav="org.webjars:bootstrap:4.6.1"/>
    </bundle>
  </static>
  <www base="/var/cache/micdn/www">
    <doc name="manual" npm="@xurp/manual@0.0.2" try-file="index.html"/>
  </www>
  <blob base="/var/lib/micdn/blob" max-size="50M">
    <bucket name="prod" key="..."/>
  </blob>
</micdn>
```

## 6. API

### 6.1 机器读取

```text
GET /api/bashub/micdn/{profile}/micdn.xml
```

返回 `application/xml`。沿用 `/api/bashub/micdn/{profile}` 的 Profile 解析和令牌校验。XML 根节点的 `remote`
由本次请求的 origin 自动写成标准配置地址，不读取 Profile 配置；反代场景按 `X-Forwarded-*` 计算。

`{profile}` 只用于定位 Profile，不再校验 `ip` 头。请求必须携带等于 `profile.key` 的令牌：

```text
X-Micdn-Token: <profile.key>
Authorization: Bearer <profile.key>
Authorization: Basic base64(<任意用户名>:<profile.key>)
```

缺失或错误返回 `401`，带 `WWW-Authenticate: Basic realm="micdn"` 和 `Cache-Control: no-store`。
未知 Profile 同样返回 `401`，避免暴露配置名是否存在。

```bash
curl -f \
  -H "Authorization: Bearer $PROFILE_KEY" \
  http://127.0.0.1:8082/api/bashub/micdn/openurp.prod/micdn.xml
```

如果部署侧用 micdn 的 `-f URL` 直接拉取，micdn 的配置下载必须把同一个令牌放进上述请求头；
只给 URL 不能完成鉴权。

旧资产清单入口与旧资源路径已删除；不提供兼容层，避免同时维护两套静态资源模型。

### 6.2 管理台聚合读取

```text
GET /api/bashub/micdn/profiles/{id}
```

一次返回一个 Profile 的完整有效配置：

- 各段设置；
- 绑定的组件、组件挂载名和顺序；
- 可复用的组件目录信息；
- 已脱敏的密钥状态（`publishKeySet` / `downloadKeySet` / `profile.keyMasked`）；
- 生成后的 XML（密钥默认脱敏）。

```text
GET /api/bashub/micdn/profiles/{id}/micdn.xml
```

供页面“预览 / 下载”使用。真实密钥只在明确的下载动作中返回，并设置 `Cache-Control: no-store`。

```text
PATCH /api/bashub/micdn/profiles/{id}
```

一次事务保存整份配置。对 Profile 页面来说，比让前端逐个调用十几个子资源更可靠。

### 6.3 组件 CRUD

组件使用一个聚合资源：

```text
GET   /api/bashub/micdn/components
POST  /api/bashub/micdn/components
PATCH /api/bashub/micdn/components/{id}
```

请求体包含 `kind`、`name`、`mountName`、`remark`、`spec`。`name` 和 `mountName` 都必填，
缺少 `mountName` 直接返回 400。`spec` 按 kind 校验；static sources 在服务端按 provider 归一排序。

## 7. 页面设计

### 7.1 Profile 列表

每个 Profile 行增加“Micdn 配置”入口，进入：

```text
/profiles/:id/micdn
```

### 7.2 Micdn 配置页

页面以 Profile 标题开头，右侧固定“预览 XML / 复制 / 下载 / 保存”。

左侧或顶部按段切换：

| 页签 | 内容 |
|---|---|
| 基础 | `home`、`listen`、日志；`remote` 不配置、不展示，下载时由请求 origin 自动生成 |
| Maven / NPM / Native | declared、base、remotes、snapshot/dev |
| 鉴权 | publish-key、download-key、max-size |
| Static | base + 引用 bundle + 只读挂载名；按挂载名字母展示，不设置顺序 |
| WWW | base + 引用 doc + 只读挂载路径 + 顺序 |
| Blob | base、max-size、publicImages + 只读 Profile name 和脱敏 key；有 key 即输出 |
| 预览 | 完整 XML、校验提示 |

页面不要把这些段拆成多个独立资源页。用户要看到的是“这个 Profile 的最终配置”，而不是一堆互不关联的表。

### 7.3 组件页

组件页保留目录式管理：

- Static bundle 及 provider 列表；
- WWW doc。

在 Profile 页中只负责“选择组件和设置顺序”；挂载名和组件来源都在组件目录维护。Blob 的 bucket
身份来自 Profile，不再出现在组件页。

## 8. 旧数据转换与移除

迁移脚本 `migrate/0.0.8-10-micdn-profile.sql` 先创建三张新表，再把旧静态资产转换成新模型：

- 每个旧 `cdn_assets` 转成一个 `static_bundle`，`gav` / `location` 按原顺序转成 `jar` / `dir` source；
- 每个“Profile -> asset group -> asset”关系转成一条 Profile 组件绑定；
- `mount_name` 取旧 `assets.base` 去掉前导 `/`，保存到组件目录，保持原静态 URL；
- 同一 Profile 的绑定按旧 `base` 排序生成 `sortno`；
- 有旧静态组的 Profile 若尚无 Micdn 配置，则补充默认配置，并把 `local_repo` / `remote_repo` 写入 Maven 段；
- 已不存在的 Profile、没有来源的资产和重复挂载名会被跳过，不制造悬挂外键。

已经执行过早期 0.0.8 Micdn Profile 改造的数据库，使用 `migrate/0.0.8-08-micdn-component-mount.sql`
把绑定表的 `mount_name` 回填到组件目录。该脚本要求每个组件都能从现有绑定中唯一确定挂载名；任何
无绑定或多挂载名的组件都会让迁移直接失败，不使用组件名补位。

`migrate/0.0.8-09-micdn-profile-blob.sql` 清理旧的 `blob_bucket` 组件和绑定，并移除 Blob 配置中已废弃的
`declared` 字段、补齐 `publicImages`。旧 bucket 的名称和 key 不再迁移；新模型只认 Profile 自身的 name/key。
`migrate/0.0.8-10-micdn-profile.sql` 同时移除配置中已废弃的 `remote` 字段。

转换完成后删除 `cdn_asset_bundles`、`cdn_asset_groups_profiles`、`cdn_assets`、`cdn_asset_groups`
四张旧表，并清理对应 sequence。转换与建表均通过 `if not exists` / `on conflict do nothing` 保持可重复执行。
旧 `asset-groups` / `assets` 页面、资源定义、演示数据和 `assetGroups` 关系全部删除，不保留兼容入口。

## 9. 安全与校验

- `cfg_profile_micdn.config.auth.publishKey` / `downloadKey` 和 `cfg_profiles.key` 属于凭据；
- basctl 的机器配置会把 micdn `auth.downloadKey` 写入 `<snapshot-repo token>`，作为
  `/maven` SNAPSHOT 的读令牌；未配置时省略 `token`（匿名下载）。SPA 查看 `server.xml`
  时该值显示为 `********`；
- 列表和聚合读取默认只返回“已设置/未设置”；Profile key 保留首尾各两个字符，中间用 `**` 掩盖；
- 只有显式下载 XML 时返回明文，并要求登录、`no-store`、不在日志中打印；
- 校验挂载名：static 必须是非空单段路径；www 必须是非空多段路径，不能有空段、`.` 或 `..`；
- 校验 Blob：启用时必须存在 Profile name/key；
- 校验 provider 与段匹配：static 不接受 zip，www 不接受 jar/dir；
- 校验 `auto-deploy` 只能用于 zip；
- 校验 base 路径不能为空；
- 组件目录内同一 kind 的挂载名唯一；Profile 内同一组件不能重复绑定；
- 渲染前做一次完整校验，错误直接返回，不生成部分 XML。

## 10. 已实现

1. 三张表、组件/Profile 聚合服务、迁移脚本和 DDL 已落地；
2. `renderMicdnXml` 与 `/api/bashub/micdn/{profile}/micdn.xml` 已实现，并用单元测试锁定空段、转义和非法来源；
3. Profile 聚合读取/保存、密钥保留与显式清空已实现；
4. 组件目录页已实现 static bundle / www doc 的 CRUD；Blob bucket 改为 Profile 级只读身份；
5. Profile 的 Micdn 配置页、聚合预览、复制与真实 XML 下载已实现；
6. 旧 `cdn_asset_*` 数据已转换，旧表、API、页面和演示数据已删除；
7. 剩余回归项：用实际生成文件启动 micdn，逐段验证 static、www、blob、maven、npm、native、auth。

验收标准：同一份 Profile 数据连续渲染两次字节一致；空段不输出；所有 micdn 配置元素都有结构化入口；
页面能看到并下载完整 XML。
