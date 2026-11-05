<template>
  <section class="page-panel server-detail-page">
    <div class="page-head">
      <div>
        <t-button size="small" variant="text" @click="goBack">← 返回</t-button>
        <h2 class="page-title">{{ instance?.id || 'Server 详情' }}</h2>
        <p v-if="agent" class="page-subtitle">
          {{ agent.project }}<template v-if="agent.ip"> · {{ agent.ip }}</template>
          <template v-if="agent.host"> / {{ agent.host }}</template>
        </p>
      </div>
      <div class="page-actions">
        <t-button size="small" variant="outline" :loading="loading" @click="load">刷新</t-button>
      </div>
    </div>

    <t-alert v-if="error" theme="error" :message="error" />

    <div v-if="!loading && !agent" class="empty-panel">
      <t-empty description="节点不在线" />
    </div>
    <div v-else-if="!loading && !instance" class="empty-panel">
      <t-empty description="实例不存在或已从配置中移除" />
    </div>

    <template v-else-if="instance && agent">
      <article class="detail-card">
        <header class="detail-card__head">
          <div>
            <h3>运行状态</h3>
            <p>来自 agent 最近一次上报</p>
          </div>
          <div class="detail-actions">
            <t-button
              v-if="!isRunning(instance)"
              size="small"
              theme="primary"
              :disabled="!canService('start')"
              :loading="serviceLoading"
              @click="confirmService('start')"
            >启动</t-button>
            <t-button
              v-if="isRunning(instance)"
              size="small"
              variant="outline"
              :disabled="!canService('restart')"
              :loading="serviceLoading"
              @click="confirmService('restart')"
            >重启</t-button>
            <t-button
              v-if="isRunning(instance)"
              size="small"
              theme="danger"
              variant="outline"
              :disabled="!canService('stop')"
              :loading="serviceLoading"
              @click="confirmService('stop')"
            >停止</t-button>
          </div>
        </header>
        <dl class="detail-facts">
          <div><dt>状态</dt><dd>{{ stateText(instance) }}</dd></div>
          <div><dt>PID</dt><dd>{{ instance.pid ?? '—' }}</dd></div>
          <div><dt>端口</dt><dd>{{ instance.httpPort ?? '—' }}</dd></div>
          <div><dt>内存</dt><dd>{{ instanceMemory(instance) }}</dd></div>
          <div><dt>引擎</dt><dd>{{ instance.engine || '—' }}</dd></div>
          <div><dt>启动时间</dt><dd>{{ instance.started || '—' }}</dd></div>
          <div><dt>Agent 心跳</dt><dd>{{ shortTime(agent.lastSeenAt) }}</dd></div>
          <div><dt>BAS_HOME</dt><dd class="detail-home">{{ agent.basHome || '—' }}</dd></div>
        </dl>
      </article>

      <article class="detail-card">
        <header class="detail-card__head">
          <div>
            <h3>应用</h3>
            <p>该实例当前部署的 webapp</p>
          </div>
        </header>
        <div v-if="(instance.webapps ?? []).length === 0" class="detail-empty">暂无应用</div>
        <table v-else class="detail-table">
          <thead><tr><th>上下文</th><th>构件</th><th>对外路径</th></tr></thead>
          <tbody>
            <tr v-for="app in instance.webapps" :key="app.id || app.uri">
              <td>{{ app.context || '/' }}</td>
              <td class="detail-uri" :title="app.uri || ''">{{ app.title || app.uri || '—' }}</td>
              <td>{{ (app.urls ?? []).join(', ') || '—' }}</td>
            </tr>
          </tbody>
        </table>
      </article>

      <article class="detail-card">
        <header class="detail-card__head">
          <div>
            <h3>日志</h3>
            <p>实例 console.out</p>
          </div>
          <div class="detail-actions">
            <t-button size="small" variant="outline" :loading="logLoading" @click="readLog">读取</t-button>
            <t-button v-if="!following" size="small" variant="outline" @click="startFollow">跟随</t-button>
            <t-button v-else size="small" theme="danger" variant="outline" @click="stopFollow">停止</t-button>
          </div>
        </header>
        <div class="log-meta">
          <span>共 {{ logTotal }} 行 · 显示 {{ logLines.length }} 行</span>
          <span v-if="following" class="log-following">跟随中</span>
        </div>
        <pre ref="logRef" class="server-log">{{ logLines.join('\n') || '（暂无日志）' }}</pre>
      </article>
    </template>
  </section>
