<template>
  <section class="page-panel">
    <div class="page-head">
      <div class="detail-heading">
        <div class="detail-heading__title title-row">
          <h2 class="page-title">{{ projectName || '配置详情' }}</h2>
          <p class="page-subtitle">
            <span v-if="projectTitle">{{ projectTitle }} · </span>
            <code v-if="qualifiedName">{{ qualifiedName }}</code>
            <span v-if="basVersion"> · BAS {{ basVersion }}</span>
          </p>
          <router-link class="title-back" to="/config/org-config?tab=projects">← 返回配置管理</router-link>
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
      <div v-if="project" class="project-detail">
        <aside class="project-nav">
          <div class="project-nav__title">配置内容</div>
          <button
            v-for="item in sectionItems"
            :key="item.key"
            type="button"
            class="project-nav__item"
            :class="{ 'project-nav__item--active': activeSection === item.key }"
            :title="item.hint"
            @click="selectSection(item.key)"
          >
            <component :is="item.icon" class="project-nav__icon" />
            <span>{{ item.label }}</span>
          </button>
          <div class="project-nav__footer">
            <span>Project key</span>
            <strong :class="{ 'text-warning': !keyConfigured }">{{ keyConfigured ? '已设置' : '未设置' }}</strong>
          </div>
        </aside>

        <main class="project-main">
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
                  <h4>Project 基本资料</h4>
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
                  <strong>{{ projectTitle || '—' }}</strong>
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
                  <strong>{{ domain || ip || '—' }}</strong>
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
                  <p>来自当前 Project 的群集、主机、应用与在线节点。</p>
                </div>
              </header>
              <div class="stat-grid">
                <div class="stat"><span>群集</span><strong>{{ farms.length }}</strong></div>
                <div class="stat"><span>服务</span><strong>{{ servers.length }}</strong></div>
                <div class="stat"><span>主机</span><strong>{{ hosts.length }}</strong></div>
                <div class="stat"><span>应用</span><strong>{{ enabledWebapps.length }}</strong></div>
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
                <div class="detail-card__actions">
                  <t-button size="small" variant="outline" @click="editProxyEndpoint">
                    编辑代理设置
                  </t-button>
                  <t-button
                    size="small"
                    variant="outline"
                    :loading="proxyApplying"
                    :disabled="!proxyEngine || !proxyConfig || !proxy || !ip || !proxyAllOnline"
                    @click="applyProxy"
                  >
                    应用到节点
                  </t-button>
                  <t-button
                    size="small"
                    theme="primary"
                    :loading="bundleDownloading"
                    :disabled="!proxyEngine || !proxyConfig"
                    @click="downloadBundle"
                  >
                    下载 ZIP
                  </t-button>
                  <t-tag :theme="proxyConfig ? 'success' : 'default'" variant="light">
                    {{ proxyConfig ? '配置已生成' : '未生成配置' }}
                  </t-tag>
                </div>
              </header>
              <div class="fact-grid">
                <div class="fact"><span>引擎</span><strong>{{ proxyEngineLabel }}</strong></div>
                <div class="fact"><span>HTTP 端口</span><strong>{{ httpPort || '—' }}</strong></div>
                <div class="fact"><span>HTTPS</span><strong>{{ enableHttps ? '已启用' : '未启用' }}</strong></div>
                <div class="fact"><span>HTTPS 端口</span><strong>{{ enableHttps ? (httpsPort || '—') : '—' }}</strong></div>
                <div class="fact"><span>强制 HTTPS</span><strong>{{ forceHttps ? '是' : '否' }}</strong></div>
                <div class="fact"><span>最大连接数</span><strong>{{ maxconn || '默认' }}</strong></div>
              </div>
              <p v-if="proxyHosts.length > 0 && !proxyAllOnline" class="load-error">
                代理节点未全部在线，无法应用配置。
              </p>
              <div class="detail-note">
                下载到服务器的代理 ZIP 按该 Project 下的群集、服务、主机与 Micdn 路径生成；修改 Project 后重新生成。
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
              <p v-else class="empty-text">当前 Project 没有可生成的代理配置。</p>
            </article>
          </div>

          <div v-else-if="activeSection === 'certificate'" class="detail-stack">
            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>HTTPS 与证书状态</h4>
                  <p>管理台只展示公钥证书，私钥永远不会下发到浏览器。</p>
                </div>
                <div class="detail-card__actions">
                  <t-tag :theme="enableHttps ? 'success' : 'default'" variant="light">
                    {{ enableHttps ? 'HTTPS 已启用' : 'HTTPS 未启用' }}
                  </t-tag>
                  <t-button size="small" theme="primary" @click="openCertificateEditor">编辑证书</t-button>
                </div>
              </header>
              <p v-if="certificateExpiryWarning" class="form-hint form-hint--warning">
                {{ certificateExpiryWarning }}
              </p>
              <div class="fact-grid">
                <div class="fact"><span>HTTPS 端口</span><strong>{{ enableHttps ? (httpsPort || '—') : '—' }}</strong></div>
                <div class="fact"><span>强制 HTTPS</span><strong>{{ forceHttps ? '是' : '否' }}</strong></div>
                <div class="fact"><span>公钥 / 私钥</span><strong>{{ certificateMaterialLabel }}</strong></div>
                <div class="fact"><span>SSL 协议</span><strong>{{ sslProtocols || '代理默认' }}</strong></div>
                <div class="fact"><span>证书过期</span><strong>{{ certificateExpiryLabel }}</strong></div>
                <div class="fact fact--wide"><span>SSL 加密套件</span><strong>{{ sslCiphers || '代理默认' }}</strong></div>
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
              <p v-else class="empty-text">当前 Project 没有设置公钥证书。</p>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>私钥保护</h4>
                  <p>代理配置从管理台下载时使用登录会话鉴权；ZIP 内的私钥只随 bundle 下发。</p>
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
                <div class="detail-card__actions">
                  <t-button size="small" variant="outline" @click="openMonitor">打开监控</t-button>
                </div>
              </header>
              <div class="stat-grid">
                <div class="stat"><span>群集</span><strong>{{ farms.length }}</strong></div>
                <div class="stat"><span>服务</span><strong>{{ servers.length }}</strong></div>
                <div class="stat"><span>主机</span><strong>{{ hosts.length }}</strong></div>
                <div class="stat"><span>应用</span><strong>{{ enabledWebapps.length }}</strong></div>
                <div class="stat"><span>运行实例</span><strong>{{ runningInstanceCount }}</strong></div>
                <div class="stat"><span>停止实例</span><strong>{{ stoppedInstanceCount }}</strong></div>
              </div>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>节点与服务</h4>
                </div>
                <router-link class="card-link" to="/monitor/agents">在线节点</router-link>
              </header>
              <p v-if="warnings.servers" class="load-error">{{ warnings.servers }}</p>
              <template v-else-if="serviceRows.length > 0">
                <p v-if="warnings.agents" class="load-error">{{ warnings.agents }}（以下只显示配置中的服务）</p>
                <table class="detail-table service-table">
                  <thead>
                    <tr>
                      <th>节点</th>
                      <th>群集</th>
                      <th>服务</th>
                      <th>HTTP</th>
                      <th>堆</th>
                      <th>状态</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="item in serviceRows" :key="item.key">
                      <td class="service-table__node">
                        <strong>{{ item.ip }}</strong>
                        <small v-if="item.hostName">{{ item.hostName }}</small>
                        <t-tag size="small" :theme="item.online ? 'success' : 'default'" variant="light">
                          {{ item.online ? '在线' : '离线' }}
                        </t-tag>
                      </td>
                      <td>{{ item.farmName }}</td>
                      <td class="service-table__name" :title="item.name">{{ item.name }}</td>
                      <td>{{ item.httpPort || '—' }}</td>
                      <td>{{ item.heap || '—' }}</td>
                      <td>
                        <t-tag size="small" :theme="item.running ? 'success' : 'warning'" variant="light">
                          {{ item.running ? '运行中' : '已停止' }}
                        </t-tag>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </template>
              <p v-else class="empty-text">当前 Project 还没有服务或在线节点。</p>
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
                  <tr><th>上下文</th><th>应用</th><th>GAV</th><th>状态</th></tr>
                </thead>
                <tbody>
                  <tr v-for="webapp in webappRows" :key="webapp.id">
                    <td><code>{{ attrOf(webapp, 'contextPath') || '/' }}</code></td>
                    <td>{{ webappTitle(webapp) }}</td>
                    <td><code>{{ attrOf(webapp, 'gav') || '—' }}</code></td>
                    <td><t-tag size="small" :theme="webappEnabled(webapp) ? 'success' : 'default'" variant="light">{{ webappEnabled(webapp) ? '启用' : '停用' }}</t-tag></td>
                  </tr>
                </tbody>
              </table>
              <p v-else class="empty-text">当前 Project 还没有部署应用。</p>
            </article>

            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>server.xml</h4>
                  <p>basctl 从该 Project 拉取并执行的最终配置。</p>
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
              <p v-else class="empty-text">当前 Project 没有可生成的 server.xml。</p>
            </article>
          </div>

          <div v-else class="detail-stack">
            <article class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>Micdn 运行配置</h4>
                  <p>Project 是 micdn 配置与组件绑定的中心。</p>
                </div>
                <div class="detail-card__actions">
                  <t-button
                    size="small"
                    variant="outline"
                    :loading="micdnReloading"
                    :title="micdnReloadTitle"
                    :disabled="!micdn || micdnServers.length === 0 || !micdnAllOnline"
                    @click="reloadMicdn"
                  >
                    Reload micdn
                  </t-button>
                  <t-button size="small" theme="primary" @click="openMicdn">编辑配置</t-button>
                </div>
              </header>
              <p v-if="warnings.micdn" class="load-error">{{ warnings.micdn }}</p>
              <div v-else-if="micdn" class="fact-grid">
                <div class="fact"><span>监听地址</span><strong>{{ micdn.config.listen || '—' }}</strong></div>
                <div class="fact"><span>Home</span><strong>~</strong></div>
                <div class="fact"><span>日志</span><strong>/var/log/micdn/micdn.log · info</strong></div>
                <div class="fact"><span>Micdn 服务器</span><strong>{{ micdnServers.length }}</strong></div>
                <div class="fact"><span>Static 绑定</span><strong>{{ staticBindings.length }}</strong></div>
                <div class="fact"><span>WWW 绑定</span><strong>{{ wwwBindings.length }}</strong></div>
              </div>
              <p v-else class="empty-text">尚未加载 Micdn 配置。</p>
              <p v-if="micdn && micdnServerStatus.length > 0 && !micdnAllOnline" class="load-error">
                Micdn 节点未全部在线，无法 reload。
              </p>
              <p v-else-if="micdn && micdnServerStatus.length > 0 && !micdnAllRunning" class="load-error">
                Micdn 服务未全部运行，可用 Reload 拉起。
              </p>
              <div v-if="micdn && micdnServerStatus.length > 0" class="micdn-host-list">
                <span v-for="server in micdnServerStatus" :key="server.host" class="micdn-host">
                  <code>{{ server.host }}</code>
                  <t-tag size="small" :theme="server.active ? 'success' : server.agentOnline ? 'warning' : 'default'" variant="light">
                    {{ server.active ? '在线' : server.agentOnline ? '已停止' : '离线' }}
                  </t-tag>
                </span>
              </div>
              <p v-else-if="micdn" class="empty-text">尚未登记 Micdn 节点。</p>
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
                  <p>仓库固定启用，以及 Blob 的 bucket 归属。</p>
                </div>
              </header>
              <div class="fact-grid">
                <div class="fact"><span>Maven</span><strong>已启用</strong></div>
                <div class="fact"><span>NPM</span><strong>已启用</strong></div>
                <div class="fact"><span>Native</span><strong>已启用</strong></div>
                <div class="fact"><span>Blob</span><strong>{{ micdn.project.keySet ? '已启用' : '未启用' }}</strong></div>
                <div class="fact"><span>Bucket</span><strong>{{ micdn.project.qualifiedName || '—' }}</strong></div>
                <div class="fact"><span>Bucket Key</span><strong>{{ micdn.project.keySet ? micdn.project.keyMasked : '未设置' }}</strong></div>
              </div>
            </article>

            <article v-if="micdn" class="detail-card">
              <header class="detail-card__head">
                <div>
                  <h4>Micdn 节点</h4>
                  <p>这些节点地址用于生成 Micdn 代理后端。</p>
                </div>
              </header>
              <table v-if="micdnServers.length > 0" class="detail-table">
                <thead>
                  <tr><th>节点 IP</th></tr>
                </thead>
                <tbody>
                  <tr v-for="server in micdnServers" :key="server.host">
                    <td><code>{{ server.host }}</code></td>
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

    <t-dialog
      v-model:visible="certificateVisible"
      header="编辑 HTTPS 证书"
      width="720px"
      :confirm-btn="{ loading: savingCertificate }"
      @confirm="saveCertificate"
    >
      <div class="certificate-form">
        <label>公钥证书（PEM，可含完整证书链）</label>
        <t-textarea
          v-model="certificateDraft"
          :autosize="{ minRows: 6, maxRows: 14 }"
          placeholder="-----BEGIN CERTIFICATE-----"
        />
        <label>私钥（PEM；留空表示保持原私钥）</label>
        <t-textarea
          v-model="privateKeyDraft"
          :autosize="{ minRows: 4, maxRows: 10 }"
          placeholder="-----BEGIN PRIVATE KEY-----"
        />
        <label>证书过期时间（自动解析失败时填写）</label>
        <t-input
          v-model="certificateNotAfterDraft"
          placeholder="2030-01-01T00:00:00Z"
        />
        <p class="form-hint">优先使用证书内的 notAfter；无法解析时才使用这里的时间。</p>
        <t-alert v-if="certificateError" theme="error" :message="certificateError" />
      </div>
    </t-dialog>

    <t-dialog v-model:visible="operationErrorVisible" :header="operationErrorTitle" width="760px" :footer="false">
      <pre class="operation-error">{{ operationErrorDetail }}</pre>
    </t-dialog>
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
import { DialogPlugin, MessagePlugin } from 'tdesign-vue-next'
import { computed, onMounted, reactive, ref, watch, type Component } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { listAgents, type AgentInstance, type AgentStatus } from '@/api/agents'
import {
  getMicdnProject,
  reloadMicdnProject,
  type MicdnBinding,
  type MicdnProjectDocument,
} from '@/api/micdn'
import {
  applyProjectProxy,
  downloadProjectProxyBundle,
  readEndpointCertificate,
  readProjectConfig,
  saveEndpointCertificate,
} from '@/api/project-detail'
import {
  attributeText,
  getResourceDetail,
  indexIncluded,
  listResource,
  relationshipIds,
  type ResourceRow,
} from '@/api/resource'

