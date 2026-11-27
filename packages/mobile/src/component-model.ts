/**
 * 手机端「组件」的纯数据模型：列表排序/搜索、编辑表单映射与部署行整理。
 * 不发请求、不碰全局状态；组件字段口径与 PC `resources/index.ts` 的 artifacts 表一致。
 */
import { attributeText, indexIncluded, relationshipIds, type ResourceRow } from '@/api/resource'

/** 面向平台：与后端 `arch`(number) 和 PC 下拉一致。 */
export const ARCH_OPTIONS = [
  { label: 'Noarch', value: 1 },
  { label: 'X86_64', value: 2 },
  { label: 'AArch64', value: 3 },
] as const

/** 打包类型：与 PC 组件表单一致；bin 已无运行时支持，不再提供。 */
export const PACKAGING_OPTIONS = ['jar', 'war', 'tar.gz'] as const

/** tar.gz 是 native 包：要面向平台与可执行文件，不需要解析/JSP/WebSocket。 */
export function isNativePackaging(packaging: string): boolean {
  return packaging === 'tar.gz'
}

/** 组件详情页的可写字段；`gav` 是后端计算字段，不在这里。 */
export interface ComponentForm {
  title: string
  groupId: string
  artifactId: string
  packaging: string
  classifier: string
  latestVersion: string
  contextPath: string
  exec: string
  arch: number
  projectId: string
  description: string
  resolveSupport: boolean
  jspSupport: boolean
  websocketSupport: boolean
}

/** 一条组件部署：项目名/标题、实际版本、上下文与启用状态。 */
export interface ComponentDeployment {
  id: string
  projectName: string
  projectTitle: string
  logoUrl: string
  version: string
  contextPath: string
  enabled: boolean
}

export function artifactTitle(row: ResourceRow): string {
  return attributeText(row.attributes.title) || attributeText(row.attributes.artifactId) || '未命名组件'
}

/** `groupId:artifactId`：列表副标题与搜索都用它。 */
export function artifactCoordinates(row: ResourceRow): string {
  const group = attributeText(row.attributes.groupId)
  const id = attributeText(row.attributes.artifactId)
  return group && id ? `${group}:${id}` : group || id || '—'
}

export function archLabel(value: unknown): string {
  const text = String(value ?? '').trim()
  if (!text) return '—'
  return ARCH_OPTIONS.find((item) => String(item.value) === text)?.label || text
}

/** 列表顺序：先 groupId、再 artifactId，同一组坐标排在一起（PC 列表只按 artifactId）。 */
export function compareArtifact(left: ResourceRow, right: ResourceRow): number {
  return (
    attributeText(left.attributes.groupId).localeCompare(attributeText(right.attributes.groupId), 'en') ||
    attributeText(left.attributes.artifactId).localeCompare(attributeText(right.attributes.artifactId), 'en', {
      numeric: true,
    })
  )
}

/** 搜索：标题、groupId、artifactId 任一命中即可。 */
export function filterArtifacts(rows: ResourceRow[], keyword: string): ResourceRow[] {
  const term = keyword.trim().toLowerCase()
  if (!term) return rows
  return rows.filter((row) =>
    [artifactTitle(row), attributeText(row.attributes.groupId), attributeText(row.attributes.artifactId)].some(
      (value) => value.toLowerCase().includes(term),
    ),
  )
}

/** 空表单：加载完成前占位，缺省值与 PC 表单一致（jar / Noarch）。 */
export function defaultComponentForm(): ComponentForm {
  return {
    title: '',
    groupId: '',
    artifactId: '',
    packaging: 'jar',
    classifier: '',
    latestVersion: '',
    contextPath: '',
    exec: '',
    arch: 1,
    projectId: '',
    description: '',
    resolveSupport: false,
    jspSupport: false,
    websocketSupport: false,
  }
}

/** 绑定 Project 的组件（客户定制）按项目分组；未绑定的归「通用组件」。 */
export interface ArtifactGroup {
  projectId: string
  rows: ResourceRow[]
}

export function groupArtifacts(rows: ResourceRow[]): { custom: ArtifactGroup[]; generic: ResourceRow[] } {
  const custom = new Map<string, ResourceRow[]>()
  const generic: ResourceRow[] = []
  for (const row of rows) {
    const projectId = relationshipIds(row, 'project')[0] ?? ''
    if (projectId) {
      const list = custom.get(projectId) ?? []
      list.push(row)
      custom.set(projectId, list)
    } else {
      generic.push(row)
    }
  }
  return {
    custom: [...custom.entries()].map(([projectId, groupRows]) => ({
      projectId,
      rows: [...groupRows].sort(compareArtifact),
    })),
    generic: [...generic].sort(compareArtifact),
  }
}

