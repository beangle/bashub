-- bas-hub 0.0.8：应用部署字段（url/base/nav_style）拆分为「应用端」Channel。
-- 对应实体 org.beangle.bashub.model.ems.Channel(app/base/channelType/embedMode/enabled)。
--
-- 执行顺序：**停掉旧后端 → 执行本脚本 → 部署新后端**。
-- 由 sas 更名的存量库，请先执行同目录的 0.0.8-schema-rename.sql（把 schema sas 改为 bas）。
-- 第 1 段（建表/回填/计数器）新老后端可共存；第 2 段会删掉 ems_apps 的三列，
-- 旧后端（实体仍映射 url/base/navStyle）在删列后启动/查询会报错，故务必按上述顺序执行。
-- 脚本可重复执行（表/约束/列/回填都做了存在性判断），已迁移的库再跑是空操作。

-- ===== 1. 建表与回填 =====
create table if not exists bas.ems_channels (
  id integer not null,
  app_id integer not null,
  base varchar(200) not null,
  channel_type varchar(20) not null,
  embed_mode varchar(20) not null,
  enabled boolean default false not null
);

do $$
begin
  alter table bas.ems_channels add constraint pk_1yi5whvx5ialppx8bcmejakj5 primary key (id);
exception when duplicate_object or duplicate_table or invalid_table_definition then null;
end $$;

do $$
begin
  alter table bas.ems_channels add constraint idx_ems_channel unique (app_id, channel_type);
exception when duplicate_object or duplicate_table then null;
end $$;

-- 0.0.7 库的 bas.ems_apps 没有主键，故默认不建外键；按 ormDdl 的 2-keys.sql 建的库可放开：
-- alter table bas.ems_channels add constraint fk_fnfitp6dm7fobk5b0bw67oc7d foreign key (app_id) references bas.ems_apps (id);

-- 每个应用补一个 PC 端：id 沿用应用 id，base 沿用 app.base，嵌入方式取缺省值 iframe（原 navStyle 无对应语义）。
-- 仅当 ems_apps 还有 base 列（尚未迁移过）时执行。
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'bas' and table_name = 'ems_apps' and column_name = 'base') then
    insert into bas.ems_channels (id, app_id, base, channel_type, embed_mode, enabled)
    select a.id, a.id, a.base, 'pc', 'iframe', true from bas.ems_apps a where a.base is not null
    on conflict do nothing;
  end if;
end $$;

-- 主键生成器 beangle_get_next_id 依赖 public.table_sequences，回填后校正计数。
insert into public.table_sequences (table_name, currval)
select 'bas.ems_channels', coalesce(max(id), 0) from bas.ems_channels
on conflict (table_name) do update set currval = greatest(table_sequences.currval, excluded.currval);

comment on table bas.ems_channels is '应用端';
comment on column bas.ems_channels.id is '非业务主键:auto_increment';
comment on column bas.ems_channels.app_id is '应用ID';
comment on column bas.ems_channels.base is '上下文地址';
comment on column bas.ems_channels.channel_type is '端类型(pc/mobile)';
comment on column bas.ems_channels.embed_mode is '嵌入方式(iframe/wujie)';
comment on column bas.ems_channels.enabled is '是否启用';

-- ===== 2. 清理 ems_apps 的旧列（仅新后端使用；执行前请确认第 1 段已生效） =====
-- 删列不可逆，建议先留底：create table if not exists bas.ems_apps_bak_0_0_8 as select * from bas.ems_apps;
alter table bas.ems_apps drop column if exists url;
alter table bas.ems_apps drop column if exists base;
alter table bas.ems_apps drop column if exists nav_style;
