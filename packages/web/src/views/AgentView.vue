<template>
  <section class="page-panel agent-page">
    <div class="page-head">
      <div>
        <h2 class="page-title">在线节点</h2>
        <p class="page-subtitle">
          basctl 主动连到 <code>/api/bashub/monitor/agents/{profile}/channel</code>。
          列表每 30 秒刷新实例摘要；点节点的“刷新”会先让 agent 重报，再拉取完整系统信息。
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
                  :loading="detailLoading[agent.profile] === true"
                  @click="refreshAgent(agent)"
                >
                  刷新
                </t-button>
                <t-button size="small" variant="outline" @click="openHistory(agent)">运行历史</t-button>
                <t-button
                  v-if="agent.supports?.includes('agent:log')"
                  size="small"
                  variant="outline"
                  @click="openAgentLog(agent)"
                >
                  Agent 日志
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
            <div v-else class="instance-table-wrap">
              <table class="instance-table">
                <thead>
                  <tr>
                    <th class="instance-col-index">序号</th>
                    <th>Server</th>
                    <th>状态</th>
                    <th class="instance-col-port">端口</th>
                    <th>应用</th>
                    <th class="instance-col-actions">操作</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="(instance, index) in instancesOf(agent)" :key="instance.id || instance.pid">
                    <td class="instance-index">{{ index + 1 }}</td>
                    <td class="instance-name" :title="instance.id || '-'">{{ instance.id || '-' }}</td>
                    <td>
                      <div class="instance-status">
                        <t-tag
                          size="small"
                          variant="light"
                          :theme="instanceStateTheme(instance)"
                        >
                          {{ instanceStateLabel(instance) }}
                        </t-tag>
                        <span v-if="isRunning(instance)" class="instance-pid">
                          PID {{ instance.pid ?? '-' }}
                        </span>
                      </div>
                    </td>
                    <td>{{ instance.httpPort ?? '-' }}</td>
                    <td class="instance-apps" :title="webappText(instance)">
                      {{ webappText(instance) || '—' }}
                    </td>
                    <td class="instance-actions">
                      <template v-if="instance.id">
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
                      </template>
                      <span v-else class="agent-muted">—</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div class="server-card">
            <div class="server-card-title">节点信息</div>
            <div class="server-card-facts">
              <div class="server-fact server-fact-wide">
                <span>BAS_HOME</span>
                <strong :title="detailFor(agent)?.basHome || '-'">{{ detailFor(agent)?.basHome || '详情未加载' }}</strong>
              </div>
              <div class="server-fact">
                <span>连接时间</span>
                <strong>{{ agent.connectedAt || '-' }}</strong>
              </div>
              <div class="server-fact">
                <span>最近心跳</span>
                <strong>{{ agent.lastSeenAt || '-' }}</strong>
              </div>
              <div class="server-fact">
                <span>最近采样</span>
                <strong>{{ agent.healthAt || '-' }}</strong>
              </div>
              <div class="server-fact">
                <span>实例摘要</span>
                <strong>{{ agent.running ?? 0 }} 运行 / {{ agent.stopped ?? 0 }} 停止</strong>
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
      v-model:visible="historyVisible"
      :header="historyHeader()"
      width="1100px"
      :footer="false"
      @closed="resetHistory"
    >
      <div class="history-toolbar">
        <span class="agent-muted">
          采样窗口与频率由 bashub 的 <code>agent-health-*</code> 配置决定。
        </span>
        <div class="history-tools">
          <t-select
            v-model="historyServer"
            size="small"
            clearable
            filterable
            placeholder="全部 Server"
            style="width: 220px"
          >
            <t-option v-for="id in historyServerIds" :key="id" :value="id" :label="id" />
          </t-select>
          <t-button size="small" variant="outline" :loading="historyLoading" @click="reloadHistory">刷新</t-button>
        </div>
      </div>
      <t-alert v-if="historyError" theme="error" :message="historyError" class="agent-alert" />
      <div v-if="historyLoading && !history" class="agent-muted">正在加载运行历史…</div>
      <div v-else-if="history && historyRows.length === 0" class="agent-muted">所选时间范围内没有采样记录。</div>
      <div v-else-if="history" class="history-list">
        <div class="history-legend">
          <span><i class="history-dot history-dot-running" />运行</span>
          <span><i class="history-dot history-dot-stopped" />停止</span>
          <span><i class="history-dot history-dot-error" />异常</span>
          <span><i class="history-dot history-dot-unknown" />无采样</span>
        </div>
        <article v-for="(row, index) in historyRows" :key="row.id" class="history-card">
          <div class="history-card-head">
            <div class="history-title">
              <span class="history-index">{{ index + 1 }}</span>
              <strong>{{ row.id }}</strong>
              <t-tag size="small" variant="light" :theme="stateTheme(row.lastState)">
                {{ stateLabel(row.lastState) }}
              </t-tag>
            </div>
            <div class="history-summary">
              <span>可用率 {{ row.availability.toFixed(1) }}%</span>
              <span>采样 {{ row.sampledDays }} 天</span>
              <span v-if="row.lastAt">最近 {{ row.lastAt }}</span>
            </div>
          </div>
          <div class="history-strip" aria-label="最近 180 天运行状态">
            <span
              v-for="cell in row.cells"
              :key="cell.date"
              class="history-cell"
              :class="`history-cell-${cell.state}`"
              :title="`${cell.date} · ${cell.title}`"
            />
          </div>
          <div class="history-axis"><span>{{ row.firstDate }}</span><span>{{ row.lastDate }}</span></div>
          <div v-if="row.changes.length" class="history-changes">
            <span class="agent-muted">最近状态变化：</span>
            <span v-for="change in row.changes.slice(0, 8)" :key="`${change.at}-${change.state}`" class="history-change">
              {{ change.at }} {{ stateLabel(change.state) }}
            </span>
          </div>
        </article>
      </div>
    </t-dialog>

    <t-dialog
      v-model:visible="logVisible"
      :header="logHeader()"
      width="900px"
      :footer="false"
      @closed="resetLog"
    >
      <div class="log-toolbar">
        <t-input
          v-model="logInstance"
          placeholder="实例名，如 platform.server1"
          :disabled="logTarget === 'agent' || logFollowing"
        />
        <t-input v-model="logFrom" placeholder="起始行（可选）" :disabled="logFollowing" />
        <t-input v-model="logTo" placeholder="结束行（可选）" :disabled="logFollowing" />
        <t-button theme="primary" :loading="logLoading" :disabled="logFollowing" @click="readLogOnce">
          读取
        </t-button>
        <t-button
          v-if="logTarget === 'instance' && !logFollowing"
          variant="outline"
          :disabled="logLoading"
          @click="startFollowing"
        >
          跟随尾部
        </t-button>
        <t-button
          v-else-if="logTarget === 'instance'"
          theme="danger"
          variant="outline"
          @click="stopFollowing"
        >
          停止跟随
        </t-button>
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

    <t-dialog
      v-model:visible="serviceErrorVisible"
      :header="serviceErrorTitle"
      width="900px"
      :footer="false"
    >
      <p v-if="serviceErrorDetail" class="service-error-detail">{{ serviceErrorDetail }}</p>
      <p v-if="serviceErrorTruncated" class="agent-muted">日志与详情已截断，完整内容请打开实例日志。</p>
      <pre v-if="serviceErrorLogTail.length" class="agent-log">{{ serviceErrorLogTail.join('\n') }}</pre>
    </t-dialog>
  </section>
