# Wear Engine 探针（G0）· 2026-11-13

> ⚠️ **2026-11-16 起废弃**：Wear Engine 服务申请被华为驳回（驳回信第 4 条：手机 App 未活跃时
> 手表→手机 P2P 发送失败），整条 B 路径改为**全网络客户端**。
> 现行规格：`Docs/superpowers/specs/2026-11-16-watch-network-client-design.md`；
> 现行探针：`Docs/analysis/手表网络探针-2026-11-16.md`。本文仅留作取证历史。

> 对应规格：`Docs/superpowers/specs/2026-11-13-watch-interaction-b-path.md` §4
> 状态：**AGC 服务申请已提交（开通待审核）**；真机探针仍停在 `1008500004`，
> 待审批通过后重跑 `--ps wearecho 1` 继续 G0-b~f。代码已就绪但不宣称手表交互可用。

## 0. 一句话结论

- 通信 API 在本机 SDK 中**确实存在**（`@kit.WearEngine`，手机与 wearable 均支持），
  P2P 消息上限、错误码、对端匹配参数都能从 `.d.ts` 直接读出来。
- **真机实测（Pocket 2，2026-11-13 22:18）**：
  1. 首次探针报 `1008509999 The client ID is not configured in the metadata of the application`
     → 已在 `entry/src/main/module.json5` 补 `metadata: client_id = 6917619826312400726`（AGC APP ID 同值）；
  2. 补配置后报 **`1008500004 App has not applied for the Wear Engine service`**
     → G0-a 不通过：需要在 AGC 申请 Wear Engine 服务。
- **2026-11-14 16:24 已在 AGC 提交服务申请**（个人开发者、HarmonyOS应用、鸿蒙智能穿戴设备、
  设备基础信息 + 消息通知），状态「开通待审核」，官方审批周期 1~2 周。详见 §9。
- G0-b ~ G0-f 与手表侧 US 验收仍无法继续取证（等服务准入）。
  手机侧代码连不上即静默降级，不影响现有功能。

## 1. 取证环境

| 项 | 值 |
|---|---|
| SDK | `/Applications/DevEco-Studio.app/Contents/sdk/default/hms/ets/api/@hms.health.wearEngine.d.ts`（2125 行） |
| Kit 入口 | `/Applications/DevEco-Studio.app/Contents/sdk/default/hms/ets/kits/@kit.WearEngine.d.ts` |
| 设备支持表 | `.../hms/ets/api/device-define/api-version/WearEngine.json` |
| 目标机 | HUAWEI Watch 5（wearable）+ HUAWEI Pocket 2（phone，`LEM-AL00`） |
| 本次已连接设备 | 仅 `192.168.31.38:46077`（Pocket 2）；**手表未连 hdc** |
| 探针代码 | 手机 `entry/src/main/ets/watch/*` + `entryability/EntryAbility.ets` 的 `maybeWatchEchoProbe`；手表 `wearable/` |

> **与规格的一处勘误**：规格 §2 F5 写的 `import { wearEngine } from '@kit.WearEngineKit'`
> 在本机 SDK 里不存在。正确入口是 `@kit.WearEngine`（内部转发 `@hms.health.wearEngine`），
> 代码已按 SDK 实际声明实现。

## 2. 静态事实（可直接作为证据）

