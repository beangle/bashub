-- 0.0.11 旧项目的 endpoint 域名应来自 project.hostname。
-- proxy_by_hostname 只控制 server.xml 的 setline-hostname，不影响旧代理是否按域名监听。
begin;

update bas.cfg_endpoints e
set domain = nullif(trim(p.hostname), '')
from bas.cfg_projects p
where e.project_id = p.id
  and e.name = 'default'
  and (e.domain is null or e.domain = '')
  and nullif(trim(p.hostname), '') is not null;

comment on column bas.cfg_endpoints.domain is '域名；可选且项目内唯一，空表示无域名代理';

commit;
