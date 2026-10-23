<template>
  <section class="page-panel agent-page">
    <div class="page-head">
      <div>
        <h2 class="page-title">在线节点</h2>
      </div>
      <div v-if="profileOptions.length > 1" class="page-actions">
        <t-select
          v-model="selectedProfile"
          class="profile-select"
          :options="profileOptions"
          filterable
          placeholder="选择 Profile"
        />
      </div>
    </div>

    <t-alert v-if="error" theme="error" :message="error" class="agent-alert" />

    <div v-if="!loading && agents.length === 0" class="agent-empty">
      <t-empty description="没有在线节点，请先在生产机启动 basctl agent。" />
    </div>

    <div v-else class="agent-grid">
      <section v-for="group in visibleGroups" :key="group.profile" class="agent-group">
        <div class="agent-card-head">
          <div class="agent-identity">
            <div class="agent-title-row">
              <div class="agent-name">
                <img
                  v-if="groupLogo(group)"
                  class="agent-org-logo"
                  :src="groupLogo(group)"
                  :alt="groupOrgTitle(group)"
                  @error="markLogoFailed(group.profile)"
                />
                <h3>{{ groupTitle(group) }}</h3>
                <t-tag theme="success" variant="light">{{ group.agents.length }} 个 agent</t-tag>
                <span class="agent-profile">
                  {{ group.profile }}
                  · {{ agentGroupRunning(group) }} 运行 / {{ agentGroupStopped(group) }} 停止
                </span>
              </div>
              <div class="agent-actions">
                <t-button size="small" variant="outline" :loading="refreshing" @click="refreshNow">
                  刷新（{{ secondsLeft }}s）
                </t-button>
                <t-button size="small" variant="outline" @click="goHistory(group.profile)">运行历史</t-button>
                <t-button
                  v-if="group.agents[0]?.profileId"
                  size="small"
                  variant="outline"
                  @click="goProfile(group.agents[0].profileId)"
                >
                  配置
                </t-button>
              </div>
            </div>
          </div>
        </div>

        <div class="ip-cards">
          <article v-for="agent in group.agents" :key="agentKey(agent)" class="ip-card">
            <header class="ip-card__head">
              <div class="ip-card__id">
                <div class="ip-card__title">
                  <strong class="ip-card__ip">{{ agent.ip || agent.host || '-' }}</strong>
                  <span v-if="agent.host" class="ip-card__host">{{ agent.host }}</span>
                  <t-tag size="small" theme="success" variant="light">在线</t-tag>
                </div>
                <span class="ip-card__os">{{ osText(agent) }}</span>
              </div>
              <span class="ip-card__count">{{ runningOf(agent) }} 运行 / {{ stoppedOf(agent) }} 停止</span>
            </header>

            <div class="ip-card__body">
              <div class="ip-card__servers">
                <div v-if="agentInstances(agent).length === 0" class="agent-muted">暂无已声明实例</div>
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
                      <tr
                        v-for="(instance, index) in agentInstances(agent)"
                        :key="instance.id || instance.pid"
                      >
                        <td class="instance-index">{{ index + 1 }}</td>
                        <td class="instance-name" :title="instance.id || '-'">{{ instance.id || '-' }}</td>
                        <td>
                          <div class="instance-status">
                            <t-tag size="small" variant="light" :theme="instanceStateTheme(instance)">
                              {{ instanceStateLabel(instance) }}
                            </t-tag>
                            <span v-if="isRunning(instance)" class="instance-pid">
                              PID {{ instance.pid ?? '-' }}
                            </span>
                          </div>
                        </td>
                        <td>{{ instance.httpPort ?? '-' }}</td>
                        <td class="instance-apps">
                          <template v-if="(instance.webapps ?? []).length">
                            <div
                              v-for="app in instance.webapps"
                              :key="app.id || app.uri"
                              class="instance-app"
                            >
                              <code>{{ app.context || '/' }}</code>
                              <span v-if="app.title" class="instance-app-title">{{ app.title }}</span>
                              <span v-if="app.uri" class="instance-app-uri" :title="app.uri">{{ app.uri }}</span>
                            </div>
                          </template>
                          <span v-else class="agent-muted">—</span>
                        </td>
                        <td class="instance-actions">
                          <template v-if="instance.id">
                            <t-button size="small" variant="text" @click="openLog(agent, instance)">查看日志</t-button>
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

              <aside class="ip-card__agent">
                <dl class="agent-conn-facts">
                  <div class="agent-conn-row">
                    <dt>连接</dt>
                    <dd>{{ shortTime(agent.connectedAt) }}</dd>
                  </div>
                  <div class="agent-conn-row">
                    <dt>心跳</dt>
                    <dd>{{ shortTime(agent.lastSeenAt) }}</dd>
                  </div>
                  <div class="agent-conn-row">
                    <dt>BAS_HOME</dt>
                    <dd class="agent-conn-home" :title="agent.basHome || ''">{{ agent.basHome || '-' }}</dd>
                  </div>
                </dl>
                <dl class="agent-conn-metrics">
                  <div class="agent-conn-row">
                    <dt>CPU</dt>
                    <dd>{{ cpuText(agent) }}</dd>
                  </div>
                  <div class="agent-conn-row">
                    <dt>内存</dt>
                    <dd>{{ memoryText(agent) }}</dd>
                  </div>
                  <div class="agent-conn-row">
                    <dt>磁盘</dt>
                    <dd>{{ diskCountText(agent) }}</dd>
                  </div>
                </dl>
                <div v-if="agent.supports?.includes('agent:log')" class="agent-conn-actions">
                  <t-button size="small" variant="outline" @click="openAgentLog(agent)">Agent 日志</t-button>
                </div>
              </aside>
            </div>
          </article>
        </div>
      </section>
    </div>


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
        <t-button
          v-if="logLoaded"
          size="small"
          variant="text"
          title="复制日志"
          :disabled="logLines.length === 0"
          @click="copyLog"
        >
          <template #icon><CopyIcon /></template>
        </t-button>
        <t-button
          v-if="logLoaded"
          size="small"
          variant="text"
          title="下载日志"
          :disabled="logLines.length === 0"
          @click="downloadLog"
        >
          <template #icon><DownloadIcon /></template>
        </t-button>
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
import { CopyIcon, DownloadIcon } from 'tdesign-icons-vue-next'
import { DialogPlugin, MessagePlugin } from 'tdesign-vue-next'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import {
  followAgentLog,
  listAgents,
  readAgentOwnLog,
  readAgentLog,
  requestAgentReport,
  serviceAgentInstance,
  type AgentDiskInfo,
  type AgentInstance,
  type AgentLogEvent,
  type AgentLogWindow,
  type AgentOrganization,
  type AgentServiceAction,
  type AgentStatus,
} from '@/api/agents'

