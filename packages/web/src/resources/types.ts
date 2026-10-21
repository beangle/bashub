/** 通用资源页的字段/资源描述，供列表、表单与菜单统一驱动。 */

export type FieldType =
  | 'text'
  | 'password'
  | 'number'
  | 'textarea'
  /** 一行一项的文本，提交为字符串数组（后端会拆分）。 */
  | 'lines'
  | 'boolean'
  | 'select'
  | 'ref'
  | 'refs'

export interface SelectOption {
  label: string
  value: string | number
}

export interface ResourceRef {
  /** 关联资源路径，如 `/organizations`。 */
  path: string
  /** JSON:API 资源名（复数）。 */
  type: string
  /** 组合成展示文本的属性名。 */
  labelFields: string[]
  sort?: string
}

/** 列表单元格的渲染方式；缺省按属性文本渲染。 */
export type CellType =
  | 'text'
  | 'image'
  | 'icon'
  /** 图标 + 文本（主机管理的「操作系统」：平台图标 + 名称(版本)）。 */
  | 'iconText'
  /** 一组小图标（主机管理的「系统特性」：功能 logo，title 为功能名）。 */
  | 'icons'
  /** 关联集合的逐条模板（群集管理的「服务」：`webapp(web33:9480)`）。 */
  | 'refItems'
  | 'boolean'
  | 'join'
  | 'flags'
  | 'link'
  | 'updatable'

export interface CellSchema {
  type: CellType
  /** image：图片宽/高（像素）。 */
  width?: number
  height?: number
  /** iconText/icons：图标来源属性（支持 `a.b` 关联路径）。font 取类名，image 取图片地址。 */
  iconField?: string
  /** iconText：图标形态，缺省 font（`<i class>`），image 时渲染 `<img src>`。 */
  iconKind?: 'font' | 'image'
  /** iconText（image）：图标宽/高（像素），缺省 30x30。 */
  iconWidth?: number
  iconHeight?: number
  /** icons：取值数组中每个元素的属性名；图标缺省 logo，title 缺省 name。 */
  titleField?: string
  /** refItems：每条关联的文本模板（`{attr}` 取该条目自己的属性/关联）。 */
  itemTemplate?: string
  /** refItems：每条关联的灰色次要文本模板（如 `({host.name}:{httpPort})`）。 */
  itemMutedTemplate?: string
  /** refItems/join：额外需要下发的 include 路径（如 `servers.host`）。 */
  include?: string[]
  /** boolean：真/假文案。 */
  trueText?: string
  falseText?: string
  /** join/flags：取值的属性路径列表。 */
  fields?: string[]
  /** join：连接符。 */
  separator?: string
  /** flags：每个属性为真时显示的文案（缺省用属性名）。 */
  labels?: Record<string, string>
  /** iconText：文本模板，`{attr}` 会替换为行内取值。 */
  template?: string
  /** text/number：文本后缀，如主机的内存 `16` → `16GB`。 */
  suffix?: string
  /** text：单元格内联样式，如 CPU 规格的 `font-size:0.8em`。 */
  style?: string
  /** link：href 模板，`{attr}` 会替换为行内取值；以 `/` 开头且非 `/api/` 的走前端路由。 */
  href?: string
  /** link：链接文案模板，缺省用单元格文本。 */
  text?: string
  /** link：打开方式，缺省 _blank。 */
  target?: '_blank' | '_self'
}