const PROJECTS_PATH = '/projects'

type SectionKey = 'overview' | 'proxy' | 'certificate' | 'bas' | 'micdn'

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

/** 节点上的一个服务；在线状态来自该 IP 的 agent。 */
interface ServerRunEntry {
  key: string
  ip: string
  hostName: string
  online: boolean
  name: string
  farmName: string
  httpPort: string
  heap: string
  running: boolean
}

const sectionItems: SectionItem[] = [
  { key: 'overview', label: '概览', hint: 'Project 的归属、版本与部署概况', icon: DashboardIcon },
  { key: 'proxy', label: 'Haproxy / Nginx', hint: '负载均衡监听与渲染后的代理配置', icon: InternetIcon },
  { key: 'certificate', label: '证书', hint: 'HTTPS、公钥证书与私钥保护', icon: CertificateIcon },
  { key: 'bas', label: 'BAS 服务', hint: '群集、服务、应用、在线实例与 server.xml', icon: ServerIcon },
  { key: 'micdn', label: 'Micdn', hint: '静态挂载、仓库、Blob 与 Micdn 节点', icon: CloudIcon },
]

const route = useRoute()
const router = useRouter()
const projectId = String(route.params.id || '')

const project = ref<ResourceRow>()
const proxy = ref<ResourceRow>()
const included = ref<Map<string, ResourceRow>>(new Map())
const farms = ref<ResourceRow[]>([])
const servers = ref<ResourceRow[]>([])
const hosts = ref<ResourceRow[]>([])
const webapps = ref<ResourceRow[]>([])
const agents = ref<AgentStatus[]>([])
const proxyConfig = ref('')
const bundleDownloading = ref(false)
const proxyApplying = ref(false)
const micdnReloading = ref(false)
const serverConfig = ref('')
const micdn = ref<MicdnProjectDocument>()
const loading = ref(false)
const loadError = ref('')
const warnings = reactive<Record<string, string>>({})
const activeSection = ref<SectionKey>(initialSection())

