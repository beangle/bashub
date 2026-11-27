<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">{{ artifactTitle || app?.title || '应用部署' }}</h2>
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
          <h3 class="mobile-card__title">组件与访问</h3>
        </header>

        <button type="button" class="mobile-app-field" :disabled="!canEdit" @click="openArtifactPicker">
          <span class="mobile-app-field__label">组件</span>
          <span class="mobile-app-field__text">
            <span class="mobile-app-field__title">{{ artifactTitle || '未选择组件' }}</span>
            <span class="mobile-app-field__meta">{{ artifactName || '—' }}</span>
          </span>
          <ArrowRightIcon v-if="canEdit" class="mobile-app-field__chevron" />
        </button>

        <div class="mobile-app-divider"></div>

        <div class="mobile-app-field">
          <span class="mobile-app-field__label">上下文</span>
          <input
            v-model="contextPath"
            class="mobile-app-field__input"
            type="text"
            placeholder="留空表示后台任务"
            autocapitalize="off"
            autocorrect="off"
            spellcheck="false"
            :disabled="!canEdit"
          />
          <button
            v-if="canEdit && contextPath"
            type="button"
            class="mobile-app-field__clear"
            aria-label="清空上下文"
            @click="contextPath = ''"
          >
            <CloseIcon />
          </button>
        </div>
        <p v-if="contextPathError" class="mobile-hint mobile-hint--error">{{ contextPathError }}</p>

        <div class="mobile-app-field mobile-app-field--plain">
          <span class="mobile-app-field__label">代理点</span>
          <span class="mobile-app-field__value">{{ endpointSummary }}</span>
          <t-button
            v-if="canEdit"
            class="mobile-header-action"
            size="small"
            variant="text"
            @click="endpointsOpen = !endpointsOpen"
          >
            {{ endpointsOpen ? '收起' : '修改' }}
          </t-button>
        </div>
        <div v-if="endpointsOpen" class="mobile-app-picker">
          <t-empty v-if="endpoints.length === 0" description="当前项目还没有代理点，需先在 PC 创建。" />
          <t-checkbox-group v-else v-model="endpointIds" class="mobile-manage-targets">
            <t-checkbox v-for="item in endpoints" :key="item.id" :value="item.id" :label="item.label" />
          </t-checkbox-group>
        </div>
        <p v-if="endpointMissing" class="mobile-hint mobile-hint--error">
          填了上下文就必须选代理点。
        </p>
        <p v-else-if="endpointOrphan" class="mobile-hint mobile-hint--error">
          选了代理点就必须填上下文。
        </p>
      </section>

      <section class="mobile-card mobile-manage-version">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">版本</h3>
          <t-button
            v-if="canEdit && versionLatest && versionLatest !== version"
            class="mobile-header-action"
            size="small"
            variant="text"
            @click="useLatest"
          >
            用最新
          </t-button>
        </header>
        <t-input v-model="version" label="版本号" placeholder="例如 1.2.3" clearable :disabled="!canEdit" />
        <div class="mobile-manage-editor__versions">
          <t-button v-if="versionOptions.length > 0" size="small" variant="outline" @click="pickerOpen = true">
            从已发布版本选择
          </t-button>
          <span v-else-if="versionsLoading" class="mobile-hint">正在读取已发布版本…</span>
          <span v-else class="mobile-hint">未读取到已发布版本，可直接输入。</span>
          <span class="mobile-hint">组件最新 {{ versionLatest || '—' }}</span>
        </div>
      </section>

      <section class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">部署目标</h3>
          <t-button
            v-if="canEdit && servers.length > 0"
            class="mobile-header-action"
            size="small"
            variant="text"
            @click="targetsOpen = !targetsOpen"
          >
            {{ targetsOpen ? '收起' : '修改' }}
          </t-button>
        </header>

        <p v-if="!targetsOpen" class="mobile-manage-targets__summary">
          已选 {{ targetIds.length }} 个 · {{ selectedTargetNames || '—' }}
        </p>
        <template v-else>
          <t-empty v-if="servers.length === 0" description="该项目还没有可部署的服务。" />
          <t-checkbox-group v-else v-model="targetIds" class="mobile-manage-targets">
            <t-checkbox v-for="server in servers" :key="server.id" :value="server.id" :label="server.label" />
          </t-checkbox-group>
        </template>
      </section>

      <div class="mobile-actions mobile-manage-actions">
        <t-button size="small" variant="outline" :disabled="saving" @click="resetForm">还原</t-button>
        <t-button size="small" theme="primary" :loading="saving" :disabled="!canSave" @click="save">
          保存
        </t-button>
      </div>
      <p v-if="!canEdit" class="mobile-hint">当前账户无变更权限，仅展示。</p>
      <p v-else class="mobile-hint">只改配置，不重启实例；重启实例后生效。</p>
    </template>

    <t-popup v-model:visible="artifactOpen" placement="bottom">
      <div class="mobile-artifact-sheet">
        <header class="mobile-artifact-sheet__head">
          <h3 class="mobile-card__title">选择组件</h3>
          <t-button size="small" variant="text" @click="artifactOpen = false">取消</t-button>
        </header>
        <t-search v-model="artifactKeyword" placeholder="搜索标题 / artifactId" shape="round" />
        <div class="mobile-artifact-sheet__body">
          <div v-if="artifactsLoading" class="mobile-loading">
            <t-loading size="24px" text="读取组件目录" />
          </div>
          <MobileNotice v-else-if="artifactsError" :message="artifactsError" />
          <t-empty
            v-else-if="filteredArtifacts.length === 0"
            :description="artifactKeyword ? '没有匹配的组件。' : '组件目录为空。'"
          />
          <div v-else class="mobile-artifact-list">
            <button
              v-for="item in filteredArtifacts"
              :key="item.id"
              type="button"
              class="mobile-artifact-item"
              @click="chooseArtifact(item)"
            >
              <span class="mobile-artifact-item__text">
                <span class="mobile-artifact-item__title">{{ item.title }}</span>
                <span class="mobile-artifact-item__meta">{{ artifactMeta(item) }}</span>
              </span>
              <CheckIcon v-if="item.id === artifactId" class="mobile-artifact-item__check" />
            </button>
          </div>
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
import { ArrowRightIcon, CheckIcon, CloseIcon } from 'tdesign-icons-vue-next'
import MobileNotice from '@/components/MobileNotice.vue'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import {
  MANAGE_CHECKS,
  listArtifacts,
  listProjectServers,
  loadManageCatalog,
  readArtifactVersions,
  readCapabilities,
  saveWebapp,
  type ArtifactOption,
  type EndpointOption,
  type ServerOption,
  type WebappEdit,
} from '@/api/manage'
import { attributeText, relationshipIds, type ResourcePage } from '@/api/resource'
import { errorText } from '@/monitor-model'
import { buildApps, type ManageApp } from '@/manage-model'

