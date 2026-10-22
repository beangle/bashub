-- bashub 0.0.8：记录 agent 的周期实例运行状态，供在线节点页展示半年历史。
--
-- 每个 profile 每个采样点一行，servers 是 {server_id: state} 的 JSONB 对象。
-- 只存 server id 与 running/stopped/error，不保存 OS、内存和 webapps 快照。
-- 唯一键把同一 profile/分钟的重复上报合并；历史清理由 bashub 低频执行。
--
-- 兼容上一版实验结构（profile/server/state 列）：先按 profile 名解析 profile_id，
-- 再把同一 profile/时刻的多行聚合成一行 servers 对象，然后替换旧表。

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'bas'
      and table_name = 'mon_server_samples'
      and column_name = 'profile'
  ) then
    drop table if exists bas.mon_server_samples_new;
    create table bas.mon_server_samples_new (
      id bigint not null,
      profile_id bigint not null,
      sampled_at timestamp with time zone not null,
      servers jsonb not null
    );
    insert into bas.mon_server_samples_new (id, profile_id, sampled_at, servers)
    select min(s.id), p.id, s.sampled_at, jsonb_object_agg(s.server, s.state)
    from bas.mon_server_samples s
    join bas.cfg_profiles p
      on p.name = substring(s.profile from strpos(s.profile, '.') + 1)
    join bas.cfg_organizations o
      on o.id = p.org_id and o.name = split_part(s.profile, '.', 1)
    group by p.id, s.sampled_at;
    drop table bas.mon_server_samples;
    alter table bas.mon_server_samples_new rename to mon_server_samples;
    alter table bas.mon_server_samples rename constraint mon_server_samples_new_id_not_null
      to mon_server_samples_id_not_null;
    alter table bas.mon_server_samples rename constraint mon_server_samples_new_profile_id_not_null
      to mon_server_samples_profile_id_not_null;
    alter table bas.mon_server_samples rename constraint mon_server_samples_new_sampled_at_not_null
      to mon_server_samples_sampled_at_not_null;
    alter table bas.mon_server_samples rename constraint mon_server_samples_new_servers_not_null
      to mon_server_samples_servers_not_null;
  end if;
end
$$;

create table if not exists bas.mon_server_samples (
  id bigint not null,
  profile_id bigint not null,
  sampled_at timestamp with time zone not null,
  servers jsonb not null
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'pk_mon_server_samples'
      and conrelid = 'bas.mon_server_samples'::regclass
  ) then
    alter table bas.mon_server_samples
      add constraint pk_mon_server_samples primary key (id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'uq_mon_server_samples_point'
      and conrelid = 'bas.mon_server_samples'::regclass
  ) then
    alter table bas.mon_server_samples
      add constraint uq_mon_server_samples_point unique (profile_id, sampled_at);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'fk_mon_server_samples_profile'
      and conrelid = 'bas.mon_server_samples'::regclass
  ) then
    alter table bas.mon_server_samples
      add constraint fk_mon_server_samples_profile
      foreign key (profile_id) references bas.cfg_profiles (id);
  end if;
end
$$;

create index if not exists idx_mon_server_samples_profile_time
  on bas.mon_server_samples (profile_id, sampled_at);

comment on table bas.mon_server_samples is '节点运行状态采样';
comment on column bas.mon_server_samples.id is '非业务主键:auto_increment';
comment on column bas.mon_server_samples.profile_id is 'Profile ID';
comment on column bas.mon_server_samples.sampled_at is '采样时刻';
comment on column bas.mon_server_samples.servers is 'server 状态: id -> running/stopped/error';
