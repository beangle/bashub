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
  /** 证书 notAfter；自动解析或人工填写，格式 YYYY-MM-DDTHH:MM:SSZ。 */
  certificateNotAfter: string
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
  input: { certificate: string; privateKey: string; certificateNotAfter?: string },
): Promise<EndpointCertificateInfo> {
  const document = await apiClient.patch<unknown>(
    apiPath('config', `/projects/${encodeURIComponent(projectId)}/endpoints/${encodeURIComponent(endpointName)}/certificate`),
    input,
  )
  return document as unknown as EndpointCertificateInfo
}
/** 管理台按登录会话下载代理 ZIP；不需要 Project key。 */
export async function downloadProjectProxyBundle(
  projectId: string,
  engine: 'haproxy' | 'nginx',
  endpoint: string,
): Promise<void> {
  const query = new URLSearchParams({ engine })
  if (endpoint) query.set('endpoint', endpoint)
  const url = apiClient.resolveUrl(apiPath('config', `/projects/${encodeURIComponent(projectId)}/proxy-bundle?${query}`))
  const response = await fetch(url, {
    credentials: 'include',
    headers: {
      ...sessionService.getAuthHeaders(''),
      Accept: 'application/zip',
    },
  })
  if (!response.ok) {
    throw new Error(`代理 bundle 下载失败（HTTP ${response.status}）`)
  }
  const blob = await response.blob()
  const disposition = response.headers.get('Content-Disposition') || ''
  const match = /filename="?([^";]+)"?/.exec(disposition)
  const filename = match?.[1] || `proxy-bundle-${engine}.zip`
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(link.href)
}
