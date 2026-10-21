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
  state?: 'running' | 'stopped'
}

export interface AgentBasSnapshot {
  /** 本机正在运行的实例，来自 `server.info`。 */
  instances?: AgentInstance[]
  /** 本机 `server.xml` 声明的实例，实例停止后仍保留，供控制台发起启动。 */
  declared?: AgentInstance[]
}

/** `GET /api/bashub/monitor/agents/status` 里的一项：一台在线节点此刻的样子。 */
export interface AgentStatus {
  profile: string
  host?: string
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

/** 要求在线节点立刻上报一次；202 只表示指令已入队，快照随后到达。 */
export async function requestAgentReport(profile: string): Promise<void> {
  await apiClient.post(apiPath('monitor', `/agents/${encodeURIComponent(profile)}/report`), {})
}

/** 让节点启停一个实例；接口等到 agent 执行完才返回最终状态。 */
export async function serviceAgentInstance(
  profile: string,
  instance: string,
  action: AgentServiceAction,
): Promise<AgentServiceResult> {
  const document = await apiClient.post<AgentServiceResult>(
    apiPath('monitor', `/agents/${encodeURIComponent(profile)}/service/${action}`),
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
): Promise<AgentLogWindow> {
  const query: Record<string, string> = { instance }
  if (from?.trim()) query.from = from.trim()
  if (to?.trim()) query.to = to.trim()
  if (tail && tail > 0) query.tail = String(tail)
  return apiClient.getPlain<AgentLogWindow>(
    apiPath('monitor', `/agents/${encodeURIComponent(profile)}/log`),
    { query },
  )
}

/**
 * 打开日志跟随流。认证靠同源 cookie；`resolveUrl` 仍会在跨域部署时追加 `URP_SID`。
 * 事件由浏览器自动重连，并带上 `Last-Event-ID`，服务端会从下一条继续。
 */
export function followAgentLog(profile: string, instance: string, tail = 200): EventSource {
  const url = apiClient.resolveUrl(
    apiPath('monitor', `/agents/${encodeURIComponent(profile)}/log/follow`),
    { query: { instance, tail: String(tail) } },
  )
  return new EventSource(url, { withCredentials: true })
}
