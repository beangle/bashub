import { ref } from 'vue'
import type { FieldSchema, ResourceSchema } from '@/resources/types'

/**
 * 记忆「当前配置」——原 web 端 cookie `current_project_id`（`ProjectHelper`）的前端对等物。
 *
 * 群集管理/主机管理/应用部署这类以配置为工作域的资源，查询条件里的「配置」默认取记忆值；
 * 用户在查询条件里选中的配置会写回记忆，切到别的资源页仍然沿用。
 * 存 localStorage 而不是 cookie：后端只出 API，没有读这个值的服务端逻辑
 * （旧实现是 Action 里 `ProjectHelper.setRememberedProject` 把 cookie 塞回请求属性）。
 */
const STORAGE_KEY = 'bashub.current_project_id'

function readStored(): string {
  try {
    return window.localStorage.getItem(STORAGE_KEY) ?? ''
  } catch {
    return ''
  }
}

/** 记忆的配置 id；空串表示还没选过。 */
export const currentProjectId = ref(readStored())

/** 归一化配置 id（下拉框给回的是 string，但表单里可能是 number）。 */
export function projectId(value: unknown): string {
  if (value === null || value === undefined || value === '') return ''
  return String(value)
}

/** 记住用户选中的配置；空值不覆盖，与旧 `ProjectHelper.remember` 只记非空值一致。 */
export function rememberProject(value: unknown): void {
  const id = projectId(value)
  if (id === '' || id === currentProjectId.value) return
  currentProjectId.value = id
  try {
    window.localStorage.setItem(STORAGE_KEY, id)
  } catch {
    /* 隐私模式等场景忽略写入失败 */
  }
}

/** 忘掉记忆：记忆的配置已被删除时用。 */
export function forgetProject(): void {
  if (currentProjectId.value === '') return
  currentProjectId.value = ''
  try {
    window.localStorage.removeItem(STORAGE_KEY)
  } catch {
    /* 同上 */
  }
}

/** 单值「配置」关联字段（`ref`→projects）。多值的 `refs`（如静态组的「针对配置」）不算当前配置。 */
export function isProjectRef(field: FieldSchema): boolean {
  return field.type === 'ref' && (field.ref?.type === 'projects' || field.ref?.path === '/projects')
}

/**
 * 资源是否以配置为工作域：查询条件里有配置，或表单里有必填的配置。
 * 命中后：查询条件默认取当前配置，新建表单的配置字段默认取当前配置。
 * （原 UI 里只有 farm/host/webapp 这样做，artifact/engine 的「针对配置」是各自可空的选项。）
 */
export function isProjectScoped(schema: ResourceSchema): boolean {
  return (schema.filters ?? []).some(isProjectRef) || schema.fields.some((field) => isProjectRef(field) && field.required)
}
