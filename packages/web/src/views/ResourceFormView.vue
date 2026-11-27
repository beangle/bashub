<template>
  <section class="page-panel">
    <div class="form-page-frame">
    <div class="page-head">
      <div class="detail-heading">
        <div class="title-row">
          <h2 class="page-title">{{ editing ? `编辑${schema.title}` : `新建${schema.title}` }}</h2>
          <router-link class="title-back" :to="returnPath">← 返回{{ schema.title }}</router-link>
        </div>
        <p v-if="contextLabel" class="page-subtitle">项目：{{ contextLabel }}</p>
      </div>
    </div>

    <t-loading :loading="loading" show-overlay>
      <div class="form-page">
        <t-form
          ref="formRef"
          :data="form"
          :rules="rules"
          :show-error-message="showErrors"
          label-align="top"
          required-mark-position="right"
        >
          <div
            class="form-page-grid"
            :style="{ gridTemplateColumns: schema.formGrid || `repeat(${schema.formColumns || 3}, minmax(0, 1fr))` }"
          >
            <template v-for="(field, index) in formFields" :key="field.key">
              <div
                v-if="field.section && (index === 0 || formFields[index - 1].section !== field.section)"
                class="form-section form-section--inline-rule"
              >
                {{ field.section }}
              </div>
              <t-form-item :label="field.label" :name="field.key" :class="{ 'form-field-wide': isWideField(field) }">
                <t-input
                  v-if="inputType(field) === 'text' || inputType(field) === 'password'"
                  v-model="form[field.key]"
                  :type="inputType(field) === 'password' ? 'password' : 'text'"
                  :placeholder="field.placeholder || `请输入${field.label}`"
                  clearable
                />
                <t-input-number
                  v-else-if="inputType(field) === 'number'"
                  v-model="form[field.key]"
                  :placeholder="field.placeholder || `请输入${field.label}`"
                  :min="field.min"
                  :max="field.max"
                  theme="normal"
                  style="width: 100%"
                />
                <t-textarea
                  v-else-if="inputType(field) === 'textarea'"
                  v-model="form[field.key]"
                  :placeholder="field.placeholder || `请输入${field.label}`"
                  :autosize="{ minRows: field.rows ?? 4 }"
                />
                <t-textarea
                  v-else-if="inputType(field) === 'lines'"
                  v-model="form[field.key]"
                  :placeholder="field.placeholder || '一行一项'"
                  :autosize="{ minRows: field.rows ?? 4 }"
                />
                <t-switch v-else-if="inputType(field) === 'boolean'" v-model="form[field.key]" />
                <t-select
                  v-else-if="inputType(field) === 'select'"
                  v-model="form[field.key]"
                  :options="field.options || []"
                  :placeholder="`请选择${field.label}`"
                  clearable
                />
                <t-select
                  v-else-if="inputType(field) === 'ref'"
                  v-model="form[field.key]"
                  :options="optionsCache[field.key] || []"
                  :placeholder="`请选择${field.label}`"
                  filterable
                  clearable
                  @change="onFieldChange(field, $event)"
                />
                <t-select
                  v-else-if="inputType(field) === 'refs' || inputType(field) === 'ids'"
                  v-model="form[field.key]"
                  :options="optionsCache[field.key] || []"
                  :placeholder="`请选择${field.label}`"
                  multiple
                  filterable
                  clearable
                />
                <template v-if="field.help" #help><span>{{ field.help }}</span></template>
              </t-form-item>
            </template>
          </div>
          <FarmServersEditor
            v-if="schema.embeddedServers && editing"
            :farm-id="editingId"
            :project-id="contextField ? String(form[contextField.key] ?? '') : ''"
          />
          <p v-else-if="schema.embeddedServers" class="form-page-hint">保存群集后即可在这里维护服务。</p>
          <div class="form-page-actions">
            <t-button variant="outline" :disabled="saving" @click="cancel">取消</t-button>
            <t-button theme="primary" :loading="saving" @click="submit">保存</t-button>
          </div>
        </t-form>
      </div>
    </t-loading>
    </div>
  </section>
