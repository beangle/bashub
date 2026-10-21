<template>
  <section class="page-panel">
    <div class="page-head">
      <div>
        <router-link class="detail-back" :to="listPath">← 返回平台功能</router-link>
        <h2 class="page-title">
          {{ featureName || '平台功能' }}
          <span v-if="featureVersion" class="detail-version">{{ featureVersion }}</span>
        </h2>
      </div>
      <div class="page-actions">
        <template v-if="editingFeature">
          <t-button variant="outline" @click="cancelFeatureEdit">取消</t-button>
          <t-button theme="primary" :loading="savingFeature" @click="submitFeature">保存</t-button>
        </template>
        <t-button v-else variant="outline" :disabled="!feature" @click="startFeatureEdit">修改</t-button>
      </div>
    </div>

    <article class="feature-detail">
      <header v-if="!editingFeature" class="feature-detail__head">
        <img v-if="featureLogo" class="feature-detail__logo" :src="featureLogo" :alt="featureName" />
        <div class="feature-detail__brief">
          <p class="feature-detail__desc">{{ featureDescription || '（暂无描述）' }}</p>
          <p class="feature-detail__deps">
            <span class="feature-detail__deps-label">依赖</span>
            <span v-if="dependencyNames.length === 0" class="feature-detail__muted">—</span>
            <span v-for="name in dependencyNames" :key="name" class="feature-detail__dep">{{ name }}</span>
          </p>
        </div>
      </header>

      <!-- 复用 bui-vue 的紧凑表单规格（.drawer-form / .drawer-form-grid：标签在上、两列栅格、13px 标签）。 -->
      <t-form v-else class="drawer-form" label-align="top" required-mark-position="right">
        <div class="drawer-form-grid">
          <t-form-item label="名称" :rules="[{ required: true, message: '请填写名称' }]">
            <t-input v-model="featureDraft.name" clearable />
          </t-form-item>
          <t-form-item label="版本" :rules="[{ required: true, message: '请填写版本' }]">
            <t-input v-model="featureDraft.version" clearable />
          </t-form-item>
          <t-form-item label="Logo" :rules="[{ required: true, message: '请填写 Logo' }]" class="drawer-form-field-wide">
            <t-input v-model="featureDraft.logo" clearable />
          </t-form-item>
          <t-form-item label="依赖" class="drawer-form-field-wide">
            <t-select
              v-model="featureDraft.dependencies"
              :options="dependencyOptions"
              placeholder="可选择多个功能"
              multiple
              filterable
              clearable
            />
          </t-form-item>
          <t-form-item label="描述" class="drawer-form-field-wide">
            <t-textarea v-model="featureDraft.description" :autosize="{ minRows: 3 }" />
          </t-form-item>
        </div>
      </t-form>

      <section class="script-section">
        <div class="script-section__head">
          <h3 class="script-section__title">脚本<span class="script-section__count">{{ scripts.length }}</span></h3>
          <t-button size="small" theme="primary" :disabled="editingScript !== null" @click="startAddScript">
            <template #icon><AddIcon /></template>
            增加脚本
          </t-button>
        </div>
        <p v-if="items.length === 0" class="script-section__empty">该功能还没有脚本，点「增加脚本」按平台添加。</p>

        <div
          v-for="item in items"
          :key="item.id"
          class="script-item"
          :class="{ 'script-item--editing': editingScript === item.id }"
        >
          <div class="script-item__platform">
            <t-select
              v-if="editingScript === item.id"
              v-model="draft.platform"
              :options="platformOptions"
              placeholder="选择平台"
              filterable
              clearable
            />
            <template v-else>
              <i v-if="item.icon" :class="item.icon"></i>
              <span>{{ item.platformName || '未设置平台' }}</span>
            </template>
          </div>
          <div class="script-item__body">
            <template v-if="editingScript === item.id">
              <t-textarea v-model="draft.scripts" :autosize="{ minRows: 10 }" placeholder="脚本内容" />
              <div class="script-item__buttons">
                <t-button size="small" variant="outline" @click="cancelScriptEdit">取消</t-button>
                <t-button size="small" theme="primary" :loading="savingScript" @click="submitScript(item.id)">保存</t-button>
              </div>
            </template>
            <template v-else>
              <pre class="script-item__content">{{ item.scripts }}</pre>
              <div class="script-item__buttons">
                <t-button size="small" variant="outline" @click="editScript(item.id)">修改</t-button>
                <t-button size="small" variant="outline" theme="danger" @click="removeScript(item.id)">删除</t-button>
              </div>
            </template>
          </div>
        </div>
      </section>
    </article>
  </section>
</template>

<script setup lang="ts">
import { AddIcon } from 'tdesign-icons-vue-next'
import { DialogPlugin, MessagePlugin } from 'tdesign-vue-next'
import { computed, onMounted, reactive, ref } from 'vue'
import { useRoute } from 'vue-router'
import {
  attributeText,
  getResource,
  listResource,
  relationshipIds,
  removeResource,
  saveResource,
  type ResourceRow,
} from '@/api/resource'

