<template>
  <section class="page-panel agent-page">
    <div class="page-head">
      <div>
        <h2 class="page-title">在线节点</h2>
        <p class="page-subtitle">
          basctl 主动连到 <code>/api/{profile}/agents</code> 后上报的系统快照与运行实例。
          每 10 秒刷新一次。
        </p>
      </div>
      <div class="page-actions">
        <t-button variant="outline" :loading="loading" @click="load()">刷新</t-button>
      </div>
    </div>

    <t-alert v-if="error" theme="error" :message="error" class="agent-alert" />

    <div v-if="!loading && agents.length === 0" class="agent-empty">
      <t-empty description="没有在线节点，请先在生产机启动 basctl agent。" />
    </div>

    <div v-else class="agent-grid">
      <t-card v-for="agent in agents" :key="agent.profile" :bordered="true" class="agent-card">
        <div class="agent-card-head">
          <div class="agent-identity">
            <div class="agent-title-row">
              <div class="agent-name">
                <h3>{{ agent.host || agent.profile }}</h3>
                <t-tag theme="success" variant="light">在线</t-tag>
              </div>
              <div class="agent-actions">
                <t-button
                  size="small"
                  variant="outline"
                  :loading="reporting[agent.profile] === true"
                  @click="requestReport(agent)"
                >
                  立即上报
                </t-button>
              </div>
            </div>
            <p class="agent-profile">
              {{ agent.profile }}
              <span v-if="agent.basctl"> · basctl {{ agent.basctl }}</span>
              <span v-if="agent.bas"> · BAS {{ agent.bas }}</span>
            </p>
          </div>
        </div>

        <div class="agent-layout">
          <div class="agent-section">
            <div class="agent-section-title">
              <span>实例</span>
              <span class="agent-muted">{{ instancesOf(agent).length }} 个</span>
            </div>
            <div v-if="instancesOf(agent).length === 0" class="agent-muted">暂无已声明实例</div>
            <div
              v-for="instance in instancesOf(agent)"
              :key="instance.id || instance.pid"
              class="instance-row"
            >
              <div class="instance-row-head">
                <div class="instance-main">
                  <strong>{{ instance.id || '-' }}</strong>
                  <t-tag
                    size="small"
                    variant="light"
                    :theme="isRunning(instance) ? 'success' : 'warning'"
                  >
                    {{ isRunning(instance) ? '运行中' : '已停止' }}
                  </t-tag>
                  <span v-if="isRunning(instance)">PID {{ instance.pid ?? '-' }}</span>
                  <span>端口 {{ instance.httpPort ?? '-' }}</span>
                  <span>{{ instance.engine || '-' }}</span>
                  <span
                    v-if="webappText(instance)"
                    class="instance-apps-text"
                    :title="webappText(instance)"
                  >
                    {{ webappText(instance) }}
                  </span>
                </div>
                <div v-if="instance.id" class="instance-actions">
                  <t-button
                    size="small"
                    variant="text"
                    @click="openLog(agent, instance)"
                  >
                    查看日志
                  </t-button>
                  <t-button
                    v-if="!isRunning(instance) && canService(agent, 'start')"
                    size="small"
                    theme="primary"
                    :loading="serviceLoading[serviceKey(agent, instance)] === true"
                    @click="confirmService(agent, instance, 'start')"
                  >
                    启动
                  </t-button>
                  <t-button
                    v-if="isRunning(instance) && canService(agent, 'restart')"
                    size="small"
                    variant="outline"
                    :loading="serviceLoading[serviceKey(agent, instance)] === true"
                    @click="confirmService(agent, instance, 'restart')"
                  >
                    重启
                  </t-button>
                  <t-button
                    v-if="isRunning(instance) && canService(agent, 'stop')"
                    size="small"
                    theme="danger"
                    variant="outline"
                    :loading="serviceLoading[serviceKey(agent, instance)] === true"
                    @click="confirmService(agent, instance, 'stop')"
                  >
                    停止
                  </t-button>
                </div>
              </div>
            </div>
          </div>

          <div class="server-card">
            <div class="server-card-title">节点信息</div>
            <div class="server-card-facts">
              <div class="server-fact server-fact-wide">
                <span>BAS_HOME</span>
                <strong :title="agent.basHome || '-'">{{ agent.basHome || '-' }}</strong>
              </div>
              <div class="server-fact">
                <span>连接时间</span>
                <strong>{{ agent.connectedAt || '-' }}</strong>
              </div>
              <div class="server-fact">
                <span>最近心跳</span>
                <strong>{{ agent.lastSeenAt || '-' }}</strong>
              </div>
              <div class="server-fact server-fact-wide">
                <span>系统</span>
                <strong :title="systemText(agent)">{{ systemText(agent) }}</strong>
              </div>
            </div>
            <div class="server-metrics">
              <span>CPU {{ cpuText(agent) }}</span>
              <span>内存 {{ memoryText(agent) }}</span>
              <span>磁盘 {{ diskCountText(agent) }}</span>
            </div>
          </div>
        </div>
      </t-card>
    </div>

    <t-dialog
      v-model:visible="logVisible"
      :header="logHeader()"
      width="900px"
      :footer="false"
      @closed="resetLog"
    >
      <div class="log-toolbar">
        <t-input v-model="logInstance" placeholder="实例名，如 platform.server1" :disabled="logFollowing" />
        <t-input v-model="logFrom" placeholder="起始行（可选）" :disabled="logFollowing" />
        <t-input v-model="logTo" placeholder="结束行（可选）" :disabled="logFollowing" />
        <t-button theme="primary" :loading="logLoading" :disabled="logFollowing" @click="readLogOnce">
          读取
        </t-button>
        <t-button v-if="!logFollowing" variant="outline" :disabled="logLoading" @click="startFollowing">
          跟随尾部
        </t-button>
        <t-button v-else theme="danger" variant="outline" @click="stopFollowing">停止跟随</t-button>
      </div>
      <t-alert v-if="logError" theme="error" :message="logError" class="agent-alert" />
      <div class="log-status">
        <t-tag v-if="logReconnecting" theme="warning" variant="light">重连中</t-tag>
        <t-tag v-else-if="logFollowing" theme="success" variant="light">跟随中</t-tag>
        <t-tag v-else-if="logLoading" variant="light">连接中</t-tag>
        <span v-if="logLoaded" class="log-meta">
          共 {{ logTotal }} 行 · 当前显示 {{ logLines.length }} 行
        </span>
        <t-button v-if="logLoaded" size="small" variant="text" @click="clearLogView">清空</t-button>
      </div>
      <pre v-if="logLoaded" ref="logRef" class="agent-log">{{ logLines.join('\n') || '（空）' }}</pre>
    </t-dialog>
  </section>
