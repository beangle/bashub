/**
 * 手机端监控的纯数据模型：只做合并、定位、百分比与历史聚合，不发请求、不碰全局状态。
 *
 * PC 的 `AgentView` / `AgentServerView` / `AgentHistoryView` 各自实现了一份实例合并与历史聚合；
 * 手机端统一从这里取结果，避免三处语义（尤其多 agent 与实例状态）再次分叉。
 */
import type {
  AgentDiskInfo,
  AgentHealth,
  AgentHistory,
  AgentInstance,
  AgentOsSnapshot,
  AgentServiceAction,
  AgentStatus,
  AgentSummary,
} from '@/api/agents'

/** 监控状态；`unknown` 只用于历史色带里没有采样的日期。 */
export type MonitorState = AgentHealth['state'] | 'unknown'

/** 项目目录条目：来自 `GET /config/projects`，只保留展示与匹配需要的字段。 */
export interface ProjectInfo {
  id: string
  name: string
  /** 后端约定的 `org.name.project.name`，同时是监控 URL 里的 `:project`。 */
  qualifiedName: string
  title: string
  orgTitle: string
  orgShortTitle: string
  orgName: string
  logoUrl: string
}

export type ProjectStatus = 'ok' | 'warning' | 'critical' | 'offline'

/** 项目目录 + 在线摘要合并后的卡片数据。 */
export interface MobileProject extends ProjectInfo {
  nodeCount: number
  running: number
  stopped: number
  error: number
  instanceTotal: number
  status: ProjectStatus
}

export interface HealthCounts {
  running: number
  stopped: number
  error: number
}

export interface ResourceUsage {
  cpuPercent?: number
  memoryPercent?: number
  diskPercent?: number
}

/** 一台节点上 CPU/内存/磁盘的展示值；没有上报的项保持 `undefined`。 */
export interface DeviceResources {
  osName: string
  cores?: number
  load1?: number
  memoryUsed?: number
  memoryTotal?: number
  diskUsed?: number
  diskTotal?: number
  diskMount?: string
}

export interface HistoryCell {
  date: string
  state: MonitorState
  title: string
}

export interface HistoryChange {
  at: string
  state: AgentHealth['state']
}

export interface InstanceHistory {
  instance: string
  cells: HistoryCell[]
  total: number
  running: number
  /** 运行采样 / 全部采样，0–100。 */
  availability: number
  sampledDays: number
  lastAt: string
  firstDate: string
  lastDate: string
  changes: HistoryChange[]
}

const DAY_MILLISECONDS = 86_400_000

function clampPercent(value: number): number {
  if (!Number.isFinite(value)) return 0
  return Math.min(100, Math.max(0, Math.round(value)))
}

function numberOrUndefined(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
}

function dateKey(value: string | undefined): string {
  const match = /^(\d{4}-\d{2}-\d{2})/.exec(value ?? '')
  return match ? match[1] : ''
}

function pad(value: number): string {
  return String(value).padStart(2, '0')
}

