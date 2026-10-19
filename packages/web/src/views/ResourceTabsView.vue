<template>
  <ResourceListView
    :key="activeTab"
    v-model:active-tab="activeTab"
    :schema-key="activeTab"
    :tabs="tabs"
  />
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import type { UnderlineTabItem } from '@beangle/bui-vue'
import ResourceListView from '@/views/ResourceListView.vue'
import { getTabGroup } from '@/resources'

const props = defineProps<{ groupKey: string }>()

const group = getTabGroup(props.groupKey)
const tabs: UnderlineTabItem[] = group.tabs.map((tab) => ({ value: tab.key, label: tab.label }))
const defaultTab = group.tabs[0]?.key || ''

const route = useRoute()
const router = useRouter()

/** URL 上的 ?tab= 是唯一状态源：刷新/收藏/前进后退都能落到同一个页签。 */
function tabFromRoute(): string | undefined {
  const value = route.query.tab
  const key = Array.isArray(value) ? value[0] : value
  return key && group.tabs.some((tab) => tab.key === key) ? key : undefined
}

const activeTab = ref(tabFromRoute() || defaultTab)

watch(activeTab, (value) => {
  if (tabFromRoute() === value) return
  router.replace({ path: group.path, query: { ...route.query, tab: value } })
})

watch(
  () => route.query.tab,
  () => {
    const next = tabFromRoute()
    if (next && next !== activeTab.value) activeTab.value = next
  },
)
</script>
