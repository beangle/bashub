<template>
  <section class="page-panel">
    <div class="page-head">
      <div>
        <router-link class="detail-back" to="/config/org-config?tab=projects">← 返回配置管理</router-link>
        <h2 class="page-title">{{ projectTitle }}</h2>
        <p class="page-subtitle">{{ doc?.project.title || 'Micdn 部署配置' }}</p>
      </div>
      <div class="page-actions">
        <t-button variant="outline" @click="router.push('/micdn/components')">组件目录</t-button>
        <t-button variant="outline" :disabled="!doc" @click="copyXml">复制 XML</t-button>
        <t-button variant="outline" tag="a" :href="downloadUrl" :disabled="!doc">下载 XML</t-button>
        <t-button theme="primary" :loading="saving" :disabled="!doc" @click="save">保存</t-button>
      </div>
    </div>

    <t-loading :loading="loading" show-overlay>
      <UnderlineTabs :tabs="tabs" :model-value="activeTab" @update:model-value="activeTab = $event" />

      <div v-if="doc" class="micdn-content">
        <template v-if="activeTab === 'base'">
          <section class="config-card">
            <header class="config-card__head">
              <div>
                <h3>运行参数</h3>
                <p>对应 micdn.xml 根属性；home 为空时由 micdn 使用 XML 所在目录。</p>
              </div>
            </header>
            <div class="form-grid">
              <label class="form-field">
                <span>监听地址</span>
                <t-input v-model="config.listen" placeholder="0.0.0.0:8888" />
              </label>
              <label class="form-field">
                <span>Home</span>
                <t-input v-model="config.home" placeholder="/var/lib/micdn" />
              </label>
              <label class="form-field">
                <span>日志文件</span>
                <t-input v-model="config.logFile" placeholder="console" />
              </label>
              <label class="form-field">
                <span>日志级别</span>
                <t-select v-model="config.logLevel" :options="logLevelOptions" />
              </label>
            </div>
          </section>
        </template>

        <template v-else-if="activeTab === 'servers'">
          <section class="config-card">
            <header class="config-card__head">
              <div>
                <h3>Micdn 服务器</h3>
                <p>
                  登记运行 micdn 的节点。每台服务器的 setline <code>adminListen</code> 会写入
                  bashub 的 peers 配置，侧车从 <code>http://&lt;adminListen&gt;/_setline/routes</code>
                  读取路由表。
                </p>
              </div>
              <t-button variant="outline" @click="addServer">添加服务器</t-button>
            </header>
            <div v-if="config.servers.length === 0" class="server-empty">
              尚未登记 micdn 服务器。setline peers 只包含现有 web 节点。
            </div>
            <table v-else class="server-table">
              <thead>
                <tr>
                  <th>名称</th>
                  <th>Setline adminListen</th>
                  <th class="server-table__action">操作</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(server, index) in config.servers" :key="index">
                  <td>
                    <t-input v-model="server.name" placeholder="cdn01" />
                  </td>
                  <td>
                    <t-input v-model="server.adminListen" placeholder="10.0.0.31:8081" />
                  </td>
                  <td class="server-table__action">
                    <t-button size="small" variant="text" theme="danger" @click="removeServer(index)">移除</t-button>
                  </td>
                </tr>
              </tbody>
            </table>
          </section>
        </template>

        <template v-else-if="activeTab === 'repos'">
          <section class="config-card">
            <header class="config-card__head">
              <div>
                <h3>Maven</h3>
                <p>声明后挂载 <code>/maven</code>；上游按顺序回源，SNAPSHOT 可单独指定。</p>
              </div>
              <t-switch v-model="config.maven.declared" />
            </header>
            <div class="form-grid" :class="{ 'form-grid--muted': !config.maven.declared }">
              <label class="form-field">
                <span>本地目录</span>
                <t-input v-model="config.maven.base" placeholder="留空使用 {home}/maven" />
              </label>
              <label class="form-field">
                <span>SNAPSHOT 上游</span>
                <t-input v-model="config.maven.snapshotRemote" placeholder="可选，完整 URL" />
              </label>
              <label class="form-field form-field--wide">
                <span>正式版上游</span>
                <t-textarea v-model="mavenRemotesText" :autosize="{ minRows: 3 }" placeholder="一行一个 URL，按优先级排序" />
              </label>
            </div>
          </section>

          <section class="config-card">
            <header class="config-card__head">
              <div>
                <h3>NPM</h3>
                <p>声明后挂载 <code>/npm</code>；dev/预发布版本可走独立 registry。</p>
              </div>
              <t-switch v-model="config.npm.declared" />
            </header>
            <div class="form-grid" :class="{ 'form-grid--muted': !config.npm.declared }">
              <label class="form-field">
                <span>本地目录</span>
                <t-input v-model="config.npm.base" placeholder="留空使用 {home}/npm" />
              </label>
              <label class="form-field">
                <span>开发版上游</span>
                <t-input v-model="config.npm.devRemote" placeholder="可选，完整 URL" />
              </label>
              <label class="form-field form-field--wide">
                <span>正式版上游</span>
                <t-textarea v-model="npmRemotesText" :autosize="{ minRows: 3 }" placeholder="一行一个 URL，按优先级排序" />
              </label>
            </div>
          </section>

          <section class="config-card">
            <header class="config-card__head">
              <div>
                <h3>Native</h3>
                <p>声明后挂载 <code>/native</code>，用于分发 tar.gz 与增量补丁。</p>
              </div>
              <t-switch v-model="config.native.declared" />
            </header>
            <div class="form-grid" :class="{ 'form-grid--muted': !config.native.declared }">
              <label class="form-field form-field--wide">
                <span>本地目录</span>
                <t-input v-model="config.native.base" placeholder="留空使用 {home}/native" />
              </label>
            </div>
          </section>
        </template>

        <template v-else-if="activeTab === 'auth'">
          <section class="config-card">
            <header class="config-card__head">
              <div>
                <h3>仓库鉴权</h3>
                <p>同时作用于 maven、npm、native。两个 key 都为空时不生成 auth 段。</p>
              </div>
            </header>
            <div class="form-grid">
              <div class="form-field">
                <span>发布密钥 publish-key</span>
                <t-input
                  v-model="authDraft.publishKey"
                  type="password"
                  :placeholder="config.auth.publishKeySet ? '已设置，留空保持不变' : '未设置'"
                  clearable
                />
                <t-checkbox v-if="config.auth.publishKeySet" v-model="clearPublishKey">清空发布密钥</t-checkbox>
              </div>
              <div class="form-field">
                <span>下载密钥 download-key</span>
                <t-input
                  v-model="authDraft.downloadKey"
                  type="password"
                  :placeholder="config.auth.downloadKeySet ? '已设置，留空保持不变' : '未设置'"
                  clearable
                />
                <t-checkbox v-if="config.auth.downloadKeySet" v-model="clearDownloadKey">清空下载密钥</t-checkbox>
              </div>
              <label class="form-field">
                <span>上传大小上限</span>
                <t-input v-model="config.auth.maxSize" placeholder="64M" />
              </label>
            </div>
          </section>
        </template>

        <template v-else-if="activeTab === 'static'">
          <section class="config-card config-card--compact">
            <div class="form-grid">
              <label class="form-field form-field--wide">
                <span>Static 本地目录</span>
                <t-input v-model="config.static.base" placeholder="留空使用 {home}/asset" />
              </label>
            </div>
          </section>
          <MicdnBindingEditor v-model="bindings" kind="static_bundle" :components="components" />
        </template>

        <template v-else-if="activeTab === 'www'">
          <section class="config-card config-card--compact">
            <div class="form-grid">
              <label class="form-field form-field--wide">
                <span>WWW 本地目录</span>
                <t-input v-model="config.www.base" placeholder="留空使用 {home}/www" />
              </label>
            </div>
          </section>
          <MicdnBindingEditor v-model="bindings" kind="www_doc" :components="components" />
        </template>

        <template v-else-if="activeTab === 'blob'">
          <section class="config-card">
            <header class="config-card__head">
              <div>
                <h3>Blob 存储</h3>
                <p>Project 有 key 时自动生成唯一的 <code>&lt;bucket&gt;</code>；没有 key 时不生成 Blob。</p>
              </div>
            </header>
            <div class="form-grid">
              <div class="form-field">
                <span>Bucket 名称</span>
                <code class="readonly-value">{{ doc.project.name }}</code>
                <small>来自 Project name，不能单独修改。</small>
              </div>
              <div class="form-field">
                <span>Bucket Key</span>
                <code class="readonly-value">{{ doc.project.keyMasked || '未设置' }}</code>
                <small v-if="doc.project.keySet">来自 Project key，仅显示首尾字符。</small>
                <small v-else class="danger-text">当前 Project 没有 key，不会生成 Blob。</small>
              </div>
              <label class="form-field">
                <span>Blob 本地目录</span>
                <t-input v-model="config.blob.base" placeholder="留空使用 {home}/blob；home 为空时为 /blob" />
              </label>
              <label class="form-field">
                <span>上传大小上限</span>
                <t-input v-model="config.blob.maxSize" placeholder="100M" />
              </label>
              <div class="form-field form-field--switch">
                <span>图片公开读取</span>
                <t-switch v-model="config.blob.publicImages" />
              </div>
            </div>
          </section>
        </template>

        <template v-else>
          <section class="preview-card">
            <header class="preview-card__head">
              <div>
                <h3>micdn.xml 预览</h3>
                <p>预览中的密钥已脱敏；保存后自动刷新，下载得到真实配置。</p>
              </div>
              <div class="preview-card__actions">
                <t-button variant="outline" @click="copyXml">复制</t-button>
                <t-button variant="outline" tag="a" :href="downloadUrl">下载</t-button>
              </div>
            </header>
            <pre class="preview-code">{{ doc.xml }}</pre>
          </section>
        </template>
      </div>
    </t-loading>
  </section>
