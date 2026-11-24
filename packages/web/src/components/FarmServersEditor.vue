<template>
  <section class="farm-servers">
    <header class="farm-servers__head">
      <div>
        <h4>服务</h4>
        <p>群集内的服务直接在这里维护，不再跳到独立页面。</p>
      </div>
      <t-button size="small" theme="primary" variant="outline" :disabled="!farmId" @click="openCreate">
        新增服务
      </t-button>
    </header>

    <p v-if="error" class="farm-servers__error">{{ error }}</p>
    <table v-else-if="rows.length > 0" class="farm-servers__table">
      <thead>
        <tr>
          <th>名称</th>
          <th>主机</th>
          <th>HTTP</th>
          <th>堆上限</th>
          <th>自启</th>
          <th>HAProxy 参数</th>
          <th />
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in rows" :key="row.id">
          <td><strong>{{ text(row.attributes.name) || '—' }}</strong></td>
          <td>{{ hostLabel(row) }}</td>
          <td>{{ text(row.attributes.httpPort) || '—' }}</td>
          <td>{{ text(row.attributes.maxHeapSize) || '0' }}</td>
          <td>{{ row.attributes.autoStart === true ? '是' : '否' }}</td>
          <td class="farm-servers__options">{{ text(row.attributes.proxyOptions) || '—' }}</td>
          <td class="farm-servers__actions">
            <t-button size="small" variant="text" theme="primary" @click="openEdit(row)">编辑</t-button>
            <t-button size="small" variant="text" theme="danger" @click="remove(row)">删除</t-button>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-else-if="!loading" class="farm-servers__empty">该群集还没有服务。</p>

    <t-dialog v-model:visible="dialogVisible" :header="editingId ? '编辑服务' : '新增服务'" width="560px" :confirm-btn="{ loading: saving }" @confirm="save">
      <div class="servers-form">
        <label><span>名称</span><t-input v-model="draft.name" placeholder="服务名" /></label>
        <label><span>主机</span>
          <t-select v-model="draft.host" :options="hostOptions" filterable placeholder="当前 Project 的主机" />
        </label>
        <label><span>HTTP 端口</span><t-input-number v-model="draft.httpPort" theme="normal" style="width: 100%" /></label>
        <label><span>堆上限(MB)</span><t-input-number v-model="draft.maxHeapSize" :min="0" theme="normal" style="width: 100%" /></label>
        <label class="servers-form__switch"><span>开机自启</span><t-switch v-model="draft.autoStart" /></label>
        <label class="servers-form__wide"><span>HAProxy 服务器参数</span>
          <t-textarea v-model="draft.proxyOptions" :autosize="{ minRows: 2, maxRows: 4 }" placeholder="例如 check inter 5s、weight 10" />
        </label>
      </div>
    </t-dialog>
  </section>
</template>

<script setup lang="ts">
import { DialogPlugin, MessagePlugin } from 'tdesign-vue-next'
import { computed, onMounted, reactive, ref, watch } from 'vue'
import {
  attributeText,
  listResource,
  relationshipIds,
  removeResource,
  saveResource,
  type ResourceRow,
} from '@/api/resource'

const props = defineProps<{ farmId: string; projectId: string }>()

const rows = ref<ResourceRow[]>([])
const hosts = ref<ResourceRow[]>([])
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const dialogVisible = ref(false)
const editingId = ref('')
const draft = reactive({
  name: '',
  host: '',
  httpPort: 0,
  maxHeapSize: 0,
  autoStart: false,
  proxyOptions: '',
})

const hostOptions = computed(() => hosts.value.map((host) => ({
  value: host.id,
  label: `${attributeText(host.attributes.name)} (${attributeText(host.attributes.ip)})`,
})))

function text(value: unknown): string {
  return attributeText(value)
}

function hostLabel(row: ResourceRow): string {
  const id = relationshipIds(row, 'host')[0]
  const host = hosts.value.find((item) => item.id === id)
  return host ? `${attributeText(host.attributes.name)} (${attributeText(host.attributes.ip)})` : '—'
}

