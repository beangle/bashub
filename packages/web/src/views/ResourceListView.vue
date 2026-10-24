<template>
  <section class="page-panel page-panel--workbench">
    <div class="page-head">
      <div>
        <h2 class="page-title">{{ schema.title }}</h2>
        <p v-if="schema.description" class="page-subtitle">{{ schema.description }}</p>
      </div>
      <div class="page-actions">
        <template v-if="schema.xmlTools">
          <t-button variant="outline" :disabled="!currentAppId" @click="exportXml">导出 XML</t-button>
          <t-button variant="outline" :disabled="!currentAppId" @click="triggerImport">导入 XML</t-button>
          <input ref="fileInput" type="file" accept=".xml,application/xml" class="hidden-file" @change="importXml" />
        </template>
        <t-button v-if="schema.exportable" variant="outline" :disabled="rows.length === 0" @click="exportCsv">导出</t-button>
        <t-button v-if="!schema.readOnly" theme="primary" @click="openCreate">
          <template #icon><AddIcon /></template>
          新建{{ schema.title }}
        </t-button>
      </div>
    </div>

    <UnderlineTabs
      v-if="tabs && tabs.length > 1"
      :tabs="tabs"
      :model-value="activeTab || ''"
      @update:model-value="emit('update:activeTab', $event)"
    />

    <div class="data-workbench" :class="{ 'data-workbench--query': filterFields.length > 0 }">
      <aside v-if="filterFields.length > 0" class="query-panel">
        <div class="query-title">查询条件</div>
        <form class="query-fields" @submit.prevent="reload">
          <label v-for="filter in filterFields" :key="filter.key" class="query-field">
            <span class="query-field-label" :class="{ required: filter.required }">{{ filter.label }}</span>
            <t-select
              v-if="filterControl(filter) === 'select'"
              v-model="filterValues[filter.key]"
              :options="filterOptions(filter)"
              :placeholder="`请选择${filter.label}`"
              filterable
              clearable
              @change="reload"
            />
            <t-input-number
              v-else-if="filterControl(filter) === 'number'"
              v-model="filterValues[filter.key]"
              :placeholder="`请输入${filter.label}`"
              clearable
              @change="reload"
            />
            <t-input
              v-else
              v-model="filterValues[filter.key]"
              :placeholder="`请输入${filter.label}`"
              clearable
              @enter="reload"
            />
          </label>
          <div class="query-actions">
            <t-button theme="primary" variant="outline" size="small" type="submit">查询</t-button>
          </div>
        </form>
      </aside>

      <main class="data-region">
        <p v-if="gateHint" class="data-region__gate">{{ gateHint }}</p>
        <t-loading v-else-if="isCards" :loading="loading" show-overlay>
        <div class="card-grid">
          <article
            v-for="row in rows"
            :key="row.id"
            class="feature-card"
            :title="cardHint"
            @click="openCard(row)"
          >
            <div class="feature-card__top">
              <img v-if="cellAttr(row, 'logo')" class="feature-card__logo" :src="cellAttr(row, 'logo')" :alt="cellAttr(row, 'name')" />
              <div class="feature-card__head">
                <span class="feature-card__name">{{ cellAttr(row, 'name') }}</span>
                <span class="feature-card__version">{{ cellAttr(row, 'version') }}</span>
              </div>
            </div>
            <p class="feature-card__desc">{{ cellAttr(row, 'description') }}</p>
            <div class="feature-card__foot">
              <span>依赖：{{ dependencyNames(row) || '—' }}</span>
              <span>{{ relationshipIds(row, 'scripts').length }} 个脚本</span>
            </div>
          </article>
          <p v-if="!loading && rows.length === 0" class="card-grid__empty">暂无{{ schema.title }}</p>
        </div>
        </t-loading>
        <DataGrid
          v-else
          :key="isTree ? `tree-${treeRevision}` : undefined"
          row-key="id"
          :data="displayRows"
          :columns="columns"
          :tree="treeConfig"
          :loading="loading"
          :pagination="pagination"
          :sort="sort"
          :selectable="!schema.readOnly"
          toolbar-placement="auto"
          column-configurable
          :actions="gridActions"
          @page-change="onPageChange"
          @sort-change="onSortChange"
          @action="onGridAction"
        />
      </main>
    </div>
  </section>

  <t-drawer
    v-model:visible="formVisible"
    :header="editingId ? `编辑${schema.title}` : `新建${schema.title}`"
    size="680px"
  >
    <t-form
      ref="formRef"
      class="drawer-form"
      :data="form"
      :rules="rules"
      :show-error-message="showErrors"
      label-align="top"
      required-mark-position="right"
    >
      <div class="drawer-form-grid">
        <t-form-item
          v-for="field in formFields"
          :key="field.key"
          :label="field.label"
          :name="field.key"
          :class="{ 'drawer-form-field-wide': isWideField(field) }"
        >
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
          <t-radio-group
            v-else-if="inputType(field) === 'radio'"
            v-model="form[field.key]"
            @change="onFieldChange(field, $event)"
          >
            <t-radio v-for="option in field.options || []" :key="String(option.value)" :value="option.value">
              {{ option.label }}
            </t-radio>
          </t-radio-group>
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
            :options="optionsOf(field)"
            :placeholder="`请选择${field.label}`"
            filterable
            clearable
          />
          <t-select
            v-else-if="inputType(field) === 'refs'"
            v-model="form[field.key]"
            :options="optionsOf(field)"
            :placeholder="`请选择${field.label}`"
            multiple
            filterable
            clearable
          />
          <template v-if="field.help" #help>
            <span>{{ field.help }}</span>
          </template>
        </t-form-item>
      </div>
      <div v-if="editingId && drawerLinks.length" class="drawer-links">
        <span class="drawer-links__label">相关页面</span>
        <t-button
          v-for="link in drawerLinks"
          :key="link.to"
          size="small"
          variant="outline"
          theme="primary"
          @click="openDrawerLink(link)"
        >
          {{ link.label }}
        </t-button>
      </div>
    </t-form>
    <template #footer>
      <div class="drawer-actions">
        <t-button variant="outline" :disabled="submitting" @click="formVisible = false">取消</t-button>
        <t-button theme="primary" :loading="submitting" @click="submitForm">提交</t-button>
      </div>
    </template>
  </t-drawer>
