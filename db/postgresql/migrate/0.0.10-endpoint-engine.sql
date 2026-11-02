-- 0.0.10 endpoint 自带代理引擎，并把项目证书复制到 default endpoint。
begin;

alter table bas.cfg_endpoints
  add column engine varchar(255) not null default 'haproxy';

update bas.cfg_endpoints e
set engine = coalesce(nullif(trim(p.proxy_engine), ''), 'haproxy')
from bas.cfg_proxy_settings p
where p.project_id = e.project_id;

update bas.cfg_endpoints e
set certificate = c.certificate,
    private_key = c.private_key
from bas.cfg_project_certificates c
where c.project_id = e.project_id
  and e.name = 'default'
  and (e.certificate is null or e.certificate = '')
  and (e.private_key is null or e.private_key = '');

comment on column bas.cfg_endpoints.engine is '代理引擎：haproxy / nginx';

commit;
