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
    <router-view :key="route.path" />
  </AppShell>
</template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, type Component } from 'vue'
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
import { resourceSchemas, resourceTabGroups } from '@/resources'

const { handleLogin, handleLogout } = auth.useAuth()
const route = useRoute()

/** 分组图标；分组标题即 schema.group，未登记的分组退化为 FolderIcon。 */
const groupIcons: Record<string, Component> = {
  平台配置: Setting1Icon,
  应用与菜单: AppIcon,
  Micdn: CloudIcon,
  应用监控: ChartIcon,
}

/**
 * 叶子菜单图标，对齐原 BAS 左侧菜单的 FontAwesome 图标：
 * profiles=fa-user、platform-features=fa-linux、engines=fa-gear、hosts=fa-server、
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
  profiles: UserIcon,
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
  'cdn-components': CloudIcon,
  agents: ServerIcon,
}

/** 概览单列；资源按 schema.group 归组缩进；运维页面并入对应分组。 */
function buildMenus(): AppShellMenuItem[] {
  const groups = new Map<string, AppShellMenuItem[]>()
  // 页签合成页占用「分组里最先出现的成员」的位置（与页签顺序无关，调页签不会挪菜单），
  // 其余页签资源不再单列（schema.menu === false）。
  const tabGroupBySchema = new Map(
    resourceTabGroups.flatMap((group) => group.tabs.map((tab) => [tab.key, group])),
  )
  const placedTabGroups = new Set<string>()
  resourceSchemas.forEach((schema) => {
    const children = groups.get(schema.group) ?? []
    const tabGroup = tabGroupBySchema.get(schema.key)
    if (tabGroup && !placedTabGroups.has(tabGroup.key)) {
      placedTabGroups.add(tabGroup.key)
      children.push({ path: tabGroup.path, title: tabGroup.title, icon: itemIcons[tabGroup.key] || AppIcon })
    }
    if (schema.menu === false) {
      groups.set(schema.group, children)
      return
    }
    children.push({ path: schema.path, title: schema.title, icon: itemIcons[schema.key] || AppIcon })
    groups.set(schema.group, children)
  })
  groups.set('应用监控', [
    { path: '/agents', title: '在线节点', icon: ServerIcon },
  ])
  groups.set('Micdn', [
    { path: '/cdn-components', title: '组件目录', icon: CloudIcon },
  ])

  const items: AppShellMenuItem[] = [{ path: '/home', title: '概览', icon: HomeIcon }]
  groups.forEach((children, title) => {
    items.push({ path: '', title, icon: groupIcons[title] ?? FolderIcon, children })
  })
  return items
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

onMounted(() => {
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
