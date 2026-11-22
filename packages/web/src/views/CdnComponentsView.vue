<template>
  <section class="page-panel">
    <div class="page-head">
      <div class="title-row">
        <h2 class="page-title">Micdn 组件目录</h2>
        <p class="page-subtitle">可复用的静态包和文档</p>
      </div>
    </div>

    <UnderlineTabs
      class="catalog-tabs"
      :tabs="tabs"
      :model-value="activeTab"
      @update:model-value="activeTab = $event as CatalogTab"
    />

    <section v-if="activeTab === 'static_bundle'" class="catalog-card">
      <header class="catalog-card__head">
        <div>
          <h3>静态包</h3>
          <p>可复用的 jar / npm / dir 静态资源</p>
        </div>
        <div class="catalog-tools">
          <t-input v-model="staticQuery" clearable placeholder="查询名称 / 挂载名" class="catalog-search" />
          <t-button theme="primary" @click="openCreate('static_bundle')">
            <template #icon><AddIcon /></template>
            新建静态包
          </t-button>
        </div>
      </header>
      <t-loading :loading="loading" show-overlay>
        <div v-if="staticComponents.length === 0 && !loading" class="catalog-empty">
          {{ staticQuery ? '没有匹配的静态包。' : '还没有静态包。创建后可被任意 Project 引用。' }}
        </div>
        <table v-else class="component-table">
          <thead>
            <tr>
              <th class="component-table__index">序号</th>
              <th>名称</th>
              <th>版本</th>
              <th>挂载名</th>
              <th>说明</th>
              <th>规格</th>
              <th class="component-table__action">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(component, index) in staticComponents" :key="component.id">
              <td class="component-table__index">{{ index + 1 }}</td>
              <td><router-link class="component-link" :to="`/micdn/components/${component.id}`">{{ component.name }}</router-link></td>
              <td><code class="component-table__version">{{ componentVersion(component) || '—' }}</code></td>
              <td><code class="component-table__mount">{{ component.mountName }}</code></td>
              <td class="component-table__muted">{{ component.remark || '—' }}</td>
              <td><code class="component-table__spec">{{ specSummary(component) }}</code></td>
              <td class="component-table__action">
                <t-button size="small" variant="text" theme="primary" @click="openEdit(component)">编辑</t-button>
                <t-button size="small" variant="text" theme="danger" @click="remove(component)">删除</t-button>
              </td>
            </tr>
          </tbody>
        </table>
      </t-loading>
    </section>

    <section v-else class="catalog-card">
      <header class="catalog-card__head">
        <div>
          <h3>文档</h3>
          <p>可复用的 npm 包或 zip 文档</p>
        </div>
        <div class="catalog-tools">
          <t-input v-model="docQuery" clearable placeholder="查询名称 / 挂载名" class="catalog-search" />
          <t-button theme="primary" @click="openCreate('www_doc')">
            <template #icon><AddIcon /></template>
            新建文档
          </t-button>
        </div>
      </header>
      <t-loading :loading="loading" show-overlay>
        <div v-if="docComponents.length === 0 && !loading" class="catalog-empty">
          {{ docQuery ? '没有匹配的文档。' : '还没有文档组件。创建后可被任意 Project 引用。' }}
        </div>
        <table v-else class="component-table">
          <thead>
            <tr>
              <th class="component-table__index">序号</th>
              <th>名称</th>
              <th>版本</th>
              <th>挂载名</th>
              <th>说明</th>
              <th>规格</th>
              <th class="component-table__action">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(component, index) in docComponents" :key="component.id">
              <td class="component-table__index">{{ index + 1 }}</td>
              <td><router-link class="component-link" :to="`/micdn/components/${component.id}`">{{ component.name }}</router-link></td>
              <td><code class="component-table__version">{{ componentVersion(component) || '—' }}</code></td>
              <td><code class="component-table__mount">{{ component.mountName }}</code></td>
              <td class="component-table__muted">{{ component.remark || '—' }}</td>
              <td><code class="component-table__spec">{{ specSummary(component) }}</code></td>
              <td class="component-table__action">
                <t-button size="small" variant="text" theme="primary" @click="openEdit(component)">编辑</t-button>
                <t-button size="small" variant="text" theme="danger" @click="remove(component)">删除</t-button>
              </td>
            </tr>
          </tbody>
        </table>
      </t-loading>
    </section>

    <t-drawer v-model:visible="drawerVisible" :header="draft.id ? '编辑组件' : '新建组件'" size="760px">
      <div class="component-form">
        <div class="form-grid">
          <label class="form-field">
            <span>类型</span>
            <t-select v-model="draft.kind" :options="kindOptions" @change="onKindChange" />
          </label>
          <label class="form-field">
            <span>名称</span>
            <t-input v-model="draft.name" placeholder="组件名称" />
          </label>
          <label class="form-field">
            <span>{{ mountLabel(draft.kind) }}</span>
            <t-input v-model="draft.mountName" :placeholder="mountPlaceholder(draft.kind)" />
          </label>
          <label class="form-field">
            <span>说明</span>
            <t-input v-model="draft.remark" placeholder="可选" />
          </label>
        </div>

        <section v-if="draft.kind === 'static_bundle'" class="spec-section">
          <header>
            <div>
              <h3>静态包来源</h3>
              <p>一个 bundle 可以有多个 jar/npm，或一个 dir；挂载名在上方设置。</p>
            </div>
            <t-button size="small" variant="outline" @click="addSource">添加来源</t-button>
          </header>
          <div v-for="(source, index) in draft.sources" :key="index" class="source-row">
            <t-select v-model="source.kind" :options="staticSourceKindOptions" class="source-row__kind" @change="normalizeSource(source)" />
            <t-input v-model="source.ref" :placeholder="refPlaceholder(source.kind)" class="source-row__ref" />
            <t-input
              v-model="source.inner"
              :disabled="source.kind === 'dir'"
              :placeholder="source.kind === 'dir' ? 'dir 无 inner' : innerPlaceholder(source.kind)"
              class="source-row__inner"
            />
            <t-button class="source-row__action" size="small" variant="text" theme="danger" @click="draft.sources.splice(index, 1)">移除</t-button>
          </div>
        </section>

        <section v-else-if="draft.kind === 'www_doc'" class="spec-section">
          <header>
            <div>
              <h3>文档来源</h3>
              <p>支持 npm 包或 zip；npm 默认读取 dist 目录。</p>
            </div>
          </header>
          <div class="form-grid form-grid--inner">
            <label class="form-field">
              <span>来源类型</span>
              <t-select v-model="draft.source.kind" :options="wwwSourceKindOptions" @change="normalizeWwwSource" />
            </label>
            <label class="form-field">
              <span>来源</span>
              <t-input v-model="draft.source.ref" :placeholder="refPlaceholder(draft.source.kind)" />
            </label>
            <label class="form-field">
              <span>包内目录</span>
              <t-input v-model="draft.source.inner" placeholder="npm 默认 dist；zip 可留空" />
            </label>
            <label class="form-field">
              <span>默认页</span>
              <t-input v-model="draft.tryFile" placeholder="index.html" />
            </label>
            <div class="form-field form-field--switch form-field--switch-wide">
              <span>自动部署</span>
              <t-switch v-model="draft.autoDeploy" :disabled="draft.source.kind !== 'zip'" />
              <p class="form-hint">
                监听 zip 源文件变化，自动重新部署并重建索引；仅 zip 来源支持。
              </p>
            </div>
            <div class="form-field form-field--switch">
              <span>自动 gzip</span>
              <t-switch v-model="draft.autoGzip" />
            </div>
          </div>
        </section>

      </div>
      <template #footer>
        <div class="drawer-actions">
          <t-button variant="outline" :disabled="saving" @click="drawerVisible = false">取消</t-button>
          <t-button theme="primary" :loading="saving" @click="submit">保存</t-button>
        </div>
      </template>
    </t-drawer>
  </section>
