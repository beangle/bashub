<template>
  <section class="mobile-page">
    <MobileNotice v-if="error" :message="error" />

    <div class="mobile-component-tabs">
      <div class="mobile-segmented" role="tablist" aria-label="组件分类">
        <button
          v-for="item in categories"
          :key="item.key"
          type="button"
          role="tab"
          :aria-selected="category === item.key"
          :class="{ 'is-active': category === item.key }"
          @click="chooseCategory(item.key)"
        >
          {{ item.label }}<span class="mobile-component-tabs__count">{{ item.count }}</span>
        </button>
      </div>
    </div>

    <t-search
      v-model="keyword"
      class="mobile-component-search"
      placeholder="搜索标题 / groupId / artifactId"
      shape="round"
    />

    <div v-if="loading && rows.length === 0" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>
    <t-empty
      v-else-if="entries.length === 0"
      :description="keyword ? `没有匹配的${activeLabel}。` : `暂无${activeLabel}。`"
    />
    <div v-else class="mobile-component-list">
      <template v-for="(entry, index) in entries" :key="index">
        <div v-if="entry.kind === 'project'" class="mobile-component-list__project">
          <img
            v-if="entry.logoUrl && !failedLogos[entry.title]"
            class="mobile-component-list__logo"
            :src="entry.logoUrl"
            :alt="entry.title"
            @error="failedLogos[entry.title] = true"
          />
          <span v-else class="mobile-component-list__logo mobile-component-list__logo--fallback">
            {{ initials(entry.title) }}
          </span>
          <span class="mobile-component-list__project-title">{{ entry.title }}</span>
        </div>
        <button v-else type="button" class="mobile-component-item" @click="open(entry.row)">
          <span class="mobile-component-item__text">
            <span class="mobile-component-item__title">{{ artifactTitle(entry.row) }}</span>
            <span class="mobile-component-item__meta">{{ artifactCoordinates(entry.row) }}</span>
          </span>
          <span class="mobile-component-item__version">
            {{ attributeText(entry.row.attributes.latestVersion) || '—' }}
          </span>
        </button>
      </template>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import MobileNotice from '@/components/MobileNotice.vue'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import { loadArtifactCatalog } from '@/api/artifacts'
import { attributeText, type ResourceRow } from '@/api/resource'
import {
  artifactCoordinates,
  artifactTitle,
  filterArtifacts,
  groupArtifacts,
} from '@/component-model'
import { errorText, initials } from '@/monitor-model'

type Category = 'custom' | 'generic'

type ListEntry =
  | { kind: 'project'; title: string; logoUrl: string }
  | { kind: 'row'; row: ResourceRow }

const CATEGORY_KEY = 'bashub.components.category'

const router = useRouter()
const route = useRoute()
const catalog = useProjectCatalog()

const rows = ref<ResourceRow[]>([])
const keyword = ref('')
const loading = ref(false)
const error = ref('')
const failedLogos = ref<Record<string, boolean>>({})

function readSavedCategory(): Category {
  const fromQuery = String(route.query.type ?? '')
  if (fromQuery === 'custom' || fromQuery === 'generic') return fromQuery
  try {
    const saved = window.localStorage.getItem(CATEGORY_KEY)
    if (saved === 'custom' || saved === 'generic') return saved
  } catch {
    // 忽略隐私模式下的 localStorage 失败。
  }
  return 'custom'
}

const category = ref<Category>(readSavedCategory())

const counts = computed(() => {
  const { custom, generic } = groupArtifacts(rows.value)
  return {
    custom: custom.reduce((sum, group) => sum + group.rows.length, 0),
    generic: generic.length,
  }
})

const categories = computed(() => [
  { key: 'custom' as const, label: '定制组件', count: counts.value.custom },
  { key: 'generic' as const, label: '通用组件', count: counts.value.generic },
])

const activeLabel = computed(() => (category.value === 'custom' ? '定制组件' : '通用组件'))

/** 当前分类内搜索；定制组件按项目分组，通用组件平铺。 */
const entries = computed<ListEntry[]>(() => {
  const { custom, generic } = groupArtifacts(filterArtifacts(rows.value, keyword.value))
  if (category.value === 'generic')
    return generic.map((row) => ({ kind: 'row' as const, row }))

  const projects = catalog.projects.value
  const groups = custom
    .map((group) => {
      const project = projects.find((item) => item.id === group.projectId)
      return { rows: group.rows, title: project?.title || '未知项目', logoUrl: project?.logoUrl || '' }
    })
    .sort((left, right) => left.title.localeCompare(right.title, 'zh-CN'))

  const list: ListEntry[] = []
  for (const group of groups) {
    list.push({ kind: 'project', title: group.title, logoUrl: group.logoUrl })
    for (const row of group.rows) list.push({ kind: 'row', row })
  }
  return list
})

function chooseCategory(next: Category): void {
  if (category.value === next) return
  category.value = next
  try {
    window.localStorage.setItem(CATEGORY_KEY, next)
  } catch {
    // 忽略隐私模式下的 localStorage 失败。
  }
  void router.replace({ query: { ...route.query, type: next } })
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    const page = await loadArtifactCatalog()
    rows.value = page.rows
  } catch (reason) {
    error.value = `组件加载失败：${errorText(reason)}`
  } finally {
    loading.value = false
  }
}

function open(row: ResourceRow): void {
  void router.push(`/components/${encodeURIComponent(row.id)}`)
}

onMounted(() => {
  void catalog.load()
  void load()
})
</script>
