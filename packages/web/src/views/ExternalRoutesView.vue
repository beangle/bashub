<template>
  <section class="page-panel">
    <div class="page-head">
      <div class="detail-heading">
        <div class="title-row">
          <h2 class="page-title">外部路由</h2>
          <router-link class="title-back" :to="projectPath">← 返回代理详情</router-link>
        </div>
        <p class="page-subtitle">{{ projectName ? `${projectName} · ` : '' }}把 PATH 前缀代理到独立系统的 host:port</p>
      </div>
      <div class="page-actions">
        <t-button theme="primary" @click="openCreate">新增外部路由</t-button>
      </div>
    </div>

    <t-alert v-if="error" theme="error" :message="error" class="page-alert" />

    <t-loading :loading="loading" show-overlay>
      <div class="route-card">
        <table v-if="routes.length" class="route-table">
          <thead>
            <tr>
              <th>路径</th>
              <th>目标</th>
              <th>说明</th>
              <th>代理点</th>
              <th>状态</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="route in routes" :key="route.id">
              <td><code>{{ attr(route, 'path') }}</code></td>
              <td><code>{{ attr(route, 'target') }}</code></td>
              <td>{{ attr(route, 'description') || '—' }}</td>
              <td>{{ endpointName(route) || '—' }}</td>
              <td>
                <t-tag size="small" :theme="enabled(route) ? 'success' : 'default'" variant="light">
                  {{ enabled(route) ? '启用' : '停用' }}
                </t-tag>
              </td>
              <td class="route-actions">
                <t-button size="small" variant="text" @click="openEdit(route)">编辑</t-button>
                <t-button size="small" variant="text" theme="danger" @click="remove(route)">删除</t-button>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else class="empty-text">还没有外部路由。添加后，代理配置会把它写入 HAProxy map / Nginx location。</p>
      </div>
    </t-loading>

    <t-drawer v-model:visible="formVisible" :header="editingId ? '编辑外部路由' : '新增外部路由'" size="520px">
      <t-form ref="formRef" :data="form" :rules="rules" label-align="top" required-mark-position="right">
        <t-form-item label="路径" name="path" help="必须以 / 开头；HAProxy map_beg 按最长前缀匹配">
          <t-input v-model="form.path" placeholder="例如 /legacy/admin" clearable />
        </t-form-item>
        <t-form-item label="目标地址" name="target" help="host:port，例如 10.10.2.15:8080；IPv6 用 [::1]:8080">
          <t-input v-model="form.target" placeholder="10.10.2.15:8080" clearable />
        </t-form-item>
        <t-form-item label="代理点" name="endpoint">
          <t-select v-model="form.endpoint" :options="endpointOptions" placeholder="选择代理点" filterable />
        </t-form-item>
        <t-form-item label="说明" name="description">
          <t-input v-model="form.description" placeholder="可选" clearable />
        </t-form-item>
        <t-form-item label="启用" name="enabled">
          <t-switch v-model="form.enabled" />
        </t-form-item>
      </t-form>
      <template #footer>
        <div class="drawer-actions">
          <t-button variant="outline" :disabled="saving" @click="formVisible = false">取消</t-button>
          <t-button theme="primary" :loading="saving" @click="submit">保存</t-button>
        </div>
      </template>
    </t-drawer>
  </section>
</template>

<script setup lang="ts">
import { MessagePlugin, type FormInstanceFunctions, type FormRule } from 'tdesign-vue-next'
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

const route = useRoute()
const projectId = String(route.params.id || '')
const projectPath = `/config/projects/${encodeURIComponent(projectId)}?section=proxy`
const routes = ref<ResourceRow[]>([])
const endpoints = ref<ResourceRow[]>([])
const projectName = ref('')
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const formVisible = ref(false)
const editingId = ref('')
const formRef = ref<FormInstanceFunctions>()
const form = reactive({ path: '', target: '', description: '', endpoint: '', enabled: true })
const endpointOptions = computed(() => endpoints.value.map((endpoint) => ({
  label: attributeText(endpoint.attributes.name),
  value: endpoint.id,
})))
const rules: Record<string, FormRule[]> = {
  path: [{ required: true, message: '请填写路径' }],
  target: [{ required: true, message: '请填写目标地址' }],
  endpoint: [{ required: true, message: '请选择代理点' }],
}

