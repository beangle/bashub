<template>
  <section class="mobile-page">
    <MobileNotice v-if="error" :message="error" />
    <MobileNotice v-if="message" theme="success" :message="message" />

    <t-grid :column="2" :border="false" class="mobile-stat-grid">
      <t-grid-item>
        <template #text><strong :class="{ 'is-danger': total.upgrades > 0 }">{{ total.upgrades }}</strong></template>
        <template #description>待升级应用</template>
      </t-grid-item>
      <t-grid-item>
        <template #text><strong :class="{ 'is-danger': total.expiring > 0 }">{{ total.expiring }}</strong></template>
        <template #description>证书将到期</template>
      </t-grid-item>
    </t-grid>

    <div v-if="busy && projects.length === 0" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>
    <t-empty v-else-if="projects.length === 0" description="暂无 Project。" />
    <div v-else class="mobile-list">
      <button
        v-for="project in projects"
        :key="project.id"
        type="button"
        class="mobile-manage-project"
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
            <span class="mobile-project-card__title-row">
              <span class="mobile-project-card__title">{{ project.title }}</span>
              <span class="mobile-project-card__qualified">{{ project.qualifiedName }}</span>
            </span>
            <span class="mobile-project-card__meta">{{ project.orgTitle }}</span>
          </span>
        </span>
        <span class="mobile-manage-project__badges">
          <t-tag v-if="pendingOf(project.id).upgrades > 0" size="small" variant="light" theme="warning">
            {{ pendingOf(project.id).upgrades }} 待升级
          </t-tag>
          <t-tag v-if="pendingOf(project.id).expiring > 0" size="small" variant="light" theme="danger">
            {{ pendingOf(project.id).expiring }} 证书
          </t-tag>
          <t-tag v-if="score(project.id) === 0" size="small" variant="light" theme="success">正常</t-tag>
        </span>
      </button>
    </div>

  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import MobileNotice from '@/components/MobileNotice.vue'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import { loadManageCatalog } from '@/api/manage'
import type { ResourcePage } from '@/api/resource'
import { errorText, initials, type ProjectInfo } from '@/monitor-model'
import {
  buildApps,
  buildCerts,
  sortProjects,
  summarizeProjects,
  totalPending,
  type ProjectPending,
} from '@/manage-model'

const router = useRouter()
const catalog = useProjectCatalog()

const webapps = ref<ResourcePage['rows']>([])
const included = ref<ResourcePage['included']>([])
const endpoints = ref<ResourcePage['rows']>([])
const loading = ref(false)
const error = ref('')
const message = ref('')
const failedLogos = reactive<Record<string, boolean>>({})

const busy = computed(() => loading.value || catalog.loading.value)

const apps = computed(() => buildApps(webapps.value, included.value))
const certs = computed(() => buildCerts(endpoints.value))
const pending = computed(() => summarizeProjects(catalog.projects.value, apps.value, certs.value))
const total = computed(() => totalPending(pending.value))
const projects = computed(() => sortProjects(catalog.projects.value))

function pendingOf(projectId: string): ProjectPending {
  return pending.value[projectId] ?? { apps: 0, upgrades: 0, certificates: 0, expiring: 0 }
}

function score(projectId: string): number {
  const entry = pendingOf(projectId)
  return entry.upgrades + entry.expiring
}

function openProject(project: ProjectInfo): void {
  void router.push(`/deploy/projects/${encodeURIComponent(project.qualifiedName)}`)
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    const data = await loadManageCatalog()
    webapps.value = data.webapps
    included.value = data.included
    endpoints.value = data.endpoints
  } catch (reason) {
    error.value = `部署数据加载失败：${errorText(reason)}`
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  void catalog.load()
  void load()
})
</script>
