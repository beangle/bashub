<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">{{ instance?.id || instanceId || '实例' }}</h2>
        <p class="mobile-page__subtitle">
          {{ project }}<template v-if="agent?.ip"> · {{ agent.ip }}</template><template v-if="agent?.host"> / {{ agent.host }}</template>
        </p>
      </div>
      <router-link class="mobile-back" :to="nodesPath">返回节点</router-link>
    </header>

    <MobileNotice v-if="error" :message="error" />
    <MobileNotice v-if="serviceResult" theme="success" :message="serviceResult" />

    <div v-if="statusesLoading && !agent && agents.length === 0" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>

    <section v-else-if="ambiguous" class="mobile-card">
      <header class="mobile-card__head">
        <h3 class="mobile-card__title">选择节点</h3>
      </header>
      <button
        v-for="item in agents"
        :key="agentKey(item)"
        type="button"
        class="mobile-agent-choice"
        @click="chooseAgent(item)"
      >
        <span>{{ item.ip || item.host || '未知节点' }}</span>
        <span class="mobile-agent-choice__meta">{{ item.host || '' }} · 心跳 {{ relativeTime(item.lastSeenAt) }}</span>
      </button>
    </section>

    <t-empty v-else-if="!agent" description="目标节点不在线。" />

    <t-empty v-else-if="!instance" :description="`实例 ${instanceId} 不存在。`" />

    <template v-else>
      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">运行状态</h3>
          <t-tag size="small" variant="light" :theme="stateTheme(instanceState(instance))">
            {{ stateLabel(instanceState(instance)) }}
          </t-tag>
        </header>

        <dl class="mobile-instance-facts">
          <div v-for="fact in instanceFacts" :key="fact.label" class="mobile-instance-fact">
            <dt>{{ fact.label }}</dt>
            <dd :title="fact.value">{{ fact.value }}</dd>
          </div>
        </dl>

        <div class="mobile-actions">
          <t-button
            v-if="!running"
            theme="primary"
            size="small"
            :disabled="!canService('start') || serviceLoading"
            :loading="serviceLoading"
            @click="confirmService('start')"
          >
            启动
          </t-button>
          <t-button
            v-if="running"
            variant="outline"
            size="small"
            :disabled="!canService('restart') || serviceLoading"
            :loading="serviceLoading"
            @click="confirmService('restart')"
          >
            重启
          </t-button>
          <t-button
            v-if="running"
            theme="danger"
            variant="outline"
            size="small"
            :disabled="!canService('stop') || serviceLoading"
            :loading="serviceLoading"
            @click="confirmService('stop')"
          >
            停止
          </t-button>
        </div>
        <p v-if="capabilityHint" class="mobile-hint">{{ capabilityHint }}</p>
      </section>

      <div v-if="serviceError" class="mobile-error-card">
        <strong>{{ serviceError }}</strong>
        <p v-if="serviceDetail" class="mobile-error-card__detail">{{ serviceDetail }}</p>
        <pre v-if="serviceLogTail.length > 0" class="mobile-error-card__log">{{ serviceLogTail.join('\n') }}</pre>
        <p v-if="serviceTruncated" class="mobile-error-card__detail">日志尾部已截断。</p>
      </div>

      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">运行历史</h3>
          <div class="mobile-segmented">
            <button type="button" :class="{ 'is-active': days === 30 }" @click="setDays(30)">30 天</button>
            <button type="button" :class="{ 'is-active': days === 180 }" @click="setDays(180)">180 天</button>
          </div>
        </header>
        <div v-if="historyLoading" class="mobile-loading">
          <t-loading size="24px" text="加载中" />
        </div>
        <MobileNotice v-else-if="historyError" :message="historyError" />
        <MobileHistoryStrip v-else-if="history" :history="history" :days="days" />
        <t-empty v-else description="暂无运行历史采样。" />
      </section>

      <section class="mobile-card">
        <h3 class="mobile-card__title">应用</h3>
        <t-cell-group v-if="webapps.length > 0" :bordered="false" class="mobile-apps">
          <t-cell
            v-for="app in webapps"
            :key="app.id || app.uri"
            :title="app.title || '未命名应用'"
            :description="app.uri || ''"
          >
            <template #note>{{ app.context || '/' }}</template>
          </t-cell>
        </t-cell-group>
        <t-empty v-else description="暂无应用。" />
      </section>

      <section v-if="deployment && deployment.state !== 'ok'" class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">配置状态</h3>
          <t-tag size="small" variant="light" :theme="deployStateTheme">{{ deployStateLabel }}</t-tag>
        </header>
        <p v-if="deployment.state === 'undelivered'" class="mobile-hint">
          配置尚未下发到该节点，稍后会自动同步。
        </p>
        <p v-else-if="deployment.state === 'unknown'" class="mobile-hint">
          无法与当前配置对照（服务器未登记或配置已删除）。
        </p>
        <template v-else>
          <ul class="mobile-deploy-items">
            <li v-for="(item, index) in deployment.items ?? []" :key="index">
              <span>{{ deployItemText(item) }}</span>
              <code v-if="item.uri">{{ item.uri }}</code>
            </li>
          </ul>
          <p class="mobile-hint">重启该实例后生效；这里只提示，不自动操作。</p>
        </template>
      </section>

      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">启停记录</h3>
          <router-link class="mobile-card__link" :to="eventsPath">全部</router-link>
        </header>
        <div v-if="eventsLoading && serverEvents.length === 0" class="mobile-loading">
          <t-loading size="20px" text="加载中" />
        </div>
        <p v-else-if="serverEvents.length === 0" class="mobile-hint">暂无手工启停记录。</p>
        <ul v-else class="mobile-event-list">
          <li v-for="event in serverEvents" :key="event.id" class="mobile-event-item">
            <t-tag size="small" variant="light" :theme="event.ok ? 'success' : 'error'">
              {{ eventActionLabel(event.action) }}
            </t-tag>
            <span class="mobile-event-item__time">{{ eventTimeLabel(event.at) }}</span>
            <span class="mobile-event-item__meta">
              {{ event.operatorName || event.operator || '—' }}
              <template v-if="event.operatorIp"> · {{ event.operatorIp }}</template>
            </span>
            <span v-if="!event.ok && event.detail" class="mobile-event-item__error">{{ event.detail }}</span>
          </li>
        </ul>
      </section>

      <section class="mobile-card">
        <MobileLogPanel
          title="实例日志"
          :lines="logLines"
          :total="logTotal"
          :loading="logLoading"
          :following="logFollowing"
          :reconnecting="logReconnecting"
          :error="logError"
          @read="openLogWindow"
          @follow="followLog"
          @stop="stopLog"
        />
      </section>
    </template>
  </section>
