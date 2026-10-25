# Agent 组网与 master 中继

> 一个 project 可以有多台 agent，但只让每个组网分组中的一台 master 直连 bashub；
> 其他 agent 作为 follower 连 master，由 master 中继上报与命令。

## 1. 配置

### Project

```text
agent_listen_port   项目内所有 agent 共用的组网端口，默认 19080
```

### Host

```text
agent_group         组网分组，默认 default_group
```

`server.xml`：

```xml
<bas version="0.14.0" agent-listen-port="19080">
  <hosts>
    <host name="app1" ip="10.0.0.10" agent-group="site-a"/>
    <host name="app2" ip="10.0.0.11" agent-group="site-a"/>
    <host name="app3" ip="10.0.0.12" agent-group="site-b"/>
  </hosts>
</bas>
```

同一 group 内 agent 必须能通过 `ip:agent-listen-port` 互相连接。

## 2. 角色

| 角色 | 含义 |
|---|---|
| `candidate` | 刚连上 hub，等待选主 |
| `master` | 当前分组的 master，保持 hub 连接 |
| `follower` | 已跟随 master，不再连 hub |

所有 agent 启动时都是 `candidate`；没有人工指定 master。

## 3. 连接流程

```text
所有 agent 连 hub
  → 上报一次
  → 探测本组其他 agent 的固定端口
  → 选可达且顺序最靠前的 host 作为 master 候选
  → 向 hub 发送 recommend
  → hub 原子决定唯一 master
  → master 保持 hub；follower 断开 hub，连 master
```

follower 连 master 成功后，master 在 hub 的逻辑会话中登记该 follower；
UI 按逻辑 agent 展示每台机器。

## 4. hub 的原子推荐

hub 按 `(project, group)` 保存一条 master 租约：

```text
master_ip
term
expires_at
```

agent 发送：

```json
{"type":"recommend","body":{"candidate":"10.0.0.10","group":"site-a"}}
```

hub 在原子操作中：

1. 若租约有效，返回当前 master
2. 若租约为空/过期，写入推荐候选，`term++`
3. 向候选发送 `become-master`
4. 向同组其他 agent 发送 `become-follower`，带 master 地址和端口

不需要被推荐者二次确认；它收到 `become-master` 后开始服务。若它没有真正启动，
租约到期后由下一次推荐替换。

## 5. 租约

- master 连接 hub 期间，hub 周期刷新 `expires_at`
- master 连接断开，租约立即失效
- follower 不收租约，只读 hub 分配的 master
- 旧 master 恢复后 term 已变，只能作为 follower

## 6. follower 连不上 master

| 场景 | 处理 |
|---|---|
| follower 连不上 master，但能连 hub | 保持 hub 连接，有限重试；不覆盖有效租约 |
| follower 连不上 master，也连不上 hub | 指数退避，只记录状态变化，不自我升主 |
| master 连着 hub，但多个 follower 连不上 | 由 follower 报告，hub 可让租约失效后重新选主 |
| master 失联 | hub 断开租约；follower 重连 hub 后重新推荐 |

## 7. 日志和 CPU

- 只在角色变化、连接状态变化时打日志
- 连接失败指数退避，最大 60 秒
- 探测仅在启动/重新选主时执行，并发受限、超时 1 秒
- `recommend` 失败按退避重试，不忙轮询
- hub 侧按 group 汇总，不逐 follower 刷日志

## 8. 当前限制

- master/follower 之间暂不使用 TLS，使用 project key
- hub 是单实例仲裁者；hub 重启会重新选主
- 一个 group 只有一个 master；若组内网络被防火墙切成互不连通的分区，需要人工调整 group
- 没有自动抢占：已有有效 master 时，新 agent 只作为 follower
