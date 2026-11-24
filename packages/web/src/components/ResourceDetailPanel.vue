<template>
  <div class="resource-detail">
    <div v-if="row" class="resource-detail__grid">
      <div
        v-for="field in fields"
        :key="field.key"
        class="resource-detail__item"
        :class="{ 'resource-detail__item--wide': isWideField(field) }"
      >
        <span>{{ field.label }}</span>
        <strong>{{ valueOf(field) || '—' }}</strong>
      </div>
    </div>
    <p v-else-if="error" class="resource-detail__error">{{ error }}</p>
    <p v-else-if="!loading" class="resource-detail__empty">记录不存在。</p>
    <div class="resource-detail__actions">
      <t-button size="small" variant="outline" @click="$emit('edit')">编辑</t-button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { MessagePlugin } from 'tdesign-vue-next'
import { onMounted, reactive, ref } from 'vue'
import { attributeText, getResourceDetail, listResource, relationshipIds, type ResourceRow } from '@/api/resource'
import { getSchema } from '@/resources'
import type { FieldSchema, SelectOption } from '@/resources/types'

const props = defineProps<{ schemaKey: string; id: string }>()
defineEmits<{ edit: [] }>()

const schema = getSchema(props.schemaKey)
const row = ref<ResourceRow>()
const loading = ref(false)
const error = ref('')
const optionsCache = reactive<Record<string, SelectOption[]>>({})
const contextField = schema.contextField ? schema.fields.find((field) => field.key === schema.contextField) : undefined
const fields = schema.fields.filter((field) => !field.secret && !field.virtual && field.key !== schema.contextField)

function isWideField(field: FieldSchema): boolean {
  return field.wide === true || field.type === 'lines' || field.type === 'textarea'
}

function valueOf(field: FieldSchema): string {
  if (!row.value) return ''
  if (field.type === 'ref') {
    const refId = relationshipIds(row.value, field.key)[0] || ''
    return optionsCache[field.key]?.find((option) => String(option.value) === refId)?.label || refId
  }
  if (field.type === 'refs' || field.type === 'ids') {
    const ids = field.type === 'refs' ? relationshipIds(row.value, field.key) : (row.value.attributes[field.key] as unknown[])
    return (Array.isArray(ids) ? ids : []).map((item) => {
      const value = String(item)
      return optionsCache[field.key]?.find((option) => String(option.value) === value)?.label || value
    }).join('、')
  }
  const value = row.value.attributes[field.key]
  if (Array.isArray(value)) return value.join('、')
  return attributeText(value)
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    const detail = await getResourceDetail(schema.path, props.id)
    row.value = detail.row
    const refs = [...fields, ...(contextField ? [contextField] : [])].filter((field) => field.ref)
    await Promise.all(refs.map(async (field) => {
      const result = await listResource(field.ref!.path, { pageSize: 300, sort: field.ref!.sort || field.ref!.labelFields[0] })
      optionsCache[field.key] = result.rows.map((item) => ({
        label: field.ref!.labelFields.map((name) => attributeText(item.attributes[name])).filter(Boolean).join(' ') || item.id,
        value: item.id,
      }))
    }))
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : '加载详情失败'
    MessagePlugin.error(error.value)
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<style scoped>
.resource-detail__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px 24px;
}

.resource-detail__item {
  display: flex;
  min-width: 0;
  align-items: baseline;
  gap: 10px;
}

.resource-detail__item--wide {
  grid-column: 1 / -1;
}

.resource-detail__item span {
  flex: 0 0 96px;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.resource-detail__item strong {
  min-width: 0;
  flex: 1;
  overflow-wrap: anywhere;
  font-size: 13px;
  font-weight: 500;
}

.resource-detail__actions {
  display: flex;
  justify-content: flex-end;
  margin-top: 18px;
  padding-top: 12px;
  border-top: 1px solid var(--td-component-stroke);
}

.resource-detail__error {
  color: var(--td-error-color);
}

.resource-detail__empty {
  color: var(--td-text-color-placeholder);
}
</style>
