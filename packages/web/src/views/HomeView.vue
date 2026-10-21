<template>
  <section class="page-panel">
    <div class="page-head">
      <div>
        <h2 class="page-title">BAS 配置中心</h2>
        <p class="page-subtitle">
          后端按 <code>ems</code> / <code>config</code> / <code>micdn</code> / <code>monitor</code>
          分组提供 API，本页由独立部署的 SPA 渲染。
        </p>
      </div>
    </div>

    <div v-for="group in groups" :key="group.name" class="tile-group">
      <h3 class="tile-group-title">{{ group.name }}</h3>
      <div class="tile-grid">
        <router-link v-for="item in group.items" :key="item.title" class="tile" :to="item.to">
          <component :is="item.icon" class="tile-icon" />
          <span class="tile-title">{{ item.title }}</span>
          <span class="tile-desc">{{ item.description }}</span>
        </router-link>
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
import {
  AppIcon,
  ServerIcon,
  SettingIcon,
  UserListIcon,
} from 'tdesign-icons-vue-next'
import type { Component } from 'vue'
import { resourceApiPath } from '@/api/prefix'
import { resourceGroups, resourceSchemas, resourceTabGroups } from '@/resources'

const groupIcons: Record<string, Component> = {
  平台配置: SettingIcon,
  应用与菜单: AppIcon,
  静态资源: UserListIcon,
}

const tabGroupBySchema = new Map(
  resourceTabGroups.flatMap((group) => group.tabs.map((tab) => [tab.key, group])),
)

/** 概览按资源列磁贴，点击落到资源所属页签；从属页面（如服务管理）不出磁贴。 */
const groups = resourceGroups
  .map((name) => ({
    name,
    items: resourceSchemas
      .filter((schema) => schema.group === name && (schema.menu !== false || tabGroupOf(schema.key)))
      .map((schema) => ({
        to: tabGroupOf(schema.key)
          ? { path: tabGroupOf(schema.key)!.path, query: { tab: schema.key } }
          : resourceApiPath(schema.path),
        title: schema.title,
        description: schema.description || '',
        icon: groupIcons[name] || AppIcon,
      })),
  }))
  .filter((group) => group.items.length > 0)

function tabGroupOf(key: string) {
  return tabGroupBySchema.get(key)
}

groups.push({
  name: '运维工具',
  items: [
    {
      to: '/monitor/agents',
      title: '在线节点',
      description: '查看 basctl 上报的系统与实例快照',
      icon: ServerIcon,
    },
  ],
})
</script>

<style scoped>
.tile-group + .tile-group {
  margin-top: 24px;
}

.tile-group-title {
  margin: 0 0 12px;
  color: var(--td-text-color-secondary);
  font-size: 14px;
  font-weight: 600;
}
</style>