</template>

<script setup lang="ts">
import { DialogPlugin, MessagePlugin } from 'tdesign-vue-next'
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  followAgentLog,
  listAgents,
  readAgentLog,
  requestAgentReport,
  serviceAgentInstance,
  type AgentDiskInfo,
  type AgentInstance,
  type AgentLogEvent,
  type AgentLogWindow,
  type AgentServiceAction,
  type AgentStatus,
} from '@/api/agents'

const agents = ref<AgentStatus[]>([])
const loading = ref(false)
const error = ref('')
const reporting = ref<Record<string, boolean>>({})
const serviceLoading = ref<Record<string, boolean>>({})

const logVisible = ref(false)
const logAgent = ref('')
const logInstance = ref('')
const logFrom = ref('')
const logTo = ref('')
const logLoading = ref(false)
const logError = ref('')
const logLoaded = ref(false)
const logFollowing = ref(false)
const logReconnecting = ref(false)
const logLines = ref<string[]>([])
const logTotal = ref(0)
const logRef = ref<HTMLElement>()

let timer: ReturnType<typeof setInterval> | undefined
let logSource: EventSource | undefined
let logGeneration = 0

const LOG_TAIL_LINES = 200
const LOG_MAX_LINES = 2000

const logHeader = () => {
  if (!logAgent.value) return '实例日志'
  return logInstance.value
    ? `${logAgent.value} · ${logInstance.value} 日志`
    : `${logAgent.value} · 实例日志`
}

async function load(quiet = false) {
  if (loading.value && quiet) return
  loading.value = true
  if (!quiet) error.value = ''
  try {
    agents.value = await listAgents()
  } catch (reason) {
    error.value = errorText(reason)
  } finally {
    loading.value = false
  }
}

