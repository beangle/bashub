/**
 * 手机端「组件」的取数与保存：只调用既有端点。
 *
 * 列表逐页取全量后前端搜索（与 PC 组件列表同源）；详情带所属项目；
 * 部署情况走 `GET /config/artifacts/{id}/webapps`；保存走通用 `PATCH /config/artifacts/{id}`。
 * 不碰组件版本刷新端点，也不新建/删除组件。
 */
import {
  fetchDocument,
  getResourceDetail,
  listResource,
  saveResource,
  type ResourcePage,
  type ResourceRow,
} from './resource'

/** 组件详情页用到的能力项；键与 `resource:action` 完全一致。 */
export const ARTIFACT_CHECKS = {
  edit: '/config/artifacts:patch',
} as const

const PAGE_SIZE = 200
/** 单次列表最多翻 20 页（4000 行）；组件量与 PC 列表同源，超过时按前 20 页展示。 */
const MAX_PAGES = 20

/** 一次取回全部组件（逐页拼接），供列表页前端搜索。 */
export async function loadArtifactCatalog(): Promise<ResourcePage> {
  const rows: ResourceRow[] = []
  const included: ResourceRow[] = []
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const result = await listResource('/artifacts', { pageSize: PAGE_SIZE, pageNumber: page })
    rows.push(...result.rows)
    included.push(...result.included)
    if (result.rows.length < PAGE_SIZE) break
  }
  return { rows, included, page: { number: 1, size: rows.length, total: rows.length } }
}

/** 组件详情：一并带回所属项目。 */
export function loadArtifactDetail(id: string) {
  return getResourceDetail('/artifacts', id, ['project'])
}

/** 使用该组件部署的应用；项目与机构一并取回，用于展示项目名与标题。 */
export function loadArtifactDeployments(id: string): Promise<ResourcePage> {
  return fetchDocument(`/artifacts/${encodeURIComponent(id)}/webapps`, {
    include: 'project,project.org',
    pageSize: '100',
  })
}

/** 保存组件定义；`projectId` 为空表示通用组件（`relationships.project.data = null`）。 */
export async function saveArtifact(
  id: string,
  attributes: Record<string, unknown>,
  projectId: string,
): Promise<void> {
  await saveResource(
    '/artifacts',
    'artifacts',
    attributes,
    { project: { data: projectId ? { type: 'projects', id: projectId } : null } },
    id,
  )
}
