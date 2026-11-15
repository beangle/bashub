-- 0.0.8：agent 自动组网（host 分组 + project 固定监听端口）。
-- 在 project/proxy 迁移之后执行；执行前备份。
begin;

alter table bas.cfg_hosts add column agent_group varchar(64) not null default 'default_group';
comment on column bas.cfg_hosts.agent_group is 'agent 组网分组';

alter table bas.cfg_projects add column agent_listen_port integer not null default 19080;
comment on column bas.cfg_projects.agent_listen_port is 'agent 统一监听端口';


commit;
