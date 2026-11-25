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
          class="mobile-touch mobile-shell__logout"
          size="small"
          variant="text"
          @click="handleLogout()"
        >
          退出
        </t-button>
        <t-button v-else class="mobile-touch mobile-shell__login" size="small" theme="primary" @click="handleLogin">
          登录
        </t-button>
      </div>
    </header>

    <main class="mobile-shell__main">
      <router-view />
    </main>

    <nav class="mobile-shell__nav" aria-label="手机端导航">
      <template v-if="project">
        <router-link class="mobile-shell__nav-item" :class="{ 'is-active': section === 'overview' }" :to="overviewPath">
          概览
        </router-link>
        <router-link class="mobile-shell__nav-item" :class="{ 'is-active': section === 'nodes' }" :to="nodesPath">
          节点
        </router-link>
      </template>
      <router-link
        v-else
        class="mobile-shell__nav-item"
        :class="{ 'is-active': section === 'projects' }"
        to="/"
      >
        项目
      </router-link>
      <router-link class="mobile-shell__nav-item" :class="{ 'is-active': section === 'me' }" to="/me">
        我的
      </router-link>
    </nav>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { auth } from '@/auth'
import { useProjectCatalog } from '@/composables/useProjectCatalog'

type MobileSection = 'projects' | 'overview' | 'nodes' | 'me'

const { currentUser, handleLogin, handleLogout } = auth.useAuth()
const route = useRoute()
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

onMounted(() => {
  void catalog.load()
})
</script>
