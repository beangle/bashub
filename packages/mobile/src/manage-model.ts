/**
 * 手机端「管理」的纯数据模型：把 `webapps` / `endpoints` 的 JSON:API 行整理成展示行，
 * 并按项目汇总待办。这里不发请求、不碰全局状态，也不重新实现版本比较——可升级判定直接用
 * 后端 `present` 给出的 `updatable`（`versionIsNewer` 只有一处实现）。
 */
import { attributeText, indexIncluded, relationshipIds, type ResourceRow } from '@/api/resource'
import type { ProjectInfo } from '@/monitor-model'

/** 证书到期预警窗口（天）；与后端 `certificateExpiring` 的列表提醒保持一致。 */
export const CERT_WARN_DAYS = 30

/** 一条应用部署：组件标题、上下文、当前版本与组件最新版本。 */
export interface ManageApp {
  id: string
  projectId: string
  /** 组件 id；用来读取「已发布版本」候选。 */
  artifactId: string
  title: string
  contextPath: string
  version: string
  latestVersion: string
  /** 运行目标（服务）id；编辑页用它预选，列表只关心数量。 */
  targetIds: string[]
  /** 运行目标（服务）数量。 */
  targets: number
  /** 后端判定的「可升级」，前端不自行比较版本号。 */
  upgradable: boolean
}

/** 一个代理点的证书现状；只读，不含私钥。 */
export interface ManageCert {
  id: string
  projectId: string
  name: string
  domain: string
  engine: string
  /** `YYYY-MM-DD` 或空；后端只暴露公钥的到期日。 */
  expires: string
  /** `certificate` 属性里是否真有公钥证书；与 PC「公钥/私钥 已配置」同一口径。 */
  hasCertificate: boolean
  /** 距今天数；证书已配置但没记录到期日时为 `null`。 */
  daysLeft: number | null
  https: boolean
}

export interface ProjectPending {
  apps: number
  upgrades: number
  certificates: number
  expiring: number
}

function truthy(value: unknown): boolean {
  return value === true || value === 'true'
}

/** 证书日期前缀按 `YYYY-MM-DD` 解析，与后端 `certificateExpiring` 的取法一致；超出部分忽略。 */
export function daysUntil(expires: string, now: Date = new Date()): number | null {
  const text = expires.trim()
  if (text.length < 10) return null
  const year = Number(text.slice(0, 4))
  const month = Number(text.slice(5, 7))
  const day = Number(text.slice(8, 10))
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) return null
  if (month < 1 || month > 12 || day < 1 || day > 31) return null
  const target = Date.UTC(year, month - 1, day)
  const base = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())
  return Math.round((target - base) / 86_400_000)
}

export function buildApps(rows: ResourceRow[], included: ResourceRow[] = []): ManageApp[] {
  const artifacts = indexIncluded(included)
  // 已停用的部署不在手机端展示：它们不运行、也不参与待升级统计，避免列表里出现一堆不可操作的行。
  const apps = rows.filter((row) => (row.attributes.enabled === undefined ? true : truthy(row.attributes.enabled))).map((row) => {
    const artifactId = relationshipIds(row, 'artifact')[0] ?? ''
    const artifact = artifacts.get(artifactId)
    const attributes = row.attributes
    return {
      id: row.id,
      projectId: relationshipIds(row, 'project')[0] ?? '',
      artifactId,
      title:
        (artifact && attributeText(artifact.attributes.title)) ||
        attributeText(attributes.artifactName) ||
        '未命名组件',
      contextPath: attributeText(attributes.contextPath),
      version: attributeText(attributes.version),
      latestVersion: artifact ? attributeText(artifact.attributes.latestVersion) : '',
      targetIds: relationshipIds(row, 'targets'),
      targets: relationshipIds(row, 'targets').length,
      upgradable: truthy(attributes.updatable),
    }
  })
  // 顺序只跟部署上下文有关：升级/改版后行不会跳动，上下文相同再按组件标题兜底。
  return apps.sort(
    (left, right) =>
      left.contextPath.localeCompare(right.contextPath) ||
      left.title.localeCompare(right.title, 'zh-CN'),
  )
}

