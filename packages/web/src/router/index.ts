import { createRouter, createWebHistory, type RouteLocation } from 'vue-router'
import { getSchema, resourceSchemas, resourceTabGroups } from '@/resources'

/** 被页签组收录的资源由 `?tab=` 重定向接管；其余资源（含 `menu: false` 的从属页面，如 /servers）都注册路由。 */
const tabSchemaKeys = new Set(resourceTabGroups.flatMap((group) => group.tabs.map((tab) => tab.key)))

const resourceRoutes = resourceSchemas
  .filter((schema) => !tabSchemaKeys.has(schema.key))
  .map((schema) => ({
    path: schema.path,
    component: () => import('@/views/ResourceListView.vue'),
    props: { schemaKey: schema.key },
    meta: { title: schema.title },
  }))

/** 页签合成页：/org-config?tab=<资源 key>。 */
const tabRoutes = resourceTabGroups.map((group) => ({
  path: group.path,
  component: () => import('@/views/ResourceTabsView.vue'),
  props: { groupKey: group.key },
  meta: { title: group.title },
}))

/** 被合成页收录的资源保留旧路径可访问：重定向到各自页签，原有查询条件（如 `?app=<id>&action=export`）一并带上。 */
const tabRedirects = resourceTabGroups.flatMap((group) =>
  group.tabs.map((tab) => ({
    path: getSchema(tab.key).path,
    redirect: (to: RouteLocation) => ({
      path: group.path,
      query: { ...to.query, tab: tab.key },
    }),
  })),
)

/** 平台功能详情页（脚本就地维护，卡片墙由 `schema.cardLink` 指过来）。 */
const detailRoutes = [
  {
    path: '/platform-features/:id',
    component: () => import('@/views/PlatformFeatureDetailView.vue'),
    meta: { title: '平台功能' },
  },
  {
    path: '/hosts/:id',
    component: () => import('@/views/HostDetailView.vue'),
    meta: { title: '主机详情' },
  },
  {
    path: '/profiles/:id',
    component: () => import('@/views/ProfileDetailView.vue'),
    meta: { title: '配置详情' },
  },
  {
    path: '/profiles/:id/micdn',
    component: () => import('@/views/MicdnProfileView.vue'),
    meta: { title: 'Micdn 配置' },
  },
  {
    path: '/cdn-components',
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
    ...tabRedirects,
    ...detailRoutes,
    { path: '/agents', component: () => import('@/views/AgentView.vue'), meta: { title: '在线节点' } },
  ],
})

export default router
