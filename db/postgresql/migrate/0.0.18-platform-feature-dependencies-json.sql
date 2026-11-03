-- 0.0.18 平台功能依赖折叠为 JSON ID 数组。
begin;

alter table bas.cfg_platform_features
  add column dependencies jsonb not null default '[]';

update bas.cfg_platform_features f
set dependencies = coalesce((
  select jsonb_agg(d.platform_feature_id::text order by t.name, d.platform_feature_id)
  from bas.cfg_platform_features_dependencies d
  join bas.cfg_platform_features t on t.id = d.platform_feature_id
  where d.from_feature_id = f.id
), '[]'::jsonb);

drop table bas.cfg_platform_features_dependencies;

comment on column bas.cfg_platform_features.dependencies is '依赖的平台功能 ID 数组：["1","2"]';

commit;
