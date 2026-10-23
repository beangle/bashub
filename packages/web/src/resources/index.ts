import { apiPath, resourceApiPath } from '@/api/prefix'
import type { ResourceRef, ResourceSchema, ResourceTabGroup } from './types'

const organizationRef: ResourceRef = { path: '/organizations', type: 'organizations', labelFields: ['name', 'title'] }
const profileRef: ResourceRef = {
  path: '/profiles',
  type: 'profiles',
  labelFields: ['qualifiedName'],
  sort: 'org.name,name',
}
const platformRef: ResourceRef = { path: '/platforms', type: 'platforms', labelFields: ['name'] }
const featureRef: ResourceRef = { path: '/platform-features', type: 'platformFeatures', labelFields: ['name', 'version'] }
const appRef: ResourceRef = { path: '/apps', type: 'apps', labelFields: ['title'] }
const resourceRef: ResourceRef = { path: '/resources', type: 'resources', labelFields: ['name', 'title'] }
const farmRef: ResourceRef = { path: '/farms', type: 'farms', labelFields: ['name'] }
const hostRef: ResourceRef = { path: '/hosts', type: 'hosts', labelFields: ['name', 'ip'] }
const serverRef: ResourceRef = { path: '/servers', type: 'servers', labelFields: ['name'] }
const artifactRef: ResourceRef = { path: '/artifacts', type: 'artifacts', labelFields: ['title', 'artifactId'] }

/**
 * 引擎类型，取值与 basctl 的 creator 同名。
 * `tomcat-server` 跑全量发行包，一个 JVM 可部署多个 webapp；其余 Java 引擎为嵌入式单应用。
 */
const engineTypeOptions = [
  { value: 'tomcat-server', label: 'tomcat 发行包（多应用）' },
  { value: 'tomcat', label: 'tomcat 嵌入式（单应用）' },
  { value: 'undertow', label: 'undertow 嵌入式（单应用）' },
  { value: 'jetty', label: 'jetty 嵌入式（单应用）' },
  { value: 'any', label: 'any' },
]
const scopeOptions = ['Public', 'Protected', 'Private'].map((value) => ({ label: value, value }))

const channelTypeOptions = [
  { label: 'PC', value: 'pc' },
  { label: '移动', value: 'mobile' },
]

const embedModeOptions = [
  { label: 'iframe', value: 'iframe' },
  { label: 'wujie', value: 'wujie' },
]

const archOptions = [
  { label: 'Noarch', value: 1 },
  { label: 'X86_64', value: 2 },
  { label: 'AArch64', value: 3 },
]

const setlineEnabledOptions = [
  { label: '启用', value: 'yes' },
  { label: '不启用', value: 'no' },
]

function hasPortValue(value: unknown): boolean {
  return value !== null && value !== undefined && String(value).trim().length > 0
}

