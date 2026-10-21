<template>
  <section class="page-panel">
    <div class="page-head">
      <div class="detail-heading">
        <div class="detail-heading__title">
          <h2 class="page-title">{{ profileName || '配置详情' }}</h2>
          <p class="page-subtitle">
            <span v-if="profileTitle">{{ profileTitle }} · </span>
            <code v-if="qualifiedName">{{ qualifiedName }}</code>
            <span v-if="basVersion"> · BAS {{ basVersion }}</span>
          </p>
          <router-link class="detail-back" to="/config/org-config?tab=profiles">← 返回配置管理</router-link>
        </div>
      </div>
    </div>

    <t-alert v-if="loadError" theme="error" :message="loadError" class="page-alert" />
    <t-alert
      v-if="warningList.length > 0"
      theme="warning"
      :message="warningList.join('；')"
      class="page-alert"
    />

    <t-loading :loading="loading" show-overlay>
      <div v-if="profile" class="profile-detail">
        <aside class="profile-nav">
          <div class="profile-nav__title">配置内容</div>
          <button
            v-for="item in sectionItems"
            :key="item.key"
            type="button"
            class="profile-nav__item"
            :class="{ 'profile-nav__item--active': activeSection === item.key }"
            :title="item.hint"
            @click="selectSection(item.key)"
          >
            <component :is="item.icon" class="profile-nav__icon" />
            <span>{{ item.label }}</span>
          </button>
          <div class="profile-nav__footer">
            <span>Profile key</span>
            <strong :class="{ 'text-warning': !keyConfigured }">{{ keyConfigured ? '已设置' : '未设置' }}</strong>
          </div>
        </aside>

        <main class="profile-main">
          <header class="section-head">
            <div>
              <h3>{{ activeSectionMeta?.label }}</h3>
              <p>{{ activeSectionMeta?.hint }}</p>
            </div>
          </header>

          <div v-if="activeSection === 'overview'" class="detail-stack">
            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>Profile 基本资料</h4>
                  <p>配置的归属、访问入口与运行版本。</p>
                </div>
                <div class="tag-row">
                  <t-tag v-if="enableHttps" theme="success" variant="light">HTTPS</t-tag>
                  <t-tag :theme="keyConfigured ? 'success' : 'warning'" variant="light">
                    {{ keyConfigured ? 'Key 已设置' : 'Key 未设置' }}
                  </t-tag>
                </div>
              </header>
              <div class="fact-grid">
                <div class="fact">
                  <span>名称</span>
                  <strong>{{ qualifiedName || '—' }}</strong>
                </div>
                <div class="fact">
                  <span>说明</span>
                  <strong>{{ profileTitle || '—' }}</strong>
                </div>
                <div class="fact">
                  <span>机构</span>
                  <strong>{{ organizationText || '—' }}</strong>
                </div>
                <div class="fact">
                  <span>BAS 版本</span>
                  <strong>{{ basVersion || '—' }}</strong>
                </div>
                <div class="fact">
                  <span>入口地址</span>
                  <strong>{{ hostname || ip || '—' }}</strong>
                </div>
                <div class="fact">
                  <span>HTTP / HTTPS</span>
                  <strong>{{ httpPort || '—' }} / {{ enableHttps ? (httpsPort || '—') : '未启用' }}</strong>
                </div>
                <div class="fact">
                  <span>代理引擎</span>
                  <strong>{{ proxyEngineLabel }}</strong>
                </div>
              </div>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>部署概况</h4>
                  <p>来自当前 Profile 的群集、主机、应用与在线节点。</p>
                </div>
              </header>
              <div class="stat-grid">
                <div class="stat"><span>群集</span><strong>{{ farms.length }}</strong></div>
                <div class="stat"><span>服务</span><strong>{{ servers.length }}</strong></div>
                <div class="stat"><span>主机</span><strong>{{ hosts.length }}</strong></div>
                <div class="stat"><span>应用</span><strong>{{ webapps.length }}</strong></div>
                <div class="stat"><span>在线节点</span><strong>{{ onlineAgents.length }}</strong></div>
                <div class="stat"><span>运行实例</span><strong>{{ runningInstanceCount }}</strong></div>
              </div>
            </article>
          </div>

          <div v-else-if="activeSection === 'proxy'" class="detail-stack">
            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>{{ proxyEngineLabel }} 入口</h4>
                  <p>负载均衡器监听、TLS 与连接数设置。</p>
                </div>
                <t-tag :theme="proxyConfig ? 'success' : 'default'" variant="light">
                  {{ proxyConfig ? '配置已生成' : '未生成配置' }}
                </t-tag>
              </header>
              <div class="fact-grid">
                <div class="fact"><span>引擎</span><strong>{{ proxyEngineLabel }}</strong></div>
                <div class="fact"><span>HTTP 端口</span><strong>{{ httpPort || '—' }}</strong></div>
                <div class="fact"><span>HTTPS</span><strong>{{ enableHttps ? '已启用' : '未启用' }}</strong></div>
                <div class="fact"><span>HTTPS 端口</span><strong>{{ enableHttps ? (httpsPort || '—') : '—' }}</strong></div>
                <div class="fact"><span>强制 HTTPS</span><strong>{{ forceHttps ? '是' : '否' }}</strong></div>
                <div class="fact"><span>最大连接数</span><strong>{{ maxconn || '默认' }}</strong></div>
              </div>
              <div class="detail-note">
                下载到服务器的代理配置按该 Profile 下的群集、服务、主机与 setline 路由渲染；修改 Profile 后重新生成。
              </div>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>{{ proxyEngineLabel }} 配置预览</h4>
                  <p>与管理台查看端点一致，内容只读。</p>
                </div>
                <div class="detail-card__actions">
                  <t-button size="small" variant="outline" :disabled="!proxyConfig" @click="copyText(proxyConfig, '代理配置')">
                    <template #icon><CopyIcon /></template>
                    复制
                  </t-button>
                </div>
              </header>
              <p v-if="warnings.proxy" class="load-error">{{ warnings.proxy }}</p>
              <pre v-else-if="proxyConfig" class="config-preview">{{ proxyConfig }}</pre>
              <p v-else class="empty-text">当前 Profile 没有可生成的代理配置。</p>
            </article>
          </div>

          <div v-else-if="activeSection === 'setline'" class="detail-stack">
            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>Setline Peers</h4>
                  <p>setline 从这里读取 web 节点与 micdn 节点的路由表。</p>
                </div>
              </header>
              <p v-if="warnings.peers" class="load-error">{{ warnings.peers }}</p>
              <table v-else-if="setlinePeers.length > 0" class="detail-table">
                <thead>
                  <tr><th>名称</th><th>地址</th></tr>
                </thead>
                <tbody>
                  <tr v-for="peer in setlinePeers" :key="`${peer.name}|${peer.url}`">
                    <td>{{ peer.name }}</td>
                    <td><code>{{ peer.url }}</code></td>
                  </tr>
                </tbody>
              </table>
              <p v-else class="empty-text">当前没有 peer。请为 Profile 添加主机或 Micdn 服务器。</p>
            </article>
          </div>

          <div v-else-if="activeSection === 'certificate'" class="detail-stack">
            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>HTTPS 与证书状态</h4>
                  <p>管理台只展示公钥证书，私钥永远不会下发到浏览器。</p>
                </div>
                <t-tag :theme="enableHttps ? 'success' : 'default'" variant="light">
                  {{ enableHttps ? 'HTTPS 已启用' : 'HTTPS 未启用' }}
                </t-tag>
              </header>
              <div class="fact-grid">
                <div class="fact"><span>HTTPS 端口</span><strong>{{ enableHttps ? (httpsPort || '—') : '—' }}</strong></div>
                <div class="fact"><span>强制 HTTPS</span><strong>{{ forceHttps ? '是' : '否' }}</strong></div>
                <div class="fact"><span>SSL 协议</span><strong>{{ sslProtocols || '代理默认' }}</strong></div>
                <div class="fact"><span>SSL 加密套件</span><strong>{{ sslCiphers || '代理默认' }}</strong></div>
                <div class="fact"><span>公钥证书</span><strong>{{ certificateText ? '已设置' : '未设置' }}</strong></div>
                <div class="fact"><span>私钥</span><strong>{{ privateKeySet ? '已设置' : '未设置' }}</strong></div>
              </div>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>公钥证书</h4>
                  <p>nginx 使用完整证书链（fullchain）时可直接作为 ssl_certificate。</p>
                </div>
                <div class="detail-card__actions">
                  <t-button size="small" variant="outline" :disabled="!certificateText" @click="copyText(certificateText, '公钥证书')">
                    <template #icon><CopyIcon /></template>
                    复制
                  </t-button>
                </div>
              </header>
              <pre v-if="certificateText" class="config-preview config-preview--certificate">{{ certificateText }}</pre>
              <p v-else class="empty-text">当前 Profile 没有设置公钥证书。</p>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>私钥保护</h4>
                  <p>配置下载端点使用 Profile key 鉴权，私钥只交给 setline 等受信组件。</p>
                </div>
                <t-tag :theme="privateKeySet ? 'success' : 'warning'" variant="light">
                  {{ privateKeySet ? '已设置' : '未设置' }}
                </t-tag>
              </header>
              <div class="detail-note">管理台不展示私钥内容，也不会通过 JSON:API 返回私钥原文。</div>
            </article>
          </div>

          <div v-else-if="activeSection === 'bas'" class="detail-stack">
            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>BAS 资源</h4>
                  <p>server.xml 渲染所依据的部署对象与在线实例。</p>
                </div>
              </header>
              <div class="stat-grid">
                <div class="stat"><span>群集</span><strong>{{ farms.length }}</strong></div>
                <div class="stat"><span>服务</span><strong>{{ servers.length }}</strong></div>
                <div class="stat"><span>主机</span><strong>{{ hosts.length }}</strong></div>
                <div class="stat"><span>应用</span><strong>{{ webapps.length }}</strong></div>
                <div class="stat"><span>运行实例</span><strong>{{ runningInstanceCount }}</strong></div>
                <div class="stat"><span>停止实例</span><strong>{{ stoppedInstanceCount }}</strong></div>
              </div>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>在线节点与实例</h4>
                  <p>只显示 profile 与当前配置一致的 basctl agent。</p>
                </div>
                <router-link class="card-link" to="/monitor/agents">在线节点</router-link>
              </header>
              <p v-if="warnings.agents" class="load-error">{{ warnings.agents }}</p>
              <table v-else-if="instanceRows.length > 0" class="detail-table">
                <thead>
                  <tr><th>节点</th><th>实例</th><th>状态</th><th>端口</th><th>引擎</th></tr>
                </thead>
                <tbody>
                  <tr v-for="row in instanceRows" :key="`${row.agent.profile}|${row.instance.id || row.instance.pid}`">
                    <td>{{ row.agent.host || row.agent.profile }}</td>
                    <td>{{ row.instance.id || '—' }}</td>
                    <td>
                      <t-tag size="small" :theme="row.running ? 'success' : 'warning'" variant="light">
                        {{ row.running ? '运行中' : '已停止' }}
                      </t-tag>
                    </td>
                    <td>{{ row.instance.httpPort || '—' }}</td>
                    <td>{{ row.instance.engine || '—' }}</td>
                  </tr>
                </tbody>
              </table>
              <p v-else class="empty-text">当前没有匹配的在线节点或已声明实例。</p>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>群集与服务</h4>
                  <p>每个服务所属群集、主机与监听端口。</p>
                </div>
              </header>
              <p v-if="warnings.farms || warnings.servers" class="load-error">{{ warnings.farms || warnings.servers }}</p>
              <table v-else-if="serverRows.length > 0" class="detail-table">
                <thead>
                  <tr><th>服务</th><th>群集</th><th>主机</th><th>HTTP</th><th>代理端口</th><th>堆上限</th></tr>
                </thead>
                <tbody>
                  <tr v-for="server in serverRows" :key="server.id">
                    <td>{{ attrOf(server, 'name') || '—' }}</td>
                    <td>{{ relatedName(server) }}</td>
                    <td>{{ hostLabel(server) }}</td>
                    <td>{{ attrOf(server, 'httpPort') || '—' }}</td>
                    <td>{{ attrOf(server, 'proxyHttpPort') || '—' }}</td>
                    <td>{{ heapText(server) }}</td>
                  </tr>
                </tbody>
              </table>
              <p v-else class="empty-text">当前 Profile 还没有服务。</p>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>已部署应用</h4>
                  <p>按上下文路径列出的 webapp 与构件版本。</p>
                </div>
              </header>
              <p v-if="warnings.webapps" class="load-error">{{ warnings.webapps }}</p>
              <table v-else-if="webappRows.length > 0" class="detail-table">
                <thead>
                  <tr><th>上下文</th><th>应用</th><th>GAV</th></tr>
                </thead>
                <tbody>
                  <tr v-for="webapp in webappRows" :key="webapp.id">
                    <td><code>{{ attrOf(webapp, 'contextPath') || '/' }}</code></td>
                    <td>{{ webappTitle(webapp) }}</td>
                    <td><code>{{ attrOf(webapp, 'gav') || '—' }}</code></td>
                  </tr>
                </tbody>
              </table>
              <p v-else class="empty-text">当前 Profile 还没有部署应用。</p>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>server.xml</h4>
                  <p>basctl 从该 Profile 拉取并执行的最终配置。</p>
                </div>
                <div class="detail-card__actions">
                  <t-button size="small" variant="outline" :disabled="!serverConfig" @click="copyText(serverConfig, 'server.xml')">
                    <template #icon><CopyIcon /></template>
                    复制
                  </t-button>
                </div>
              </header>
              <p v-if="warnings.server" class="load-error">{{ warnings.server }}</p>
              <pre v-else-if="serverConfig" class="config-preview">{{ serverConfig }}</pre>
              <p v-else class="empty-text">当前 Profile 没有可生成的 server.xml。</p>
            </article>
          </div>

          <div v-else class="detail-stack">
            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>Micdn 运行配置</h4>
                  <p>Profile 是 micdn 配置与组件绑定的中心。</p>
                </div>
                <div class="detail-card__actions">
                  <t-button size="small" theme="primary" @click="openMicdn">编辑配置</t-button>
                </div>
              </header>
              <p v-if="warnings.micdn" class="load-error">{{ warnings.micdn }}</p>
              <div v-else-if="micdn" class="fact-grid">
                <div class="fact"><span>监听地址</span><strong>{{ micdn.config.listen || '—' }}</strong></div>
                <div class="fact"><span>Home</span><strong>{{ micdn.config.home || 'XML 所在目录' }}</strong></div>
                <div class="fact"><span>日志</span><strong>{{ micdn.config.logFile || 'console' }} · {{ micdn.config.logLevel || 'info' }}</strong></div>
                <div class="fact"><span>Micdn 服务器</span><strong>{{ micdnServers.length }}</strong></div>
                <div class="fact"><span>Static 绑定</span><strong>{{ staticBindings.length }}</strong></div>
                <div class="fact"><span>WWW 绑定</span><strong>{{ wwwBindings.length }}</strong></div>
              </div>
              <p v-else class="empty-text">尚未加载 Micdn 配置。</p>
            </article>

            <article v-if="micdn" class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>静态资源挂载</h4>
                  <p>挂载名来自组件目录，bundle 与文档按挂载名稳定排序。</p>
                </div>
              </header>
              <div class="mount-columns">
                <section class="mount-group">
                  <h5>Static <span>{{ staticBindings.length }}</span></h5>
                  <div v-if="staticBindings.length > 0" class="mount-list">
                    <div v-for="binding in staticBindings" :key="binding.componentId" class="mount-item">
                      <code>/static/{{ binding.mountName }}/</code>
                      <span>{{ binding.name }}</span>
                    </div>
                  </div>
                  <p v-else class="empty-text">没有 static 绑定。</p>
                </section>
                <section class="mount-group">
                  <h5>WWW <span>{{ wwwBindings.length }}</span></h5>
                  <div v-if="wwwBindings.length > 0" class="mount-list">
                    <div v-for="binding in wwwBindings" :key="binding.componentId" class="mount-item">
                      <code>/{{ binding.mountName }}/</code>
                      <span>{{ binding.name }}</span>
                    </div>
                  </div>
                  <p v-else class="empty-text">没有 www 绑定。</p>
                </section>
              </div>
            </article>

            <article v-if="micdn" class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>仓库与 Blob</h4>
                  <p>仓库是否声明，以及 Blob 的 bucket 归属。</p>
                </div>
              </header>
              <div class="fact-grid">
                <div class="fact"><span>Maven</span><strong>{{ micdn.config.maven.declared ? '已启用' : '未启用' }}</strong></div>
                <div class="fact"><span>NPM</span><strong>{{ micdn.config.npm.declared ? '已启用' : '未启用' }}</strong></div>
                <div class="fact"><span>Native</span><strong>{{ micdn.config.native.declared ? '已启用' : '未启用' }}</strong></div>
                <div class="fact"><span>Blob</span><strong>{{ micdn.profile.keySet ? '已启用' : '未启用' }}</strong></div>
                <div class="fact"><span>Bucket</span><strong>{{ micdn.profile.name || '—' }}</strong></div>
                <div class="fact"><span>Bucket Key</span><strong>{{ micdn.profile.keySet ? micdn.profile.keyMasked : '未设置' }}</strong></div>
              </div>
            </article>

            <article v-if="micdn" class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>Micdn 节点</h4>
                  <p>这些 adminListen 同时会进入 setline peers。</p>
                </div>
              </header>
              <table v-if="micdnServers.length > 0" class="detail-table">
                <thead>
                  <tr><th>名称</th><th>Setline adminListen</th></tr>
                </thead>
                <tbody>
                  <tr v-for="server in micdnServers" :key="`${server.name}|${server.adminListen}`">
                    <td>{{ server.name }}</td>
                    <td><code>{{ server.adminListen }}</code></td>
                  </tr>
                </tbody>
              </table>
              <p v-else class="empty-text">尚未登记 Micdn 服务器。</p>
            </article>
          </div>
        </main>
      </div>
      <t-empty v-else-if="!loading" description="未找到配置" />
    </t-loading>
  </section>
