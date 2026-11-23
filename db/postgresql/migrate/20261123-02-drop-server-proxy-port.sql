-- 0.0.10 移除未使用的服务代理端口；代理始终转发服务的 httpPort。
begin;
alter table bas.cfg_servers drop column proxy_http_port;
commit;
