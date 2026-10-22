-- bashub 0.0.8：setline 管理口改为主机属性（cfg_hosts.setline_admin_port）。
--
-- 旧模型的 Profile.setline_port 是整组主机共用的管理口；新模型中 setline 是否启用、
-- listen/admin 端口都是机器级事实，写在对应的 Host 上。只回填已经配置了 listen 端口的
-- 主机；没有 listen 端口的旧主机不猜测，由管理员在主机表单里显式启用。

alter table bas.cfg_hosts add column if not exists setline_admin_port integer;

update bas.cfg_hosts h
set setline_admin_port = p.setline_port::integer
from bas.cfg_profiles p
where h.profile_id = p.id
  and h.setline_listen_port is not null
  and (case when p.setline_port ~ '^[0-9]+$'
            then p.setline_port::integer
       end) between 1 and 65535;

alter table bas.cfg_profiles drop column if exists setline_port;

comment on column bas.cfg_hosts.setline_admin_port is 'setlineAdminPort?';
