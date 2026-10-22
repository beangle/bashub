# PostgreSQL 迁移顺序

升级时先停掉旧后端，再按文件名的两位序号从小到大执行本目录的脚本。脚本均为幂等脚本，
已执行过的步骤可以重复运行。

| 序号 | 脚本 | 说明 |
|---|---|---|
| 01 | `0.0.8-01-schema-rename.sql` | `sas` schema 改名为 `bas`；必须最先执行 |
| 02 | `0.0.8-02-app-channels.sql` | 应用部署字段拆分为 Channel |
| 03 | `0.0.8-03-engine-types.sql` | 引擎类型更名 |
| 04 | `0.0.8-04-legacy-columns.sql` | 清理历史遗留列 |
| 05 | `0.0.8-05-drop-setline-port.sql` | 移除 Profile 的 setline 管理口端口 |
| 06 | `0.0.8-06-profile-certificate.sql` | Profile 增加 HTTPS 证书字段 |
| 07 | `0.0.8-07-webapp-urls.sql` | Webapp 增加对外 URL 前缀 |
| 08 | `0.0.8-08-micdn-component-mount.sql` | 早期 Micdn 组件挂载名上移；须在 10 之前 |
| 09 | `0.0.8-09-micdn-profile-blob.sql` | 清理旧 Blob bucket；须在 10 之前 |
| 10 | `0.0.8-10-micdn-profile.sql` | 完整的 Micdn Profile 迁移；须在 08、09 之后 |
| 11 | `0.0.8-11-profile-setline-port.sql` | Profile 增加 setline 管理口（adminListen）端口 |
| 12 | `0.0.8-12-host-setline-listen-port.sql` | 主机增加可选的 setline listen 端口，供 peer agent 拉取路由 |
| 13 | `0.0.8-13-host-setline-admin-port.sql` | 管理口下沉到主机；把旧 Profile 端口回填给已启用 setline 的主机 |
| 14 | `0.0.8-14-profile-proxy-by-hostname.sql` | Profile 增加 `proxyByHostname`，控制 setline 路由是否按域名分组 |

全新安装直接执行 `../init/*.sql` 建库，不需要运行本目录的升级脚本。
