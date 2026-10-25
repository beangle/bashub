-- 0.0.8：native engine 支持。
begin;

alter table bas.cfg_artifacts add column exec varchar(255);
comment on column bas.cfg_artifacts.exec is 'native 可执行文件相对路径';

commit;
