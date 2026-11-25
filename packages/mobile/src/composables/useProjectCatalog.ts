/**
 * 手机端的项目目录：一次拉取全部 Project（含所属机构），供项目列表与手机壳的
 * 顶部项目上下文共用。目录只在浏览器内存里缓存，不写 localStorage，也不读 PC 的当前项目。
 */
import { ref } from 'vue'
import { attributeText, listResource, type ResourceRow } from '@/api/resource'
import { errorText, type ProjectInfo } from '@/monitor-model'

const projects = ref<ProjectInfo[]>([])
const loading = ref(false)
const error = ref('')
const loaded = ref(false)
let inflight: Promise<void> | null = null

function indexRows(rows: ResourceRow[]): Map<string, ResourceRow> {
  const index = new Map<string, ResourceRow>()
  for (const row of rows) {
    index.set(`${row.type}:${row.id}`, row)
    if (!index.has(row.id)) index.set(row.id, row)
  }
  return index
}

function toProjectInfo(row: ResourceRow, index: Map<string, ResourceRow>): ProjectInfo {
  const attributes = row.attributes
  const name = attributeText(attributes.name)
  const qualifiedName = attributeText(attributes.qualifiedName) || name
  const title = attributeText(attributes.title) || name || qualifiedName || row.id
  const target = row.relationships.org?.data
  const reference = Array.isArray(target) ? target[0] : target
  const org = reference ? index.get(`${reference.type}:${reference.id}`) ?? index.get(reference.id) : undefined
  const orgTitle = org ? attributeText(org.attributes.title) || attributeText(org.attributes.shortTitle) : ''
  const orgShortTitle = org ? attributeText(org.attributes.shortTitle) || orgTitle : ''
  const orgName = org ? attributeText(org.attributes.name) || orgTitle : ''
  const logoUrl = org ? attributeText(org.attributes.logoUrl) : ''
  return {
    id: row.id,
    name,
    qualifiedName,
    title,
    orgTitle: orgTitle || '未归属机构',
    orgShortTitle,
    orgName,
    logoUrl,
  }
}

function compareProjects(left: ProjectInfo, right: ProjectInfo): number {
  return (
    left.orgName.localeCompare(right.orgName, 'zh-CN') ||
    left.qualifiedName.localeCompare(right.qualifiedName, 'zh-CN')
  )
}

/** 拉取项目目录；`force` 为真时忽略已加载缓存，供下拉刷新/手动刷新使用。 */
export function useProjectCatalog() {
  async function load(force = false): Promise<void> {
    if (inflight) return inflight
    if (loaded.value && !force) return
    loading.value = true
    error.value = ''
    inflight = (async () => {
      try {
        const page = await listResource('/projects', { pageSize: 500, include: ['org'] })
        const index = indexRows(page.included)
        projects.value = page.rows.map((row) => toProjectInfo(row, index)).sort(compareProjects)
        loaded.value = true
      } catch (reason) {
        error.value = errorText(reason)
      } finally {
        loading.value = false
        inflight = null
      }
    })()
    return inflight
  }

  /** 按 URL 里的 qualifiedName 找项目；也接受裸 name，方便旧链接。 */
  function projectOf(qualifiedName: string): ProjectInfo | undefined {
    if (!qualifiedName) return undefined
    return projects.value.find((project) => project.qualifiedName === qualifiedName || project.name === qualifiedName)
  }

  return { projects, loading, error, loaded, load, projectOf }
}