</template>

<script setup lang="ts">
import { JsonApiRequestError } from '@beangle/ems-app'
import { DialogPlugin } from 'tdesign-mobile-vue'
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  readAgentHistory,
  serviceAgentInstance,
  type AgentDeployItem,
  type AgentServiceAction,
  type AgentStatus,
} from '@/api/agents'
import MobileHistoryStrip from '@/components/MobileHistoryStrip.vue'
import MobileNotice from '@/components/MobileNotice.vue'
import MobileLogPanel from '@/components/MobileLogPanel.vue'
import { readServerEvents, type ServerEvent, type ServerEventAction } from '@/api/events'
import { useAgentLog } from '@/composables/useAgentLog'
import { useAgentMonitor } from '@/composables/useAgentMonitor'
import {
  agentKey,
  errorText,
  findAgent,
  findInstance,
  formatBytes,
  historyForInstance,
  instanceState,
  isInstanceRunning,
  relativeTime,
  stateLabel,
  stateTheme,
  supportsService,
  type InstanceHistory,
} from '@/monitor-model'

const route = useRoute()
const router = useRouter()
const project = computed(() => String(route.params.project ?? ''))
const instanceId = computed(() => String(route.params.instance ?? ''))
const agentIp = computed(() => String(route.query.agent ?? ''))

const {
  statuses,
  loading: statusesLoading,
  error,
  refresh,
} = useAgentMonitor({ project: () => project.value, mode: 'status' })

const {
  lines: logLines,
  total: logTotal,
  loading: logLoading,
  following: logFollowing,
  reconnecting: logReconnecting,
  error: logError,
  read: readLog,
  follow: followLogSource,
  stop: stopLog,
} = useAgentLog()

