import { apiClient } from './client'
import { apiPath } from './prefix'

export interface SessionInfo {
  code?: string
  name?: string
}

/** 当前登录用户；未登录时后端返回 401 并触发 CAS 跳转。 */
export function getSession(): Promise<SessionInfo> {
  return apiClient.getPlain<SessionInfo>(apiPath('ems', '/sessions'))
}