const organization = computed(() => related(project.value, 'org', 'organizations'))
const organizationName = computed(() => attrOf(organization.value, 'name'))
const name = computed(() => attrOf(project.value, 'name'))
const qualifiedName = computed(() => attrOf(project.value, 'qualifiedName') || [organizationName.value, name.value].filter(Boolean).join('.'))
const projectName = computed(() => qualifiedName.value || name.value)
const projectTitle = computed(() => attrOf(project.value, 'title'))
const basVersion = computed(() => attrOf(project.value, 'basVersion'))
const ip = computed(() => attrOf(proxy.value, 'ip'))
const domain = computed(() => attrOf(proxy.value, 'domain'))
const httpPort = computed(() => attrOf(proxy.value, 'httpPort'))
const httpsPort = computed(() => attrOf(proxy.value, 'httpsPort'))
const enableHttps = computed(() => boolOf(proxy.value?.attributes.enableHttps))
const forceHttps = computed(() => boolOf(proxy.value?.attributes.forceHttps))
const maxconn = computed(() => attrOf(proxy.value, 'maxconn'))
const proxyEngine = computed(() => attrOf(proxy.value, 'proxyEngine'))
const proxyEngineLabel = computed(() => {
  if (proxyEngine.value === 'haproxy') return 'HAProxy'
  if (proxyEngine.value === 'nginx') return 'Nginx'
  return proxyEngine.value || '未设置'
})
const sslProtocols = computed(() => attrOf(proxy.value, 'sslProtocols'))
const sslCiphers = computed(() => attrOf(proxy.value, 'sslCiphers'))
const certificateExpiryLabel = computed(() => {
  if (!certificateNotAfter.value) return '未记录'
  const date = new Date(certificateNotAfter.value)
  if (Number.isNaN(date.getTime())) return certificateNotAfter.value
  return date.toLocaleString('zh-CN', { hour12: false })
})
const certificateMaterialLabel = computed(() => {
  const certificate = Boolean(certificateText.value)
  if (certificate && privateKeySet.value) return '均已设置'
  if (!certificate && !privateKeySet.value) return '均未设置'
  return certificate ? '公钥已设置 / 私钥未设置' : '公钥未设置 / 私钥已设置'
})
const certificateExpiryWarning = computed(() => {
  if (!certificateNotAfter.value) return ''
  const date = new Date(certificateNotAfter.value)
  if (Number.isNaN(date.getTime())) return ''
  const days = Math.ceil((date.getTime() - Date.now()) / 86400000)
  if (days < 0) return '证书已过期'
  if (days <= 30) return `证书将在 ${days} 天内过期`
  return ''
})
const certificateText = ref('')
const certificateNotAfter = ref('')
const privateKeySet = ref(false)
const certificateVisible = ref(false)
const certificateDraft = ref('')
const certificateNotAfterDraft = ref('')
const privateKeyDraft = ref('')
const savingCertificate = ref(false)
const certificateError = ref('')
const operationErrorVisible = ref(false)
const operationErrorTitle = ref('')
const operationErrorDetail = ref('')
const keyConfigured = computed(() => Boolean(attrOf(project.value, 'key')) || micdn.value?.project.keySet === true)
const organizationText = computed(() => {
  const orgTitle = attrOf(organization.value, 'title')
  return [organizationName.value, orgTitle].filter(Boolean).join(' · ')
})

