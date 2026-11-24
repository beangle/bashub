<template>
  <section class="page-panel customer-health">
    <div class="page-head">
      <div class="detail-heading">
        <h2 class="page-title">项目总览</h2>
        <p class="page-subtitle">所有 Project 的实例、证书与容量风险</p>
      </div>
      <div class="page-actions">
        <span v-if="updatedAt" class="updated-at">更新于 {{ updatedAt }}</span>
        <span class="updated-at">{{ loading ? '刷新中…' : `${secondsLeft}s 后自动刷新` }}</span>
        <t-button variant="outline" :loading="loading" @click="reload">刷新</t-button>
      </div>
    </div>

    <t-alert v-if="error" theme="error" :message="error" class="health-alert" />

    <div class="health-summary">
      <article class="summary-card summary-card--total">
        <span>客户总数</span>
        <div class="summary-card__value">
          <strong>{{ projects.length }}</strong>
          <small>{{ agentCount }} 个在线节点 · {{ instanceRunning }}/{{ instanceTotal }} 个实例运行</small>
        </div>
      </article>
      <article class="summary-card summary-card--ok">
        <span>正常</span>
        <div class="summary-card__value">
          <strong>{{ summary.ok }}</strong>
          <small>无警告</small>
        </div>
      </article>
      <article class="summary-card summary-card--warning">
        <span>警告</span>
        <div class="summary-card__value">
          <strong>{{ summary.warning }}</strong>
          <small>需要关注</small>
        </div>
      </article>
      <article class="summary-card summary-card--critical">
        <span>严重</span>
        <div class="summary-card__value">
          <strong>{{ summary.critical }}</strong>
          <small>需要处理</small>
        </div>
      </article>
    </div>

    <t-loading :loading="loading" show-overlay>
      <div class="health-grid">
        <article
          v-for="item in projects"
          :key="item.id"
          class="health-card"
          :class="`is-${item.status}`"
        >
          <header class="health-card__head">
            <div class="health-card__identity">
              <img
                v-if="item.logoUrl && !failedLogos[item.id]"
                class="health-card__logo"
                :src="item.logoUrl"
                :alt="item.orgTitle"
                @error="failedLogos[item.id] = true"
              />
              <div v-else class="health-card__logo health-card__logo--fallback">{{ item.initials }}</div>
              <div>
                <h3>{{ cardTitle(item) }}</h3>
                <span class="health-card__qualified">{{ item.qualifiedName }}</span>
              </div>
            </div>
            <t-tag :theme="statusTheme(item.status)" variant="light">{{ statusLabel(item.status) }}</t-tag>
          </header>

          <div class="health-card__stats">
            <div>
              <span>在线节点</span>
              <strong>{{ item.agentCount }}</strong>
            </div>
            <div>
              <span>运行实例</span>
              <strong>{{ item.running }}/{{ item.instanceTotal }}</strong>
            </div>
            <div>
              <span>内存</span>
              <strong>{{ item.memoryPercent === undefined ? '—' : `${item.memoryPercent}%` }}</strong>
            </div>
            <div>
              <span>CPU</span>
              <strong>{{ item.cpuText }}</strong>
            </div>
          </div>

          <div v-if="item.alerts.length" class="health-card__alerts">
            <div v-for="(alert, index) in item.alerts.slice(0, 3)" :key="`${alert.level}-${index}`" :class="`is-${alert.level}`">
              <span class="health-card__dot"></span>
              <span>{{ alert.text }}</span>
            </div>
            <span v-if="item.alerts.length > 3" class="health-card__more">+{{ item.alerts.length - 3 }} 项</span>
          </div>
          <div v-else class="health-card__calm">
            运行平稳 · 内存 {{ item.memoryPercent === undefined ? '未上报' : `${item.memoryPercent}%` }} · CPU {{ item.cpuText }}
          </div>

          <footer class="health-card__foot">
            <span>{{ item.orgTitle }}</span>
            <router-link :to="`/config/projects/${item.id}`">配置</router-link>
            <router-link :to="`/monitor/agents?project=${encodeURIComponent(item.qualifiedName)}`">监控</router-link>
          </footer>
        </article>
      </div>
      <p v-if="!loading && projects.length === 0" class="health-empty">暂无 Project。</p>
    </t-loading>
  </section>
</template>

