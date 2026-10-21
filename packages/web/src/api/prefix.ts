/** bashub 后端根前缀；能力域在它下面再分组。 */
export const API_PREFIX = '/api/bashub'

/** 能力域前缀，均相对于 `API_PREFIX`。 */
export const API_GROUPS = {
  ems: '/ems',
  config: '/config',
  micdn: '/micdn',
  monitor: '/monitor',
} as const

export type ApiGroup = keyof typeof API_GROUPS

/** 只有 EMS 自身的数据走 `ems`，其余管理台资源统一走 `config`。 */
const EMS_RESOURCE_PATHS = new Set(['channels', 'menus', 'resources'])

/** 供 `EmsJsonApiClient` 使用的组内路径。 */
export function apiPath(group: ApiGroup, path = ''): string {
  if (!path) return API_GROUPS[group]
  return `${API_GROUPS[group]}${path.startsWith('/') ? path : `/${path}`}`
}

/** 完整路径，用于运行时配置、下载链接等不经过 `apiClient` 的场景。 */
export function apiRootPath(group: ApiGroup, path = ''): string {
  return `${API_PREFIX}${apiPath(group, path)}`
}

/** 通用资源路径按资源名选择能力域，例如 `/menus` → `ems`、`/profiles` → `config`。 */
export function resourceApiPath(path: string): string {
  const resource = path.replace(/^\/+/, '').split('/')[0]
  return apiPath(EMS_RESOURCE_PATHS.has(resource) ? 'ems' : 'config', path)
}
