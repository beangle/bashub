<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">管理</h2>
      </div>
      <t-button size="small" variant="outline" :loading="busy" @click="reload">刷新</t-button>
    </header>

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
          <span class="mobile-manage-project__text">
            <span class="mobile-manage-project__title">{{ project.title }}</span>
            <span class="mobile-manage-project__meta">{{ project.qualifiedName }}</span>
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

    <section class="mobile-card">
      <header class="mobile-card__head">
        <h3 class="mobile-card__title">组件版本</h3>
      </header>
      <p class="mobile-hint">从仓库刷新所有组件的最新版本，应用部署升级时按它比较。</p>
      <div class="mobile-actions">
        <t-button
          v-if="canRefresh"
          size="small"
          theme="primary"
          :loading="refreshing"
          :disabled="refreshing"
          @click="confirmRefresh"
        >
          刷新最新版本
        </t-button>
        <p v-else class="mobile-hint">{{ capabilityHint }}</p>
      </div>
    </section>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { DialogPlugin } from 'tdesign-mobile-vue'
import MobileNotice from '@/components/MobileNotice.vue'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import { MANAGE_CHECKS, loadManageCatalog, readCapabilities, refreshArtifactVersions } from '@/api/manage'
import type { ResourcePage } from '@/api/resource'
import { errorText, initials, type ProjectInfo } from '@/monitor-model'
import {
  buildApps,
  buildCerts,
  sortProjectsByPending,
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
const refreshing = ref(false)
const error = ref('')
const message = ref('')
const capabilities = ref<Record<string, boolean>>({})
const capabilityError = ref(false)
const failedLogos = reactive<Record<string, boolean>>({})

const busy = computed(() => loading.value || catalog.loading.value)

const apps = computed(() => buildApps(webapps.value, included.value))
const certs = computed(() => buildCerts(endpoints.value))
const pending = computed(() => summarizeProjects(catalog.projects.value, apps.value, certs.value))
const total = computed(() => totalPending(pending.value))
const projects = computed(() => sortProjectsByPending(catalog.projects.value, pending.value))

const canRefresh = computed(() => capabilities.value[MANAGE_CHECKS.artifacts] === true)
const capabilityHint = computed(() =>
  capabilityError.value ? '无法确认变更权限，已隐藏写操作。' : '当前账户无变更权限，仅展示现状。',
)

function pendingOf(projectId: string): ProjectPending {
  return pending.value[projectId] ?? { apps: 0, upgrades: 0, certificates: 0, expiring: 0 }
}

function score(projectId: string): number {
  const entry = pendingOf(projectId)
  return entry.upgrades + entry.expiring
}

function openProject(project: ProjectInfo): void {
  void router.push(`/manage/projects/${encodeURIComponent(project.qualifiedName)}`)
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    const [data, caps] = await Promise.all([
      loadManageCatalog(),
      readCapabilities([MANAGE_CHECKS.deploy, MANAGE_CHECKS.artifacts]).then(
        (value) => ({ ok: true as const, value }),
        (reason: unknown) => ({ ok: false as const, reason }),
      ),
    ])
    webapps.value = data.webapps
    included.value = data.included
    endpoints.value = data.endpoints
    if (caps.ok) {
      capabilities.value = caps.value
      capabilityError.value = false
    } else {
      capabilities.value = {}
      capabilityError.value = true
    }
  } catch (reason) {
    error.value = `管理数据加载失败：${errorText(reason)}`
  } finally {
    loading.value = false
  }
}

async function reload(): Promise<void> {
  message.value = ''
  await Promise.all([catalog.load(true), load()])
}

function confirmRefresh(): void {
  if (!canRefresh.value || refreshing.value) return
  const dialog = DialogPlugin.confirm({
    title: '刷新组件最新版本',
    content: '将从仓库读取所有组件的最新版本；只更新版本信息，不改任何应用部署。',
    confirmBtn: '确定',
    cancelBtn: '取消',
    onConfirm: () => {
      dialog.destroy()
      void runRefresh()
    },
  })
}

async function runRefresh(): Promise<void> {
  refreshing.value = true
  error.value = ''
  message.value = ''
  try {
    await refreshArtifactVersions()
    message.value = '组件最新版本已刷新。'
    await load()
  } catch (reason) {
    error.value = `刷新失败：${errorText(reason)}`
  } finally {
    refreshing.value = false
  }
}

onMounted(() => {
  void catalog.load()
  void load()
})
</script>
