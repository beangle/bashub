<template>
  <section class="page-panel events-page">
    <div class="page-head">
      <div class="detail-heading">
        <div class="title-row">
          <h2 class="page-title">启停记录</h2>
          <p class="page-subtitle">{{ project }}<template v-if="instance"> · {{ instance }}</template></p>
          <t-button class="title-back" size="small" variant="text" @click="goBack">← 返回</t-button>
        </div>
      </div>
      <div class="page-actions">
        <t-button size="small" variant="outline" :loading="loading" @click="load">刷新</t-button>
      </div>
    </div>

    <t-alert v-if="error" theme="error" :message="error" />

    <article class="detail-card">
      <header class="detail-card__head">
        <div>
          <h3>手工启停事件</h3>
          <p>最近 {{ events.length }} 条，最新在前；节点离线/超时也会记录。</p>
        </div>
      </header>
      <div v-if="loading && events.length === 0" class="detail-empty">正在加载启停记录…</div>
      <div v-else-if="events.length === 0" class="detail-empty">暂无手工启停记录。</div>
      <table v-else class="detail-table">
        <thead>
          <tr>
            <th>时间</th><th>实例</th><th>动作</th><th>操作人</th><th>操作人 IP</th><th>节点 IP</th><th>结果</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="event in events" :key="event.id">
            <td>{{ timeText(event.at) }}</td>
            <td>{{ event.instance }}</td>
            <td>
              <t-tag size="small" variant="light" :theme="event.ok ? 'success' : 'danger'">
                {{ actionText(event.action) }}
              </t-tag>
            </td>
            <td>
              {{ event.operatorName || event.operator || '—' }}
              <span v-if="event.operator" class="muted">（{{ event.operator }}）</span>
            </td>
            <td>{{ event.operatorIp || '—' }}</td>
            <td>{{ event.agentIp || '—' }}</td>
            <td>
              <div>{{ event.ok ? '成功' : '失败' }}</div>
              <div v-if="!event.ok && event.detail" class="event-error">{{ event.detail }}</div>
            </td>
          </tr>
        </tbody>
      </table>
    </article>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { readServerEvents, type ServerEvent, type ServerEventAction } from '@/api/events'

const route = useRoute()
const router = useRouter()
const project = computed(() => String(route.params.project ?? ''))
const instance = computed(() => String(route.query.instance ?? ''))
const agentIp = computed(() => String(route.query.ip ?? ''))

const events = ref<ServerEvent[]>([])
const loading = ref(false)
const error = ref('')

function actionText(action: ServerEventAction): string {
  if (action === 'start') return '启动'
  if (action === 'stop') return '停止'
  return '重启'
}

function timeText(value?: string): string {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString('zh-CN', { hour12: false })
}

function goBack(): void {
  if (instance.value) {
    const params = new URLSearchParams()
    if (agentIp.value) params.set('ip', agentIp.value)
    const suffix = params.size > 0 ? `?${params.toString()}` : ''
    void router.push(
      `/monitor/agents/${encodeURIComponent(project.value)}/servers/${encodeURIComponent(instance.value)}${suffix}`,
    )
  } else {
    void router.push('/monitor/agents')
  }
}

async function load(): Promise<void> {
  if (!project.value) return
  loading.value = true
  error.value = ''
  try {
    events.value = await readServerEvents(project.value, {
      instance: instance.value || undefined,
      limit: 200,
    })
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : String(reason)
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  void load()
})
watch([project, instance], () => {
  void load()
})
</script>

<style scoped>
.events-page { display: flex; flex-direction: column; gap: 12px; }
.detail-card { padding: 14px 16px; border: 1px solid var(--td-component-stroke); border-radius: 8px; background: var(--td-bg-color-container); }
.detail-card__head { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
.detail-card__head h3 { margin: 0; font-size: 16px; }
.detail-card__head p { margin: 0; color: var(--td-text-color-placeholder); font-size: 12px; }
.detail-empty { padding: 12px 0; color: var(--td-text-color-placeholder); font-size: 12px; }
.detail-table { width: 100%; margin-top: 12px; border-collapse: collapse; font-size: 12px; }
.detail-table th,
.detail-table td { padding: 6px 8px; border-bottom: 1px solid var(--td-component-stroke); text-align: left; vertical-align: top; }
.detail-table th { color: var(--td-text-color-placeholder); font-weight: 500; }
.muted { color: var(--td-text-color-placeholder); }
.event-error { margin-top: 2px; color: var(--td-error-color); word-break: break-all; }
</style>
