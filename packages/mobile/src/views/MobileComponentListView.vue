<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">组件</h2>
        <p class="mobile-page__subtitle">{{ rows.length }} 个组件</p>
      </div>
      <t-button size="small" variant="outline" :loading="loading" @click="load">刷新</t-button>
    </header>

    <MobileNotice v-if="error" :message="error" />

    <t-search v-model="keyword" placeholder="搜索标题 / groupId / artifactId" shape="round" />

    <div v-if="loading && rows.length === 0" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>
    <t-empty
      v-else-if="entries.length === 0"
      :description="keyword ? '没有匹配的组件。' : '暂无组件。'"
    />
    <div v-else class="mobile-component-list">
      <template v-for="(entry, index) in entries" :key="index">
        <h3 v-if="entry.kind === 'section'" class="mobile-component-list__section">
          {{ entry.label }}<span class="mobile-component-list__count">{{ entry.count }}</span>
        </h3>
        <div v-else-if="entry.kind === 'project'" class="mobile-component-list__project">
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
import { useRouter } from 'vue-router'
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

type ListEntry =
  | { kind: 'section'; label: string; count: number }
  | { kind: 'project'; title: string; logoUrl: string }
  | { kind: 'row'; row: ResourceRow }

const router = useRouter()
const catalog = useProjectCatalog()

const rows = ref<ResourceRow[]>([])
const keyword = ref('')
const loading = ref(false)
const error = ref('')
const failedLogos = ref<Record<string, boolean>>({})

/** 定制组件按项目分组在前、通用组件在后；搜索时同样保留分组，空分组自动消失。 */
const entries = computed<ListEntry[]>(() => {
  const { custom, generic } = groupArtifacts(filterArtifacts(rows.value, keyword.value))
  const projects = catalog.projects.value
  const groups = custom
    .map((group) => {
      const project = projects.find((item) => item.id === group.projectId)
      return { rows: group.rows, title: project?.title || '未知项目', logoUrl: project?.logoUrl || '' }
    })
    .sort((left, right) => left.title.localeCompare(right.title, 'zh-CN'))

  const list: ListEntry[] = []
  const customCount = groups.reduce((sum, group) => sum + group.rows.length, 0)
  if (customCount > 0) list.push({ kind: 'section', label: '定制组件', count: customCount })
  for (const group of groups) {
    list.push({ kind: 'project', title: group.title, logoUrl: group.logoUrl })
    for (const row of group.rows) list.push({ kind: 'row', row })
  }
  if (generic.length > 0) list.push({ kind: 'section', label: '通用组件', count: generic.length })
  for (const row of generic) list.push({ kind: 'row', row })
  return list
})

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
