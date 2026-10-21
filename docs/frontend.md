# 前端工程说明（packages/web）

管理台是 Vite + Vue 3 + TDesign 的独立 SPA，与 D 后端（只提供 JSON:API）分开构建、分开部署。

## 依赖管理

仓库根目录是 pnpm workspace，**禁止使用 npm / yarn**（`scripts/check-pnpm.cjs` 会在 install 时拦截）。

```bash
pnpm install              # 安装依赖（根 + packages/*）
pnpm dev:web              # 本地开发，vite --host 0.0.0.0
pnpm typecheck            # 类型检查
pnpm build:web            # 产物到 packages/web/dist
pnpm --filter @beangle/bashub-web package   # build + 打包 release/bashub-web.zip
```

## 依赖约定：`@beangle/ems-app`、`@beangle/bui-vue` 都跟正式版

登录会话、运行时配置、请求客户端、微前端生命周期、门户 UI 同步与 PC 壳层（`AppShell`）都来自 `beangle/ems` 的 `packages/ems-app`，
表格组件来自 `beangle/bui-vue`。两者都跟**已在 npmjs 发布的正式版**，按包正常解析，不用 `link:`：

```json
"@beangle/ems-app": "^0.0.2",
"@beangle/bui-vue": "^0.0.5"
```

只有需要联调上游还没发布的改动时，才临时把版本号换成开发预览版（如 `"@beangle/ems-app": "0.0.3-dev.<UTC 时间戳>"`，
由 ems 仓库的 `pnpm release:dev` 发布到本地 registry），联调完换回正式版。

`link:` 会把源码/构建产物路径透到本仓库，逼着应用侧加源码别名、`server.fs.allow`、重复 Vue 实例之类的耦合；
两种版本号走的解析路径一样（`exports` 到 `dist` + `styles/`），只是版本号来源不同。`ems-app` 声明的 `bui-vue`
区间要跟本仓库对齐，升级时两处一起改，pnpm 才会去重成一份；否则 `ems-app` 自带嵌套副本，
`AppShell` 里的 `SideNav` 与页面用的 `DataGrid` 分属两个实例。

`@beangle/*` 的正式版发到 npmjs 后，本地 registry **不会自动跟上**：packument 一旦落盘就本地优先，
代理只补本地缺失的包。把 tgz 交给 `micdn install` 装进去即可（版本、`dist-tags` 与 `time` 并入已有 packument，
已有的开发版条目不受影响）：

```bash
npm pack @beangle/bui-vue@0.0.5 --registry https://registry.npmjs.org
micdn -f <micdn.xml> install ./beangle-bui-vue-0.0.5.tgz

npm pack @beangle/ems-app@0.0.2 --registry https://registry.npmjs.org
micdn -f <micdn.xml> install ./beangle-ems-app-0.0.2.tgz
```

仓库根 `.npmrc` 把 `@beangle`、`@openurp` 作用域指向本地 registry（读取匿名可用，不含密钥，可提交）：

```ini
@beangle:registry=http://localhost/npm/
@openurp:registry=http://localhost/npm/
```

**发布用的 token 不放这里**（本文件要提交、且被 `.gitignore` 白名单放开）：token 属于用户级密钥，
写进 `~/.npmrc`，一行一个 registry，host+path 必须与发布地址逐字一致（含结尾 `/`，`localhost` 与
`127.0.0.1` 算两个 registry）：

```ini
//localhost/npm/:_authToken=<token>
//127.0.0.1:8080/npm/:_authToken=<token>
```

CI 里换成密钥变量插值（npm/pnpm 会展开 `${...}`），不要提交真实 token：
`//<host>/<path>/:_authToken=${NPM_TOKEN}`。排查：`npm whoami --registry http://localhost/npm/` 能认人即通；
发布报 E401 基本都是 host+path 没对上。

升级联调循环（先改库、发新版本，再让本仓库跟上）：

```bash
(cd ../ems/packages/ems-app && pnpm publishLocal)  # bui-vue 走 ~/bin/npm-release.sh，发完再 micdn install 进本地 registry
pnpm add @beangle/ems-app@dev                      # 按本地 registry 的 dev 标签解析并写回精确版本号
pnpm add @beangle/bui-vue@^0.0.5                   # 正式版直接写区间
```

