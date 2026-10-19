-- bashub 0.0.8（附）：把 Micdn 挂载名从 Profile 绑定上移到组件目录。
-- 适用于已经执行过早期 0.0.8 Micdn Profile 改造的数据库；新库直接按新结构创建。
-- 不提供“组件名作为挂载名”的回退：无法唯一确定挂载名时直接中止迁移。

do $$
declare
  missing_component text;
  conflicting_component text;
begin
  if to_regclass('bas.cdn_components') is null
      or to_regclass('bas.cfg_profile_micdn_components') is null then
    return;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'bas'
      and table_name = 'cdn_components'
      and column_name = 'mount_name'
  ) then
    return;
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'bas'
      and table_name = 'cfg_profile_micdn_components'
      and column_name = 'mount_name'
  ) then
    raise exception 'cdn_components.mount_name 不存在，且绑定表也没有可迁移的 mount_name';
  end if;

  select string_agg(component.id::text, ', ' order by component.id)
  into missing_component
  from bas.cdn_components component
  where not exists (
    select 1 from bas.cfg_profile_micdn_components binding
    where binding.component_id = component.id
  );
  if missing_component is not null then
    raise exception '以下组件没有绑定，无法确定 mount_name: %', missing_component;
  end if;

  select string_agg(component_id::text, ', ' order by component_id)
  into conflicting_component
  from (
    select component_id
    from bas.cfg_profile_micdn_components
    group by component_id
    having count(distinct mount_name) <> 1
  ) conflict;
  if conflicting_component is not null then
    raise exception '以下组件存在多个或空 mount_name: %', conflicting_component;
  end if;

  alter table bas.cdn_components add column mount_name varchar(255);

  update bas.cdn_components component
  set mount_name = binding.mount_name
  from (
    select component_id, min(mount_name) as mount_name
    from bas.cfg_profile_micdn_components
    group by component_id
  ) binding
  where binding.component_id = component.id;

  alter table bas.cdn_components alter column mount_name set not null;
  alter table bas.cdn_components
    add constraint uq_cdn_components_kind_mount_name unique (kind, mount_name);

  alter table bas.cfg_profile_micdn_components
    drop constraint if exists uq_profile_micdn_mount;
  alter table bas.cfg_profile_micdn_components drop column mount_name;
  alter table bas.cfg_profile_micdn_components
    add constraint uq_profile_micdn_component unique (profile_id, component_id);

  comment on column bas.cdn_components.mount_name is '部署挂载名';
end $$;
