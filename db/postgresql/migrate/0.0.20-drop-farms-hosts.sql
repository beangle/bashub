-- 0.0.20 Farm 与 Host 没有实际语义，删除遗留关系表。
begin;

drop table if exists bas.cfg_farms_hosts;

commit;