const onlineAgents = computed(() =>
  agents.value.filter((agent) => agent.project === qualifiedName.value || agent.project === name.value),
)
const onlineHosts = computed(() => new Set(
  onlineAgents.value.flatMap((agent) => [agent.ip, agent.host]).filter((host): host is string => Boolean(host)),
))
const proxyHosts = computed(() => String(attrOf(proxy.value, 'ip') || '')
  .split(',')
  .map((ip) => ip.trim())
  .filter(Boolean))
const proxyAllOnline = computed(() =>
  proxyHosts.value.length > 0 && proxyHosts.value.every((host) => onlineHosts.value.has(host)),
)
const micdnServerStatus = computed(() =>
  micdnServers.value.map((server) => {
    const host = server.host.trim()
    const agent = onlineAgents.value.find((item) => item.ip === host || item.host === host)
    return { host, agentOnline: onlineHosts.value.has(host), active: agent?.os?.micdn?.active === true }
  }),
)
const micdnAllOnline = computed(() =>
  micdnServerStatus.value.length > 0 && micdnServerStatus.value.every((server) => server.agentOnline),
)
const micdnAllRunning = computed(() =>
  micdnServerStatus.value.length > 0 && micdnServerStatus.value.every((server) => server.active),
)
const micdnReloadTitle = computed(() => {
  if (!micdn.value) return 'Micdn 配置尚未加载'
  if (micdnServerStatus.value.length === 0) return '尚未登记 Micdn 节点'
  const offline = micdnServerStatus.value.filter((server) => !server.agentOnline).map((server) => server.host)
  return offline.length === 0 ? '向登记节点发送 reload' : `离线节点：${offline.join(', ')}`
})
const instanceRows = computed<InstanceRow[]>(() =>
  onlineAgents.value
    .flatMap((agent) => instancesOf(agent).map((instance) => ({ agent, instance, running: isRunning(instance) })))
    .sort((a, b) => (a.agent.host || a.agent.project).localeCompare(b.agent.host || b.agent.project)),
)
const runningInstanceCount = computed(() => instanceRows.value.filter((row) => row.running).length)
const stoppedInstanceCount = computed(() => instanceRows.value.filter((row) => !row.running).length)

