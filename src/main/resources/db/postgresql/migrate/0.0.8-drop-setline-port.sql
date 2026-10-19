-- bashub 0.0.8：移除 Profile 的 setline 管理口端口（cfg_profiles.setline_port）。
--
-- setline 管理口属于节点自己的 setline.conf，不再由 Profile 保存；生成的 server.xml
-- 也不再声明 <setline>。曾执行过 0.0.8-setline.sql 的数据库用本脚本清理遗留列。
-- 可重复执行。

alter table bas.cfg_profiles drop column if exists setline_port;
