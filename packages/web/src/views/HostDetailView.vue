<template>
  <section class="page-panel">
    <div class="page-head">
      <div>
        <router-link class="detail-back" :to="listPath">← 返回主机管理</router-link>
        <h2 class="page-title">{{ hostName || '主机详情' }}</h2>
      </div>
      <div class="page-actions">
        <t-button v-if="scriptUrl" variant="outline" tag="a" :href="scriptUrl" target="_blank">
          <template #icon><DownloadIcon /></template>
          下载初始化脚本
        </t-button>
      </div>
    </div>

    <t-loading :loading="loading" show-overlay>
      <div class="host-detail">
        <div class="host-card">
          <div class="host-card__head"><i class="fa-solid fa-server"></i> 主机信息</div>
          <table class="info-table">
            <tbody>
              <tr>
                <td class="info-table__label">名称</td>
                <td class="info-table__value">{{ hostName || '—' }}</td>
                <td class="info-table__label">IP地址</td>
                <td class="info-table__value">{{ hostIp || '—' }}</td>
              </tr>
              <tr>
                <td class="info-table__label">操作系统</td>
                <td class="info-table__value">
                  <i v-if="platformIcon" :class="platformIcon"></i>
                  {{ platformText || '—' }}
                </td>
                <td class="info-table__label">内存</td>
                <td class="info-table__value">
                  {{ memoryText }}
                  <span :class="{ 'info-table__warn': memoryShort }">（运行需要 {{ memoryNeeded }}MB）</span>
                </td>
              </tr>
              <tr>
                <td class="info-table__label">CPU规格</td>
                <td class="info-table__value">{{ cpuText || '—' }}</td>
                <td class="info-table__label">CPU核心数</td>
                <td class="info-table__value">{{ coresText || '—' }}</td>
              </tr>
              <tr>
                <td class="info-table__label">系统特性</td>
                <td class="info-table__value" colspan="3">
                  <span v-if="features.length === 0" class="info-table__muted">—</span>
                  <img
                    v-for="feature in features"
                    :key="feature.id"
                    class="info-table__feature"
                    :src="feature.logo"
                    :title="feature.name"
                    :alt="feature.name"
                  />
                </td>
              </tr>
              <tr>
                <td class="info-table__label">开放端口</td>
                <td class="info-table__value" colspan="3">
                  <span v-if="servers.length === 0" class="info-table__muted">—</span>
                  <span v-for="(server, index) in sortedServers" :key="server.id">
                    <template v-if="index > 0">&nbsp;</template>
                    {{ serverLabel(server) }}
                  </span>
                </td>
              </tr>
              <tr>
                <td class="info-table__label">部署应用</td>
                <td class="info-table__value" colspan="3">
                  <span v-if="webapps.length === 0" class="info-table__muted">—</span>
                  <p v-for="(webapp, index) in sortedWebapps" :key="webapp.id" class="info-table__webapp">
                    {{ index + 1 }}. {{ webappLabel(webapp) }}
                  </p>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </t-loading>
  </section>
</template>

<script setup lang="ts">
import { DownloadIcon } from 'tdesign-icons-vue-next'
import { MessagePlugin } from 'tdesign-vue-next'
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { runtimeConfig } from '@/auth'
import { apiRootPath } from '@/api/prefix'
import {
  attributeText,
  fetchDocument,
  getResourceDetail,
  indexIncluded,
  listResource,
  relationshipIds,
  type ResourceRow,
} from '@/api/resource'

const HOSTS_PATH = '/hosts'
const SERVERS_PATH = '/servers'

const route = useRoute()
const hostId = String(route.params.id || '')
const listPath = '/config/farm-hosts?tab=hosts'

const host = ref<ResourceRow>()
const included = ref<Map<string, ResourceRow>>(new Map())
const servers = ref<ResourceRow[]>([])
const webapps = ref<ResourceRow[]>([])
const loading = ref(false)

const hostName = computed(() => attributeText(host.value?.attributes.name))
const hostIp = computed(() => attributeText(host.value?.attributes.ip))
const cpuText = computed(() => attributeText(host.value?.attributes.cpu))
const coresText = computed(() => attributeText(host.value?.attributes.cores))
const memoryGb = computed(() => Number(host.value?.attributes.memory ?? 0))
const memoryText = computed(() => (host.value ? `${memoryGb.value}GB` : '—'))

const platform = computed(() => related(host.value, 'platform', 'platforms'))
const platformIcon = computed(() => attributeText(platform.value?.attributes.fonticon))
const platformText = computed(() => {
  if (!platform.value) return ''
  const version = attributeText(host.value?.attributes.platformVersion)
  return `${attributeText(platform.value.attributes.name)}(${version})`
})