<script setup lang="ts">
import { MessagePlugin } from 'tdesign-vue-next'
import { onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import {
  attributeText,
  listResource,
  relationshipTargets,
  type ResourceRow,
} from '@/api/resource'
import { listAgents, type AgentStatus } from '@/api/agents'

type HealthLevel = 'ok' | 'warning' | 'critical'

interface HealthAlert {
  level: Exclude<HealthLevel, 'ok'>
  text: string
}

interface ProjectHealth {
  id: string
  title: string
  qualifiedName: string
  orgTitle: string
  orgShortTitle: string
  orgSortName: string
  logoUrl: string
  initials: string
  status: HealthLevel
  agentCount: number
  instanceTotal: number
  running: number
  memoryPercent?: number
  cpuText: string
  alerts: HealthAlert[]
}

const projects = ref<ProjectHealth[]>([])
const loading = ref(false)
const error = ref('')
const updatedAt = ref('')
const failedLogos = reactive<Record<string, boolean>>({})
const summary = reactive({ ok: 0, warning: 0, critical: 0 })
const agentCount = ref(0)
const instanceTotal = ref(0)
const instanceRunning = ref(0)
const REFRESH_SECONDS = 30
const secondsLeft = ref(REFRESH_SECONDS)
let refreshTimer: ReturnType<typeof setInterval> | undefined

function statusLabel(status: HealthLevel): string {
  return status === 'ok' ? '正常' : status === 'warning' ? '警告' : '严重'
}

function statusTheme(status: HealthLevel): 'success' | 'warning' | 'danger' {
  return status === 'ok' ? 'success' : status === 'warning' ? 'warning' : 'danger'
}

function cardTitle(item: ProjectHealth): string {
  return item.orgShortTitle && !item.title.startsWith(item.orgShortTitle)
    ? `${item.orgShortTitle} · ${item.title}`
    : item.title
}

function initials(title: string): string {
  return title.trim().slice(0, 1).toUpperCase() || 'P'
}

function memoryUsage(agent: AgentStatus): number | undefined {
  const mem = agent.os?.mem
  if (!mem || typeof mem.total !== 'number' || typeof mem.available !== 'number' || mem.total <= 0) return undefined
  return Math.round(((mem.total - mem.available) / mem.total) * 100)
}

function diskUsage(agent: AgentStatus): number | undefined {
  const values = (agent.os?.disk ?? [])
    .filter((disk): disk is { total: number; available: number } => typeof disk.total === 'number' && typeof disk.available === 'number' && disk.total > 0)
    .map((disk) => (disk.total - disk.available) / disk.total)
  return values.length ? Math.round(Math.max(...values) * 100) : undefined
}

function cpuText(agent: AgentStatus): string {
  const cpu = agent.os?.cpu
  if (!cpu || typeof cpu.load1 !== 'number') return '—'
  const cores = typeof cpu.cores === 'number' && cpu.cores > 0 ? ` / ${cpu.cores}核` : ''
  return `${cpu.load1.toFixed(1)}${cores}`
}

function instanceStats(agent: AgentStatus): { total: number; running: number; stopped: number; error: number } {
  const health = agent.health ?? []
  const declared = agent.basReport?.declared
  const total = Array.isArray(declared) ? declared.length : health.length
  const running = health.filter((item) => item.state === 'running').length
  const error = health.filter((item) => item.state === 'error').length
  return { total, running, stopped: Math.max(0, total - running - error), error }
}

function endpointAlerts(rows: ResourceRow[], projectId: string): HealthAlert[] {
  const alerts: HealthAlert[] = []
  rows.filter((row) => relationshipTargets(row, 'project').some((target) => target.id === projectId)).forEach((row) => {
    const expiry = attributeText(row.attributes.certificateNotAfter).trim()
    if (!expiry) return
    const time = new Date(expiry).getTime()
    if (Number.isNaN(time)) return
    const days = Math.ceil((time - Date.now()) / 86_400_000)
    const name = attributeText(row.attributes.name) || '代理点'
    if (days < 0) alerts.push({ level: 'critical', text: `${name} 证书已过期` })
    else if (days <= 30) alerts.push({ level: 'warning', text: `${name} 证书 ${days} 天后到期` })
  })
  return alerts
}

function buildProject(project: ResourceRow, agents: AgentStatus[], endpoints: ResourceRow[], included: Map<string, ResourceRow>): ProjectHealth {
  const attributes = project.attributes
  const org = relationshipTargets(project, 'org')[0]
  const orgRow = org ? included.get(`${org.type}:${org.id}`) || included.get(org.id) : undefined
  const qualifiedName = attributeText(attributes.qualifiedName)
  const title = attributeText(attributes.title) || attributeText(attributes.name) || qualifiedName || project.id
  const orgTitle = orgRow ? attributeText(orgRow.attributes.title) || attributeText(orgRow.attributes.shortTitle) : ''
  const orgShortTitle = orgRow ? attributeText(orgRow.attributes.shortTitle) || orgTitle : ''
  const orgSortName = orgRow ? attributeText(orgRow.attributes.name) || orgTitle : ''
  const logoUrl = orgRow ? attributeText(orgRow.attributes.logoUrl) : ''
  const relatedAgents = agents.filter((agent) => agent.projectId === project.id ||
    (!agent.projectId && (agent.project === qualifiedName || agent.project === attributeText(attributes.name))))
  const stats = relatedAgents.reduce((sum, agent) => {
    const current = instanceStats(agent)
    sum.total += current.total
    sum.running += current.running
    sum.stopped += current.stopped
    sum.error += current.error
    return sum
  }, { total: 0, running: 0, stopped: 0, error: 0 })
  const memory = relatedAgents.map(memoryUsage).filter((value): value is number => value !== undefined)
  const disk = relatedAgents.map(diskUsage).filter((value): value is number => value !== undefined)
  const cpu = relatedAgents.map((agent) => agent.os?.cpu?.load1).filter((value): value is number => typeof value === 'number')
  const alerts: HealthAlert[] = []
  if (relatedAgents.length === 0) alerts.push({ level: 'warning', text: '无在线节点，无法采集运行数据' })
  if (stats.error > 0) alerts.push({ level: 'critical', text: `${stats.error} 个实例异常` })
  if (stats.stopped > 0) alerts.push({ level: 'warning', text: `${stats.stopped} 个实例未启动` })
  alerts.push(...endpointAlerts(endpoints, project.id))
  const maxDisk = disk.length ? Math.max(...disk) : undefined
  if (maxDisk !== undefined && maxDisk >= 90) alerts.push({ level: 'critical', text: `磁盘使用率 ${maxDisk}%` })
  else if (maxDisk !== undefined && maxDisk >= 80) alerts.push({ level: 'warning', text: `磁盘使用率 ${maxDisk}%` })
  const maxMemory = memory.length ? Math.max(...memory) : undefined
  if (maxMemory !== undefined && maxMemory >= 90) alerts.push({ level: 'warning', text: `内存使用率 ${maxMemory}%` })
  const status: HealthLevel = alerts.some((alert) => alert.level === 'critical')
    ? 'critical'
    : alerts.length > 0 ? 'warning' : 'ok'
  return {
    id: project.id,
    title,
    qualifiedName,
    orgTitle: orgTitle || '未归属机构',
    orgShortTitle: orgShortTitle || '',
    orgSortName: orgSortName || '',
    logoUrl,
    initials: initials(title),
    status,
    agentCount: relatedAgents.length,
    instanceTotal: stats.total,
    running: stats.running,
    memoryPercent: maxMemory,
    cpuText: cpu.length ? `${Math.max(...cpu).toFixed(1)}` : '—',
    alerts,
  }
}

async function reload() {
  if (loading.value) return
  loading.value = true
  secondsLeft.value = REFRESH_SECONDS
  error.value = ''
  try {
    const [projectPage, agents, endpointPage] = await Promise.all([
      listResource('/projects', { pageSize: 500, include: ['org'] }),
      listAgents(),
      listResource('/endpoints', { pageSize: 500 }),
    ])
    const included = new Map<string, ResourceRow>()
    projectPage.included.forEach((row) => {
      included.set(`${row.type}:${row.id}`, row)
      if (!included.has(row.id)) included.set(row.id, row)
    })
    projects.value = projectPage.rows
      .map((project) => buildProject(project, agents, endpointPage.rows, included))
      .sort((a, b) => {
        const byOrg = a.orgSortName.localeCompare(b.orgSortName, 'zh-CN')
        return byOrg || a.qualifiedName.localeCompare(b.qualifiedName, 'zh-CN')
      })
    summary.ok = projects.value.filter((item) => item.status === 'ok').length
    summary.warning = projects.value.filter((item) => item.status === 'warning').length
    summary.critical = projects.value.filter((item) => item.status === 'critical').length
    agentCount.value = agents.length
    instanceTotal.value = projects.value.reduce((sum, item) => sum + item.instanceTotal, 0)
    instanceRunning.value = projects.value.reduce((sum, item) => sum + item.running, 0)
    updatedAt.value = new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : '加载项目总览数据失败'
    MessagePlugin.error(error.value)
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  void reload()
  refreshTimer = setInterval(() => {
    if (loading.value) return
    secondsLeft.value -= 1
    if (secondsLeft.value <= 0) void reload()
  }, 1000)
})

onBeforeUnmount(() => {
  if (refreshTimer) clearInterval(refreshTimer)
})
</script>

<style scoped>
.health-alert {
  margin: 8px 12px;
}

.page-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.updated-at {
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.health-summary {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
  margin: 12px 12px 18px;
}

.summary-card {
  display: flex;
  flex-direction: column;
  justify-content: center;
  min-height: 66px;
  padding: 9px 14px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container);
}

.summary-card > span {
  color: var(--td-text-color-secondary);
  font-size: 12px;
}

.summary-card__value {
  display: flex;
  min-width: 0;
  align-items: baseline;
  gap: 8px;
  margin-top: 2px;
}

.summary-card strong {
  flex: none;
  font-size: 24px;
  line-height: 1.1;
}

.summary-card small {
  overflow: hidden;
  color: var(--td-text-color-placeholder);
  font-size: 11px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.summary-card--ok strong { color: var(--td-success-color); }
.summary-card--warning strong { color: var(--td-warning-color); }
.summary-card--critical strong { color: var(--td-error-color); }

.health-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 12px;
  padding: 0 12px 24px;
}

.health-card {
  display: flex;
  flex-direction: column;
  min-height: 230px;
  padding: 14px;
  border: 1px solid var(--td-component-stroke);
  border-left: 3px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container);
}