/** 同一个 profile 下的多台 agent（每台一张连接卡片，实例表合并）。 */
interface AgentGroup {
  profile: string
  org?: AgentOrganization
  agents: AgentStatus[]
}

const agents = ref<AgentStatus[]>([])
const loading = ref(false)
const error = ref('')
const serviceLoading = ref<Record<string, boolean>>({})
const serviceErrorVisible = ref(false)
const serviceErrorTitle = ref('节点应答失败')
const serviceErrorDetail = ref('')
const serviceErrorLogTail = ref<string[]>([])
const serviceErrorTruncated = ref(false)


const logVisible = ref(false)
const logAgent = ref('')
const logIp = ref('')
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

const POLL_SECONDS = 30
const secondsLeft = ref(POLL_SECONDS)
const refreshing = ref(false)

let timer: ReturnType<typeof setInterval> | undefined
let logSource: EventSource | undefined
let logGeneration = 0

const LOG_TAIL_LINES = 200
const LOG_MAX_LINES = 2000

const delay = (milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds))

const logHeader = () => {
  if (!logAgent.value) return '实例日志'
  const who = logIp.value ? `${logAgent.value}@${logIp.value}` : logAgent.value
  if (logTarget.value === 'agent') return `${who} · Agent 日志`
  return logInstance.value ? `${who} · ${logInstance.value} 日志` : `${who} · 实例日志`
}