/** 服务表：运行中的排在停止的上面，同组按节点、群集、服务名排序。 */
const serviceRows = computed<ServerRunEntry[]>(() => {
  const agentsByIp = new Map<string, AgentStatus>()
  const instancesByAgent = new Map<AgentStatus, AgentInstance[]>()
  for (const agent of onlineAgents.value) {
    if (agent.ip) agentsByIp.set(agent.ip, agent)
    instancesByAgent.set(agent, instancesOf(agent))
  }

  const entries: ServerRunEntry[] = []
  const seen = new Set<string>()
  for (const server of servers.value) {
    const host = related(server, 'host', 'hosts')
    const hostIp = attrOf(host, 'ip') || '未分配 IP'
    const hostName = attrOf(host, 'name')
    const farmName = relatedName(server)
    const serverName = attrOf(server, 'name')
    const agent = agentsByIp.get(hostIp)
    const instance = agent
      ? (instancesByAgent.get(agent) ?? []).find(
          (item) => item.id === `${farmName}.${serverName}` || item.id === serverName,
        )
      : undefined
    if (agent && instance?.id) seen.add(`${agent.ip}|${instance.id}`)
    entries.push({
      key: `server:${server.id}`,
      ip: hostIp,
      hostName,
      online: Boolean(agent),
      name: serverName,
      farmName,
      httpPort: attrOf(server, 'httpPort'),
      heap: heapText(server),
      running: instance ? isRunning(instance) : false,
    })
  }

  // agent 上报了配置里没有的实例时也展示出来，避免“在线却看不到”。
  for (const agent of onlineAgents.value) {
    for (const instance of instancesByAgent.get(agent) ?? []) {
      const id = instance.id ?? ''
      if (!id || seen.has(`${agent.ip}|${id}`)) continue
      const dot = id.indexOf('.')
      entries.push({
        key: `instance:${agent.ip}:${id}`,
        ip: agent.ip || '未分配 IP',
        hostName: agent.host || '',
        online: true,
        name: id,
        farmName: dot > 0 ? id.slice(0, dot) : '未分组',
        httpPort: instance.httpPort ? String(instance.httpPort) : '',
        heap: '',
        running: isRunning(instance),
      })
    }
  }

  const byText = (a: string, b: string) => a.localeCompare(b, 'zh-CN', { numeric: true })
  return entries.sort((a, b) =>
    Number(b.running) - Number(a.running) ||
    byText(a.ip, b.ip) ||
    byText(a.farmName, b.farmName) ||
    byText(a.name, b.name),
  )
})