</template>

<script setup lang="ts">
import { UnderlineTabs, type UnderlineTabItem } from '@beangle/bui-vue'
import { AddIcon } from 'tdesign-icons-vue-next'
import { DialogPlugin, MessagePlugin } from 'tdesign-vue-next'
import { computed, onMounted, reactive, ref } from 'vue'
import {
  createCdnComponent,
  deleteCdnComponent,
  listCdnComponents,
  updateCdnComponent,
  type CdnComponent,
  type CdnComponentInput,
  type MicdnComponentKind,
  type MicdnComponentSpec,
  type MicdnSource,
  type MicdnSourceKind,
  type StaticBundleSpec,
  type WwwDocSpec,
} from '@/api/micdn'

type CatalogTab = 'static_bundle' | 'www_doc'
const activeTab = ref<CatalogTab>('static_bundle')
const tabs: UnderlineTabItem[] = [
  { value: 'static_bundle', label: '静态包' },
  { value: 'www_doc', label: '文档' },
]

const kindOptions = [
  { value: 'static_bundle', label: '静态包 static_bundle' },
  { value: 'www_doc', label: '文档 www_doc' },
]
const staticSourceKindOptions = [
  { value: 'jar', label: 'jar' },
  { value: 'npm', label: 'npm' },
  { value: 'dir', label: 'dir' },
]
const wwwSourceKindOptions = [
  { value: 'npm', label: 'npm' },
  { value: 'zip', label: 'zip' },
]