async function load(quiet = false) {
  if (loading.value && quiet) return
  loading.value = true
  if (!quiet) error.value = ''
  try {
    // 一个 profile 可以有多台 agent：/agents/status 每台一项，页面按 profile 分组展示。
    agents.value = await listAgents()
  } catch (reason) {
    error.value = errorText(reason)
  } finally {
    loading.value = false
  }
}

/** 同一 profile 的 agent 归到一张卡片：实例表合并，右侧列各台连接信息。 */
const groups = computed<AgentGroup[]>(() => {
  const byProfile = new Map<string, AgentGroup>()
  for (const agent of agents.value) {
    let group = byProfile.get(agent.profile)
    if (!group) {
      group = { profile: agent.profile, org: agent.org, agents: [] }
      byProfile.set(agent.profile, group)
    }
    group.org ??= agent.org
    group.agents.push(agent)
  }
  return [...byProfile.values()]
})

const MONITOR_PROFILE_KEY = 'bashub.monitor_profile'

function readSelectedProfile(): string {
  try {
    return window.localStorage.getItem(MONITOR_PROFILE_KEY) ?? ''
  } catch {
    return ''
  }
}

/** 多个 profile 同时在线时只展示一个，用右上角下拉切换。 */
const selectedProfile = ref(readSelectedProfile())

function profileLabel(group: AgentGroup): string {
  const title = groupTitle(group)
  return title === group.profile ? group.profile : `${title}（${group.profile}）`
}

const profileOptions = computed(() =>
  groups.value.map((group) => ({ value: group.profile, label: profileLabel(group) })),
)

/** 当前选中的 profile；选中的已经离线时退回第一个。 */
const activeGroup = computed<AgentGroup | undefined>(() => {
  const list = groups.value
  if (!list.length) return undefined
  return list.find((group) => group.profile === selectedProfile.value) ?? list[0]
})

/** 卡片模板按数组渲染，但只放当前选中的那个 profile。 */
const visibleGroups = computed(() => (activeGroup.value ? [activeGroup.value] : []))

watch(
  groups,
  (list) => {
    if (!list.length) return
    if (!list.some((group) => group.profile === selectedProfile.value)) {
      selectedProfile.value = list[0].profile
    }
  },
  { immediate: true },
)

watch(selectedProfile, (value) => {
  try {
    window.localStorage.setItem(MONITOR_PROFILE_KEY, value)
  } catch {
    /* 隐私模式等场景忽略写入失败 */
  }
})

const router = useRouter()

/** 运行历史是独立页面：`/monitor/agents/:profile/history`。 */
function goHistory(profile: string) {
  if (!profile) return
  void router.push(`/monitor/agents/${encodeURIComponent(profile)}/history`)
}

/** 跳到该 profile 的配置详情（管理 server.xml / webapp 的地方）。 */
function goProfile(profileId?: string) {
  if (!profileId) return
  void router.push(`/config/profiles/${encodeURIComponent(profileId)}`)
}

/** 同一 profile 下多台 agent 的键：后端用 `ip` 区分机器，没有 ip 时退回 host。 */
function agentKey(agent: AgentStatus): string {
  return `${agent.profile}@${agent.ip || agent.host || ''}`
}

/** 运行/停止数以实例表为准：service:start 后 agent 先补发 report:bas，health 要等下一次采样。 */
function runningOf(agent: AgentStatus): number {
  return instancesOf(agent).filter(isRunning).length
}

function stoppedOf(agent: AgentStatus): number {
  return instancesOf(agent).filter((instance) => !isRunning(instance)).length
}

function agentGroupRunning(group: AgentGroup): number {
  return group.agents.reduce((sum, agent) => sum + runningOf(agent), 0)
}

function agentGroupStopped(group: AgentGroup): number {
  return group.agents.reduce((sum, agent) => sum + stoppedOf(agent), 0)
}

