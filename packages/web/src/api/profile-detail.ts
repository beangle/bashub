import { apiClient } from './client'
import { getPlainJson } from './resource'
import { sessionService } from '@/auth'

export interface SetlinePeer {
  name: string
  url: string
}

export type ProfileConfigKind = 'proxy' | 'server'

const contentTypes: Record<ProfileConfigKind, string> = {
  proxy: 'text/plain',
  server: 'application/xml',
}

export async function readProfileConfig(profileId: string, kind: ProfileConfigKind): Promise<string> {
  const url = apiClient.resolveUrl(`/profiles/${encodeURIComponent(profileId)}/config/${kind}`)
  const response = await fetch(url, {
    credentials: 'include',
    headers: {
      ...sessionService.getAuthHeaders(''),
      Accept: contentTypes[kind],
    },
  })
  if (response.status === 404) return ''
  if (!response.ok) {
    throw new Error(`${kind === 'proxy' ? '代理配置' : 'server.xml'}加载失败（HTTP ${response.status}）`)
  }
  return response.text()
}

export async function readSetlinePeers(profileId: string): Promise<SetlinePeer[]> {
  const document = await getPlainJson<{ peers?: SetlinePeer[] }>(
    `/profiles/${encodeURIComponent(profileId)}/config/setline-peers`,
  )
  return document.peers ?? []
}
