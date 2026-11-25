<template>
  <div class="mobile-shell">
    <header class="mobile-shell__header">
      <router-link v-if="project" class="mobile-shell__context" to="/">
        <span class="mobile-shell__context-title">{{ projectTitle }}</span>
        <span class="mobile-shell__context-subtitle">
          <span v-if="projectSubtitle">{{ projectSubtitle }}</span>
          <span class="mobile-shell__context-switch">切换项目</span>
        </span>
      </router-link>
      <div v-else class="mobile-shell__brand">
        <span class="mobile-shell__brand-title">BAS 监控台</span>
      </div>

      <div class="mobile-shell__account">
        <router-link v-if="currentUser" class="mobile-shell__user" to="/me">
          {{ currentUser.name || '我的' }}
        </router-link>
        <t-button
          v-if="currentUser"
          class="mobile-shell__logout"
          size="small"
          variant="text"
          @click="handleLogout()"
        >
          退出
        </t-button>
        <t-button v-else class="mobile-shell__login" size="small" theme="primary" @click="handleLogin">
          登录
        </t-button>
      </div>
    </header>

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
      <t-tab-bar-item v-if="project" value="overview">
        <template #icon><HomeIcon /></template>
        概览
      </t-tab-bar-item>
      <t-tab-bar-item v-if="project" value="nodes">
        <template #icon><ServerIcon /></template>
        节点
      </t-tab-bar-item>
      <t-tab-bar-item v-if="!project" value="projects">
        <template #icon><ViewModuleIcon /></template>
        项目
      </t-tab-bar-item>
      <t-tab-bar-item value="me">
        <template #icon><UserIcon /></template>
        我的
      </t-tab-bar-item>
    </t-tab-bar>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { HomeIcon, ServerIcon, UserIcon, ViewModuleIcon } from 'tdesign-icons-vue-next'
import { auth } from '@/auth'
import { useProjectCatalog } from '@/composables/useProjectCatalog'

type MobileSection = 'projects' | 'overview' | 'nodes' | 'me'

const { currentUser, handleLogin, handleLogout } = auth.useAuth()
const route = useRoute()
const router = useRouter()
const catalog = useProjectCatalog()

const project = computed(() => String(route.params.project ?? ''))
const projectInfo = computed(() => catalog.projectOf(project.value))
const projectTitle = computed(() => projectInfo.value?.title || project.value)
const projectSubtitle = computed(() => {
  const info = projectInfo.value
  if (!info) return ''
  const parts = [info.orgTitle]
  if (info.qualifiedName && info.qualifiedName !== info.title) parts.push(info.qualifiedName)
  return parts.filter((part) => part.length > 0).join(' · ')
})

const overviewPath = computed(() => `/projects/${encodeURIComponent(project.value)}`)
const nodesPath = computed(() => `${overviewPath.value}/nodes`)

const section = computed<MobileSection>(() => {
  const path = route.path
  if (path === '/') return 'projects'
  if (path.startsWith('/me')) return 'me'
  if (!project.value) return 'projects'
  if (path.includes('/nodes') || path.includes('/instances/')) return 'nodes'
  return 'overview'
})

const activeTab = computed(() => section.value)

function onTabChange(payload: string | number | { value: string | number }): void {
  // TDesign Mobile 的 onChange 实际回调是值本身（d.ts 写的是 {value}），两种都兼容。
  const value = String(typeof payload === 'object' ? payload.value : payload)
  if (value === 'overview') void router.push(overviewPath.value)
  else if (value === 'nodes') void router.push(nodesPath.value)
  else if (value === 'projects') void router.push('/')
  else if (value === 'me') void router.push('/me')
}

onMounted(() => {
  void catalog.load()
})
</script>