</template>

<script setup lang="ts">
import { JsonApiRequestError } from '@beangle/ems-app'
import { DialogPlugin, MessagePlugin } from 'tdesign-vue-next'
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  followAgentLog,
  listAgentSummaries,
  listAgents,
  readAgentHistory,
  readAgentOwnLog,
  readAgentLog,
  requestAgentReport,
  serviceAgentInstance,
  type AgentDiskInfo,
  type AgentHealth,
  type AgentHistory,
  type AgentInstance,
  type AgentLogEvent,
  type AgentLogWindow,
  type AgentServiceAction,
  type AgentSummary,
  type AgentStatus,
} from '@/api/agents'

interface HistoryCell {
  date: string
  state: AgentHealth['state'] | 'unknown'
  title: string
}

interface HistoryRow {
  id: string
  lastAt: string
  lastState: AgentHealth['state'] | ''
  availability: number
  sampledDays: number
  firstDate: string
  lastDate: string
  cells: HistoryCell[]
  changes: { at: string; state: AgentHealth['state'] }[]
}

const agents = ref<AgentSummary[]>([])
const details = ref<Record<string, AgentStatus>>({})
const loading = ref(false)
const error = ref('')
const detailLoading = ref<Record<string, boolean>>({})
const serviceLoading = ref<Record<string, boolean>>({})
const serviceErrorVisible = ref(false)
const serviceErrorTitle = ref('节点应答失败')
const serviceErrorDetail = ref('')
const serviceErrorLogTail = ref<string[]>([])
const serviceErrorTruncated = ref(false)