</template>

<script setup lang="ts">
import { UnderlineTabs, type UnderlineTabItem } from '@beangle/bui-vue'
import { MessagePlugin } from 'tdesign-vue-next'
import { computed, onMounted, reactive, ref, toRaw, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import MicdnBindingEditor from '@/components/MicdnBindingEditor.vue'
import {
  defaultMicdnConfig,
  getMicdnProject,
  micdnXmlUrl,
  saveMicdnProject,
  type CdnComponent,
  type MicdnAuthConfig,
  type MicdnBinding,
  type MicdnConfig,
  type MicdnProjectDocument,
} from '@/api/micdn'

const route = useRoute()
const router = useRouter()
const projectId = String(route.params.id || '')

const tabs: UnderlineTabItem[] = [
  { value: 'base', label: '基础' },
  { value: 'servers', label: '服务器' },
  { value: 'repos', label: 'Maven / NPM / Native' },
  { value: 'auth', label: '鉴权' },
  { value: 'static', label: 'Static' },
  { value: 'www', label: 'WWW' },
  { value: 'blob', label: 'Blob' },
  { value: 'preview', label: '预览' },
]

const logLevelOptions = [
  'trace', 'debugv', 'debug-v', 'debug', 'diagnostic', 'verbose',
  'info', 'warn', 'warning', 'error', 'critical', 'fatal',
].map((value) => ({ value, label: value }))

const doc = ref<MicdnProjectDocument>()
const config = ref<MicdnConfig>(defaultMicdnConfig())
const bindings = ref<MicdnBinding[]>([])
const components = ref<CdnComponent[]>([])
const loading = ref(false)
const saving = ref(false)
const mavenRemotesText = ref('')
const npmRemotesText = ref('')
const authDraft = reactive({ publishKey: '', downloadKey: '' })
const clearPublishKey = ref(false)
const clearDownloadKey = ref(false)

function initialTab(): string {
  const value = route.query.tab
  const key = Array.isArray(value) ? value[0] : value
  return key && tabs.some((tab) => tab.value === key) ? key : 'base'
}

const activeTab = ref(initialTab())
const projectTitle = computed(() => doc.value?.project.qualifiedName || doc.value?.project.name || 'Micdn 配置')
const downloadUrl = computed(() => (projectId ? micdnXmlUrl(projectId) : '#'))

watch(activeTab, (value) => {
  if (route.query.tab === value) return
  void router.replace({ path: route.path, query: { ...route.query, tab: value } })
})

function applyDocument(payload: MicdnProjectDocument) {
  doc.value = payload
  config.value = structuredClone(payload.config)
  bindings.value = payload.bindings.map((binding) => ({ ...binding }))
  components.value = payload.components
  mavenRemotesText.value = (payload.config.maven.remotes || []).join('\n')
  npmRemotesText.value = (payload.config.npm.remotes || []).join('\n')
  authDraft.publishKey = ''
  authDraft.downloadKey = ''
  clearPublishKey.value = false
  clearDownloadKey.value = false
}

async function load() {
  loading.value = true
  try {
    applyDocument(await getMicdnProject(projectId))
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '加载 Micdn 配置失败')
  } finally {
    loading.value = false
  }
}