export const resourceSchemas: ResourceSchema[] = [
  {
    key: 'organizations',
    alias: 'organization',
    path: '/organizations',
    type: 'organizations',
    title: '机构管理',
    group: '平台配置',
    description: '机构名称、简称与 Logo',
    sort: 'name',
    filters: [{ key: 'name', label: '名称' }, { key: 'title', label: '标题' }],
    fields: [
      { key: 'name', label: '名称', required: true, width: 160 },
      { key: 'logoUrl', label: 'Logo', width: 90, cell: { type: 'image', width: 30 } },
      { key: 'title', label: '标题', required: true },
      { key: 'shortTitle', label: '简称', width: 140 },
    ],
  },
  {
    key: 'platforms',
    alias: 'platform',
    path: '/platforms',
    type: 'platforms',
    title: '平台管理',
    group: '平台配置',
    description: '操作系统平台及其主版本',
    sort: 'name',
    filters: [{ key: 'name', label: '名称' }, { key: 'majorVersion', label: '主版本' }],
    fields: [
      { key: 'name', label: '名称', required: true },
      { key: 'majorVersion', label: '主版本' },
      { key: 'fonticon', label: '字体图标', cell: { type: 'icon' } },
    ],
  },
  {
    key: 'profiles',
    alias: 'profile',
    path: '/profiles',
    type: 'profiles',
    title: '配置管理',
    group: '平台配置',
    description: '部署配置：仓库、端口、HTTPS、setline 与 Micdn',
    sort: 'name',
    filters: [{ key: 'name', label: '名称' }, { key: 'title', label: '标题' }],
    fields: [
      { key: 'name', label: '名称', required: true, width: '10%', cell: { type: 'link', href: resourceApiPath('/profiles/{id}'), text: '{qualifiedName}', target: '_self' } },
      { key: 'title', label: '说明', required: true, cell: { type: 'join', fields: ['org.shortTitle', 'title'], separator: '' } },
      { key: 'org', label: '机构', type: 'ref', ref: organizationRef, column: false },
      { key: 'basVersion', label: '版本', required: true, width: '8%' },
      { key: 'key', label: 'Key', column: false, wide: true },
      { key: 'ip', label: 'IP', required: true, width: '13%' },
      { key: 'hostname', label: '域名', width: '16%' },
      {
        key: 'proxyByHostname', label: 'Setline 按域名分组', type: 'boolean', column: false,
        help: '启用时把 Profile 域名生成为 setline-hostname；关闭时省略该属性，由 basctl 使用 * 默认组',
      },
      { key: 'proxyEngine', label: '代理类型', type: 'select', column: false, options: [{ label: 'Haproxy', value: 'haproxy' }, { label: 'Nginx', value: 'nginx' }] },
      { key: 'httpPort', label: 'HTTP 端口', type: 'number', column: false },
      { key: 'maxconn', label: '最大连接数', type: 'number', column: false },
      { key: 'enableHttps', label: '使用HTTPS', type: 'boolean', width: '10%', cell: { type: 'boolean', trueText: 'true', falseText: 'false' } },
      { key: 'forceHttps', label: '强制 HTTPS', type: 'boolean', column: false },
      { key: 'httpsPort', label: 'HTTPS 端口', type: 'number', column: false },
      {
        key: 'sslCiphers', label: 'SSL 加密套件', column: false,
        help: '不填写时由代理使用默认套件',
      },
      { key: 'sslProtocols', label: 'SSL 协议', column: false },
      { key: 'localRepo', label: '本地仓库', column: false, help: '默认 ~/.m2/repository' },
      { key: 'remoteRepo', label: '远程仓库', column: false, width: 260 },
    ],
    drawerLinks: [
      { label: '配置详情', to: resourceApiPath('/profiles/{id}') },
      { label: 'Micdn 配置', to: apiPath('micdn', '/profiles/{id}') },
    ],
  },
  {
    key: 'engines',
    alias: 'engine',
    path: '/engines',
    type: 'engines',
    title: '引擎管理',
    group: '平台配置',
    description: 'Servlet 容器/引擎及其监听器与依赖 jar',
    sort: 'name',
    filters: [
      { key: 'name', label: '名称' },
      { key: 'typ', label: '类型', type: 'select', options: engineTypeOptions },
    ],
    fields: [
      { key: 'name', label: '名称', required: true },
      {
        key: 'typ', label: '类型', type: 'select', required: true, options: engineTypeOptions,
      },
      { key: 'version', label: '版本', required: true },
      { key: 'jspSupport', label: 'JSP', type: 'boolean', help: '仅 tomcat-server（发行包）带 Jasper；嵌入式引擎不支持 JSP' },
      { key: 'websocketSupport', label: 'WebSocket', type: 'boolean', help: '关闭后 basctl 不再引入 websocket 依赖；tomcat-server 随发行包，不受影响' },
      { key: 'profile', label: '配置', type: 'ref', ref: profileRef },
      { key: 'listeners', label: '监听器', type: 'lines', column: false, help: '一行一个监听器类名' },
      { key: 'jars', label: '依赖 Jar', type: 'lines', column: false, help: '一行一个 jar 坐标' },
    ],
  },
  {
    key: 'farms',
    alias: 'farm',
    path: '/farms',
    type: 'farms',
    title: '群集管理',
    group: '平台配置',
    description: '同一配置下的引擎与进程参数',
    sort: 'name',
    filters: [{ key: 'name', label: '名称' }, { key: 'profile', label: '配置', type: 'ref', ref: profileRef, required: true }],
    fields: [
      { key: 'name', label: '名称', required: true, width: '10%' },
      // 配置是查询条件里的必填项，列表列不再重复展示。
      { key: 'profile', label: '配置', type: 'ref', ref: profileRef, required: true, column: false },
      { key: 'engine', label: '引擎', type: 'ref', ref: { path: '/engines', type: 'engines', labelFields: ['name', 'version'] }, required: true, width: '12%' },
      { key: 'maxHeapSize', label: '堆上限(MB)', type: 'number', required: true, width: '8%' },
      // 进程参数只在表单里维护。
      { key: 'serverOptions', label: '进程参数', column: false, help: '如 -Xss512k' },
      // 与原 farm/list.ftl 一致：`服务名(主机名:端口)`，多个以空格分隔。
      {
        key: 'servers', label: '服务', type: 'refs', ref: serverRef, form: false,
        cell: {
          type: 'refItems', itemTemplate: '{name}', itemMutedTemplate: '({host.name}:{httpPort})',
          include: ['servers.host'],
        },
      },
      {
        key: 'serverLink', label: '操作', form: false, sortable: false, width: '7%',
        cell: { type: 'link', href: `${resourceApiPath('/servers')}?farm={id}`, text: '维护', target: '_self' },
      },
      { key: 'proxyOptions', label: '代理配置', type: 'textarea', column: false },
    ],
    // 服务是群集的从属资源（原 farm/form.ftl 的「服务配置」页签、farm/list.ftl 的「维护」链接）。
    drawerLinks: [{ label: '维护服务', to: `${resourceApiPath('/servers')}?farm={id}` }],
  },
  {
    key: 'servers',
    alias: 'server',
    path: '/servers',
    type: 'servers',
    title: '服务管理',
    group: '平台配置',
    description: '群集内运行在某台主机上的服务',
    sort: 'name',
    menu: false,
    filters: [{ key: 'farm', label: '群集', type: 'ref', ref: farmRef }, { key: 'host', label: '主机', type: 'ref', ref: hostRef }],
    fields: [
      { key: 'name', label: '名称', required: true },
      { key: 'farm', label: '群集', type: 'ref', ref: farmRef, required: true },
      { key: 'host', label: '主机', type: 'ref', ref: hostRef, required: true },
      { key: 'httpPort', label: 'HTTP 端口', type: 'number' },
      { key: 'maxHeapSize', label: '堆上限(MB)', type: 'number', help: '0 表示与群集一致' },
      { key: 'proxyHttpPort', label: '代理端口', type: 'number' },
      { key: 'proxyOptions', label: '代理', type: 'textarea', column: true },
    ],
  },
  {
    key: 'hosts',
    alias: 'host',
    path: '/hosts',
    type: 'hosts',
    title: '主机管理',
    group: '平台配置',
    description: '主机规格与操作系统特性',
    sort: 'name',
    filters: [{ key: 'name', label: '名称' }, { key: 'ip', label: 'IP' }, { key: 'profile', label: '配置', type: 'ref', ref: profileRef, required: true }],
    fields: [
      // 列标题与宽度对齐原 host/list.ftl：名称10% IP地址13% 操作系统12% 系统特性(auto) 内存8% 平台10% CPU核心8% CPU规格20%。
      { key: 'name', label: '名称', required: true, width: '10%', cell: { type: 'link', href: resourceApiPath('/hosts/{id}'), text: '{name}', target: '_self' } },
      { key: 'ip', label: 'IP', columnTitle: 'IP地址', required: true, width: '13%' },
      // 配置是查询条件里的必填项，列表列不再重复展示。
      { key: 'profile', label: '配置', type: 'ref', ref: profileRef, required: true, column: false },
      // 与原 host/list.ftl 一致：平台图标 + 名称(版本) 合成一列。
      {
        key: 'platform', label: '操作系统', type: 'ref', ref: platformRef, required: true, width: '12%',
        cell: { type: 'iconText', iconField: 'platform.fonticon', template: '{platform.name}({platformVersion})' },
      },
      // 后端 featureLogos 已按 support(platform) 过滤，只显示功能 logo（title 为功能名）。
      { key: 'featureLogos', label: '系统特性', form: false, sortable: false, cell: { type: 'icons', titleField: 'name' } },
      { key: 'platformVersion', label: '系统版本', required: true, column: false },
      // 列序与原 host/list.ftl 一致：系统特性 → 内存 → 平台 → CPU核心 → CPU规格。
      { key: 'memory', label: '内存', type: 'number', required: true, width: '8%', help: '单位：GB', cell: { type: 'text', suffix: 'GB' } },
      { key: 'arch', label: '体系结构', columnTitle: '平台', type: 'select', options: archOptions, required: true, width: '10%' },
      { key: 'cores', label: 'CPU 核心数', columnTitle: 'CPU核心', type: 'number', required: true, width: '8%' },
      { key: 'cpu', label: 'CPU 规格', columnTitle: 'CPU规格', required: true, width: '20%', cell: { type: 'text', style: 'font-size:0.8em' } },
      {
        key: 'setlineEnabled', label: '启用 Setline', type: 'radio', column: false,
        options: setlineEnabledOptions, defaultValue: 'no', virtual: true,
        deriveValue: (attributes) =>
          hasPortValue(attributes.setlineListenPort) && hasPortValue(attributes.setlineAdminPort) ? 'yes' : 'no',
        onChange: (value, form) => {
          if (value === 'yes') {
            form.setlineListenPort = 8080
            form.setlineAdminPort = 10080
          } else {
            form.setlineListenPort = null
            form.setlineAdminPort = null
          }
        },
        help: '启用前须为所属配置填写域名，路由组直接使用该域名；关闭会清空两个端口。已有 Webapp 把该主机上的服务作为运行目标时不能关闭',
      },
      {
        key: 'setlineListenPort', label: 'Setline 监听端口', type: 'number', column: false, nullable: true,
        min: 1, max: 65535, placeholder: '8080', requiredWhen: 'setlineEnabled', requiredWhenValue: 'yes',
        help: 'setline 数据面 listen 端口；agent 从 http://<IP>:<端口>/_setline/routes 拉取路由。它和 admin 端口必须同时配置',
      },
      {
        key: 'setlineAdminPort', label: 'Setline 管理口端口', type: 'number', column: false, nullable: true,
        min: 1, max: 65535, placeholder: '10080', requiredWhen: 'setlineEnabled', requiredWhenValue: 'yes',
        help: 'setline adminListen 端口；basctl 在本机连接 127.0.0.1:<端口> 推路由，不写入 server.xml',
      },
      { key: 'features', label: '系统特性', type: 'refs', ref: featureRef, column: false },
    ],
  },
  {
    key: 'artifacts',
    alias: 'artifact',
    path: '/artifacts',
    type: 'artifacts',
    title: '组件管理',
    group: '平台配置',
    description: '可部署的 jar/war 构件',
    sort: 'artifactId',
    tools: [
      {
        code: 'update-version', label: '刷新最新版本', action: 'update-version',
        selection: 'oneOrMore', theme: 'primary', confirm: '刷新所选组件的最新版本号？',
      },
    ],
    filters: [{ key: 'artifactId', label: 'artifactId' }, { key: 'groupId', label: 'groupId' }],
    // 列序对齐原 artifact/list.ftl：标题 → GAV → 部署上下文 → 面向平台 → 需要解析 → 容器要求。
    columns: ['title', 'gav', 'contextPath', 'arch', 'resolveSupport', 'container'],
    fields: [
      { key: 'title', label: '标题', required: true, width: '20%' },
      { key: 'artifactId', label: 'artifactId', required: true, column: false },
      { key: 'groupId', label: 'groupId', required: true, column: false },
      { key: 'packaging', label: '打包类型', type: 'select', required: true, column: false, options: ['jar', 'war', 'bin'].map((value) => ({ label: value, value })) },
      { key: 'classifier', label: '分类器', column: false },
      { key: 'arch', label: '面向平台', type: 'select', options: archOptions, width: '8%' },
      { key: 'latestVersion', label: '最新版本', required: true, column: false },
      { key: 'gav', label: 'GAV', form: false, sortable: false },
      { key: 'contextPath', label: '部署上下文', width: '15%' },
      { key: 'profile', label: '针对配置', type: 'ref', ref: profileRef, column: false },
      { key: 'description', label: '介绍', type: 'textarea', column: false },
      { key: 'resolveSupport', label: '需要解析', type: 'boolean', width: '8%' },
      {
        key: 'container', label: '容器要求', form: false, sortable: false, width: '8%',
        cell: { type: 'flags', fields: ['jspSupport', 'websocketSupport'], labels: { jspSupport: 'jsp', websocketSupport: 'websocket' } },
      },
      { key: 'jspSupport', label: 'JSP', type: 'boolean', column: false },
      { key: 'websocketSupport', label: 'WebSocket', type: 'boolean', column: false },
    ],
  },
  {
    key: 'webapps',
    alias: 'webapp',
    path: '/webapps',
    type: 'webapps',
    title: '应用部署',
    group: '平台配置',
    description: '把组件部署到配置下的若干服务',
    sort: 'contextPath',
    tools: [
      {
        code: 'upgrade', label: '升级到最新版', action: 'upgrade',
        selection: 'oneOrMore', theme: 'primary', confirm: '把所选应用升级到组件最新版本？',
      },
    ],
    filters: [
      { key: 'artifact.artifactId', label: '组件', filterKey: 'artifact.artifactId' },
      { key: 'version', label: '版本' },
      { key: 'profile', label: '配置', type: 'ref', ref: profileRef, required: true },
    ],
    fields: [
      { key: 'artifact', label: '标题', type: 'ref', ref: artifactRef, required: true, form: true, cell: { type: 'join', fields: ['artifact.title'] } },
      { key: 'artifactName', label: '名称', form: false, sortable: false, width: '21%', cell: { type: 'join', fields: ['artifact.artifactId'] } },
      // 配置是查询条件里的必填项，列表列不再重复展示。
      { key: 'profile', label: '配置', type: 'ref', ref: profileRef, required: true, column: false },
      { key: 'version', label: '版本', required: true, width: '12%', cell: { type: 'updatable' } },
      { key: 'contextPath', label: '上下文', required: true },
      { key: 'urls', label: '对外路径', type: 'lines', column: false, help: '一行一个 URL 前缀，反代与 setline 按它转发；留空按上下文。上下文为 / 而内部 URL 无公共前缀（如 /a、/b）时必须逐条列出' },
      { key: 'unpack', label: '解压执行', type: 'boolean' },
      { key: 'targets', label: '运行在', type: 'refs', ref: serverRef, help: '只能选择配置了 Setline 监听端口的主机上的服务' },
      { key: 'libs', label: '扩展库', column: false, help: 'gav 形式，分号或逗号分割' },
    ],
  },
  {
    key: 'platform-features',
    alias: 'platformFeature',
    path: '/platform-features',
    type: 'platformFeatures',
    title: '平台功能',
    group: '平台配置',
    description: '操作系统功能检查与安装脚本集合',
    sort: 'name',
    layout: 'cards',
    filters: [{ key: 'name', label: '名称' }],
    fields: [
      { key: 'name', label: '名称', required: true },
      { key: 'version', label: '版本', required: true },
      { key: 'logo', label: 'Logo', required: true, width: 90, cell: { type: 'image', width: 60, height: 60 } },
      { key: 'dependencies', label: '依赖', type: 'refs', ref: featureRef },
      { key: 'description', label: '描述', type: 'textarea', column: true },
    ],
    // 卡片点进详情页：功能自身与它的脚本就地维护（原 platformFeature/info.ftl，见 PlatformFeatureDetailView）。
    cardLink: resourceApiPath('/platform-features/{id}'),
  },
  {
    key: 'apps',
    alias: 'app',
    path: '/apps',
    type: 'apps',
    title: '应用管理',
    group: '应用与菜单',
    description: 'EMS 应用登记与依赖',
    sort: 'name',
    filters: [{ key: 'group', label: '分组', type: 'ref', ref: { path: '/app-groups', type: 'appGroups', labelFields: ['title'] } }, { key: 'name', label: '名称' }, { key: 'title', label: '标题' }],
    fields: [
      { key: 'name', label: '名称', required: true },
      { key: 'title', label: '标题', required: true },
      { key: 'group', label: '分组', type: 'ref', ref: { path: '/app-groups', type: 'appGroups', labelFields: ['title'] }, required: true },
      { key: 'artifactId', label: 'artifactId', required: true, column: false },
      { key: 'services', label: '依赖项' },
    ],
  },
  {
    key: 'channels',
    alias: 'channel',
    path: '/channels',
    type: 'channels',
    title: '应用端',
    group: '应用与菜单',
    description: '应用的部署上下文与嵌入方式',
    sort: 'base',
    filters: [
      { key: 'app', label: '应用', type: 'ref', ref: appRef, required: true },
      { key: 'channelType', label: '端类型', type: 'select', options: channelTypeOptions },
      { key: 'enabled', label: '状态', type: 'boolean' },
    ],
    fields: [
      { key: 'app', label: '应用', type: 'ref', ref: appRef, required: true, column: false },
      { key: 'base', label: '上下文地址', required: true },
      { key: 'channelType', label: '端类型', type: 'select', options: channelTypeOptions, required: true, width: 100 },
      { key: 'embedMode', label: '嵌入方式', type: 'select', options: embedModeOptions, required: true, width: 100 },
      { key: 'enabled', label: '启用', type: 'boolean', width: 80 },
    ],
  },
  {
    key: 'app-groups',
    alias: 'appGroup',
    path: '/app-groups',
    type: 'appGroups',
    title: '应用分组',
    group: '应用与菜单',
    description: 'EMS 应用分组',
    sort: 'name',
    filters: [{ key: 'name', label: '名称' }, { key: 'title', label: '标题' }],
    fields: [
      { key: 'name', label: '名称', required: true },
      { key: 'title', label: '标题', required: true },
    ],
  },
  {
    key: 'menus',
    alias: 'menu',
    path: '/menus',
    type: 'menus',
    title: '菜单管理',
    group: '应用与菜单',
    description: '应用的菜单树、入口与使用资源',
    sort: 'indexno',
    xmlTools: true,
    tree: true,
    filters: [
      { key: 'app', label: '应用', type: 'ref', ref: appRef, required: true },
      { key: 'indexno', label: '顺序号' },
      { key: 'name', label: '名称' },
      { key: 'enName', label: '英文名' },
      { key: 'entry.name', label: '入口资源', filterKey: 'entry.name' },
      { key: 'enabled', label: '状态', type: 'boolean' },
    ],
    fields: [
      { key: 'app', label: '应用', type: 'ref', ref: appRef, required: true, column: false },
      { key: 'name', label: '名称', required: true, width: 200 },
      { key: 'enName', label: '英文名称', required: true },
      { key: 'indexno', label: '顺序号', type: 'number', required: true, width: 100 },
      { key: 'parent', label: '上级菜单', type: 'ref', ref: { path: '/menus', type: 'menus', labelFields: ['name'] }, column: false },
      { key: 'fonticon', label: '字体图标', column: false },
      { key: 'entry', label: '入口资源', type: 'ref', ref: resourceRef, column: false },
      // 只显示资源标题：资源的 name 是权限名（形如 /setting/config.action），原 menu/list.ftl 也只列 title。
      { key: 'resources', label: '使用资源', type: 'refs', ref: resourceRef, cell: { type: 'join', fields: ['resources.title'] } },
      { key: 'params', label: '参数', column: false, help: '不要以 ? 或 & 开头' },
      { key: 'enabled', label: '启用', type: 'boolean', width: 80 },
      // 入口地址 = 入口资源的权限名 + 参数（原 menu/list.ftl 的「入口及备注」提示里的入口部分）。
      { key: 'entryUrl', label: '入口地址', form: false, sortable: false, width: '26%', cell: { type: 'join', fields: ['entry.name', 'params'], separator: '?' } },
      { key: 'remark', label: '备注', type: 'textarea', column: false },
    ],
  },
  {
    key: 'resources',
    alias: 'resource',
    path: '/resources',
    type: 'resources',
    title: '资源管理',
    group: '应用与菜单',
    description: '应用的权限资源',
    sort: 'name',
    exportable: true,
    filters: [{ key: 'app', label: '应用', type: 'ref', ref: appRef }, { key: 'name', label: '名称' }, { key: 'scope', label: '范围', type: 'select', options: scopeOptions }],
    fields: [
      { key: 'app', label: '应用', type: 'ref', ref: appRef, required: true },
      { key: 'name', label: '名称', required: true },
      { key: 'title', label: '标题', required: true },
      {
        key: 'scope', label: '范围', type: 'select', options: scopeOptions,
      },
      { key: 'actions', label: '动作', column: false },
      { key: 'enabled', label: '启用', type: 'boolean' },
      { key: 'remark', label: '备注', type: 'textarea', column: true },
    ],
  },
]