function booleanValue(value: unknown): boolean {
  return value === true || value === 'true'
}

/** 组件行 → 编辑表单；缺省值对齐后端必填与 PC 默认（打包类型 jar、面向平台 Noarch）。 */
export function formOf(row: ResourceRow): ComponentForm {
  const attrs = row.attributes
  const arch = Number(attributeText(attrs.arch))
  return {
    title: attributeText(attrs.title),
    groupId: attributeText(attrs.groupId),
    artifactId: attributeText(attrs.artifactId),
    packaging: attributeText(attrs.packaging) || 'jar',
    classifier: attributeText(attrs.classifier),
    latestVersion: attributeText(attrs.latestVersion),
    contextPath: attributeText(attrs.contextPath),
    exec: attributeText(attrs.exec),
    arch: Number.isFinite(arch) && arch > 0 ? arch : 1,
    projectId: relationshipIds(row, 'project')[0] ?? '',
    description: attributeText(attrs.description),
    resolveSupport: booleanValue(attrs.resolveSupport),
    jspSupport: booleanValue(attrs.jspSupport),
    websocketSupport: booleanValue(attrs.websocketSupport),
  }
}

/**
 * 表单 → PATCH attributes：按打包类型归一化不适用字段，避免隐藏字段把旧值带回去。
 * jar/war 固定 Noarch 且没有可执行文件；tar.gz 固定不需要解析/JSP/WebSocket。
 * 分类器两种类型都不在手机端编辑，原值保留提交。
 */
export function attributesOf(form: ComponentForm): Record<string, unknown> {
  const native = isNativePackaging(form.packaging)
  return {
    title: form.title.trim(),
    groupId: form.groupId.trim(),
    artifactId: form.artifactId.trim(),
    packaging: form.packaging,
    classifier: form.classifier.trim(),
    latestVersion: form.latestVersion.trim(),
    contextPath: form.contextPath.trim(),
    exec: native ? form.exec.trim() : '',
    arch: native ? Number(form.arch) : 1,
    description: form.description.trim(),
    resolveSupport: native ? false : form.resolveSupport,
    jspSupport: native ? false : form.jspSupport,
    websocketSupport: native ? false : form.websocketSupport,
  }
}

/** 保存前的必填校验；返回空串表示可保存。 */
export function formError(form: ComponentForm): string {
  if (!form.title.trim()) return '标题不能为空'
  if (!form.artifactId.trim()) return 'artifactId 不能为空'
  if (!form.groupId.trim()) return 'groupId 不能为空'
  if (!form.packaging) return '请选择打包类型'
  if (!form.latestVersion.trim()) return '最新版本不能为空'
  if (isNativePackaging(form.packaging) && !ARCH_OPTIONS.some((item) => item.value === Number(form.arch))) {
    return '请选择面向平台'
  }
  return ''
}

export function isEnabled(value: unknown): boolean {
  return value === undefined || value === true || value === 'true'
}

/**
 * 部署情况：`/artifacts/{id}/webapps?include=project,project.org` 的 data + included。
 * 只留展示字段；按项目名、上下文、版本排序，保证刷新后行不跳动。
 */
export function buildDeployments(rows: ResourceRow[], included: ResourceRow[]): ComponentDeployment[] {
  const index = indexIncluded(included)
  return rows
    .map((row) => {
      const projectId = relationshipIds(row, 'project')[0] ?? ''
      const project = projectId ? index.get(projectId) : undefined
      const orgId = project ? relationshipIds(project, 'org')[0] ?? '' : ''
      const org = orgId ? index.get(orgId) : undefined
      return {
        id: row.id,
        projectName: project ? attributeText(project.attributes.qualifiedName) || attributeText(project.attributes.name) : '',
        projectTitle: project ? attributeText(project.attributes.title) : '',
        logoUrl: org ? attributeText(org.attributes.logoUrl) : '',
        version: attributeText(row.attributes.version),
        contextPath: attributeText(row.attributes.contextPath),
        enabled: isEnabled(row.attributes.enabled),
      }
    })
    .sort(
      (left, right) =>
        left.projectName.localeCompare(right.projectName, 'zh-CN') ||
        left.contextPath.localeCompare(right.contextPath) ||
        left.version.localeCompare(right.version, undefined, { numeric: true }),
    )
}