async function requestReport(agent: AgentStatus) {
  reporting.value = { ...reporting.value, [agent.profile]: true }
  try {
    await requestAgentReport(agent.profile)
    MessagePlugin.success(`已请求 ${agent.profile} 立即上报`)
    setTimeout(() => void load(true), 800)
  } catch (reason) {
    MessagePlugin.error(errorText(reason))
  } finally {
    reporting.value = { ...reporting.value, [agent.profile]: false }
  }
}

function canService(agent: AgentStatus, action: AgentServiceAction): boolean {
  return agent.supports?.includes(`service:${action}`) === true
}

function serviceKey(agent: AgentStatus, instance: AgentInstance): string {
  return `${agent.profile}:${instance.id ?? instance.pid ?? ''}`
}

function confirmService(agent: AgentStatus, instance: AgentInstance, action: AgentServiceAction) {
  const name = instance.id || '该实例'
  const label = action === 'restart' ? '重启' : action === 'stop' ? '停止' : '启动'
  const dialog = DialogPlugin.confirm({
    header: `${label}实例`,
    body: action === 'stop'
      ? `确定停止 ${name}？停止后该实例的对外服务会立即中断。`
      : action === 'start'
        ? `确定启动 ${name}？`
        : `确定${label} ${name}？实例会短暂中断。`,
    onConfirm: async () => {
      await runService(agent, instance, action)
      dialog.destroy()
    },
  })
}

async function runService(agent: AgentStatus, instance: AgentInstance, action: AgentServiceAction) {
  if (!instance.id) return
  const key = serviceKey(agent, instance)
  serviceLoading.value = { ...serviceLoading.value, [key]: true }
  try {
    const result = await serviceAgentInstance(agent.profile, instance.id, action)
    const label = action === 'restart' ? '重启' : action === 'stop' ? '停止' : '启动'
    MessagePlugin.success(`${instance.id} 已${label}（${result.state}）`)
    await load(true)
  } catch (reason) {
    MessagePlugin.error(errorText(reason))
  } finally {
    serviceLoading.value = { ...serviceLoading.value, [key]: false }
  }
}

function openLog(agent: AgentStatus, instance: AgentInstance) {
  logAgent.value = agent.profile
  logInstance.value = instance.id || ''
  logFrom.value = ''
  logTo.value = ''
  logError.value = ''
  resetLogWindow()
  logVisible.value = true
  if (logInstance.value) void startFollowing()
}

async function readLogOnce() {
  if (logLoading.value) return
  stopFollowing()
  if (!logInstance.value.trim()) {
    logError.value = '请填写实例名'
    return
  }
  logLoading.value = true
  logError.value = ''
  resetLogWindow()
  try {
    const window = await readAgentLog(
      logAgent.value,
      logInstance.value.trim(),
      logFrom.value,
      logTo.value,
      !logFrom.value.trim() && !logTo.value.trim() ? LOG_TAIL_LINES : undefined,
    )
    applyWindow(window)
  } catch (reason) {
    logError.value = errorText(reason)
  } finally {
    logLoading.value = false
  }
}

/** 打开 SSE：首次取尾部，之后服务端推送增量；断线由 EventSource 自动重连。 */
function startFollowing() {
  if (logLoading.value) return
  stopFollowing()
  const generation = logGeneration
  if (!logInstance.value.trim()) {
    logError.value = '请填写实例名'
    return
  }
  logLoading.value = true
  logError.value = ''
  resetLogWindow()
  const source = followAgentLog(logAgent.value, logInstance.value.trim(), LOG_TAIL_LINES)
  logSource = source

  source.onopen = () => {
    if (generation !== logGeneration) {
      source.close()
      return
    }
    logLoading.value = false
    logFollowing.value = true
    logReconnecting.value = false
    logError.value = ''
  }

  source.addEventListener('lines', (event) => {
    if (generation !== logGeneration) return
    const window = parseLogEvent(event)
    if (!window) {
      source.close()
      logSource = undefined
      logFollowing.value = false
      logLoading.value = false
      logError.value = '日志数据异常，请重新打开'
      return
    }
    const stickToBottom = nearBottom()
    applyWindow(window, window.reset === true, stickToBottom)
    logFollowing.value = true
    logReconnecting.value = false
    logLoading.value = false
    logError.value = ''
  })

  source.addEventListener('failure', (event) => {
    if (generation !== logGeneration) return
    source.close()
    if (logSource === source) logSource = undefined
    logFollowing.value = false
    logReconnecting.value = false
    logLoading.value = false
    logError.value = failureText(event)
  })

  source.onerror = () => {
    if (generation !== logGeneration) return
    logLoading.value = false
    logReconnecting.value = true
    logError.value = '日志连接中断，正在自动重连…'
  }
}

