-- bashub 0.0.8（附）：以 Profile 为中心的完整 micdn 配置。
-- 旧 cdn_asset_* 模型不兼容；先把旧静态资产转换为组件与 Profile 绑定，再移除旧表。
-- 执行顺序：本目录按文件名序号执行；本脚本是 0.0.8 的最后一步。
-- 脚本可重复执行。

create table if not exists bas.cdn_components (
  id bigint not null,
  kind varchar(32) not null,
  name varchar(255) not null,
  mount_name varchar(255) not null,
  remark varchar(255),
  spec jsonb not null
);

create table if not exists bas.cfg_profile_micdn (
  profile_id bigint not null,
  config jsonb not null
);

create table if not exists bas.cfg_profile_micdn_components (
  id bigint not null,
  component_id bigint not null,
  profile_id bigint not null,
  sortno integer default 0 not null
);

do $$
begin
  alter table bas.cdn_components add constraint pk_cdn_components primary key (id);
exception when duplicate_object or invalid_table_definition then null;
end $$;

do $$
begin
  alter table bas.cdn_components add constraint uq_cdn_components_kind_name unique (kind, name);
exception when duplicate_object or duplicate_table then null;
end $$;

do $$
begin
  alter table bas.cdn_components add constraint uq_cdn_components_kind_mount_name unique (kind, mount_name);
exception when duplicate_object or duplicate_table then null;
end $$;

do $$
begin
  alter table bas.cfg_profile_micdn add constraint pk_cfg_profile_micdn primary key (profile_id);
exception when duplicate_object or invalid_table_definition then null;
end $$;

do $$
begin
  alter table bas.cfg_profile_micdn_components add constraint pk_cfg_profile_micdn_components primary key (id);
exception when duplicate_object or invalid_table_definition then null;
end $$;

do $$
begin
  alter table bas.cfg_profile_micdn_components add constraint uq_profile_micdn_component unique (profile_id, component_id);
exception when duplicate_object or duplicate_table then null;
end $$;

do $$
begin
  alter table bas.cfg_profile_micdn add constraint fk_cfg_profile_micdn_profile
    foreign key (profile_id) references bas.cfg_profiles (id);
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table bas.cfg_profile_micdn_components add constraint fk_profile_micdn_components_profile
    foreign key (profile_id) references bas.cfg_profiles (id);
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table bas.cfg_profile_micdn_components add constraint fk_profile_micdn_components_component
    foreign key (component_id) references bas.cdn_components (id);
exception when duplicate_object then null;
end $$;

create index if not exists idx_cfg_profile_micdn_components_component
  on bas.cfg_profile_micdn_components (component_id);