</template>

<script setup lang="ts">
import { DataGrid, UnderlineTabs, type DataGridAction, type DataGridColumn, type UnderlineTabItem } from '@beangle/bui-vue'
import { AddIcon, DeleteIcon, EditIcon } from 'tdesign-icons-vue-next'
import { DialogPlugin, MessagePlugin, type FormInstanceFunctions, type FormRule, type PageInfo } from 'tdesign-vue-next'
import { computed, h, nextTick, onMounted, reactive, ref, shallowRef } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import {
  attributeText,
  callResourceAction,
  getPlainJson,
  indexIncluded,
  listResource,
  relationshipIds,
  relationshipTargets,
  removeResource,
  saveResource,
  uploadResourceFile,
  type ResourceRow,
} from '@/api/resource'
import { apiPath } from '@/api/prefix'
import { currentProjectId, forgetProject, isProjectRef, isProjectScoped, projectId, rememberProject } from '@/current-project'
import { rememberedFilterValue, rememberFilterValue } from '@/filter-memory'
import { getSchema } from '@/resources'
import type { DrawerLinkSchema, FieldSchema, SelectOption } from '@/resources/types'

const props = defineProps<{
  schemaKey: string
  /** 同页多资源切换的页签；缺省不渲染页签条。 */
  tabs?: UnderlineTabItem[]
  /** 当前页签，配合 `v-model:active-tab` 使用。 */
  activeTab?: string
}>()

const emit = defineEmits<{ 'update:activeTab': [value: string] }>()

const schema = getSchema(props.schemaKey)
const formFields = schema.fields.filter((field) => field.form !== false)
const filterFields = schema.filters || []
const route = useRoute()
const router = useRouter()
const isTree = Boolean(schema.tree)
const treeConfig = isTree ? { childrenKey: 'children', defaultExpandAll: true } : undefined
const isCards = schema.layout === 'cards'
/** 以配置为工作域的资源（群集/主机/应用部署）：查询条件与新建表单都跟着「当前配置」走。 */
const projectScoped = isProjectScoped(schema)
/** 查询条件里的「配置」字段。 */
const projectFilter = filterFields.find(isProjectRef)
/** 树形表格的 defaultExpandAll 只在挂载时生效，数据异步返回后需重挂一次才能整树展开。 */
const treeRevision = ref(0)

/** 卡片依赖关联的 JSON:API 资源名（用于从 included 中回取）。 */
const featureRefType = 'platformFeatures'

/** 列表列字段：缺省展示除 textarea/lines/password 之外的字段。 */
function isColumnField(field: FieldSchema): boolean {
  return field.column ?? !['textarea', 'lines', 'password'].includes(field.type || 'text')
}

/** 列序缺省与字段声明一致；schema.columns 显式指定时按其排列，未列出的字段追加在后。 */
function orderedColumnFields(): FieldSchema[] {
  const fields = schema.fields.filter(isColumnField)
  if (!schema.columns) return fields
  const rank = new Map(schema.columns.map((key, index) => [key, index]))
  const rankOf = (field: FieldSchema) => rank.get(field.key) ?? Number.MAX_SAFE_INTEGER
  return [...fields].sort((a, b) => rankOf(a) - rankOf(b))
}

const columns: DataGridColumn[] = orderedColumnFields()
  .map((field) => ({
    colKey: field.key,
    title: field.columnTitle || field.label,
    width: field.width,
    sortable: isSortableField(field),
    sortKey: field.sortKey || defaultSortKey(field),
    cell: field.cell ? renderCell(field) : undefined,
  }))

/**
 * 列头排序：对齐原 BUI 网格「带 property 的列都可排序」。
 * 缺省属性列可排序；集合（refs）与派生的链接/图标列由 schema 显式设 `sortable: false`。
 */
function isSortableField(field: FieldSchema): boolean {
  return field.sortable ?? field.type !== 'refs'
}

/** 引用列按关联的展示字段排序（如平台列 → `platform.name`、组件列 → `artifact.title`）。 */
function defaultSortKey(field: FieldSchema): string | undefined {
  if (field.type !== 'ref' || !field.ref) return undefined
  const label = field.ref.labelFields[0]
  return label ? `${field.refKey || field.key}.${label}` : undefined
}

const rows = shallowRef<ResourceRow[]>([])
const includedIndex = shallowRef(indexIncluded([]))
const loading = ref(false)
const sort = ref(schema.sort || '')
const pagination = reactive({ current: 1, pageSize: 30, total: 0 })
const filterValues = reactive<Record<string, unknown>>({})
const optionsCache = reactive<Record<string, SelectOption[]>>({})

