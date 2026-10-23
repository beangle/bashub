# PostgreSQL 数据库脚本

- `db.xml`：当前 schema（0.0.8）的结构说明，供对照与文档使用。
- `init/*.sql`：全新安装脚本，按文件名序号执行。`0-schemas.sql` 建 schema，
  `1`–`6` 建表/键/索引/约束/注释，`7-auxiliaries.sql` 建公共函数与 `table_sequences`。

0.0.8 起仓库不再提供增量迁移脚本：全新库直接执行 `init/*.sql`；已有旧库需要历史迁移时，
从 git 历史取回原 `migrate/0.0.8-*.sql` 按序号执行。当前结构以 `db.xml` 与 `init/` 为准。

```bash
for f in init/*.sql; do
  psql -h localhost -U openurp -d bas -v ON_ERROR_STOP=1 -f "$f"
done
```
