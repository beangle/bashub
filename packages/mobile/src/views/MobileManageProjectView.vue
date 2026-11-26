<template>
  <section class="mobile-page">
    <div class="mobile-page__toolbar">
      <span class="mobile-updated">{{ projectInfo ? projectInfo.qualifiedName : project }}</span>
      <t-button size="small" variant="outline" :loading="busy" @click="reload">刷新</t-button>
    </div>

    <MobileNotice v-if="error" :message="error" />
    <MobileNotice v-if="message" theme="success" :message="message" />
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
          <t-button
            v-if="canDeploy && upgradable.length > 0"
            size="small"
            variant="text"
            :loading="upgrading"
            :disabled="upgrading"
            @click="confirmUpgradeAll"
          >
            全部升级
          </t-button>
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
              <p class="mobile-manage-app__title">{{ app.title }}</p>
              <p class="mobile-manage-app__meta">{{ app.contextPath || '无上下文' }}</p>
            </div>
            <div class="mobile-manage-app__side">
              <ArrowUpIcon
                v-if="app.upgradable"
                class="mobile-manage-app__arrow"
                title="有可用的新版本"
              />
              <ArrowRightIcon class="mobile-manage-app__chevron" />
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
              <t-tag
                size="small"
                variant="light"
                :theme="cert.daysLeft === null ? 'default' : certAlerted(cert) ? 'danger' : 'success'"
              >
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
import { DialogPlugin } from 'tdesign-mobile-vue'
import { ArrowRightIcon, ArrowUpIcon } from 'tdesign-icons-vue-next'
import MobileNotice from '@/components/MobileNotice.vue'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import { MANAGE_CHECKS, loadManageCatalog, readCapabilities, upgradeWebapps } from '@/api/manage'
import type { ResourcePage } from '@/api/resource'
import { errorText } from '@/monitor-model'
import { buildApps, buildCerts, certAlerted, certLabel, type ManageApp } from '@/manage-model'

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
const upgrading = ref(false)
const error = ref('')
const message = ref('')
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
const upgradable = computed(() => apps.value.filter((app) => app.upgradable))

const canDeploy = computed(() => capabilities.value[MANAGE_CHECKS.deploy] === true)

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    const [data, caps] = await Promise.all([
      loadManageCatalog(),
      readCapabilities([MANAGE_CHECKS.deploy, MANAGE_CHECKS.deployEdit]).then(
        (value) => ({ ok: true as const, value }),
        () => ({ ok: false as const }),
      ),
    ])
    webapps.value = data.webapps
    included.value = data.included
    endpoints.value = data.endpoints
    capabilities.value = caps.ok ? caps.value : {}
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

function openApp(app: ManageApp): void {
  void router.push(`/manage/projects/${encodeURIComponent(project.value)}/apps/${encodeURIComponent(app.id)}`)
}

function confirmUpgradeAll(): void {
  if (!canDeploy.value || upgrading.value) return
  const ids = upgradable.value.map((app) => app.id)
  if (ids.length === 0) return
  const dialog = DialogPlugin.confirm({
    title: '全部升级',
    content: `把该项目 ${ids.length} 个可升级应用的配置版本改为各自组件的最新版本；只更新配置、不重启实例，重启后生效。`,
    confirmBtn: '升级',
    cancelBtn: '取消',
    onConfirm: () => {
      dialog.destroy()
      void runUpgrade(ids, ids.length)
    },
  })
}

async function runUpgrade(ids: string[], count: number): Promise<void> {
  upgrading.value = true
  error.value = ''
  message.value = ''
  try {
    await upgradeWebapps(ids)
    message.value = `已更新 ${count} 个应用的配置版本；未重启实例，重启后生效。`
    await load()
  } catch (reason) {
    error.value = `升级失败：${errorText(reason)}`
  } finally {
    upgrading.value = false
  }
}

onMounted(() => {
  void catalog.load()
  void load()
})
</script>