/** 查询条件是否已填值（空串、未选、空多选都算没填）。 */
function filterValueFilled(value: unknown): boolean {
  if (Array.isArray(value)) return value.length > 0
  return value !== '' && value !== null && value !== undefined
}

/**
 * 必填查询条件为空时（菜单管理的「应用」）不查列表：原菜单页也是先选应用再加载，
 * 否则会把全量菜单拉回来。
 */
const missingRequiredFilters = computed(() =>
  filterFields.filter((field) => field.required && !filterValueFilled(filterValues[field.key])),
)
const gateHint = computed(() =>
  missingRequiredFilters.value.length > 0 ? `请先选择${missingRequiredFilters.value[0].label}` : '',
)

const displayRows = computed<Record<string, unknown>[]>(() =>
  buildTree(rows.value.map((row) => {
    const item: Record<string, unknown> = { id: row.id, __row: row }
    columns.forEach((column) => {
      const field = schema.fields.find((candidate) => candidate.key === column.colKey)
      item[String(column.colKey)] = field ? cellText(row, field) : ''
    })
    return item
  })),
)

/** 非树形直接返回平铺数据；树形按 `parent` 关联把平铺数据拼成嵌套结构。 */
function buildTree(items: Record<string, unknown>[]): Record<string, unknown>[] {
  if (!isTree) return items
  const byId = new Map(items.map((item) => [String(item.id), item]))
  const roots: Record<string, unknown>[] = []
  items.forEach((item) => {
    const parentId = relationshipIds(item.__row as ResourceRow, 'parent')[0]
    const parent = parentId ? byId.get(parentId) : undefined
    if (parent && parent !== item) {
      const children = (parent.children as Record<string, unknown>[] | undefined) ?? []
      children.push(item)
      parent.children = children
    } else {
      roots.push(item)
    }
  })
  return roots
}

const currentAppId = computed(() => String(filterValues.app || ''))

function labelOf(row: ResourceRow | undefined, fields: string[]): string {
  if (!row) return ''
  return fields
    .map((name) => attributeText(row.attributes[name]))
    .filter((text) => text.length > 0)
    .join(' ')
}

function cellText(row: ResourceRow, field: FieldSchema): string {
  const cell = field.cell
  if (cell && (cell.type === 'join' || cell.type === 'flags')) {
    const parts = (cell.fields || []).map((name) => ({
      name,
      value: displayValue(row, name),
    }))
    if (cell.type === 'flags') {
      return parts
        .filter((part) => part.value === true || part.value === 'true')
        .map((part) => cell.labels?.[part.name] || part.name)
        .join(' ')
    }
    return parts
      .map((part) => attributeText(part.value))
      .filter((text) => text.length > 0)
      .join(cell.separator || '')
  }
  // 图标 + 文本：列值取模板（不含图标），排序/导出/复制都拿到可读文本。
  if (cell && cell.type === 'iconText') {
    return cell.template ? fillTemplate(cell.template, row) : attributeText(fieldValue(row, field))
  }
  // 一组小图标：列值取各图标项的 title（功能名），便于导出。
  if (cell && cell.type === 'icons') {
    return iconItems(row, field, cell)
      .map((item) => item.title)
      .filter((title) => title.length > 0)
      .join(' ')
  }
  // 关联集合逐条套模板：如群集的「服务」→ `webapp(web33:9480)`（原 farm/list.ftl）。
  if (cell && cell.type === 'refItems') {
    return refItemTexts(row, field, cell).join(cell.separator || ' ')
  }
  // 枚举字段列表里显示的是选项文案（如 1/2/3 → Noarch/X86_64/AArch64），不是裸 id。
  if (field.type === 'select' && field.options) {
    const value = fieldValue(row, field)
    const matched = field.options.find((option) => String(option.value) === String(value))
    if (matched) return matched.label
  }
  if (field.type === 'ref' || field.type === 'refs') {
    const ref = field.ref
    if (!ref) return ''
    return relationshipIds(row, field.refKey || field.key)
      .map((id) => labelOf(includedIndex.value.get(`${ref.type}:${id}`), ref.labelFields))
      .filter((text) => text.length > 0)
      .join(', ')
  }
  const text = attributeText(valueAt(row.attributes, field.path || [field.key]))
  return cell && cell.suffix && text ? `${text}${cell.suffix}` : text
}

/** 字段原始取值（属性路径优先，支持 `a.b` 嵌套）。 */
function fieldValue(row: ResourceRow, field: FieldSchema): unknown {
  return valueAt(row.attributes, field.path || [field.key])
}

/** 数组属性里的图标项（`icons` 单元格）：`[{logo, name}, ...]`。 */
function iconItems(row: ResourceRow, field: FieldSchema, cell: NonNullable<FieldSchema['cell']>): { icon: string; title: string }[] {
  const raw = fieldValue(row, field)
  if (!Array.isArray(raw)) return []
  return raw
    .filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === 'object')
    .map((item) => ({
      icon: attributeText(item[cell.iconField || 'logo']),
      title: attributeText(item[cell.titleField || 'name']),
    }))
    .filter((item) => item.icon.length > 0)
}

/**
 * `refItems` 单元格逐条内容：按条目名称排序后套 `itemTemplate` / `itemMutedTemplate`。
 * 关联行取自 `included`（需在 `cell.include` 里声明嵌套路径，如 `servers.host`）。
 */
