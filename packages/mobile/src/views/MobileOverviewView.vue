<template>
  <section class="mobile-page">
    <div class="mobile-page__toolbar">
      <span class="mobile-updated">
        <template v-if="updatedAt">更新于 {{ updatedAt }}</template>
        <template v-else>等待首次上报</template>
        · {{ secondsLeft }} 秒后自动刷新
      </span>
      <t-button size="small" variant="outline" :loading="busy" @click="reload">刷新</t-button>
    </div>

    <MobileNotice v-if="error" :message="error" />
    <MobileNotice v-if="catalogError" :message="catalogError" />
    <MobileNotice v-if="opsError" :message="opsError" />
    <MobileNotice v-if="opsMessage" theme="success" :message="opsMessage" />

    <div v-if="catalogLoading && !projectInfo" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>
    <t-empty
      v-else-if="!projectInfo"
      :description="catalogError ? '项目目录加载失败。' : `项目 ${project} 不存在或无权访问。`"
    />

    <template v-if="projectInfo">
      <t-grid :column="4" :border="false" class="mobile-stat-grid">
        <t-grid-item>
          <template #text><strong>{{ health.nodeCount }}</strong></template>
          <template #description>在线节点</template>
        </t-grid-item>
        <t-grid-item>
          <template #text><strong>{{ health.running }}</strong></template>
          <template #description>运行实例</template>
        </t-grid-item>
        <t-grid-item>
          <template #text><strong :class="{ 'is-danger': health.stopped > 0 }">{{ health.stopped }}</strong></template>
          <template #description>停止</template>
        </t-grid-item>
        <t-grid-item>
          <template #text><strong :class="{ 'is-danger': health.error > 0 }">{{ health.error }}</strong></template>
          <template #description>异常</template>
        </t-grid-item>
      </t-grid>

      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">服务状态</h3>
        </header>
        <div class="mobile-components">
          <div v-for="item in componentSummary" :key="item.key" class="mobile-service-row">
            <div class="mobile-service-label">
              <span class="mobile-service-name">{{ item.label }}</span>
              <span class="mobile-service-version" :title="item.version">{{ item.version }}</span>
            </div>
            <div class="mobile-service-actions">
              <t-tag size="small" variant="light" :theme="item.theme">{{ item.text }}</t-tag>
              <t-button
                v-if="item.action === 'micdn'"
                size="small"
                variant="outline"
                :loading="micdnReloading"
                :disabled="!micdnAllOnline || micdnReloading"
                @click="confirmMicdnReload"
              >
                Reload
              </t-button>
              <t-button
                v-else
                size="small"
                variant="outline"
                :loading="proxyApplying"
                :disabled="!proxyAllOnline || !proxyEngineValid || proxyApplying"
                @click="confirmProxyApply"
              >
                应用
              </t-button>
            </div>
          </div>
        </div>
      </section>


      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">节点健康</h3>
        </header>

        <t-empty v-if="agents.length === 0" description="暂无在线节点。" />
        <div v-else class="mobile-node-list">
          <article
            v-for="agent in agents"
            :key="agentKey(agent)"
            class="mobile-overview-node"
            role="button"
            tabindex="0"
            @click="openHost(agent)"
            @keydown.enter="openHost(agent)"
          >
            <header class="mobile-overview-node__head">
              <div>
                <h4 class="mobile-overview-node__title">{{ agent.ip || agent.host || '未知节点' }}</h4>
                <p class="mobile-overview-node__meta">
                  {{ agent.host || '主机未上报' }} · 心跳 {{ relativeTime(agent.lastSeenAt) }}
                </p>
              </div>
              <t-tag size="small" variant="light" :theme="nodeTheme(agent)">
                {{ nodeLabel(agent) }}
              </t-tag>
            </header>
            <div class="mobile-overview-node__resources">
              <MobileMetricBar
                label="CPU"
                :value="resourceUsage(agent.os).cpuPercent"
                :detail="cpuDetail(agent)"
              />
              <MobileMetricBar
                label="内存"
                :value="resourceUsage(agent.os).memoryPercent"
                :detail="memoryDetail(agent)"
              />
              <MobileMetricBar
                label="磁盘"
                :value="resourceUsage(agent.os).diskPercent"
                :detail="diskDetail(agent)"
              />
            </div>
            <p class="mobile-overview-node__stats">
              实例 {{ countsOf(agent).running }} 运行 / {{ countsOf(agent).stopped }} 停止<template
                v-if="countsOf(agent).error"
              > / {{ countsOf(agent).error }} 异常</template>
            </p>
          </article>
        </div>
      </section>


    </template>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import type { AgentStatus } from '@/api/agents'
