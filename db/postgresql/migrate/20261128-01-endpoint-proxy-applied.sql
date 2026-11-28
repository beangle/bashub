-- 代理节点最近一次成功应用的 bundle hash：按 IP 记录，用于和当前生成的 manifest hash 对比。
begin;
alter table bas.cfg_endpoints add column proxy_applied jsonb not null default '{}';
comment on column bas.cfg_endpoints.proxy_applied is '各代理节点最近一次成功应用的 bundle hash 与应用时间：ip -> {hash, at}';
commit;