function applyWindow(window: AgentLogWindow, reset = false, stickToBottom = true) {
  if (reset || logLines.value.length === 0) {
    logLines.value = window.lines.slice(-LOG_MAX_LINES)
  } else {
    logLines.value.push(...window.lines)
    if (logLines.value.length > LOG_MAX_LINES) {
      logLines.value.splice(0, logLines.value.length - LOG_MAX_LINES)
    }
  }
  logTotal.value = window.total
  logLoaded.value = true
  if (stickToBottom) scrollToBottom()
}

function stopFollowing() {
  logGeneration++
  if (logSource) {
    logSource.close()
    logSource = undefined
  }
  logFollowing.value = false
  logReconnecting.value = false
  logLoading.value = false
}

function resetLogWindow() {
  logLines.value = []
  logTotal.value = 0
  logLoaded.value = false
}

function parseLogEvent(event: Event): AgentLogEvent | null {
  try {
    const value = JSON.parse((event as MessageEvent<string>).data) as AgentLogEvent
    return Array.isArray(value.lines) ? value : null
  } catch {
    return null
  }
}

function failureText(event: Event): string {
  try {
    const value = JSON.parse((event as MessageEvent<string>).data) as { error?: string }
    if (value.error) return value.error
    return '日志连接已中断，请重新打开'
  } catch {
    return '日志连接已中断，请重新打开'
  }
}

function clearLogView() {
  logLines.value = []
  logLoaded.value = false
}

function nearBottom(): boolean {
  const element = logRef.value
  if (!element) return true
  return element.scrollHeight - element.scrollTop - element.clientHeight < 40
}

function scrollToBottom() {
  void nextTick(() => {
    const element = logRef.value
    if (element) element.scrollTop = element.scrollHeight
  })
}

function resetLog() {
  stopFollowing()
  logAgent.value = ''
  logInstance.value = ''
  logFrom.value = ''
  logTo.value = ''
  logError.value = ''
  resetLogWindow()
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
    if (!instance.id || runningById.has(instance.id)) {
      merged.push({ ...instance, state: 'running' })
    }
  }
  return merged
}

function isRunning(instance: AgentInstance): boolean {
  return instance.state !== 'stopped'
}

function webappText(instance: AgentInstance): string {
  const labels: string[] = []
  for (const app of instance.webapps ?? []) {
    const label = app.context || app.uri || app.id
    if (label) labels.push(label)
  }
  return labels.join(' · ')
}

function systemText(agent: AgentStatus): string {
  const os = agent.os?.os
  if (!os) return '不可用'
  return [os.name, os.kernel, os.arch].filter(Boolean).join(' · ') || '不可用'
}

function cpuText(agent: AgentStatus): string {
  const cpu = agent.os?.cpu
  if (!cpu) return '不可用'
  const loads = [cpu.load1, cpu.load5, cpu.load15]
    .filter((value): value is number => typeof value === 'number')
    .join(' / ')
  const cores = typeof cpu.cores === 'number' ? `${cpu.cores} 核` : '核数不可用'
  return loads ? `${cores} · load ${loads}` : cores
}

function memoryText(agent: AgentStatus): string {
  const mem = agent.os?.mem
  if (!mem || typeof mem.total !== 'number') return '不可用'
  if (typeof mem.available !== 'number') return formatBytes(mem.total)
  const used = mem.total - mem.available
  return `${formatBytes(used)} / ${formatBytes(mem.total)}`
}

function diskCountText(agent: AgentStatus): string {
  const disks = agent.os?.disk ?? []
  if (disks.length === 0) return '不可用'
  const root = disks.find((disk) => disk.mount === '/') ?? disks[0]
  return `${disks.length} 个挂载点 · ${diskText(root)}`
}