</template>

<script setup lang="ts">
import {
  CertificateIcon,
  CloudIcon,
  CopyIcon,
  DashboardIcon,
  InternetIcon,
  LinkIcon,
  ServerIcon,
} from 'tdesign-icons-vue-next'
import { MessagePlugin } from 'tdesign-vue-next'
import { computed, onMounted, reactive, ref, watch, type Component } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { listAgents, type AgentInstance, type AgentStatus } from '@/api/agents'
import { getMicdnProfile, type MicdnBinding, type MicdnProfileDocument } from '@/api/micdn'
import { readProfileConfig, readSetlinePeers, type SetlinePeer } from '@/api/profile-detail'
import {
  attributeText,
  getResourceDetail,
  indexIncluded,
  listResource,
  relationshipIds,
  type ResourceRow,
} from '@/api/resource'

const PROFILES_PATH = '/profiles'

type SectionKey = 'overview' | 'proxy' | 'setline' | 'certificate' | 'bas' | 'micdn'

interface SectionItem {
  key: SectionKey
  label: string
  hint: string
  icon: Component
}

interface InstanceRow {
  agent: AgentStatus
  instance: AgentInstance
  running: boolean
}

const sectionItems: SectionItem[] = [
  { key: 'overview', label: '概览', hint: 'Profile 的归属、版本与部署概况', icon: DashboardIcon },
  { key: 'proxy', label: 'Haproxy / Nginx', hint: '负载均衡监听与渲染后的代理配置', icon: InternetIcon },
  { key: 'setline', label: 'Setline', hint: 'setline 的 peer 列表与路由来源', icon: LinkIcon },
  { key: 'certificate', label: '证书', hint: 'HTTPS、公钥证书与私钥保护', icon: CertificateIcon },
  { key: 'bas', label: 'BAS 服务', hint: '群集、服务、应用、在线实例与 server.xml', icon: ServerIcon },
  { key: 'micdn', label: 'Micdn', hint: '静态挂载、仓库、Blob 与 Micdn 节点', icon: CloudIcon },
]

