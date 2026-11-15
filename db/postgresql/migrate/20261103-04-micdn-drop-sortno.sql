-- 0.0.14 Micdn 组件登记改为纯顺序数组，去掉 sortno。
begin;

update bas.cfg_project_micdn m
set components = coalesce((
  select jsonb_agg(jsonb_build_object('componentId', item.value->>'componentId') order by item.ordinality)
  from jsonb_array_elements(m.components) with ordinality as item(value, ordinality)
), '[]'::jsonb);

comment on column bas.cfg_project_micdn.components is 'Micdn 组件登记，按数组顺序挂载：[{componentId}]';

commit;