| # | 问题 | 实测值（来自 SDK 声明） | 来源 |
|---|---|---|---|
| S1 | 模块/Kit 名 | `@kit.WearEngine` → `wearEngine`；syscap `SystemCapability.Health.WearEngine` | `@kit.WearEngine.d.ts`、`@hms.health.wearEngine.d.ts:26` |
| S2 | 设备支持 | phone 5.0.0(12)、tablet 5.0.0(12)、**wearable 5.1.0(18)** | `device-define/api-version/WearEngine.json` |
| S3 | 设备发现 | `getDeviceClient(context).getConnectedDevices(): Promise<Device[]>`；Device 含 `randomId / category / name / softwareVersion / model / isSmartWatch / osCategory` | `d.ts:212-362` |
| S4 | 能力查询 | `device.isWearEngineCapabilitySupported(WearEngineCapability.P2P_COMMUNICATION)` | `d.ts:292`、`d.ts:46` |
| S5 | 收发 | `P2pClient.sendMessage(deviceRandomId, P2pAppParam, P2pMessage)`；`registerMessageReceiver(deviceRandomId, P2pAppParam, cb)` | `d.ts:716`、`d.ts:802` |
| S6 | 消息约束 | `P2pMessage.content: Uint8Array`，**字节数 [1, 4096)** | `d.ts:479-488`、`d.ts:696` |
| S7 | 对端匹配 | `AppInfo { bundleName, fingerprint }`；`P2pAppParam.transformLocalAppInfo?` 可走云端兼容映射 | `d.ts:371-388`、`d.ts:521-545` |
| S8 | 发送结果码 | `P2pResultCode`: 200 未安装 / 201 未运行 / 202 运行中 / 203 未知 / 206 通信失败 / **207 成功** | `d.ts:396-445` |
| S9 | 关键错误码 | `1008500004` App 未申请 Wear Engine 服务；`1008500005` HUAWEI ID 未授权；`1008500006` 未同意隐私；`1008500007` 设备能力不支持；`1008500008/09` 账号异常；`1008509999` 内部错误 | 各 API `@throws` |
| S10 | 权限标注 | `.d.ts` 里**没有任何 `@permission` 标注**；准入闸门是「AGC 申请 Wear Engine 服务」，不是运行时权限 | `d.ts` 全文 |
| S11 | 启动对端应用 | `startRemoteApp(randomId, remoteBundleName)`；6.1.1(24) 起支持 `AppInfo + StartConfig` | `d.ts:663-689` |
| S12 | 模板通知（备选通道） | `NotifyClient.notify()`：标题 [1,28) 字节、正文 [1,400) 字节、最多 3 个按钮，`onActionTriggered` 回传按钮动作 | `d.ts:1226-1526` |

### S12 的意义（若 G0-a 只放开「通知」不放开 P2P）

Wear Engine 自带**带按钮的模板通知**与动作回传：
`NOTIFICATION_WITH_ONE_BUTTON / TWO / THREE` + `NotificationAction.FIRST/SECOND/THIRD_BUTTON_CLICKED`。
这条通道同样受 `1008500004` 约束，但它不要求手表安装自家 App——
若真机证明 P2P 第三方不可用、而模板通知可用，可降级成「手表通知按钮 → 回传动作」，
语义仍是「手机裁决」。**本次未实现**，只作为 G0 失败决策树里的备选记录。

## 3. G0 清单（真机取证位）

> 逐项状态：`[静态已证]` = SDK 声明可回答；`[真机已证]` = 已有 hilog 证据；`[阻断]` = 前置闸门未过。

### 3.0 真机日志（原文，Pocket 2 `192.168.31.38:46077`）

第一次（未配 client_id）：

```
YouJing.Probe.WatchEcho: wearecho=1 已登记（热启=false），等待桥接初始化
YouJing.Watch.Bridge: 桥接就绪 current=无 pending=0 echo=true
YouJing.Watch.Transport: Wear Engine 初始化失败 code=1008509999 msg=The client ID is not configured in the metadata of the application.
YouJing.Watch.Bridge: Wear Engine 通道=不可用（不可用不影响手机侧功能）
YouJing.Probe.WatchEcho: 已发 hello ok=false；手表应显示「收到」并回 pong
```

补 `client_id` 后（第二次）：

```
YouJing.Watch.Transport: Wear Engine 初始化失败 code=1008500004 msg=App has not applied for the Wear Engine service
YouJing.Watch.Bridge: Wear Engine 通道=不可用（不可用不影响手机侧功能）
```

结论：**client_id 配置已生效；当前唯一阻断是「未申请 Wear Engine 服务」。**

补充一条同日的**出站路径真机证据**（`--ps watchcardprobe 1`，不依赖通道）：