function refItemParts(
  row: ResourceRow,
  field: FieldSchema,
  cell: NonNullable<FieldSchema['cell']>,
): { main: string; muted: string }[] {
  const template = cell.itemTemplate
  if (!template && !cell.itemMutedTemplate) return []
  const parts = relationshipTargets(row, field.refKey || field.key)
    .map((target) => includedIndex.value.get(`${target.type}:${target.id}`))
    .filter((item): item is ResourceRow => Boolean(item))

  // 这里运行在表格单元格的 render 中，不能原地排序响应式数组，否则会再次触发
  // 当前 TR 的更新并形成递归。先复制成普通数组再排序。
  return Array.from(parts)
    .sort((a, b) => attributeText(a.attributes.name).localeCompare(attributeText(b.attributes.name)))
    .map((item) => ({
      main: template ? fillTemplate(template, item) : '',
      muted: cell.itemMutedTemplate ? fillTemplate(cell.itemMutedTemplate, item) : '',
    }))
    .filter((part) => part.main.length > 0 || part.muted.length > 0)
}

/** `refItems` 的纯文本形式（排序/导出/复制用）。 */
function refItemTexts(row: ResourceRow, field: FieldSchema, cell: NonNullable<FieldSchema['cell']>): string[] {
  return refItemParts(row, field, cell).map((part) => `${part.main}${part.muted}`)
}

/** 取展示值：优先属性路径（支持 `a.b` 嵌套），否则按「关联.属性」从 included 中取。 */
function displayValue(row: ResourceRow, name: string): unknown {
  if (name === 'id') return row.id
  const direct = valueAt(row.attributes, name.split('.'))
  if (direct !== undefined) return direct
  const [head, ...rest] = name.split('.')
  const targets = relationshipTargets(row, head)
  if (targets.length === 0) return undefined
  const texts = targets
    // 必须按「类型:id」回取：不同实体类型的 id 会重复，只用 id 会串到别的类型上。
    .map((target) => includedIndex.value.get(`${target.type}:${target.id}`))
    .filter((item): item is ResourceRow => Boolean(item))
    .map((item) => attributeText(valueAt(item.attributes, rest)))
    .filter((text) => text.length > 0)
  return texts.length > 0 ? texts.join(', ') : undefined
}

/** 把 `{attr}` 模板替换成行内取值。 */
function fillTemplate(template: string, row: ResourceRow): string {
  return template.replace(/\{([a-zA-Z0-9_.]+)\}/g, (_match, name: string) => attributeText(displayValue(row, name)))
}

/** 按 schema 的 cell 描述渲染单元格（图片/图标/布尔/连接文本）。 */
function renderCell(field: FieldSchema) {
  const cell = field.cell!
  return (render: typeof h, params: { row: Record<string, unknown> }) => {
    const text = String(params.row[field.key] ?? '')
    const source = params.row.__row as ResourceRow | undefined
    switch (cell.type) {
      case 'image':
        if (!text) return render('span', {})
        return render('img', {
          src: text,
          alt: field.label,
          style: `width:${cell.width || 30}px;height:${cell.height || cell.width || 30}px;object-fit:contain`,
        })
      case 'icon':
        return text ? render('i', { class: text }) : render('span', {})
      case 'text': {
        // 纯文本列：支持内联样式（如 CPU 规格的 0.8em），文本本身已在此前的 cellText 里拼好。
        if (!text) return render('span', {})
        return cell.style ? render('span', { style: cell.style }, text) : render('span', {}, text)
      }
      case 'iconText': {
        if (!source) return render('span', {}, text)
        const icon = cell.iconField ? attributeText(displayValue(source, cell.iconField)) : ''
        const label = cell.template ? fillTemplate(cell.template, source) : text
        const children: ReturnType<typeof render>[] = []
        if (icon) {
          children.push(
            cell.iconKind === 'image'
              ? render('img', {
                  src: icon,
                  alt: label,
                  style: `width:${cell.iconWidth || 30}px;height:${cell.iconHeight || cell.iconWidth || 30}px;object-fit:contain`,
                })
              : render('i', { class: icon }),
          )
        }
        if (label) children.push(render('span', {}, label))
        return render('span', { class: 'cell-icon-text' }, children)
      }
      case 'icons': {
        if (!source) return render('span', {}, text)
        return render(
          'span',
          { class: 'cell-icons' },
          iconItems(source, field, cell).map((item) => render('img', { src: item.icon, alt: item.title, title: item.title })),
        )
      }
      case 'refItems': {
        // 每条关联不折行、横向紧凑排布；次要部分灰色（如群集的「服务」webapp(web33:9480)）。
        if (!source) return render('span', {}, text)
        return render(
          'span',
          { class: 'cell-ref-items' },
          refItemParts(source, field, cell).map((part) =>
            render('span', { class: 'cell-ref-item' }, [
              part.main,
              part.muted ? render('span', { class: 'cell-ref-muted' }, part.muted) : null,
            ]),
          ),
        )
      }
      case 'boolean':
        return render('span', {}, text === '是' || text === 'true' ? cell.trueText || '是' : cell.falseText || '否')
      case 'updatable': {
        if (!source || attributeText(displayValue(source, 'updatable')) !== '是') return render('span', {}, text)
        const latest = attributeText(displayValue(source, 'artifact.latestVersion'))
        return render('span', { title: `可升级至 ${latest}` }, [text, render('span', { class: 'cell-update-arrow' }, ' ↑')])
      }
      case 'link': {
        if (!source) return render('span', {}, text)
        const href = fillTemplate(cell.href || '', source)
        const label = cell.text ? fillTemplate(cell.text, source) : text
        if (!href) return render('span', {}, label)
        if (href.startsWith('/') && !href.startsWith('/api/')) {
          return render(RouterLink, { to: href }, () => label)
        }
        return render('a', { href, target: cell.target || '_blank', rel: 'noopener' }, label)
      }
      default:
        return render('span', {}, text)
    }
  }
}

