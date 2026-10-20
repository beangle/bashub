-- bas-hub 0.0.8（附）：Profile 增加 HTTPS 公钥证书与私钥。
--
-- 证书按 nginx 的两项属性保存：
--   ssl_certificate      PEM 公钥证书（可含完整中间链，供 nginx ssl_certificate）
--   ssl_certificate_key  PEM 私钥（供 nginx ssl_certificate_key）
-- 管理台只回显公钥，私钥脱敏；setline pull 通过带 Profile.key 的机器端点读取原文，
-- 分别落成 cert.pem / key.pem，并拼出 haproxy 需要的 bundle.pem。
--
-- 两点都可空：未启用 HTTPS 的 Profile 不需要证书。脚本可重复执行。

alter table bas.cfg_profiles add column if not exists ssl_certificate text;
alter table bas.cfg_profiles add column if not exists ssl_certificate_key text;

comment on column bas.cfg_profiles.ssl_certificate is 'sslCertificate?';
comment on column bas.cfg_profiles.ssl_certificate_key is 'sslCertificateKey?';
