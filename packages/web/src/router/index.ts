import { createRouter, createWebHistory } from 'vue-router'
import { resourceApiPath } from '@/api/prefix'
import { resourceSchemas, resourceTabGroups } from '@/resources'

const tabSchemaKeys = new Set(resourceTabGroups.flatMap((group) => group.tabs.map((tab) => tab.key)))

const resourceRoutes = resourceSchemas
  .filter((schema) => !tabSchemaKeys.has(schema.key))
  .map((schema) => ({
    path: resourceApiPath(schema.path),
    component: () => import('@/views/ResourceListView.vue'),
    props: { schemaKey: schema.key },
    meta: { title: schema.title },
  }))

const tabRoutes = resourceTabGroups.map((group) => ({
  path: group.path,
  component: () => import('@/views/ResourceTabsView.vue'),
  props: { groupKey: group.key },
  meta: { title: group.title },
}))

/** 平台功能详情页（脚本就地维护，卡片墙由 `schema.cardLink` 指过来）。 */
const detailRoutes = [
  {
    path: '/config/platform-features/:id',
    component: () => import('@/views/PlatformFeatureDetailView.vue'),
    meta: { title: '平台功能' },
  },
  {
    path: '/config/hosts/:id',
    component: () => import('@/views/HostDetailView.vue'),
    meta: { title: '主机详情' },
  },
  {
    path: '/config/projects/:id',
    component: () => import('@/views/ProjectDetailView.vue'),
    meta: { title: '配置详情' },
  },
  {
    path: '/micdn/projects/:id',
    component: () => import('@/views/MicdnProjectView.vue'),
    meta: { title: 'Micdn 配置' },
  },
  {
    path: '/micdn/components',
    component: () => import('@/views/CdnComponentsView.vue'),
    meta: { title: 'Micdn 组件目录' },
  },
]

const router = createRouter({
  history: createWebHistory(import.meta.env.VITE_APP_BASE || import.meta.env.BASE_URL),
  routes: [
    { path: '/', redirect: '/home' },
    { path: '/home', component: () => import('@/views/HomeView.vue'), meta: { title: '概览' } },
    ...resourceRoutes,
    ...tabRoutes,
    ...detailRoutes,
    { path: '/monitor/agents', component: () => import('@/views/AgentView.vue'), meta: { title: '在线节点' } },
    {
      path: '/monitor/agents/:project/history',
      component: () => import('@/views/AgentHistoryView.vue'),
      meta: { title: '运行历史' },
    },
  ],
})

export default router
