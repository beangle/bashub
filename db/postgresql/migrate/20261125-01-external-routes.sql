-- 外部系统路由：把非 BAS/Micdn 管理的路径显式代理到固定 host:port。
begin;
create table bas.cfg_external_routes (
  id bigint not null,
  project_id bigint not null,
  endpoint_id bigint not null,
  path varchar(255) not null,
  target varchar(255) not null,
  description varchar(255),
  enabled boolean not null default true,
  constraint pk_cfg_external_routes primary key (id),
  constraint uk_cfg_external_routes_path unique (endpoint_id, path),
  constraint fk_cfg_external_routes_project foreign key (project_id) references bas.cfg_projects (id),
  constraint fk_cfg_external_routes_endpoint foreign key (endpoint_id) references bas.cfg_endpoints (id)
);
comment on table bas.cfg_external_routes is '外部系统代理路由：path -> host:port';
comment on column bas.cfg_external_routes.target is 'host:port；支持 [IPv6]:port';
comment on column bas.cfg_external_routes.enabled is '是否启用；false 不生成代理路由';
commit;
