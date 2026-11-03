-- 0.0.12 证书已迁移到 cfg_endpoints；删除不再读取的项目证书表。
-- 执行前确认 0.0.10 已把项目证书复制到 default endpoint，并备份数据库。
begin;

drop table if exists bas.cfg_project_certificates;

commit;
