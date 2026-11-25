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

    <div v-if="componentStates.length > 0" class="mobile-node__components">
      <t-tag v-for="item in componentStates" :key="item.key" size="small" variant="light" :theme="item.theme">
        {{ item.label }} {{ item.state }}
      </t-tag>
    </div>

    <div class="mobile-node__instances">
      <h4 class="mobile-node__section-title">实例</h4>
      <t-cell-group v-if="instances.length > 0" :bordered="false">
        <t-cell
          v-for="instance in instances"
          :key="instance.id || String(instance.pid)"
          :title="instance.id || '未命名实例'"
          :description="instanceMemory(instance)"
          arrow
          @click="emit('open-instance', instance)"
        >
          <template #note>
            <t-tag size="small" variant="light" :theme="stateTheme(instanceState(instance))">
              {{ stateLabel(instanceState(instance)) }}
            </t-tag>
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

interface ComponentState {
  key: string
  label: string
  state: string
  theme: 'success' | 'warning' | 'danger' | 'default'
}

function stateThemeOf(value: string, active: boolean | undefined): ComponentState['theme'] {
  if (active === true || value === 'active' || value === 'running') return 'success'
  if (active === false || value === 'inactive' || value === 'stopped') return 'warning'
  return 'default'
}

const componentStates = computed<ComponentState[]>(() => {
  const os = props.agent.os
  const result: ComponentState[] = []
  if (os?.micdn) {
    const state = os.micdn.state || (os.micdn.active ? 'active' : 'inactive')
    result.push({ key: 'micdn', label: 'Micdn', state, theme: stateThemeOf(state, os.micdn.active) })
  }
  const proxy = os?.proxyState
  const proxyEntries: { key: 'haproxy' | 'nginx'; label: string }[] = [
    { key: 'haproxy', label: 'HAProxy' },
    { key: 'nginx', label: 'Nginx' },
  ]
  for (const entry of proxyEntries) {
    const item = proxy?.[entry.key]
    if (!item) continue
    const state = item.state || (item.active ? 'active' : 'inactive')
    result.push({ key: entry.key, label: entry.label, state, theme: stateThemeOf(state, item.active) })
  }
  return result
})

function instanceMemory(instance: AgentInstance): string {
  if (!isInstanceRunning(instance) || typeof instance.rssBytes !== 'number') return '—'
  return formatBytes(instance.rssBytes)
}
</script>
