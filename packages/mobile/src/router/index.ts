import { createRouter, createWebHistory } from 'vue-router'

/**
 * 独立手机端 SPA 的路由：应用挂在 `/m/bashub/` 下，所以这里用根路径。
 * 项目上下文只由 `:project`（配置 qualifiedName）携带，不读 PC 的全局项目选择。
 */
const router = createRouter({
  history: createWebHistory(import.meta.env.VITE_APP_BASE || import.meta.env.BASE_URL),
  routes: [
    { path: '/', component: () => import('@/views/MobileProjectsView.vue'), meta: { title: '项目' } },
    {
      path: '/projects/:project',
      component: () => import('@/views/MobileOverviewView.vue'),
      meta: { title: '项目概览' },
    },
    {
      path: '/projects/:project/nodes',
      component: () => import('@/views/MobileNodesView.vue'),
      meta: { title: '项目节点' },
    },
    {
      path: '/projects/:project/nodes/:host',
      component: () => import('@/views/MobileNodesView.vue'),
      meta: { title: '主机详情' },
    },
    {
      path: '/projects/:project/instances/:instance',
      component: () => import('@/views/MobileInstanceView.vue'),
      meta: { title: '实例详情' },
    },
    {
      path: '/deploy',
      component: () => import('@/views/MobileManageView.vue'),
      meta: { title: '部署' },
    },
    {
      path: '/deploy/projects/:project',
      component: () => import('@/views/MobileManageProjectView.vue'),
      meta: { title: '项目部署' },
    },
    {
      path: '/deploy/projects/:project/apps/:app',
      component: () => import('@/views/MobileManageAppView.vue'),
      meta: { title: '应用部署' },
    },
    {
      path: '/components',
      component: () => import('@/views/MobileComponentListView.vue'),
      meta: { title: '组件' },
    },
    {
      path: '/components/:artifact',
      component: () => import('@/views/MobileComponentView.vue'),
      meta: { title: '组件详情' },
    },
    { path: '/me', component: () => import('@/views/MobileMeView.vue'), meta: { title: '我的' } },
  ],
})

export default router
