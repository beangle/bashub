<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">节点</h2>
        <p class="mobile-page__subtitle">{{ project }} · {{ statuses.length }} 台在线</p>
      </div>
      <t-button size="small" variant="outline" :loading="loading" @click="refresh()">
        刷新
      </t-button>
    </header>

    <p class="mobile-updated">
      <template v-if="updatedAt">更新于 {{ updatedAt }}</template>
      <template v-else>等待首次上报</template>
      · {{ secondsLeft }} 秒后自动刷新
    </p>

    <MobileNotice v-if="error" :message="error" />
    <MobileNotice v-if="actionError" :message="actionError" />

    <div v-if="loading && statuses.length === 0" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>
    <t-empty v-else-if="statuses.length === 0" description="暂无在线节点。" />

    <div class="mobile-node-list">
      <MobileNodeCard
        v-for="agent in orderedAgents"
        :key="agentKey(agent)"
        :agent="agent"
        :refreshing="refreshingNodes[agentKey(agent)] === true"
        @refresh="refreshNode(agent)"
        @agent-log="openAgentLog(agent)"
        @open-instance="openInstance(agent, $event)"
      />
    </div>

    <section v-if="activeLogAgent" class="mobile-card">
      <MobileLogPanel
        :title="logTitle"
        :lines="logLines"
        :total="logTotal"
        :loading="logLoading"
        :following="logFollowing"
        :reconnecting="logReconnecting"
        :error="logError"
        :can-follow="false"
        @read="rereadAgentLog"
        @follow="rereadAgentLog"
        @stop="stopLog"
      />
    </section>
  </section>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { requestAgentReport, type AgentInstance, type AgentStatus } from '@/api/agents'
import MobileLogPanel from '@/components/MobileLogPanel.vue'
import MobileNotice from '@/components/MobileNotice.vue'
import MobileNodeCard from '@/components/MobileNodeCard.vue'
import { useAgentLog } from '@/composables/useAgentLog'
import { useAgentMonitor } from '@/composables/useAgentMonitor'
import { agentKey, compareAgentHealth, errorText } from '@/monitor-model'

const route = useRoute()
const router = useRouter()
const project = computed(() => String(route.params.project ?? ''))
const {
  statuses,
  loading,
  error,
  updatedAt,
  secondsLeft,
  refresh,
} = useAgentMonitor({ project: () => project.value, mode: 'status' })

const {
  lines: logLines,
  total: logTotal,
  loading: logLoading,
  following: logFollowing,
  reconnecting: logReconnecting,
  error: logError,
  read: readLog,
  stop: stopLog,
} = useAgentLog()

const refreshingNodes = ref<Record<string, boolean>>({})
const actionError = ref('')
const activeLogAgent = ref<AgentStatus | null>(null)

const orderedAgents = computed(() => [...statuses.value].sort(compareAgentHealth))
const logTitle = computed(() => {
  const agent = activeLogAgent.value
  if (!agent) return 'Agent 日志'
  return `${agent.ip || agent.host || project.value} · Agent 日志`
})

async function refreshNode(agent: AgentStatus): Promise<void> {
  const key = agentKey(agent)
  if (refreshingNodes.value[key]) return
  refreshingNodes.value = { ...refreshingNodes.value, [key]: true }
  actionError.value = ''
  try {
    await requestAgentReport(agent.project, agent.ip)
    // 202 只表示指令已入队；等 agent 重新上报后再读快照。
    await new Promise((resolve) => setTimeout(resolve, 900))
    await refresh(true)
  } catch (reason) {
    actionError.value = errorText(reason)
  } finally {
    refreshingNodes.value = { ...refreshingNodes.value, [key]: false }
  }
}

function openAgentLog(agent: AgentStatus): void {
  activeLogAgent.value = agent
  void readLog({ project: project.value, kind: 'agent', agent: agent.ip })
}

function rereadAgentLog(): void {
  const agent = activeLogAgent.value
  if (!agent) return
  void readLog({ project: project.value, kind: 'agent', agent: agent.ip })
}

function openInstance(agent: AgentStatus, instance: AgentInstance): void {
  if (!instance.id) return
  void router.push({
    path: `/projects/${encodeURIComponent(project.value)}/instances/${encodeURIComponent(instance.id)}`,
    query: { agent: agent.ip || '' },
  })
}
</script>