function lines(value: string): string[] {
  return value
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
}

function addServer() {
  const used = new Set(config.value.servers.map((server) => server.name))
  let index = config.value.servers.length + 1
  while (used.has(`cdn${String(index).padStart(2, '0')}`)) index += 1
  config.value.servers.push({
    name: `cdn${String(index).padStart(2, '0')}`,
    adminListen: '',
  })
}

function removeServer(index: number) {
  config.value.servers.splice(index, 1)
}

function outgoingConfig(): MicdnConfig {
  const next = structuredClone(toRaw(config.value))
  next.maven.remotes = lines(mavenRemotesText.value)
  next.npm.remotes = lines(npmRemotesText.value)

  const auth: MicdnAuthConfig = { maxSize: next.auth.maxSize }
  if (clearPublishKey.value) auth.publishKey = ''
  else if (authDraft.publishKey.length > 0) auth.publishKey = authDraft.publishKey
  if (clearDownloadKey.value) auth.downloadKey = ''
  else if (authDraft.downloadKey.length > 0) auth.downloadKey = authDraft.downloadKey
  next.auth = auth
  return next
}

async function save() {
  saving.value = true
  try {
    const payload = await saveMicdnProject(
      projectId,
      outgoingConfig(),
      bindings.value.map((binding) => ({
        componentId: binding.componentId,
        sortno: Number(binding.sortno) || 0,
      })),
    )
    applyDocument(payload)
    MessagePlugin.success('Micdn 配置已保存')
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '保存 Micdn 配置失败')
  } finally {
    saving.value = false
  }
}

