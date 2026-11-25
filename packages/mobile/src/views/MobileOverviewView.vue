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
          <template #text><strong>{{ health.stopped }}</strong></template>
          <template #description>停止</template>
        </t-grid-item>
        <t-grid-item>
          <template #text><strong :class="{ 'is-danger': health.error > 0 }">{{ health.error }}</strong></template>
          <template #description>异常</template>
        </t-grid-item>
      </t-grid>

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
            @click="openNodes"
            @keydown.enter="openNodes"
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
import { computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import type { AgentStatus } from '@/api/agents'
import MobileMetricBar from '@/components/MobileMetricBar.vue'
import MobileNotice from '@/components/MobileNotice.vue'
import { useAgentMonitor } from '@/composables/useAgentMonitor'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import {
  agentHealthCounts,
  agentKey,
  compareAgentHealth,
  deviceResources,
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

function openNodes(): void {
  void router.push(`/projects/${encodeURIComponent(project.value)}/nodes`)
}

async function reload(): Promise<void> {
  await Promise.all([catalog.load(true), refresh()])
}

onMounted(() => {
  void catalog.load()
})
</script>
