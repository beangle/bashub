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

export interface MicdnRepoConfig {
  declared: boolean
  base: string
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
  name: string
  adminListen: string
}

export interface MicdnConfig {
  home: string
  listen: string
  logFile: string
  logLevel: string
  maven: MicdnRepoConfig
  npm: MicdnRepoConfig
  native: { declared: boolean; base: string }
  auth: MicdnAuthConfig
  static: { base: string }
  www: { base: string }
  blob: { base: string; maxSize: string; publicImages: boolean }
  servers: MicdnServer[]
}

export interface MicdnBinding {
  id?: string
  componentId: string
  kind: MicdnComponentKind
  name: string
  mountName: string
  sortno: number
  spec: MicdnComponentSpec
}

export interface MicdnBindingInput {
  componentId: string
  sortno: number
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
    logFile: 'console',
    logLevel: 'info',
    maven: { declared: false, base: '', remotes: [], snapshotRemote: '' },
    npm: { declared: false, base: '', remotes: [], devRemote: '' },
    native: { declared: false, base: '' },
    auth: { maxSize: '64M' },
    static: { base: '' },
    www: { base: '' },
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

export function micdnXmlUrl(projectId: string): string {
  return apiClient.resolveUrl(apiPath('micdn', `/projects/${encodeURIComponent(projectId)}/micdn.xml`))
}