interface DraftSource {
  kind: MicdnSourceKind
  ref: string
  inner: string
}

const draft = reactive({
  id: '',
  kind: 'static_bundle' as MicdnComponentKind,
  name: '',
  mountName: '',
  remark: '',
  sources: [] as DraftSource[],
  source: { kind: 'npm', ref: '', inner: '' } as DraftSource,
  tryFile: 'index.html',
  autoDeploy: false,
  autoGzip: true,
})

const components = ref<CdnComponent[]>([])
const staticQuery = ref('')
const docQuery = ref('')
const loading = ref(false)
const saving = ref(false)
const drawerVisible = ref(false)

const staticComponents = computed(() => filterComponents('static_bundle', staticQuery.value))
const docComponents = computed(() => filterComponents('www_doc', docQuery.value))

function filterComponents(kind: MicdnComponentKind, query: string): CdnComponent[] {
  const needle = query.trim().toLowerCase()
  return components.value
    .filter((component) => component.kind === kind)
    .filter((component) => !needle
      || component.name.toLowerCase().includes(needle)
      || component.mountName.toLowerCase().includes(needle)
      || (component.remark || '').toLowerCase().includes(needle))
}

async function load() {
  loading.value = true
  try {
    components.value = await listCdnComponents()
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '加载组件目录失败')
  } finally {
    loading.value = false
  }
}

function openCreate(kind: MicdnComponentKind) {
  Object.assign(draft, {
    id: '',
    kind,
    name: '',
    mountName: '',
    remark: '',
    sources: [newSource('jar')],
    source: newSource('npm'),
    tryFile: 'index.html',
    autoDeploy: false,
    autoGzip: true,
  })
  drawerVisible.value = true
}

function openEdit(component: CdnComponent) {
  Object.assign(draft, {
    id: component.id,
    kind: component.kind,
    name: component.name,
    mountName: component.mountName,
    remark: component.remark || '',
    sources: [],
    source: newSource('npm'),
    tryFile: 'index.html',
    autoDeploy: false,
    autoGzip: true,
  })
  if (component.kind === 'static_bundle') {
    const spec = component.spec as StaticBundleSpec
    draft.sources = (spec.sources || []).map((source) => ({ ...source }))
  } else if (component.kind === 'www_doc') {
    const spec = component.spec as WwwDocSpec
    draft.source = { ...spec.source }
    draft.tryFile = spec.tryFile || 'index.html'
    draft.autoDeploy = Boolean(spec.autoDeploy)
    draft.autoGzip = spec.autoGzip !== false
  }
  drawerVisible.value = true
}

function newSource(kind: MicdnSourceKind): DraftSource {
  return { kind, ref: '', inner: '' }
}

function onKindChange() {
  if (draft.kind === 'static_bundle' && draft.sources.length === 0) draft.sources = [newSource('jar')]
  if (draft.kind === 'www_doc' && !['npm', 'zip'].includes(draft.source.kind)) draft.source = newSource('npm')
}

function mountLabel(kind: MicdnComponentKind): string {
  switch (kind) {
    case 'static_bundle':
      return 'Bundle 挂载名'
    case 'www_doc':
      return '文档挂载路径'
    default:
      return '挂载名'
  }
}

function mountPlaceholder(kind: MicdnComponentKind): string {
  switch (kind) {
    case 'static_bundle':
      return 'bootstrap'
    case 'www_doc':
      return 'manual 或 manual/v2'
    default:
      return 'bundle-name'
  }
}

