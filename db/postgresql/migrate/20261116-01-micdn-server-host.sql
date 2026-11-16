-- 20261116 Micdn 服务器登记从 adminListen(host:port) 改为 host。
begin;

update bas.cfg_project_micdn p
set config = jsonb_set(
  p.config,
  '{servers}',
  coalesce((
    select jsonb_agg(jsonb_build_object(
      'name', s->>'name',
      'host',
      case
        when s ? 'host' then s->>'host'
        when (s->>'adminListen') ~ '^\[.*\]:[0-9]+$'
          then substring(s->>'adminListen' from '^\[(.*)\]:[0-9]+$')
        else regexp_replace(coalesce(s->>'adminListen', ''), ':[0-9]+$', '')
      end
    ) order by s->>'name')
    from jsonb_array_elements(p.config->'servers') s
  ), '[]'::jsonb)
)
where jsonb_typeof(p.config->'servers') = 'array';

comment on column bas.cfg_project_micdn.config is 'Micdn 聚合配置；servers[].host 为节点地址，代理端口取 listen';

commit;