/** 后端资源路径与别名（别名即实体简单名，filter 要写成 `别名.属性`）。 */
const FEATURES_PATH = '/platform-features'
const SCRIPTS_PATH = '/platform-feature-scripts'
const PLATFORMS_PATH = '/platforms'
const SCRIPTS_ALIAS = 'platformFeatureScript'
const NEW_SCRIPT_ID = '__new__'

const route = useRoute()
const featureId = String(route.params.id || '')
/** 返回平台功能列表。 */
const listPath = '/config/platform-ops?tab=platform-features'

const feature = ref<ResourceRow>()
const features = ref<ResourceRow[]>([])
const platforms = ref<ResourceRow[]>([])
const scripts = ref<ResourceRow[]>([])

const editingFeature = ref(false)
const savingFeature = ref(false)
const editingScript = ref<string | null>(null)
const savingScript = ref(false)
const draft = reactive({ platform: '', scripts: '' })
const featureDraft = reactive({ name: '', version: '', logo: '', description: '', dependencies: [] as string[] })

const featureName = computed(() => attributeText(feature.value?.attributes.name))
const featureVersion = computed(() => attributeText(feature.value?.attributes.version))
const featureLogo = computed(() => attributeText(feature.value?.attributes.logo))
const featureDescription = computed(() => attributeText(feature.value?.attributes.description))

function featureLabel(row: ResourceRow): string {
  const name = attributeText(row.attributes.name)
  const version = attributeText(row.attributes.version)
  return version ? `${name} ${version}` : name
}

const dependencyNames = computed(() =>
  relationshipIds(feature.value, 'dependencies')
    .map((id) => features.value.find((row) => row.id === id))
    .filter((row): row is ResourceRow => Boolean(row))
    .map(featureLabel)
    .sort(),
)

const dependencyOptions = computed(() =>
  features.value
    .filter((row) => row.id !== featureId)
    .map((row) => ({ label: featureLabel(row), value: row.id })),
)

const platformOptions = computed(() =>
  platforms.value.map((row) => ({ label: attributeText(row.attributes.name), value: row.id })),
)

function platformOf(id: string): ResourceRow | undefined {
  return platforms.value.find((row) => row.id === id)
}

interface ScriptItem {
  id: string
  icon: string
  platformName: string
  scripts: string
}

/** 列表项 = 正在新增的空行（可选）+ 已保存的脚本。 */
const items = computed<ScriptItem[]>(() => {
  const list: ScriptItem[] = editingScript.value === NEW_SCRIPT_ID
    ? [{ id: NEW_SCRIPT_ID, icon: '', platformName: '', scripts: '' }]
    : []
  scripts.value.forEach((row) => {
    const platform = platformOf(relationshipIds(row, 'platform')[0] || '')
    list.push({
      id: row.id,
      icon: attributeText(platform?.attributes.fonticon),
      platformName: attributeText(platform?.attributes.name),
      scripts: attributeText(row.attributes.scripts),
    })
  })
  return list
})

async function loadScripts() {
  const result = await listResource(SCRIPTS_PATH, {
    pageSize: 200,
    filters: { [`${SCRIPTS_ALIAS}.feature.id`]: featureId },
  })
  scripts.value = result.rows
}

async function loadFeature() {
  feature.value = await getResource(FEATURES_PATH, featureId)
}

onMounted(async () => {
  try {
    const [featureRow, featureList, platformList] = await Promise.all([
      getResource(FEATURES_PATH, featureId),
      listResource(FEATURES_PATH, { pageSize: 300, sort: 'name' }),
      listResource(PLATFORMS_PATH, { pageSize: 300, sort: 'name' }),
    ])
    feature.value = featureRow
    features.value = featureList.rows
    platforms.value = platformList.rows
    await loadScripts()
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '加载平台功能失败')
  }
})

function startFeatureEdit() {
  const attributes = feature.value?.attributes || {}
  featureDraft.name = attributeText(attributes.name)
  featureDraft.version = attributeText(attributes.version)
  featureDraft.logo = attributeText(attributes.logo)
  featureDraft.description = attributeText(attributes.description)
  featureDraft.dependencies = relationshipIds(feature.value, 'dependencies')
  editingFeature.value = true
}

function cancelFeatureEdit() {
  editingFeature.value = false
}

async function submitFeature() {
  if (!featureDraft.name.trim() || !featureDraft.version.trim() || !featureDraft.logo.trim()) {
    MessagePlugin.warning('名称、版本与 Logo 不能为空')
    return
  }
  savingFeature.value = true
  try {
    await saveResource(
      FEATURES_PATH,
      'platformFeatures',
      {
        name: featureDraft.name.trim(),
        version: featureDraft.version.trim(),
        logo: featureDraft.logo.trim(),
        description: featureDraft.description,
      },
      { dependencies: { data: featureDraft.dependencies.map((id) => ({ type: 'platformFeatures', id })) } },
      featureId,
    )
    editingFeature.value = false
    await loadFeature()
    MessagePlugin.success('已保存')
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '保存失败')
  } finally {
    savingFeature.value = false
  }
}

function startAddScript() {
  editingScript.value = NEW_SCRIPT_ID
  draft.platform = ''
  draft.scripts = ''
}

