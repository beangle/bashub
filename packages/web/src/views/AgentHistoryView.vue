<template>
  <section class="page-panel">
    <div class="page-head">
      <div>
        <router-link class="detail-back" to="/monitor/agents">← 在线节点</router-link>
        <h2 class="page-title">运行历史</h2>
        <p class="page-subtitle">
          {{ profile || '-' }} · 最近 {{ days }} 天；采样窗口与频率由 bashub 的
          <code>agent-health-*</code> 配置决定。
        </p>
      </div>
      <div class="page-actions">
        <t-button v-if="profileId" variant="outline" @click="goProfile">配置</t-button>
      </div>
    </div>

    <div class="history-toolbar">
      <div class="history-legend">
        <span><i class="history-dot history-dot-running" />运行</span>
        <span><i class="history-dot history-dot-stopped" />停止</span>
        <span><i class="history-dot history-dot-error" />异常</span>
        <span><i class="history-dot history-dot-unknown" />无采样</span>
      </div>
      <div class="history-tools">
        <t-select
          v-model="serverFilter"
          size="small"
          clearable
          filterable
          placeholder="全部 Server"
          style="width: 220px"
        >
          <t-option v-for="id in serverIds" :key="id" :value="id" :label="id" />
        </t-select>
        <t-button size="small" variant="outline" :loading="loading" @click="reload">刷新</t-button>
      </div>
    </div>

    <t-alert v-if="error" theme="error" :message="error" class="agent-alert" />
    <div v-if="loading && !history" class="agent-muted">正在加载运行历史…</div>
    <div v-else-if="history && rows.length === 0" class="agent-muted">所选时间范围内没有采样记录。</div>
    <div v-else-if="history" class="history-list">
      <article v-for="(row, index) in rows" :key="row.id" class="history-card">
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
        <div class="history-strip" :aria-label="`最近 ${days} 天运行状态`">
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
          <span
            v-for="change in row.changes.slice(0, 8)"
            :key="`${change.at}-${change.state}`"
            class="history-change"
          >
            {{ change.at }} {{ stateLabel(change.state) }}
          </span>
        </div>
      </article>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { readAgentHistory, type AgentHealth, type AgentHistory } from '@/api/agents'

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

const route = useRoute()
const router = useRouter()
const days = 180

const profile = computed(() => String(route.params.profile ?? ''))
const profileId = computed(() => history.value?.profileId ?? '')
const history = ref<AgentHistory | null>(null)
const loading = ref(false)
const error = ref('')
const serverFilter = ref('')

const serverIds = computed<string[]>(() => {
  const ids = new Set<string>()
  for (const sample of history.value?.samples ?? []) {
    for (const [id, state] of Object.entries(sample.servers ?? {})) {
      if (isHealthState(state)) ids.add(id)
    }
  }
  return [...ids].sort(compareServerIds)
})

const rows = computed<HistoryRow[]>(() => {
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
  if (serverFilter.value) ids = ids.filter((id) => id === serverFilter.value)

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

function errorText(reason: unknown): string {
  return reason instanceof Error ? reason.message : String(reason)
}

async function reload() {
  if (!profile.value || loading.value) return
  loading.value = true
  error.value = ''
  try {
    history.value = await readAgentHistory(profile.value, { days })
  } catch (reason) {
    error.value = errorText(reason)
  } finally {
    loading.value = false
  }
}

function goProfile() {
  if (profileId.value) router.push(`/config/profiles/${encodeURIComponent(profileId.value)}`)
}

watch(profile, () => {
  history.value = null
  serverFilter.value = ''
  void reload()
})

onMounted(() => {
  void reload()
})
</script>

<style scoped>
.detail-back {
  color: var(--td-text-color-secondary);
  font-size: 13px;
  text-decoration: none;
}

.detail-back:hover {
  color: var(--td-brand-color);
}

.agent-muted {
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.agent-alert {
  margin: 0 12px;
}

.history-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 12px;
  padding: 12px 12px 0;
}

.history-tools {
  display: flex;
  align-items: center;
  gap: 8px;
}

.history-legend {
  display: flex;
  align-items: center;
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

/* 整页展示后按两列铺开，充分利用宽度；窄屏自动回落成一列。 */
.history-list {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(520px, 1fr));
  gap: 12px;
  padding: 12px;
}

.history-card {
  padding: 12px 14px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container-hover);
}

.history-card-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 12px;
}

.history-title {
  display: flex;
  align-items: center;
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
  display: flex;
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
  height: 20px;
  margin-top: 10px;
  overflow: hidden;
  border-radius: 3px;
}

.history-cell {
  min-width: 0;
}

.history-axis {
  display: flex;
  justify-content: space-between;
  margin-top: 4px;
  color: var(--td-text-color-placeholder);
  font-size: 11px;
}

.history-changes {
  display: flex;
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
  .history-list {
    grid-template-columns: 1fr;
  }
}
</style>