</template>

<script setup lang="ts">
import { MessagePlugin, type FormInstanceFunctions, type FormRule } from 'tdesign-vue-next'
import { computed, onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import FarmServersEditor from '@/components/FarmServersEditor.vue'
import {
  attributeText,
  getResource,
  listResource,
  relationshipIds,
  saveResource,
  type ResourceRow,
} from '@/api/resource'
import { resourceApiPath } from '@/api/prefix'
import { currentProjectId, projectId } from '@/current-project'
import { getSchema, getTabGroup, resourceTabGroups } from '@/resources'
import type { FieldSchema, SelectOption } from '@/resources/types'

const route = useRoute()
const router = useRouter()
const schemaKey = String(route.params.schemaKey || '')
const schema = getSchema(schemaKey)
const editingId = String(route.params.id || '')
const editing = editingId.length > 0
const contextField = schema.contextField ? schema.fields.find((field) => field.key === schema.contextField) : undefined
const formFields = schema.fields.filter((field) => field.form !== false && field.key !== schema.contextField)
const loading = ref(false)
const saving = ref(false)
const showErrors = ref(false)
const formRef = ref<FormInstanceFunctions>()
const form = reactive<Record<string, unknown>>({})
const optionsCache = reactive<Record<string, SelectOption[]>>({})
const rows = new Map<string, ResourceRow[]>()

const listPath = computed(() => {
  const group = resourceTabGroups.find((item) => item.tabs.some((tab) => tab.key === schemaKey))
  return group ? `${group.path}?tab=${schemaKey}` : resourceApiPath(schema.path)
})
const returnPath = computed(() => {
  const value = route.query.returnTo
  return typeof value === 'string' && value.startsWith('/') ? value : listPath.value
})
const contextLabel = computed(() => {
  if (!contextField) return ''
  const raw = String(form[contextField.key] ?? '')
  if (!raw) return ''
  return optionsCache[contextField.key]?.find((option) => String(option.value) === raw)?.label || raw
})

function inputType(field: FieldSchema): string {
  return field.type || 'text'
}

function isWideField(field: FieldSchema): boolean {
  if (field.wide !== undefined) return field.wide
  const type = inputType(field)
  return type === 'textarea' || type === 'lines'
}

function fieldValue(row: ResourceRow, field: FieldSchema): unknown {
  return row.attributes[field.key]
}

function defaultFormValue(field: FieldSchema): unknown {
  if (field.defaultValue !== undefined) return field.defaultValue
  switch (inputType(field)) {
  case 'refs':
  case 'ids':
    return []
  case 'boolean':
    return false
  case 'number':
    return undefined
  default:
    return ''
  }
}

function resetForm(row?: ResourceRow) {
  ;[...formFields, ...(contextField ? [contextField] : [])].forEach((field) => {
    if (!row) {
      if (contextField && field.key === contextField.key) {
        form[field.key] = projectId(route.query.contextProjectId) || currentProjectId.value
      } else {
        form[field.key] = defaultFormValue(field)
      }
      return
    }
    if (field.type === 'ref') {
      form[field.key] = relationshipIds(row, field.key)[0] || ''
    } else if (field.type === 'refs') {
      form[field.key] = relationshipIds(row, field.key)
    } else if (field.type === 'ids') {
      const value = fieldValue(row, field)
      form[field.key] = Array.isArray(value) ? value.map(String) : []
    } else if (field.type === 'boolean') {
      form[field.key] = Boolean(fieldValue(row, field))
    } else if (field.type === 'lines') {
      const value = fieldValue(row, field)
      form[field.key] = Array.isArray(value) ? value.join('\n') : value == null ? '' : String(value)
    } else if (field.secret) {
      form[field.key] = ''
    } else {
      const value = fieldValue(row, field)
      form[field.key] = value === null || value === undefined ? '' : value
    }
  })
}

async function loadOptions() {
  let project = contextField ? String(form[contextField.key] ?? '') : currentProjectId.value
  if (contextField && !project) {
    project = projectId(route.query.contextProjectId) || currentProjectId.value
  }
  const refs = [...formFields, ...(contextField ? [contextField] : [])].filter((field) => field.ref)
  await Promise.all(refs.map(async (field) => {
    const ref = field.ref!
    let result
    if (ref.path === '/servers' && field.optionsFilter === 'farm.project.id' && project) {
      const farms = await listResource('/farms', { filters: { 'farm.project.id': project }, pageSize: 500 })
      const farmIds = new Set(farms.rows.map((row) => row.id))
      result = await listResource('/servers', { pageSize: 300, sort: ref.sort || ref.labelFields[0], include: ['farm', 'host'] })
      result.rows = result.rows.filter((row) => relationshipIds(row, 'farm').some((id) => farmIds.has(id)))
    } else {
      result = await listResource(ref.path, {
        pageSize: 300,
        sort: ref.sort || ref.labelFields[0],
        filters: field.optionsFilter && project ? { [field.optionsFilter]: project } : undefined,
      })
    }
    // 应用部署的组件候选：当前项目的组件或通用组件；保留当前已选项，避免历史跨项目部署无法编辑。
    if (ref.path === '/artifacts' && project) {
      const current = String(form[field.key] ?? '')
      result.rows = result.rows.filter((row) => {
        const owner = relationshipIds(row, 'project')[0] || ''
        return row.id === current || owner === '' || owner === project
      })
    }
    rows.set(field.key, result.rows)
    optionsCache[field.key] = result.rows.map((row) => ({
      label: ref.labelFields.map((name) => attributeText(row.attributes[name])).filter(Boolean).join(' ') || row.id,
      value: row.id,
    }))
  }))
}

function onFieldChange(field: FieldSchema, value: unknown) {
  if (!field.refDefaults || !field.ref) return
  const selected = rows.get(field.key)?.find((row) => row.id === String(value))
  if (!selected) return
  for (const [target, path] of Object.entries(field.refDefaults)) {
    form[target] = attributeText(selected.attributes[path]) || ''
  }
  fillSingleCoupledOption()
}

/**
 * 条件必填的关联字段（如应用部署的「代理点」随「上下文」出现）：
 * 目标字段为空且只有一个可选项时自动选中；有多个选项则留空，由用户明确选择。
 */
function fillSingleCoupledOption() {
  formFields.forEach((field) => {
    if (!field.requiredWhenFilled || !filled(form[field.requiredWhenFilled])) return
    if (field.type !== 'refs' && field.type !== 'ref') return
    const selected = form[field.key]
    if (filled(selected)) return
    const options = optionsCache[field.key] || []
    if (options.length !== 1) return
    form[field.key] = field.type === 'refs' ? [String(options[0].value)] : String(options[0].value)
  })
}

const rules = computed<Record<string, FormRule[]>>(() => {
  const result: Record<string, FormRule[]> = {}
  formFields.forEach((field) => {
    const list: FormRule[] = []
    const required = isRequiredField(field) || (field.requiredWhenFilled && filled(form[field.requiredWhenFilled]))
    if (required)
      list.push({ required: true, message: `请填写${field.label}` })
    if (list.length > 0) result[field.key] = list
  })
  return result
})

function filled(value: unknown): boolean {
  return value !== '' && value !== null && value !== undefined && (!Array.isArray(value) || value.length > 0)
}

function isRequiredField(field: FieldSchema): boolean {
  if (field.required) return true
  if (!field.requiredWhen) return false
  const trigger = form[field.requiredWhen]
  if (field.requiredWhenValue !== undefined) return trigger === field.requiredWhenValue
  return Boolean(trigger)
}

function buildPayload(): { attributes: Record<string, unknown>; relationships: Record<string, unknown> } {
  const attributes: Record<string, unknown> = {}
  const relationships: Record<string, unknown> = {}
  formFields.forEach((field) => {
    if (field.virtual) return
    const raw = form[field.key]
    if (field.type === 'ref') {
      relationships[field.key] = { data: raw ? { type: field.ref!.type, id: String(raw) } : null }
      return
    }
    if (field.type === 'refs') {
      const ids = Array.isArray(raw) ? raw : []
      relationships[field.key] = { data: ids.map((id) => ({ type: field.ref!.type, id: String(id) })) }
      return
    }
    if (field.type === 'ids') {
      attributes[field.key] = Array.isArray(raw) ? raw.map(String) : []
      return
    }
    if (field.type === 'boolean') {
      attributes[field.key] = Boolean(raw)
      return
    }
    if (field.type === 'lines') {
      const lines = String(raw ?? '').split('\n').map((line) => line.trim()).filter(Boolean)
      attributes[field.key] = field.json ? lines : lines.join('\n')
      return
    }
    if (field.type === 'number') {
      if (raw === '' || raw === undefined || raw === null) {
        if (field.required) attributes[field.key] = 0
        return
      }
      attributes[field.key] = Number(raw)
      return
    }
    const text = String(raw ?? '').trim()
    if (text.length === 0) {
      if (field.allowEmpty) attributes[field.key] = ''
      return
    }
    attributes[field.key] = text
  })
  if (contextField && contextField.type === 'ref' && form[contextField.key]) {
    relationships[contextField.key] = { data: { type: contextField.ref!.type, id: String(form[contextField.key]) } }
  }
  return { attributes, relationships }
}

async function load() {
  loading.value = true
  try {
    if (editing) {
      resetForm(await getResource(schema.path, editingId))
    } else {
      resetForm()
    }
    await loadOptions()
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '加载表单失败')
  } finally {
    loading.value = false
  }
}