const historyVisible = ref(false)
const historyAgent = ref('')
const historyServer = ref('')
const history = ref<AgentHistory | null>(null)
const historyLoading = ref(false)
const historyError = ref('')

const logVisible = ref(false)
const logAgent = ref('')
const logTarget = ref<'instance' | 'agent'>('instance')
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

const delay = (milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds))

const logHeader = () => {
  if (!logAgent.value) return '实例日志'
  if (logTarget.value === 'agent') return `${logAgent.value} · Agent 日志`
  return logInstance.value
    ? `${logAgent.value} · ${logInstance.value} 日志`
    : `${logAgent.value} · 实例日志`
}

async function load(quiet = false) {
  if (loading.value && quiet) return
  loading.value = true
  if (!quiet) error.value = ''
  try {
    agents.value = await listAgentSummaries()
  } catch (reason) {
    error.value = errorText(reason)
  } finally {
    loading.value = false
  }
}

/** 节点卡片上的“刷新”：先让 agent 重报一次现状，再取摘要与完整详情。 */
async function refreshAgent(agent: AgentSummary) {
  detailLoading.value = { ...detailLoading.value, [agent.profile]: true }
  try {
    await requestAgentReport(agent.profile)
    await delay(900)
    await Promise.all([load(true), loadDetail(agent.profile)])
    MessagePlugin.success(`已刷新 ${agent.profile}`)
  } catch (reason) {
    MessagePlugin.error(errorText(reason))
  } finally {
    detailLoading.value = { ...detailLoading.value, [agent.profile]: false }
  }
}

function detailFor(agent: AgentSummary): AgentStatus | undefined {
  return details.value[agent.profile]
}

async function loadDetail(profile: string) {
  const all = await listAgents()
  const found = all.find((item) => item.profile === profile)
  if (found) details.value = { ...details.value, [profile]: found }
}

function canService(agent: AgentSummary, action: AgentServiceAction): boolean {
  return agent.supports?.includes(`service:${action}`) === true
}

function serviceKey(agent: AgentSummary, instance: AgentInstance): string {
  return `${agent.profile}:${instance.id ?? instance.pid ?? ''}`
}

function confirmService(agent: AgentSummary, instance: AgentInstance, action: AgentServiceAction) {
  const name = instance.id || '该实例'
  const label = action === 'restart' ? '重启' : action === 'stop' ? '停止' : '启动'
  const dialog = DialogPlugin.confirm({
    header: `${label}实例`,
    body: action === 'stop'
      ? `确定停止 ${name}？停止后该实例的对外服务会立即中断。`
      : action === 'start'
        ? `确定启动 ${name}？`
        : `确定${label} ${name}？实例会短暂中断。`,
    onConfirm: () => {
      // 启停要等 agent 回执（后端最多等 120 秒），确认框先关，进度交给
      // 实例按钮的 loading 与结果消息，避免用户以为点击没生效而重复点击。
      dialog.destroy()
      void runService(agent, instance, action)
    },
  })
}

async function runService(agent: AgentSummary, instance: AgentInstance, action: AgentServiceAction) {
  if (!instance.id) return
  const key = serviceKey(agent, instance)
  // 同一实例已有启停请求在途时不再下发，挡住确认框淡出期间的二次点击。
  if (serviceLoading.value[key]) return
  serviceLoading.value = { ...serviceLoading.value, [key]: true }
  try {
    const result = await serviceAgentInstance(agent.profile, instance.id, action)
    const label = action === 'restart' ? '重启' : action === 'stop' ? '停止' : '启动'
    MessagePlugin.success(`${instance.id} 已${label}（${result.state}）`)
    const cached = { ...details.value }
    delete cached[agent.profile]
    details.value = cached
    await load(true)
  } catch (reason) {
    const failure = serviceFailure(reason)
    if (failure) {
      serviceErrorTitle.value = failure.title
      serviceErrorDetail.value = failure.detail
      serviceErrorLogTail.value = failure.logTail
      serviceErrorTruncated.value = failure.truncated
      serviceErrorVisible.value = true
    } else {
      MessagePlugin.error(errorText(reason))
    }
  } finally {
    serviceLoading.value = { ...serviceLoading.value, [key]: false }
  }
}

