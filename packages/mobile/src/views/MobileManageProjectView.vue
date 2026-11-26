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

        <p v-if="!canDeploy" class="mobile-hint">{{ capabilityHint }}</p>
        <t-empty v-if="apps.length === 0" description="该项目还没有部署应用。" />
        <div v-else class="mobile-manage-list">
          <article v-for="app in apps" :key="app.id" class="mobile-manage-app">
            <div class="mobile-manage-app__text">
              <p class="mobile-manage-app__title">{{ app.title }}</p>
              <p class="mobile-manage-app__meta">
                {{ app.contextPath || '无上下文' }} · 目标 {{ app.targets }} · {{ app.enabled ? '启用' : '已停用' }}
              </p>
            </div>
            <div v-if="app.upgradable || canEdit" class="mobile-manage-app__side">
              <t-button v-if="canEdit" size="small" variant="text" :disabled="saving" @click="openEditor(app)">
                编辑
              </t-button>
              <t-button
                v-if="app.upgradable && canDeploy"
                size="small"
                variant="outline"
                :disabled="upgrading"
                @click="confirmUpgrade(app)"
              >
                升级
              </t-button>
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

    <t-popup v-model:visible="editorOpen" placement="bottom" @visible-change="onEditorVisible">
      <div class="mobile-manage-editor">
        <header class="mobile-manage-editor__head">
          <h3 class="mobile-manage-editor__title">{{ editing?.title }}</h3>
          <span class="mobile-manage-editor__meta">{{ editing?.contextPath || '无上下文' }}</span>
        </header>
        <t-input v-model="editVersion" label="版本" placeholder="例如 1.2.3" clearable />
        <div class="mobile-manage-editor__versions">
          <t-button
            v-if="versionOptions.length > 0"
            size="small"
            variant="outline"
            @click="pickerOpen = true"
          >
            从已发布版本选择
          </t-button>
          <span v-else-if="versionsLoading" class="mobile-hint">正在读取已发布版本…</span>
          <span v-else class="mobile-hint">未读取到已发布版本，可直接输入版本号。</span>
          <span v-if="versionLatest" class="mobile-manage-editor__latest">组件最新 {{ versionLatest }}</span>
        </div>
        <p class="mobile-hint">只改配置版本并通知在线节点重新拉取，不会重启实例；重启实例后才生效。</p>
        <div class="mobile-actions">
          <t-button size="small" variant="outline" :disabled="saving" @click="closeEditor">取消</t-button>
          <t-button
            size="small"
            theme="primary"
            :loading="saving"
            :disabled="saving || editVersion.trim().length === 0"
            @click="saveVersion"
          >
            保存
          </t-button>
        </div>
      </div>
    </t-popup>

    <t-popup v-model:visible="pickerOpen" placement="bottom">
      <t-picker
        :columns="pickerColumns"
        :model-value="pickerValue"
        title="选择已发布版本"
        cancel-btn="取消"
        confirm-btn="确定"
        @confirm="onPickVersion"
        @cancel="pickerOpen = false"
      />
    </t-popup>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { DialogPlugin } from 'tdesign-mobile-vue'
import MobileNotice from '@/components/MobileNotice.vue'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import {
  MANAGE_CHECKS,
  editWebappVersion,
  loadManageCatalog,
  readArtifactVersions,
  readCapabilities,
  upgradeWebapps,
} from '@/api/manage'
import type { ResourcePage } from '@/api/resource'
import { errorText } from '@/monitor-model'
import {
  buildApps,
  buildCerts,
  certAlerted,
  certLabel,
  type ManageApp,
} from '@/manage-model'

const route = useRoute()
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
const editorOpen = ref(false)
const editing = ref<ManageApp | null>(null)
const editVersion = ref('')
const saving = ref(false)
const pickerOpen = ref(false)
const versionOptions = ref<string[]>([])
const versionLatest = ref('')
const versionsLoading = ref(false)
const capabilityError = ref(false)

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
const canEdit = computed(() => capabilities.value[MANAGE_CHECKS.deployEdit] === true)
const capabilityHint = computed(() =>
  capabilityError.value ? '无法确认变更权限，已隐藏升级操作。' : '当前账户无变更权限，仅展示现状。',
)

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

function openEditor(app: ManageApp): void {
  if (!canEdit.value || saving.value) return
  editing.value = app
  editVersion.value = app.version
  editorOpen.value = true
  void loadVersions(app)
}

/** 读取组件已发布版本；失败只收起候选，不挡手工输入。 */
async function loadVersions(app: ManageApp): Promise<void> {
  versionOptions.value = []
  versionLatest.value = app.latestVersion
  if (!app.artifactId) return
  versionsLoading.value = true
  try {
    const info = await readArtifactVersions(app.artifactId)
    versionOptions.value = [...new Set(info.versions.map(String).filter(Boolean))].sort((left, right) =>
      right.localeCompare(left, undefined, { numeric: true }),
    )
    if (info.latest) versionLatest.value = String(info.latest)
  } catch {
    versionOptions.value = []
  } finally {
    versionsLoading.value = false
  }
}

const pickerColumns = computed(() =>
  versionOptions.value.map((value) => ({
    label:
      value === versionLatest.value
        ? `${value}（最新）`
        : value === editing.value?.version
          ? `${value}（当前）`
          : value,
    value,
  })),
)

const pickerValue = computed<string[]>(() => {
  const first = pickerColumns.value[0]?.value
  return [editVersion.value || first || '']
})

function onPickVersion(value: Array<string | number>): void {
  const picked = value?.[0]
  if (picked !== undefined && picked !== null && String(picked).length > 0) editVersion.value = String(picked)
  pickerOpen.value = false
}

function closeEditor(): void {
  if (saving.value) return
  editorOpen.value = false
  editing.value = null
}

function onEditorVisible(visible: boolean): void {
  if (!visible && !saving.value) editing.value = null
}

async function saveVersion(): Promise<void> {
  const app = editing.value
  const version = editVersion.value.trim()
  if (!app || !version || saving.value) return
  saving.value = true
  error.value = ''
  message.value = ''
  try {
    await editWebappVersion(app.id, version)
    const title = app.title
    editorOpen.value = false
    editing.value = null
    message.value = `已把「${title}」的版本改为 ${version}；未重启实例，重启后生效。`
    await load()
  } catch (reason) {
    error.value = `版本修改失败：${errorText(reason)}`
  } finally {
    saving.value = false
  }
}

async function reload(): Promise<void> {
  message.value = ''
  await Promise.all([catalog.load(true), load()])
}

function confirmUpgrade(app: ManageApp): void {
  if (!canDeploy.value || upgrading.value) return
  const dialog = DialogPlugin.confirm({
    title: '升级应用',
    content: `把「${app.title}」的配置版本从 ${app.version || '—'} 改为 ${app.latestVersion}；只更新配置、不重启实例，重启后生效。`,
    confirmBtn: '升级',
    cancelBtn: '取消',
    onConfirm: () => {
      dialog.destroy()
      void runUpgrade([app.id], 1)
    },
  })
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

watch(
  () => projectInfo.value?.id,
  (id) => {
    if (!id || loading.value || webapps.value.length > 0) return
    void load()
  },
)

onMounted(() => {
  void catalog.load()
  void load()
})
</script>
