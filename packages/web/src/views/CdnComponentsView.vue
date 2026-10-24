<template>
  <section class="page-panel">
    <div class="page-head">
      <div>
        <h2 class="page-title">Micdn 组件目录</h2>
        <p class="page-subtitle">可复用的静态包和文档</p>
      </div>
      <div class="page-actions">
        <t-button theme="primary" @click="openCreate">
          <template #icon><AddIcon /></template>
          新建组件
        </t-button>
      </div>
    </div>

    <div class="catalog-card">
      <t-loading :loading="loading" show-overlay>
        <div v-if="components.length === 0 && !loading" class="catalog-empty">
          还没有组件。创建后可被任意 Project 引用。
        </div>
        <table v-else class="component-table">
          <thead>
            <tr>
              <th class="component-table__kind">类型</th>
              <th>名称</th>
              <th>挂载名</th>
              <th>说明</th>
              <th>规格</th>
              <th class="component-table__action">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="component in components" :key="component.id">
              <td><span class="kind-tag" :class="`kind-tag--${component.kind}`">{{ kindLabel(component.kind) }}</span></td>
              <td><strong>{{ component.name }}</strong></td>
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
    </div>

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
            <div class="form-field form-field--switch">
              <span>自动部署</span>
              <t-switch v-model="draft.autoDeploy" :disabled="draft.source.kind !== 'zip'" />
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
import { AddIcon } from 'tdesign-icons-vue-next'
import { DialogPlugin, MessagePlugin } from 'tdesign-vue-next'
import { onMounted, reactive, ref } from 'vue'
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
const loading = ref(false)
const saving = ref(false)
const drawerVisible = ref(false)

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

function openCreate() {
  Object.assign(draft, {
    id: '',
    kind: 'static_bundle',
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

.component-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
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

.component-table__muted {
  color: var(--td-text-color-secondary);
}

.component-table__mount {
  white-space: nowrap;
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
