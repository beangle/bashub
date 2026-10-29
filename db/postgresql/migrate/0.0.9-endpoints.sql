-- 0.0.9 多代理 endpoint：server.xml 的 <proxies> 与 webapp endpoints。
begin;

create table bas.cfg_endpoints (
  id bigint not null,
  project_id bigint not null,
  name varchar(255) not null,
  ips varchar(1024) not null,
  domain varchar(255),
  force_https boolean not null default false,
  certificate text,
  private_key text,
  http_port integer not null default 80,
  https_port integer not null default 443,
  enable_https boolean not null default false,
  maxconn integer not null default 30000,
  ssl_ciphers varchar(255),
  ssl_protocols varchar(255)
);

create table bas.cfg_webapps_endpoints (
  endpoint_id bigint not null,
  webapp_id bigint not null
);

alter table bas.cfg_endpoints
  add constraint pk_cfg_endpoints primary key (id);
alter table bas.cfg_endpoints
  add constraint uq_cfg_endpoints_project_name unique (project_id, name);
alter table bas.cfg_endpoints
  add constraint uq_cfg_endpoints_project_domain unique (project_id, domain);
alter table bas.cfg_endpoints
  add constraint fk_cfg_endpoints_project foreign key (project_id)
  references bas.cfg_projects (id);

alter table bas.cfg_webapps_endpoints
  add constraint pk_cfg_webapps_endpoints primary key (webapp_id, endpoint_id);
alter table bas.cfg_webapps_endpoints
  add constraint fk_cfg_webapps_endpoints_webapp foreign key (webapp_id)
  references bas.cfg_webapps (id);
alter table bas.cfg_webapps_endpoints
  add constraint fk_cfg_webapps_endpoints_endpoint foreign key (endpoint_id)
  references bas.cfg_endpoints (id);

create index idx_cfg_webapps_endpoints_webapp on bas.cfg_webapps_endpoints (webapp_id);
create index idx_cfg_webapps_endpoints_endpoint on bas.cfg_webapps_endpoints (endpoint_id);

comment on table bas.cfg_endpoints is 'Project 的代理 endpoint';
comment on column bas.cfg_endpoints.name is 'endpoint 唯一名称';
comment on column bas.cfg_endpoints.ips is '代理机内网 IP，逗号分隔';
comment on column bas.cfg_endpoints.domain is '域名；可选且唯一';
comment on column bas.cfg_endpoints.force_https is '是否强制 HTTPS';
comment on column bas.cfg_endpoints.certificate is 'PEM 证书';
comment on column bas.cfg_endpoints.private_key is 'PEM 私钥';
comment on table bas.cfg_webapps_endpoints is 'Webapp 与代理 endpoint 的关系';

commit;
