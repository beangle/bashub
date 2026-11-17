<template>
  <section class="page-panel">
    <div class="page-head">
      <div>
        <router-link class="detail-back" to="/micdn/components">← 返回组件目录</router-link>
        <h2 class="page-title">{{ component?.name || '组件详情' }}</h2>
        <p class="page-subtitle">{{ kindLabel(component?.kind) }}</p>
      </div>
      <t-button variant="outline" @click="router.push('/micdn/components')">返回目录</t-button>
    </div>

    <t-loading :loading="loading" show-overlay>
      <div v-if="component" class="detail-stack">
        <article class="detail-card">
          <header class="detail-card__head">
            <div>
              <h4>基本信息</h4>
              <p>组件目录中的定义，供 Project 引用。</p>
            </div>
          </header>
          <div class="fact-grid">
            <div class="fact"><span>名称</span><strong>{{ component.name }}</strong></div>
            <div class="fact"><span>类型</span><strong>{{ kindLabel(component.kind) }}</strong></div>
            <div class="fact"><span>挂载名</span><strong>{{ component.mountName }}</strong></div>
            <div class="fact"><span>公开路径</span><strong><code>{{ contextPath(component) }}</code></strong></div>
            <div class="fact"><span>版本</span><strong>{{ version(component) || '—' }}</strong></div>
            <div class="fact"><span>说明</span><strong>{{ component.remark || '—' }}</strong></div>
          </div>
        </article>

        <article class="detail-card">
          <header class="detail-card__head">
            <div>
              <h4>来源</h4>
              <p>静态包可以包含多个来源。</p>
            </div>
          </header>
          <div v-if="sources.length > 0" class="source-list">
            <div v-for="(source, index) in sources" :key="index" class="source-item">
              <t-tag variant="light">{{ source.kind }}</t-tag>
              <code>{{ source.ref }}</code>
              <span v-if="source.inner" class="source-inner">/{{ source.inner }}</span>
            </div>
          </div>
          <p v-else class="empty-text">没有来源信息。</p>
        </article>

        <article class="detail-card">
          <header class="detail-card__head">
            <div>
              <h4>部署情况</h4>
              <p>引用该组件的 Project；版本和路径取各自实际绑定的组件。</p>
            </div>
            <t-tag variant="light">{{ deployments.length }} 个 Project</t-tag>
          </header>
          <table v-if="deployments.length > 0" class="deployment-table">
            <thead>
              <tr><th>Project</th><th>版本</th><th>Context Path</th></tr>
            </thead>
            <tbody>
              <tr v-for="item in deployments" :key="item.projectId">
                <td>
                  <strong>{{ item.projectTitle || item.projectName }}</strong>
                  <small>{{ item.qualifiedName }}</small>
                </td>
                <td><code>{{ item.version || '—' }}</code></td>
                <td><code>{{ item.contextPath }}</code></td>
              </tr>
            </tbody>
          </table>
          <p v-else class="empty-text">尚未被 Project 引用。</p>
        </article>
      </div>
    </t-loading>
  </section>
</template>

<script setup lang="ts">
import { MessagePlugin } from 'tdesign-vue-next'
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  getCdnComponent,
  type CdnComponent,
  type CdnComponentDetail,
  type MicdnSource,
} from '@/api/micdn'

const route = useRoute()
const router = useRouter()
const loading = ref(false)
const detail = ref<CdnComponentDetail>()

const component = computed(() => detail.value?.data)
const deployments = computed(() => detail.value?.deployments || [])
const sources = computed<MicdnSource[]>(() => {
  const value = component.value
  if (!value) return []
  if (value.kind === 'static_bundle') {
    return (value.spec as { sources?: MicdnSource[] }).sources || []
  }
  const source = (value.spec as { source?: MicdnSource }).source
  return source ? [source] : []
})

function kindLabel(kind?: string): string {
  if (kind === 'static_bundle') return '静态包'
  if (kind === 'www_doc') return '文档'
  return '组件'
}

function version(value: CdnComponent): string {
  const ref = sources.value[0]?.ref || ''
  const parts = ref.split(':')
  return parts.length > 1 ? parts[parts.length - 1] : ref
}

function contextPath(value: CdnComponent): string {
  const base = value.kind === 'www_doc' ? '/www/' : '/asset/'
  return `${base}${value.mountName}`
}

async function load() {
  loading.value = true
  try {
    detail.value = await getCdnComponent(String(route.params.id || ''))
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '加载组件详情失败')
  } finally {
    loading.value = false
  }
}

onMounted(load)
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

.source-list {
  padding: 4px 16px 16px;
}

.source-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 0;
  border-bottom: 1px solid var(--td-component-stroke);
}

.source-item:last-child {
  border-bottom: 0;
}

.source-inner {
  color: var(--td-text-color-placeholder);
}

.deployment-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.deployment-table th,
.deployment-table td {
  padding: 10px 16px;
  border-bottom: 1px solid var(--td-component-stroke);
  text-align: left;
  vertical-align: top;
}

.deployment-table th {
  color: var(--td-text-color-secondary);
  font-weight: 500;
}

.deployment-table tr:last-child td {
  border-bottom: 0;
}

.deployment-table td small {
  display: block;
  margin-top: 3px;
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