function attr(row: ResourceRow, key: string): string {
  return attributeText(row.attributes[key])
}

function enabled(row: ResourceRow): boolean {
  const value = row.attributes.enabled
  return value === undefined || value === true || value === 'true'
}

function endpointName(row: ResourceRow): string {
  const id = relationshipIds(row, 'endpoint')[0] || ''
  const endpoint = endpoints.value.find((item) => item.id === id)
  return endpoint ? attributeText(endpoint.attributes.name) : ''
}

function resetForm() {
  form.path = ''
  form.target = ''
  form.description = ''
  form.endpoint = endpoints.value.length === 1 ? endpoints.value[0].id : ''
  form.enabled = true
}

function openCreate() {
  editingId.value = ''
  resetForm()
  formVisible.value = true
}

function openEdit(row: ResourceRow) {
  editingId.value = row.id
  form.path = attr(row, 'path')
  form.target = attr(row, 'target')
  form.description = attr(row, 'description')
  form.endpoint = relationshipIds(row, 'endpoint')[0] || ''
  form.enabled = enabled(row)
  formVisible.value = true
}

function validTarget(value: string): boolean {
  const trimmed = value.trim()
  if (!trimmed || trimmed.includes('://') || trimmed.includes('/')) return false
  const match = trimmed.startsWith('[')
    ? /^\[[^\]]+\]:(\d+)$/.exec(trimmed)
    : /^([^:]+):(\d+)$/.exec(trimmed)
  if (!match) return false
  const port = Number(trimmed.startsWith('[') ? match[1] : match[2])
  return Number.isInteger(port) && port >= 1 && port <= 65535
}

async function submit() {
  const valid = await formRef.value?.validate()
  if (valid !== true) return
  if (!form.path.trim().startsWith('/') || form.path.trim() === '/') {
    MessagePlugin.error('路径必须以 / 开头，且不能是根路径')
    return
  }
  if (!validTarget(form.target)) {
    MessagePlugin.error('目标地址必须是 host:port')
    return
  }
  saving.value = true
  try {
    await saveResource(
      '/external-routes',
      'externalRoutes',
      {
        path: form.path.trim(),
        target: form.target.trim(),
        description: form.description.trim(),
        enabled: form.enabled,
      },
      {
        project: { data: { type: 'projects', id: projectId } },
        endpoint: { data: { type: 'endpoints', id: form.endpoint } },
      },
      editingId.value || undefined,
    )
    MessagePlugin.success(editingId.value ? '保存成功' : '创建成功')
    formVisible.value = false
    await load()
  } catch (reason) {
    MessagePlugin.error(reason instanceof Error ? reason.message : '保存失败')
  } finally {
    saving.value = false
  }
}

function remove(row: ResourceRow) {
  const path = attr(row, 'path')
  if (!window.confirm(`确定删除外部路由 ${path}？`)) return
  void removeResource('/external-routes', row.id)
    .then(async () => {
      MessagePlugin.success('删除成功')
      await load()
    })
    .catch((reason) => MessagePlugin.error(reason instanceof Error ? reason.message : '删除失败'))
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [project, endpointPage, routePage] = await Promise.all([
      getResource('/projects', projectId),
      listResource('/endpoints', { pageSize: 100, filters: { 'endpoint.project.id': projectId } }),
      listResource('/external-routes', { pageSize: 500, filters: { 'externalRoute.project.id': projectId } }),
    ])
    projectName.value = attributeText(project.attributes.qualifiedName) || attributeText(project.attributes.name)
    endpoints.value = endpointPage.rows
    routes.value = routePage.rows
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : '加载外部路由失败'
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<style scoped>
.page-alert {
  margin: 8px 12px;
}

.route-card {
  margin: 12px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container);
  overflow: hidden;
}

.route-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.route-table th,
.route-table td {
  padding: 8px 12px;
  border-bottom: 1px solid var(--td-component-stroke);
  text-align: left;
  vertical-align: middle;
}

.route-table th {
  color: var(--td-text-color-secondary);
  font-weight: 500;
}

.route-actions {
  white-space: nowrap;
}

.empty-text {
  padding: 36px;
  color: var(--td-text-color-placeholder);
  text-align: center;
}

.drawer-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
</style>
