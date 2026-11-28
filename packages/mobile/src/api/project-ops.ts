import { apiClient } from './client'
import { apiPath } from './prefix'

export interface MicdnServerInfo {
  host: string
}

export interface MicdnProjectDocument {
  config: {
    servers: MicdnServerInfo[]
  }
  components: unknown[]
}

export type ProxyNodeState = 'applied' | 'pending' | 'unknown' | 'error'

export interface ProxyNodeStatus {
  ip: string
  state: ProxyNodeState
  appliedHash?: string
  appliedAt?: string
}

export interface ProxyEndpointStatus {
  name: string
  engine: string
  hash: string
  nodes: ProxyNodeStatus[]
}

/** 各代理节点最近一次应用的 bundle hash 与当前配置对比；按需调用，不轮询。 */
export async function readProjectProxyState(projectId: string): Promise<ProxyEndpointStatus[]> {
  const document = await apiClient.getPlain<{ data?: ProxyEndpointStatus[] }>(
    apiPath('config', `/projects/${encodeURIComponent(projectId)}/proxy-state`),
  )
  return document.data ?? []
}

export interface OperationResult {
  host: string
  ok: boolean
  error?: string
  data?: unknown
}

export function getMicdnProject(projectId: string): Promise<MicdnProjectDocument> {
  return apiClient.getPlain<MicdnProjectDocument>(apiPath('micdn', `/projects/${encodeURIComponent(projectId)}`))
}

export async function reloadMicdnProject(projectId: string): Promise<OperationResult[]> {
  const document = await apiClient.post<OperationResult[]>(
    apiPath('micdn', `/projects/${encodeURIComponent(projectId)}/reload`),
    {},
  )
  return document.data ?? []
}

export async function applyProjectProxy(
  projectId: string,
  engine: 'haproxy' | 'nginx',
  endpoint: string,
): Promise<OperationResult[]> {
  const document = await apiClient.post<OperationResult[]>(
    apiPath('config', `/projects/${encodeURIComponent(projectId)}/proxy/apply`),
    { engine, endpoint },
  )
  return document.data ?? []
}
