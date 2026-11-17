<template>
  <section class="page-panel">
    <div class="page-head">
      <div>
        <router-link class="detail-back" :to="listPath">← 返回组件管理</router-link>
        <h2 class="page-title">{{ artifactName || '组件详情' }}</h2>
        <p class="page-subtitle">{{ artifactGav || '可部署的 jar/war 构件' }}</p>
      </div>
      <t-button variant="outline" @click="router.push(listPath)">返回列表</t-button>
    </div>

    <t-loading :loading="loading" show-overlay>
      <div v-if="artifact" class="detail-stack">
        <article class="detail-card">
          <header class="detail-card__head">
            <div>
              <h4>基本信息</h4>
              <p>构件定义与默认部署参数。</p>
            </div>
          </header>
          <div class="fact-grid">
            <div class="fact"><span>标题</span><strong>{{ attributeText(artifact.attributes.title) || '—' }}</strong></div>
            <div class="fact"><span>artifactId</span><strong><code>{{ attributeText(artifact.attributes.artifactId) || '—' }}</code></strong></div>
            <div class="fact"><span>groupId</span><strong><code>{{ attributeText(artifact.attributes.groupId) || '—' }}</code></strong></div>
            <div class="fact"><span>最新版本</span><strong>{{ attributeText(artifact.attributes.latestVersion) || '—' }}</strong></div>
            <div class="fact"><span>打包类型</span><strong>{{ attributeText(artifact.attributes.packaging) || '—' }}</strong></div>
            <div class="fact"><span>部署上下文</span><strong><code>{{ attributeText(artifact.attributes.contextPath) || '—' }}</code></strong></div>
            <div class="fact"><span>面向平台</span><strong>{{ archLabel }}</strong></div>
            <div class="fact"><span>默认项目</span><strong>{{ projectLabel }}</strong></div>
            <div class="fact"><span>可执行文件</span><strong><code>{{ attributeText(artifact.attributes.exec) || '—' }}</code></strong></div>
          </div>
        </article>

        <article class="detail-card">
          <header class="detail-card__head">
            <div>
              <h4>部署情况</h4>
              <p>每个 Project 的实际版本、context path 和对外 URL。</p>
            </div>
            <t-tag variant="light">{{ webapps.length }} 个部署</t-tag>
          </header>
          <table v-if="webapps.length > 0" class="detail-table">
            <thead>
              <tr><th>Logo</th><th>Name</th><th>标题</th><th>部署路径</th></tr>
            </thead>
            <tbody>
              <tr v-for="webapp in webapps" :key="webapp.id">
                <td>
                  <img v-if="projectLogo(webapp)" class="project-logo" :src="projectLogo(webapp)" :alt="projectName(webapp)" />
                  <span v-else class="empty-logo">—</span>
                </td>
                <td>{{ projectName(webapp) }}</td>
                <td>{{ projectTitle(webapp) }}</td>
                <td><code>{{ attributeText(webapp.attributes.contextPath) || '—' }}</code></td>
              </tr>
            </tbody>
          </table>
          <p v-else class="empty-text">尚未在任何 Project 中部署。</p>
        </article>
      </div>
    </t-loading>
  </section>
</template>

<script setup lang="ts">
import { MessagePlugin } from 'tdesign-vue-next'
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { resourceApiPath } from '@/api/prefix'
import {
  attributeText,
  fetchDocument,
  getResourceDetail,
  indexIncluded,
  relationshipIds,
  type ResourceRow,
} from '@/api/resource'

const ARTIFACTS_PATH = '/artifacts'
const ARCH_LABELS: Record<string, string> = { '1': 'Noarch', '2': 'X86_64', '3': 'AArch64' }

const route = useRoute()
const router = useRouter()
const listPath = resourceApiPath(ARTIFACTS_PATH)
const artifactId = String(route.params.id || '')
const loading = ref(false)
const artifact = ref<ResourceRow>()
const webapps = ref<ResourceRow[]>([])
const included = ref<Map<string, ResourceRow>>(new Map())

