-- 0.0.13 Project 的 Micdn 组件登记从关系表改为 JSON 数组。
-- components = [{"componentId":"17001","sortno":10}, ...]
begin;

alter table bas.cfg_project_micdn
  add column components jsonb not null default '[]';

-- 防止存在组件绑定但缺少 cfg_project_micdn 主行的旧数据。
insert into bas.cfg_project_micdn (project_id, config, components)
select distinct c.project_id, '{}'::jsonb, '[]'::jsonb
from bas.cfg_project_micdn_components c
on conflict (project_id) do nothing;

update bas.cfg_project_micdn m
set components = coalesce((
  select jsonb_agg(jsonb_build_object('componentId', c.component_id::text, 'sortno', c.sortno)
         order by c.sortno, c.component_id)
  from bas.cfg_project_micdn_components c
  where c.project_id = m.project_id
), '[]'::jsonb);

drop table bas.cfg_project_micdn_components;

comment on column bas.cfg_project_micdn.components is 'Micdn 组件登记：[{componentId,sortno}]';

commit;
