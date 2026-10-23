-- bashub 0.0.8：SSL 公私钥从 cfg_profiles 拆到 cfg_profile_certificates。
--
-- profile 的列表/详情/监控 enrich 不再携带证书大字段；证书只给专用端点与 setline 下载端点读取。
-- 可重复执行：表已存在时跳过建表；旧列已删时跳过数据搬迁。

create table if not exists bas.cfg_profile_certificates (
  profile_id bigint not null,
  certificate text,
  private_key text
);

alter table bas.cfg_profile_certificates drop constraint if exists pk_cfg_profile_certificates;
alter table bas.cfg_profile_certificates add constraint pk_cfg_profile_certificates primary key (profile_id);

alter table bas.cfg_profile_certificates drop constraint if exists fk_cfg_profile_certificates_profile;
alter table bas.cfg_profile_certificates
  add constraint fk_cfg_profile_certificates_profile foreign key (profile_id) references bas.cfg_profiles (id);

comment on column bas.cfg_profile_certificates.profile_id is 'Profile ID';
comment on column bas.cfg_profile_certificates.certificate is '公钥证书(PEM)';
comment on column bas.cfg_profile_certificates.private_key is '私钥(PEM)';

do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'bas' and table_name = 'cfg_profiles' and column_name = 'ssl_certificate') then
    insert into bas.cfg_profile_certificates (profile_id, certificate, private_key)
    select id, ssl_certificate, ssl_certificate_key
      from bas.cfg_profiles
     where coalesce(ssl_certificate, '') <> '' or coalesce(ssl_certificate_key, '') <> ''
    on conflict (profile_id) do update
       set certificate = coalesce(excluded.certificate, bas.cfg_profile_certificates.certificate),
           private_key = coalesce(excluded.private_key, bas.cfg_profile_certificates.private_key);
  end if;
end $$;

alter table bas.cfg_profiles drop column if exists ssl_certificate;
alter table bas.cfg_profiles drop column if exists ssl_certificate_key;
