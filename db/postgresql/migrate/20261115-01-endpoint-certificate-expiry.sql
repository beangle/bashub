-- 20261115 记录证书过期时间，供管理台显示与到期提醒。
begin;

alter table bas.cfg_endpoints
  add column if not exists certificate_not_after varchar(64);

comment on column bas.cfg_endpoints.certificate_not_after is '证书过期时间；自动解析或人工填写';

commit;
