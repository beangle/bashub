<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">{{ app?.title || '应用部署' }}</h2>
        <p class="mobile-page__subtitle">{{ projectInfo?.qualifiedName || project }}</p>
      </div>
      <router-link class="mobile-back" :to="projectPath">返回项目</router-link>
    </header>

    <MobileNotice v-if="error" :message="error" />
    <MobileNotice v-if="message" theme="success" :message="message" />
    <MobileNotice v-if="catalogError" :message="catalogError" />

    <div v-if="loading && !app" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>
    <t-empty v-else-if="!app" description="该部署不存在，或已停用。" />

    <template v-else>
      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">部署</h3>
        </header>
        <dl class="mobile-instance-facts">
          <div class="mobile-instance-fact">
            <dt>上下文</dt>
            <dd>{{ app.contextPath || '无' }}</dd>
          </div>
          <div class="mobile-instance-fact">
            <dt>当前版本</dt>
            <dd>{{ app.version || '—' }}</dd>
          </div>
          <div class="mobile-instance-fact">
            <dt>组件最新</dt>
            <dd>{{ versionLatest || '—' }}</dd>
          </div>
        </dl>
      </section>

      <section class="mobile-card mobile-manage-version">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">版本</h3>
          <t-button
            v-if="versionLatest && versionLatest !== version"
            size="small"
            variant="text"
            @click="useLatest"
          >
            用最新
          </t-button>
        </header>
        <t-input v-model="version" label="版本号" placeholder="例如 1.2.3" clearable />
        <div class="mobile-manage-editor__versions">
          <t-button v-if="versionOptions.length > 0" size="small" variant="outline" @click="pickerOpen = true">
            从已发布版本选择
          </t-button>
          <span v-else-if="versionsLoading" class="mobile-hint">正在读取已发布版本…</span>
          <span v-else class="mobile-hint">未读取到已发布版本，可直接输入。</span>
        </div>
      </section>

      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">部署目标</h3>
          <t-button v-if="canEdit && servers.length > 0" size="small" variant="text" @click="targetsOpen = !targetsOpen">
            {{ targetsOpen ? '收起' : '修改' }}
          </t-button>
        </header>

        <p v-if="!targetsOpen" class="mobile-manage-targets__summary">
          已选 {{ targetIds.length }} 个 · {{ selectedTargetNames || '—' }}
        </p>
        <template v-else>
          <div v-if="serversLoading" class="mobile-loading">
            <t-loading size="24px" text="加载服务" />
          </div>
          <t-empty v-else-if="servers.length === 0" description="该项目还没有可部署的服务。" />
          <t-checkbox-group v-else v-model="targetIds" class="mobile-manage-targets">
            <t-checkbox v-for="server in servers" :key="server.id" :value="server.id" :label="server.label" />
          </t-checkbox-group>
        </template>
      </section>

      <div class="mobile-actions mobile-manage-actions">
        <t-button size="medium" variant="outline" :disabled="saving" @click="resetForm">还原</t-button>
        <t-button
          size="medium"
          theme="primary"
          :loading="saving"
          :disabled="!canSave"
          @click="save"
        >
          保存
        </t-button>
      </div>
      <p v-if="!canEdit" class="mobile-hint">当前账户无变更权限，仅展示。</p>
      <p v-else class="mobile-hint">
        只改部署配置并通知在线节点重新拉取，不会重启实例；重启实例后才生效。
      </p>
    </template>

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
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import MobileNotice from '@/components/MobileNotice.vue'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import {
  MANAGE_CHECKS,
  listProjectServers,
  loadManageCatalog,
  readArtifactVersions,
  readCapabilities,
  saveWebapp,
  type ServerOption,
} from '@/api/manage'
import { errorText } from '@/monitor-model'
import { buildApps, type ManageApp } from '@/manage-model'

const route = useRoute()
const catalog = useProjectCatalog()

const project = computed(() => String(route.params.project ?? ''))
const appId = computed(() => String(route.params.app ?? ''))
const projectInfo = computed(() => catalog.projectOf(project.value))
const catalogError = computed(() => catalog.error.value)
const projectPath = computed(() => `/manage/projects/${encodeURIComponent(project.value)}`)

const app = ref<ManageApp | null>(null)
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const message = ref('')

const version = ref('')
const versionOptions = ref<string[]>([])
const versionLatest = ref('')
const versionsLoading = ref(false)
const pickerOpen = ref(false)

const servers = ref<ServerOption[]>([])
const serversLoading = ref(false)
const targetIds = ref<string[]>([])
const targetsOpen = ref(false)

const capabilities = ref<Record<string, boolean>>({})
const canEdit = computed(() => capabilities.value[MANAGE_CHECKS.deployEdit] === true)
const canSave = computed(
  () => canEdit.value && !saving.value && version.value.trim().length > 0 && targetIds.value.length > 0,
)

const pickerColumns = computed(() =>
  versionOptions.value.map((value) => ({
    label:
      value === versionLatest.value ? `${value}（最新）` : value === app.value?.version ? `${value}（当前）` : value,
    value,
  })),
)
const pickerValue = computed<string[]>(() => [version.value || pickerColumns.value[0]?.value || ''])

const selectedTargetNames = computed(() =>
  servers.value
    .filter((server) => targetIds.value.includes(server.id))
    .map((server) => server.label)
    .join('、'),
)

function resetForm(): void {
  const current = app.value
  if (!current) return
  version.value = current.version
  targetIds.value = [...current.targetIds]
  targetsOpen.value = false
  message.value = ''
}

function useLatest(): void {
  if (versionLatest.value) version.value = versionLatest.value
}

function onPickVersion(value: Array<string | number>): void {
  const picked = value?.[0]
  if (picked !== undefined && picked !== null && String(picked).length > 0) version.value = String(picked)
  pickerOpen.value = false
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    await catalog.load()
    const [data, caps, options] = await Promise.all([
      loadManageCatalog(),
      readCapabilities([MANAGE_CHECKS.deployEdit]).then(
        (value) => ({ ok: true as const, value }),
        () => ({ ok: false as const }),
      ),
      listProjectServers(projectInfo.value?.id ?? '').catch(() => [] as ServerOption[]),
    ])
    app.value = buildApps(data.webapps, data.included).find((item) => item.id === appId.value) ?? null
    capabilities.value = caps.ok ? caps.value : {}
    servers.value = options
    resetForm()
    if (app.value) {
      versionLatest.value = app.value.latestVersion
      void loadVersions(app.value)
    }
  } catch (reason) {
    error.value = `部署详情加载失败：${errorText(reason)}`
  } finally {
    loading.value = false
  }
}

/** 读取组件已发布版本；失败只收起候选，不挡手工输入。 */
async function loadVersions(target: ManageApp): Promise<void> {
  versionOptions.value = []
  if (!target.artifactId) return
  versionsLoading.value = true
  try {
    const info = await readArtifactVersions(target.artifactId)
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

async function save(): Promise<void> {
  const current = app.value
  if (!current || !canSave.value) return
  saving.value = true
  error.value = ''
  message.value = ''
  try {
    await saveWebapp(current.id, version.value.trim(), targetIds.value)
    await load()
    message.value = '已保存部署配置；未重启实例，重启后生效。' 
  } catch (reason) {
    error.value = `保存失败：${errorText(reason)}`
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  void catalog.load()
  void load()
})
</script>
