-- bashub 0.0.8：Profile 增加按域名生成 setline 路由组的开关。
--
-- false（默认）：省略 server.xml 根元素 setline-hostname，basctl 使用 * 默认组。
-- true：要求 Profile.hostname 非空，并把它输出为 setline-hostname。

alter table bas.cfg_profiles
  add column if not exists proxy_by_hostname boolean default false not null;

comment on column bas.cfg_profiles.proxy_by_hostname is 'proxyByHostname?';
