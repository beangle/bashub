-- 20261119 停止按 Project 配置公网远程仓库；server.xml 由本地 micdn 地址生成。
begin;

alter table bas.cfg_projects drop column if exists remote_repo;

commit;
