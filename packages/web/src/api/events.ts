import { apiClient } from './client'
import { apiPath } from './prefix'

export type ServerEventAction = 'start' | 'stop' | 'restart'

export interface ServerEvent {
  id: string
  instance: string
  action: ServerEventAction
  operator?: string
  operatorName?: string
  operatorIp?: string
  agentIp?: string
  ok: boolean
  detail?: string
  at?: string
}

/** 某 Project（或某实例）的手工启停记录，最新在前。 */
export async function readServerEvents(
  project: string,
  options: { instance?: string; limit?: number } = {},
): Promise<ServerEvent[]> {
  const params = new URLSearchParams()
  if (options.instance) params.set('instance', options.instance)
  if (options.limit) params.set('limit', String(options.limit))
  const query = params.size > 0 ? `?${params.toString()}` : ''
  const result = await apiClient.getPlain<{ data?: ServerEvent[] }>(
    apiPath('monitor', `/agents/${encodeURIComponent(project)}/events${query}`),
  )
  return result.data ?? []
}
