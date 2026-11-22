import { apiClient } from './client'
import { apiPath } from './prefix'

export type MicdnComponentKind = 'static_bundle' | 'www_doc'
export type MicdnSourceKind = 'jar' | 'npm' | 'dir' | 'zip'

export interface MicdnSource {
  kind: MicdnSourceKind
  ref: string
  inner: string
}

export interface StaticBundleSpec {
  sources: MicdnSource[]
}

export interface WwwDocSpec {
  source: MicdnSource
  tryFile: string
  autoDeploy: boolean
  autoGzip: boolean
}

export type MicdnComponentSpec = StaticBundleSpec | WwwDocSpec

export interface CdnComponent {
  id: string
  kind: MicdnComponentKind
  name: string
  mountName: string
  remark: string
  spec: MicdnComponentSpec
}

export interface ComponentDeployment {
  projectId: string
  projectName: string
  projectTitle: string
  qualifiedName: string
  componentId: string
  version: string
  contextPath: string
}

export interface CdnComponentDetail {
  data: CdnComponent
  deployments: ComponentDeployment[]
}

export interface MicdnRepoConfig {
  declared: boolean
  remotes: string[]
  snapshotRemote?: string
  devRemote?: string
}

export interface MicdnAuthConfig {
  maxSize: string
  publishKey?: string
  downloadKey?: string
  publishKeySet?: boolean
  downloadKeySet?: boolean
}

export interface MicdnServer {
  host: string
}

export interface MicdnConfig {
  home: string
  listen: string
  logFile: string
  logLevel: string
  maven: MicdnRepoConfig
  npm: MicdnRepoConfig
  native: { declared: boolean }
  auth: MicdnAuthConfig
  static: Record<string, never>
  www: Record<string, never>
  blob: { base: string; maxSize: string; publicImages: boolean }
  servers: MicdnServer[]
}

export interface MicdnBinding {
  id?: string
  componentId: string
  kind: MicdnComponentKind
  name: string
  mountName: string
  spec: MicdnComponentSpec
}

export interface MicdnBindingInput {
  componentId: string
}

export interface MicdnProjectSummary {
  id: string
  name: string
  qualifiedName: string
  title: string
  ip: string
  keyMasked: string
  keySet: boolean
}

export interface MicdnProjectDocument {
  project: MicdnProjectSummary
  config: MicdnConfig
  bindings: MicdnBinding[]
  components: CdnComponent[]
  xml: string
}

export interface CdnComponentInput {
  kind: MicdnComponentKind
  name: string
  mountName: string
  remark: string
  spec: MicdnComponentSpec
}

export function defaultMicdnConfig(): MicdnConfig {
  return {
    home: '',
    listen: '0.0.0.0:8888',
    logFile: '/var/log/micdn/micdn.log',
    logLevel: 'info',
    maven: { declared: false, remotes: [], snapshotRemote: '' },
    npm: { declared: false, remotes: [], devRemote: '' },
    native: { declared: false },
    auth: { maxSize: '64M' },
    static: {},
    www: {},
    blob: { base: '', maxSize: '100M', publicImages: true },
    servers: [],
  }
}

export function getMicdnProject(projectId: string): Promise<MicdnProjectDocument> {
  return apiClient.getPlain<MicdnProjectDocument>(apiPath('micdn', `/projects/${encodeURIComponent(projectId)}`))
}

export async function saveMicdnProject(
  projectId: string,
  config: MicdnConfig,
  bindings: MicdnBindingInput[],
): Promise<MicdnProjectDocument> {
  const document = await apiClient.patch<unknown>(
    apiPath('micdn', `/projects/${encodeURIComponent(projectId)}`),
    { config, bindings },
  )
  return document as unknown as MicdnProjectDocument
}

export async function listCdnComponents(): Promise<CdnComponent[]> {
  const document = await apiClient.getPlain<{ data: CdnComponent[] }>(apiPath('micdn', '/components'))
  return document.data || []
}

export function getCdnComponent(id: string): Promise<CdnComponentDetail> {
  return apiClient.getPlain<CdnComponentDetail>(apiPath('micdn', `/components/${encodeURIComponent(id)}`))
}

export async function createCdnComponent(input: CdnComponentInput): Promise<CdnComponent> {
  const document = await apiClient.post<CdnComponent>(apiPath('micdn', '/components'), input)
  if (!document.data) throw new Error('创建组件后未返回数据')
  return document.data
}

export async function updateCdnComponent(id: string, input: CdnComponentInput): Promise<CdnComponent> {
  const document = await apiClient.patch<CdnComponent>(apiPath('micdn', `/components/${id}`), input)
  if (!document.data) throw new Error('更新组件后未返回数据')
  return document.data
}

export async function deleteCdnComponent(id: string): Promise<void> {
  await apiClient.delete(apiPath('micdn', `/components/${id}`))
}

export interface MicdnReloadResult {
  host: string
  ok: boolean
  error?: string
  data?: unknown
}

export async function reloadMicdnProject(projectId: string): Promise<MicdnReloadResult[]> {
  const document = (await apiClient.post(
    apiPath('micdn', `/projects/${encodeURIComponent(projectId)}/reload`),
    {},
  )) as { data?: MicdnReloadResult[] }
  return document.data || []
}

export function micdnXmlUrl(projectId: string): string {
  return apiClient.resolveUrl(apiPath('micdn', `/projects/${encodeURIComponent(projectId)}/micdn.xml`))
}
