<template>
  <AppShell
    :title="runtimeConfig.appTitle || 'BAS 配置中心'"
    :logo-url="runtimeConfig.logoUrl"
    brand-mark="BAS"
    subtitle="BAS Hub"
    :menus="menus"
    :active-path="route.path"
    :user-name="currentUser?.name || ''"
    :locale="locale"
    :theme-mode="themeMode"
    login-label="登录"
    logout-label="退出登录"
    @login="handleLogin"
    @logout="handleLogout"
    @update:locale="applyLocale"
    @update:theme-mode="applyThemeMode"
  >
    <template #topbar-extra>
      <t-select
        v-if="projectOptions.length > 0"
        v-model="selectedProject"
        class="global-project-picker"
        :options="projectOptions"
        size="small"
        filterable
        clearable
        placeholder="选择 Project"
      />
    </template>
    <router-view :key="route.path" />
  </AppShell>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch, type Component } from 'vue'
import { useRoute } from 'vue-router'
import {
  AppShell,
  type AppShellMenuItem,
} from '@beangle/ems-app/pc'
import {
  bindPortalUiSync,
  detectPortalLocale,
  detectPortalThemeMode,
  normalizePortalLocale,
  portalFontSizeToCss,
  type PortalLocale,
  type PortalThemeMode,
} from '@beangle/ems-app'
import {
  AppIcon,
  BuildingIcon,
  ChartIcon,
  CloudIcon,
  ComponentGridIcon,
  DesktopIcon,
  FolderIcon,
  HomeIcon,
  RocketIcon,
  ServerIcon,
  Setting1Icon,
  ShareIcon,
  SystemComponentsIcon,
  UsergroupIcon,
  UserIcon,
  ViewListIcon,
} from 'tdesign-icons-vue-next'
import { auth, currentUser, runtimeConfig } from '@/auth'
import { resourceApiPath } from '@/api/prefix'
import { attributeText, listResource } from '@/api/resource'
import { currentProjectId, forgetProject, projectId, rememberProject } from '@/current-project'
import { resourceSchemas, resourceTabGroups } from '@/resources'

const { handleLogin, handleLogout } = auth.useAuth()
const route = useRoute()
const projectOptions = ref<{ label: string; value: string }[]>([])
const selectedProject = computed({
  get: () => currentProjectId.value,
  set: (value: string | number | undefined) => {
    const id = projectId(value)
    if (id) rememberProject(id)
    else forgetProject()
  },
})

async function loadProjectOptions() {
  try {
    const result = await listResource('/projects', { pageSize: 500 })
    projectOptions.value = result.rows.map((row) => {
      const name = attributeText(row.attributes.qualifiedName) || attributeText(row.attributes.name)
      const title = attributeText(row.attributes.title)
      return { label: title ? `${name} · ${title}` : name || row.id, value: row.id }
    })
    if (currentProjectId.value && !projectOptions.value.some((option) => option.value === currentProjectId.value))
      forgetProject()
  } catch {
    projectOptions.value = []
  }
}

/** 分组图标；分组标题即 schema.group，未登记的分组退化为 FolderIcon。 */
const groupIcons: Record<string, Component> = {
  平台配置: Setting1Icon,
  应用与菜单: AppIcon,
  Micdn: CloudIcon,
  应用监控: ChartIcon,
}

/**
 * 叶子菜单图标，对齐原 BAS 左侧菜单的 FontAwesome 图标：
 * projects=fa-user、platform-features=fa-linux、engines=fa-gear、hosts=fa-server、
 * farms=fa-circle-nodes、artifacts=fa-app-store、webapps=fa-person-running、
 * apps=fa-app-store、menus=fa-bars。
 * 原菜单没有的页面选取语义相近的 TDesign 图标。
 */
const itemIcons: Record<string, Component> = {
  'org-config': BuildingIcon,
  'platform-ops': DesktopIcon,
  'app-config': UsergroupIcon,
  'menu-config': ViewListIcon,
  'farm-hosts': ShareIcon,
  organizations: BuildingIcon,
  platforms: ComponentGridIcon,
  projects: UserIcon,
  'platform-features': DesktopIcon,
  engines: Setting1Icon,
  hosts: ServerIcon,
  farms: ShareIcon,
  servers: SystemComponentsIcon,
  artifacts: AppIcon,
  webapps: RocketIcon,
  'app-groups': UsergroupIcon,
  apps: AppIcon,
  resources: FolderIcon,
  menus: ViewListIcon,
}

/** 左侧菜单按产品约定的三组组织，不再跟随 schema 自动生成。 */
function buildMenus(): AppShellMenuItem[] {
  return [
    { path: '/home', title: '概览', icon: HomeIcon },
    {
      path: '',
      title: '配置与监控',
      icon: ChartIcon,
      children: [
        { path: '/monitor/overview', title: '项目总览', icon: ChartIcon },
        { path: '/config/org-config', title: '项目配置', icon: UserIcon },
        { path: '/config/farm-hosts', title: '主机配置', icon: ServerIcon },
        { path: '/config/webapps', title: '部署维护', icon: RocketIcon },
        { path: '/monitor/agents', title: '在线监控', icon: DesktopIcon },
      ],
    },
    {
      path: '',
      title: '配置管理',
      icon: Setting1Icon,
      children: [
        { path: '/config/platform-ops', title: '操作系统', icon: ComponentGridIcon },
        { path: '/config/engines', title: '引擎管理', icon: Setting1Icon },
        { path: '/config/artifacts', title: '组件维护', icon: AppIcon },
        { path: '/micdn/components', title: '静态资源', icon: CloudIcon },
      ],
    },
    {
      path: '',
      title: '应用管理',
      icon: AppIcon,
      children: [
        { path: '/ems/app-config', title: '应用维护', icon: AppIcon },
        { path: '/ems/menu-config', title: '菜单管理', icon: ViewListIcon },
      ],
    },
  ]
}
const menus: AppShellMenuItem[] = buildMenus()

const locale = ref<PortalLocale>(detectPortalLocale())
const themeMode = ref<PortalThemeMode>(detectPortalThemeMode())

/** AppShell 的 update:locale 传的是字符串，归一后再落地。 */
function applyLocale(value: string) {
  const next = normalizePortalLocale(value)
  if (next) locale.value = next
}

function applyThemeMode(value: PortalThemeMode) {
  themeMode.value = value
  document.documentElement.setAttribute('theme-mode', value)
}

let unbindPortalUi: (() => void) | undefined

watch(currentUser, (user) => {
  if (user && projectOptions.value.length === 0) void loadProjectOptions()
})

onMounted(() => {
  void loadProjectOptions()
  applyThemeMode(themeMode.value)
  unbindPortalUi = bindPortalUiSync({
    onLocale: applyLocale,
    onThemeMode: applyThemeMode,
    onFontSize: (size) => {
      document.documentElement.style.fontSize = portalFontSizeToCss(size)
    },
  })
})

onBeforeUnmount(() => unbindPortalUi?.())
</script>