function addSource() {
  draft.sources.push(newSource('jar'))
}

function normalizeSource(source: DraftSource) {
  if (source.kind === 'dir') source.inner = ''
}

function normalizeWwwSource() {
  if (draft.source.kind !== 'zip') draft.autoDeploy = false
}

function refPlaceholder(kind: MicdnSourceKind): string {
  switch (kind) {
    case 'jar':
      return 'groupId:artifactId:version'
    case 'npm':
      return 'package@version'
    case 'zip':
      return '/srv/docs/manual.zip'
    default:
      return '/srv/static/local'
  }
}

function innerPlaceholder(kind: MicdnSourceKind): string {
  if (kind === 'jar') return 'META-INF/resources（留空自动判断）'
  if (kind === 'npm') return 'dist'
  return 'zip 内目录'
}

function buildSpec(): MicdnComponentSpec {
  if (draft.kind === 'static_bundle') {
    return {
      sources: draft.sources.map((source) => ({
        kind: source.kind,
        ref: source.ref.trim(),
        inner: source.kind === 'dir' ? '' : source.inner.trim(),
      })),
    }
  }
  if (draft.kind === 'www_doc') {
    return {
      source: {
        kind: draft.source.kind,
        ref: draft.source.ref.trim(),
        inner: draft.source.inner.trim(),
      },
      tryFile: draft.tryFile.trim(),
      autoDeploy: draft.autoDeploy,
      autoGzip: draft.autoGzip,
    }
  }
  throw new Error('不支持的组件类型')
}

async function submit() {
  if (!draft.name.trim()) {
    MessagePlugin.warning('组件名称不能为空')
    return
  }
  const mountName = draft.mountName.trim()
  if (!mountName) {
    MessagePlugin.warning('挂载名不能为空')
    return
  }
  if (draft.kind === 'static_bundle' && (mountName.includes('/') || mountName.includes('\\'))) {
    MessagePlugin.warning('静态包的挂载名不能包含路径')
    return
  }
  const input: CdnComponentInput = {
    kind: draft.kind,
    name: draft.name.trim(),
    mountName,
    remark: draft.remark.trim(),
    spec: buildSpec(),
  }
  saving.value = true
  try {
    if (draft.id) await updateCdnComponent(draft.id, input)
    else await createCdnComponent(input)
    drawerVisible.value = false
    MessagePlugin.success('组件已保存')
    await load()
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '保存组件失败')
  } finally {
    saving.value = false
  }
}

function remove(component: CdnComponent) {
  const dialog = DialogPlugin.confirm({
    header: '删除组件',
    body: `确定删除「${component.name}」？仍被 Project 引用时会被拒绝。`,
    onConfirm: async () => {
      try {
        await deleteCdnComponent(component.id)
        MessagePlugin.success('组件已删除')
        dialog.destroy()
        await load()
      } catch (error) {
        MessagePlugin.error(error instanceof Error ? error.message : '删除组件失败')
      }
    },
  })
}

function kindLabel(kind: MicdnComponentKind): string {
  switch (kind) {
    case 'static_bundle':
      return '静态包'
    case 'www_doc':
      return '文档'
    default:
      return kind
  }
}

/** 实际版本：jar 取最后一段，npm 取最后一个 @ 之后；无法识别返回空。 */
function componentVersion(component: CdnComponent): string {
  let source: MicdnSource | undefined
  if (component.kind === 'www_doc') {
    source = (component.spec as WwwDocSpec).source
  } else {
    source = (component.spec as StaticBundleSpec).sources?.[0]
  }
  if (!source) return ''
  if (source.kind === 'npm') {
    const at = source.ref.lastIndexOf('@')
    return at > 0 ? source.ref.slice(at + 1) : ''
  }
  if (source.kind === 'jar') {
    const parts = source.ref.split(':')
    return parts.length >= 3 ? parts[parts.length - 1] : ''
  }
  return ''
}

function specSummary(component: CdnComponent): string {
  if (component.kind === 'static_bundle') {
    const spec = component.spec as StaticBundleSpec
    return (spec.sources || [])
      .map((source: MicdnSource) => `${source.kind}:${source.ref}${source.inner ? `/${source.inner}` : ''}`)
      .join(' + ')
  }
  if (component.kind === 'www_doc') {
    const spec = component.spec as WwwDocSpec
    return `${spec.source.kind}:${spec.source.ref}${spec.source.inner ? `/${spec.source.inner}` : ''}${spec.autoDeploy ? '，自动部署' : ''}`
  }
  return ''
}

