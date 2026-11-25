import { createApp } from 'vue'
import 'tdesign-mobile-vue/dist/tdesign.css'
import { initializeAuth, loadRuntimeConfig } from '@/auth'
import App from './App.vue'
import router from './router'
import '@/mobile.css'

async function mount(): Promise<void> {
  // 先取运行时配置（EMS/CAS 地址），再据此初始化登录态。
  await loadRuntimeConfig()
  await initializeAuth()
  createApp(App).use(router).mount('#app')
}

void mount()