export interface FieldSchema {
  key: string
  /** 属性路径，缺省为 `[key]`；组件属性的键与其所属字段不一致时用它定位。 */
  path?: string[]
  label: string
  /** 列表列标题；缺省用 label（表单标签与列表标题不一致时用，如「IP」/「IP地址」）。 */
  columnTitle?: string
  type?: FieldType
  required?: boolean
  placeholder?: string
  help?: string
  /** 敏感值：编辑时不由服务端回填，留空表示保持原值。 */
  secret?: boolean
  /** type=select 的静态选项。 */
  options?: SelectOption[]
  /** 新建表单的初始值；缺省 select 为空串、boolean 见 ResourceListView。 */
  defaultValue?: string | number | boolean
  /** type=ref/refs 的关联资源。 */
  ref?: ResourceRef
  /** ref/refs：JSON:API 中的关联名；缺省与 key 相同（用于同一关联的多种展示列）。 */
  refKey?: string
  /** 列表单元格渲染方式；缺省按属性文本渲染。 */
  cell?: CellSchema
  /** 是否作为列表列展示；缺省：textarea/lines/password 之外的字段都展示。 */
  column?: boolean
  /** 是否出现在表单中。 */
  form?: boolean
  /** 条件必填：指定布尔字段为真时，本字段必填。 */
  requiredWhen?: string
  /** 条件必填时，编辑已有记录且此属性为真，留空视为保留原值。 */
  preserveWhenSet?: string
  /** 作为查询条件时后端 filter 的属性路径；缺省：普通字段用 key，引用字段用 `key.id`。 */
  filterKey?: string
  /** 在抽屉表单中独占一行；缺省由控件类型决定（textarea/lines 独占）。 */
  wide?: boolean
  width?: number | string
  /** 是否可点击列头排序；缺省：属性列可排序，`refs`（集合）列不可排序。 */
  sortable?: boolean
  /** 排序时提交给后端的属性路径；缺省：普通字段用 key，引用字段用 `key.关联展示字段`。 */
  sortKey?: string
}

export interface ResourceToolSchema {
  code: string
  label: string
  /** 后端动作路径，如 `update-version`、`upgrade`。 */
  action: string
  selection: 'one' | 'oneOrMore' | 'many'
  confirm?: string
  theme?: 'primary' | 'danger' | 'default' | 'warning' | 'success'
}

/** 编辑抽屉里的关联页入口（如群集 → 服务配置）：`to` 里的 `{属性}` 用当前行取值替换。 */
export interface DrawerLinkSchema {
  label: string
  to: string
}

export interface ResourceSchema {
  /** 稳定标识，路由 props 与菜单 key。 */
  key: string
  /** 后端实体别名（simpleEntityName，如 `webapp`），列表 filter 的查询前缀。 */
  alias: string
  /** 后端资源路径，如 `/profiles`；页面路由由所属能力域和页签组决定。 */
  path: string
  /** JSON:API 资源名（复数）。 */
  type: string
  title: string
  group: string
  description?: string
  fields: FieldSchema[]
  /**
   * 列表列顺序（字段 key 列表）；缺省按 `fields` 的声明顺序。
   * 只影响列表列排列与导出列序，表单字段顺序仍按 `fields`（如组件管理：GAV 列在标题之后，但其表单字段不在该位置）。
   */
  columns?: string[]
  /** 列表查询条件，如菜单页按应用过滤。 */
  filters?: FieldSchema[]
  /** 列表默认排序。 */
  sort?: string
  /** 批量动作。 */
  tools?: ResourceToolSchema[]
  /** 是否只读（仅浏览，不提供新建/编辑/删除）。 */
  readOnly?: boolean
  /** 是否以树形展示：前端按 `parent` 关联把平铺数据拼成树。 */
  tree?: boolean
  /** 列表展示形态：普通表格（缺省）或卡片墙（如平台功能）。 */
  layout?: 'table' | 'cards'
  /** 卡片墙的落点（路由模板，`{属性}` 用行内取值替换）；缺省点卡片是打开编辑抽屉。 */
  cardLink?: string
  /** 需要服务端导出 XML 等特殊工具。 */
  xmlTools?: boolean
  /** 提供列表 CSV 导出（原 `action.exportData` 的对等能力）。 */
  exportable?: boolean
  /** 是否作为独立菜单项出现；缺省 true。设为 false 用于从属页面（如服务管理）。 */
  menu?: boolean
  /** 编辑抽屉底部的关联页入口，只在编辑已有记录时出现。 */
  drawerLinks?: DrawerLinkSchema[]
}

/** 页签合成页：把若干资源列表收进一个菜单项，页面内用页签切换。 */
export interface ResourceTabGroup {
  /** 稳定标识，路由 props 与菜单图标使用。 */
  key: string
  /** 含能力域前缀的前端路由，如 `/config/org-config`。 */
  path: string
  /** 菜单标题。 */
  title: string
  /** 所属菜单分组，与 ResourceSchema.group 同一命名空间。 */
  group: string
  description?: string
  /** 页签；`key` 对应 resourceSchemas 的 key，第一个为默认页签。 */
  tabs: { key: string; label: string }[]
}
