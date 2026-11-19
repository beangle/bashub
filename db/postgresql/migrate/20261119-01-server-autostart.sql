-- 20261119 Server 开机自启与 wait-for 条件。
begin;

alter table bas.cfg_servers
  add column if not exists auto_start boolean not null default false;
alter table bas.cfg_servers
  add column if not exists wait_for text;

comment on column bas.cfg_servers.auto_start is 'basagent 开机自启';
comment on column bas.cfg_servers.wait_for is '启动等待条件 JSON 数组';

commit;
