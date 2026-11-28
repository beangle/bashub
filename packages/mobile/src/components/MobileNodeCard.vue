<template>
  <article class="mobile-node">
    <header class="mobile-node__head">
      <div class="mobile-node__identity">
        <h3 class="mobile-node__title">{{ props.agent.ip || props.agent.host || '未知节点' }}</h3>
        <p class="mobile-node__meta">
          <span>{{ props.agent.host || '主机未上报' }}</span>
          <span>{{ roleLabel }}</span>
          <span>心跳 {{ relativeTime(props.agent.lastSeenAt) }}</span>
        </p>
      </div>
      <t-tag size="small" variant="light" :theme="nodeTheme">{{ nodeLabel }}</t-tag>
    </header>

    <div class="mobile-node__resources">
      <MobileMetricBar label="CPU" :value="usage.cpuPercent" :detail="cpuDetail" />
      <MobileMetricBar label="内存" :value="usage.memoryPercent" :detail="memoryDetail" />
      <MobileMetricBar label="磁盘" :value="usage.diskPercent" :detail="diskDetail" />
    </div>

    <dl class="mobile-node__facts">
      <div class="mobile-node__fact">
        <dt>系统</dt>
        <dd>{{ resources.osName || '未上报' }}</dd>
      </div>
      <div class="mobile-node__fact">
        <dt>实例</dt>
        <dd>{{ counts.running }} 运行 / {{ counts.stopped }} 停止<template v-if="counts.error"> / {{ counts.error }} 异常</template></dd>
      </div>
      <div class="mobile-node__fact">
        <dt>版本</dt>
        <dd>basctl {{ props.agent.basctl || '—' }} · bas {{ props.agent.bas || '—' }}</dd>
      </div>
    </dl>

    <div class="mobile-node__instances">
      <h4 class="mobile-node__section-title">实例</h4>
      <t-cell-group v-if="instances.length > 0" :bordered="false">
        <t-cell
          v-for="instance in instances"
          :key="instance.id || String(instance.pid)"
          arrow
          @click="emit('open-instance', instance)"
        >
          <template #title>
            <span class="mobile-instance-title">
              <span class="mobile-instance-title__name">{{ instance.id || '未命名实例' }}</span>
              <t-tag
                v-if="deployLabel(instance)"
                size="small"
                variant="light"
                :theme="deployTheme(instance)"
              >{{ deployLabel(instance) }}</t-tag>
            </span>
          </template>
          <template #note>
            <span class="mobile-instance-note">
              <span class="mobile-instance-note__memory">{{ instanceMemory(instance) }}</span>
              <t-tag size="small" variant="light" :theme="stateTheme(instanceState(instance))">
                {{ stateLabel(instanceState(instance)) }}
              </t-tag>
            </span>
          </template>
        </t-cell>
      </t-cell-group>
      <t-empty v-else description="暂无实例。" />
    </div>

    <footer class="mobile-node__actions">
      <t-button size="small" variant="outline" :loading="props.refreshing" @click="emit('refresh')">
        刷新节点
      </t-button>
      <t-button
        size="small"
        variant="outline"
        :disabled="!canReadAgentLog"
        @click="emit('agent-log')"
      >
        Agent 日志
      </t-button>
    </footer>
  </article>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { AgentInstance, AgentStatus } from '@/api/agents'
import MobileMetricBar from '@/components/MobileMetricBar.vue'
import {
  agentHealthCounts,
  deviceResources,
  formatBytes,
  instanceState,
  isInstanceRunning,
  mergeAgentInstances,
  relativeTime,
  resourceUsage,
  stateLabel,
  stateTheme,
} from '@/monitor-model'

const props = withDefaults(
  defineProps<{
    agent: AgentStatus
    refreshing?: boolean
  }>(),
  { refreshing: false },
)

const emit = defineEmits<{
  refresh: []
  'agent-log': []
  'open-instance': [instance: AgentInstance]
}>()

const counts = computed(() => agentHealthCounts(props.agent))
const usage = computed(() => resourceUsage(props.agent.os))
const resources = computed(() => deviceResources(props.agent))
const instances = computed(() => mergeAgentInstances(props.agent))
const canReadAgentLog = computed(() => props.agent.supports?.includes('agent:log') === true)

const roleLabel = computed(() => (props.agent.role === 'master' ? '主节点' : '从节点'))

const nodeTheme = computed<'success' | 'warning' | 'danger' | 'default'>(() => {
  if (counts.value.error > 0) return 'danger'
  if (counts.value.running > 0 && counts.value.stopped === 0) return 'success'
  if (counts.value.running > 0 || counts.value.stopped > 0) return 'warning'
  return 'default'
})

const nodeLabel = computed(() => {
  if (counts.value.error > 0) return '有异常'
  if (counts.value.running > 0 && counts.value.stopped === 0) return '运行正常'
  if (counts.value.running > 0) return '部分停止'
  return '无运行实例'
})

const cpuDetail = computed(() => {
  if (resources.value.load1 === undefined) return ''
  return `${resources.value.load1.toFixed(2)} / ${resources.value.cores ?? '—'} 核`
})

const memoryDetail = computed(() => {
  if (resources.value.memoryTotal === undefined) return ''
  return `${formatBytes(resources.value.memoryUsed)} / ${formatBytes(resources.value.memoryTotal)}`
})

const diskDetail = computed(() => {
  if (resources.value.diskTotal === undefined) return ''
  const mount = resources.value.diskMount || '/'
  return `${mount} ${formatBytes(resources.value.diskUsed)} / ${formatBytes(resources.value.diskTotal)}`
})

function deployLabel(instance: AgentInstance): string {
  switch (instance.deployment?.state) {
    case 'restart': return '待重启'
    case 'undelivered': return '未下发'
    case 'unknown': return '未知'
    default: return ''
  }
}

function deployTheme(instance: AgentInstance): 'warning' | 'default' {
  return instance.deployment?.state === 'restart' ? 'warning' : 'default'
}

function instanceMemory(instance: AgentInstance): string {
  if (!isInstanceRunning(instance) || typeof instance.rssBytes !== 'number') return '—'
  return formatBytes(instance.rssBytes)
}
</script>