const days = ref(30)
const history = ref<InstanceHistory | null>(null)
const historyLoading = ref(false)
const historyError = ref('')

const serviceLoading = ref(false)
const serviceError = ref('')
const serviceDetail = ref('')
const serviceLogTail = ref<string[]>([])
const serviceTruncated = ref(false)
const serviceResult = ref('')

const agents = computed(() => statuses.value.filter((agent) => agent.project === project.value))
const agent = computed(() => findAgent(statuses.value, project.value, agentIp.value || undefined))
const instance = computed(() => findInstance(agent.value, instanceId.value))
const ambiguous = computed(() => agentIp.value === '' && agents.value.length > 1)
const running = computed(() => (instance.value ? isInstanceRunning(instance.value) : false))
const webapps = computed(() => instance.value?.webapps ?? [])
const deployment = computed(() => instance.value?.deployment)
const agentIdentity = computed(() => (agent.value ? agentKey(agent.value) : ''))
const eventsPath = computed(() => {
  const base = `/projects/${encodeURIComponent(project.value)}/events`
  return instanceId.value ? `${base}?instance=${encodeURIComponent(instanceId.value)}` : base
})

const serverEvents = ref<ServerEvent[]>([])
const eventsLoading = ref(false)

function eventActionLabel(action: ServerEventAction): string {
  if (action === 'start') return '启动'
  if (action === 'stop') return '停止'
  return '重启'
}

function eventTimeLabel(value?: string): string {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString('zh-CN', { hour12: false })
}

async function loadServerEvents(): Promise<void> {
  if (!project.value || !instanceId.value) return
  eventsLoading.value = true
  try {
    serverEvents.value = await readServerEvents(project.value, {
      instance: instanceId.value,
      limit: 20,
    })
  } catch {
    serverEvents.value = []
  } finally {
    eventsLoading.value = false
  }
}

const nodesPath = computed(() => {
  const base = `/projects/${encodeURIComponent(project.value)}/nodes`
  return agentIp.value ? `${base}/${encodeURIComponent(agentIp.value)}` : base
})

const deployStateLabel = computed(() => {
  switch (deployment.value?.state) {
    case 'restart': return '待重启'
    case 'undelivered': return '未下发'
    case 'unknown': return '未知'
    default: return ''
  }
})

const deployStateTheme = computed<'warning' | 'default'>(() =>
  deployment.value?.state === 'restart' ? 'warning' : 'default',
)

function deployItemText(item: AgentDeployItem): string {
  if (item.action === 'load') return `待加载 ${item.context || '/'}`
  if (item.action === 'remove') return `待删除 ${item.context || '/'}`
  if (item.reason === 'port') return `待重启：端口 ${item.running ?? '—'} → ${item.configured ?? '—'}`
  return `待重启 ${item.context || '/'}（访问路径变化）`
}

const instanceMemory = computed(() => {
  const target = instance.value
  if (!target || !isInstanceRunning(target) || typeof target.rssBytes !== 'number') return '—'
  return formatBytes(target.rssBytes)
})

const instanceFacts = computed(() => {
  const target = instance.value
  if (!target) return []
  return [
    { label: 'PID', value: String(target.pid ?? '—') },
    { label: '端口', value: String(target.httpPort ?? '—') },
    { label: '内存', value: instanceMemory.value },
    { label: '引擎', value: target.engine || '—' },
    { label: '启动时间', value: target.started || '—' },
    { label: 'Agent 心跳', value: relativeTime(agent.value?.lastSeenAt) },
  ]
})

const capabilityHint = computed(() => {
  const current = agent.value
  if (!current) return ''
  const supported = (['start', 'stop', 'restart'] as AgentServiceAction[])
    .filter((action) => supportsService(current, action))
  return supported.length === 0 ? '当前节点不支持启停。' : ''
})

function serviceLabel(action: AgentServiceAction): string {
  if (action === 'stop') return '停止'
  if (action === 'start') return '启动'
  return '重启'
}

function canService(action: AgentServiceAction): boolean {
  return supportsService(agent.value, action)
}

