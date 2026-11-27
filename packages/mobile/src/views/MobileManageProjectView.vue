<template>
  <section class="mobile-page">
    <div class="mobile-page__toolbar">
      <span class="mobile-updated">{{ projectInfo ? projectInfo.qualifiedName : project }}</span>
      <t-button size="small" variant="outline" :loading="busy" @click="reload">刷新</t-button>
    </div>

    <MobileNotice v-if="error" :message="error" />
    <MobileNotice v-if="catalogError" :message="catalogError" />

    <div v-if="busy && !projectInfo" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>
    <t-empty
      v-else-if="!projectInfo"
      :description="catalogError ? '项目目录加载失败。' : `项目 ${project} 不存在或无权访问。`"
    />

    <template v-if="projectInfo">
      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">应用部署</h3>
          <span class="mobile-header-actions">
            <t-button
              v-if="canDeploy"
              class="mobile-header-action"
              size="small"
              variant="text"
              @click="openCreate"
            >
              新增
            </t-button>
          </span>
        </header>

        <t-empty v-if="apps.length === 0" description="该项目还没有部署应用。" />
        <div v-else class="mobile-manage-list">
          <article
            v-for="app in apps"
            :key="app.id"
            class="mobile-manage-app is-tappable"
            role="button"
            tabindex="0"
            @click="openApp(app)"
            @keydown.enter="openApp(app)"
          >
            <div class="mobile-manage-app__text">
              <div class="mobile-manage-app__line">
                <p class="mobile-manage-app__title">{{ app.title }}</p>
                <span class="mobile-manage-app__version">
                  <span>{{ app.version || '—' }}</span>
                  <span v-if="upgradeTarget(app)" class="mobile-manage-app__to">→ {{ upgradeTarget(app) }}</span>
                </span>
              </div>
              <p class="mobile-manage-app__meta">{{ app.contextPath || '无上下文' }}</p>
            </div>
          </article>
        </div>
      </section>

      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">证书</h3>
        </header>
        <t-empty v-if="certs.length === 0" description="该项目没有代理点。" />
        <div v-else class="mobile-manage-list">
          <article v-for="cert in certs" :key="cert.id" class="mobile-manage-cert">
            <div class="mobile-manage-cert__text">
              <p class="mobile-manage-cert__title">
                {{ cert.name }}
                <span class="mobile-manage-cert__engine">{{ cert.engine }}</span>
              </p>
              <p class="mobile-manage-cert__meta">{{ cert.domain || '无域名' }}</p>
            </div>
            <div class="mobile-manage-cert__side">
              <t-tag size="small" variant="light" :theme="certTheme(cert)">
                {{ certLabel(cert) }}
              </t-tag>
              <span v-if="cert.expires" class="mobile-manage-cert__expires">{{ cert.expires }}</span>
            </div>
          </article>
        </div>
      </section>
    </template>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import MobileNotice from '@/components/MobileNotice.vue'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import { MANAGE_CHECKS, loadManageCatalog, readCapabilities } from '@/api/manage'
import type { ResourcePage } from '@/api/resource'
import { errorText } from '@/monitor-model'
import { buildApps, buildCerts, certLabel, certTheme, type ManageApp } from '@/manage-model'

const route = useRoute()
const router = useRouter()
const catalog = useProjectCatalog()

const project = computed(() => String(route.params.project ?? ''))
const projectInfo = computed(() => catalog.projectOf(project.value))
const catalogError = computed(() => catalog.error.value)

const webapps = ref<ResourcePage['rows']>([])
const included = ref<ResourcePage['included']>([])
const endpoints = ref<ResourcePage['rows']>([])
const loading = ref(false)
const error = ref('')
const capabilities = ref<Record<string, boolean>>({})

const busy = computed(() => loading.value || catalog.loading.value)
const allApps = computed(() => buildApps(webapps.value, included.value))
const allCerts = computed(() => buildCerts(endpoints.value))
const apps = computed(() => {
  const id = projectInfo.value?.id
  return id ? allApps.value.filter((app) => app.projectId === id) : []
})
const certs = computed(() => {
  const id = projectInfo.value?.id
  return id ? allCerts.value.filter((cert) => cert.projectId === id) : []
})
/**
 * 可升级时行尾显示「当前 → 目标版本」。后端判可升级但组件最新版本没取到（或与当前版本串相同）时
 * 只显示当前版本，不臆造「最新」。
 */
function upgradeTarget(app: ManageApp): string {
  if (!app.upgradable) return ''
  const latest = app.latestVersion.trim()
  return latest && latest !== app.version.trim() ? latest : ''
}

const canDeploy = computed(() => capabilities.value[MANAGE_CHECKS.deploy] === true)

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    await catalog.load()
    const [data, caps] = await Promise.all([
      loadManageCatalog(),
      readCapabilities([MANAGE_CHECKS.deploy]).then(
        (value) => ({ ok: true as const, value }),
        () => ({ ok: false as const }),
      ),
    ])
    webapps.value = data.webapps
    included.value = data.included
    endpoints.value = data.endpoints
    capabilities.value = caps.ok ? caps.value : {}
  } catch (reason) {
    error.value = `部署数据加载失败：${errorText(reason)}`
  } finally {
    loading.value = false
  }
}

async function reload(): Promise<void> {
  await Promise.all([catalog.load(true), load()])
}

function openCreate(): void {
  void router.push(`/deploy/projects/${encodeURIComponent(project.value)}/new`)
}

function openApp(app: ManageApp): void {
  void router.push(`/deploy/projects/${encodeURIComponent(project.value)}/apps/${encodeURIComponent(app.id)}`)
}

onMounted(() => {
  void load()
})
</script>