const route = useRoute()
const router = useRouter()
const profileId = String(route.params.id || '')

const profile = ref<ResourceRow>()
const included = ref<Map<string, ResourceRow>>(new Map())
const farms = ref<ResourceRow[]>([])
const servers = ref<ResourceRow[]>([])
const hosts = ref<ResourceRow[]>([])
const webapps = ref<ResourceRow[]>([])
const agents = ref<AgentStatus[]>([])
const proxyConfig = ref('')
const serverConfig = ref('')
const setlinePeers = ref<SetlinePeer[]>([])
const micdn = ref<MicdnProfileDocument>()
const loading = ref(false)
const loadError = ref('')
const warnings = reactive<Record<string, string>>({})
const activeSection = ref<SectionKey>(initialSection())

const organization = computed(() => related(profile.value, 'org', 'organizations'))
const organizationName = computed(() => attrOf(organization.value, 'name'))
const name = computed(() => attrOf(profile.value, 'name'))
const qualifiedName = computed(() => attrOf(profile.value, 'qualifiedName') || [organizationName.value, name.value].filter(Boolean).join('.'))
const profileName = computed(() => qualifiedName.value || name.value)
const profileTitle = computed(() => attrOf(profile.value, 'title'))
const basVersion = computed(() => attrOf(profile.value, 'basVersion'))
const ip = computed(() => attrOf(profile.value, 'ip'))
const hostname = computed(() => attrOf(profile.value, 'hostname'))
const httpPort = computed(() => attrOf(profile.value, 'httpPort'))
const httpsPort = computed(() => attrOf(profile.value, 'httpsPort'))
const enableHttps = computed(() => boolOf(profile.value?.attributes.enableHttps))
const forceHttps = computed(() => boolOf(profile.value?.attributes.forceHttps))
const maxconn = computed(() => attrOf(profile.value, 'maxconn'))
const proxyEngine = computed(() => attrOf(profile.value, 'proxyEngine'))
const proxyEngineLabel = computed(() => {
  if (proxyEngine.value === 'haproxy') return 'HAProxy'
  if (proxyEngine.value === 'nginx') return 'Nginx'
  return proxyEngine.value || '未设置'
})
const sslProtocols = computed(() => attrOf(profile.value, 'sslProtocols'))
const sslCiphers = computed(() => attrOf(profile.value, 'sslCiphers'))
const certificateText = computed(() => attrOf(profile.value, 'sslCertificate'))
const privateKeySet = computed(() => boolOf(profile.value?.attributes.sslCertificateKeySet))
const keyConfigured = computed(() => Boolean(attrOf(profile.value, 'key')) || micdn.value?.profile.keySet === true)
const organizationText = computed(() => {
  const orgTitle = attrOf(organization.value, 'title')
  return [organizationName.value, orgTitle].filter(Boolean).join(' · ')
})

