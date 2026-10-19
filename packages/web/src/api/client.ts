import { EmsJsonApiClient, jsonApiContentType } from '@beangle/ems-app'
import { sessionService } from '@/auth'

export const JSONAPI_CONTENT_TYPE = jsonApiContentType

/** hub 管理接口前缀，资源名为英文复数。 */
export const API_PREFIX = '/api/hub'

/**
 * 统一使用 ems-app 的 `EmsJsonApiClient`：JSON:API 内容协商、
 * `page[...]`/`filter[...]` 查询、`URP_SID` 追加与 401/302 跳 CAS 登录都由它处理。
 */
export const apiClient = new EmsJsonApiClient({
  basePath: API_PREFIX,
  session: {
    getAuthHeaders: (contentType) => sessionService.getAuthHeaders(contentType),
    login: (redirectUrl) => sessionService.requireLogin(redirectUrl),
  },
})

export interface ListQuery {
  pageNumber?: number
  pageSize?: number
  /** 排序，`-` 前缀表示倒序，例如 `-name`。 */
  sort?: string
  /** 实体属性查询条件，如 `{ 'platform.name': 'x' }`，后端按 `filter[...]` 解析。 */
  filters?: Record<string, string | number | null | undefined>
}
