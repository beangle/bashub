import { apiClient } from './client'
import { apiPath } from './prefix'

export interface AgentOsInfo {
  name?: string
  kernel?: string
  arch?: string
}

export interface AgentCpuInfo {
  cores?: number
  load1?: number
  load5?: number
  load15?: number
}

export interface AgentMemInfo {
  total?: number
  available?: number
}

export interface AgentDiskInfo {
  mount?: string
  total?: number
  available?: number
}

export interface AgentOsSnapshot {
  os?: AgentOsInfo
  cpu?: AgentCpuInfo
  mem?: AgentMemInfo
  disk?: AgentDiskInfo[]
}

export interface AgentWebapp {
  id?: string
  uri?: string
  context?: string
  urls?: string[]
}

export interface AgentInstance {
  id?: string
  pid?: number
  engine?: string
  httpPort?: number
  started?: string
  webapps?: AgentWebapp[]
  /** 前端合并 `instances` / `declared` 后得到的状态；接口本身只对运行实例给出 `running`。 */
  state?: 'running' | 'stopped' | 'error'
}

export interface AgentBasSnapshot {
  /** 本机正在运行的实例，来自 `server.info`。 */
  instances?: AgentInstance[]
  /** 本机 `server.xml` 声明的实例，实例停止后仍保留，供控制台发起启动。 */
  declared?: AgentInstance[]
}

/** Profile 所属机构的展示信息（监控卡片用它当大标题与 Logo）。 */
export interface AgentOrganization {
  name?: string
  title?: string
  shortTitle?: string
  logoUrl?: string
}

/** `GET /api/bashub/monitor/agents/status` 里的一项：一台在线节点此刻的样子。 */
export interface AgentStatus {
  profile: string
  /** agent 上报的服务器 IP；同一 profile 下用它区分不同机器。 */
  ip?: string
  host?: string
  org?: AgentOrganization
  basctl?: string
  bas?: string
  basHome?: string
  supports?: string[]
  connectedAt?: string
  lastSeenAt?: string
  osAt?: string
  os?: AgentOsSnapshot
  basAt?: string
  basReport?: AgentBasSnapshot
  healthAt?: string
  health?: AgentHealth[]
}

export interface AgentHealth {
  id: string
  state: 'running' | 'stopped' | 'error'
}

/** `GET /api/bashub/monitor/agents/summary`：在线列表轮询用的轻量摘要。 */
export interface AgentSummary {
  profile: string
  /** agent 上报的服务器 IP；同一 profile 下用它区分不同机器。 */
  ip?: string
  host?: string
  org?: AgentOrganization
  basctl?: string
  bas?: string
  supports?: string[]
  connectedAt?: string
  lastSeenAt?: string
  healthAt?: string
  running?: number
  stopped?: number
  health?: AgentHealth[]
}

/** 一个采样点：同一时刻整个 profile 的 server 状态。 */
export interface AgentHistorySample {
  at: string
  servers: Record<string, AgentHealth['state']>
}

export interface AgentHistory {
  profile: string
  from: string
  to: string
  days: number
  samples: AgentHistorySample[]
}

export interface AgentLogWindow {
  total: number
  from: number
  to: number
  lines: string[]
}

/** SSE `lines` 事件：`reset=true` 时替换窗口，否则追加。 */
export interface AgentLogEvent extends AgentLogWindow {
  reset?: boolean
}

export type AgentServiceAction = 'start' | 'stop' | 'restart'

export interface AgentServiceResult {
  state: 'running' | 'stopped'
  pid?: number
}

export async function listAgents(): Promise<AgentStatus[]> {
  const result = await apiClient.getPlain<{ agents?: AgentStatus[] }>(apiPath('monitor', '/agents/status'))
  return result.agents ?? []
}

/** 读取节点的半年运行历史：一次取回 profile 的原始采样，按 server 聚合由页面完成。 */
export async function readAgentHistory(
  profile: string,
  options: { days?: number } = {},
): Promise<AgentHistory> {
  const query: Record<string, string> = { days: String(options.days ?? 180) }
  return apiClient.getPlain<AgentHistory>(
    apiPath('monitor', `/agents/${encodeURIComponent(profile)}/history`),
    { query },
  )
}

/** 目标 agent 的查询参数：同一 profile 有多台在线 agent 时必填（值为 `/agents/status` 里的 `ip`）。 */
function agentQuery(agent?: string): string {
  return agent ? `?agent=${encodeURIComponent(agent)}` : ''
}

/** 要求在线节点立刻上报一次；202 只表示指令已入队，快照随后到达。 */
export async function requestAgentReport(profile: string, agent?: string): Promise<void> {
  await apiClient.post(
    apiPath('monitor', `/agents/${encodeURIComponent(profile)}/report`) + agentQuery(agent),
    {},
  )
}

/** 让节点启停一个实例；接口等到 agent 执行完才返回最终状态。 */
export async function serviceAgentInstance(
  profile: string,
  instance: string,
  action: AgentServiceAction,
  agent?: string,
): Promise<AgentServiceResult> {
  const document = await apiClient.post<AgentServiceResult>(
    apiPath('monitor', `/agents/${encodeURIComponent(profile)}/service/${action}`) + agentQuery(agent),
    { instance },
  )
  if (!document.data) throw new Error('节点未返回服务状态')
  return document.data
}

export function readAgentLog(
  profile: string,
  instance: string,
  from?: string,
  to?: string,
  tail?: number,
  agent?: string,
): Promise<AgentLogWindow> {
  const query: Record<string, string> = { instance }
  if (from?.trim()) query.from = from.trim()
  if (to?.trim()) query.to = to.trim()
  if (tail && tail > 0) query.tail = String(tail)
  if (agent) query.agent = agent
  return apiClient.getPlain<AgentLogWindow>(
    apiPath('monitor', `/agents/${encodeURIComponent(profile)}/log`),
    { query },
  )
}

/**
 * 打开日志跟随流。认证靠同源 cookie；`resolveUrl` 仍会在跨域部署时追加 `URP_SID`。
 * 事件由浏览器自动重连，并带上 `Last-Event-ID`，服务端会从下一条继续。
 */
export function followAgentLog(
  profile: string,
  instance: string,
  tail = 200,
  agent?: string,
): EventSource {
  const query: Record<string, string> = { instance, tail: String(tail) }
  if (agent) query.agent = agent
  const url = apiClient.resolveUrl(
    apiPath('monitor', `/agents/${encodeURIComponent(profile)}/log/follow`),
    { query },
  )
  return new EventSource(url, { withCredentials: true })
}

/** 读取 basagent 自身的 console 日志；窗口参数与实例日志相同，但没有实例名。 */
export function readAgentOwnLog(
  profile: string,
  from?: string,
  to?: string,
  tail?: number,
  agent?: string,
): Promise<AgentLogWindow> {
  const query: Record<string, string> = {}
  if (from?.trim()) query.from = from.trim()
  if (to?.trim()) query.to = to.trim()
  if (tail && tail > 0) query.tail = String(tail)
  if (agent) query.agent = agent
  return apiClient.getPlain<AgentLogWindow>(
    apiPath('monitor', `/agents/${encodeURIComponent(profile)}/agent-log`),
    { query },
  )
}