-- 旧模型中的一个 asset 就是一个 static bundle：base 去掉前导 / 后成为组件挂载名，
-- bundle 的 gav/location 依次转成 jar/dir source。旧表只存在于升级库中，因此转换和删除都做成条件执行。
do $$
begin
  if to_regclass('bas.cdn_assets') is not null
      and to_regclass('bas.cdn_asset_bundles') is not null
      and to_regclass('bas.cdn_asset_groups_profiles') is not null
      and to_regclass('bas.cfg_profiles') is not null then
    insert into bas.cdn_components (id, kind, name, mount_name, remark, spec)
    select base.max_id + row_number() over (order by asset.id),
           'static_bundle',
           asset.name,
           ltrim(asset.base, '/'),
           asset.remark,
           jsonb_build_object(
             'sources',
             jsonb_agg(
               case
                 when coalesce(bundle.gav, '') <> '' then
                   jsonb_build_object('kind', 'jar', 'ref', bundle.gav, 'inner', '')
                 else
                   jsonb_build_object('kind', 'dir', 'ref', bundle.location, 'inner', '')
               end
               order by bundle.id
             )
           )
    from bas.cdn_assets asset
    join bas.cdn_asset_bundles bundle on bundle.asset_id = asset.id
    cross join (
      select coalesce(max(id), 0) as max_id from bas.cdn_components
    ) base
    where coalesce(bundle.gav, '') <> '' or coalesce(bundle.location, '') <> ''
    group by asset.id, asset.name, asset.base, asset.remark, base.max_id
    on conflict (kind, name) do nothing;

    insert into bas.cfg_profile_micdn_components (id, component_id, profile_id, sortno)
    select base.max_id + row_number() over (
             order by links.profile_id, asset.base, asset.id
           ),
           component.id,
           links.profile_id,
           row_number() over (
             partition by links.profile_id
             order by asset.base, asset.id
           ) * 10
    from (
      select distinct link.profile_id, asset.id as asset_id
      from bas.cdn_asset_groups_profiles link
      join bas.cdn_assets asset on asset.group_id = link.asset_group_id
      join bas.cfg_profiles profile on profile.id = link.profile_id
    ) links
    join bas.cdn_assets asset on asset.id = links.asset_id
    join bas.cdn_components component
      on component.kind = 'static_bundle' and component.name = asset.name
    cross join (
      select coalesce(max(id), 0) as max_id from bas.cfg_profile_micdn_components
    ) base
    on conflict (profile_id, component_id) do nothing;

    insert into bas.cfg_profile_micdn (profile_id, config)
    select distinct profile.id,
           jsonb_build_object(
             'home', '/var/lib/micdn',
             'listen', '0.0.0.0:8888',
             'logFile', 'console',
             'logLevel', 'info',
             'maven', jsonb_build_object(
               'declared', true,
               'base', profile.local_repo,
               'remotes', case
                 when coalesce(profile.remote_repo, '') = '' then '[]'::jsonb
                 else jsonb_build_array(profile.remote_repo)
               end,
               'snapshotRemote', ''
             ),
             'npm', jsonb_build_object(
               'declared', false,
               'base', '',
               'remotes', '[]'::jsonb,
               'devRemote', ''
             ),
             'native', jsonb_build_object('declared', false, 'base', ''),
             'auth', jsonb_build_object(
               'publishKey', '',
               'downloadKey', '',
               'maxSize', '64M'
             ),
             'static', jsonb_build_object('base', '/var/cache/micdn/asset'),
             'www', jsonb_build_object('base', '/var/cache/micdn/www'),
             'blob', jsonb_build_object(
               'base', '/var/lib/micdn/blob',
               'maxSize', '50M'
             )
           )
    from bas.cdn_asset_groups_profiles link
    join bas.cfg_profiles profile on profile.id = link.profile_id
    on conflict (profile_id) do nothing;
  end if;
end $$;

-- 已迁移配置若仍是历史默认监听，统一升级为对外监听。
update bas.cfg_profile_micdn
set config = jsonb_set(config, '{listen}', '"0.0.0.0:8888"'::jsonb)
where config->>'listen' = '127.0.0.1:8888';

-- remote 由下载请求的 origin 自动生成，不再保存到 Profile 配置。
update bas.cfg_profile_micdn
set config = config - 'remote'
where config ? 'remote';

drop table if exists bas.cdn_asset_bundles cascade;
drop table if exists bas.cdn_asset_groups_profiles cascade;
drop table if exists bas.cdn_assets cascade;
drop table if exists bas.cdn_asset_groups cascade;

delete from public.table_sequences where table_name like 'bas.cdn_asset%';

insert into public.table_sequences (table_name, currval)
select 'bas.cdn_components', coalesce(max(id), 0) from bas.cdn_components
on conflict (table_name) do update set currval = greatest(table_sequences.currval, excluded.currval);

insert into public.table_sequences (table_name, currval)
select 'bas.cfg_profile_micdn_components', coalesce(max(id), 0) from bas.cfg_profile_micdn_components
on conflict (table_name) do update set currval = greatest(table_sequences.currval, excluded.currval);

comment on table bas.cdn_components is 'Micdn 可复用组件目录';
comment on column bas.cdn_components.id is '非业务主键:auto_increment';
comment on column bas.cdn_components.kind is '组件类型:static_bundle/www_doc';
comment on column bas.cdn_components.name is '组件名称';
comment on column bas.cdn_components.mount_name is '部署挂载名';
comment on column bas.cdn_components.remark is '备注';
comment on column bas.cdn_components.spec is '组件规格(JSON)';

comment on table bas.cfg_profile_micdn is 'Profile 的 Micdn 配置';
comment on column bas.cfg_profile_micdn.profile_id is 'Profile ID';
comment on column bas.cfg_profile_micdn.config is 'Micdn 配置(JSON)';

comment on table bas.cfg_profile_micdn_components is 'Profile 的 Micdn 组件绑定';
comment on column bas.cfg_profile_micdn_components.id is '非业务主键:auto_increment';
comment on column bas.cfg_profile_micdn_components.component_id is '组件 ID';
comment on column bas.cfg_profile_micdn_components.profile_id is 'Profile ID';
comment on column bas.cfg_profile_micdn_components.sortno is '排序号';