.health-card.is-warning { border-left-color: var(--td-warning-color); }
.health-card.is-critical { border-left-color: var(--td-error-color); }

.health-card__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 10px;
}

.health-card__identity {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.health-card__logo {
  width: 40px;
  height: 40px;
  flex: none;
  border-radius: 8px;
  object-fit: contain;
  background: var(--td-bg-color-container-hover);
}

.health-card__logo--fallback {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--td-brand-color);
  font-size: 18px;
  font-weight: 700;
}

.health-card h3 {
  overflow: hidden;
  margin: 0;
  font-size: 14px;
  line-height: 1.4;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.health-card__qualified {
  display: block;
  overflow: hidden;
  margin-top: 2px;
  color: var(--td-text-color-placeholder);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 11px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.health-card__stats {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 8px;
  margin-top: 14px;
  padding: 10px 0;
  border-top: 1px solid var(--td-component-stroke);
  border-bottom: 1px solid var(--td-component-stroke);
}

.health-card__stats div {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 2px;
}

.health-card__stats span {
  color: var(--td-text-color-placeholder);
  font-size: 11px;
}

.health-card__stats strong {
  overflow: hidden;
  font-size: 14px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.health-card__alerts {
  display: flex;
  flex-direction: column;
  gap: 5px;
  margin-top: 10px;
  font-size: 12px;
}

.health-card__alerts > div {
  display: flex;
  min-width: 0;
  align-items: baseline;
  gap: 6px;
}

.health-card__alerts > div.is-critical { color: var(--td-error-color); }
.health-card__alerts > div.is-warning { color: var(--td-warning-color); }

.health-card__dot {
  width: 5px;
  height: 5px;
  flex: none;
  border-radius: 50%;
  background: currentColor;
}

.health-card__more {
  color: var(--td-text-color-placeholder);
  font-size: 11px;
}

.health-card__calm {
  margin-top: 10px;
  color: var(--td-success-color);
  font-size: 12px;
}

.health-card__foot {
  display: flex;
  gap: 10px;
  align-items: center;
  margin-top: auto;
  padding-top: 10px;
  color: var(--td-text-color-placeholder);
  font-size: 11px;
}

.health-card__foot span {
  overflow: hidden;
  flex: 1;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.health-card__foot a {
  color: var(--td-brand-color);
  text-decoration: none;
}

.health-empty {
  padding: 48px;
  color: var(--td-text-color-placeholder);
  text-align: center;
}

@media (max-width: 900px) {
  .health-summary {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
</style>