const onlineAgents = computed(() =>
  agents.value.filter((agent) => agent.profile === qualifiedName.value || agent.profile === name.value),
)
const instanceRows = computed<InstanceRow[]>(() =>
  onlineAgents.value
    .flatMap((agent) => instancesOf(agent).map((instance) => ({ agent, instance, running: isRunning(instance) })))
    .sort((a, b) => (a.agent.host || a.agent.profile).localeCompare(b.agent.host || b.agent.profile)),
)
const runningInstanceCount = computed(() => instanceRows.value.filter((row) => row.running).length)
const stoppedInstanceCount = computed(() => instanceRows.value.filter((row) => !row.running).length)

const serverRows = computed(() =>
  [...servers.value].sort((a, b) => attrOf(a, 'name').localeCompare(attrOf(b, 'name'))),
)
const webappRows = computed(() =>
  [...webapps.value].sort((a, b) => attrOf(a, 'contextPath').localeCompare(attrOf(b, 'contextPath'))),
)
const staticBindings = computed(() => bindingsOf('static_bundle'))
const wwwBindings = computed(() => bindingsOf('www_doc'))
const micdnServers = computed(() =>
  [...(micdn.value?.config.servers ?? [])].sort((a, b) => a.name.localeCompare(b.name)),
)
const warningList = computed(() => Object.values(warnings).filter(Boolean))
const activeSectionMeta = computed(() => sectionItems.find((item) => item.key === activeSection.value))

