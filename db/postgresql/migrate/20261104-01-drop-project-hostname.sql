-- project.hostname 已由 endpoint.domain 取代；routes 的 host 现在来自 endpoint。
begin;

alter table bas.cfg_projects drop column if exists hostname;

commit;
