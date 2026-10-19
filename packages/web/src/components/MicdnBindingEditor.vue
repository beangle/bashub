<template>
  <section class="binding-editor">
    <header class="binding-editor__head">
      <div>
        <h3>{{ title }}</h3>
        <p>{{ description }}</p>
      </div>
      <div class="binding-editor__add">
        <t-select
          v-model="addId"
          :options="componentOptions"
          :placeholder="componentOptions.length ? '选择组件' : '组件目录为空'"
          :disabled="componentOptions.length === 0"
          filterable
          clearable
        />
        <t-button theme="primary" variant="outline" :disabled="!addId" @click="addBinding">
          <template #icon><AddIcon /></template>
          添加绑定
        </t-button>
      </div>
    </header>

    <div v-if="rows.length === 0" class="binding-editor__empty">
      尚未绑定{{ kindLabel }}。可先在「组件目录」创建组件，再从上方选择。
    </div>
    <table v-else class="binding-table">
      <thead>
        <tr>
          <th>组件</th>
          <th>规格</th>
          <th>挂载名</th>
          <th v-if="showSort" class="binding-table__sort">顺序</th>
          <th class="binding-table__action">操作</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(row, index) in rows" :key="row.id || `${row.componentId}-${index}`">
          <td>
            <strong>{{ row.name }}</strong>
          </td>
          <td><code class="binding-table__spec">{{ specSummary(row.spec) }}</code></td>
          <td><code class="binding-table__mount">{{ row.mountName }}</code></td>
          <td v-if="showSort" class="binding-table__sort">
            <t-input-number
              :model-value="row.sortno"
              theme="normal"
              :min="0"
              @change="updateRow(index, { sortno: Number($event || 0) })"
            />
          </td>
          <td class="binding-table__action">
            <t-button size="small" variant="text" theme="danger" @click="removeBinding(index)">移除</t-button>
          </td>
        </tr>
      </tbody>
    </table>
  </section>
</template>

<script setup lang="ts">
import { AddIcon } from 'tdesign-icons-vue-next'
import { computed, ref } from 'vue'
import type {
  CdnComponent,
  MicdnBinding,
  MicdnComponentKind,
  StaticBundleSpec,
  WwwDocSpec,
} from '@/api/micdn'

const props = defineProps<{
  kind: MicdnComponentKind
  modelValue: MicdnBinding[]
  components: CdnComponent[]
}>()

const emit = defineEmits<{ 'update:modelValue': [value: MicdnBinding[]] }>()

const addId = ref('')

const rows = computed(() => {
  const items = props.modelValue.filter((binding) => binding.kind === props.kind)
  if (props.kind !== 'static_bundle') return items
  return [...items].sort((left, right) => left.mountName.localeCompare(right.mountName))
})
const showSort = computed(() => props.kind !== 'static_bundle')
const candidates = computed(() => {
  const bound = new Set(rows.value.map((row) => row.componentId))
  return props.components.filter((component) => component.kind === props.kind && !bound.has(component.id))
})
const componentOptions = computed(() =>
  candidates.value.map((component) => ({
    value: component.id,
    label: [
      component.name === component.mountName ? component.name : `${component.name} → ${component.mountName}`,
      component.remark,
    ].filter(Boolean).join('（') + (component.remark ? '）' : ''),
  })),
)

const kindLabel = computed(() => {
  switch (props.kind) {
    case 'static_bundle':
      return '静态包'
    case 'www_doc':
      return '文档'
    default:
      return props.kind
  }
})

const title = computed(() => `${kindLabel.value}绑定`)
const description = computed(() => {
  switch (props.kind) {
    case 'static_bundle':
      return '挂载名在组件目录维护，对应 /static/{mountName}/；bundle 按挂载名字母排序，来源按 provider 稳定排序。'
    case 'www_doc':
      return '文档路径在组件目录维护，对应 /www/{mountName}/；此处只设置引用顺序。'
    default:
      return ''
  }
})

function emitRows(nextRows: MicdnBinding[]) {
  emit('update:modelValue', [
    ...props.modelValue.filter((binding) => binding.kind !== props.kind),
    ...nextRows,
  ])
}

function addBinding() {
  const component = candidates.value.find((candidate) => candidate.id === addId.value)
  if (!component) return
  const sortno = props.modelValue.reduce((max, binding) => Math.max(max, Number(binding.sortno) || 0), 0) + 10
  emitRows([
    ...rows.value,
    {
      componentId: component.id,
      kind: component.kind,
      name: component.name,
      mountName: component.mountName,
      sortno,
      spec: component.spec,
    },
  ])
  addId.value = ''
}

function updateRow(index: number, patch: Partial<MicdnBinding>) {
  emitRows(rows.value.map((row, current) => (current === index ? { ...row, ...patch } : row)))
}

function removeBinding(index: number) {
  emitRows(rows.value.filter((_row, current) => current !== index))
}

function specSummary(spec: MicdnBinding['spec']): string {
  if ('sources' in spec) {
    const sources = (spec as StaticBundleSpec).sources || []
    return sources.map((source) => `${source.kind}:${source.ref}${source.inner ? `/${source.inner}` : ''}`).join(' + ')
  }
  if ('source' in spec) {
    const doc = spec as WwwDocSpec
    const inner = doc.source.inner ? `/${doc.source.inner}` : ''
    return `${doc.source.kind}:${doc.source.ref}${inner}`
  }
  return ''
}

</script>

<style scoped>
.binding-editor {
  border: 1px solid var(--td-component-stroke);
  border-radius: 6px;
  background: var(--td-bg-color-container);
}

.binding-editor__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 16px;
  border-bottom: 1px solid var(--td-component-stroke);
}

.binding-editor__head h3 {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}

.binding-editor__head p {
  margin: 3px 0 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.binding-editor__add {
  display: flex;
  flex: 0 0 auto;
  gap: 8px;
  min-width: 360px;
}

.binding-editor__add :deep(.t-select) {
  flex: 1;
}

.binding-editor__empty {
  padding: 20px 16px;
  color: var(--td-text-color-placeholder);
  font-size: 13px;
}

.binding-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.binding-table th,
.binding-table td {
  padding: 8px 12px;
  border-bottom: 1px solid var(--td-component-stroke);
  text-align: left;
  vertical-align: middle;
}

.binding-table th {
  color: var(--td-text-color-secondary);
  font-weight: 500;
  white-space: nowrap;
}

.binding-table tr:last-child td {
  border-bottom: 0;
}

.binding-table__sort {
  width: 110px;
}

.binding-table__action {
  width: 70px;
  text-align: right !important;
}

.binding-table__spec {
  color: var(--td-text-color-secondary);
  word-break: break-all;
}

.binding-table__mount {
  white-space: nowrap;
}

</style>