function localDateKey(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

function recentDateKeys(count: number, anchor: string): string[] {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(anchor)
  // 用 UTC 日历做「减一天」，避免浏览器时区/夏令时把日期算偏。
  const end = match
    ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
    : Date.now()
  const dates: string[] = []
  for (let offset = count - 1; offset >= 0; offset -= 1) {
    const day = new Date(end - offset * DAY_MILLISECONDS)
    dates.push(`${day.getUTCFullYear()}-${pad(day.getUTCMonth() + 1)}-${pad(day.getUTCDate())}`)
  }
  return dates
}

export function isHealthState(value: unknown): value is AgentHealth['state'] {
  return value === 'running' || value === 'stopped' || value === 'error'
}

/** 多 agent 的稳定键：后端用 `ip` 区分同一 project 的不同机器。 */
export function agentKey(agent: { project: string; ip?: string; host?: string }): string {
  return `${agent.project}@${agent.ip || agent.host || ''}`
}

function summaryMatchesProject(summary: AgentSummary, project: ProjectInfo): boolean {
  if (summary.projectId && project.id) return summary.projectId === project.id
  return summary.project === project.qualifiedName || summary.project === project.name
}

function summaryHealth(summary: AgentSummary): HealthCounts {
  if (summary.health && summary.health.length > 0) {
    return summary.health.reduce<HealthCounts>((counts, item) => {
      if (item.state === 'running') counts.running += 1
      else if (item.state === 'stopped') counts.stopped += 1
      else counts.error += 1
      return counts
    }, { running: 0, stopped: 0, error: 0 })
  }
  return {
    running: numberOrUndefined(summary.running) ?? 0,
    stopped: numberOrUndefined(summary.stopped) ?? 0,
    error: 0,
  }
}

function statusOf(counts: HealthCounts, nodeCount: number): ProjectStatus {
  if (nodeCount === 0) return 'offline'
  if (counts.error > 0) return 'critical'
  if (counts.stopped > 0) return 'warning'
  return 'ok'
}

/**
 * 项目目录 + 在线摘要 → 手机项目卡片。
 *
 * 全部 Project 都返回，`nodeCount === 0` 标记为离线，这样手机端不会因为节点离线就从列表里消失。
 */
export function mergeProjects(projects: ProjectInfo[], summaries: AgentSummary[]): MobileProject[] {
  return projects.map((project) => {
    const related = summaries.filter((summary) => summaryMatchesProject(summary, project))
    const counts = related.reduce<HealthCounts>((total, summary) => {
      const current = summaryHealth(summary)
      total.running += current.running
      total.stopped += current.stopped
      total.error += current.error
      return total
    }, { running: 0, stopped: 0, error: 0 })
    return {
      ...project,
      nodeCount: related.length,
      running: counts.running,
      stopped: counts.stopped,
      error: counts.error,
      instanceTotal: counts.running + counts.stopped + counts.error,
      status: statusOf(counts, related.length),
    }
  })
}

function compareInstances(left: AgentInstance, right: AgentInstance): number {
  return (
    (left.id || '').localeCompare(right.id || '', 'zh-CN', { numeric: true, sensitivity: 'base' }) ||
    (left.pid ?? 0) - (right.pid ?? 0)
  )
}

/**
 * 一台节点的实例：运行中的在前，失败/停止的在后。
 *
 * 与 PC 端语义一致：`declared` 存在时以声明为准（配置里删掉的 server 不再展示），
 * 否则退回 `instances` / `health`。
 */
export function mergeAgentInstances(agent: AgentStatus): AgentInstance[] {
  const report = agent.basReport
  const running = report?.instances ?? []
  const healthById = new Map((agent.health ?? []).map((item) => [item.id, item]))
  const declaredKnown = Array.isArray(report?.declared)
  if (!declaredKnown) {
    if (running.length === 0) {
      return (agent.health ?? [])
        .map((item) => ({ id: item.id, state: item.state, rssBytes: item.rssBytes }))
        .sort(compareInstances)
    }
    return running
      .map((instance) => ({
        ...instance,
        state: 'running' as const,
        rssBytes: instance.rssBytes ?? (instance.id ? healthById.get(instance.id)?.rssBytes : undefined),
      }))
      .sort(compareInstances)
  }
  const runningById = new Map<string, AgentInstance>()
  for (const instance of running) {
    if (instance.id) runningById.set(instance.id, instance)
  }
  const merged: AgentInstance[] = []
  for (const declared of report?.declared ?? []) {
    const live = declared.id ? runningById.get(declared.id) : undefined
    if (live) {
      merged.push({
        ...live,
        state: 'running',
        rssBytes: live.rssBytes ?? healthById.get(live.id || '')?.rssBytes,
      })
      if (declared.id) runningById.delete(declared.id)
    } else {
      merged.push({ ...declared, state: 'stopped' })
    }
  }
  return merged.sort(compareInstances)
}

/** 按 project + ip 定位一台在线节点；没有 ip 且有多台时返回 undefined，让页面先让用户选。 */
export function findAgent(agents: AgentStatus[], project: string, ip?: string): AgentStatus | undefined {
  const scoped = agents.filter((agent) => agent.project === project)
  if (ip) return scoped.find((agent) => (agent.ip || '') === ip)
  return scoped.length === 1 ? scoped[0] : undefined
}

/** 定位实例；agent 缺失或实例名缺失都返回 undefined。 */
export function findInstance(
  agent: AgentStatus | undefined,
  instanceId: string | undefined,
): AgentInstance | undefined {
  if (!agent || !instanceId) return undefined
  return mergeAgentInstances(agent).find((instance) => instance.id === instanceId)
}

/** CPU=load1/核数，内存=已用/总量，磁盘=所有挂载点里最高使用率；全部钳制在 0–100。 */
export function resourceUsage(os: AgentOsSnapshot | undefined): ResourceUsage {
  const cpu = os?.cpu
  const cores = numberOrUndefined(cpu?.cores)
  const load1 = numberOrUndefined(cpu?.load1)
  const cpuPercent = load1 !== undefined && cores !== undefined && cores > 0
    ? clampPercent((load1 / cores) * 100)
    : undefined

  const mem = os?.mem
  const memoryTotal = numberOrUndefined(mem?.total)
  const memoryAvailable = numberOrUndefined(mem?.available)
  const memoryPercent = memoryTotal !== undefined && memoryTotal > 0 && memoryAvailable !== undefined
    ? clampPercent(((memoryTotal - memoryAvailable) / memoryTotal) * 100)
    : undefined

  const diskPercent = maxDiskPercent(os?.disk ?? [])

  return { cpuPercent, memoryPercent, diskPercent }
}

function maxDiskPercent(disks: AgentDiskInfo[]): number | undefined {
  const values = disks
    .filter((disk): disk is { total: number; available: number } =>
      typeof disk.total === 'number' && typeof disk.available === 'number' && disk.total > 0)
    .map((disk) => clampPercent(((disk.total - disk.available) / disk.total) * 100))
  return values.length > 0 ? Math.max(...values) : undefined
}

/** 节点卡片上的原始容量文本；没有上报时返回 `undefined`，由组件显示占位。 */
export function deviceResources(agent: AgentStatus | undefined): DeviceResources {
  const os = agent?.os
  const cpu = os?.cpu
  const mem = os?.mem
  const disks = os?.disk ?? []
  const root = disks.find((disk) => disk.mount === '/') ?? disks[0]
  const memoryTotal = numberOrUndefined(mem?.total)
  const memoryAvailable = numberOrUndefined(mem?.available)
  const diskTotal = numberOrUndefined(root?.total)
  const diskAvailable = numberOrUndefined(root?.available)
  return {
    osName: [os?.os?.name, os?.os?.kernel].filter(Boolean).join(' · '),
    cores: numberOrUndefined(cpu?.cores),
    load1: numberOrUndefined(cpu?.load1),
    memoryUsed: memoryTotal !== undefined && memoryAvailable !== undefined ? memoryTotal - memoryAvailable : undefined,
    memoryTotal,
    diskUsed: diskTotal !== undefined && diskAvailable !== undefined ? diskTotal - diskAvailable : undefined,
    diskTotal,
    diskMount: root?.mount,
  }
}

/** 单实例历史：返回最近 `days` 天的日格、可用率与状态变化。 */
export function historyForInstance(history: AgentHistory, instanceId: string, days: number): InstanceHistory {
  const byDate = new Map<string, { state: AgentHealth['state']; at: string; total: number; running: number }>()
  for (const sample of history.samples ?? []) {
    const state = sample.servers?.[instanceId]
    if (!isHealthState(state)) continue
    const date = dateKey(sample.at)
    if (!date) continue
    const day = byDate.get(date)
    if (!day) {
      byDate.set(date, { state, at: sample.at, total: 1, running: state === 'running' ? 1 : 0 })
    } else {
      day.state = state
      day.at = sample.at
      day.total += 1
      if (state === 'running') day.running += 1
    }
  }

  const anchor = dateKey(history.to) || latestSampleDate(history) || localDateKey(new Date())
  const dates = recentDateKeys(days, anchor)
  let total = 0
  let running = 0
  let sampledDays = 0
  let lastAt = ''
  const changes: HistoryChange[] = []
  let previous: AgentHealth['state'] | '' = ''
  const cells = dates.map((date): HistoryCell => {
    const day = byDate.get(date)
    if (!day) return { date, state: 'unknown', title: '无采样' }
    total += day.total
    running += day.running
    sampledDays += 1
    lastAt = day.at
    if (previous && previous !== day.state) changes.push({ at: day.at, state: day.state })
    previous = day.state
    return {
      date,
      state: day.state,
      title: `${day.running} 运行 / ${day.total - day.running} 停止或异常`,
    }
  })
  changes.reverse()
  return {
    instance: instanceId,
    cells,
    total,
    running,
    availability: total > 0 ? (running / total) * 100 : 0,
    sampledDays,
    lastAt,
    firstDate: dates[0] ?? '',
    lastDate: dates[dates.length - 1] ?? '',
    changes,
  }
}

function latestSampleDate(history: AgentHistory): string {
  let latest = ''
  for (const sample of history.samples ?? []) {
    const date = dateKey(sample.at)
    if (date > latest) latest = date
  }
  return latest
}

/** 能力判断：只有节点显式上报 `service:<action>` 才允许启停。 */
export function supportsService(
  agent: { supports?: string[] } | null | undefined,
  action: AgentServiceAction,
): boolean {
  return agent?.supports?.includes(`service:${action}`) === true
}

/** 节点健康计数；优先按 health 明细，缺失时退回摘要里的 running/stopped。 */
export function agentHealthCounts(agent: AgentStatus | AgentSummary): HealthCounts {
  if (agent.health && agent.health.length > 0) {
    return agent.health.reduce<HealthCounts>((counts, item) => {
      if (item.state === 'running') counts.running += 1
      else if (item.state === 'stopped') counts.stopped += 1
      else counts.error += 1
      return counts
    }, { running: 0, stopped: 0, error: 0 })
  }
  return {
    running: numberOrUndefined('running' in agent ? agent.running : undefined) ?? 0,
    stopped: numberOrUndefined('stopped' in agent ? agent.stopped : undefined) ?? 0,
    error: 0,
  }
}

/** 节点排序：异常优先，其次停止，再按 ip/主机名稳定排序。 */
export function compareAgentHealth(left: AgentStatus, right: AgentStatus): number {
  const rank = (agent: AgentStatus): number => {
    const counts = agentHealthCounts(agent)
    if (counts.error > 0) return 0
    if (counts.stopped > 0) return 1
    if (counts.running > 0) return 2
    return 3
  }
  return rank(left) - rank(right) || (left.ip || left.host || '').localeCompare(right.ip || right.host || '')
}

/** 项目卡片排序：异常优先，正常其次，离线最后；同级按机构与配置名。 */
export function compareProjectHealth(left: MobileProject, right: MobileProject): number {
  const rank = (status: ProjectStatus): number => {
    if (status === 'critical') return 0
    if (status === 'warning') return 1
    if (status === 'ok') return 2
    return 3
  }
  return (
    rank(left.status) - rank(right.status) ||
    left.orgName.localeCompare(right.orgName, 'zh-CN') ||
    left.qualifiedName.localeCompare(right.qualifiedName, 'zh-CN')
  )
}

export function projectStatusLabel(status: ProjectStatus): string {
  if (status === 'critical') return '严重'
  if (status === 'warning') return '警告'
  if (status === 'offline') return '离线'
  return '正常'
}

export function projectStatusTheme(status: ProjectStatus): 'success' | 'warning' | 'danger' | 'default' {
  if (status === 'critical') return 'danger'
  if (status === 'warning') return 'warning'
  if (status === 'offline') return 'default'
  return 'success'
}

export function stateLabel(state: MonitorState): string {
  if (state === 'running') return '运行中'
  if (state === 'stopped') return '已停止'
  if (state === 'error') return '异常'
  return '无采样'
}

export function stateTheme(state: MonitorState): 'success' | 'warning' | 'danger' | 'default' {
  if (state === 'running') return 'success'
  if (state === 'stopped') return 'warning'
  if (state === 'error') return 'danger'
  return 'default'
}

export function isInstanceRunning(instance: AgentInstance): boolean {
  return instance.state !== 'stopped' && instance.state !== 'error'
}

export function instanceState(instance: AgentInstance): MonitorState {
  if (instance.state === 'error') return 'error'
  return isInstanceRunning(instance) ? 'running' : 'stopped'
}

export function formatBytes(value: number | undefined): string {
  if (value === undefined || !Number.isFinite(value)) return '—'
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  let amount = Math.max(0, value)
  let unit = 0
  while (amount >= 1024 && unit < units.length - 1) {
    amount /= 1024
    unit += 1
  }
  return `${amount >= 10 || unit === 0 ? amount.toFixed(0) : amount.toFixed(1)} ${units[unit]}`
}

export function formatPercent(value: number | undefined): string {
  return value === undefined ? '—' : `${value}%`
}

/** 时间只留「月日 时:分:秒」；采样串里是服务器本地时间，不做浏览器时区换算。 */
export function shortTime(value: string | undefined): string {
  if (!value) return '—'
  const match = /^\d{4}-(\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})/.exec(value)
  return match ? `${match[1]} ${match[2]}` : value
}

export function relativeTime(value: string | undefined): string {
  if (!value) return '—'
  const at = new Date(value).getTime()
  if (Number.isNaN(at)) return value
  const seconds = Math.max(0, Math.floor((Date.now() - at) / 1000))
  if (seconds < 60) return `${seconds} 秒前`
  if (seconds < 3600) return `${Math.floor(seconds / 60)} 分钟前`
  return shortTime(value)
}

export function initials(title: string): string {
  return title.trim().slice(0, 1).toUpperCase() || 'P'
}

export function errorText(reason: unknown): string {
  return reason instanceof Error ? reason.message : String(reason)
}

/** 把百分比钳制到 0–100；组件层再展示进度条，避免各处重复 Math.min/max。 */
export function clampResourcePercent(value: number | undefined): number {
  return value === undefined ? 0 : clampPercent(value)
}
