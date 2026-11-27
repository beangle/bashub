-- 打包类型去掉 bin：运行时已不支持 bin，历史数据按 native 包（tar.gz）归并。
begin;
update bas.cfg_artifacts set packaging = 'tar.gz' where packaging = 'bin';
commit;
