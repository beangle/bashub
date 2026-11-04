-- setline agent 只运行在代理侧，主机不再登记 setline 监听/管理端口。
begin;

alter table bas.cfg_hosts drop column if exists setline_listen_port;
alter table bas.cfg_hosts drop column if exists setline_admin_port;

commit;
