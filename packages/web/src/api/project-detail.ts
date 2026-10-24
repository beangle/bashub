import { apiClient } from './client'
import { getPlainJson } from './resource'
import { sessionService } from '@/auth'
import { apiPath } from './prefix'

export interface SetlinePeer {
  name: string
  url: string
}

export type ProjectConfigKind = 'proxy' | 'server'

const contentTypes: Record<ProjectConfigKind, string> = {
  proxy: 'text/plain',
  server: 'application/xml',
}

export async function readProjectConfig(projectId: string, kind: ProjectConfigKind): Promise<string> {
  const url = apiClient.resolveUrl(apiPath('config', `/projects/${encodeURIComponent(projectId)}/${kind}`))
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

export async function readSetlinePeers(projectId: string): Promise<SetlinePeer[]> {
  const document = await getPlainJson<{ peers?: SetlinePeer[] }>(
    apiPath('config', `/projects/${encodeURIComponent(projectId)}/setline-peers`),
  )
  return document.peers ?? []
}

export interface ProjectCertificateInfo {
  /** PEM 公钥证书（可含完整链）。 */
  certificate: string
  /** 私钥是否已设置；私钥原文永远不下发。 */
  keySet: boolean
}

export function readProjectCertificate(projectId: string): Promise<ProjectCertificateInfo> {
  return getPlainJson<ProjectCertificateInfo>(
    apiPath('config', `/projects/${encodeURIComponent(projectId)}/certificate`),
  )
}

export async function saveProjectCertificate(
  projectId: string,
  input: { certificate: string; privateKey: string },
): Promise<ProjectCertificateInfo> {
  const document = await apiClient.patch<unknown>(
    apiPath('config', `/projects/${encodeURIComponent(projectId)}/certificate`),
    input,
  )
  return document as unknown as ProjectCertificateInfo
}
