/**
 * 记忆查询条件里选中的引用值——原后端用 cookie 记「菜单管理选中的应用」
 * （`AppHelper.remember("menu.app.id")`）的前端对等物。
 *
 * 菜单管理这类按应用分域的列表，应用是必填查询条件：选过一次之后，再进页面默认沿用上次的应用，
 * 不用每次重选。存 localStorage：后端只出 API，没有读这个值的服务端逻辑。
 */
function storageKey(schemaKey: string, fieldKey: string): string {
  return `bashub.filter.${schemaKey}.${fieldKey}`
}

/** 读记忆值；空串表示没记过。 */
export function rememberedFilterValue(schemaKey: string, fieldKey: string): string {
  try {
    return window.localStorage.getItem(storageKey(schemaKey, fieldKey)) ?? ''
  } catch {
    return ''
  }
}

/** 记住选中的查询条件值；空值不覆盖（与旧 `AppHelper.remember` 只记非空值一致）。 */
export function rememberFilterValue(schemaKey: string, fieldKey: string, value: unknown): void {
  if (value === null || value === undefined || value === '') return
  try {
    window.localStorage.setItem(storageKey(schemaKey, fieldKey), String(value))
  } catch {
    /* 隐私模式等场景忽略写入失败 */
  }
}