```
YouJing.Watch.Bridge: 桥接就绪 current=无 pending=0 echo=false
YouJing.Watch.Bridge: Wear Engine 通道=不可用（不可用不影响手机侧功能）
YouJing.Watch.Bridge: 出站请示卡 cardId=probe-unplanned-博览园 options=3 recommended=move_tomorrow
YouJing.Probe.WatchCard: 合成请示卡已浮出 id=probe-unplanned-博览园 options=3
YouJing.Probe.WatchCard: 合成卡已收起：出站投影与撤卡路径均已走一遍
```

说明「投影 + 落盘 + 撤卡」在真机上不崩；缺的只是 P2P 通道本身。

再补一条**打卡路由真机证据**（`--ps watchcheckinprobe 1`，用临时行程模拟手表决策）：

```
YouJing.Watch.Bridge: 出站打卡卡 cardId=checkin-watchprobe%2D1794580096968-probe%2Dstop stop=探针站
YouJing.Watch.Bridge: 丢弃决策 cardId=… 原因=card-not-live
YouJing.Watch.Bridge: 手表打卡落库 trip=watchprobe-1794580096968 stop=probe-stop source=manual
YouJing.Probe.WatchCheckin: rows=1 source=manual lat=0 lng=0 （期望 rows=1 source=manual lat=0 lng=0）
YouJing.Probe.WatchCheckin: 临时行程与打卡已清理
```

即：**US-3（source=manual、无伪造坐标）与 US-6（连发两次只落一行）已在真机验证**，
且临时数据已清理。这条路径不依赖 Wear Engine 通道。

再补一条**离页队列真机证据**（`--ps watchqueueprobe 1`）：

```
YouJing.Watch.Bridge: 决策 cardId=probe-queue-… option=move_tomorrow → queue(offpage)
YouJing.Watch.Bridge: 离页决策入队 cardId=probe-queue-… option=move_tomorrow stake=low
YouJing.Probe.WatchQueue: 离页决策后 pending=1（期望 1）
YouJing.Watch.Bridge: 离页决策已执行 cardId=probe-queue-… option=move_tomorrow
YouJing.Probe.WatchQueue: 消费=1 执行器收到=move_tomorrow pending=0 （期望 1/move_tomorrow/0）
```

即 **US-7 的「离页入队 → 回页消费」链路已在真机验证**（偏好计数走同一条 recordChoice）。

| 项 | 要回答的问题 | 当前状态 | 取证方式 / 判据 |
|---|---|---|---|
| **G0-a 第三方准入** | 普通第三方应用能否调通 Wear Engine？是否要签协议/申请权益？ | **真机证 `1008500004`；2026-11-14 已提交服务申请，开通待审核** | 审批通过后重跑 `--ps wearecho 1`；成功即「通道就绪 + 收发 207」 |
| **G0-b 设备发现** | 手机能否列出已配对手表？返回结构？ | `[静态已证]` API 与字段见 S3；**被 G0-a 阻断** | 服务开通后重跑 `--ps wearecho 1`，看 `已发现设备数=N` |
| **G0-c 对端识别** | 手机与手表应用如何关联？是否要求同 bundleName？ | **被 G0-a 阻断**；当前按同 bundleName + 空指纹注册 | 服务开通后看是否仍报 `401`/对端不匹配；需要时从 AGC 取指纹回填 `WATCH_REMOTE_FINGERPRINT` |
| **G0-d 后台收取** | 手表 App 不在前台时能否收到消息并抬腕提醒？ | **被 G0-a 阻断** | 代码已兼容「推送/拉取」两种结论：手表每次连上都发 `sync` 补当前卡 |
| **G0-e 消息约束** | 单条大小上限？文本/JSON？断连可靠性？ | `[静态已证]` JSON 走 Uint8Array，**1–4096 字节**；可靠性 SDK 未承诺 | 服务开通后看 `发送成功 bytes=…`；断连靠 `sync` + 幂等，不依赖补发 |
| **G0-f 权限** | 需要哪些权限？`DISTRIBUTED_DATASYNC` 是否够？ | `[静态已证]` d.ts 无 `@permission`；闸门是服务申请 | 服务开通后若报权限错，再补 `module.json5`；证明前不声明 |

## 4. 探针操作单（真机照做）