async function load() {
  if (!props.farmId) return
  loading.value = true
  error.value = ''
  try {
    const [serverPage, hostPage] = await Promise.all([
      listResource('/servers', { filters: { 'server.farm.id': props.farmId }, pageSize: 500, sort: 'name' }),
      listResource('/hosts', {
        filters: props.projectId ? { 'host.project.id': props.projectId } : undefined,
        pageSize: 500,
        sort: 'name',
      }),
    ])
    rows.value = serverPage.rows
    hosts.value = hostPage.rows
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : '加载服务失败'
  } finally {
    loading.value = false
  }
}

function openCreate() {
  editingId.value = ''
  Object.assign(draft, {
    name: '',
    host: hosts.value.length === 1 ? hosts.value[0].id : '',
    httpPort: 8080,
    maxHeapSize: 0,
    autoStart: false,
    proxyOptions: '',
  })
  dialogVisible.value = true
}

function openEdit(row: ResourceRow) {
  editingId.value = row.id
  Object.assign(draft, {
    name: text(row.attributes.name),
    host: relationshipIds(row, 'host')[0] || '',
    httpPort: Number(row.attributes.httpPort ?? 0),
    maxHeapSize: Number(row.attributes.maxHeapSize ?? 0),
    autoStart: row.attributes.autoStart === true,
    proxyOptions: text(row.attributes.proxyOptions),
  })
  dialogVisible.value = true
}

async function save() {
  if (!draft.name.trim() || !draft.host) {
    MessagePlugin.error('请填写服务名称并选择主机')
    return
  }
  saving.value = true
  try {
    await saveResource('/servers', 'servers', {
      name: draft.name.trim(),
      httpPort: draft.httpPort,
      maxHeapSize: draft.maxHeapSize,
      autoStart: draft.autoStart,
      proxyOptions: draft.proxyOptions,
    }, {
      farm: { data: { type: 'farms', id: props.farmId } },
      host: { data: { type: 'hosts', id: draft.host } },
    }, editingId.value || undefined)
    dialogVisible.value = false
    await load()
    MessagePlugin.success(editingId.value ? '服务已保存' : '服务已创建')
  } catch (reason) {
    MessagePlugin.error(reason instanceof Error ? reason.message : '保存服务失败')
  } finally {
    saving.value = false
  }
}

function remove(row: ResourceRow) {
  const dialog = DialogPlugin.confirm({
    header: '删除服务',
    body: `确认删除 ${text(row.attributes.name)}？`,
    onConfirm: async () => {
      try {
        await removeResource('/servers', row.id)
        dialog.destroy()
        await load()
        MessagePlugin.success('服务已删除')
      } catch (reason) {
        MessagePlugin.error(reason instanceof Error ? reason.message : '删除服务失败')
      }
    },
  })
}

onMounted(load)
watch(() => [props.farmId, props.projectId], load)
</script>

<style scoped>
.farm-servers {
  margin-top: 18px;
  padding-top: 14px;
  border-top: 1px solid var(--td-component-stroke);
}

.farm-servers__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 10px;
}

.farm-servers__head h4 {
  margin: 0;
  font-size: 14px;
}

.farm-servers__head p {
  margin: 3px 0 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.farm-servers__table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.farm-servers__table th,
.farm-servers__table td {
  padding: 7px 8px;
  border-bottom: 1px solid var(--td-component-stroke);
  text-align: left;
  vertical-align: middle;
}

.farm-servers__table th {
  color: var(--td-text-color-placeholder);
  font-weight: 500;
  white-space: nowrap;
}

.farm-servers__options {
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.farm-servers__actions {
  text-align: right !important;
  white-space: nowrap;
}

.farm-servers__error {
  color: var(--td-error-color);
  font-size: 12px;
}

.farm-servers__empty {
  margin: 0;
  padding: 10px 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.servers-form {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px 16px;
}

.servers-form label {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 5px;
  color: var(--td-text-color-secondary);
  font-size: 12px;
}

.servers-form label.servers-form__switch {
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
  gap: 8px;
}

.servers-form__switch .t-switch {
  flex: none;
}

.servers-form__wide {
  grid-column: 1 / -1;
}
</style>