/** 卡片视图取属性文本。 */
function cellAttr(row: ResourceRow, name: string): string {
  return attributeText(row.attributes[name])
}

/** 卡片视图展示依赖功能名，依赖已在列表 include 中返回。 */
function dependencyNames(row: ResourceRow): string {
  return relationshipIds(row, 'dependencies')
    .map((id) => includedIndex.value.get(`${featureRefType}:${id}`) || includedIndex.value.get(id))
    .map((item) => (item ? attributeText(item.attributes.name) : ''))
    .filter((name) => name.length > 0)
    .join(', ')
}

function valueAt(attributes: Record<string, unknown>, path: string[]): unknown {
  let current: unknown = attributes
  for (const key of path) {
    if (current === null || current === undefined || typeof current !== 'object') return undefined
    current = (current as Record<string, unknown>)[key]
  }
  return current
}

function setAt(target: Record<string, unknown>, path: string[], value: unknown): void {
  let current = target
  path.slice(0, -1).forEach((key) => {
    if (typeof current[key] !== 'object' || current[key] === null) current[key] = {}
    current = current[key] as Record<string, unknown>
  })
  current[path[path.length - 1]] = value
}

function inputType(field: FieldSchema): string {
  if (field.type) return field.type
  return 'text'
}

/** 多行控件在抽屉表单里占满整行（标签在上、两列栅格）。 */
function isWideField(field: FieldSchema): boolean {
  if (field.wide !== undefined) return field.wide
  const type = inputType(field)
  return type === 'textarea' || type === 'lines'
}

function optionsOf(field: FieldSchema): SelectOption[] {
  return optionsCache[field.key] || []
}

/** 查询条件的控件类型：引用/枚举/布尔用下拉，数字用数字框，其余用文本框。 */
function filterControl(field: FieldSchema): 'select' | 'number' | 'text' {
  if (field.type === 'ref' || field.type === 'select' || field.type === 'boolean') return 'select'
  if (field.type === 'number') return 'number'
  return 'text'
}

function filterOptions(field: FieldSchema): SelectOption[] {
  if (field.type === 'boolean') {
    return [
      { label: '启用', value: 'true' },
      { label: '停用', value: 'false' },
    ]
  }
  return field.options || optionsOf(field)
}

function refsOf(): FieldSchema[] {
  return [...formFields, ...filterFields].filter((field) => field.ref && (field.type === 'ref' || field.type === 'refs'))
}

async function loadOptions() {
  const refs = refsOf()
  await Promise.all(
    refs.map(async (field) => {
      const ref = field.ref!
      const key = `${ref.path}#${field.key}`
      if (optionsCache[key]) {
        optionsCache[field.key] = optionsCache[key]
        return
      }
      const result = await listResource(ref.path, { pageSize: 300, sort: ref.sort || ref.labelFields[0] })
      const options = result.rows.map((row) => ({ label: labelOf(row, ref.labelFields) || row.id, value: row.id }))
      optionsCache[key] = options
      optionsCache[field.key] = options
    }),
  )
}

const gridActions = computed<DataGridAction[]>(() => {
  const actions: DataGridAction[] = []
  if (!schema.readOnly) {
    actions.push({ code: 'edit', label: '编辑', selection: 'one', theme: 'primary', icon: EditIcon })
    actions.push({ code: 'delete', label: '删除', selection: 'one', theme: 'danger', icon: DeleteIcon })
  }
  ;(schema.tools || []).forEach((tool) => {
    actions.push({
      code: tool.code,
      label: tool.label,
      selection: tool.selection === 'many' ? 'many' : tool.selection,
      theme: tool.theme || 'default',
    })
  })
  return actions
})

const formVisible = ref(false)
const submitting = ref(false)
/** 打开抽屉时先不显示校验结果；首次提交后再显示（否则新建/编辑一打开就满屏必填红字）。 */
const showErrors = ref(false)
const editingId = ref('')
/** 正在编辑的原始行：抽屉里的关联页入口按行内取值填模板。 */
const editingRow = ref<ResourceRow>()
const formRef = ref<FormInstanceFunctions>()
const form = reactive<Record<string, unknown>>({})
const fileInput = ref<HTMLInputElement>()
const drawerLinks = schema.drawerLinks || []
const cardHint = schema.readOnly ? '' : schema.cardLink ? `查看${schema.title}` : `点击编辑${schema.title}`

const rules = computed<Record<string, FormRule[]>>(() => {
  const result: Record<string, FormRule[]> = {}
  formFields.forEach((field) => {
    const fieldRules: FormRule[] = []
    if (isRequiredField(field))
      fieldRules.push({ required: true, message: `请填写${field.label}` })
    if (field.type === 'number' && (field.min !== undefined || field.max !== undefined)) {
      fieldRules.push({
        validator: (value) => {
          if (value === '' || value === undefined || value === null) return true
          const number = Number(value)
          if (!Number.isFinite(number)) return { result: false, message: `${field.label}必须是数字` }
          if (!Number.isInteger(number)) return { result: false, message: `${field.label}必须是整数` }
          if (field.min !== undefined && number < field.min)
            return { result: false, message: `${field.label}不能小于${field.min}` }
          if (field.max !== undefined && number > field.max)
            return { result: false, message: `${field.label}不能大于${field.max}` }
          return true
        },
      })
    }
    if (fieldRules.length > 0) result[field.key] = fieldRules
  })
  return result
})

