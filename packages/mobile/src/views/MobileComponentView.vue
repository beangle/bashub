<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">{{ row ? artifactTitle(row) : '组件详情' }}</h2>
        <p class="mobile-page__subtitle">{{ row ? artifactCoordinates(row) : '' }}</p>
      </div>
      <router-link class="mobile-back" to="/components">返回组件</router-link>
    </header>

    <MobileNotice v-if="error" :message="error" />
    <MobileNotice v-if="message" theme="success" :message="message" />
    <MobileNotice v-if="catalogError" :message="catalogError" />

    <div v-if="loading && !row" class="mobile-loading">
      <t-loading size="24px" text="加载中" />
    </div>
    <t-empty v-else-if="!row" description="该组件不存在。" />

    <template v-else>
      <section class="mobile-card mobile-component-form">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">基本信息</h3>
          <t-button
            v-if="canEdit && !editing"
            class="mobile-header-action"
            size="small"
            variant="text"
            @click="startEdit"
          >
            修改
          </t-button>
        </header>

        <template v-if="!editing">
          <dl class="mobile-instance-facts">
            <div class="mobile-instance-fact">
              <dt>打包类型</dt>
              <dd>{{ form.packaging || '—' }}</dd>
            </div>
            <div v-if="native" class="mobile-instance-fact">
              <dt>面向平台</dt>
              <dd>{{ archLabel(form.arch) }}</dd>
            </div>
            <div class="mobile-instance-fact">
              <dt>最新版本</dt>
              <dd>{{ form.latestVersion || '—' }}</dd>
            </div>
            <div class="mobile-instance-fact">
              <dt>部署上下文</dt>
              <dd>{{ form.contextPath || '无' }}</dd>
            </div>
            <div v-if="form.projectId" class="mobile-instance-fact">
              <dt>默认项目</dt>
              <dd>{{ projectLabel }}</dd>
            </div>
            <div v-if="!native" class="mobile-instance-fact mobile-instance-fact--wide">
              <dt>运行特征</dt>
              <dd>{{ featureLabel }}</dd>
            </div>
            <div v-if="native && form.classifier" class="mobile-instance-fact">
              <dt>分类器</dt>
              <dd>{{ form.classifier }}</dd>
            </div>
            <div v-if="native && form.exec" class="mobile-instance-fact mobile-instance-fact--wide">
              <dt>可执行文件</dt>
              <dd>{{ form.exec }}</dd>
            </div>
          </dl>
          <p v-if="form.description" class="mobile-component-description">{{ form.description }}</p>
        </template>

        <template v-else>

        <div class="mobile-component-row">
          <span class="mobile-component-row__label">标题</span>
          <input v-model="form.title" class="mobile-component-row__input" type="text" :disabled="!canEdit" />
        </div>
        <div class="mobile-component-row">
          <span class="mobile-component-row__label">artifactId</span>
          <input v-model="form.artifactId" class="mobile-component-row__input" type="text" :disabled="!canEdit" />
        </div>
        <div class="mobile-component-row">
          <span class="mobile-component-row__label">groupId</span>
          <input v-model="form.groupId" class="mobile-component-row__input" type="text" :disabled="!canEdit" />
        </div>
        <div class="mobile-component-row">
          <span class="mobile-component-row__label">打包类型</span>
          <span class="mobile-component-row__value">{{ form.packaging || '—' }}</span>
          <button
            v-if="canEdit"
            type="button"
            class="mobile-component-row__picker"
            aria-label="选择打包类型"
            @click="openSheet('packaging')"
          >
            <ArrowRightIcon class="mobile-component-row__chevron" />
          </button>
        </div>
        <div v-if="native" class="mobile-component-row">
          <span class="mobile-component-row__label">分类器</span>
          <input v-model="form.classifier" class="mobile-component-row__input" type="text" :disabled="!canEdit" />
        </div>
        <div class="mobile-component-row">
          <span class="mobile-component-row__label">最新版本</span>
          <input v-model="form.latestVersion" class="mobile-component-row__input" type="text" :disabled="!canEdit" />
        </div>
        <div class="mobile-component-row">
          <span class="mobile-component-row__label">部署上下文</span>
          <input
            v-model="form.contextPath"
            class="mobile-component-row__input"
            type="text"
            placeholder="/context"
            :disabled="!canEdit"
          />
        </div>
        <div v-if="native" class="mobile-component-row">
          <span class="mobile-component-row__label">面向平台</span>
          <span class="mobile-component-row__value">{{ archLabel(form.arch) }}</span>
          <button
            v-if="canEdit"
            type="button"
            class="mobile-component-row__picker"
            aria-label="选择面向平台"
            @click="openSheet('arch')"
          >
            <ArrowRightIcon class="mobile-component-row__chevron" />
          </button>
        </div>
        <div v-if="native" class="mobile-component-row">
          <span class="mobile-component-row__label">可执行文件</span>
          <input v-model="form.exec" class="mobile-component-row__input" type="text" :disabled="!canEdit" />
        </div>
        <div class="mobile-component-row">
          <span class="mobile-component-row__label">默认项目</span>
          <span class="mobile-component-row__value">{{ projectLabel }}</span>
          <button
            v-if="canEdit"
            type="button"
            class="mobile-component-row__picker"
            aria-label="选择默认项目"
            @click="openSheet('project')"
          >
            <ArrowRightIcon class="mobile-component-row__chevron" />
          </button>
        </div>
        <div v-if="!native" class="mobile-component-row">
          <span class="mobile-component-row__label">需要解析</span>
          <t-switch v-model="form.resolveSupport" :disabled="!canEdit" />
        </div>
        <div v-if="!native" class="mobile-component-row">
          <span class="mobile-component-row__label">JSP</span>
          <t-switch v-model="form.jspSupport" :disabled="!canEdit" />
        </div>
        <div v-if="!native" class="mobile-component-row">
          <span class="mobile-component-row__label">WebSocket</span>
          <t-switch v-model="form.websocketSupport" :disabled="!canEdit" />
        </div>
        <div class="mobile-component-row mobile-component-row--stack">
          <span class="mobile-component-row__label">描述</span>
          <textarea
            v-model="form.description"
            class="mobile-component-row__textarea"
            rows="3"
            :disabled="!canEdit"
          />
        </div>
        </template>
      </section>

      <section v-if="!editing" class="mobile-card">
        <header class="mobile-card__head">
          <h3 class="mobile-card__title">部署情况</h3>
          <t-tag v-if="deployments.length > 0" size="small" variant="light">{{ enabledCount }} 个启用部署</t-tag>
        </header>

        <MobileNotice v-if="deploymentsError" :message="deploymentsError" />
        <t-empty v-else-if="deployments.length === 0" description="尚未在任何 Project 中部署。" />
        <div v-else class="mobile-component-deploy-list">
          <article
            v-for="item in deployments"
            :key="item.id"
            class="mobile-component-deploy"
            role="button"
            tabindex="0"
            @click="openDeployment(item)"
            @keydown.enter="openDeployment(item)"
          >
            <img
              v-if="item.logoUrl && !failedLogos[item.id]"
              class="mobile-component-deploy__logo"
              :src="item.logoUrl"
              :alt="item.projectTitle || item.projectName"
              @error="failedLogos[item.id] = true"
            />
            <span v-else class="mobile-component-deploy__logo mobile-component-deploy__logo--fallback">
              {{ initials(item.projectTitle || item.projectName) }}
            </span>
            <span class="mobile-component-deploy__title">{{ item.projectTitle || item.projectName || '未知项目' }}</span>
            <span v-if="contextMarker(item)" class="mobile-component-deploy__context">{{ contextMarker(item) }}</span>
            <span class="mobile-component-deploy__version">{{ item.version || '—' }}</span>
            <t-tag v-if="!item.enabled" size="small" variant="light" theme="default">停用</t-tag>
          </article>
        </div>
      </section>

      <div v-if="editing" class="mobile-actions mobile-manage-actions">
        <t-button size="small" variant="outline" :disabled="saving" @click="cancelEdit">取消</t-button>
        <t-button size="small" theme="primary" :loading="saving" :disabled="!canSave" @click="save">保存</t-button>
      </div>
      <p v-if="!canEdit" class="mobile-hint">当前账户无变更权限，仅展示。</p>
    </template>

    <t-action-sheet
      v-model:visible="sheetVisible"
      :items="sheetItems"
      cancel-text="取消"
      @selected="onSheetSelected"
    />
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Toast } from 'tdesign-mobile-vue'
import { ArrowRightIcon } from 'tdesign-icons-vue-next'
import MobileNotice from '@/components/MobileNotice.vue'
import { useProjectCatalog } from '@/composables/useProjectCatalog'
import { readCapabilities } from '@/api/manage'
import {
  ARTIFACT_CHECKS,
  loadArtifactDeployments,
  loadArtifactDetail,
  saveArtifact,
} from '@/api/artifacts'
import { type ResourceRow } from '@/api/resource'
import {
  ARCH_OPTIONS,
  PACKAGING_OPTIONS,
  archLabel,
  artifactCoordinates,
  artifactTitle,
  attributesOf,
  buildDeployments,
  defaultComponentForm,
  formError,
  formOf,
  isNativePackaging,
  type ComponentDeployment,
  type ComponentForm,
} from '@/component-model'
import { errorText, initials } from '@/monitor-model'

