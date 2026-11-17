-- 20261117 清理 Micdn 节点 host 中误填的端口：端口统一取 config.listen。
begin;

update bas.cfg_project_micdn p
set config = jsonb_set(
  p.config,
  '{servers}',
  coalesce((
    select jsonb_agg(jsonb_build_object(
      'host',
      case
        when (s->>'host') ~ '^\[[^]]+\]:[0-9]+$'
          then substring(s->>'host' from '^\[([^]]+)\]')
        when (s->>'host') ~ '^[^:]+:[0-9]+$'
          then regexp_replace(s->>'host', ':[0-9]+$', '')
        else s->>'host'
      end
    ))
    from jsonb_array_elements(p.config->'servers') s
  ), '[]'::jsonb)
)
where jsonb_typeof(p.config->'servers') = 'array';

comment on column bas.cfg_project_micdn.config is 'Micdn 聚合配置；servers[].host 只含节点地址，端口取 listen';

commit;