function initialSection(): SectionKey {
  const value = route.query.section
  const key = String(Array.isArray(value) ? value[0] : value || '')
  return sectionItems.some((item) => item.key === key) ? (key as SectionKey) : 'overview'
}

function selectSection(key: SectionKey) {
  activeSection.value = key
}

watch(activeSection, (value) => {
  if (route.query.section === value) return
  void router.replace({ path: route.path, query: { ...route.query, section: value } })
})

function openMicdn() {
  void router.push(`/micdn/profiles/${profileId}`)
}

function attrOf(row: ResourceRow | undefined, key: string): string {
  return attributeText(row?.attributes[key])
}

function boolOf(value: unknown): boolean {
  return value === true || value === 'true' || value === 1 || value === '1'
}

function related(row: ResourceRow | undefined, key: string, type: string): ResourceRow | undefined {
  const id = relationshipIds(row, key)[0]
  return id ? included.value.get(`${type}:${id}`) : undefined
}

function relatedName(server: ResourceRow): string {
  return attrOf(related(server, 'farm', 'farms'), 'name') || '—'
}

function hostLabel(server: ResourceRow): string {
  const host = related(server, 'host', 'hosts')
  const hostName = attrOf(host, 'name')
  const hostIp = attrOf(host, 'ip')
  return [hostName, hostIp].filter(Boolean).join(' · ') || '—'
}