import {
  applyProjectProxy,
  getMicdnProject,
  reloadMicdnProject,
  type OperationResult,
} from '@/api/project-ops'
import { attributeText, listResource } from '@/api/resource'
import { DialogPlugin } from 'tdesign-mobile-vue'
import MobileMetricBar from '@/components/MobileMetricBar.vue'
import MobileNotice from '@/components/MobileNotice.vue'
import { useAgentMonitor } from '@/composables/useAgentMonitor'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import {
  agentHealthCounts,
  agentKey,
  compareAgentHealth,
  deviceResources,
  errorText,
  formatBytes,
  mergeProjects,
  relativeTime,
  resourceUsage,
} from '@/monitor-model'

const route = useRoute()
const router = useRouter()
const project = computed(() => String(route.params.project ?? ''))
const catalog = useProjectCatalog()
const {
  summaries,
  statuses,
  loading,
  error,
  updatedAt,
  secondsLeft,
  refresh,
} = useAgentMonitor({ project: () => project.value, mode: 'both' })

const projectInfo = computed(() => catalog.projectOf(project.value))
const catalogLoading = computed(() => catalog.loading.value)
const catalogError = computed(() => catalog.error.value)
const busy = computed(() => loading.value || catalogLoading.value)

const health = computed(() => {
  if (!projectInfo.value) {
    return { nodeCount: 0, running: 0, stopped: 0, error: 0, instanceTotal: 0 }
  }
  return mergeProjects([projectInfo.value], summaries.value)[0]
})

const agents = computed(() => [...statuses.value].sort(compareAgentHealth))

interface AgentComponentState {
  active?: boolean
  state?: string
  version?: string
}

interface ProjectComponentRow {
  key: string
  label: string
  version: string
  text: string
  theme: 'success' | 'warning' | 'default'
  action: 'micdn' | 'proxy'
}

function summarizeComponent(
  label: string,
  states: AgentComponentState[],
  alwaysShow = false,
): Pick<ProjectComponentRow, 'text' | 'theme'> | null {
  if (states.length === 0) return alwaysShow ? { text: '未上报', theme: 'default' } : null
  const active = states.filter((item) => item.active === true || item.state === 'active' || item.state === 'running').length
  if (active === states.length) return { text: `正常 ${active}/${states.length}`, theme: 'success' }
  if (active > 0) return { text: `部分停用 ${active}/${states.length}`, theme: 'warning' }
  return { text: `停用 0/${states.length}`, theme: 'warning' }
}

function firstVersion(values: (string | undefined)[]): string {
  const versions = [...new Set(values.map((value) => value?.trim()).filter((value): value is string => Boolean(value)))]
  return versions[0] || '—'
}

const opsLoading = ref(false)
const opsError = ref('')
const opsMessage = ref('')
const micdnHosts = ref<string[]>([])
const proxyHosts = ref<string[]>([])
const proxyEndpoint = ref('')
const proxyEngine = ref<'haproxy' | 'nginx' | ''>('')
const micdnReloading = ref(false)
const proxyApplying = ref(false)

function hostList(value: unknown): string[] {
  const text = Array.isArray(value) ? value.join(',') : String(value ?? '')
  return [...new Set(text.split(',').map((host) => host.trim()).filter(Boolean))]
}

