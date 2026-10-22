-- bashub 0.0.8：为主机记录可选的 setline 数据面 listen 端口（cfg_hosts.setline_listen_port）。
--
-- setline agent 通过 http://<host.ip>:<port>/_setline/routes 拉取路由表；该端口与
-- Profile.setline_port（只在本机执行的 adminListen，用于推路由）是两回事，也不写入
-- server.xml。并非每台主机都部署 setline：空值表示不部署，此时该主机不会进入 peers，
-- 其上的 server 也不能作为 Webapp 的 run-at 目标。
--
-- 可重复执行：列已存在时保持原值。

alter table bas.cfg_hosts add column if not exists setline_listen_port integer;

alter table bas.cfg_hosts alter column setline_listen_port drop not null;

comment on column bas.cfg_hosts.setline_listen_port is 'setlineListenPort?';