function heapText(server: ResourceRow): string {
  const own = attrOf(server, 'maxHeapSize')
  if (own) return own
  const farmHeap = attrOf(related(server, 'farm', 'farms'), 'maxHeapSize')
  return farmHeap ? `${farmHeap}（群集）` : '—'
}

function webappTitle(webapp: ResourceRow): string {
  const artifact = related(webapp, 'artifact', 'artifacts')
  return attrOf(artifact, 'title') || attrOf(artifact, 'artifactId') || '—'
}

function bindingsOf(kind: 'static_bundle' | 'www_doc'): MicdnBinding[] {
  return (micdn.value?.bindings ?? [])
    .filter((binding) => binding.kind === kind)
    .sort((a, b) => a.mountName.localeCompare(b.mountName))
}

function instancesOf(agent: AgentStatus): AgentInstance[] {
  const running = agent.basReport?.instances ?? []
  const declared = agent.basReport?.declared ?? []
  const runningById = new Map<string, AgentInstance>()
  for (const instance of running) {
    if (instance.id) runningById.set(instance.id, instance)
  }

  const merged: AgentInstance[] = []
  for (const instance of declared) {
    const live = instance.id ? runningById.get(instance.id) : undefined
    if (live) {
      merged.push({ ...live, state: 'running' })
      if (instance.id) runningById.delete(instance.id)
    } else {
      merged.push({ ...instance, state: 'stopped' })
    }
  }
  for (const instance of running) {
    if (!instance.id || runningById.has(instance.id)) merged.push({ ...instance, state: 'running' })
  }
  return merged
}

function isRunning(instance: AgentInstance): boolean {
  return instance.state !== 'stopped'
}

function warning(key: string, label: string, reason: unknown) {
  warnings[key] = `${label}加载失败：${errorText(reason)}`
}

function errorText(reason: unknown): string {
  return reason instanceof Error ? reason.message : String(reason)
}