const artifactName = computed(
  () => attributeText(artifact.value?.attributes.title) || attributeText(artifact.value?.attributes.artifactId),
)
const artifactGav = computed(() => {
  const attrs = artifact.value?.attributes
  if (!attrs) return ''
  const group = attributeText(attrs.groupId)
  const id = attributeText(attrs.artifactId)
  const version = attributeText(attrs.latestVersion)
  return group && id ? `${group}:${id}:${version}` : ''
})
const archLabel = computed(() => {
  const arch = attributeText(artifact.value?.attributes.arch)
  return ARCH_LABELS[arch] || arch || '—'
})
const projectLabel = computed(() => {
  const project = related(artifact.value, 'project', 'projects')
  return project
    ? attributeText(project.attributes.qualifiedName) || attributeText(project.attributes.name)
    : '—'
})

function related(row: ResourceRow | undefined, key: string, type: string): ResourceRow | undefined {
  const id = relationshipIds(row, key)[0]
  return id ? included.value.get(`${type}:${id}`) : undefined
}

function projectOf(webapp: ResourceRow): ResourceRow | undefined {
  return related(webapp, 'project', 'projects')
}

function projectName(webapp: ResourceRow): string {
  return attributeText(projectOf(webapp)?.attributes.qualifiedName) || '—'
}

function projectTitle(webapp: ResourceRow): string {
  return attributeText(projectOf(webapp)?.attributes.title) || '—'
}

function projectLogo(webapp: ResourceRow): string {
  const project = projectOf(webapp)
  return project ? attributeText(related(project, 'org', 'organizations')?.attributes.logoUrl) : ''
}

onMounted(async () => {
  loading.value = true
  try {
    const [detail, deploymentDoc] = await Promise.all([
      getResourceDetail(ARTIFACTS_PATH, artifactId, ['project', 'project.org']),
      fetchDocument(`${ARTIFACTS_PATH}/${artifactId}/webapps`, { include: 'project,project.org' }),
    ])
    artifact.value = detail.row
    webapps.value = deploymentDoc.rows
    included.value = indexIncluded([...detail.included, ...deploymentDoc.included])
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '加载组件详情失败')
  } finally {
    loading.value = false
  }
})
</script>

<style scoped>
.detail-stack {
  display: grid;
  gap: 16px;
}

.detail-back {
  display: inline-block;
  margin-bottom: 4px;
  color: var(--td-text-color-secondary);
  font-size: 13px;
}

.detail-back:hover {
  text-decoration: underline;
}

.detail-card {
  overflow: hidden;
  border: 1px solid var(--td-component-stroke);
  border-radius: 8px;
  background: var(--td-bg-color-container);
}

.detail-card__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  padding: 16px;
  border-bottom: 1px solid var(--td-component-stroke);
}

.detail-card__head h4 {
  margin: 0;
  font-size: 15px;
}

.detail-card__head p {
  margin: 4px 0 0;
  color: var(--td-text-color-secondary);
  font-size: 13px;
}

.fact-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 14px 22px;
  padding: 16px;
}

.fact {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 3px;
}

.fact span {
  color: var(--td-text-color-placeholder);
  font-size: 12px;
}

.fact strong,
.fact code {
  overflow-wrap: anywhere;
  color: var(--td-text-color-primary);
  font-size: 13px;
  font-weight: 500;
}

.detail-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.detail-table th,
.detail-table td {
  padding: 9px 14px;
  border-bottom: 1px solid var(--td-component-stroke);
  text-align: left;
  vertical-align: middle;
}

.detail-table th {
  color: var(--td-text-color-placeholder);
  font-weight: 500;
  white-space: nowrap;
}

.detail-table tr:last-child td {
  border-bottom: 0;
}

.detail-table code {
  padding: 1px 4px;
  border-radius: 3px;
  background: var(--td-bg-color-container-hover);
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace;
  font-size: 11px;
}

.project-logo {
  width: 28px;
  height: 28px;
  object-fit: contain;
  vertical-align: middle;
}

.empty-logo {
  color: var(--td-text-color-placeholder);
}

.empty-text {
  padding: 16px;
  color: var(--td-text-color-placeholder);
  font-size: 13px;
}

@media (max-width: 720px) {
  .fact-grid {
    grid-template-columns: 1fr;
  }
}
</style>