发布脚本细节见 `ems-app/scripts/publish-local.sh`（构建 → 临时写版本号 → 发 `--tag dev` → 复原 `package.json`；
`DRY_RUN=1` 可只打印目标 registry）。

`src/auth.ts` 是唯一的接线点：创建 `runtimeConfig` 与 `auth`，并暴露 `loadRuntimeConfig()` /
`initializeAuth()`。运行时配置来自 `/api/bashub/ems/configs.json`，按 ems-app 的约定只含 `ems_base`（外加 `app_name`/`logoUrl`），CAS 地址由 ems-app 在 `ems_base` 后拼接 `/cas`。`/api/bashub/ems/sessions/logout` 由 `logoutUrl` 选项指定。

## 环境变量（Vite）

| 变量 | 用途 |
|---|---|
| `VITE_APP_BASE` | 部署前缀，默认 `/bashub/`，须与 web 服务器部署目录一致 |
| `VITE_API_BASE` | 开发环境后端 origin，dev server 用它把同源 `/api` 代理到后端 |
| `VITE_CAS_*` | 可选的 CAS 构建期兜底；正常由 `configs.json` 的 `ems_base` 推导 |

生产环境默认走同源相对路径，由 web 服务器把 `/api` 反代到 D 后端；SPA 的 history 路由需 fallback 到 `index.html`。

## 组件与样式

- TDesign 组件按需引入：`unplugin-vue-components` + `TDesignResolver`（见 `vite.config.ts`），模板里直接写 `<t-*>`；`components.d.ts` 由该插件生成，需提交。
- 该按需引入只改写本应用的模板，覆盖不到库产物：`@beangle/bui-vue` 的 `DataGrid` 用 `resolveComponent('t-table')` 这类运行时名字取组件，
  必须在 `main.ts` 里显式全局注册它用到的 button/checkbox/input-number/loading/option/popup/select/table，
  否则表格只剩工具条与「1-30 of N」分页，不渲染表头与数据行。
- 表格用 `@beangle/bui-vue` 的 `DataGrid`（显式 import），样式入口 `@beangle/bui-vue/styles/data-grid.css`。
- 表格色板（`--bui-gridbar-bg`/`--bui-grid-header-bg`/`--bui-grid-row-hover-bg`/`--bui-grid-row-selected-bg` 等，
  经典 BUI 同名变量）由 bui-vue 自带缺省值（浅色 + `[theme-mode="dark"]` 深色），**应用侧不要再重复声明**；
  否则「已选择 N 条」提示条、行悬停会退化成中性灰。门户色板仍可通过 ems-app 的 `applyPaletteVars()` 覆盖其中同名变量。
- DataGrid 工具条按钮用默认的 `variant: 'text'`（无边框文本 + 悬停底色），与经典 BUI 的 `.toolbar-item`、exam 一致；
  不要传 `variant: 'outline'`，那会变成带边框的盒子按钮。
- 壳层样式由 `@beangle/ems-app/dist/index.css` 提供，`src/styles.css` 只保留业务面板样式。
- 侧栏菜单由 `@beangle/ems-app` 的 `AppShell` 渲染，菜单本体是 `@beangle/bui-vue` 的 `SideNav`
  （规格取自 EMS 门户侧栏，即 ems-shell 的 AdminLTE `nav-sidebar`）：扁平项无圆角无选中底色，
  顶级项左侧 3px 透明边框、激活或含激活子项时染主色，子级整层缩进 0.5rem 且文字转灰。
  样式入口 `@beangle/bui-vue/styles/side-nav.css` 必须在 `main.ts` 引入（bui-vue 的样式一律单独引出）；
  几何/色板走 `--bui-side-nav-*`，`AppShell` 已把 `--appshell-sidebar-*` 映射过去，宿主仍只需覆盖后者。
  分组按手风琴展开（同一时刻只展开含当前条目的分组，点其它分组标题时收起前一个），窄屏由 AppShell
  的 `matchMedia('(max-width: 900px)')` 传 `collapsed`，只留图标。