const route = useRoute()
const catalog = useProjectCatalog()

const project = computed(() => String(route.params.project ?? ''))
const appId = computed(() => String(route.params.app ?? ''))
const projectInfo = computed(() => catalog.projectOf(project.value))
const catalogError = computed(() => catalog.error.value)
const projectPath = computed(() => `/deploy/projects/${encodeURIComponent(project.value)}`)

const app = ref<ManageApp | null>(null)
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const message = ref('')

const artifactId = ref('')
const artifactTitle = ref('')
const artifactName = ref('')
const artifactOpen = ref(false)
const artifactKeyword = ref('')
const artifacts = ref<ArtifactOption[]>([])
const artifactsLoading = ref(false)
const artifactsError = ref('')

const contextPath = ref('')
const endpointIds = ref<string[]>([])
const endpoints = ref<EndpointOption[]>([])
const endpointsOpen = ref(false)

const version = ref('')
const versionOptions = ref<string[]>([])
const versionLatest = ref('')
const versionsLoading = ref(false)
const pickerOpen = ref(false)

const servers = ref<ServerOption[]>([])
const targetIds = ref<string[]>([])
const targetsOpen = ref(false)

const capabilities = ref<Record<string, boolean>>({})
const canEdit = computed(() => capabilities.value[MANAGE_CHECKS.deployEdit] === true)