const webappRows = computed(() =>
  [...webapps.value].sort((a, b) => attrOf(a, 'contextPath').localeCompare(attrOf(b, 'contextPath'))),
)
const enabledWebapps = computed(() => webapps.value.filter(webappEnabled))

function webappEnabled(webapp: ResourceRow): boolean {
  const value = webapp.attributes.enabled
  return value === undefined || value === true || value === 'true'
}
const staticBindings = computed(() => bindingsOf('static_bundle'))
const wwwBindings = computed(() => bindingsOf('www_doc'))
const micdnServers = computed(() =>
  [...(micdn.value?.config.servers ?? [])].sort((a, b) => a.host.localeCompare(b.host)),
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
  void router.push(`/micdn/projects/${projectId}`)
}

function openMonitor() {
  void router.push({ path: '/monitor/agents', query: { project: qualifiedName.value } })
}

function operationFailureText(item: { host: string; error?: string; data?: unknown }): string {
  let detail = item.error || '未知错误'
  if (item.data && typeof item.data === 'object' && 'detail' in item.data) {
    const value = (item.data as { detail?: unknown }).detail
    if (typeof value === 'string' && value.length > 0)
      detail += `\n${value}`
  }
  return `${item.host}\n${detail}`
}

function showOperationError(title: string, detail: string) {
  operationErrorTitle.value = title
  operationErrorDetail.value = detail
  operationErrorVisible.value = true
}

