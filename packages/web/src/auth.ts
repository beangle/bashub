import { createEmsAuth, createEmsRuntimeConfig, loadEmsRuntimeConfigs } from '@beangle/ems-app'
import { apiPath, apiRootPath } from '@/api/prefix'

/** SPA 部署前缀，须与独立 web 服务器的部署目录一致（构建时用 VITE_APP_BASE 覆盖）。 */
export const APP_BASE_PATH = import.meta.env.VITE_APP_BASE || '/bashub/'

/** 后端只出 API，EMS/CAS 地址统一由 `configs.json` 下发；VITE_CAS_* 仅作构建期兜底。 */
export const runtimeConfig = createEmsRuntimeConfig({
  appBasePath: APP_BASE_PATH,
  casBaseUrl: import.meta.env.VITE_CAS_BASE,
  casAuthLoginUrl: import.meta.env.VITE_CAS_AUTH_LOGIN_URL,
  casLoginUrl: import.meta.env.VITE_CAS_LOGIN_URL,
  casLogoutUrl: import.meta.env.VITE_CAS_LOGOUT_URL,
})

export async function loadRuntimeConfig(): Promise<void> {
  const { appConfig } = await loadEmsRuntimeConfigs({
    appConfigPath: apiRootPath('ems', '/configs.json'),
    // 独立部署暂不拉取平台主题；接入门户后由宿主下发。
    themeConfigPath: null,
  })
  if (appConfig) runtimeConfig.applyConfig(appConfig)
}

/** 登录会话：CAS 登录/登出 + token 存取，登出走本应用后端 `sessions/logout`。 */
export const auth = createEmsAuth({
  appBasePath: APP_BASE_PATH,
  casAuthLoginUrl: () => runtimeConfig.getCasAuthLoginUrl(),
  casLoginUrl: () => runtimeConfig.getCasLoginUrl(),
  casLogoutUrl: () => runtimeConfig.getCasLogoutUrl(),
  logoutUrl: () => runtimeConfig.getApiUrl(apiRootPath('ems', '/sessions/logout')),
})

export const sessionService = auth.sessionService
export const currentUser = auth.currentUser
export const initializeAuth = auth.initializeAuth