function editScript(id: string) {
  const row = scripts.value.find((candidate) => candidate.id === id)
  if (!row) return
  editingScript.value = id
  draft.platform = relationshipIds(row, 'platform')[0] || ''
  draft.scripts = attributeText(row.attributes.scripts)
}

function cancelScriptEdit() {
  editingScript.value = null
  draft.platform = ''
  draft.scripts = ''
}

async function submitScript(id: string) {
  if (!draft.platform) {
    MessagePlugin.warning('请选择平台')
    return
  }
  if (!draft.scripts.trim()) {
    MessagePlugin.warning('脚本内容不能为空')
    return
  }
  savingScript.value = true
  try {
    await saveResource(
      SCRIPTS_PATH,
      'platformFeatureScripts',
      { scripts: draft.scripts },
      {
        platform: { data: { type: 'platforms', id: draft.platform } },
        feature: { data: { type: 'platformFeatures', id: featureId } },
      },
      id === NEW_SCRIPT_ID ? undefined : id,
    )
    cancelScriptEdit()
    await loadScripts()
    MessagePlugin.success('已保存')
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '保存失败')
  } finally {
    savingScript.value = false
  }
}

function removeScript(id: string) {
  const row = scripts.value.find((candidate) => candidate.id === id)
  const platform = platformOf(relationshipIds(row, 'platform')[0] || '')
  const dialog = DialogPlugin.confirm({
    header: '删除确认',
    body: `确定删除${attributeText(platform?.attributes.name)}平台的脚本？`,
    onConfirm: async () => {
      try {
        await removeResource(SCRIPTS_PATH, id)
        MessagePlugin.success('删除成功')
        dialog.destroy()
        if (editingScript.value === id) cancelScriptEdit()
        await loadScripts()
      } catch (error) {
        MessagePlugin.error(error instanceof Error ? error.message : '删除失败')
      }
    },
  })
}
</script>

<style scoped>
.detail-back {
  display: inline-block;
  margin-bottom: 4px;
  color: var(--td-text-color-secondary);
  font-size: 13px;
}

.detail-back:hover {
  color: var(--td-brand-color);
}

.detail-version {
  margin-left: 8px;
  color: var(--td-text-color-secondary);
  font-size: 14px;
  font-weight: 400;
}

.feature-detail {
  display: grid;
  gap: 16px;
}

.feature-detail__head {
  display: flex;
  gap: 16px;
  padding: 12px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 6px;
  background: var(--td-bg-color-container);
}

.feature-detail__logo {
  width: 72px;
  height: 72px;
  object-fit: contain;
}

.feature-detail__brief {
  min-width: 0;
}

.feature-detail__desc {
  margin: 0 0 8px;
  color: var(--td-text-color-primary);
  font-size: 13px;
  line-height: 1.6;
  white-space: pre-wrap;
}

.feature-detail__deps {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  margin: 0;
  font-size: 13px;
}

.feature-detail__deps-label,
.feature-detail__muted {
  color: var(--td-text-color-secondary);
}

.feature-detail__dep {
  padding: 1px 8px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 10px;
  background: var(--td-bg-color-container-hover);
  color: var(--td-text-color-secondary);
}

.script-section {
  border: 1px solid var(--td-component-stroke);
  border-radius: 6px;
  background: var(--td-bg-color-container);
}

.script-section__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 12px;
  border-bottom: 1px solid var(--td-component-stroke);
}

.script-section__title {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}

.script-section__count {
  margin-left: 6px;
  color: var(--td-text-color-secondary);
  font-weight: 400;
}

.script-section__empty {
  margin: 0;
  padding: 16px 12px;
  color: var(--td-text-color-placeholder);
  font-size: 13px;
}

.script-item {
  display: grid;
  grid-template-columns: 170px minmax(0, 1fr);
  /* 平台名与脚本首行齐平（与原 info.ftl 的左列平台 + 右列脚本一致）。 */
  align-items: start;
  border-bottom: 1px solid var(--td-component-stroke);
}

.script-item:last-child {
  border-bottom: none;
}

.script-item--editing {
  background: var(--td-bg-color-container-hover);
}

.script-item__platform {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 10px 12px;
  border-right: 1px solid var(--td-component-stroke);
  color: var(--td-text-color-primary);
  font-size: 13px;
}

.script-item__body {
  display: grid;
  gap: 6px;
  min-width: 0;
  padding: 10px 12px;
}

.script-item__content {
  max-height: 320px;
  margin: 0;
  overflow: auto;
  color: var(--td-text-color-primary);
  font-family: var(--td-font-family-mono, ui-monospace, SFMono-Regular, Menlo, monospace);
  font-size: 12px;
  line-height: 1.6;
  white-space: pre-wrap;
  word-break: break-all;
}

.script-item__buttons {
  display: flex;
  gap: 8px;
  justify-content: flex-end;
}

@media (max-width: 980px) {
  .script-item {
    grid-template-columns: 1fr;
  }

  .script-item__platform {
    border-right: none;
    border-bottom: 1px solid var(--td-component-stroke);
  }
}
</style>
