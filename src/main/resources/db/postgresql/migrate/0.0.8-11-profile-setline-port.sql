-- bashub 0.0.8：恢复 Profile 的 setline 管理口端口（cfg_profiles.setline_port）。
--
-- basctl 的 conf/server.xml 用 <setline port="..."> 声明要推路由的 setline 管理口
-- （adminListen）。该端口属于节点运行参数，但由 Profile 统一下发：同一 Profile 下的
-- 节点共用同一个管理口端口，生成的 server.xml 才会包含 <setline>。留空表示不启用
-- setline，不会使用 8080 等隐式缺省值；8080 通常是 web/API 的监听端口。
--
-- 可重复执行：该列已存在时是空操作。

alter table bas.cfg_profiles add column if not exists setline_port varchar(255);

comment on column bas.cfg_profiles.setline_port is 'setlinePort?';