export function buildCerts(rows: ResourceRow[], now: Date = new Date()): ManageCert[] {
  const certs = rows.map((row) => {
    const expires = attributeText(row.attributes.certificateNotAfter)
    return {
      id: row.id,
      projectId: relationshipIds(row, 'project')[0] ?? '',
      name: attributeText(row.attributes.name),
      domain: attributeText(row.attributes.domain),
      engine: attributeText(row.attributes.engine),
      expires: expires.slice(0, 10),
      hasCertificate: attributeText(row.attributes.certificate).includes('BEGIN CERTIFICATE'),
      daysLeft: daysUntil(expires, now),
      https: truthy(row.attributes.enableHttps),
    }
  })
  return certs.sort(
    (left, right) =>
      (left.daysLeft ?? Number.MAX_SAFE_INTEGER) - (right.daysLeft ?? Number.MAX_SAFE_INTEGER) ||
      left.name.localeCompare(right.name, 'zh-CN'),
  )
}

/** 证书是否已进入预警（含已过期）。 */
export function certAlerted(cert: ManageCert): boolean {
  return cert.daysLeft !== null && cert.daysLeft <= CERT_WARN_DAYS
}

/** 证书状态文本：未配置 / 已配置但到期未知 / 已过期 N 天 / 剩余 N 天。 */
export function certLabel(cert: ManageCert): string {
  if (!cert.hasCertificate) return '未配置证书'
  if (cert.daysLeft === null) return '已配置 · 到期未知'
  if (cert.daysLeft < 0) return `已过期 ${Math.abs(cert.daysLeft)} 天`
  if (cert.daysLeft === 0) return '今天到期'
  return `剩余 ${cert.daysLeft} 天`
}

/** 证书标签配色：未配置中性、到期未知/临近警告、已过期严重。 */
export function certTheme(cert: ManageCert): 'success' | 'danger' | 'warning' | 'default' {
  if (!cert.hasCertificate) return 'default'
  if (cert.daysLeft === null) return 'warning'
  if (cert.daysLeft <= 0) return 'danger'
  return cert.daysLeft <= CERT_WARN_DAYS ? 'warning' : 'success'
}

export function summarizeProjects(
  projects: ProjectInfo[],
  apps: ManageApp[],
  certs: ManageCert[],
): Record<string, ProjectPending> {
  const pending: Record<string, ProjectPending> = {}
  for (const project of projects) {
    pending[project.id] = { apps: 0, upgrades: 0, certificates: 0, expiring: 0 }
  }
  for (const app of apps) {
    const entry = pending[app.projectId]
    if (!entry) continue
    entry.apps += 1
    if (app.upgradable) entry.upgrades += 1
  }
  for (const cert of certs) {
    const entry = pending[cert.projectId]
    if (!entry) continue
    entry.certificates += 1
    if (certAlerted(cert)) entry.expiring += 1
  }
  return pending
}

/** 有事项的项目排前面，其次按 `qualifiedName` 固定顺序。 */
export function sortProjectsByPending(
  projects: ProjectInfo[],
  pending: Record<string, ProjectPending>,
): ProjectInfo[] {
  const score = (project: ProjectInfo): number => {
    const entry = pending[project.id]
    return entry ? entry.upgrades + entry.expiring : 0
  }
  return [...projects].sort(
    (left, right) =>
      score(right) - score(left) || left.qualifiedName.localeCompare(right.qualifiedName, 'zh-CN'),
  )
}

/** 全量合计：给首页两个统计格用。 */
export function totalPending(pending: Record<string, ProjectPending>): { upgrades: number; expiring: number } {
  let upgrades = 0
  let expiring = 0
  for (const entry of Object.values(pending)) {
    upgrades += entry.upgrades
    expiring += entry.expiring
  }
  return { upgrades, expiring }
}
