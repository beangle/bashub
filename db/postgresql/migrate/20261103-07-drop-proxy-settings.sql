-- 0.0.17 代理配置已完整迁移到 cfg_endpoints；删除旧的 proxy-settings 表。
begin;

drop table if exists bas.cfg_proxy_settings;

commit;
