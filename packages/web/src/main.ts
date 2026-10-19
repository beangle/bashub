import { createApp, type App as VueApp } from 'vue'
import { registerWujieApp } from '@beangle/ems-app'
import 'tdesign-vue-next/es/style/index.css'
// 平台/菜单的 fonticon 存的是 Font Awesome 的类名（fa-brands fa-centos 等），
// 旧 FTL 由 b.head 从静态资源里加载 font-awesome；SPA 自包含，这里只引 solid + brands 两套字体。
import '@fortawesome/fontawesome-free/css/fontawesome.min.css'
import '@fortawesome/fontawesome-free/css/solid.min.css'
import '@fortawesome/fontawesome-free/css/brands.min.css'
import '@beangle/bui-vue/styles/data-grid.css'
import '@beangle/bui-vue/styles/query-form.css'
import '@beangle/bui-vue/styles/workbench.css'
import '@beangle/bui-vue/styles/underline-tabs.css'
import '@beangle/bui-vue/styles/drawer-form.css'
import '@beangle/bui-vue/styles/side-nav.css'
import '@beangle/ems-app/dist/index.css'
// @beangle/bui-vue 的 DataGrid 用 resolveComponent('t-table') 这类运行时名字取组件，
// unplugin 的按需导入只改写本应用模板，覆盖不到库产物，必须在此全局注册。
import Button from 'tdesign-vue-next/es/button'
import Checkbox from 'tdesign-vue-next/es/checkbox'
import InputNumber from 'tdesign-vue-next/es/input-number'
import Loading from 'tdesign-vue-next/es/loading'
import Popup from 'tdesign-vue-next/es/popup'
import Select, { Option } from 'tdesign-vue-next/es/select'
import Table from 'tdesign-vue-next/es/table'
import EnhancedTable from 'tdesign-vue-next/es/table/enhanced-table'
import { initializeAuth, loadRuntimeConfig } from '@/auth'
import App from './App.vue'
import router from './router'
import './styles.css'

const gridComponents = [Button, Checkbox, InputNumber, Loading, Option, Popup, Select, Table]

let app: VueApp<Element> | null = null

async function mount() {
  if (app) return
  // 先取运行时配置（EMS/CAS 地址），再据此初始化登录态。
  await loadRuntimeConfig()
  await initializeAuth()
  const instance = createApp(App)
  instance.use(router)
  gridComponents.forEach((component) => instance.use(component))
  // 树形表格由 EnhancedTable 提供（DataGrid 以 t-enhanced-table 动态引用）。
  instance.component('TEnhancedTable', EnhancedTable)
  app = instance
  instance.mount('#app')
}

function unmount() {
  app?.unmount()
  app = null
}

registerWujieApp({ mount, unmount })
