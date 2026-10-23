import { apiClient } from './client'
import { getPlainJson } from './resource'
import { sessionService } from '@/auth'
import { apiPath } from './prefix'

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
  const url = apiClient.resolveUrl(apiPath('config', `/profiles/${encodeURIComponent(profileId)}/${kind}`))
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
    apiPath('config', `/profiles/${encodeURIComponent(profileId)}/setline-peers`),
  )
  return document.peers ?? []
}

export interface ProfileCertificateInfo {
  /** PEM 公钥证书（可含完整链）。 */
  certificate: string
  /** 私钥是否已设置；私钥原文永远不下发。 */
  keySet: boolean
}

export function readProfileCertificate(profileId: string): Promise<ProfileCertificateInfo> {
  return getPlainJson<ProfileCertificateInfo>(
    apiPath('config', `/profiles/${encodeURIComponent(profileId)}/certificate`),
  )
}

export async function saveProfileCertificate(
  profileId: string,
  input: { certificate: string; privateKey: string },
): Promise<ProfileCertificateInfo> {
  const document = await apiClient.patch<unknown>(
    apiPath('config', `/profiles/${encodeURIComponent(profileId)}/certificate`),
    input,
  )
  return document as unknown as ProfileCertificateInfo
}