/** 静态必填，或 `requiredWhen` 指向的布尔字段为真时必填。 */
function isRequiredField(field: FieldSchema): boolean {
  if (field.required) return true
  if (!field.requiredWhen) return false
  const trigger = form[field.requiredWhen]
  if (field.requiredWhenValue !== undefined) {
    if (trigger !== field.requiredWhenValue) return false
  } else if (!Boolean(trigger)) {
    return false
  }
  if (!field.preserveWhenSet) return true
  const existing = editingRow.value
    ? valueAt(editingRow.value.attributes, [field.preserveWhenSet])
    : undefined
  return existing !== true && existing !== 'true'
}

function listInclude(): string[] {
  const refs = [...schema.fields, ...filterFields]
    .filter((field) => field.ref)
    .map((field) => field.refKey || field.key)
  // 单元格模板会读关联内部的属性（如服务的 `{host.name}`），需要一并声明嵌套 include。
  const nested = schema.fields.flatMap((field) => field.cell?.include || [])
  return [...new Set([...refs, ...nested])]
}

function listFilters(): Record<string, string> {
  const filters: Record<string, string> = {}
  filterFields.forEach((field) => {
    const value = filterValues[field.key]
    if (value === '' || value === null || value === undefined) return
    const attr = field.filterKey || (field.type === 'ref' ? `${field.key}.id` : field.key)
    // 后端按「实体别名.属性」解析 filter，别名即实体类简单名（见 EntityAction.simpleEntityName）。
    filters[`${schema.alias}.${attr}`] = String(value)
    // 必填引用查询条件（如菜单管理的应用）记住选中值，下次进页面自动带上。
    if (field.required && field.type === 'ref') rememberFilterValue(schema.key, field.key, value)
    // 以配置为工作域的资源：查询时把选中的配置记为「当前配置」（空值不覆盖）。
    if (isProjectRef(field)) rememberProject(value)
  })
  return filters
}

/**
 * 打开页面时把查询条件里的「配置」填成记忆值（URL 显式给出的查询条件优先）。
 * 需在 loadOptions 之后调用：记忆的配置可能已被删除，此时丢弃记忆，避免下拉框显示一个裸 id。
 */
function applyCurrentProject() {
  if (!projectFilter) return
  const options = optionsCache[projectFilter.key]
  if (currentProjectId.value !== '' && options?.length && !options.some((option) => projectId(option.value) === currentProjectId.value)) {
    forgetProject()
  }
  if (projectId(filterValues[projectFilter.key]) === '' && currentProjectId.value !== '') {
    filterValues[projectFilter.key] = currentProjectId.value
  }
}

/**
 * 必填引用查询条件（菜单管理的「应用」）补默认值：URL 显式给出的查询条件优先，
 * 否则取上次记住的值（仍在下拉选项里才算数），只有唯一选项时直接用。都取不到就留空，等用户选。
 * 需在 loadOptions 之后调用：记忆的应用可能已被删除，此时丢弃记忆。
 */
function applyDefaultRequiredFilters() {
  filterFields.forEach((field) => {
    if (!field.required) return
    if (filterValueFilled(filterValues[field.key])) {
      rememberFilterValue(schema.key, field.key, filterValues[field.key])
      return
    }
    const options = optionsCache[field.key] || []
    const remembered = rememberedFilterValue(schema.key, field.key)
    if (remembered !== '' && options.some((option) => String(option.value) === remembered)) {
      filterValues[field.key] = remembered
      return
    }
    if (options.length === 1) filterValues[field.key] = options[0].value
  })
}

async function loadRows() {
  // 必填查询条件为空：不查列表（原菜单页先选应用再 load），清空上一次的结果。
  if (missingRequiredFilters.value.length > 0) {
    rows.value = []
    includedIndex.value = indexIncluded([])
    pagination.total = 0
    if (isTree) treeRevision.value += 1
    return
  }
  loading.value = true
  try {
    const result = await listResource(schema.path, {
      pageNumber: pagination.current,
      pageSize: isTree ? 1000 : pagination.pageSize,
      sort: sort.value,
      include: listInclude(),
      filters: listFilters(),
    })
    rows.value = result.rows
    includedIndex.value = indexIncluded(result.included)
    pagination.total = result.page.total
    if (isTree) treeRevision.value += 1
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : `加载${schema.title}失败`)
  } finally {
    loading.value = false
  }
}

function reload() {
  pagination.current = 1
  void loadRows()
}

function onPageChange(page: PageInfo) {
  pagination.current = page.current
  pagination.pageSize = page.pageSize
  void loadRows()
}

function onSortChange(next: string) {
  sort.value = next
  reload()
}

function defaultFormValue(field: FieldSchema): unknown {
  if (field.defaultValue !== undefined) return field.defaultValue
  switch (inputType(field)) {
    case 'refs':
      return []
    case 'boolean':
      return field.key === 'enabled' || field.key === 'resolveSupport'
    case 'number':
      return undefined
    default:
      return ''
  }
}