</template>

<script setup lang="ts">
import { DialogPlugin, MessagePlugin } from 'tdesign-vue-next'
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  followAgentLog,
  listAgents,
  readAgentLog,
  serviceAgentInstance,
  type AgentInstance,
  type AgentLogEvent,
  type AgentServiceAction,
  type AgentStatus,
} from '@/api/agents'

const route = useRoute()
const router = useRouter()
const project = String(route.params.project || '')
const instanceId = String(route.params.instance || '')
const agentIp = String(route.query.ip || '')

const agents = ref<AgentStatus[]>([])
const loading = ref(false)
const error = ref('')
const serviceLoading = ref(false)

const agent = computed(() => agents.value.find((item) => item.project === project && (!agentIp || item.ip === agentIp)))
const instance = computed(() => (agent.value ? agentInstances(agent.value).find((item) => item.id === instanceId) : undefined))

const logLines = ref<string[]>([])
const logTotal = ref(0)
const logLoading = ref(false)
const following = ref(false)
const logRef = ref<HTMLElement>()
let logSource: EventSource | undefined

function agentInstances(value: AgentStatus): AgentInstance[] {
  const report = value.basReport
  const running = report?.instances ?? []
  const healthById = new Map((value.health ?? []).map((item) => [item.id, item]))
  if (!Array.isArray(report?.declared)) {
    return running.map((item) => ({
      ...item,
      state: 'running' as const,
      rssBytes: item.rssBytes ?? healthById.get(item.id || '')?.rssBytes,
    }))
  }
  const runningById = new Map(running.map((item) => [item.id || '', item]))
  return (report?.declared ?? []).map((declared) => {
    const live = runningById.get(declared.id || '')
    return live
      ? { ...live, state: 'running' as const, rssBytes: live.rssBytes ?? healthById.get(live.id || '')?.rssBytes }
      : { ...declared, state: 'stopped' as const }
  })
}

function isRunning(value: AgentInstance): boolean {
  return value.state !== 'stopped' && value.state !== 'error'
}

function stateText(value: AgentInstance): string {
  if (value.state === 'error') return '异常'
  return isRunning(value) ? '运行中' : '已停止'
}

function canService(action: AgentServiceAction): boolean {
  return agent.value?.supports?.includes(`service:${action}`) === true
}

function instanceMemory(value: AgentInstance): string {
  if (!isRunning(value) || typeof value.rssBytes !== 'number') return '—'
  return formatBytes(value.rssBytes)
}

function formatBytes(value: number): string {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  let amount = value
  let unit = 0
  while (amount >= 1024 && unit < units.length - 1) {
    amount /= 1024
    unit++
  }
  return `${amount.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`
}

function shortTime(value?: string): string {
  if (!value) return '—'
  const match = /^\d{4}-(\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})/.exec(value)
  return match ? `${match[1]} ${match[2]}` : value
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    agents.value = await listAgents()
    if (!agent.value) throw new Error('节点不在线')
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : String(reason)
  } finally {
    loading.value = false
  }
}

