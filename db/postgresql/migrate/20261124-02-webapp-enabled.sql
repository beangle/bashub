-- 应用部署支持临时下线：配置和端口保留，但不再生成 server.xml / 代理路由。
begin;
alter table bas.cfg_webapps add column enabled boolean not null default true;
comment on column bas.cfg_webapps.enabled is '是否启用；false 表示临时下线，保留配置但不运行、不参与告警和统计';
commit;