/**
 * 页签合成页：资源仍按能力域提供独立 API，但页面保持原有页签组织方式。
 * 组路径带能力域前缀，旧的无域路径不再注册。
 */
export const resourceTabGroups: ResourceTabGroup[] = [
  {
    key: 'org-config',
    path: apiPath('config', '/org-config'),
    title: '配置与机构',
    group: '平台配置',
    description: '机构及其部署配置',
    tabs: [
      { key: 'profiles', label: '配置管理' },
      { key: 'organizations', label: '机构管理' },
    ],
  },
  {
    key: 'platform-ops',
    path: apiPath('config', '/platform-ops'),
    title: '平台与功能',
    group: '平台配置',
    description: '操作系统平台及其功能脚本',
    tabs: [
      { key: 'platform-features', label: '平台功能' },
      { key: 'platforms', label: '平台管理' },
    ],
  },
  {
    key: 'farm-hosts',
    path: apiPath('config', '/farm-hosts'),
    title: '群集与主机',
    group: '平台配置',
    description: '配置下的群集与运行主机',
    tabs: [
      { key: 'farms', label: '群集管理' },
      { key: 'hosts', label: '主机管理' },
    ],
  },
  {
    key: 'app-config',
    path: apiPath('ems', '/app-config'),
    title: '应用配置',
    group: '应用与菜单',
    description: 'EMS 应用、端与分组',
    tabs: [
      { key: 'apps', label: '应用管理' },
      { key: 'channels', label: '应用端' },
      { key: 'app-groups', label: '应用分组' },
    ],
  },
  {
    key: 'menu-config',
    path: apiPath('ems', '/menu-config'),
    title: '菜单与资源',
    group: '应用与菜单',
    description: '应用的菜单树与权限资源',
    tabs: [
      { key: 'menus', label: '菜单管理' },
      { key: 'resources', label: '资源管理' },
    ],
  },
]

export const schemaByKey: Map<string, ResourceSchema> = new Map(resourceSchemas.map((schema) => [schema.key, schema]))

export function getSchema(key: string): ResourceSchema {
  const schema = schemaByKey.get(key)
  if (!schema) throw new Error(`未定义的资源：${key}`)
  return schema
}

export function getTabGroup(key: string): ResourceTabGroup {
  const group = resourceTabGroups.find((item) => item.key === key)
  if (!group) throw new Error(`未定义的页签组：${key}`)
  return group
}

export const resourceGroups: string[] = [...new Set(resourceSchemas.map((schema) => schema.group))]