function confirmService(action: AgentServiceAction) {
  const current = instance.value
  const currentAgent = agent.value
  if (!current?.id || !currentAgent) return
  const label = action === 'restart' ? '重启' : action === 'stop' ? '停止' : '启动'
  const dialog = DialogPlugin.confirm({
    header: `${label}实例`,
    body: `确定${label} ${current.id}？`,
    onConfirm: async () => {
      dialog.destroy()
      serviceLoading.value = true
      try {
        await serviceAgentInstance(currentAgent.project, current.id!, action, currentAgent.ip)
        MessagePlugin.success(`${current.id} 已${label}`)
        await load()
      } catch (reason) {
        MessagePlugin.error(reason instanceof Error ? reason.message : `${label}失败`)
      } finally {
        serviceLoading.value = false
      }
    },
  })
}

async function readLog() {
  stopFollow()
  logLoading.value = true
  try {
    const window = await readAgentLog(project, instanceId, undefined, undefined, 200, agentIp || undefined)
    logLines.value = window.lines
    logTotal.value = window.total
    await scrollLogToEnd()
  } catch (reason) {
    MessagePlugin.error(reason instanceof Error ? reason.message : '读取日志失败')
  } finally {
    logLoading.value = false
  }
}

function startFollow() {
  stopFollow()
  following.value = true
  logSource = followAgentLog(project, instanceId, 200, agentIp || undefined)
  logSource.addEventListener('lines', (event) => {
    const payload = JSON.parse((event as MessageEvent).data) as AgentLogEvent
    logLines.value = payload.reset ? payload.lines : [...logLines.value, ...payload.lines]
    logTotal.value = payload.total
    void scrollLogToEnd()
  })
}

function stopFollow() {
  logSource?.close()
  logSource = undefined
  following.value = false
}

async function scrollLogToEnd() {
  await nextTick()
  if (logRef.value) logRef.value.scrollTop = logRef.value.scrollHeight
}

function goBack() {
  void router.push('/monitor/agents')
}

onMounted(async () => {
  await load()
  if (instance.value) await readLog()
})

onBeforeUnmount(stopFollow)
</script>

<style scoped>
.server-detail-page { display: flex; flex-direction: column; gap: 12px; }
.page-subtitle { margin: 4px 0 0; color: var(--td-text-color-placeholder); font-size: 13px; }
.empty-panel { padding: 32px 0; }
.detail-card { padding: 14px 16px; border: 1px solid var(--td-component-stroke); border-radius: 8px; background: var(--td-bg-color-container); }
.detail-card__head { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
.detail-card__head h3 { margin: 0; font-size: 16px; }
.detail-card__head p { margin: 3px 0 0; color: var(--td-text-color-placeholder); font-size: 12px; }
.detail-actions { display: flex; gap: 6px; }
.detail-facts { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 10px 18px; margin: 14px 0 0; }
.detail-facts div { min-width: 0; }
.detail-facts dt { color: var(--td-text-color-placeholder); font-size: 11px; }
.detail-facts dd { margin: 2px 0 0; overflow: hidden; font-size: 13px; text-overflow: ellipsis; white-space: nowrap; }
.detail-home { font-family: monospace; }
.detail-empty { padding: 12px 0; color: var(--td-text-color-placeholder); font-size: 12px; }
.detail-table { width: 100%; margin-top: 12px; border-collapse: collapse; font-size: 12px; }
.detail-table th, .detail-table td { padding: 6px 8px; border-bottom: 1px solid var(--td-component-stroke); text-align: left; }
.detail-table th { color: var(--td-text-color-placeholder); font-weight: 500; }
.detail-uri { max-width: 360px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.log-meta { display: flex; justify-content: space-between; margin-top: 10px; color: var(--td-text-color-placeholder); font-size: 12px; }
.log-following { color: var(--td-success-color); }
.server-log { max-height: 460px; margin: 8px 0 0; padding: 10px; overflow: auto; border-radius: 6px; color: var(--td-text-color-primary); font-family: monospace; font-size: 12px; line-height: 1.5; background: var(--td-bg-color-container-hover); white-space: pre-wrap; }
</style>
