<template>
  <div class="mobile-shell">
    <header class="mobile-shell__header">
      <router-link v-if="project" class="mobile-shell__context" :to="contextTarget">
        <img
          v-if="projectLogo && !logoFailed"
          class="mobile-shell__context-logo"
          :src="projectLogo"
          :alt="projectTitle"
          @error="logoFailed = true"
        />
        <span v-else class="mobile-shell__context-logo mobile-shell__context-logo--fallback">
          {{ projectInitial }}
        </span>
        <span class="mobile-shell__context-text">
          <span class="mobile-shell__context-title">{{ projectTitle }}</span>
          <span class="mobile-shell__context-subtitle">
            <span v-if="projectSubtitle">{{ projectSubtitle }}</span>
            <span class="mobile-shell__context-switch">切换项目</span>
          </span>
        </span>
      </router-link>
      <div v-else class="mobile-shell__brand">
        <span class="mobile-shell__brand-title">BAS 监控台</span>
      </div>

      <div v-if="!currentUser" class="mobile-shell__account">
        <t-button class="mobile-shell__login" size="small" theme="primary" @click="handleLogin">
          登录
        </t-button>
      </div>
    </header>

    <div v-if="canInstall && !isStandalone" class="mobile-install-banner">
      <span>安装到桌面</span>
      <t-button size="small" theme="primary" @click="installApp">安装</t-button>
    </div>

    <main class="mobile-shell__main">
      <router-view />
    </main>

    <t-tab-bar
      :value="activeTab"
      :fixed="false"
      :bordered="true"
      :safe-area-inset-bottom="true"
      @change="onTabChange"
    >
      <t-tab-bar-item value="monitor">
        <template #icon><ChartIcon /></template>
        监控
      </t-tab-bar-item>
      <t-tab-bar-item value="manage">
        <template #icon><SettingIcon /></template>
        管理
      </t-tab-bar-item>
      <t-tab-bar-item value="me">
        <template #icon><UserIcon /></template>
        我的
      </t-tab-bar-item>
    </t-tab-bar>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChartIcon, SettingIcon, UserIcon } from 'tdesign-icons-vue-next'
import { canInstall, installApp, isStandalone } from '@/pwa'
import { auth } from '@/auth'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import { initials } from '@/monitor-model'

const { currentUser, handleLogin } = auth.useAuth()
const route = useRoute()
const router = useRouter()
const catalog = useProjectCatalog()

const project = computed(() => String(route.params.project ?? ''))
const projectInfo = computed(() => catalog.projectOf(project.value))
const projectTitle = computed(() => projectInfo.value?.title || project.value)
const projectLogo = computed(() => projectInfo.value?.logoUrl || '')
const projectInitial = computed(() => initials(projectTitle.value))
const logoFailed = ref(false)
watch(project, () => {
  logoFailed.value = false
})
const projectSubtitle = computed(() => {
  const info = projectInfo.value
  if (!info) return ''
  const parts = [info.orgTitle]
  if (info.qualifiedName && info.qualifiedName !== info.title) parts.push(info.qualifiedName)
  return parts.filter((part) => part.length > 0).join(' · ')
})

/** 三个标签各占一个路由前缀；管理页的项目上下文仍要回管理列表，不回监控首页。 */
const activeTab = computed(() => {
  if (route.path.startsWith('/manage')) return 'manage'
  return route.path.startsWith('/me') ? 'me' : 'monitor'
})

const contextTarget = computed(() => (route.path.startsWith('/manage') ? '/manage' : '/'))

function onTabChange(payload: string | number | { value: string | number }): void {
  // TDesign Mobile 的 onChange 实际回调是值本身（d.ts 写的是 {value}），两种都兼容。
  const value = String(typeof payload === 'object' ? payload.value : payload)
  if (value === 'me') void router.push('/me')
  else if (value === 'manage') void router.push('/manage')
  else if (value === 'monitor') void router.push('/')
}

onMounted(() => {
  void catalog.load()
})
</script>
