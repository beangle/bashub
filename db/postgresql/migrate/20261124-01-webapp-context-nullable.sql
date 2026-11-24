-- 0.0.10 应用部署允许没有上下文（后台任务）。
begin;
alter table bas.cfg_webapps alter column context_path drop not null;
comment on column bas.cfg_webapps.context_path is 'contextPath? 可空：空表示后台任务，不生成代理路由';
commit;
