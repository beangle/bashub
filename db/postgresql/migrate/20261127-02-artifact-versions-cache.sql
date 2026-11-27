-- 组件版本候选缓存：Maven metadata 的 <versions> 落到库，前端不再实时请求 Maven Central。
begin;
alter table bas.cfg_artifacts add column versions jsonb not null default '[]';
comment on column bas.cfg_artifacts.versions is 'Maven metadata 的 versions 列表，由周期/手动刷新写入';
commit;