/**
 * 新建表单里引用字段的默认值：同一 key 的查询条件若已选中某个引用值，就直接用它。
 * 只认单选 `ref`；`refs`（多选）与文本框同名的查询条件不参与，避免歧义。
 */
function seedFromFilter(field: FieldSchema): string | undefined {
  const filter = filterFields.find((candidate) => candidate.key === field.key && candidate.type === 'ref')
  const value = filter ? filterValues[filter.key] : undefined
  return typeof value === 'string' && value.length > 0 ? value : undefined
}

function resetForm(row?: ResourceRow) {
  formFields.forEach((field) => {
    if (!row) {
      // 以配置为工作域的资源：新建时配置默认取「当前配置」（原 UI 用隐藏域锁定在记忆的配置上）。
      if (projectScoped && isProjectRef(field)) {
        form[field.key] = currentProjectId.value
        return
      }
      // 从属页面（如 /config/servers?farm=1）：新建时父对象取查询条件里的值
      // （原 UI 用隐藏域把父对象锁在 URL 传来的 id 上，如 server.farm.id）。
      const seeded = seedFromFilter(field)
      if (seeded !== undefined) {
        form[field.key] = seeded
        return
      }
      form[field.key] = defaultFormValue(field)
      return
    }
    if (field.type === 'ref') {
      form[field.key] = relationshipIds(row, field.key)[0] || ''
    } else if (field.type === 'refs') {
      form[field.key] = relationshipIds(row, field.key)
    } else if (field.deriveValue) {
      form[field.key] = field.deriveValue(row.attributes)
    } else if (field.type === 'boolean') {
      form[field.key] = Boolean(valueAt(row.attributes, field.path || [field.key]))
    } else if (field.type === 'lines') {
      const value = valueAt(row.attributes, field.path || [field.key])
      form[field.key] = Array.isArray(value) ? value.join('\n') : value == null ? '' : String(value)
    } else if (field.secret) {
      form[field.key] = ''
    } else {
      const value = valueAt(row.attributes, field.path || [field.key])
      form[field.key] = value === null || value === undefined ? '' : value
    }
  })
}

function onFieldChange(field: FieldSchema, value: unknown) {
  field.onChange?.(value, form)
}

async function openForm() {
  showErrors.value = false
  formVisible.value = true
  await nextTick()
  formRef.value?.clearValidate()
}

function openCreate() {
  editingId.value = ''
  editingRow.value = undefined
  resetForm()
  void openForm()
}

/** 卡片墙的落点：`cardLink` 模板（如平台功能 → 详情页）优先，否则打开编辑抽屉。 */
function openCard(row: ResourceRow) {
  if (schema.cardLink) {
    void router.push(fillTemplate(schema.cardLink, row))
    return
  }
  openEdit(row)
}

function openEdit(row: ResourceRow) {
  editingId.value = row.id
  editingRow.value = row
  resetForm(row)
  void openForm()
}

/** 抽屉里的关联页入口：关掉抽屉再跳到目标页（如群集 → /config/servers?farm=<id>）。 */
function openDrawerLink(link: DrawerLinkSchema) {
  if (!editingRow.value) return
  const to = fillTemplate(link.to, editingRow.value)
  formVisible.value = false
  void router.push(to)
}

function selectedRows(payload: { selectedRows: Record<string, unknown>[] }): ResourceRow[] {
  const ids = new Set(payload.selectedRows.map((row) => String(row.id)))
  return rows.value.filter((row) => ids.has(row.id))
}

function onGridAction(payload: { action: DataGridAction; selectedRows: Record<string, unknown>[] }) {
  const selected = selectedRows(payload)
  const tool = (schema.tools || []).find((candidate) => candidate.code === payload.action.code)
  if (payload.action.code === 'edit' && selected[0]) {
    openEdit(selected[0])
  } else if (payload.action.code === 'delete' && selected[0]) {
    confirmRemove(selected[0])
  } else if (tool) {
    confirmTool(tool.code, tool.label, tool.confirm, selected)
  }
}

function confirmRemove(row: ResourceRow) {
  const dialog = DialogPlugin.confirm({
    header: '删除确认',
    body: `确定删除所选${schema.title}记录？`,
    onConfirm: async () => {
      try {
        await removeResource(schema.path, row.id)
        MessagePlugin.success('删除成功')
        dialog.destroy()
        await loadRows()
      } catch (error) {
        MessagePlugin.error(error instanceof Error ? error.message : '删除失败')
      }
    },
  })
}

function confirmTool(code: string, label: string, confirm: string | undefined, selected: ResourceRow[]) {
  const tool = (schema.tools || []).find((candidate) => candidate.code === code)
  const dialog = DialogPlugin.confirm({
    header: label,
    body: confirm || `确定执行${label}？`,
    onConfirm: async () => {
      try {
        await callResourceAction(schema.path, tool?.action || code, selected.map((row) => row.id))
        MessagePlugin.success(`${label}已完成`)
        dialog.destroy()
        await loadRows()
      } catch (error) {
        MessagePlugin.error(error instanceof Error ? error.message : `${label}失败`)
      }
    },
  })
}

async function submitForm(): Promise<boolean> {
  showErrors.value = true
  const valid = await formRef.value?.validate()
  if (valid !== true) return false

  submitting.value = true
  try {
    const { attributes, relationships } = buildPayload()
    await saveResource(schema.path, schema.type, attributes, relationships, editingId.value || undefined)
    MessagePlugin.success(editingId.value ? '保存成功' : '创建成功')
    formVisible.value = false
    await loadRows()
    return true
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '保存失败')
    return false
  } finally {
    submitting.value = false
  }
}

