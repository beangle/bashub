import { apiClient } from './client'
import { getPlainJson } from './resource'
import { sessionService } from '@/auth'
import { apiPath } from './prefix'

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

export interface EndpointCertificateInfo {
  /** PEM 公钥证书（可含完整链）。 */
  certificate: string
  /** 私钥是否已设置；私钥原文永远不下发。 */
  keySet: boolean
}

export function readEndpointCertificate(projectId: string, endpointName: string): Promise<EndpointCertificateInfo> {
  return getPlainJson<EndpointCertificateInfo>(
    apiPath('config', `/projects/${encodeURIComponent(projectId)}/endpoints/${encodeURIComponent(endpointName)}/certificate`),
  )
}

export async function saveEndpointCertificate(
  projectId: string,
  endpointName: string,
  input: { certificate: string; privateKey: string },
): Promise<EndpointCertificateInfo> {
  const document = await apiClient.patch<unknown>(
    apiPath('config', `/projects/${encodeURIComponent(projectId)}/endpoints/${encodeURIComponent(endpointName)}/certificate`),
    input,
  )
  return document as unknown as EndpointCertificateInfo
}