async function reloadMicdn() {
  if (!micdnAllOnline.value) {
    MessagePlugin.error('Micdn 节点未全部在线，无法 reload')
    return
  }
  micdnReloading.value = true
  try {
    const results = await reloadMicdnProject(projectId)
    const failed = results.filter((item) => !item.ok)
    if (failed.length > 0) {
      showOperationError('Micdn reload 失败', failed.map(operationFailureText).join('\n\n'))
    } else {
      MessagePlugin.success('micdn 已 reload')
    }
  } catch (error) {
    showOperationError('Micdn reload 失败', errorText(error))
  } finally {
    micdnReloading.value = false
  }
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

function editProxyEndpoint() {
  router.push({
    path: '/config/org-config',
    query: { tab: 'endpoints', project: projectId },
  })
}

function applyProxy() {
  if (!proxy.value || !proxyEngine.value) return
  if (!proxyAllOnline.value) {
    MessagePlugin.error('代理节点未全部在线，无法应用配置')
    return
  }
  const endpoint = attributeText(proxy.value.attributes.name)
  const dialog = DialogPlugin.confirm({
    header: '应用到代理节点',
    body: `将在 ${attributeText(proxy.value.attributes.ips) || '登记的节点'} 上应用代理配置并 reload，期间可能有短暂中断。`,
    onConfirm: async () => {
      proxyApplying.value = true
      try {
        const results = await applyProjectProxy(
          projectId,
          proxyEngine.value as 'haproxy' | 'nginx',
          endpoint,
        )
        const failed = results.filter((item) => !item.ok)
        if (failed.length > 0) {
          showOperationError('代理应用失败', failed.map(operationFailureText).join('\n\n'))
        } else {
          MessagePlugin.success('代理已应用到节点')
        }
        dialog.destroy()
      } catch (error) {
        showOperationError('代理应用失败', errorText(error))
      } finally {
        proxyApplying.value = false
      }
    },
  })
}

async function downloadBundle() {
  if (!proxyEngine.value || !proxy.value) return
  bundleDownloading.value = true
  try {
    const endpoint = attributeText(proxy.value.attributes.name)
    await downloadProjectProxyBundle(projectId, proxyEngine.value as 'haproxy' | 'nginx', endpoint)
    MessagePlugin.success('代理 bundle 已开始下载')
  } catch (error) {
    MessagePlugin.error(errorText(error) || '代理 bundle 下载失败')
  } finally {
    bundleDownloading.value = false
  }
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

/** 打开证书编辑框：公钥回填，私钥不回显（留空保持原值）。 */
const certificateEndpointName = computed(() => attrOf(proxy.value, 'name'))

async function loadEndpointCertificate() {
  const endpointName = certificateEndpointName.value
  if (!endpointName) {
    certificateText.value = ''
    certificateNotAfter.value = ''
    privateKeySet.value = false
    return
  }
  try {
    const info = await readEndpointCertificate(projectId, endpointName)
    certificateText.value = info.certificate
    certificateNotAfter.value = info.certificateNotAfter
    privateKeySet.value = info.keySet
  } catch (reason) {
    warning('certificate', '证书', reason)
  }
}

function openCertificateEditor() {
  certificateDraft.value = certificateText.value
  privateKeyDraft.value = ''
  certificateError.value = ''
  certificateVisible.value = true
}

async function saveCertificate() {
  if (savingCertificate.value) return
  certificateError.value = ''
  if (!certificateDraft.value.includes('BEGIN CERTIFICATE')) {
    certificateError.value = '公钥证书必须是 PEM 格式（包含 BEGIN CERTIFICATE）'
    return
  }
  savingCertificate.value = true
  try {
    const info = await saveEndpointCertificate(projectId, certificateEndpointName.value, {
      certificate: certificateDraft.value,
      privateKey: privateKeyDraft.value,
      certificateNotAfter: certificateNotAfterDraft.value,
    })
    certificateText.value = info.certificate
    certificateNotAfter.value = info.certificateNotAfter
    privateKeySet.value = info.keySet
    certificateVisible.value = false
    MessagePlugin.success('证书已保存')
  } catch (reason) {
    certificateError.value = errorText(reason)
  } finally {
    savingCertificate.value = false
  }
}

function endpointAsProxy(endpoint: ResourceRow): ResourceRow {
  const attributes = endpoint.attributes
  return {
    ...endpoint,
    attributes: {
      ...attributes,
      ip: attributes.ips,
      proxyEngine: attributes.engine,
    },
  }
}

async function load() {
  loading.value = true
  loadError.value = ''
  Object.keys(warnings).forEach((key) => delete warnings[key])

  let detail: Awaited<ReturnType<typeof getResourceDetail>>
  try {
    detail = await getResourceDetail(PROJECTS_PATH, projectId, ['org'])
  } catch (error) {
    loadError.value = `加载 Project 失败：${errorText(error)}`
    loading.value = false
    return
  }

  project.value = detail.row
  const includedRows = [...detail.included]

  const [
    farmsResult, hostsResult, webappsResult, agentsResult, proxyResult, serverResult,
    micdnResult, endpointResult,
  ] =
    await Promise.allSettled([
      listResource('/farms', {
        filters: { 'farm.project.id': projectId },
        include: ['engine'],
        pageSize: 500,
      }),
      listResource('/hosts', {
        filters: { 'host.project.id': projectId },
        pageSize: 500,
      }),
      listResource('/webapps', {
        filters: { 'webapp.project.id': projectId },
        include: ['artifact'],
        pageSize: 1000,
      }),
      listAgents(),
      readProjectConfig(projectId, 'proxy'),
      readProjectConfig(projectId, 'server'),
      getMicdnProject(projectId),
      listResource('/endpoints', {
        filters: { 'endpoint.project.id': projectId },
        pageSize: 100,
      }),
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
  if (endpointResult.status === 'fulfilled') {
    const rows = endpointResult.value.rows
    const endpoint = rows.find((row) => attributeText(row.attributes.name) === 'default') ?? rows[0]
    proxy.value = endpoint ? endpointAsProxy(endpoint) : undefined
    await loadEndpointCertificate()
  } else {
    warning('endpoint', '代理点', endpointResult.reason)
  }

  if (serverResult.status === 'fulfilled') serverConfig.value = serverResult.value
  else warning('server', 'server.xml', serverResult.reason)

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


.detail-card__actions,
.tag-row {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.page-alert {
  margin-bottom: 12px;
}

.project-detail {
  display: grid;
  grid-template-columns: 198px minmax(0, 1fr);
  align-items: start;
  gap: 16px;
}

.project-nav {
  position: sticky;
  top: 16px;
  padding: 7px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container);
}

.project-nav__title {
  padding: 7px 10px 9px;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
  font-weight: 500;
}

.project-nav__item {
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

.project-nav__item:hover {
  background: var(--td-bg-color-container-hover);
}

.project-nav__item--active {
  background: var(--td-brand-color-light);
  color: var(--td-brand-color);
  font-weight: 600;
}

.project-nav__icon {
  flex: none;
  font-size: 16px;
}

.project-nav__footer {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  margin-top: 7px;
  padding: 10px;
  border-top: 1px solid var(--td-component-stroke);
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.project-nav__footer strong {
  color: var(--td-text-color-primary);
  font-weight: 500;
}

.text-warning {
  color: var(--td-warning-color) !important;
}

.project-main {
  min-width: 0;
}

.section-head {
  margin-bottom: 10px;
}

.section-head > div,
.detail-card__head > div {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 3px 8px;
  min-width: 0;
}

.section-head h3 {
  margin: 0;
  font-size: 16px;
  font-weight: 600;
}

.section-head p {
  margin: 0;
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
  margin: 0;
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

.micdn-host-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 12px;
}

.micdn-host {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-radius: 4px;
  background: var(--td-bg-color-container-hover);
  font-size: 12px;
}

.fact-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 14px 22px;
  padding: 14px;
}

.fact--wide {
  grid-column: 1 / -1;
}

.fact--wide strong {
  overflow: visible;
  white-space: normal;
  overflow-wrap: anywhere;
}

.fact {
  display: flex;
  min-width: 0;
  align-items: baseline;
  gap: 8px;
}

.fact span {
  flex: none;
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

.service-table {
  margin: 0;
}

.service-table__node strong,
.service-table__node small {
  display: block;
}

.service-table__node strong {
  font-variant-numeric: tabular-nums;
}

.service-table__node small {
  margin-top: 2px;
  color: var(--td-text-color-placeholder);
  font-size: 11px;
}

.service-table__node .t-tag {
  margin-top: 4px;
}

.service-table__name {
  max-width: 220px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
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

.form-hint {
  margin: 6px 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.form-hint--warning {
  color: var(--td-warning-color);
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

.certificate-form {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.certificate-form label {
  color: var(--td-text-color-secondary);
  font-size: 12px;
}

.config-preview--certificate {
  max-height: 260px;
}

.operation-error {
  margin: 0;
  color: var(--td-text-color-primary);
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace;
  font-size: 12px;
  white-space: pre-wrap;
  word-break: break-word;
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
  .project-detail {
    grid-template-columns: 1fr;
  }

  .project-nav {
    position: static;
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .project-nav__title,
  .project-nav__footer {
    display: none;
  }

  .project-nav__item {
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
