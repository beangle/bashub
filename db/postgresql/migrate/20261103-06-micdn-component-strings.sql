-- 0.0.16 Micdn 组件登记直接存 componentId 字符串数组：["18","19"]。
begin;

update bas.cfg_project_micdn m
set components = coalesce((
  select jsonb_agg(coalesce(item.value->>'componentId', item.value#>>'{}') order by item.ordinality)
  from jsonb_array_elements(m.components) with ordinality as item(value, ordinality)
), '[]'::jsonb);

comment on column bas.cfg_project_micdn.components is 'Micdn 组件 ID 数组，按挂载名排序：["18","19"]';

commit;