const profileName = computed(() =>
  attributeText(related(host.value, 'profile', 'profiles')?.attributes.qualifiedName),
)

const scriptUrl = computed(() =>
  profileName.value && hostIp.value
    ? runtimeConfig.getApiUrl(apiRootPath('config', `/${profileName.value}/script/${hostIp.value}.sh`))
    : '',
)

/** 系统特性：详情页跟原 host/info.ftl 一样展示全部（列表页才按平台过滤）。 */
const features = computed(() =>
  relationshipIds(host.value, 'features')
    .map((id) => included.value.get(`platformFeatures:${id}`))
    .filter((row): row is ResourceRow => Boolean(row))
    .map((row) => ({
      id: row.id,
      name: attributeText(row.attributes.name),
      logo: attributeText(row.attributes.logo),
    }))
    .filter((item) => item.logo.length > 0)
    .sort((a, b) => a.name.localeCompare(b.name)),
)

const sortedServers = computed(() =>
  [...servers.value].sort((a, b) => Number(a.attributes.httpPort ?? 0) - Number(b.attributes.httpPort ?? 0)),
)

/** 运行所需内存：服务自带堆上限，否则取所属群集的默认值（原 info.ftl 的口径）。 */
const memoryNeeded = computed(() =>
  servers.value.reduce((sum, server) => {
    const own = Number(server.attributes.maxHeapSize ?? 0)
    if (own > 0) return sum + own
    const farm = related(server, 'farm', 'farms')
    return sum + Number(farm?.attributes.maxHeapSize ?? 0)
  }, 0),
)

const memoryShort = computed(() => host.value !== undefined && memoryGb.value * 1024 * 0.8 < memoryNeeded.value)

const sortedWebapps = computed(() =>
  [...webapps.value].sort((a, b) => webappLabel(a).localeCompare(webappLabel(b))),
)

/** 从 included 里取某个 to-one 关联。 */
function related(row: ResourceRow | undefined, key: string, type: string): ResourceRow | undefined {
  const id = relationshipIds(row, key)[0]
  return id ? included.value.get(`${type}:${id}`) : undefined
}

function serverLabel(server: ResourceRow): string {
  const name = attributeText(server.attributes.qualifiedName) || attributeText(server.attributes.name)
  return `${name}(${attributeText(server.attributes.httpPort)})`
}

function webappLabel(webapp: ResourceRow): string {
  const artifact = related(webapp, 'artifact', 'artifacts')
  const title = attributeText(artifact?.attributes.title) || attributeText(artifact?.attributes.artifactId)
  const gav = attributeText(webapp.attributes.gav)
  return title ? `${title}(${gav})` : gav
}

onMounted(async () => {
  loading.value = true
  try {
    const [hostDetail, serverPage, webappDoc] = await Promise.all([
      getResourceDetail(HOSTS_PATH, hostId, ['profile', 'profile.org', 'platform', 'features']),
      listResource(SERVERS_PATH, {
        filters: { 'server.host.id': hostId },
        include: ['farm'],
        pageSize: 200,
      }),
      fetchDocument(`${HOSTS_PATH}/${hostId}/webapps`, { include: 'artifact' }),
    ])
    host.value = hostDetail.row
    included.value = indexIncluded([...hostDetail.included, ...serverPage.included, ...webappDoc.included])
    servers.value = serverPage.rows
    webapps.value = webappDoc.rows
  } catch (error) {
    MessagePlugin.error(error instanceof Error ? error.message : '加载主机详情失败')
  } finally {
    loading.value = false
  }
})
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

.host-card {
  border: 1px solid var(--td-component-stroke);
  border-radius: 6px;
  background: var(--td-bg-color-container);
}

.host-card__head {
  padding: 8px 12px;
  border-bottom: 1px solid var(--td-component-stroke);
  color: var(--td-text-color-primary);
  font-size: 14px;
  font-weight: 500;
}

.info-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.info-table td {
  padding: 6px 12px;
  border-bottom: 1px solid var(--td-component-stroke);
  vertical-align: top;
}

.info-table tr:last-child td {
  border-bottom: 0;
}

.info-table__label {
  width: 12%;
  color: var(--td-text-color-secondary);
  white-space: nowrap;
}

.info-table__value {
  color: var(--td-text-color-primary);
}

.info-table__warn {
  color: var(--td-error-color);
}

.info-table__muted {
  color: var(--td-text-color-placeholder);
}

.info-table__feature {
  max-height: 20px;
  margin-right: 6px;
  vertical-align: middle;
}

.info-table__webapp {
  margin: 0;
}
</style>
