<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">项目</h2>
      </div>
      <t-button class="mobile-touch" size="small" variant="outline" :loading="busy" @click="reload">刷新</t-button>
    </header>

    <t-alert v-if="error" theme="error" :message="error" class="mobile-alert" />

    <div class="mobile-summary">
      <div class="mobile-summary__item">
        <strong>{{ onlineProjects }}</strong>
        <span>在线项目</span>
      </div>
      <div class="mobile-summary__item">
        <strong>{{ totalNodes }}</strong>
        <span>在线节点</span>
      </div>
      <div class="mobile-summary__item">
        <strong>{{ totalRunning }}/{{ totalInstances }}</strong>
        <span>运行实例</span>
      </div>
    </div>

    <t-input v-model="keyword" class="mobile-search" placeholder="搜索项目 / 机构" clearable />

    <t-loading :loading="busy" show-overlay>
      <div class="mobile-list">
        <button
          v-for="project in visibleProjects"
          :key="project.id"
          type="button"
          class="mobile-project-card"
          @click="openProject(project)"
        >
          <span class="mobile-project-card__identity">
            <img
              v-if="project.logoUrl && !failedLogos[project.id]"
              class="mobile-project-card__logo"
              :src="project.logoUrl"
              :alt="project.orgTitle"
              @error="failedLogos[project.id] = true"
            />
            <span v-else class="mobile-project-card__logo mobile-project-card__logo--fallback">
              {{ initials(project.title) }}
            </span>
            <span class="mobile-project-card__text">
              <span class="mobile-project-card__title">{{ project.title }}</span>
              <span class="mobile-project-card__meta">{{ project.orgTitle }} · {{ project.qualifiedName }}</span>
            </span>
          </span>
          <span class="mobile-project-card__side">
            <t-tag size="small" variant="light" :theme="projectStatusTheme(project.status)">
              {{ projectStatusLabel(project.status) }}
            </t-tag>
            <span class="mobile-project-card__stats">
              节点 {{ project.nodeCount }} · 实例 {{ project.running }}/{{ project.instanceTotal }}
            </span>
          </span>
        </button>
        <p v-if="!busy && visibleProjects.length === 0" class="mobile-empty">
          {{ keyword ? '没有匹配的项目。' : '暂无 Project。' }}
        </p>
      </div>
    </t-loading>

  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAgentMonitor } from '@/composables/useAgentMonitor'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import {
  compareProjectHealth,
  initials,
  mergeProjects,
  projectStatusLabel,
  projectStatusTheme,
} from '@/monitor-model'

const router = useRouter()
const catalog = useProjectCatalog()
const {
  summaries,
  loading: monitorLoading,
  error: monitorError,
  refresh: refreshMonitor,
} = useAgentMonitor({ project: () => '', mode: 'summary' })

const keyword = ref('')
const failedLogos = reactive<Record<string, boolean>>({})

const mergedProjects = computed(() =>
  mergeProjects(catalog.projects.value, summaries.value).sort(compareProjectHealth),
)
const loading = computed(() => catalog.loading.value || monitorLoading.value)
const busy = computed(() => loading.value)
const error = computed(() => catalog.error.value || monitorError.value)

const visibleProjects = computed(() => {
  const term = keyword.value.trim().toLowerCase()
  if (!term) return mergedProjects.value
  return mergedProjects.value.filter((project) =>
    [project.title, project.qualifiedName, project.orgTitle]
      .some((value) => value.toLowerCase().includes(term)),
  )
})

const onlineProjects = computed(() => mergedProjects.value.filter((project) => project.nodeCount > 0).length)
const totalNodes = computed(() => mergedProjects.value.reduce((sum, project) => sum + project.nodeCount, 0))
const totalRunning = computed(() => mergedProjects.value.reduce((sum, project) => sum + project.running, 0))
const totalInstances = computed(() => mergedProjects.value.reduce((sum, project) => sum + project.instanceTotal, 0))

async function reload(): Promise<void> {
  await Promise.all([catalog.load(true), refreshMonitor()])
}

function openProject(project: { qualifiedName: string }): void {
  void router.push(`/projects/${encodeURIComponent(project.qualifiedName)}`)
}

onMounted(() => {
  void catalog.load()
})
</script>
