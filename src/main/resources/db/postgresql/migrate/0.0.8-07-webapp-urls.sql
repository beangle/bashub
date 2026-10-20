-- bas-hub 0.0.8（附）：webapp 增加对外 URL 前缀（cfg_webapps.urls，jsonb 数组）。
--
-- 背景：原来只有 context_path，路由器（setline / nginx / haproxy）只能按它转发。上下文为 / 的
-- webapp（内部 URL 无公共前缀，如 /context1、/context2）与另一个同类应用无法区分，反代里只能
-- 保留其中一个。新增的 urls 逐条列出对外路径；为空数组表示仍按 context_path 转发。
--
-- 执行顺序：**停掉旧后端 → 执行本脚本 → 部署新后端**。
-- 与其他脚本相互独立；升级时仍按本目录的文件序号执行。
-- 可重复执行：存量行回填成 [] 后再补 not null，已是 not null 时是空操作。
-- 存量数据不需要别的迁移：urls 为 [] 即等价于原来的按 context_path 转发。

alter table bas.cfg_webapps add column if not exists urls jsonb;

-- 实体侧缺省是空数组，存量行必须回填后才能在模型里补 not null。
update bas.cfg_webapps set urls = '[]'::jsonb where urls is null;

alter table bas.cfg_webapps alter column urls set not null;

comment on column bas.cfg_webapps.urls is 'urls?';
