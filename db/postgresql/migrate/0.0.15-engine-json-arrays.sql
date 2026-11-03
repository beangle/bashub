-- 0.0.15 Engine 的 listeners/jars 改为 JSON 数组；Micdn 组件按挂载名稳定排序。
begin;

alter table bas.cfg_engines
  add column listeners jsonb not null default '[]',
  add column jars jsonb not null default '[]';

update bas.cfg_engines e
set listeners = coalesce((
      select jsonb_agg(l.value_ order by l.value_)
      from bas.cfg_engines_listeners l where l.engine_id = e.id
    ), '[]'::jsonb),
    jars = coalesce((
      select jsonb_agg(j.value_ order by j.value_)
      from bas.cfg_engines_jars j where j.engine_id = e.id
    ), '[]'::jsonb);

drop table bas.cfg_engines_listeners;
drop table bas.cfg_engines_jars;

-- Micdn 组件数组按组件挂载名排序，保证输出稳定。
update bas.cfg_project_micdn m
set components = coalesce((
  select jsonb_agg(item.value order by c.mount_name, item.ordinality)
  from jsonb_array_elements(m.components) with ordinality as item(value, ordinality)
  left join bas.cdn_components c on c.id::text = item.value->>'componentId'
), '[]'::jsonb);

comment on column bas.cfg_engines.listeners is 'Engine 监听器类名数组';
comment on column bas.cfg_engines.jars is 'Engine 依赖 jar 数组';

commit;