function openLog(agent: AgentSummary, instance: AgentInstance) {
  logTarget.value = 'instance'
  logAgent.value = agent.profile
  logInstance.value = instance.id || ''
  logFrom.value = ''
  logTo.value = ''
  logError.value = ''
  resetLogWindow()
  logVisible.value = true
  if (logInstance.value) void startFollowing()
}

function openAgentLog(agent: AgentSummary) {
  logTarget.value = 'agent'
  logAgent.value = agent.profile
  logInstance.value = ''
  logFrom.value = ''
  logTo.value = ''
  logError.value = ''
  resetLogWindow()
  logVisible.value = true
  void readLogOnce()
}

async function readLogOnce() {
  if (logLoading.value) return
  stopFollowing()
  if (logTarget.value === 'instance' && !logInstance.value.trim()) {
    logError.value = '请填写实例名'
    return
  }
  logLoading.value = true
  logError.value = ''
  resetLogWindow()
  try {
    const hasRange = logFrom.value.trim() || logTo.value.trim()
    const window = logTarget.value === 'agent'
      ? await readAgentOwnLog(
          logAgent.value,
          logFrom.value,
          logTo.value,
          hasRange ? undefined : LOG_TAIL_LINES,
        )
      : await readAgentLog(
          logAgent.value,
          logInstance.value.trim(),
          logFrom.value,
          logTo.value,
          hasRange ? undefined : LOG_TAIL_LINES,
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
  if (logTarget.value !== 'instance') return
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
  logTarget.value = 'instance'
  logAgent.value = ''
  logInstance.value = ''
  logFrom.value = ''
  logTo.value = ''
  logError.value = ''
  resetLogWindow()
}

function instancesOf(agent: AgentSummary): AgentInstance[] {
  const detail = detailFor(agent)
  if (!detail) {
    return (agent.health ?? []).map((item) => ({
      id: item.id,
      state: item.state,
    }))
  }
  const running = detail.basReport?.instances ?? []
  const declared = detail.basReport?.declared ?? []
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
  return merged.sort(
    (left, right) =>
      (left.id || '').localeCompare(right.id || '', 'zh-CN', { numeric: true, sensitivity: 'base' }) ||
      (left.pid ?? 0) - (right.pid ?? 0),
  )
}

function isRunning(instance: AgentInstance): boolean {
  return instance.state !== 'stopped' && instance.state !== 'error'
}

function instanceStateLabel(instance: AgentInstance): string {
  if (instance.state === 'error') return '异常'
  return isRunning(instance) ? '运行中' : '已停止'
}

function instanceStateTheme(instance: AgentInstance): 'success' | 'warning' | 'danger' {
  if (instance.state === 'error') return 'danger'
  return isRunning(instance) ? 'success' : 'warning'
}

function webappText(instance: AgentInstance): string {
  const labels: string[] = []
  for (const app of instance.webapps ?? []) {
    const label = app.context || app.uri || app.id
    if (label) labels.push(label)
  }
  return labels.join(' · ')
}

function systemText(agent: AgentSummary): string {
  const os = detailFor(agent)?.os?.os
  if (!os) return '点击“刷新”加载'
  return [os.name, os.kernel, os.arch].filter(Boolean).join(' · ') || '不可用'
}

function cpuText(agent: AgentSummary): string {
  const cpu = detailFor(agent)?.os?.cpu
  if (!cpu) return '详情未加载'
  const loads = [cpu.load1, cpu.load5, cpu.load15]
    .filter((value): value is number => typeof value === 'number')
    .join(' / ')
  const cores = typeof cpu.cores === 'number' ? `${cpu.cores} 核` : '核数不可用'
  return loads ? `${cores} · load ${loads}` : cores
}

function memoryText(agent: AgentSummary): string {
  const mem = detailFor(agent)?.os?.mem
  if (!mem || typeof mem.total !== 'number') return '详情未加载'
  if (typeof mem.available !== 'number') return formatBytes(mem.total)
  const used = mem.total - mem.available
  return `${formatBytes(used)} / ${formatBytes(mem.total)}`
}

function diskCountText(agent: AgentSummary): string {
  const disks = detailFor(agent)?.os?.disk ?? []
  if (disks.length === 0) return '详情未加载'
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

const historyServerIds = computed<string[]>(() => {
  const ids = new Set<string>()
  for (const sample of history.value?.samples ?? []) {
    for (const [id, state] of Object.entries(sample.servers ?? {})) {
      if (isHealthState(state)) ids.add(id)
    }
  }
  return [...ids].sort(compareServerIds)
})

const historyRows = computed<HistoryRow[]>(() => {
  const data = history.value
  if (!data) return []
  const dates = recentDateKeys(data.days)
  const samplesByServer = new Map<string, { at: string; state: AgentHealth['state'] }[]>()
  for (const sample of data.samples) {
    if (Number.isNaN(new Date(sample.at).getTime())) continue
    for (const [id, state] of Object.entries(sample.servers ?? {})) {
      if (!isHealthState(state)) continue
      let items = samplesByServer.get(id)
      if (!items) {
        items = []
        samplesByServer.set(id, items)
      }
      items.push({ at: sample.at, state })
    }
  }

  let ids = [...samplesByServer.keys()].sort(compareServerIds)
  if (historyServer.value) ids = ids.filter((id) => id === historyServer.value)

  return ids.map((id) => {
    const samples = samplesByServer.get(id) ?? []
    const byDate = new Map<string, { running: number; stopped: number; error: number }>()
    let lastAt = ''
    let lastState: AgentHealth['state'] | '' = ''
    const changes: { at: string; state: AgentHealth['state'] }[] = []
    for (const sample of samples) {
      const date = localDateKey(new Date(sample.at))
      let day = byDate.get(date)
      if (!day) {
        day = { running: 0, stopped: 0, error: 0 }
        byDate.set(date, day)
      }
      if (sample.state === 'running') day.running++
      else if (sample.state === 'stopped') day.stopped++
      else day.error++
      if (lastState !== sample.state) {
        changes.push({ at: sample.at, state: sample.state })
        lastState = sample.state
      }
      lastAt = sample.at
    }

    let running = 0
    let stopped = 0
    let failed = 0
    let sampledDays = 0
    const cells = dates.map((date): HistoryCell => {
      const day = byDate.get(date)
      if (!day) return { date, state: 'unknown', title: '无采样' }
      running += day.running
      stopped += day.stopped
      failed += day.error
      sampledDays++
      const state = day.error > 0 ? 'error' : day.stopped > 0 ? 'stopped' : 'running'
      return {
        date,
        state,
        title: `${day.running} 运行 / ${day.stopped} 停止 / ${day.error} 异常`,
      }
    })
    const total = running + stopped + failed
    return {
      id,
      lastAt,
      lastState,
      availability: total > 0 ? (running / total) * 100 : 0,
      sampledDays,
      firstDate: dates[0] ?? '',
      lastDate: dates[dates.length - 1] ?? '',
      cells,
      changes: changes.slice(-200).reverse(),
    }
  })
})

function compareServerIds(left: string, right: string): number {
  return left.localeCompare(right, 'zh-CN', { numeric: true, sensitivity: 'base' })
}

function isHealthState(value: unknown): value is AgentHealth['state'] {
  return value === 'running' || value === 'stopped' || value === 'error'
}

function recentDateKeys(count: number): string[] {
  const dates: string[] = []
  const end = new Date()
  end.setHours(12, 0, 0, 0)
  for (let offset = count - 1; offset >= 0; offset--) {
    const day = new Date(end)
    day.setDate(end.getDate() - offset)
    dates.push(localDateKey(day))
  }
  return dates
}

function localDateKey(value: Date): string {
  const month = String(value.getMonth() + 1).padStart(2, '0')
  const day = String(value.getDate()).padStart(2, '0')
  return `${value.getFullYear()}-${month}-${day}`
}

function historyHeader(): string {
  return historyAgent.value ? `${historyAgent.value} · 最近 180 天运行历史` : '运行历史'
}

function stateLabel(state: AgentHealth['state'] | ''): string {
  if (state === 'running') return '运行中'
  if (state === 'stopped') return '已停止'
  if (state === 'error') return '异常'
  return '无采样'
}

function stateTheme(state: AgentHealth['state'] | ''): 'success' | 'warning' | 'danger' | 'default' {
  if (state === 'running') return 'success'
  if (state === 'stopped') return 'warning'
  if (state === 'error') return 'danger'
  return 'default'
}

async function openHistory(agent: AgentSummary) {
  historyAgent.value = agent.profile
  historyServer.value = ''
  history.value = null
  historyError.value = ''
  historyVisible.value = true
  await reloadHistory()
}

async function reloadHistory() {
  if (!historyAgent.value || historyLoading.value) return
  historyLoading.value = true
  historyError.value = ''
  try {
    history.value = await readAgentHistory(historyAgent.value, { days: 180 })
  } catch (reason) {
    historyError.value = errorText(reason)
  } finally {
    historyLoading.value = false
  }
}

function resetHistory() {
  historyAgent.value = ''
  historyServer.value = ''
  history.value = null
  historyError.value = ''
}

onMounted(() => {
  void load()
  timer = setInterval(() => void load(true), 30_000)
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

.instance-table-wrap {
  margin-top: 8px;
  overflow-x: auto;
}

.instance-table {
  width: 100%;
  min-width: 680px;
  border-collapse: collapse;
  font-size: 13px;
}

.instance-table th,
.instance-table td {
  padding: 8px 10px;
  border-top: 1px solid var(--td-component-stroke);
  text-align: left;
  vertical-align: middle;
}

.instance-table th {
  color: var(--td-text-color-placeholder);
  font-size: 12px;
  font-weight: 500;
  white-space: nowrap;
}

.instance-col-index {
  width: 44px;
}

.instance-col-port {
  width: 64px;
}

.instance-col-actions {
  width: 1%;
  text-align: right !important;
}

.instance-index {
  color: var(--td-text-color-placeholder);
  font-variant-numeric: tabular-nums;
  text-align: right !important;
}

.instance-name {
  max-width: 220px;
  overflow: hidden;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.instance-status {
  display: flex;
  align-items: center;
  gap: 6px;
  white-space: nowrap;
}

.instance-pid {
  color: var(--td-text-color-secondary);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}

.instance-apps {
  max-width: 240px;
  min-width: 0;
  overflow: hidden;
  color: var(--td-text-color-secondary);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.instance-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  flex-shrink: 0;
  gap: 6px;
  white-space: nowrap;
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

.service-error-detail {
  margin: 0 0 12px;
  color: var(--td-text-color-primary);
  white-space: pre-wrap;
  word-break: break-word;
}

.history-toolbar,
.history-card-head,
.history-title,
.history-summary,
.history-legend,
.history-changes,
.history-axis {
  display: flex;
  align-items: center;
}

.history-toolbar {
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}

.history-tools {
  display: flex;
  align-items: center;
  gap: 8px;
}

.history-list {
  display: grid;
  gap: 12px;
}

.history-legend {
  flex-wrap: wrap;
  gap: 14px;
  color: var(--td-text-color-secondary);
  font-size: 12px;
}

.history-legend span {
  display: inline-flex;
  align-items: center;
  gap: 5px;
}

.history-dot {
  width: 9px;
  height: 9px;
  border-radius: 2px;
}

.history-dot-running,
.history-cell-running {
  background: var(--td-success-color, #2ba471);
}

.history-dot-stopped,
.history-cell-stopped {
  background: var(--td-warning-color, #e37318);
}

.history-dot-error,
.history-cell-error {
  background: var(--td-error-color, #d54941);
}

.history-dot-unknown,
.history-cell-unknown {
  background: var(--td-component-stroke, #dcdcdc);
}

.history-card {
  padding: 12px 14px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container-hover);
}

.history-card-head {
  justify-content: space-between;
  gap: 12px;
}

.history-title {
  min-width: 0;
  gap: 8px;
}

.history-title strong {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.history-index {
  color: var(--td-text-color-placeholder);
  font-variant-numeric: tabular-nums;
}

.history-summary {
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 10px;
  color: var(--td-text-color-secondary);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}

.history-strip {
  display: grid;
  grid-template-columns: repeat(180, minmax(0, 1fr));
  gap: 1px;
  height: 18px;
  margin-top: 10px;
  overflow: hidden;
  border-radius: 3px;
}

.history-cell {
  min-width: 0;
}

.history-axis {
  justify-content: space-between;
  margin-top: 4px;
  color: var(--td-text-color-placeholder);
  font-size: 11px;
}

.history-changes {
  flex-wrap: wrap;
  gap: 6px 12px;
  margin-top: 6px;
  color: var(--td-text-color-secondary);
  font-size: 12px;
}

.history-change {
  white-space: nowrap;
}

@media (max-width: 760px) {
  .agent-layout {
    grid-template-columns: 1fr;
  }

  .agent-card-head,
  .log-toolbar {
    align-items: flex-start;
    flex-direction: column;
  }

  .agent-title-row {
    align-items: flex-start;
    flex-wrap: wrap;
  }

  .history-toolbar,
  .history-card-head {
    align-items: flex-start;
    flex-direction: column;
  }

  .history-summary {
    justify-content: flex-start;
  }
}
</style>