async function loadHistory(): Promise<void> {
  if (!project.value || !instanceId.value) return
  historyLoading.value = true
  historyError.value = ''
  try {
    const data = await readAgentHistory(project.value, { days: days.value })
    history.value = historyForInstance(data, instanceId.value, days.value)
  } catch (reason) {
    history.value = null
    historyError.value = errorText(reason)
  } finally {
    historyLoading.value = false
  }
}

function setDays(value: number): void {
  if (days.value === value) return
  days.value = value
  void loadHistory()
}

function openLogWindow(): void {
  const current = agent.value
  if (!current || !instanceId.value) return
  void readLog({ project: project.value, instance: instanceId.value, agent: current.ip, kind: 'instance' })
}

function followLog(): void {
  const current = agent.value
  if (!current || !instanceId.value) return
  followLogSource({
    project: project.value,
    instance: instanceId.value,
    agent: current.ip,
    kind: 'instance',
  })
}

function chooseAgent(item: AgentStatus): void {
  void router.replace({ query: { ...route.query, agent: item.ip || '' } })
}

function confirmService(action: AgentServiceAction): void {
  const current = agent.value
  const target = instance.value
  if (!current || !target?.id || serviceLoading.value) return
  const name = target.id
  const label = serviceLabel(action)
  const body = action === 'stop'
    ? `确定停止 ${name}？停止后该实例的对外服务会立即中断。`
    : action === 'start'
      ? `确定启动 ${name}？`
      : `确定重启 ${name}？实例会短暂中断。`
  const dialog = DialogPlugin.confirm({
    title: `${label}实例`,
    content: body,
    // TDesign Mobile 的 DialogPlugin 默认 confirmBtn/cancelBtn 是空串，
    // 不显式传就不会渲染按钮，只剩正文。
    confirmBtn: '确定',
    cancelBtn: '取消',
    onConfirm: () => {
      dialog.destroy()
      void runService(current, name, action)
    },
  })
}

async function runService(current: AgentStatus, instanceName: string, action: AgentServiceAction): Promise<void> {
  if (serviceLoading.value) return
  serviceLoading.value = true
  serviceError.value = ''
  serviceDetail.value = ''
  serviceLogTail.value = []
  serviceTruncated.value = false
  serviceResult.value = ''
  try {
    const result = await serviceAgentInstance(current.project, instanceName, action, agent.value?.ip ?? current.ip)
    serviceResult.value = `${instanceName} 已${serviceLabel(action)}（${result.state}）`
    await loadHistory()
    await loadServerEvents()
    await refresh(true)
  } catch (reason) {
    const failure = serviceFailure(reason)
    serviceError.value = failure?.title || errorText(reason)
    serviceDetail.value = failure?.detail || ''
    serviceLogTail.value = failure?.logTail ?? []
    serviceTruncated.value = failure?.truncated ?? false
    // 失败尝试也会落库，刷新一次记录让“谁动过”可见。
    void loadServerEvents()
  } finally {
    serviceLoading.value = false
  }
}

interface ServiceFailure {
  title: string
  detail: string
  logTail: string[]
  truncated: boolean
}

function serviceFailure(reason: unknown): ServiceFailure | null {
  if (!(reason instanceof JsonApiRequestError)) return null
  const error = (reason.errors[0] ?? {}) as {
    title?: string
    detail?: string
    meta?: { detail?: unknown; logTail?: unknown; truncated?: unknown }
  }
  const meta = error.meta
  if (!meta) return null
  const detail = typeof meta.detail === 'string' ? meta.detail : ''
  const logTail = Array.isArray(meta.logTail)
    ? meta.logTail.filter((line): line is string => typeof line === 'string')
    : []
  if (!detail && logTail.length === 0) return null
  return {
    title: error.title || '节点应答失败',
    detail: detail || error.detail || reason.message,
    logTail,
    truncated: meta.truncated === true,
  }
}

watch([agentIdentity, instanceId], () => {
  // 切换实例/节点时先清掉上一页的结果，避免旧历史或旧失败信息挂在新标题下。
  history.value = null
  historyError.value = ''
  serviceError.value = ''
  serviceDetail.value = ''
  serviceLogTail.value = []
  serviceTruncated.value = false
  serviceResult.value = ''
  if (!agent.value || !instance.value) return
  void loadHistory()
  void loadServerEvents()
  openLogWindow()
}, { immediate: true })
</script>