onMounted(load)
</script>

<style scoped>
.page-actions {
  display: flex;
  gap: 8px;
}

.catalog-card {
  border: 1px solid var(--td-component-stroke);
  border-radius: 6px;
  background: var(--td-bg-color-container);
}

.catalog-empty {
  padding: 48px 16px;
  color: var(--td-text-color-placeholder);
  text-align: center;
}

.catalog-tabs {
  margin-bottom: 12px;
}

.catalog-card__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 12px;
}

.catalog-card__head > div {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 3px 8px;
  min-width: 0;
}

.catalog-card__head h3 {
  margin: 0;
  font-size: 16px;
}

.catalog-card__head p {
  margin: 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.catalog-tools {
  display: flex;
  align-items: center;
  gap: 8px;
}

.catalog-search {
  width: 220px;
}

.component-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.component-table__index {
  width: 48px;
  color: var(--td-text-color-placeholder);
  text-align: right !important;
}

.component-table th,
.component-table td {
  padding: 10px 12px;
  border-bottom: 1px solid var(--td-component-stroke);
  text-align: left;
  vertical-align: top;
}

.component-table th {
  color: var(--td-text-color-secondary);
  font-weight: 500;
  white-space: nowrap;
}

.component-table tr:last-child td {
  border-bottom: 0;
}

.component-table__kind {
  width: 90px;
}

.component-table__action {
  width: 110px;
  text-align: right !important;
  white-space: nowrap;
}

.component-link {
  color: var(--td-brand-color);
  font-weight: 600;
  text-decoration: none;
}

.component-link:hover {
  text-decoration: underline;
}

.component-table__muted {
  color: var(--td-text-color-secondary);
}

.component-table__mount,
.component-table__version {
  white-space: nowrap;
}

.component-table__version {
  color: var(--td-text-color-secondary);
  font-size: 12px;
}

.component-table__spec {
  color: var(--td-text-color-secondary);
  font-size: 12px;
  word-break: break-all;
}

.kind-tag {
  display: inline-block;
  padding: 1px 7px;
  border-radius: 10px;
  background: var(--td-bg-color-container-hover);
  color: var(--td-text-color-secondary);
  font-size: 12px;
  white-space: nowrap;
}

.kind-tag--static_bundle {
  background: var(--td-brand-color-light);
  color: var(--td-brand-color);
}

.kind-tag--www_doc {
  background: var(--td-success-color-light);
  color: var(--td-success-color);
}

.component-form {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px 18px;
}

.form-grid--inner {
  padding: 12px 16px 16px;
}

.form-field {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 6px;
  font-size: 13px;
}

.form-field > span {
  color: var(--td-text-color-secondary);
}

.form-field--wide {
  grid-column: 1 / -1;
}

.form-field--switch-wide {
  grid-column: 1 / -1;
}

.form-hint {
  margin: 4px 0 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
  font-weight: normal;
}

.form-field--switch {
  align-items: flex-start;
  justify-content: center;
}

.spec-section {
  border: 1px solid var(--td-component-stroke);
  border-radius: 6px;
}

.spec-section > header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 16px;
  border-bottom: 1px solid var(--td-component-stroke);
}

.spec-section > header h3 {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}

.spec-section > header p {
  margin: 3px 0 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.source-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 16px;
  border-bottom: 1px solid var(--td-component-stroke);
}

.source-row:last-child {
  border-bottom: 0;
}

.source-row__kind {
  flex: none;
  width: 64px;
  min-width: 64px;
  max-width: 64px;
}

.source-row__kind :deep(.t-input) {
  padding-right: 8px;
  padding-left: 8px;
}

.source-row__ref {
  flex: 4;
  min-width: 0;
}

.source-row__inner {
  flex: 1;
  min-width: 0;
}

.source-row__action {
  flex: 0 0 auto;
  white-space: nowrap;
}

.drawer-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}

@media (max-width: 760px) {
  .form-grid {
    grid-template-columns: 1fr;
  }

  .form-field--wide {
    grid-column: auto;
  }

  .source-row {
    flex-wrap: wrap;
  }
}
</style>
