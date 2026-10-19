import type { JsonApiRelationship, JsonApiResource } from '@beangle/ems-app'
import { API_PREFIX, apiClient, type ListQuery } from './client'

/** 一条资源：保留 JSON:API 的 attributes 与 relationships，便于通用列表/表单渲染。 */
export interface ResourceRow {
  id: string
  type: string
  attributes: Record<string, unknown>
  relationships: Record<string, JsonApiRelationship>
}

export interface ResourcePage {
  rows: ResourceRow[]
  included: ResourceRow[]
  page: { number: number; size: number; total: number }
}

export interface ResourceListQuery extends ListQuery {
  /** 需要一并返回的关联，如 `['org']`。 */
  include?: string[]
}

function toRow(resource: JsonApiResource): ResourceRow {
  return {
    id: resource.id,
    type: resource.type,
    attributes: (resource.attributes || {}) as Record<string, unknown>,
    relationships: resource.relationships || {},
  }
}

export async function listResource(path: string, params: ResourceListQuery = {}): Promise<ResourcePage> {
  const { include, ...rest } = params
  const document = await apiClient.get<JsonApiResource[]>(`${path}/search`, {
    ...rest,
    query: include && include.length > 0 ? { include: include.join(',') } : undefined,
  })

  const rows = (document.data || []).map(toRow)
  const included = (document.included || []).map(toRow)
  const page = document.meta?.page
  return {
    rows,
    included,
    page: page ?? { number: 1, size: rows.length, total: rows.length },
  }
}

/** 取单条记录（`GET {path}/{id}`，JSON:API 单资源文档）。 */
export async function getResource(path: string, id: string): Promise<ResourceRow> {
  const document = await apiClient.get<JsonApiResource>(`${path}/${id}`)
  if (!document.data) throw new Error(`未找到记录：${path}/${id}`)
  return toRow(document.data)
}

/** 取单条记录并一并返回 `include` 的关联（JSON:API 单资源文档）。 */
export async function getResourceDetail(
  path: string,
  id: string,
  include: string[] = [],
): Promise<{ row: ResourceRow; included: ResourceRow[] }> {
  const document = await apiClient.get<JsonApiResource>(`${path}/${id}`, {
    query: include.length > 0 ? { include: include.join(',') } : undefined,
  })
  if (!document.data) throw new Error(`未找到记录：${path}/${id}`)
  return { row: toRow(document.data), included: (document.included || []).map(toRow) }
}

/** 取自定义动作返回的 JSON:API 文档（如 `/hosts/{id}/webapps`），支持 `include`。 */
export async function fetchDocument(path: string, query?: Record<string, string>): Promise<ResourcePage> {
  const document = await apiClient.get<JsonApiResource[]>(path, { query })
  const rows = (document.data || []).map(toRow)
  const included = (document.included || []).map(toRow)
  const page = document.meta?.page
  return { rows, included, page: page ?? { number: 1, size: rows.length, total: rows.length } }
}

export async function saveResource(
  path: string,
  type: string,
  attributes: Record<string, unknown>,
  relationships: Record<string, unknown>,
  id?: string,
): Promise<void> {
  const data: Record<string, unknown> = { type, ...(id ? { id } : {}) }
  if (Object.keys(attributes).length > 0) data.attributes = attributes
  if (Object.keys(relationships).length > 0) data.relationships = relationships

  if (id) await apiClient.patch(`${path}/${id}`, { data })
  else await apiClient.post(path, { data })
}

export async function removeResource(path: string, id: string): Promise<void> {
  await apiClient.delete(`${path}/${id}`)
}

/** 调用资源上的批量动作（如 artifacts/update-version、webapps/upgrade）。 */
export async function callResourceAction(path: string, action: string, ids: string[]): Promise<void> {
  await apiClient.post(`${path}/${action}`, { ids })
}

/** 上传文件（multipart/form-data），用于菜单 XML 导入等。 */
export async function uploadResourceFile<T>(path: string, formData: FormData): Promise<T> {
  const document = await apiClient.upload<T>(path, formData)
  return document as unknown as T
}

/** 取非 JSON:API 结构的普通 JSON（如 `{xml: "..."}`）。 */
export function getPlainJson<T>(path: string, query?: Record<string, string>): Promise<T> {
  return apiClient.getPlain<T>(path, { query })
}

/** 取某条记录的关联 id 列表（to-one 也返回单元素数组）。 */
export function relationshipIds(row: ResourceRow | undefined, key: string): string[] {
  const data = row?.relationships[key]?.data
  if (!data) return []
  return Array.isArray(data) ? data.map((item) => item.id) : [data.id]
}

/**
 * 取关联目标的「类型 + id」。不同类型的记录 id 可能相同（如配置文件 id=1、服务 id=1），
 * 用 `included` 回取时必须带上类型，否则会串到别的类型上。
 */
export function relationshipTargets(row: ResourceRow | undefined, key: string): { type: string; id: string }[] {
  const data = row?.relationships[key]?.data
  if (!data) return []
  return (Array.isArray(data) ? data : [data]).map((item) => ({ type: item.type, id: item.id }))
}

/** 把 included 建成索引，方便按 id 取回关联记录的展示字段。 */
export function indexIncluded(included: ResourceRow[]): Map<string, ResourceRow> {
  const map = new Map<string, ResourceRow>()
  included.forEach((row) => {
    map.set(`${row.type}:${row.id}`, row)
    if (!map.has(row.id)) map.set(row.id, row)
  })
  return map
}

export function attributeText(value: unknown): string {
  if (value === null || value === undefined) return ''
  if (Array.isArray(value)) return value.join(', ')
  if (typeof value === 'boolean') return value ? '是' : '否'
  return String(value)
}
