-- bas-hub 0.0.8（前置）：产品由 sas 更名为 bas，数据库 schema 与相关列名同步改名。
--   schema                        sas                  -> bas
--   cfg_profiles.sas_version 列   sas_version          -> bas_version
--   public.table_sequences 键名   'sas.<table>'        -> 'bas.<table>'
--
-- 执行顺序：本目录按文件名序号从小到大执行；本脚本为 01，必须最先执行。
-- 后续脚本的建表、删列语句均使用 bas. 前缀，须在本脚本之后运行。
-- 全新安装直接用 init/*.sql 建库即可，无需本脚本。
-- 脚本可重复执行：schema/列/序列键名改完后再次运行是空操作。
-- 改名仅调整对象归属，表、索引、外键等 OID 不变，无需重建依赖对象。

-- ===== 1. 重命名 schema =====
do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'sas')
     and not exists (select 1 from information_schema.schemata where schema_name = 'bas') then
    alter schema sas rename to bas;
  end if;
end $$;

-- ===== 2. 重命名 cfg_profiles.sas_version 列 =====
-- 对应实体 org.beangle.bashub.model.config.Profile.basVersion。
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'bas' and table_name = 'cfg_profiles' and column_name = 'sas_version')
     and not exists (select 1 from information_schema.columns
              where table_schema = 'bas' and table_name = 'cfg_profiles' and column_name = 'bas_version') then
    alter table bas.cfg_profiles rename column sas_version to bas_version;
  end if;
end $$;

-- ===== 3. 修正主键生成器表名 =====
-- public.next_id(schema.table) 以 'schema.table' 字符串为键，schema 改名后旧键名会失效，
-- 若不修正，新记录会退化为 max(id)+1 重新计数（并发下可能撞主键）。
-- schema 已经手工改过名时 `sas.*` 与 `bas.*` 两套键可能并存；此时保留较大的 currval，
-- 再删掉 `sas.*` 旧键，避免 rename 撞主键或计数器回退。
do $$
begin
  if to_regclass('public.table_sequences') is not null then
    insert into public.table_sequences (table_name, currval)
    select 'bas.' || substr(ts.table_name, 5), ts.currval
      from public.table_sequences ts
     where ts.table_name like 'sas.%'
       and to_regclass('bas.' || substr(ts.table_name, 5)) is not null
    on conflict (table_name) do update
       set currval = greatest(public.table_sequences.currval, excluded.currval);

    delete from public.table_sequences where table_name like 'sas.%';
  end if;
end $$;