async function copyText(value: string, label: string) {
  if (!value) return
  try {
    await navigator.clipboard.writeText(value)
    MessagePlugin.success(`已复制${label}`)
  } catch (error) {
    MessagePlugin.error(errorText(error) || '复制失败，请检查浏览器剪贴板权限')
  }
}

async function load() {
  loading.value = true
  loadError.value = ''
  Object.keys(warnings).forEach((key) => delete warnings[key])

  let detail: Awaited<ReturnType<typeof getResourceDetail>>
  try {
    detail = await getResourceDetail(PROFILES_PATH, profileId, ['org'])
  } catch (error) {
    loadError.value = `加载 Profile 失败：${errorText(error)}`
    loading.value = false
    return
  }

  profile.value = detail.row
  const includedRows = [...detail.included]

  const [farmsResult, hostsResult, webappsResult, agentsResult, proxyResult, serverResult, peersResult, micdnResult] =
    await Promise.allSettled([
      listResource('/farms', {
        filters: { 'farm.profile.id': profileId },
        include: ['engine'],
        pageSize: 500,
      }),
      listResource('/hosts', {
        filters: { 'host.profile.id': profileId },
        pageSize: 500,
      }),
      listResource('/webapps', {
        filters: { 'webapp.profile.id': profileId },
        include: ['artifact'],
        pageSize: 1000,
      }),
      listAgents(),
      readProfileConfig(profileId, 'proxy'),
      readProfileConfig(profileId, 'server'),
      readSetlinePeers(profileId),
      getMicdnProfile(profileId),
    ])

  if (farmsResult.status === 'fulfilled') {
    farms.value = farmsResult.value.rows
    includedRows.push(...farmsResult.value.included)
  } else {
    warning('farms', '群集', farmsResult.reason)
  }

  if (hostsResult.status === 'fulfilled') {
    hosts.value = hostsResult.value.rows
    includedRows.push(...hostsResult.value.included)
  } else {
    warning('hosts', '主机', hostsResult.reason)
  }

  if (webappsResult.status === 'fulfilled') {
    webapps.value = webappsResult.value.rows
    includedRows.push(...webappsResult.value.included)
  } else {
    warning('webapps', '应用', webappsResult.reason)
  }

  if (agentsResult.status === 'fulfilled') agents.value = agentsResult.value
  else warning('agents', '在线节点', agentsResult.reason)

  if (proxyResult.status === 'fulfilled') proxyConfig.value = proxyResult.value
  else warning('proxy', '代理配置', proxyResult.reason)

  if (serverResult.status === 'fulfilled') serverConfig.value = serverResult.value
  else warning('server', 'server.xml', serverResult.reason)

  if (peersResult.status === 'fulfilled') setlinePeers.value = peersResult.value
  else warning('peers', 'Setline peers', peersResult.reason)

  if (micdnResult.status === 'fulfilled') micdn.value = micdnResult.value
  else warning('micdn', 'Micdn 配置', micdnResult.reason)

  const farmIds = farms.value.map((farm) => farm.id)
  if (farmIds.length > 0) {
    try {
      const serverPage = await listResource('/servers', {
        filters: { 'server.farm.id': farmIds.join(',') },
        include: ['farm', 'host'],
        pageSize: 1000,
      })
      servers.value = serverPage.rows
      includedRows.push(...serverPage.included)
    } catch (error) {
      warning('servers', '服务', error)
    }
  } else {
    servers.value = []
  }

  included.value = indexIncluded(includedRows)
  loading.value = false
}

onMounted(load)
</script>

<style scoped>
.detail-heading {
  width: 100%;
  min-width: 0;
}

.detail-heading__title {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 12px;
}

.detail-back {
  flex: none;
  margin-left: auto;
  padding: 4px 8px;
  border-radius: 4px;
  color: var(--td-text-color-secondary);
  font-size: 13px;
  text-decoration: none;
}

.detail-back:hover {
  background: var(--td-bg-color-container-hover);
  color: var(--td-brand-color);
}

.detail-card__actions,
.tag-row {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.page-alert {
  margin-bottom: 12px;
}

.profile-detail {
  display: grid;
  grid-template-columns: 198px minmax(0, 1fr);
  align-items: start;
  gap: 16px;
}

.profile-nav {
  position: sticky;
  top: 16px;
  padding: 7px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container);
}

.profile-nav__title {
  padding: 7px 10px 9px;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
  font-weight: 500;
}

.profile-nav__item {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 8px;
  padding: 9px 10px;
  border: 0;
  border-radius: 5px;
  background: transparent;
  color: var(--td-text-color-primary);
  font: inherit;
  font-size: 13px;
  text-align: left;
  cursor: pointer;
}

.profile-nav__item:hover {
  background: var(--td-bg-color-container-hover);
}

