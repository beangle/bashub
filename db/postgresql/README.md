# PostgreSQL 数据库脚本

- `db.xml`：当前 schema（0.0.8）的结构说明，供对照与文档使用。
- `init/*.sql`：全新安装脚本，按文件名序号执行。`0-schemas.sql` 建 schema，
  `1`–`6` 建表/键/索引/约束/注释，`7-auxiliaries.sql` 建公共函数与 `table_sequences`。

0.0.8 提供项目/代理结构调整的增量迁移：全新库直接执行 `init/*.sql`；已有 0.0.8 旧结构
执行 `migrate/0.0.8-project-proxy.sql` 升级；agent 中继再执行
`migrate/0.0.8-agent-relay.sql`。当前结构以 `db.xml` 与 `init/` 为准。

```bash
for f in init/*.sql; do
  psql -h localhost -U openurp -d bas -v ON_ERROR_STOP=1 -f "$f"
done
```
