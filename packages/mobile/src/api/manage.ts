/**
 * 手机端「部署」的取数与动作封装。
 *
 * 只调用既有端点：`config` 域的资源查询（`webapps` / `endpoints` / `servers` / `artifacts`）与
 * 两个既有动作（`webapps/upgrade`、`PATCH webapps/{id}`），以及只读能力查询
 * `ems/authorizations`（回答「当前会话能不能做这件事」）。
 */
import { apiClient } from './client'
import { apiPath } from './prefix'
import { attributeText, callResourceAction, indexIncluded, listResource, relationshipIds, saveResource, type ResourcePage } from './resource'

/** 部署页用到的能力项；键与 `resource:action` 完全一致，便于直接查表。 */
export const MANAGE_CHECKS = {
  deploy: '/config/webapps:post',
  deployEdit: '/config/webapps:patch',
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

/** 一次取回全部应用部署与代理点；部署首页的角标和项目页都从这里取数，不按项目 N+1 请求。 */
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

/** 换组件用的组件目录条目：标题、Maven artifactId、默认上下文与最新版本。 */
export interface ArtifactOption {
  id: string
  title: string
  artifactName: string
  /** 组件默认上下文；为空表示该组件没有默认上下文（按后台任务部署）。 */
  contextPath: string
  latestVersion: string
}

/** 一次取回全部组件，供组件选择弹层在前端搜索；组件数量与 PC 列表同源，不按项目过滤。 */
export async function listArtifacts(): Promise<ArtifactOption[]> {
  const page = await listAllRows('/artifacts')
  return page.rows
    .map((row) => ({
      id: row.id,
      title: attributeText(row.attributes.title) || attributeText(row.attributes.artifactId),
      artifactName: attributeText(row.attributes.artifactId),
      contextPath: attributeText(row.attributes.contextPath),
      latestVersion: attributeText(row.attributes.latestVersion),
    }))
    .sort(
      (left, right) =>
        left.title.localeCompare(right.title, 'zh-CN') || left.artifactName.localeCompare(right.artifactName),
    )
}

/** 部署详情页一次保存的全部可变项；不变的部分也照原值提交，PATCH 是幂等覆盖。 */
export interface WebappEdit {
  artifactId: string
  contextPath: string
  version: string
  targetIds: string[]
  endpointIds: string[]
}

/** 保存应用部署的组件、上下文、版本、运行目标与代理点；只改配置，不重启实例，重启后生效。 */
export async function saveWebapp(id: string, edit: WebappEdit): Promise<void> {
  await saveResource(
    '/webapps',
    'webapps',
    { version: edit.version, contextPath: edit.contextPath },
    {
      artifact: { data: { type: 'artifacts', id: edit.artifactId } },
      targets: { data: edit.targetIds.map((target) => ({ type: 'servers', id: target })) },
      endpoints: { data: edit.endpointIds.map((endpoint) => ({ type: 'endpoints', id: endpoint })) },
    },
    id,
  )
}

export interface ServerOption {
  id: string
  label: string
}

/** 代理点选项：与 `ServerOption` 同形但语义不同，单独命名避免把服务当代理点。 */
export interface EndpointOption {
  id: string
  label: string
}

/** 当前 Project 下可作为运行目标的服务；标签用后端派生的 `displayName`（群集.服务 (IP)）。 */
export async function listProjectServers(projectId: string): Promise<ServerOption[]> {
  const page = await listResource('/servers', { pageSize: 500, include: ['farm'] })
  const farms = indexIncluded(page.included)
  return page.rows
    .filter((row) => {
      const farmId = relationshipIds(row, 'farm')[0] ?? ''
      const farm = farms.get(farmId)
      return farm ? (relationshipIds(farm, 'project')[0] ?? '') === projectId : false
    })
    .map((row) => ({ id: row.id, label: attributeText(row.attributes.displayName) || attributeText(row.attributes.name) }))
    .sort((left, right) => left.label.localeCompare(right.label, 'zh-CN'))
}
