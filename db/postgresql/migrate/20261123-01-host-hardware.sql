-- 0.0.10 Host 的系统/CPU/磁盘现状折叠为 hardware JSON；保留 memory/cores/platform 供查询与配置。
begin;

alter table bas.cfg_hosts
  add column hardware jsonb not null default '{}';

update bas.cfg_hosts
set hardware = jsonb_build_object(
  'schema', 1,
  'source', 'legacy',
  'os', jsonb_build_object(
    'version', platform_version,
    'arch', case arch
      when 1 then 'noarch'
      when 2 then 'x86_64'
      when 3 then 'aarch64'
      else arch::text
    end
  ),
  'cpu', jsonb_build_object('model', cpu),
  'mem', jsonb_build_object('totalBytes', memory::bigint * 1073741824)
);

alter table bas.cfg_hosts
  drop column platform_version,
  drop column cpu,
  drop column arch;

comment on column bas.cfg_hosts.hardware is 'Agent/人工采集的系统与硬件现状 JSON';

commit;