async function submit() {
  showErrors.value = true
  const valid = await formRef.value?.validate()
  if (valid !== true) return
  saving.value = true
  try {
    const { attributes, relationships } = buildPayload()
    await saveResource(schema.path, schema.type, attributes, relationships, editingId || undefined)
    MessagePlugin.success(editing ? '保存成功' : '创建成功')
    await router.push(returnPath.value)
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '保存失败')
  } finally {
    saving.value = false
  }
}

function cancel() {
  void router.push(returnPath.value)
}

onMounted(load)
</script>

<style scoped>
.form-page-frame {
  max-width: 1040px;
  margin: 0 auto;
}

.form-page {
  margin: 12px auto 28px;
  padding: 18px 28px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container);
}

.form-page-grid {
  display: grid;
  gap: 10px 20px;
}

.form-page :deep(.t-form__item) {
  min-width: 0;
  /* TDesign 默认给 FormItem 24px 下边距；栅格已用 gap 控制间距，避免叠加。 */
  margin-bottom: 0;
}

.form-page :deep(.t-input),
.form-page :deep(.t-input-number),
.form-page :deep(.t-select),
.form-page :deep(.t-textarea) {
  width: 100%;
}

.form-field-wide {
  grid-column: 1 / -1;
}

.form-section {
  grid-column: 1 / -1;
  margin-top: 14px;
  padding-top: 6px;
  border-top: 1px solid var(--td-component-stroke);
  color: var(--td-text-color-secondary);
  font-size: 13px;
  font-weight: 600;
}

.form-section--inline-rule {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-top: 14px;
  padding-top: 4px;
  border-top: 0;
}

.form-section--inline-rule::after {
  flex: 1;
  height: 1px;
  background: var(--td-component-stroke);
  content: '';
}

.form-page-grid > .form-section:first-child {
  margin-top: 0;
}

.form-page-hint {
  margin: 18px 0 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.form-page-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 14px;
  padding-top: 12px;
  border-top: 1px solid var(--td-component-stroke);
}
</style>