.profile-nav__item--active {
  background: var(--td-brand-color-light);
  color: var(--td-brand-color);
  font-weight: 600;
}

.profile-nav__icon {
  flex: none;
  font-size: 16px;
}

.profile-nav__footer {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  margin-top: 7px;
  padding: 10px;
  border-top: 1px solid var(--td-component-stroke);
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.profile-nav__footer strong {
  color: var(--td-text-color-primary);
  font-weight: 500;
}

.text-warning {
  color: var(--td-warning-color) !important;
}

.profile-main {
  min-width: 0;
}

.section-head {
  margin-bottom: 10px;
}

.section-head h3 {
  margin: 0;
  font-size: 16px;
  font-weight: 600;
}

.section-head p {
  margin: 3px 0 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.detail-stack {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.detail-card {
  overflow: hidden;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container);
}

.detail-card__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  padding: 11px 14px;
  border-bottom: 1px solid var(--td-component-stroke);
}

.detail-card__head h4 {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}

.detail-card__head p {
  margin: 3px 0 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.card-link {
  flex: none;
  color: var(--td-brand-color);
  font-size: 13px;
  text-decoration: none;
}

.card-link:hover {
  text-decoration: underline;
}

.fact-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px 22px;
  padding: 14px;
}

.fact {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 3px;
}

.fact span {
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.fact strong,
.fact code {
  overflow: hidden;
  color: var(--td-text-color-primary);
  font-size: 13px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.fact code {
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace;
  font-weight: 400;
}

.stat-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(104px, 1fr));
  gap: 10px;
  padding: 14px;
}

.stat {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 10px 12px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 6px;
  background: var(--td-bg-color-container-hover);
}

.stat span {
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.stat strong {
  color: var(--td-text-color-primary);
  font-size: 20px;
  font-weight: 600;
  line-height: 1.2;
}

.detail-note {
  padding: 0 14px 14px;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
  line-height: 1.6;
}

.detail-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.detail-table th,
.detail-table td {
  padding: 9px 14px;
  border-bottom: 1px solid var(--td-component-stroke);
  text-align: left;
  vertical-align: top;
}

.detail-table th {
  color: var(--td-text-color-placeholder);
  font-weight: 500;
  white-space: nowrap;
}

.detail-table tr:last-child td {
  border-bottom: 0;
}

.detail-table code {
  padding: 1px 4px;
  border-radius: 3px;
  background: var(--td-bg-color-container-hover);
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace;
  font-size: 11px;
}

.config-preview {
  max-height: 420px;
  margin: 0;
  padding: 14px;
  overflow: auto;
  background: var(--td-bg-color-container-hover);
  color: var(--td-text-color-primary);
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace;
  font-size: 12px;
  line-height: 1.6;
  white-space: pre-wrap;
  word-break: break-all;
}

.config-preview--certificate {
  max-height: 260px;
}

.empty-text,
.load-error {
  margin: 0;
  padding: 14px;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.load-error {
  color: var(--td-error-color);
}

.mount-columns {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.mount-group {
  min-width: 0;
  padding: 14px;
}

.mount-group + .mount-group {
  border-left: 1px solid var(--td-component-stroke);
}

.mount-group h5 {
  margin: 0 0 10px;
  color: var(--td-text-color-secondary);
  font-size: 12px;
  font-weight: 600;
}

.mount-group h5 span {
  margin-left: 4px;
  color: var(--td-text-color-placeholder);
  font-weight: 400;
}

.mount-list {
  display: flex;
  max-height: 240px;
  flex-direction: column;
  gap: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  scrollbar-gutter: stable;
}

.mount-item {
  display: flex;
  align-items: baseline;
  min-width: 0;
  gap: 10px;
  padding: 5px 8px 5px 0;
}

.mount-item:hover {
  background: var(--td-bg-color-container-hover);
}

.mount-item code {
  flex: 0 1 auto;
  min-width: 0;
  max-width: 60%;
  overflow: hidden;
  color: var(--td-text-color-primary);
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace;
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mount-item span {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  color: var(--td-text-color-placeholder);
  font-size: 11px;
  text-align: right;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mount-group .empty-text {
  padding: 4px 0;
}

@media (max-width: 900px) {
  .profile-detail {
    grid-template-columns: 1fr;
  }

  .profile-nav {
    position: static;
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .profile-nav__title,
  .profile-nav__footer {
    display: none;
  }

  .profile-nav__item {
    width: auto;
  }
}

@media (max-width: 620px) {
  .fact-grid,
  .mount-columns {
    grid-template-columns: 1fr;
  }

  .mount-group + .mount-group {
    border-top: 1px solid var(--td-component-stroke);
    border-left: 0;
  }
}
</style>