function agentForHost(host: string): AgentStatus | undefined {
  return statuses.value.find((agent) => agent.ip === host || agent.host === host)
}

const micdnAllOnline = computed(() => micdnHosts.value.length > 0 && micdnHosts.value.every((host) => agentForHost(host)))
const proxyAllOnline = computed(() => proxyHosts.value.length > 0 && proxyHosts.value.every((host) => agentForHost(host)))
const proxyEngineValid = computed(() => proxyEngine.value === 'haproxy' || proxyEngine.value === 'nginx')

async function loadProjectOps(projectId: string | undefined): Promise<void> {
  opsLoading.value = true
  opsError.value = ''
  micdnHosts.value = []
  proxyHosts.value = []
  proxyEndpoint.value = ''
  proxyEngine.value = ''
  if (!projectId) {
    opsLoading.value = false
    return
  }
  const [micdnResult, endpointResult] = await Promise.allSettled([
    getMicdnProject(projectId),
    listResource('/endpoints', { filters: { 'endpoint.project.id': projectId }, pageSize: 100 }),
  ])
  const errors: string[] = []
  if (micdnResult.status === 'fulfilled') {
    micdnHosts.value = [
      ...new Set(micdnResult.value.config.servers.map((server) => server.host.trim()).filter(Boolean)),
    ]
  } else {
    errors.push('Micdn 配置加载失败')
  }
  if (endpointResult.status === 'fulfilled') {
    const rows = endpointResult.value.rows
    const endpoint = rows.find((row) => attributeText(row.attributes.name) === 'default') ?? rows[0]
    if (endpoint) {
      proxyEndpoint.value = attributeText(endpoint.attributes.name)
      const engine = attributeText(endpoint.attributes.engine)
      proxyEngine.value = engine === 'haproxy' || engine === 'nginx' ? engine : ''
      proxyHosts.value = hostList(endpoint.attributes.ips)
    }
  } else {
    errors.push('代理 endpoint 加载失败')
  }
  opsError.value = errors.join('；')
  opsLoading.value = false
}

function operationError(results: OperationResult[]): string {
  return results
    .filter((item) => !item.ok)
    .map((item) => `${item.host}: ${item.error || '失败'}`)
    .join('；')
}

function confirmMicdnReload(): void {
  if (!micdnAllOnline.value || micdnReloading.value) return
  const dialog = DialogPlugin.confirm({
    title: 'Micdn reload',
    content: `将在 ${micdnHosts.value.join(', ')} 上 reload Micdn。`,
    confirmBtn: '确定',
    cancelBtn: '取消',
    onConfirm: () => {
      dialog.destroy()
      void runMicdnReload()
    },
  })
}

async function runMicdnReload(): Promise<void> {
  const projectId = projectInfo.value?.id
  if (!projectId || micdnReloading.value) return
  micdnReloading.value = true
  opsError.value = ''
  opsMessage.value = ''
  try {
    const results = await reloadMicdnProject(projectId)
    const failure = operationError(results)
    if (failure) opsError.value = `Micdn reload 失败：${failure}`
    else opsMessage.value = 'Micdn 已 reload'
    await refresh(true)
  } catch (reason) {
    opsError.value = `Micdn reload 失败：${errorText(reason)}`
  } finally {
    micdnReloading.value = false
  }
}

function confirmProxyApply(): void {
  if (!proxyAllOnline.value || !proxyEngineValid.value || proxyApplying.value) return
  const engine = proxyEngine.value
  const dialog = DialogPlugin.confirm({
    title: '应用代理配置',
    content: `将在 ${proxyHosts.value.join(', ')} 上应用 ${engine} 配置并 reload。`,
    confirmBtn: '确定',
    cancelBtn: '取消',
    onConfirm: () => {
      dialog.destroy()
      void runProxyApply()
    },
  })
}

