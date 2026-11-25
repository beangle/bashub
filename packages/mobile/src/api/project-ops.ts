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