function buildPayload(): { attributes: Record<string, unknown>; relationships: Record<string, unknown> } {
  const attributes: Record<string, unknown> = {}
  const relationships: Record<string, unknown> = {}

  formFields.forEach((field) => {
    if (field.virtual) return
    const path = field.path || [field.key]
    const raw = form[field.key]

    if (field.type === 'ref') {
      relationships[field.key] = { data: raw ? { type: field.ref!.type, id: String(raw) } : null }
      return
    }
    if (field.type === 'refs') {
      const ids = Array.isArray(raw) ? (raw as string[]) : []
      relationships[field.key] = { data: ids.map((id) => ({ type: field.ref!.type, id: String(id) })) }
      return
    }
    if (field.type === 'boolean') {
      setAt(attributes, path, Boolean(raw))
      return
    }
    if (field.type === 'lines') {
      const lines = String(raw ?? '')
        .split('\n')
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
      setAt(attributes, path, lines.join('\n'))
      return
    }
    if (field.type === 'number') {
      if (raw === '' || raw === undefined || raw === null) {
        if (field.required) setAt(attributes, path, 0)
        else if (field.nullable) setAt(attributes, path, null)
        return
      }
      setAt(attributes, path, Number(raw))
      return
    }
    const text = String(raw ?? '').trim()
    if (text.length === 0) return
    setAt(attributes, path, text)
  })

  return { attributes, relationships }
}

/** 导出当前列表为 CSV（带 BOM，Excel 直接打开不乱码）。 */
function exportCsv() {
  const header = columns.map((column) => csvCell(String(column.title ?? ''))).join(',')
  const body = rows.value
    .map((row) =>
      columns
        .map((column) => {
          const field = schema.fields.find((candidate) => candidate.key === column.colKey)
          return csvCell(field ? cellText(row, field) : '')
        })
        .join(','),
    )
    .join('\r\n')
  const blob = new Blob([`\uFEFF${header}\r\n${body}\r\n`], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = window.document.createElement('a')
  link.href = url
  link.download = `${schema.key}.csv`
  link.click()
  URL.revokeObjectURL(url)
}

function csvCell(value: string): string {
  return /[",\r\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value
}

async function exportXml() {
  try {
    const payload = await getPlainJson<{ xml?: string }>(apiPath('ems', `${schema.path}/export`), {
      app: currentAppId.value,
    })
    const blob = new Blob([payload.xml || ''], { type: 'application/xml' })
    const url = URL.createObjectURL(blob)
    const link = window.document.createElement('a')
    link.href = url
    link.download = `${schema.key}.xml`
    link.click()
    URL.revokeObjectURL(url)
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '导出失败')
  }
}

function triggerImport() {
  fileInput.value?.click()
}

async function importXml(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file || !currentAppId.value) return
  const data = new FormData()
  data.append('app', currentAppId.value)
  data.append('menufile', file)
  try {
    await uploadResourceFile(`${schema.path}/import`, data)
    MessagePlugin.success('导入成功')
    await loadRows()
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '导入失败')
  } finally {
    input.value = ''
  }
}

onMounted(async () => {
  filterFields.forEach((field) => {
    const value = route.query[field.key]
    if (typeof value === 'string' && value.length > 0) filterValues[field.key] = value
  })
  // 宿主/门户下发的当前配置优先（参数名沿用 ems-app 的 EMS_URL_PARAMS.contextProjectId）。
  const contextProject = projectId(route.query.contextProjectId)
  if (contextProject !== '') rememberProject(contextProject)
  try {
    await loadOptions()
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '加载选项失败')
  }
  applyCurrentProject()
  applyDefaultRequiredFilters()
  await loadRows()
  // /menus?app=xx&action=export：从「应用」列表的导出链接直接落到菜单页并下载 XML。
  if (schema.xmlTools && route.query.action === 'export' && currentAppId.value) {
    await exportXml()
  }
})
</script>

<style scoped>
.page-actions {
  display: flex;
  gap: 8px;
}

.hidden-file {
  display: none;
}

.drawer-links {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid var(--td-component-stroke);
}

.drawer-links__label {
  color: var(--td-text-color-secondary);
  font-size: 13px;
}

.card-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  gap: 16px;
  align-content: start;
}

.card-grid__empty {
  color: var(--td-text-color-placeholder);
}

.feature-card {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 16px;
  border: 1px solid var(--td-component-border);
  border-radius: 6px;
  background: var(--td-bg-color-container);
  cursor: pointer;
  transition: box-shadow 0.2s;
}

.feature-card:hover {
  box-shadow: var(--td-shadow-2);
}

.feature-card__top {
  display: flex;
  align-items: center;
  gap: 12px;
}

.feature-card__logo {
  width: 60px;
  height: 60px;
  flex: 0 0 auto;
  object-fit: contain;
}

.feature-card__head {
  display: flex;
  align-items: baseline;
  gap: 8px;
}

.feature-card__name {
  font-size: 15px;
  font-weight: 600;
}

.feature-card__version {
  color: var(--td-text-color-secondary);
  font-size: 12px;
}

.feature-card__desc {
  margin: 0;
  min-height: 4.3em;
  overflow: hidden;
  color: var(--td-text-color-secondary);
  font-size: 13px;
  line-height: 1.4;
}

.feature-card__foot {
  display: flex;
  justify-content: space-between;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}
</style>
