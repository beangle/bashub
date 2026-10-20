-- Blob bucket 不再属于可复用组件目录：bucket 的 name/key 固定取 Profile。
-- Blob 是否输出由 Profile key 决定，不再是配置中的 declared 开关；
-- 这里清理旧字段并补齐 publicImages，随后删除废弃组件与绑定。
-- 执行顺序：必须在 0.0.8-10-micdn-profile.sql 之前。

do $$
begin
  if to_regclass('bas.cdn_components') is null
      or to_regclass('bas.cfg_profile_micdn') is null
      or to_regclass('bas.cfg_profile_micdn_components') is null then
    return;
  end if;

  update bas.cfg_profile_micdn config
  set config = jsonb_set(
    config.config,
    '{blob}',
    ((config.config->'blob') - 'declared') || jsonb_build_object(
      'publicImages', coalesce(config.config->'blob'->'publicImages', 'true'::jsonb)
    ),
    true
  )
  where config.config ? 'blob'
    and jsonb_typeof(config.config->'blob') = 'object';

  delete from bas.cfg_profile_micdn_components binding
  using bas.cdn_components component
  where binding.component_id = component.id
    and component.kind = 'blob_bucket';

  delete from bas.cdn_components where kind = 'blob_bucket';
end $$;

comment on column bas.cdn_components.kind is '组件类型:static_bundle/www_doc';