type SheetKind = '' | 'packaging' | 'arch' | 'project'

const route = useRoute()
const router = useRouter()
const projects = useProjectCatalog()

const id = computed(() => String(route.params.artifact ?? ''))
const catalogError = computed(() => projects.error.value)

const row = ref<ResourceRow | null>(null)
const form = ref<ComponentForm>(defaultComponentForm())
const deployments = ref<ComponentDeployment[]>([])
const deploymentsError = ref('')
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const message = ref('')
const canEdit = ref(false)
const editing = ref(false)
const sheetKind = ref<SheetKind>('')
const failedLogos = ref<Record<string, boolean>>({})

const native = computed(() => isNativePackaging(form.value.packaging))
const canSave = computed(() => canEdit.value && !saving.value)
const enabledCount = computed(() => deployments.value.filter((item) => item.enabled).length)

const projectLabel = computed(() => {
  const found = projects.projects.value.find((item) => item.id === form.value.projectId)
  return found ? `${found.title} · ${found.qualifiedName}` : '无（通用组件）'
})

/** 查看态只列开启的运行特征，避免一行三个「否」。 */
const featureLabel = computed(() => {
  const items = [
    form.value.resolveSupport ? '需要解析' : '',
    form.value.jspSupport ? 'JSP' : '',
    form.value.websocketSupport ? 'WebSocket' : '',
  ].filter(Boolean)
  return items.length > 0 ? items.join(' · ') : '—'
})

