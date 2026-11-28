<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">启停记录</h2>
        <p class="mobile-page__subtitle">{{ project }}<template v-if="instance"> · {{ instance }}</template></p>
      </div>
      <router-link class="mobile-back" :to="overviewPath">返回概览</router-link>
    </header>

    <MobileNotice v-if="error" :message="error" />

    <div class="mobile-page__toolbar">
      <span class="mobile-updated">最近 {{ events.length }} 条 · 最新在前</span>
    </div>

    <div v-if="loading && events.length === 0" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>
    <t-empty v-else-if="events.length === 0" description="暂无手工启停记录。" />
    <div v-else class="mobile-event-list">
      <article v-for="event in events" :key="event.id" class="mobile-card mobile-event">
        <div class="mobile-event__head">
          <t-tag size="small" variant="light" :theme="!event.ok ? 'error' : event.action === 'stop' ? 'warning' : 'success'">
            {{ actionLabel(event.action) }}
          </t-tag>
          <span class="mobile-event__time">{{ timeLabel(event.at) }}</span>
        </div>
        <p class="mobile-event__main">{{ event.instance }}</p>
        <p class="mobile-event__meta">
          {{ event.operatorName || event.operator || '—' }}
          <template v-if="event.operatorIp"> · {{ event.operatorIp }}</template>
          <template v-if="event.agentIp"> · 节点 {{ event.agentIp }}</template>
        </p>
        <p v-if="!event.ok && event.detail" class="mobile-event__error">{{ event.detail }}</p>
      </article>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import MobileNotice from '@/components/MobileNotice.vue'
import { readServerEvents, type ServerEvent, type ServerEventAction } from '@/api/events'
import { errorText } from '@/monitor-model'

const route = useRoute()
const project = computed(() => String(route.params.project ?? ''))
const instance = computed(() => String(route.query.instance ?? ''))
const overviewPath = computed(() => `/projects/${encodeURIComponent(project.value)}`)

const events = ref<ServerEvent[]>([])
const loading = ref(false)
const error = ref('')

function actionLabel(action: ServerEventAction): string {
  if (action === 'start') return '启动'
  if (action === 'stop') return '停止'
  return '重启'
}

function timeLabel(value?: string): string {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString('zh-CN', { hour12: false })
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
    error.value = `启停记录加载失败：${errorText(reason)}`
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