async function copyXml() {
  if (!doc.value) return
  try {
    await navigator.clipboard.writeText(doc.value.xml)
    MessagePlugin.success('已复制脱敏后的 micdn.xml')
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '复制失败，请检查浏览器剪贴板权限')
  }
}

onMounted(load)
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

.page-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.micdn-content {
  display: flex;
  flex-direction: column;
  gap: 16px;
  margin-top: 16px;
}

.config-card,
.preview-card {
  border: 1px solid var(--td-component-stroke);
  border-radius: 6px;
  background: var(--td-bg-color-container);
}

.config-card__head,
.preview-card__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 16px;
  border-bottom: 1px solid var(--td-component-stroke);
}

.config-card__head h3,
.preview-card__head h3 {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}

.config-card__head p,
.preview-card__head p {
  margin: 3px 0 0;
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.config-card__head code,
.preview-card__head code {
  padding: 0 3px;
  border-radius: 3px;
  background: var(--td-bg-color-container-hover);
}

.config-card--compact {
  padding: 12px 16px 16px;
}

.config-card--compact .form-grid {
  padding: 0;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px 18px;
  padding: 16px;
}

.form-field {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 6px;
  color: var(--td-text-color-primary);
  font-size: 13px;
}

.form-field > span {
  color: var(--td-text-color-secondary);
  font-size: 13px;
}

.form-field small {
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.server-empty {
  padding: 20px 16px;
  color: var(--td-text-color-placeholder);
  font-size: 13px;
}

.server-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.server-table th,
.server-table td {
  padding: 10px 16px;
  border-bottom: 1px solid var(--td-component-stroke);
  text-align: left;
  vertical-align: middle;
}

.server-table th {
  color: var(--td-text-color-secondary);
  font-weight: 500;
}

.server-table tr:last-child td {
  border-bottom: 0;
}

.server-table__action {
  width: 80px;
  text-align: right !important;
}

.readonly-value {
  display: block;
  min-height: 32px;
  padding: 6px 10px;
  border: 1px solid var(--td-component-stroke);
  border-radius: 4px;
  background: var(--td-bg-color-container-hover);
  color: var(--td-text-color-primary);
  font-size: 13px;
}

.danger-text {
  color: var(--td-error-color) !important;
}

.form-field--wide {
  grid-column: 1 / -1;
}

.form-grid--muted {
  opacity: 0.62;
}

.preview-card__actions {
  display: flex;
  gap: 8px;
}

.preview-code {
  max-height: calc(100vh - 300px);
  margin: 0;
  padding: 16px;
  overflow: auto;
  border-radius: 0 0 6px 6px;
  background: var(--td-bg-color-container-hover);
  color: var(--td-text-color-primary);
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace;
  font-size: 12px;
  line-height: 1.6;
}

@media (max-width: 860px) {
  .form-grid {
    grid-template-columns: 1fr;
  }

  .form-field--wide {
    grid-column: auto;
  }
}
</style>