const contextPathError = computed(() => {
  const value = contextPath.value.trim()
  if (value.length === 0) return ''
  if (!value.startsWith('/')) return '上下文必须以 / 开头'
  if (/\s/.test(value)) return '上下文不能包含空白'
  return ''
})

/** 上下文非空必须有代理点，否则 `proxy.d` 按 endpoint 过滤后这条部署不会被任何代理路由。 */
const endpointMissing = computed(() => contextPath.value.trim().length > 0 && endpointIds.value.length === 0)
/** 反向也成立：选了代理点却没有上下文，配置在 PC 侧是不合法的。 */
const endpointOrphan = computed(() => contextPath.value.trim().length === 0 && endpointIds.value.length > 0)

const canSave = computed(
  () =>
    canEdit.value &&
    !saving.value &&
    artifactId.value.length > 0 &&
    version.value.trim().length > 0 &&
    targetIds.value.length > 0 &&
    contextPathError.value === '' &&
    !endpointMissing.value &&
    !endpointOrphan.value,
)

const filteredArtifacts = computed(() => {
  const term = artifactKeyword.value.trim().toLowerCase()
  if (!term) return artifacts.value
  return artifacts.value.filter((item) =>
    [item.title, item.artifactName].some((value) => value.toLowerCase().includes(term)),
  )
})

const selectedTargetNames = computed(() =>
  servers.value
    .filter((server) => targetIds.value.includes(server.id))
    .map((server) => server.label)
    .join('、'),
)

const endpointSummary = computed(() => {
  const names = endpointIds.value
    .map((id) => endpoints.value.find((item) => item.id === id)?.label ?? '')
    .filter(Boolean)
  return names.length > 0 ? names.join('、') : '未绑定'
})

const pickerColumns = computed(() =>
  versionOptions.value.map((value) => ({
    label:
      value === versionLatest.value ? `${value}（最新）` : value === app.value?.version ? `${value}（当前）` : value,
    value,
  })),
)
const pickerValue = computed<string[]>(() => [version.value || pickerColumns.value[0]?.value || ''])

// 清空上下文等于把部署改成后台任务，代理点必须跟着清空（与 PC 表单的耦合规则一致）。
// 同步 flush：resetForm 里先写上下文再写代理点，所以加载出来的数据不会被这条规则改写。
watch(
  contextPath,
  (value) => {
    if (value.trim().length === 0 && endpointIds.value.length > 0) endpointIds.value = []
  },
  { flush: 'sync' },
)

function artifactMeta(item: ArtifactOption): string {
  const parts = [item.artifactName, item.contextPath ? `默认上下文 ${item.contextPath}` : '无默认上下文']
  if (item.latestVersion) parts.push(`最新 ${item.latestVersion}`)
  return parts.filter(Boolean).join(' · ')
}