前置：手机与手表已配对、手表已开启开发者模式并允许调试；手机装上本轮 debug 包。

### 4.1 手机侧发起

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
T=<手机 connect-key>            # 当前为 192.168.31.38:46077
$HDC -t $T install -r entry/build/default/outputs/default/entry-default-signed.hap
$HDC -t $T shell hilog -r
$HDC -t $T shell aa start -a EntryAbility -b com.youjing.app --ps wearecho 1
sleep 5
$HDC -t $T shell hilog -x | grep -E 'YouJing\.(Watch|Probe\.WatchEcho)'
```

期望日志顺序：

1. `YouJing.Watch.Bridge: 桥接就绪 … echo=true`
2. `YouJing.Watch.Transport: 已发现设备数=1` → `候选设备 … name=HUAWEI WATCH 5 … smartWatch=true`
3. `YouJing.Watch.Transport: 通道就绪 device=…`
4. `YouJing.Probe.WatchEcho: 已发 hello ok=true`
5. 手表屏幕出现「收到：youjing-watch-echo」+「回 ping」
6. 点手表「回 ping」→ 手机日志 `YouJing.Probe.WatchEcho: 收到对端消息: {"pong":"youjing-watch-pong",…}`

### 4.2 手表侧

手表模块构建产物：`wearable/build/default/outputs/default/wearable-default-signed.hap`。
安装方式取决于手表调试通道（`hdc list targets` 能列出表时用 `hdc -t <表> install`）。
安装后打开「有径」手表 App：未连接时显示「未连接手机」，连上后显示「暂无待决」；
收到 hello 后显示回声页。

### 4.3 结果记录表（真机现场填）

| 项 | 实测值 | 证据（hilog 行 / 截图） |
|---|---|---|
| G0-a 准入 | **失败：`1008500004 App has not applied for the Wear Engine service`**（补 client_id 前为 `1008509999`） | 见 §3.0 两段日志原文 |
| G0-b 设备发现 | 被 G0-a 阻断，未取证 | — |
| G0-c 对端匹配 | 被 G0-a 阻断，未取证 | — |
| G0-d 后台收取 | 被 G0-a 阻断，未取证 | — |
| G0-e 大小/可靠性 | 静态：1–4096 字节；真机未取证 | `@hms.health.wearEngine.d.ts:696` |
| G0-f 权限 | 静态：d.ts 无 `@permission`；真机未取证 | `d.ts` 全文 |

## 5. 决策树（按规格 §4.4，预先写明不硬闯）

| 真机结论 | 动作 |
|---|---|
| **G0-a 失败（`1008500004` / 无权益）——本次已命中** | **B 路径停摆**。保留 F2 通知文字兜底；如实告知用户需华为侧准入。代码保留但不启用（连不上即静默降级，不伪造交互） |
| G0-d 只能拉取 | UX 改为「抬腕打开有径手表 App 即见当前卡」；`sync` 已实现，只改文案与用户告知 |
| G0-c/e 受限 | 只调协议与注册方式（指纹、分包），不改「手机裁决」原则 |
| G0 全绿 | 继续 US-1~US-10 真机走查（见规格 §8），再谈上架 |

### 5.1 下一步（用户侧，Trae 不代办）

1. ~~在 AGC 为 `com.youjing.app` 申请 Wear Engine 服务~~ —— **2026-11-14 16:24 已提交**（见 §9）。
2. 等待审批结果（官方说明 1~2 周，邮件/短信/站内信通知）；期间无需重复提交。
3. 审批通过后，`client_id` 若与 APP ID 不同，改
   `entry/src/main/module.json5` 与 `wearable/src/main/module.json5` 两处 metadata 即可。
4. 重跑 `--ps wearecho 1`；若仍报对端不匹配，再按 G0-c 回填 `WATCH_REMOTE_FINGERPRINT`。
5. G0 全绿后才进入 US-1~US-10 真机走查与手表上架流程。

## 6. 本轮代码落点

| 文件 | 作用 |
|---|---|
| `watchcontract/src/main/ets/WatchProtocol.ets` | 线协议类型 + 编解码 + 打卡 cardId（单一真源） |
| `watchcontract/src/main/ets/WatchProjection.ets` | CompanionPrompt → WatchCard 扁平投影、打卡卡 |
| `entry/src/main/ets/watch/WatchRoute.ets` | 路由决策表 + 入站前置校验（过时/跨账号），纯逻辑可离线测 |
| `entry/src/main/ets/watch/WatchBridge.ets` | 出站 / 入站 / 幂等 / 离页队列 / 打卡落库 / 账号隔离 |
| `entry/src/main/ets/watch/WearEngineTransport.ets` | 手机侧 Wear Engine 收发（唯一碰 @kit.WearEngine 的文件） |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 桥接初始化 + `--ps wearecho 1` / `--ps watchcardprobe 1` / `--ps watchcheckinprobe 1` 探针 |
| `entry/src/main/ets/pages/OnTripPage.ets` | 到站推打卡卡、手表打卡刷新、离页队列消费 |
| `entry/src/main/ets/common/location/ArrivalNotice.ets` | 到站通知补社交通讯提醒槽位（US-9 文字兜底，避免静默不转发） |
| `wearable/` | 手表 entry 模块：回声页 + 一屏一卡 + ArcButton + 断连/过期态 |
| `tools/verify_watch_contract.sh` | 线协议 / 路由 / 前置校验 / 消息体积离线断言（73 条） |

## 7. US-1 ~ US-10 覆盖矩阵（代码 / 离线证据 / 真机状态）

| US | 代码落点 | 离线证据 | 真机状态 |
|---|---|---|---|
| US-1 抬腕见卡 | `publishPrompt` + 手表 `sync` 补发 | 投影断言 | **阻断**（投影/落盘已真机跑通，P2P 未通） |
| US-2 手表点选生效 | `handleCompanion` → `CompanionStore.execute` | `inpage → execute` 断言 | 阻断 |
| US-3 手表打卡 | `CheckinDao.set(evidence=null)` → `source=manual` | `checkinIntent` 断言 + 打卡卡体积 | **已验证（探针模拟决策）**：rows=1 source=manual lat/lng=0 |
| US-4 推荐项高亮 | `recommendedKey` 投影 + `ArcButton` | 推荐键断言 | 阻断 |
| US-5 划掉/超时 | `__dismiss__` + 手表 10min 过期 + 手机 30min TTL | `dismiss`/`precheck stale` 断言 | 阻断 |
| US-6 幂等 | `processed` 环 + `ON_CONFLICT_REPLACE` | `duplicate → drop` 断言 | **已验证（探针连发两次）**：仅落一行 |
| US-7 离页不丢 | `pending` 队列 + 回页 `consumePending` + 高风险重新请示 | `queue`/`high-stake-offpage` 断言 | **已验证（队列探针）**：pending 1→0、执行器收到 move_tomorrow；真实后台时机待 G0 |
| US-8 断连降级 | 手表 8s 存活核对 + 「未连接手机」态 | UI 无离线断言 | 阻断（无表可验） |
| US-9 通知兜底 | `ArrivalNotice` 补 `SOCIAL_COMMUNICATION` 槽位 | `arrivalprobe ok=true`（真机） | 手机侧已验；手表镜像待有表复验 |
| US-10 多设备/账号隔离 | 卡片记录带 `uid` + `precheck foreign-account` | 跨账号断言 | 阻断 |

> 依赖 G0 的 9 条用户故事目前只能标「阻断」，不伪造通过。G0-a 通过后按上表逐条走真机。

## 8. 真人抬腕验收清单（G0 通过后照做，脚本不能替代）

前置：手表已装 `wearable-default-signed.hap`，手机已装本轮 debug 包，两台设备同华为账号/已配对。

| # | 操作 | 期望（逐项勾） |
|---|---|---|
| 1 | 手机进入行程页，触发一张规划外到站请示卡 | 手表抬腕出现同标题/同选项；推荐项在底部高亮（US-1 / US-4） |
| 2 | 手表点推荐项「挪明天」 | 手机行程页该站移到明天、出现可撤销提示；偏好计数与手机点选一致（US-2） |
| 3 | 走到下一站围栏内，等手机推打卡卡 | 手表出现「到「X」了，打卡吗？」；点打卡后手机 checkin 表 `source=manual`、进度刷新（US-3） |
| 4 | 手表连点两次打卡 | checkin 表仅一行（US-6） |
| 5 | 手表点「忽略」 | 手表清屏；手机请示卡收起、行程无改动（US-5） |
| 6 | 让卡片放置超过 10 分钟不操作 | 手表自动清屏并回 `__dismiss__`；手机卡收起（US-5） |
| 7 | 退到桌面/锁屏后，用手机触发打卡决策（或等手表重连补发） | 打卡仍落库；回行程页进度已更新（US-7） |
| 8 | 关闭手机蓝牙 | 8 秒内手表显示「未连接手机」，按钮不再假装成功（US-8） |
| 9 | 恢复蓝牙 | 手表自动重连并发 `sync`，当前卡重新出现（US-8 / US-1 拉取式） |
| 10 | 卸载手表 App（或强停），在手机触发到站 | 手表仍收到带提醒槽位的文字通知（US-9） |
| 11 | 退出登录换另一个账号，再点旧卡 | 旧卡决策被丢弃（`cardId`/`uid` 对不上），不写新账号数据（US-10） |
| 12 | 用 `hdc shell uitest dumpLayout` 量 Apply 页按钮 bounds | 圆屏无裁剪、按钮可命中（规格 §10） |

> 第 1~12 项中任何一项与期望不符，按「G0 失败决策树」记录证据后再改，不在没有证据时改语义。

## 7. 已知未覆盖

- 手表侧 UI 只做了编译验证，**未做真机圆屏裁剪 / 按钮命中实测**（规格 §10 明确要求 dumpLayout 量 bounds）。
- 手表 App 的签名/Profile 是否需要为 wearable 增补设备类型，未在 AGC 核对（规格 §12.2）。
- `WATCH_REMOTE_FINGERPRINT` 为空串：这是 G0-c 的待填项，不是遗漏。

## 9. AGC 服务申请记录（2026-11-14）

| 项 | 值 |
|---|---|
| 提交时间 | 2026-11-14 16:24:41 |
| 申请入口 | AGC → 应用管理 → 有径 → 开放能力配置 → 开放能力管理 → 开放能力申请 → Wear Engine → 管理 → 申请 Wear Engine 服务 |
| 产品 | 有径（`com.youjing.app`），APP ID `6917619826312400726` |
| 开发者类型 | **个人**（已认证，开发者 ID `10086000824313557`） |
| 产品类型 | HarmonyOS应用 |
| 支持设备 | 鸿蒙智能穿戴设备（HUAWEI WATCH 5） |
| 是否开发穿戴应用 | 是，我开发或计划开发对应用设备的应用 |
| 申请权限 | 设备基础信息（DEVICE_MANAGER）、消息通知（NOTIFY） |
| 已签协议 | 《HUAWEI Wear Engine 服务使用协议》《华为APIs使用协议》 |
| 上传材料 | [申请数据权限及使用说明-有径.xlsx](file:///Users/itxiaobai/HarmonyProject2/Docs/analysis/wear-engine-apply/申请数据权限及使用说明-有径.xlsx)、[用户授权路径说明-有径.xlsx](file:///Users/itxiaobai/HarmonyProject2/Docs/analysis/wear-engine-apply/用户授权路径说明-有径.xlsx) |
| 申请状态 | **开通待审核**（产品列表可见，更新时间 2026-11-14 16:24:41） |
| 官方审批周期 | 1~2 周，结果经邮件/短信/站内信通知 |

材料要点：

- 权限说明按模板「个人开发者」sheet 填写：设备基础信息用于手机↔手表 P2P 卡片同步；
  消息通知仅作到站提醒的文字兜底。
- 用户授权路径说明：HarmonyOS 上这两项权限为默认授予，无独立授权弹窗，故不涉及授权截图
  （模板原文明确「手机应用类型为安卓和鸿蒙时……无需提供」）。
- 应用信息：有径为 AI 行程规划与执行助手；尚未上架、暂无评分；功能截图可应审核要求补充。
- 补充说明：无华为硬件采购计划、不联合华为品牌、行业选「其他（旅行行程规划与打卡工具）」。
- 上传时遇到 `上传失败`：原因是首版 Excel 删掉了模板中的企业 sheet；保留模板全部 sheet 后上传成功。
  后续如被驳回需修改，切记不要删除模板自带的工作表。

审批通过后的第一件事：`--ps wearecho 1`，期望 `通道就绪` + 手表回 `pong`；
随后按 §3 表格继续 G0-b~f 与 §8 的真人抬腕清单。

## 10. 驳回与重申（2026-11-16）

**结果**：11-14 提交的 Wear Engine 服务申请被华为智能穿戴设备能力开放团队驳回（APP ID `6917619826312400726`）。
**性质**：申请材料/权限范围问题，**不是「第三方禁用」**——通道可申请，按下面整改后重申。

### 10.1 驳回四条 → 整改对照

| # | 驳回原文要点 | 对我们的含义 | 整改动作 |
|---|---|---|---|
| 1 | 用新版申请表，按蓝色样例填必填项（手表型号、使用场景、手机手表 UX、应用介绍） | 11-14 那两份 xlsx 模板/必填项不符 | 从 https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/wearengine_apply 下新模板重填；**保留模板全部 sheet**（首版删企业 sheet 曾致上传失败） |
| 2 | 补手机侧 + 手表侧截图/UX 图，体现 Wear Engine 场景 | 申请时未附截图 | 出手机请示卡 UI + 手表卡片 UI 截图/UX 图，标注「手机投影卡片→手表渲染→点选回传」链路 |
| 3 | 手表侧开发 APP，P2P 只需「设备基础信息」权限，一般无需「消息通知」权限 | 多申了 NOTIFY | **重申只留 DEVICE_MANAGER，去掉 NOTIFY**。P2P 卡片同步只用 DEVICE_MANAGER；US-9 文字兜底走手机本地通知镜像（F2），不占 Wear Engine 权限，去掉不丢能力 |
| 4 | 手表→手机同步时手机 App 未活跃则发送失败；建议手表联网直同步服务器；坚持手机中转需说明为何不能联网 + 手机未活跃处理办法 + 截图 | **核心 UX 硬约束**（规格 F10/§7.1） | 处理办法取决于架构方向（A 手表暂存补同步 / B 手表直连服务器 / C 仅前台），**待用户拍板后填此段** |

### 10.2 重申材料清单（用户侧动作，Trae 不代办登录/提交）

- [ ] 下载新版申请表与样例（驳回信给的 URL）。
- [ ] 权限范围改为**仅设备基础信息（DEVICE_MANAGER）**。
- [ ] 按蓝色样例填齐：手表型号 HUAWEI WATCH 5、使用场景（行中请示卡/打卡的腕上确认）、手机手表 UX、应用介绍。
- [ ] 附手机侧 + 手表侧 UX 截图（链路：手机 CompanionPrompt → WatchCard → 手表渲染 → WatchDecision 回传 → 手机裁决）。
- [ ] 「手机未活跃处理办法」一段：按 §10.3 选定方向填写 + 对应截图。
- [ ] 不勾选「打开/关闭设备侧传感器、读取传感器数据」（除非已与华为穿戴团队达成一致）。
- [ ] 保留模板全部工作表后上传；无华为接口人可邮 hihealth@huawei.com。

### 10.3 待用户拍板：手机未活跃投递缺口（规格 §7.1）

驳回第 4 条把「手机揣兜里、抬腕点手表」的核心卖点逼到墙角：用户点手表时手机 App 常在后台，P2P 决策送不到手机。
三方向（A 手表本地暂存+手机活跃补同步 / B 手表直连服务器[反转服务器暂缓] / C 仅手机前台可用）见规格 §7.1。
**选定前不动架构、不填重申第 4 条叙事。** 已真机验证的 US-3/6/7 不受影响（US-7 是「离页但 App 活跃」，与「App 不活跃」是两层）。
