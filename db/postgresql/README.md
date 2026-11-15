# PostgreSQL 数据库脚本

- `db.xml`：当前 schema 的结构说明，供对照与文档使用。
- `init/*.sql`：全新安装脚本，按文件名序号执行。`0-schemas.sql` 建 schema，
  `1`–`6` 建表/键/索引/约束/注释，`7-auxiliaries.sql` 建公共函数与 `table_sequences`。
- `migrate/*.sql`：已有库的增量迁移，按文件名排序依次执行。

## 迁移文件命名

增量迁移使用日期前缀，不再用项目版本号：

```text
YYYYMMDD-NN-描述.sql
```

例如：

```text
20261024-01-project-proxy.sql
20261103-01-endpoint-domain.sql
20261115-01-endpoint-certificate-expiry.sql
```

同一天有多条迁移时用 `NN` 保持顺序。迁移文件一旦发布不再改名。

## 安装与升级

全新库直接执行：

```bash
for f in init/*.sql; do
  psql -h localhost -U openurp -d bas -v ON_ERROR_STOP=1 -f "$f"
done
```

已有库按时间顺序执行尚未应用的 `migrate/*.sql`。当前结构以 `db.xml` 与 `init/` 为准。