function resetForm(): void {
  const current = app.value
  if (!current) return
  artifactId.value = current.artifactId
  artifactTitle.value = current.title
  artifactName.value = current.artifactName
  contextPath.value = current.contextPath
  endpointIds.value = [...current.endpointIds]
  version.value = current.version
  versionLatest.value = current.latestVersion
  targetIds.value = [...current.targetIds]
  targetsOpen.value = false
  endpointsOpen.value = false
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

async function openArtifactPicker(): Promise<void> {
  if (!canEdit.value) return
  artifactOpen.value = true
  artifactKeyword.value = ''
  if (artifacts.value.length > 0 || artifactsLoading.value) return
  artifactsLoading.value = true
  artifactsError.value = ''
  try {
    artifacts.value = await listArtifacts()
  } catch (reason) {
    artifactsError.value = `组件目录加载失败：${errorText(reason)}`
  } finally {
    artifactsLoading.value = false
  }
}

/**
 * 换组件：与 PC 表单的 `refDefaults` 一致，带出新组件的最新版本与默认上下文；
 * 组件没有默认上下文时保留当前上下文，避免换个组件就把已有路由弄没。
 */
function chooseArtifact(item: ArtifactOption): void {
  artifactOpen.value = false
  if (item.id === artifactId.value) return
  artifactId.value = item.id
  artifactTitle.value = item.title
  artifactName.value = item.artifactName
  versionLatest.value = item.latestVersion
  version.value = item.latestVersion
  if (item.contextPath) contextPath.value = item.contextPath
  void loadVersions(item.id)
}

async function loadVersions(targetArtifactId: string): Promise<void> {
  versionOptions.value = []
  if (!targetArtifactId) return
  versionsLoading.value = true
  try {
    const info = await readArtifactVersions(targetArtifactId)
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

function projectEndpoints(rows: ResourcePage['rows']): EndpointOption[] {
  const id = projectInfo.value?.id
  if (!id) return []
  return rows
    .filter((row) => (relationshipIds(row, 'project')[0] ?? '') === id)
    .map((row) => ({ id: row.id, label: attributeText(row.attributes.name) }))
    .sort((left, right) => left.label.localeCompare(right.label, 'zh-CN'))
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
    endpoints.value = projectEndpoints(data.endpoints)
    resetForm()
    if (app.value) void loadVersions(app.value.artifactId)
  } catch (reason) {
    error.value = `部署详情加载失败：${errorText(reason)}`
  } finally {
    loading.value = false
  }
}

function endpointSignature(ids: string[]): string {
  return [...ids].sort().join(',')
}

/** 只有换组件、改上下文或动代理点才需要确认；只改版本/目标沿用直接保存。 */
function structuralChanged(): boolean {
  const current = app.value
  if (!current) return false
  return (
    artifactId.value !== current.artifactId ||
    contextPath.value.trim() !== current.contextPath ||
    endpointSignature(endpointIds.value) !== endpointSignature(current.endpointIds)
  )
}

function changeSummary(): string {
  const current = app.value
  if (!current) return ''
  const lines: string[] = []
  if (artifactId.value !== current.artifactId) lines.push(`组件 ${current.title} → ${artifactTitle.value}`)
  const nextContext = contextPath.value.trim()
  if (nextContext !== current.contextPath) {
    lines.push(`上下文 ${current.contextPath || '无'} → ${nextContext || '无（后台任务）'}`)
  }
  if (endpointSignature(endpointIds.value) !== endpointSignature(current.endpointIds)) {
    const previous =
      current.endpointIds
        .map((id) => endpoints.value.find((item) => item.id === id)?.label ?? '')
        .filter(Boolean)
        .join('、') || '无'
    lines.push(`代理点 ${previous} → ${endpointSummary.value}`)
  }
  if (version.value.trim() !== current.version) lines.push(`版本 ${current.version || '—'} → ${version.value.trim()}`)
  return lines.join('；')
}

/**
 * 上下文与代理点决定代理路由：改完配置还得让代理节点重新应用 bundle（监控页「重载」），
 * 这一步手机端不做，所以在确认框里点一句。
 */
function proxyNote(current: ManageApp): string {
  const endpointsChanged = endpointSignature(endpointIds.value) !== endpointSignature(current.endpointIds)
  if (!endpointsChanged && contextPath.value.trim() === current.contextPath) return ''
  return '代理配置需在监控页重载后生效。'
}

async function save(): Promise<void> {
  const current = app.value
  if (!current || !canSave.value) return
  const edit: WebappEdit = {
    artifactId: artifactId.value,
    contextPath: contextPath.value.trim(),
    version: version.value.trim(),
    targetIds: [...targetIds.value],
    endpointIds: [...endpointIds.value],
  }
  if (!structuralChanged()) {
    await runSave(edit)
    return
  }
  const dialog = DialogPlugin.confirm({
    title: '确认修改部署',
    content: `${changeSummary()}。只改配置，不重启实例；重启后生效。${proxyNote(current)}`,
    confirmBtn: '确定',
    cancelBtn: '取消',
    onConfirm: () => {
      dialog.destroy()
      void runSave(edit)
    },
  })
}

async function runSave(edit: WebappEdit): Promise<void> {
  const current = app.value
  if (!current || saving.value) return
  saving.value = true
  error.value = ''
  message.value = ''
  try {
    await saveWebapp(current.id, edit)
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
