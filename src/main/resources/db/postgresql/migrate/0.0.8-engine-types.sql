-- bas-hub 0.0.8（附）：引擎类型更名，与 basctl 的 creator 类型对齐。
--   cfg_engines.typ    tomcat          -> tomcat-server   （旧值指全量发行包/多应用）
--   cfg_engines.typ    tomcat-dist     -> tomcat-server   （更早的对照名，兼容导入数据）
--   cfg_engines.typ    undertow-embed  -> undertow        （更早的对照名，兼容导入数据）
--   cfg_engines.typ    vibed           -> any             （vibe.d 引擎下线）
--   undertow / jetty / any 保持不变：jetty 重新作为嵌入式单应用可用。
--
-- 为什么必须迁 `tomcat`：旧库里 `tomcat` 指全量发行包，新库里 `tomcat` 改指嵌入式
-- 单应用，与 `tomcat-server` 是两种不同形态；不迁移的话旧记录会被新后端当成单应用
-- 引擎（多个 webapp 部署到同一 farm 时 basctl 会直接报错）。
--
-- 映射集刻意不含 `tomcat-embed` -> `tomcat`：`tomcat` 既是本脚本的输入（旧发行包名）
-- 又是输出（新嵌入名），若纳入该规则，第二次执行会把已改成 `tomcat` 的记录再迁成
-- `tomcat-server`，破坏幂等。`tomcat-embed` 只出现在 basctl 的 creator 里，从未写入
-- cfg_engines.typ（本表由 bashub 与旧 sasadmin 维护），故不需迁；若确有历史数据，
-- 请在**停库后**手工处理，顺序要紧——先跑本脚本，再执行：
--   update bas.cfg_engines set typ = 'tomcat' where typ = 'tomcat-embed';
-- （若先执行这句，它产出的 `tomcat` 会被本脚本的 `tomcat` -> `tomcat-server` 规则吃掉。）
--
-- 执行顺序：**停掉旧后端 → 执行本脚本 → 部署新后端**。
-- 与 0.0.8.sql / 0.0.8-legacy-columns.sql / 0.0.8-schema-rename.sql 相互独立，可单独执行。
-- 可重复执行：where 里的旧值都不在映射输出值集合内，第二次运行是空操作。

update bas.cfg_engines
   set typ = case typ
               when 'tomcat'         then 'tomcat-server'
               when 'tomcat-dist'    then 'tomcat-server'
               when 'undertow-embed' then 'undertow'
               when 'vibed'          then 'any'
               else typ
             end
 where typ in ('tomcat', 'tomcat-dist', 'undertow-embed', 'vibed');

-- 迁移后可自查：以下查询应返回 0 行。
-- select id, name, typ from bas.cfg_engines
--  where typ in ('tomcat-dist', 'undertow-embed', 'vibed');