const sheetVisible = computed({
  get: () => sheetKind.value !== '',
  set: (value: boolean) => {
    if (!value) sheetKind.value = ''
  },
})

const sheetItems = computed<string[]>(() => {
  if (sheetKind.value === 'packaging') return [...PACKAGING_OPTIONS]
  if (sheetKind.value === 'arch') return ARCH_OPTIONS.map((item) => item.label)
  if (sheetKind.value === 'project') {
    return ['无（通用组件）', ...projects.projects.value.map((item) => `${item.title} · ${item.qualifiedName}`)]
  }
  return []
})

function openSheet(kind: Exclude<SheetKind, ''>): void {
  sheetKind.value = kind
}

function onSheetSelected(_item: unknown, index: number): void {
  if (sheetKind.value === 'packaging') {
    form.value.packaging = PACKAGING_OPTIONS[index] ?? form.value.packaging
  } else if (sheetKind.value === 'arch') {
    form.value.arch = ARCH_OPTIONS[index]?.value ?? form.value.arch
  } else if (sheetKind.value === 'project') {
    form.value.projectId = index === 0 ? '' : projects.projects.value[index - 1]?.id ?? ''
  }
  sheetKind.value = ''
}

function reset(): void {
  if (!row.value) return
  form.value = formOf(row.value)
  message.value = ''
}

function startEdit(): void {
  reset()
  error.value = ''
  editing.value = true
}

function cancelEdit(): void {
  reset()
  editing.value = false
}

async function loadDeployments(): Promise<void> {
  deploymentsError.value = ''
  try {
    const page = await loadArtifactDeployments(id.value)
    deployments.value = buildDeployments(page.rows, page.included)
  } catch (reason) {
    deployments.value = []
    deploymentsError.value = `部署情况加载失败：${errorText(reason)}`
  }
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    await projects.load()
    const [detail, caps] = await Promise.all([
      loadArtifactDetail(id.value),
      readCapabilities([ARTIFACT_CHECKS.edit]).then(
        (value) => ({ ok: true as const, value }),
        () => ({ ok: false as const }),
      ),
    ])
    row.value = detail.row
    canEdit.value = caps.ok && caps.value[ARTIFACT_CHECKS.edit] === true
    form.value = formOf(detail.row)
    await loadDeployments()
  } catch (reason) {
    error.value = `组件加载失败：${errorText(reason)}`
  } finally {
    loading.value = false
  }
}

async function save(): Promise<void> {
  const current = row.value
  if (!current || !canSave.value) return
  const invalid = formError(form.value)
  if (invalid) {
    Toast.error(invalid)
    return
  }
  saving.value = true
  error.value = ''
  message.value = ''
  try {
    await saveArtifact(current.id, attributesOf(form.value), form.value.projectId)
    await load()
    editing.value = false
    message.value = '已保存组件定义。'
  } catch (reason) {
    error.value = `保存失败：${errorText(reason)}`
  } finally {
    saving.value = false
  }
}

/**
 * 部署上下文与组件默认上下文不同时才标注，避免每行重复同一个路径。
 * 返回空串表示一致；不一致但部署没有上下文时标「无上下文」。
 */
function contextMarker(item: ComponentDeployment): string {
  const current = form.value.contextPath.trim()
  const deployed = item.contextPath.trim()
  if (deployed === current) return ''
  return deployed || '无上下文'
}

function openDeployment(item: ComponentDeployment): void {
  if (!item.projectName) return
  void router.push(`/deploy/projects/${encodeURIComponent(item.projectName)}/apps/${encodeURIComponent(item.id)}`)
}

onMounted(() => {
  void projects.load()
  void load()
})
</script>