- 左栏查询面板的规格（面板内边距、60px 标签列、28px 控件、查询按钮）由 `@beangle/bui-vue/styles/query-form.css`
  提供，工作台外框/栅格由 `styles/workbench.css` 提供，两者都在 `main.ts` 引入；应用侧只用
  `--bui-query-*`/`--bui-*` 变量覆盖色板（含 `[theme-mode='dark']`），不要重写几何。
- 列表页「新建/编辑」抽屉表单的规格由 `@beangle/bui-vue/styles/drawer-form.css` 提供（`main.ts` 引入）：
  `t-drawer` + `t-form.drawer-form` + `label-align="top"` + `required-mark required-mark-position="right"`，
  字段放进 `.drawer-form-grid`（两列，`textarea`/`lines` 用 `.drawer-form-field-wide` 占整行），
  动作条放抽屉 `#footer` 插槽（`div.drawer-actions`；字段少、不需滚动的短表单才内联 `:footer="false"`）。
  三个必须注意的点：`requiredMark`/`requiredMarkPosition` 是两个 prop，写 `required-mark="right"` 无效且会类型告警；
  字段说明要用 `<template #help>`（走 `.t-input__help`，占一行），塞进默认插槽会挤在同一 flex 行里；
  抽屉内的 FormItem 常驻 DOM，给 model 赋空值会触发 TDesign「值变化即校验」，所以表单绑定
  `:show-error-message="showErrors"`，打开时置 false、首次提交前置 true。

## 页面组织

- 资源页是元数据驱动的：`src/resources/index.ts` 声明每个资源的 `path`/`type`/`fields`/`filters`/`tools`，
  `src/views/ResourceListView.vue` 据此渲染 DataGrid、查询、增删改与批量动作；`src/router`、`HomeView`、
  `StandaloneShell` 的菜单也由同一份 schema 生成。新增一个后台资源通常只需加一段 schema。
  字段列宽用 `field.width`：数字按 px（如顺序号 100、菜单启用列 80、菜单名称列 200），字符串按百分比。
- 查询条件渲染在左侧 `aside.query-panel`（对齐 exam 的 `data-workbench` 布局），字段来自 `schema.filters`：
  `ref`/`select`/`boolean` 用下拉，`number` 用数字框，其余用文本框（回车即查）。
- 每个 schema 必须声明 `alias`（后端实体简单名，如 `webapp`/`menu`）：列表 filter 会拼成
  `filter[<alias>.<属性>]`，后端 `QueryHelper` 只认这个带别名前缀的写法；引用字段缺省用 `key.id`，
  需要打到关联对象属性（如 `artifact.artifactId`、`entry.name`）时用 `filterKey` 指定。
- 引用列缺省按 `ref.labelFields` 组合展示（下拉选项也用它）；只想展示关联的某个属性时给该列加
  `cell: { type: 'join', fields: ['<关联名>.<属性>'] }`（如菜单的「使用资源」只列 `resources.title`，
  不显示资源名那种 `/setting/config.action` 的权限串，与旧 `menu/list.ftl` 一致）；
  `join` 走列表 `include` 回来的关联数据，字段本身仍按 `refs` 参与表单与 include。多个字段用
  `separator` 连接，空值自动跳过（如菜单的「入口地址」= `entry.name` + `?` + `params`）。
- 「当前配置」记忆（原 `ProfileHelper` + cookie `current_profile_id` 的前端对等物，见 `src/current-profile.ts`）：
  查询条件里有 `ref`→`profiles` 字段的资源视为**配置作用域**（当前是群集管理/主机管理/应用部署），
  打开页面时该查询条件自动填成记忆的配置，用户在查询条件里选中的配置会写回记忆（存 localStorage
  `bashub.current_profile_id`），切到同类页面继续沿用；新建表单里的配置字段也默认取记忆值。
  空值不覆盖（与旧 `ProfileHelper.remember` 一致，清空条件=看全部，不会抹掉记忆）；记忆的配置若已被删除，
  加载选项后会被丢弃，避免下拉框显示裸 id。宿主/门户下发的 `?contextProfileId=<id>` 优先级最高
  （参数名沿用 ems-app 的 `EMS_URL_PARAMS.contextProfileId`）。`refs`→profiles（如静态组的「针对配置」）不算，
  artifact/engine 的「针对配置」是可空选项、不参与记忆。
