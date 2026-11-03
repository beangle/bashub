-- 0.0.19 Host 的系统特性折叠为 featureIds JSON 数组。
begin;

alter table bas.cfg_hosts
  add column feature_ids jsonb not null default '[]';

update bas.cfg_hosts h
set feature_ids = coalesce((
  select jsonb_agg(f.platform_feature_id::text order by p.name, f.platform_feature_id)
  from bas.cfg_hosts_features f
  join bas.cfg_platform_features p on p.id = f.platform_feature_id
  where f.host_id = h.id
), '[]'::jsonb);

drop table bas.cfg_hosts_features;

comment on column bas.cfg_hosts.feature_ids is '系统特性 ID 数组';

commit;
