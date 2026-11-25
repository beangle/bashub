/**
 * 手机端日志窗口：先读尾部，再按需跟随；统一处理 `reset`、错误状态与 EventSource 清理。
 *
 * `followAgentLog()` 负责创建流（同源 cookie 认证），本组合式函数只消费它，
 * 因此页面里不直接创建流，也不会漏掉卸载时的 `close()`。
 */
import { onBeforeUnmount, ref } from 'vue'
import {
  followAgentLog,
  readAgentLog,
  readAgentOwnLog,
  type AgentLogEvent,
  type AgentLogWindow,
} from '@/api/agents'
import { errorText } from '@/monitor-model'

export type AgentLogKind = 'instance' | 'agent'

export interface AgentLogTarget {
  project: string
  instance?: string
  /** 目标节点 ip；同一 project 有多台在线节点时必填。 */
  agent?: string
  kind: AgentLogKind
  tail?: number
}

const MAX_LINES = 2000
const DEFAULT_TAIL = 200

export function useAgentLog() {
  const lines = ref<string[]>([])
  const total = ref(0)
  const loading = ref(false)
  const following = ref(false)
  const reconnecting = ref(false)
  const error = ref('')
  const loaded = ref(false)
  const target = ref<AgentLogTarget | null>(null)
  let source: EventSource | null = null
  let generation = 0

  function applyWindow(window: AgentLogWindow, reset = false): void {
    if (reset || lines.value.length === 0) {
      lines.value = window.lines.slice(-MAX_LINES)
    } else {
      const next = [...lines.value, ...window.lines]
      lines.value = next.length > MAX_LINES ? next.slice(next.length - MAX_LINES) : next
    }
    total.value = window.total
    loaded.value = true
  }

  async function read(next: AgentLogTarget): Promise<void> {
    stop()
    target.value = next
    loading.value = true
    error.value = ''
    loaded.value = false
    lines.value = []
    total.value = 0
    try {
      const tail = next.tail ?? DEFAULT_TAIL
      const window = next.kind === 'agent'
        ? await readAgentOwnLog(next.project, undefined, undefined, tail, next.agent)
        : await readAgentLog(next.project, next.instance ?? '', undefined, undefined, tail, next.agent)
      applyWindow(window, true)
    } catch (reason) {
      error.value = errorText(reason)
    } finally {
      loading.value = false
    }
  }

  function follow(next: AgentLogTarget): void {
    // agent 自身日志没有 SSE 通道；调用方传进来时退回一次性读取。
    if (next.kind !== 'instance' || !next.instance) {
      void read(next)
      return
    }
    stop()
    target.value = next
    loading.value = true
    error.value = ''
    reconnecting.value = false
    loaded.value = false
    lines.value = []
    total.value = 0
    const current = ++generation
    const stream = followAgentLog(next.project, next.instance, next.tail ?? DEFAULT_TAIL, next.agent)
    source = stream

    stream.onopen = () => {
      if (current !== generation) {
        stream.close()
        return
      }
      loading.value = false
      following.value = true
      reconnecting.value = false
      error.value = ''
    }

    stream.addEventListener('lines', (event: Event) => {
      if (current !== generation) return
      const window = parseLogEvent(event)
      if (!window) {
        stream.close()
        if (source === stream) source = null
        following.value = false
        loading.value = false
        error.value = '日志数据异常，请重新读取'
        return
      }
      applyWindow(window, window.reset === true)
      following.value = true
      reconnecting.value = false
      loading.value = false
      error.value = ''
    })

    stream.addEventListener('failure', (event: Event) => {
      if (current !== generation) return
      stream.close()
      if (source === stream) source = null
      following.value = false
      reconnecting.value = false
      loading.value = false
      error.value = failureText(event)
    })

    stream.onerror = () => {
      if (current !== generation) return
      loading.value = false
      reconnecting.value = true
      error.value = '日志连接中断，正在自动重连…'
    }
  }

  function stop(): void {
    generation += 1
    if (source) {
      source.close()
      source = null
    }
    following.value = false
    reconnecting.value = false
    loading.value = false
  }

  function clear(): void {
    stop()
    target.value = null
    lines.value = []
    total.value = 0
    loaded.value = false
    error.value = ''
  }

  onBeforeUnmount(stop)

  return { lines, total, loading, following, reconnecting, error, loaded, target, read, follow, stop, clear }
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
    return value.error || '日志连接已中断，请重新读取'
  } catch {
    return '日志连接已中断，请重新读取'
  }
}