function diskText(disk: AgentDiskInfo): string {
  if (typeof disk.total !== 'number') return disk.mount || '不可用'
  const available = typeof disk.available === 'number' ? `，可用 ${formatBytes(disk.available)}` : ''
  return `${disk.mount || '-'} ${formatBytes(disk.total)}${available}`
}

function formatBytes(value: number): string {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  let amount = value
  let unit = 0
  while (amount >= 1024 && unit < units.length - 1) {
    amount /= 1024
    unit++
  }
  return `${amount >= 10 || unit === 0 ? amount.toFixed(0) : amount.toFixed(1)} ${units[unit]}`
}

function errorText(reason: unknown): string {
  return reason instanceof Error ? reason.message : String(reason)
}

onMounted(() => {
  void load()
  timer = setInterval(() => void load(true), 10_000)
})

onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
  stopFollowing()
})
</script>

<style scoped>
.agent-alert {
  margin-bottom: 16px;
}

.agent-empty {
  padding: 48px 16px;
  border: 1px dashed var(--td-component-stroke);
  border-radius: 6px;
  color: var(--td-text-color-secondary);
}

.agent-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 16px;
  padding: 8px;
}

.agent-card-head,
.agent-section-title,
.agent-title-row,
.agent-name,
.instance-main,
.log-toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
}

.agent-card-head {
  align-items: flex-start;
}

.agent-title-row {
  justify-content: space-between;
}

.agent-identity {
  flex: 1;
  min-width: 0;
}

.agent-card-head h3,
.agent-name h3 {
  margin: 0;
  font-size: 17px;
}

.agent-profile {
  margin: 2px 0 0;
  color: var(--td-text-color-placeholder);
  font-size: 13px;
}

.agent-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.agent-layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(300px, 380px);
  align-items: start;
  gap: 16px;
  margin-top: 12px;
}

.server-card {
  box-sizing: border-box;
  width: 100%;
  padding: 10px 12px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container-hover);
}

.server-card-title {
  margin-bottom: 6px;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
  font-weight: 600;
}

.server-card-facts {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 6px 14px;
}

.server-fact {
  min-width: 0;
}

.server-fact-wide {
  grid-column: 1 / -1;
}

.server-fact > span {
  display: block;
  color: var(--td-text-color-placeholder);
  font-size: 11px;
}

.server-fact > strong {
  display: block;
  overflow: hidden;
  font-size: 12px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.server-metrics {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 14px;
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid var(--td-component-stroke);
  color: var(--td-text-color-secondary);
  font-size: 12px;
}

.agent-muted {
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.agent-section {
  min-width: 0;
}

.agent-section-title {
  justify-content: space-between;
  margin-bottom: 4px;
  font-weight: 600;
}

.instance-row {
  padding: 8px 0;
  border-top: 1px solid var(--td-component-stroke);
}

.instance-row-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.instance-main {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  font-size: 13px;
  white-space: nowrap;
}

.instance-main > strong,
.instance-main > span {
  flex-shrink: 0;
}

.instance-main > .instance-apps-text {
  flex-shrink: 1;
  min-width: 60px;
  overflow: hidden;
  color: var(--td-text-color-placeholder);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.instance-actions {
  display: flex;
  flex-shrink: 0;
  gap: 6px;
}

.log-toolbar {
  align-items: stretch;
  margin-bottom: 12px;
}

.log-toolbar :deep(.t-input) {
  flex: 1 1 0;
  min-width: 0;
}

.log-toolbar :deep(.t-button) {
  flex: 0 0 auto;
}

.log-status {
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 24px;
  margin-bottom: 8px;
}

.log-meta {
  margin-bottom: 8px;
  color: var(--td-text-color-secondary);
  font-size: 13px;
}

.agent-log {
  max-height: 520px;
  margin: 0;
  overflow: auto;
  padding: 12px;
  border-radius: 6px;
  background: var(--td-bg-color-container-hover);
  font-family: 'Andale Mono', ui-monospace, monospace;
  font-size: 13px;
  white-space: pre-wrap;
  word-break: break-all;
}

@media (max-width: 760px) {
  .agent-layout {
    grid-template-columns: 1fr;
  }

  .agent-card-head,
  .instance-row-head,
  .log-toolbar {
    align-items: flex-start;
    flex-direction: column;
  }

  .agent-title-row {
    align-items: flex-start;
    flex-wrap: wrap;
  }
}
</style>
