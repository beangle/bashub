/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** 开发环境后端 origin，供 dev server 代理同源 /api 使用。 */
  readonly VITE_API_BASE?: string
  /** SPA 部署前缀，须与独立 web 服务器的部署目录一致。 */
  readonly VITE_APP_BASE?: string
  /** 可选的 CAS 构建期兜底地址；不配置时由 /api/bashub/configs.json 下发。 */
  readonly VITE_CAS_BASE?: string
  readonly VITE_CAS_AUTH_LOGIN_URL?: string
  readonly VITE_CAS_LOGIN_URL?: string
  readonly VITE_CAS_LOGOUT_URL?: string
}

declare module '*.vue' {
  import type { DefineComponent } from 'vue'

  const component: DefineComponent<object, object, unknown>
  export default component
}
