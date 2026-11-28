-- 手工启停实例事件：记录操作人、操作人 IP、执行节点与结果，供监控页查看。
begin;
create table bas.mon_server_events (
  id bigint not null,
  project_id bigint not null,
  instance varchar(255) not null,
  action varchar(16) not null,
  operator varchar(255) not null,
  operator_name varchar(255),
  operator_ip varchar(64),
  agent_ip varchar(64),
  ok boolean default false not null,
  detail varchar(1024),
  created_at timestamp with time zone default now() not null
);
alter table bas.mon_server_events add constraint pk_mon_server_events primary key (id);
alter table bas.mon_server_events add constraint fk_mon_server_events_project
  foreign key (project_id) references bas.cfg_projects (id);
create index idx_mon_server_events_project_time on bas.mon_server_events (project_id, created_at);
create index idx_mon_server_events_project_instance_time on bas.mon_server_events (project_id, instance, created_at);
comment on table bas.mon_server_events is '手工启停实例事件';
comment on column bas.mon_server_events.instance is 'server/实例 id';
comment on column bas.mon_server_events.action is 'start / stop / restart';
comment on column bas.mon_server_events.operator is '操作人登录名';
comment on column bas.mon_server_events.operator_name is '操作人显示名';
comment on column bas.mon_server_events.operator_ip is '操作人 IP';
comment on column bas.mon_server_events.agent_ip is '执行该动作的节点 IP';
comment on column bas.mon_server_events.ok is '是否成功';
comment on column bas.mon_server_events.detail is '失败原因或节点回执';
comment on column bas.mon_server_events.created_at is '事件时间';
commit;