async function runProxyApply(): Promise<void> {
  const projectId = projectInfo.value?.id
  if (!projectId || !proxyEngineValid.value || proxyApplying.value) return
  proxyApplying.value = true
  opsError.value = ''
  opsMessage.value = ''
  try {
    const results = await applyProjectProxy(
      projectId,
      proxyEngine.value as 'haproxy' | 'nginx',
      proxyEndpoint.value,
    )
    const failure = operationError(results)
    if (failure) opsError.value = `代理应用失败：${failure}`
    else opsMessage.value = '代理配置已应用'
    await refresh(true)
  } catch (reason) {
    opsError.value = `代理应用失败：${errorText(reason)}`
  } finally {
    proxyApplying.value = false
  }
}

watch(() => projectInfo.value?.id, (projectId) => {
  void loadProjectOps(projectId)
}, { immediate: true })

const componentSummary = computed<ProjectComponentRow[]>(() => {
  const micdnStates = statuses.value
    .map((agent) => agent.os?.micdn)
    .filter((item): item is AgentComponentState => item !== undefined)
  const micdn = summarizeComponent('Micdn', micdnStates, true)
  const engine = proxyEngine.value
  const engineLabel = engine === 'haproxy' ? 'HAProxy' : engine === 'nginx' ? 'Nginx' : '代理'
  const proxyStates = engine
    ? statuses.value
      .map((agent) => agent.os?.proxyState?.[engine])
      .filter((item): item is AgentComponentState => item !== undefined)
    : []
  const proxy = engine
    ? summarizeComponent(engineLabel, proxyStates, true)
    : { text: '未配置', theme: 'default' as const }
  return [
    {
      key: 'micdn',
      label: 'Micdn',
      version: firstVersion(micdnStates.map((item) => item.version)),
      text: micdn?.text || '未上报',
      theme: micdn?.theme || 'default',
      action: 'micdn',
    },
    {
      key: 'proxy',
      label: engineLabel,
      version: engine ? firstVersion(statuses.value.map((agent) => agent.os?.proxy?.[engine])) : '—',
      text: proxy?.text || '未上报',
      theme: proxy?.theme || 'default',
      action: 'proxy',
    },
  ]
})

function countsOf(agent: AgentStatus) {
  return agentHealthCounts(agent)
}

function nodeTheme(agent: AgentStatus): 'success' | 'warning' | 'danger' | 'default' {
  const counts = countsOf(agent)
  if (counts.error > 0) return 'danger'
  if (counts.running > 0 && counts.stopped === 0) return 'success'
  if (counts.running > 0 || counts.stopped > 0) return 'warning'
  return 'default'
}

function nodeLabel(agent: AgentStatus): string {
  const counts = countsOf(agent)
  if (counts.error > 0) return '有异常'
  if (counts.running > 0 && counts.stopped === 0) return '运行正常'
  if (counts.running > 0) return '部分停止'
  return '无运行实例'
}

function cpuDetail(agent: AgentStatus): string {
  const resources = deviceResources(agent)
  if (resources.load1 === undefined) return ''
  return `${resources.load1.toFixed(2)} / ${resources.cores ?? '—'} 核`
}

function memoryDetail(agent: AgentStatus): string {
  const resources = deviceResources(agent)
  if (resources.memoryTotal === undefined) return ''
  return `${formatBytes(resources.memoryUsed)} / ${formatBytes(resources.memoryTotal)}`
}

function diskDetail(agent: AgentStatus): string {
  const resources = deviceResources(agent)
  if (resources.diskTotal === undefined) return ''
  return `${resources.diskMount || '/'} ${formatBytes(resources.diskUsed)} / ${formatBytes(resources.diskTotal)}`
}

function openHost(agent: AgentStatus): void {
  const host = agent.ip || ''
  if (!host) {
    void router.push(`/projects/${encodeURIComponent(project.value)}/nodes`)
    return
  }
  void router.push(`/projects/${encodeURIComponent(project.value)}/nodes/${encodeURIComponent(host)}`)
}

async function reload(): Promise<void> {
  await Promise.all([catalog.load(true), refresh()])
}

onMounted(() => {
  void catalog.load()
})
</script>
