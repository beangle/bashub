/**
 * 手机端「管理」的取数与动作封装。
 *
 * 只调用既有端点：`config` 域的资源查询（`webapps` / `endpoints`）与两个既有动作
 * （`webapps/upgrade`、`artifacts/update-version`），以及新增的只读能力查询
 * `ems/authorizations`（回答「当前会话能不能做这件事」）。
 */
import { apiClient } from './client'
import { apiPath } from './prefix'
import { callResourceAction, listResource, saveResource, type ResourcePage } from './resource'

/** 管理页用到的能力项；键与 `resource:action` 完全一致，便于直接查表。 */
export const MANAGE_CHECKS = {
  deploy: '/config/webapps:post',
  deployEdit: '/config/webapps:patch',
  artifacts: '/config/artifacts:post',
} as const

export type ManageCapabilities = Record<string, boolean>

const PAGE_SIZE = 200
/** 单次列表最多翻 20 页（4000 行）；超过时按前 20 页展示，不静默死循环。 */
const MAX_PAGES = 20

/** 逐页取完全量资源；`include` 用于把组件标题与最新版本一并带回。 */
async function listAllRows(path: string, include: string[] = []): Promise<ResourcePage> {
  const rows: ResourcePage['rows'] = []
  const included: ResourcePage['included'] = []
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const result = await listResource(path, { pageSize: PAGE_SIZE, pageNumber: page, include })
    rows.push(...result.rows)
    included.push(...result.included)
    if (result.rows.length < PAGE_SIZE) break
  }
  return { rows, included, page: { number: 1, size: rows.length, total: rows.length } }
}

export interface ManageCatalog {
  webapps: ResourcePage['rows']
  included: ResourcePage['included']
  endpoints: ResourcePage['rows']
}

/** 一次取回全部应用部署与代理点；管理首页的角标和项目页都从这里取数，不按项目 N+1 请求。 */
export async function loadManageCatalog(): Promise<ManageCatalog> {
  const [webapps, endpoints] = await Promise.all([
    listAllRows('/webapps', ['artifact']),
    listAllRows('/endpoints'),
  ])
  return { webapps: webapps.rows, included: webapps.included, endpoints: endpoints.rows }
}

/** 当前会话在若干 `resource:action` 上的能力；后端按同一份 `authorize` 判定。 */
export async function readCapabilities(checks: string[]): Promise<ManageCapabilities> {
  const document = await apiClient.getPlain<{
    checks?: { resource?: string; action?: string; allowed?: boolean }[]
  }>(apiPath('ems', '/authorizations'), { query: { checks: checks.join(',') } })
  const capabilities: ManageCapabilities = {}
  for (const item of document.checks ?? []) {
    const resource = String(item.resource ?? '')
    const action = String(item.action ?? '')
    if (!resource || !action) continue
    capabilities[`${resource}:${action}`] = item.allowed === true
  }
  return capabilities
}

/** 把所选应用部署的配置版本改成组件最新版本；实例重启后才生效。 */
export async function upgradeWebapps(ids: string[]): Promise<void> {
  if (ids.length === 0) return
  await callResourceAction('/webapps', 'upgrade', ids)
}

/** 组件在 Maven Central 上已发布的版本；取不到时后端返回空列表，调用方回退到手工输入。 */
export interface ArtifactVersions {
  latest: string
  versions: string[]
}

export async function readArtifactVersions(artifactId: string): Promise<ArtifactVersions> {
  return apiClient.getPlain<ArtifactVersions>(
    apiPath('config', `/artifacts/${encodeURIComponent(artifactId)}/versions`),
  )
}

/** 指定应用部署的版本（不限于最新）；只改 `version` 一个字段，不重启实例，重启后生效。 */
export async function editWebappVersion(id: string, version: string): Promise<void> {
  await saveResource('/webapps', 'webapps', { version }, {}, id)
}

/** 从仓库刷新所有组件的最新版本元数据。 */
export async function refreshArtifactVersions(): Promise<void> {
  await callResourceAction('/artifacts', 'update-version', [])
}