/** 单台 agent 的实例，按 server 名升序；卡片只展示这台机器的服务，不做跨 agent 合并。 */
function agentInstances(agent: AgentStatus): AgentInstance[] {
  return instancesOf(agent).sort((a, b) => (a.id || '').localeCompare(b.id || '', 'zh-CN', { numeric: true }))
}

/**
 * 手动刷新：让当前 profile 的每台 agent 重报一次，再取一次完整快照，倒计时归零重来。
 * 30 秒自动刷新只重读 `/agents/status`，不打扰 agent。
 */
async function refreshNow() {
  if (refreshing.value) return
  refreshing.value = true
  secondsLeft.value = POLL_SECONDS
  try {
    const group = activeGroup.value
    if (group) {
      const results = await Promise.allSettled(
        group.agents.map((agent) => requestAgentReport(agent.profile, agent.ip)),
      )
      const rejected = results.filter(
        (result): result is PromiseRejectedResult => result.status === 'rejected',
      )
      if (rejected.length === results.length && rejected.length > 0) {
        MessagePlugin.error(errorText(rejected[0].reason))
      }
      await delay(900)
    }
    await load()
  } finally {
    refreshing.value = false
  }
}

/** 加载失败的 Logo 按 profile 记住，避免每次重渲染都再请求一次坏地址。 */
const failedLogos = ref<Record<string, boolean>>({})

/** 卡片大标题：机构标题优先；没有机构信息时退回 profile。 */
function groupOrgTitle(group: AgentGroup): string {
  return group.org?.title || group.org?.shortTitle || group.profile
}

/** 卡片大标题：优先 profile 的说明（title），没有时回退机构标题 / profile 名。 */
function groupTitle(group: AgentGroup): string {
  return group.agents[0]?.profileTitle || groupOrgTitle(group)
}

function groupLogo(group: AgentGroup): string {
  const url = group.org?.logoUrl
  return url && !failedLogos.value[group.profile] ? url : ''
}



/** Logo 加载失败只隐藏图片，标题与在线状态照常显示。 */
function markLogoFailed(profile: string) {
  failedLogos.value = { ...failedLogos.value, [profile]: true }
}

function canService(agent: AgentStatus, action: AgentServiceAction): boolean {
  return agent.supports?.includes(`service:${action}`) === true
}

function serviceKey(agent: AgentStatus, instance: AgentInstance): string {
  return `${agentKey(agent)}:${instance.id ?? instance.pid ?? ''}`
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
    onConfirm: () => {
      // 启停要等 agent 回执（后端最多等 120 秒），确认框先关，进度交给
      // 实例按钮的 loading 与结果消息，避免用户以为点击没生效而重复点击。
      dialog.destroy()
      void runService(agent, instance, action)
    },
  })
}

