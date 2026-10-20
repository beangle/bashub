-- bas-hub 0.0.8（附）：清理模型中已不存在的历史遗留列。
--   cfg_farms.enable_access_log    79 行，全为 false（原 farm 表单的「访问日志」开关）
--   cfg_servers.enable_access_log  189 行，全为 false（原 server 表单的「访问日志」开关）
--   cfg_hosts.os                   22 行中 9 行有值（CentOS/Fedora 版本串，已被 platform + platform_version 取代）
--   cfg_farms.max_threads          原 HTTP Connector 线程数，已从 Farm 实体、server.xml 模板与 SPA schema 移除
-- 这些列在实体、模板、SPA schema 中均无引用，直接删除，不做归档。
-- 与 0.0.8-02-app-channels.sql 相互独立；已迁移的库再跑是空操作（drop column if exists）。
-- 删列不可逆，如需留底请在执行前自行备份，例如：
--   create table if not exists bas.cfg_farms_bak_0_0_8 as select id, enable_access_log from bas.cfg_farms;

alter table bas.cfg_farms drop column if exists enable_access_log;
alter table bas.cfg_farms drop column if exists max_threads;
alter table bas.cfg_servers drop column if exists enable_access_log;
alter table bas.cfg_hosts drop column if exists os;

-- 早期版本的本脚本会把取值归档到 bas.cfg_legacy_values_0_0_8，如无该表此句为空操作。
drop table if exists bas.cfg_legacy_values_0_0_8;