- 必填查询条件（菜单管理的「应用」，`filters` 里标 `required: true`）：**未选定时不发列表请求**，
  数据区只显示「请先选择应用」，避免空条件把全量菜单拉回来（原 `MenuAction.indexSetting` 也是先选应用再加载）。
  默认值优先取记忆：URL 显式给的查询条件优先级最高，其次是 localStorage 里上次选的应用
  （键 `bashub.filter.<schema key>.<字段 key>`，本页即 `bashub.filter.menus.app`，对应旧 cookie `menu.app.id`），
  记忆值若已不在下拉选项里（应用被删）会被丢弃；只有唯一选项时直接选中它。
  导出/导入 XML 按钮同样以「应用已选」为前置条件。
- 从属页面：`menu: false` 但**不被页签组收录**的资源保留独立路由、只是不进菜单，入口放在父资源页上。
  当前是 `servers`（服务管理）：对应原 `farm/form.ftl` 的「服务配置」页签 + `farm/list.ftl` 的「维护」链接，
  入口在群集列表行的「维护」（`/servers?farm=<id>`）与群集编辑抽屉底部的「相关页面」（`schema.drawerLinks`，
  `{属性}` 按当前行取值填充，只在编辑已有记录时出现）。子页面靠 `ResourceListView` 的 URL 查询条件预填左侧查询面板，
  新建时同一 key 的单选 `ref` 字段也默认取该值（原 UI 用隐藏域锁定父对象，如 `server.farm.id`）。
- 平台功能详情页 `/platform-features/:id`（`PlatformFeatureDetailView.vue`，对应原 `platformFeature/info.ftl`）：
  卡片墙由 `schema.cardLink` 指过来（卡片点击进详情，不再开抽屉），页面里功能自身「修改」就地编辑，
  每个平台一份脚本就地查看/修改、就地保存与删除，标题栏右侧「增加脚本」追加一行编辑态。
  脚本按 `filter[platformFeatureScript.feature.id]=<id>` 拉取（别名即实体简单名），平台下拉取
  `/api/bashub/config/platforms`；写入走 JSON:API 的
  `POST/PATCH/DELETE /api/bashub/config/platform-feature-scripts`。该资源因此**没有独立列表页**，
  SPA 里也不再有对应的 schema。
- Profile 详情页 `/profiles/:id`（`ProfileDetailView.vue`）：从配置列表的名称列或编辑抽屉进入，
  左侧导航切换概览、Haproxy/Nginx、Setline、证书、BAS 服务与 Micdn，右侧以卡片展示配置和关联资源；
  `?section=setline` 等查询参数可直达对应分区。
- 页签合成页：`resourceTabGroups` 把若干资源列表收进**一个菜单项**、页面内用页签切换。当前四组：
  `配置与机构`（`/org-config`，收 `profiles` + `organizations`）、`平台与功能`（`/platform-ops`，
  收 `platform-features` + `platforms`，页签顺序沿用原 `config/platform/nav.ftl` 的「系统特性→操作系统」）、
  `应用配置`（`/app-config`，收 `apps` + `channels` + `app-groups`，应用端即 app 的部署上下文/嵌入方式）、
  `菜单与资源`（`/menu-config`，收 `menus` + `resources`）。
  第一个页签即默认页签，路由 `<组路径>?tab=<资源 key>`；组 key 与成员资源 key 不重名。
  菜单项落在分组里**最先出现的成员**的位置上，与页签顺序无关。被收录的资源标 `menu: false`
  不再单列菜单；`ResourceListView` 收到 `tabs` 时在页头下方渲染 `@beangle/bui-vue` 的 `UnderlineTabs`，
  样式需在 `main.ts` 引 `@beangle/bui-vue/styles/underline-tabs.css`。页签状态只认 URL 的 `?tab=`，
  刷新/收藏/前进后退一致；各页签资源自己的旧路径（`/organizations`、`/profiles`）由路由重定向到本页，
  重定向会**带上原有查询条件**（如 `/menus?app=<id>` 落到菜单页签后仍按该应用过滤，导出按钮据此可用）。

## 接口

接口契约见 [`docs/frontend-api.md`](frontend-api.md)；各前端路由与后端 API 的逐页对应见
[`docs/frontend-routes.md`](frontend-routes.md)。
