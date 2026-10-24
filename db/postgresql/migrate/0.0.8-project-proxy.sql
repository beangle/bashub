-- 0.0.8 项目/代理结构变更：profile 改名 project，代理字段拆到 cfg_proxy_settings。
-- 只支持从 0.0.8 直接升级；执行前备份数据库。
begin;

-- 1. 表改名
alter table bas.cfg_profiles rename to cfg_projects;
alter table bas.cfg_profile_micdn rename to cfg_project_micdn;
alter table bas.cfg_profile_micdn_components rename to cfg_project_micdn_components;
alter table bas.cfg_profile_certificates rename to cfg_project_certificates;

-- 2. 外键列改名
alter table bas.cfg_artifacts rename column profile_id to project_id;
alter table bas.cfg_engines rename column profile_id to project_id;
alter table bas.cfg_farms rename column profile_id to project_id;
alter table bas.cfg_hosts rename column profile_id to project_id;
alter table bas.cfg_webapps rename column profile_id to project_id;
alter table bas.cfg_project_micdn rename column profile_id to project_id;
alter table bas.cfg_project_micdn_components rename column profile_id to project_id;
alter table bas.cfg_project_certificates rename column profile_id to project_id;
alter table bas.mon_server_samples rename column profile_id to project_id;

-- 3. 代理/Setline 配置独立成表，并按 project 回填
create table bas.cfg_proxy_settings (
  id bigint not null,
  project_id bigint not null,
  ip varchar(255) not null,
  proxy_by_hostname boolean not null default false,
  proxy_engine varchar(255) not null default 'haproxy',
  maxconn integer not null default 30000,
  http_port integer not null default 80,
  https_port integer not null default 443,
  enable_https boolean not null default false,
  force_https boolean not null default true,
  ssl_ciphers varchar(255),
  ssl_protocols varchar(255)
);
insert into bas.cfg_proxy_settings
  (id, project_id, ip, proxy_by_hostname, proxy_engine, maxconn,
   http_port, https_port, enable_https, force_https, ssl_ciphers, ssl_protocols)
select id, id, ip, proxy_by_hostname, proxy_engine, maxconn,
       http_port, https_port, enable_https, force_https, ssl_ciphers, ssl_protocols
from bas.cfg_projects;

alter table bas.cfg_proxy_settings
  add constraint pk_cfg_proxy_settings primary key (id);
alter table bas.cfg_proxy_settings
  add constraint uq_cfg_proxy_settings_project unique (project_id);
alter table bas.cfg_proxy_settings
  add constraint fk_cfg_proxy_settings_project foreign key (project_id)
  references bas.cfg_projects (id);

-- 4. 从 project 删除已迁走的字段
alter table bas.cfg_projects
  drop column enable_https,
  drop column force_https,
  drop column http_port,
  drop column https_port,
  drop column ip,
  drop column maxconn,
  drop column proxy_by_hostname,
  drop column proxy_engine,
  drop column ssl_ciphers,
  drop column ssl_protocols;

-- 5. 约束/索引改名，与新命名保持一致
alter table bas.cfg_project_certificates
  rename constraint pk_cfg_profile_certificates to pk_cfg_project_certificates;
alter table bas.cfg_project_micdn
  rename constraint pk_cfg_profile_micdn to pk_cfg_project_micdn;
alter table bas.cfg_project_micdn_components
  rename constraint pk_cfg_profile_micdn_components to pk_cfg_project_micdn_components;
alter table bas.cfg_project_micdn_components
  rename constraint uq_profile_micdn_component to uq_project_micdn_component;
alter table bas.mon_server_samples
  rename constraint fk_mon_server_samples_profile to fk_mon_server_samples_project;
alter table bas.cfg_project_certificates
  rename constraint fk_cfg_profile_certificates_profile to fk_cfg_project_certificates_project;
alter table bas.cfg_project_micdn
  rename constraint fk_cfg_profile_micdn_profile to fk_cfg_project_micdn_project;
alter table bas.cfg_project_micdn_components
  rename constraint fk_profile_micdn_components_component to fk_project_micdn_components_component;
alter table bas.cfg_project_micdn_components
  rename constraint fk_profile_micdn_components_profile to fk_project_micdn_components_project;
alter index bas.idx_mon_server_samples_profile_time rename to idx_mon_server_samples_project_time;
alter index bas.idx_cfg_profile_micdn_components_component
  rename to idx_cfg_project_micdn_components_component;

-- 6. 注释
comment on table bas.cfg_projects is 'Project?';
comment on table bas.cfg_project_micdn is 'Project 的 Micdn 配置';
comment on table bas.cfg_project_micdn_components is 'Project 的 Micdn 组件绑定';
comment on table bas.cfg_project_certificates is 'Project 的 HTTPS 证书';
comment on table bas.cfg_proxy_settings is 'Project 的代理/SETLINE 配置';
comment on column bas.cfg_proxy_settings.id is '非业务主键:datetime';
comment on column bas.cfg_proxy_settings.project_id is 'Project?ID';
comment on column bas.cfg_proxy_settings.ip is '内部 IP(多个用空格/逗号分隔)';
comment on column bas.cfg_proxy_settings.proxy_by_hostname is 'proxyByHostname?';
comment on column bas.cfg_proxy_settings.proxy_engine is 'proxyEngine?';
comment on column bas.cfg_proxy_settings.maxconn is 'maxconn?';
comment on column bas.cfg_proxy_settings.http_port is 'httpPort?';
comment on column bas.cfg_proxy_settings.https_port is 'httpsPort?';
comment on column bas.cfg_proxy_settings.enable_https is 'enableHttps?';
comment on column bas.cfg_proxy_settings.force_https is 'forceHttps?';
comment on column bas.cfg_proxy_settings.ssl_ciphers is 'sslCiphers?';
comment on column bas.cfg_proxy_settings.ssl_protocols is 'sslProtocols?';

commit;
