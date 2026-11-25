/**
 * 手机端监控数据：按 URL 里的 project 过滤 `/agents/summary` 与 `/agents/status`，
 * 统一处理加载态、错误、可见性轮询与请求去重。
 *
 * 页面只消费返回的 ref；轮询与 `document.hidden` 的暂停逻辑都在这里，
 * 避免每个页面各写一份定时器（重复挂载时最容易漏清理）。
 */
import { onBeforeUnmount, onMounted, ref, type Ref } from 'vue'
import { listAgentSummaries, listAgents, type AgentStatus, type AgentSummary } from '@/api/agents'
import { errorText } from '@/monitor-model'

export type MonitorMode = 'summary' | 'status' | 'both'

export interface AgentMonitorOptions {
  /** 返回当前 project 的 qualifiedName；空串表示不过滤（项目列表用）。 */
  project: () => string
  mode?: MonitorMode
  intervalSeconds?: number
  /** 为 false 时不在 onMounted 立即拉取，交给页面显式 refresh。 */
  immediate?: boolean
}

export interface AgentMonitor {
  summaries: Ref<AgentSummary[]>
  statuses: Ref<AgentStatus[]>
  loading: Ref<boolean>
  error: Ref<string>
  updatedAt: Ref<string>
  secondsLeft: Ref<number>
  refresh: (quiet?: boolean) => Promise<void>
}

function filterByProject<T extends { project: string }>(items: T[], project: string): T[] {
  return project ? items.filter((item) => item.project === project) : items
}

function clock(): string {
  return new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
}

export function useAgentMonitor(options: AgentMonitorOptions): AgentMonitor {
  const intervalSeconds = options.intervalSeconds ?? 30
  const mode = options.mode ?? 'status'
  const summaries = ref<AgentSummary[]>([])
  const statuses = ref<AgentStatus[]>([])
  const loading = ref(false)
  const error = ref('')
  const updatedAt = ref('')
  const secondsLeft = ref(intervalSeconds)
  let inflight: Promise<void> | null = null
  let timer: ReturnType<typeof setInterval> | undefined

  async function refresh(quiet = false): Promise<void> {
    if (inflight) return inflight
    if (!quiet) {
      loading.value = true
      error.value = ''
    }
    secondsLeft.value = intervalSeconds
    inflight = (async () => {
      try {
        const wantSummary = mode !== 'status'
        const wantStatus = mode !== 'summary'
        const [summaryResult, statusResult] = await Promise.all([
          wantSummary ? listAgentSummaries() : Promise.resolve<AgentSummary[]>([]),
          wantStatus ? listAgents() : Promise.resolve<AgentStatus[]>([]),
        ])
        const project = options.project()
        summaries.value = filterByProject(summaryResult, project)
        statuses.value = filterByProject(statusResult, project)
        updatedAt.value = clock()
        error.value = ''
      } catch (reason) {
        error.value = errorText(reason)
      } finally {
        loading.value = false
        inflight = null
      }
    })()
    return inflight
  }

  function onVisibilityChange(): void {
    if (document.hidden) return
    secondsLeft.value = intervalSeconds
    void refresh(true)
  }

  function startTimer(): void {
    if (timer) clearInterval(timer)
    timer = setInterval(() => {
      // 页面在后台时既不倒计时也不发请求；回到前台由 visibilitychange 立即补一次。
      if (document.hidden) {
        secondsLeft.value = intervalSeconds
        return
      }
      secondsLeft.value -= 1
      if (secondsLeft.value <= 0) {
        secondsLeft.value = intervalSeconds
        void refresh(true)
      }
    }, 1000)
  }

  onMounted(() => {
    if (options.immediate !== false) void refresh()
    startTimer()
    document.addEventListener('visibilitychange', onVisibilityChange)
  })

  onBeforeUnmount(() => {
    if (timer) clearInterval(timer)
    timer = undefined
    document.removeEventListener('visibilitychange', onVisibilityChange)
  })

  return { summaries, statuses, loading, error, updatedAt, secondsLeft, refresh }
}