async function runService(agent: AgentStatus, instance: AgentInstance, action: AgentServiceAction) {
  if (!instance.id) return
  const key = serviceKey(agent, instance)
  // 同一实例已有启停请求在途时不再下发，挡住确认框淡出期间的二次点击。
  if (serviceLoading.value[key]) return
  serviceLoading.value = { ...serviceLoading.value, [key]: true }
  try {
    const result = await serviceAgentInstance(agent.profile, instance.id, action, agent.ip)
    const label = action === 'restart' ? '重启' : action === 'stop' ? '停止' : '启动'
    MessagePlugin.success(`${instance.id} 已${label}（${result.state}）`)
    await waitForServiceSnapshot(agent, instance.id, result.state)
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

/**
 * 启停接口只等到 agent 执行完，agent 随后补发的 `report:bas` 可能晚于 HTTP 响应；
 * 直接取快照常常还是旧状态。短轮询几次，等列表真的反映新状态再收工；
 * 都等不到（agent 慢或报告丢了）就交给 30 秒轮询兜底。
 */
async function waitForServiceSnapshot(
  agent: AgentStatus,
  instance: string,
  expected: 'running' | 'stopped',
) {
  for (const wait of [800, 1200, 1500]) {
    await delay(wait)
    await load(true)
    const current = agents.value.find((item) => agentKey(item) === agentKey(agent))
    const running = (current?.basReport?.instances ?? []).some((item) => item.id === instance)
    if ((expected === 'running') === running) return
  }
}

function openLog(agent: AgentStatus, instance: AgentInstance) {
  logTarget.value = 'instance'
  logAgent.value = agent.profile
  logIp.value = agent.ip || ''
  logInstance.value = instance.id || ''
  logFrom.value = ''
  logTo.value = ''
  logError.value = ''
  resetLogWindow()
  logVisible.value = true
  if (logInstance.value) void startFollowing()
}

function openAgentLog(agent: AgentStatus) {
  logTarget.value = 'agent'
  logAgent.value = agent.profile
  logIp.value = agent.ip || ''
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
          logIp.value || undefined,
        )
      : await readAgentLog(
          logAgent.value,
          logInstance.value.trim(),
          logFrom.value,
          logTo.value,
          hasRange ? undefined : LOG_TAIL_LINES,
          logIp.value || undefined,
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
  const source = followAgentLog(logAgent.value, logInstance.value.trim(), LOG_TAIL_LINES,
    logIp.value || undefined)
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

/** 复制当前窗口内的日志（不含行号，可直接贴到工单/聊天里）。 */
async function copyLog() {
  const text = logLines.value.join('\n')
  if (!text) return
  try {
    await navigator.clipboard.writeText(text)
    MessagePlugin.success(`已复制 ${logLines.value.length} 行日志`)
  } catch (error) {
    MessagePlugin.error(errorText(error) || '复制失败，请检查浏览器剪贴板权限')
  }
}

/** 下载当前窗口内的日志；文件名带 profile、实例与本地时间，便于区分多次抓取。 */
function downloadLog() {
  const text = logLines.value.join('\n')
  if (!text) return
  const url = URL.createObjectURL(new Blob([text], { type: 'text/plain;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = logFileName()
  document.body.appendChild(link)
  link.click()
  link.remove()
  // 立即 revoke 在部分浏览器会取消下载，延后一拍再释放。
  setTimeout(() => URL.revokeObjectURL(url), 1000)
  MessagePlugin.success('日志已下载')
}

function logFileName(): string {
  const now = new Date()
  const pad = (value: number) => String(value).padStart(2, '0')
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`
    + `-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`
  const target = logTarget.value === 'agent' ? 'agent' : logInstance.value || 'instance'
  return `${logAgent.value || 'basctl'}-${target}-${stamp}.log`
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

function instancesOf(agent: AgentStatus): AgentInstance[] {
  const running = agent.basReport?.instances ?? []
  const declared = agent.basReport?.declared ?? []
  if (running.length === 0 && declared.length === 0) {
    return (agent.health ?? []).map((item) => ({
      id: item.id,
      state: item.state,
    }))
  }
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

/** 卡片副标题：操作系统名称与内核版本；还没上报时给一句提示。 */
function osText(agent: AgentStatus): string {
  const os = agent.os?.os
  if (!os) return '系统信息未上报'
  return [os.name, os.kernel].filter(Boolean).join(' · ') || '系统信息未上报'
}

/** 时间只留「月日T时分秒」；时区由服务器 locale 决定，卡面上不重复展示。 */
function shortTime(value?: string): string {
  if (!value) return '-'
  const match = /^\d{4}-(\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})/.exec(value)
  return match ? `${match[1]}T${match[2]}` : value
}

function cpuText(agent: AgentStatus): string {
  const cpu = agent.os?.cpu
  if (!cpu) return '详情未加载'
  const loads = [cpu.load1, cpu.load5, cpu.load15]
    .filter((value): value is number => typeof value === 'number')
    .join(' / ')
  const cores = typeof cpu.cores === 'number' ? `${cpu.cores} 核` : '核数不可用'
  return loads ? `${cores} · load ${loads}` : cores
}

function memoryText(agent: AgentStatus): string {
  const mem = agent.os?.mem
  if (!mem || typeof mem.total !== 'number') return '详情未加载'
  if (typeof mem.available !== 'number') return formatBytes(mem.total)
  const used = mem.total - mem.available
  return `${formatBytes(used)} / ${formatBytes(mem.total)}`
}

function diskCountText(agent: AgentStatus): string {
  const disks = agent.os?.disk ?? []
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

onMounted(() => {
  void load()
  timer = setInterval(() => {
    secondsLeft.value -= 1
    if (secondsLeft.value > 0) return
    secondsLeft.value = POLL_SECONDS
    void load(true)
  }, 1000)
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
  display: flex;
  flex-direction: column;
  gap: 20px;
  padding: 0 12px 16px;
}

/* profile 不再套卡片：标题直接落在页面上，IP 卡片占满整宽。 */
.agent-group {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.agent-card-head,
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

/* 机构 Logo：固定方形，长宽比不一致时留白而不是拉伸。 */
.agent-org-logo {
  flex: 0 0 auto;
  width: 32px;
  height: 32px;
  border-radius: 4px;
  object-fit: contain;
}

/* 右上角的 profile 切换；窄屏下占满整行。 */
.profile-select {
  width: 280px;
  max-width: 100%;
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

/* 每台 agent（IP）一张卡片：左侧该机器的 server 表，右侧连接信息。 */
.ip-cards {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.ip-card {
  overflow: hidden;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container);
}

.ip-card__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 14px;
  border-bottom: 1px solid var(--td-component-stroke);
  background: var(--td-bg-color-container-hover);
}

.ip-card__id {
  min-width: 0;
}

.ip-card__title {
  display: flex;
  align-items: center;
  min-width: 0;
  gap: 8px;
}

.ip-card__ip {
  font-size: 15px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.ip-card__host {
  overflow: hidden;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ip-card__os {
  display: block;
  margin-top: 2px;
  overflow: hidden;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ip-card__count {
  flex: none;
  color: var(--td-text-color-secondary);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}

.ip-card__body {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 280px;
  align-items: start;
}

.ip-card__servers {
  min-width: 0;
}

.ip-card__servers .instance-table-wrap {
  margin-top: 0;
}

.ip-card__agent {
  padding: 10px 14px;
  border-left: 1px solid var(--td-component-stroke);
}

.ip-card__agent .agent-conn-facts,
.ip-card__agent .agent-conn-metrics {
  padding: 8px 0;
}

.ip-card__agent .agent-conn-actions {
  padding: 8px 0 0;
  border-top: 0;
  background: none;
}

/* BAS_HOME 的值：等宽字体便于辨认路径，过长时省略。 */
.agent-conn-home {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  color: var(--td-text-color-secondary);
  font-family: 'Andale Mono', ui-monospace, monospace;
  font-size: 11px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-conn-facts,
.agent-conn-metrics {
  margin: 0;
  padding: 8px 12px;
  border-top: 1px solid var(--td-component-stroke);
}

.agent-conn-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  padding: 2px 0;
}

.agent-conn-row dt {
  flex: 0 0 auto;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.agent-conn-row dd {
  min-width: 0;
  margin: 0;
  overflow-wrap: anywhere;
  color: var(--td-text-color-primary);
  font-size: 12px;
  text-align: right;
}

.agent-conn-actions {
  display: flex;
  gap: 8px;
  padding: 8px 12px;
  border-top: 1px solid var(--td-component-stroke);
  background: var(--td-bg-color-container-hover);
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
  min-width: 0;
  color: var(--td-text-color-secondary);
  font-size: 12px;
}

.instance-app {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 2px 6px;
  padding: 1px 0;
}

.instance-app code {
  padding: 0 4px;
  border-radius: 3px;
  background: var(--td-bg-color-container-hover);
  font-family: 'Andale Mono', ui-monospace, monospace;
  font-size: 11px;
}

.instance-app-title {
  color: var(--td-text-color-primary);
}

.instance-app-uri {
  min-width: 0;
  overflow-wrap: anywhere;
  color: var(--td-text-color-placeholder);
  font-family: 'Andale Mono', ui-monospace, monospace;
  font-size: 11px;
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


@media (max-width: 760px) {
  .ip-card__body {
    grid-template-columns: 1fr;
  }

  .ip-card__agent {
    border-top: 1px solid var(--td-component-stroke);
    border-left: 0;
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
}
</style>
