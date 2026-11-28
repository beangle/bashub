# 监控与部署状态使用说明

本文面向日常运维：在 PC 或手机上看实例是否需要重启、如何确认新版本已经生效，以及启停记录、代理配置状态和日志的入口与边界。

## 1. 数据从哪里来

监控不直接读客户机，所有判断都基于 agent 的 `report:bas`：

- `basReport.instances`：**正在运行**的实例；每个实例带 `id`、`pid`、`httpPort`、`started`、`webapps[]`，每个 webapp 带 `uri`、`context`、`urls`。
  `uri` 是 `gav://groupId:artifactId:packaging[:classifier]:version`，版本就在里面。
- `basReport.declared`：节点本机当前 `server.xml` 声明的实例和 webapp（每次上报重新读取）；即使实例停止也有。
- `instances[].webapps` 是 basctl **启动实例时**写下的 `server.info` 清单，不是应用级实时健康上报；单独热替换或某个应用挂掉不会刷新这份清单。

hub 把三边放在一起比较：

```text
hub 的 webapp 配置（期望的 gav/context/urls/targets）
  ↔ agent declared（server.xml 是否已经下发）
  ↔ instances[].webapps（实际启动的 uri/context/urls）
```

## 2. 状态怎么读

每个在线实例的 `deployment.state` 只有以下几种：

| state | 含义 | 界面表现 |
|---|---|---|
| `ok` | 运行中的实例与配置一致；或实例停止、但 `declared` 与配置一致 | 不显示提示。停止只是“没在跑”，不是配置问题 |
| `restart` | 实例在跑，但版本/组件/上下文/`urls`/端口与配置不同 | 显示「待重启」；明细里是待加载、待删除、待重启项 |
| `undelivered` | hub 配置与 agent `declared` 不一致，新配置还没到节点 | 显示「未下发」，稍后自动同步，不要急着重启 |
| `unknown` | 实例 id 在项目配置里找不到（服务器未登记/配置已删除） | 显示「未知」 |

`ok` 的停止实例不会显示「启动后生效」：配置一致，启动后自然用当前配置，没有待处理项。只有 `undelivered` 才需要关注。

没有上报的节点（离线）没有运行态，无法判断；界面只显示离线，不显示部署状态。

## 3. 在哪里看

**PC**

- `/monitor/agents`：实例行第一列 Server 名字上方显示状态标签（待重启/未下发/未知）。
- `/monitor/agents/:project/servers/:instance`：运行状态标题栏的简短提示；右侧是应用和最近启停记录。鼠标悬停提示可看具体差异项。
- `/config/projects/:id` 的「部署概况」：统计「配置待生效」。
- `/monitor/agents/:project/events`：按 Project/实例查看启停记录。

**手机**

- 项目概览：`N 个运行实例的部署配置待生效`。
- 项目节点 `/projects/:project/nodes`：实例名后面显示待重启/未下发/未知，右侧只保留内存和运行状态，保持对齐。
- 实例页 `/projects/:project/instances/:instance`：「配置状态」卡片列出差异。
- 项目概览的「启停记录」或实例页「全部」：`/projects/:project/events`。

## 4. 典型操作

### 升级一个部署的版本

1. 在部署详情修改版本并保存。配置已经改了，但运行中的实例不会自动重启。
2. 等状态从「未下发」变成「待重启」（agent 拉取新的 `server.xml` 后）。
3. 到实例页重启对应实例；重启后 agent 重新上报，运行 `uri` 与配置一致，状态恢复 `ok`。
4. 如果重启后仍是「待重启」，先确认 agent 是否已经拿到新配置（看「未下发」是否已消失），再看运行 `uri` 是否与配置版本一致。

### 修改运行目标或删部署

- 旧 server 上会显示待删除/待重启，新 server 上可能是待加载/未下发；按提示重启或启动对应实例。
- 删除部署只删配置；运行中的实例不会自动停止，重启后才会移除。

### 实例处于停止状态

- 配置已下发且一致：不显示提示，启动后即用当前配置。
- 配置未下发：显示「未下发」；等 agent 同步后再启动。

### 改代理

应用的上下文、对外路径、运行目标或 endpoint/证书变化会影响代理配置，这部分不在实例对账里：

- PC 代理页/手机项目概览显示「代理待应用」时，调用「应用」让代理节点 `proxy:apply`。
- 「已应用」只以 hub 成功应用的 bundle hash 为准；有人在 hub 外手工应用或直接改客户机文件，hub 不会发现。
- 先重启受影响的实例、再应用代理，避免代理路由指向尚未加载新上下文的实例。

## 5. 启停记录

PC/手机通过 hub 触发的 `start` / `stop` / `restart` 都会写入 `bas.mon_server_events`：

- 字段：实例、动作、操作人、操作人 IP、执行节点、成功/失败、原因、时间。
- 节点离线、超时、节点拒绝也会记录，用于解释“谁在什么时候动过哪台实例”。
- PC 在线节点页和手机项目概览都有「启停记录」入口；PC 实例页保留最近 20 条。
- 只在 hub 触发的动作会记录；直接在服务器上执行 systemctl/basctl 不会进入这张表。

## 6. 日志

- 读的是实例的 `logs/<instance>/console.out` 尾部；实例没启动过或日志被清理时，接口返回空窗口，页面显示「暂无日志」，不再报 502。
- 老 agent 不支持 `log:read` 时返回 409「节点不支持该指令」，需要升级 agent。
- 日志是实例启动时的 console 输出，不是应用级健康检查。

## 7. 已知边界

- 只覆盖在线节点；离线节点无从判断。
- `instances[].webapps` 是启动清单，不是实时应用状态；热替换、单应用崩溃不会自动反映，只有重启实例才刷新。
- agent 不上报 `libs`、`unpack`、`exec`、endpoints 等字段，因此这些配置变化目前无法从运行态对账里发现。
- 应用标题由 hub 按配置补；配置删除后，运行上报里只剩 `uri`/context。
- 手工在 hub 外改客户机文件或启停实例，不在检测和记录范围内。
- 部署状态不能代替应用自身的健康检查；它只回答“运行中的版本/上下文是否与配置一致、配置是否已经到节点”。

## 8. 相关文档

- 页面与 API 对照：[frontend-routes.md](frontend-routes.md)
- 监控 API 字段：[frontend-api.md](frontend-api.md)
- 手机端页面说明：[frontend.md](frontend.md)
