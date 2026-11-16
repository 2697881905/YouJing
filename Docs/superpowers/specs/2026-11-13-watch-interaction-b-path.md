# 有径手表轻交互 · B 路径规格说明书（转交 Trae）

> ⚠️ **已废弃（2026-11-16）**：Wear Engine P2P 路径真机证需 AGC 申请且被驳回，加之「手机未活跃 P2P 发送失败」平台硬约束，整体转向全网络客户端。
> **现行规格见 `2026-11-16-watch-network-client-design.md`。** 本文仅留作取证历史，勿据此实现。

- 日期：2026-11-13
- 状态：**设计稿 · 含一道未通过的真机硬闸门 G0，G0 通过前不得开工业务 UI**
- 转交对象：Trae（独立实现，本文自包含，不依赖产出它的对话）
- 关联取证提交：`8bb11d0`（watchprobe 常驻探针，含真机结论注释）
- 目标设备：HUAWEI Watch 5（智能穿戴 wearable，HarmonyOS 5+）+ 鸿蒙 NEXT 手机（实测机 Pocket 2）
- bundleName：`com.youjing.app`（手机与手表同属一个应用）

---

## 0. 给 Trae 的执行须知（先读这段）

1. **本工程是 probe-first 文化**：任何「能不能」都先用最小真机探针拿证据，再投 UI。本文 §4 的 G0 就是这种探针，**它是开工前置条件，不是可选项**。G0 不通过，整个 B 路径停摆，回到 §4.4 的决策树，不要硬写 UI。
2. **不要相信本文里的任何 Wear Engine API 片段是权威**。准确 API 以本机 DevEco SDK 的 `@kit.WearEngine`（内部转发 `@hms.health.wearEngine`）d.ts 为准——动手前先读 SDK 声明（路径形如 `/Applications/DevEco-Studio.app/Contents/sdk/default/hms/ets/api/@hms.health.wearEngine.d.ts`），核对设备支持表里有没有 `wearable`。Kit 名是 `@kit.WearEngine`，**不是** `@kit.WearEngineKit`（后者本机不存在，Trae 已勘误）。
3. **手机是唯一裁决者**。手表只是「远程渲染 + 输入面」，绝不在手表上做决策、改行程、调后端。所有写库都发生在手机侧（见 §7）。
4. **BFF 未公网**（服务器暂缓）。手表**不能**直连任何后端，一切经手机中转。不要给手表设计独立联网逻辑。
5. 构建装机用仓库根脚本 `tools/build_install.sh`（它保证「构建成功才装机」，并校验产物时间戳）。多设备时用 `HDC_TARGET=<connect-key>` 指定。hdc 若不在 PATH，用绝对路径 `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc`。
6. 日志一律走 `common/logger/Logger`（hilog 封装，`YouJing.` 前缀，`%{public}s`）。**禁止 console.\***（真机不进 hilog，P6 门禁会拦）。
7. 签名复用 `build-profile.json5` 里现成的 `default`/`release` signingConfig，**按名字引用，不要把证书路径/密码写进任何新文件或文档**。
8. 验收要真机逐屏跑，闸门绿 ≠ 界面起得来。手表侧大量行为只能真人抬腕验证，脚本注入不可靠——把「需真人验证」的项显式列进验收清单，不要假装自动化覆盖了。

---

## 1. 问题陈述

有径的定位是「保姆级 AI 行程助手」，核心体验是**少掏手机**：行中到站、规划外到访、该不该调整，助手端出带默认推荐的「请示卡」，用户一键拍板。

但当前所有拍板都必须**掏出手机、点亮屏幕、进行程页点按钮**。抬腕看一眼手表就确认「打卡 / 跳过」是这套体验的自然延伸——运动场景、手里拎着东西、手机在包里时尤其有价值。

**A 路径（手机通知带操作按钮 → 镜像到手表点按）已被真机证伪**（见 §2）：手表只镜像通知文字，不透传第三方按钮。因此要做手表交互，只剩 **B 路径：独立手表 App + 手机中转**。

值得做的理由：与「少掏手机」定位高度契合；复用现有助手接缝（§3），增量集中在「一个新端 + 一条通信链路」，不动业务大脑。

---

## 2. 已验证事实（真机证据，2026-11-13，Watch 5 + Pocket 2）

| # | 事实 | 证据 | 对方案的影响 |
|---|---|---|---|
| F1 | 手机通知按钮 → WantAgent → App 收到动作，端到端通 | hilog `YouJing.Probe.Watch: 收到通知按钮回传 action=checkin` | 手机侧回传机制可复用思路 |
| F2 | **提醒通知**（SOCIAL_COMMUNICATION 槽位）能镜像到手表，显示文字 | 补槽位后手表收到「到『博览园』了，打卡吗？」 | 通知可作「兜底提醒」，但仅此而已 |
| F3 | **静默通知**（无槽位、remindFlags=0）根本不转发到手表 | 系统日志 `NotificationRemindManager: No need to remind, isSilence`；slotType=65535 | 任何想上手表的通知必须带提醒槽位 |
| F4 | **第三方通知的 actionButtons 不透传手表**——手表只显文字、无按钮 | 同一条通知：手机有「打卡/跳过」按钮且可点，手表无按钮 | **A 路径死，必须 B 路径** |
| F5 | Wear Engine 有鸿蒙 NEXT 版（Kit 入口 `@kit.WearEngine`，**非** `@kit.WearEngineKit`，Trae 已勘误），支持手机↔手表应用双向 P2P 消息 | 本机 SDK `@hms.health.wearEngine.d.ts`；真机证 `1008500004`=需 AGC 申请服务 | 通道存在但**需服务准入**；2026-11-14 申请被驳回，重申中（见探针报告 §10） |
| F10 | **手机 App 未活跃时，手表→手机的 P2P 消息发送失败**（华为驳回信明示，平台硬约束） | 华为 Wear Engine 驳回邮件 2026-11-16 第 4 条 | **「手机揣兜里抬腕点」的核心 UX 受威胁**；处理方案待用户拍板（§7.1） |
| F11 | 手表侧开发 APP 场景，P2P 只需「设备基础信息」权限，无需「消息通知」权限 | 华为驳回信第 3 条 | 重申去掉 NOTIFY；US-9 文字兜底走手机本地通知镜像，不占 Wear Engine 权限 |
| F6 | `CompanionPrompt/CompanionOption/CompanionAction` 是纯数据、无 @kit 依赖 | `entry/src/main/ets/companion/CompanionTypes.ets` | **现成接缝**：可直接序列化给手表渲染 |
| F7 | 助手执行器只在 OnTripPage 存活时注册 | `OnTripPage.ets:244` registerExecutor / `:252` clearExecutor；`CompanionStore.ets:30` execute 无执行器即静默丢弃 | **暗坑**：手表决策回来时用户若不在行程页会被丢 → §7 必须解决 |
| F8 | 打卡是独立动作，不属于 CompanionPrompt | `OnTripPage.ets:1753` toggleCheckin → `CheckinDao.set`；`CheckinDao.ets:30` source='arrival'\|'manual' | 手表打卡要单独建模，不能硬塞进请示卡 |
| F9 | 工程当前单 entry 模块、deviceTypes=["phone"]、targetSdk 26.0.0 | `build-profile.json5:72`、`entry/src/main/module.json5:7` | 需新增 wearable 模块（§5） |

来源链接见 §12.3。

---

## 3. 方案概述（高层形状）

```
┌─────────────── 手机（唯一裁决者）───────────────┐
│  CompanionEngine（纯逻辑大脑，不改）              │
│        │ 产出 CompanionPrompt                    │
│        ▼                                         │
│  WatchBridge（新增·常驻）                        │
│   ├─ 出站：把请示卡/打卡请求序列化成 WatchCard    │
│   │        经 Wear Engine 发手表                 │
│   └─ 入站：收 WatchDecision → 路由到执行器        │
│        ├─ 打卡 → CheckinDao.set（source=manual） │
│        └─ 请示 → 常驻执行器 / 待办队列            │
└──────────────────┬──────────────────────────────┘
                   │ Wear Engine Kit（P2P 消息，G0 验证）
┌──────────────────▼──────────────────────────────┐
│  手表 wearable 模块（新增·薄端）                  │
│   ├─ 收 WatchCard → 圆屏渲染标题+后果+选项按钮    │
│   └─ 用户点按 → 回 WatchDecision{cardId,optionKey}│
│   不做决策 / 不改行程 / 不联网 / 不存业务态        │
└─────────────────────────────────────────────────┘
```

**核心原则**：手表渲染的卡片与手机请示卡**同源**（都来自 CompanionPrompt），手表回传的选项键与手机点选**同义**（都是 option.key）。这样手表只是给同一个大脑加了一块远程屏幕，业务语义零分叉。

**深模块接缝**：整个变更尽量只跨**一个稳定接缝——`WatchCard`/`WatchDecision` 线协议**（§6）。手机侧大脑、DAO、执行器都不动语义，只新增一个 Bridge 把现有意图翻译到线上；手表侧只认线协议。协议稳定后，两端各自可独立测试、独立替换底层（哪怕将来 Wear Engine 换通道，协议不变）。

---

## 4. G0 硬闸门：Wear Engine 真机回声探针（先于一切业务代码）

**目的**：用最小成本证实「第三方鸿蒙 NEXT 应用能否经 Wear Engine 与 Watch 5 上的自家手表应用双向通信」，并摸清约束。**这是 B 路径的地基，地基没验真前不盖楼。**

### 4.1 探针范围（只做这些，不做 UI）
- 手机 entry 加一个 debug 探针入口（仿 `EntryAbility` 现有 `--ps watchprobe` 模式，新增 `--ps wearecho 1`）。
- 手表 wearable 模块只放一页：显示「收到：xxx」+ 一个「回 ping」按钮。
- 手机发一条 `{hello:"..."}` → 手表显示 → 点按钮回 `{pong:"..."}` → 手机 hilog 打出收到。

### 4.2 必须逐项拿到证据的清单
| 项 | 要回答的问题 | 通过判据 |
|---|---|---|
| G0-a 第三方准入 | 普通第三方应用能否调通 Wear Engine？ | **需 AGC 申请 Wear Engine 服务**（真机证 `1008500004`）；2026-11-14 申请被驳回，按 §10 重申 | 服务开通后真机收发成功（P2pResultCode=207） |
| G0-b 设备发现 | 手机能否列出已配对的 HarmonyOS 手表？API 与返回结构？ | 能拿到 Watch 5 的设备标识 |
| G0-c 对端识别 | 手机应用与手表应用如何关联？是否要求同 bundleName？手表侧如何注册接收？ | 明确对端匹配规则并真机命中 |
| G0-d 后台收取 | 手表应用**不在前台**时能否收到消息并抬腕提醒？还是必须打开应用才看得到？ | 明确「推送式」还是「拉取式」——**直接决定 UX 形态** |
| G0-e 消息约束 | 单条消息大小上限？文本/JSON 是否支持？可靠性（断连是否补发/队列）？ | 记录上限与断连行为 |
| G0-f 权限 | 需要哪些权限？`ohos.permission.DISTRIBUTED_DATASYNC` 是否够？手表侧是否另需？ | 权限清单 + 真机授权通过 |

### 4.3 探针产出
一份 `Docs/analysis/WearEngine探针-<日期>.md`：逐项「问题/实测值/来源（hilog 行或截图）」三列表，无证据项标 tentative。**G0 报告是开工许可证。**

### 4.4 G0 失败决策树（不要硬闯）
- **G0-a 失败（第三方不可用/需未获得的权益）**：B 路径整体停摆。如实告知用户「需华为侧准入」，**降级到 F2 能力**：手机发提醒通知，手表看文字（无交互），打卡仍回手机点。不要伪造交互。
- **G0-d 失败（只能拉取、不能推送）**：UX 退化为「抬腕打开有径手表 App 看当前待决卡片」，而非「 wrist 震动推送」。仍可做，但要在 §8 用户故事里把「主动推送」改成「打开即见」，并告知用户这个落差。
- **G0-c/e 受限**：按实测约束调整 §6 协议（如分包、对端注册方式），不改「手机裁决」原则。

---

## 5. 模块与工程结构

### 5.1 新增 wearable 模块（多设备同应用）
- 新建模块目录 `wearable/`，`module.json5`：`type:"entry"`、`deviceTypes:["wearable"]`、独立 `mainElement`（如 `WatchAbility`）、独立 `pages`。
- 根 `build-profile.json5` 的 `modules` 数组追加 `{name:"wearable", srcPath:"./wearable", targets:[{name:"default", applyToProducts:["default","release"]}]}`。
- 手机 entry 的 `deviceTypes` **保持 ["phone"]**，不要把 wearable 塞进手机模块（两端 UI 与能力差异大，分模块干净）。
- 两模块同属 bundleName `com.youjing.app`（一个应用、多设备入口）。**多 entry 模块同 bundle 的具体打包/签名机制以 DevEco 多设备模板为准**——Trae 先用官方 wearable 模板建一个最小工程跑通装机，再合并进本仓，不要凭空猜构建配置。
- 手表侧权限按 G0-f 实测清单声明（至少含 DISTRIBUTED_DATASYNC，若 G0 证明需要）。

### 5.2 共享线协议（单一真源）
- 新建静态共享包 HAR `watchcontract/`，只放**纯数据线协议类型**（§6 的 WatchCard/WatchDecision/WatchOption），无 @kit 依赖。
- entry 与 wearable 都依赖它。**禁止两端各抄一份接口**——序列化漂移是这类方案最常见的隐性 bug。
- `CompanionPrompt` 本身不必整包搬给手表：它含 `UnplannedInput.day`（TripDay）等重对象。WatchCard 是它的**扁平投影**（§6），由手机 Bridge 负责投影，手表只吃扁平 DTO。

### 5.3 手表 UI 约束
- 圆屏（Watch 5 约 466×466 px），用 ArkUI 穿戴组件（`ArcList`/`ArcButton` 等 Arc* 系列，以 SDK 实际支持为准）。
- 一屏一卡：标题 + 一句后果 + 至多 3 个选项按钮（与手机请示卡选项数一致）+ 推荐项高亮。
- 不搬手机视觉语言（玻璃材质/复杂 token 在手表无意义），手表用系统原生穿戴风格，**官方组件优先，禁自绘**。

---

## 6. 线协议（稳定接缝 · 单一真源在 watchcontract HAR）

JSON over Wear Engine 消息。所有字段扁平、可 JSON.stringify。

### 6.1 手机 → 手表：`WatchCard`
```jsonc
{
  "v": 1,                      // 协议版本，手表据此兼容
  "type": "card",
  "cardId": "unplanned-博览园-act123",  // 去重键，复用 CompanionPrompt.id；打卡用 "checkin-<tripId>-<stopKey>"
  "kind": "companion",         // "companion"（请示卡）| "checkin"（打卡确认）
  "title": "你到了博览园——不在今天计划里",
  "detail": "它大概要 90 分钟，会挤占下一站。怎么安排？",
  "options": [                 // 至多 3 个；打卡固定 2 个
    { "key": "move_tomorrow", "label": "挪明天", "subline": "今天从容逛" }
  ],
  "recommendedKey": "move_tomorrow",  // 推荐项 key（手表高亮）；打卡推荐 "checkin"
  "ts": 1794576962289          // 手机发出时刻，手表用于过期判断
}
```
- 由 CompanionPrompt 投影：`title/detail/options[].key/label/subline` 直取，`recommendedKey = options[recommendedIndex].key`。
- 打卡卡（F8）：`kind:"checkin"`，options 固定 `[{key:"checkin",label:"打卡"},{key:"skip",label:"跳过"}]`，title 形如「到『博览园』了，打卡吗？」。

### 6.2 手表 → 手机：`WatchDecision`
```jsonc
{
  "v": 1,
  "type": "decision",
  "cardId": "unplanned-博览园-act123",  // 必须回原 cardId，手机据此对账
  "optionKey": "move_tomorrow",         // 用户点的选项 key；划掉/超时用 "__dismiss__"
  "ts": 1794576990000
}
```
- 手表**只回 key，不回 action 对象**——action 由手机按 cardId 找回原 CompanionPrompt 再取，保证执行语义永远在手机侧定义（手表拿不到、也不该拿 TripDay 等）。

### 6.3 协议纪律
- 手表收到未知 `v` 或畸形 JSON：静默忽略 + 打日志，不崩。
- 手机收到对不上的 cardId（卡已撤/已决）：静默丢弃 + 打日志（幂等，重复决策不重复执行）。
- 消息体保持小（G0-e 上限内）；detail 文案手机侧截断到手表可读长度。

---

## 7. 手机侧路由（解决 F7 执行器生命周期暗坑）

**问题**：现有 `CompanionStore.execute` 的执行器由 OnTripPage 在 aboutToAppear 注册、aboutToDisappear 清空。手表决策可能在用户**离开行程页甚至 App 在后台**时到达——直接复用会静默丢弃。

**解法**：新增常驻 `WatchBridge`（不绑页面生命周期），入站决策分两条路：

1. **打卡决策（kind=checkin）**：Bridge 直接调 `CheckinDao.set(context, tripId, stopKey, true, null)`。
   - `evidence=null` → `source='manual'`（F8 口径）。**手表打卡没有手机定位凭证，绝不伪造 arrival 证据**。
   - tripId/stopKey 从 cardId 解析；账号分区由 CheckinDao 内部 `AccountStore.uid()` 保证，手表无需自带身份。
   - 打卡成功后：刷新万能卡片（WidgetSync）、若行程页在场则通知其 reload。
2. **请示决策（kind=companion）**：Bridge 持有一个**常驻执行器**（复用 OnTripPage 现有的 `handleCompanionAction` 逻辑，抽成不依赖页面实例的服务），或：
   - 行程页在场 → 转交页面执行器（保持现有撤销快照/ toast 体验）；
   - 行程页不在场 → 落「待执行队列」（preferences），下次进行程页消费；**高风险动作（stake=high，如花钱/不可逆）不在后台静默执行，留到用户回行程页确认**。
   - 偏好降级闭环（CompanionPrefs.recordChoice）仍要记录，保持与手机点选一致。

**出站触发**：Bridge 订阅 `CompanionStore.show`（或在其内加一个出站钩子），每浮出一张请示卡就投影成 WatchCard 发手表；到站打卡请求（ArrivalNotice 时机）额外发一张 checkin 卡。**手机请示卡与手表卡同生同灭**：手机 dismiss 时发一条撤卡消息（或手表按 ts 过期自清）。

### 7.1 手机未活跃投递缺口（F10 · 待用户拍板，未定不改架构）

§7 的离页队列解决的是「手机 App 还活着、只是不在行程页」。但华为驳回信（F10）揭示更狠一层：**手机 App 整个不活跃（后台/被杀）时，手表→手机的 P2P 消息直接发送失败**——决策连手机都到不了，队列无从接住。这正好打在「手机揣兜里、抬腕点手表」的核心场景上。

候选方向（**含取舍，须用户选定后才落架构与重申材料**）：
- **方向 A · 手表本地暂存 + 手机活跃时补同步**（无需服务器）：手表点按后本地存决策（带时间戳），UI 显示「已记录，待同步」，手机 App 下次活跃经 P2P 补传。打卡（一条日志）体验无损；请示决策延迟执行。代价：手表要持一个小的待决队列，**放宽「手表不存业务态」原则**；且华为可能追问「为何不联网」。
- **方向 B · 手表直连服务器**（华为建议）：手表独立联网把决策写 BFF，手机事后同步。最贴合「手机揣兜里」，但**反转「服务器暂缓」决策**、需 BFF 公网部署 + 手表侧身份（当前手表无身份，复用手机版），新增范围大。
- **方向 C · 仅手机前台可用**（最简）：手表只做「已打开手机 App 的第二屏」，手机不活跃时手表明示「需打开手机 App」。诚实但价值有限，基本放弃核心卖点。

> 选定前：代码维持现状（连不上静默降级），重申材料的「手机未活跃处理办法」一段留空待填。

---

## 8. 用户故事（编号 · 每条可独立验证）

> 标注 [G0-d] 的项依赖「推送式 vs 拉取式」结论，G0 后据实修订措辞。

- **US-1 抬腕见卡** [G0-d]：手机浮出请示卡时，手表收到对应卡片（推送式则抬腕即见；拉取式则打开手表 App 即见），标题/后果/选项与手机一致。验证：两端文案逐项对表。
- **US-2 手表点选生效**：手表点某选项，手机侧执行与手机点同一选项**完全一致**（行程改动/打卡落库/偏好计数）。验证：手表点「挪明天」后，手机行程页看到该站已挪明天且可撤销。
- **US-3 手表打卡**：到站后手表点「打卡」，checkin 表落一条 `source='manual'` 记录，行程页进度刷新。验证：查 checkin 表 source 字段 = manual，无伪造坐标。
- **US-4 推荐项高亮**：手表卡 recommendedKey 对应按钮高亮，与手机推荐项一致。验证：截图对表。
- **US-5 划掉/超时**：手表划掉或卡片过期，回 `__dismiss__`，手机收起对应请示卡，不执行任何动作。验证：手机卡消失、行程无改动。
- **US-6 幂等**：同一 cardId 重复决策（手表连点/断连重发）只执行一次。验证：连点两次打卡，checkin 表仅一条。
- **US-7 后台/离页不丢** [F7]：用户不在行程页时手表点打卡仍落库；点高风险请示则留待回页确认，不静默执行。验证：退到桌面后手表打卡成功；高风险项回页才执行。
- **US-8 断连降级**：手表与手机断连时，手表显示「未连接手机」，不假装成功；手机侧请示卡照常可在手机点。验证：关蓝牙后手表提示断连。
- **US-9 通知兜底**：即使手表 App 未装/未开，到站提醒通知（带提醒槽位）仍镜像到手表显示文字（F2/F3）。验证：卸载手表 App 后手表仍收到文字通知。
- **US-10 多设备隔离**：手表决策只作用于手机当前登录账号的当前活跃行程。验证：切换账号后旧卡决策被丢弃（cardId 对不上）。

---

## 9. 已定决策（避免后续翻案）

| 决策 | 选择 | 理由 |
|---|---|---|
| 交互通道 | Wear Engine Kit（G0 验证后定） | A 路径已证伪；官方 NEXT 穿戴通信能力 |
| 裁决位置 | 手机唯一裁决，手表薄端 | BFF 未公网 + 业务大脑/DAO 都在手机；手表不持业务态 |
| 复用接缝 | CompanionPrompt → WatchCard 扁平投影 | F6 纯数据现成；业务语义零分叉 |
| 协议真源 | watchcontract HAR 单份 | 防两端序列化漂移 |
| 手表打卡凭证 | source='manual'，evidence=null | F8 口径；不伪造到站证据 |
| 模块形态 | 独立 wearable entry 模块，同 bundleName | 两端能力差异大，分模块干净 |
| 手表视觉 | 系统原生穿戴组件，不搬手机玻璃语言 | 官方组件优先、圆屏适配 |
| 高风险动作 | 后台不静默执行，留回页确认 | 与助手「高风险恒请示」立场一致 |
| 通知角色 | 仅兜底文字提醒（带提醒槽位） | F2/F3/F4：能镜像文字、不能交互 |

---

## 10. 测试决策（接缝处测，「完成」长什么样）

- **线协议（最高接缝，持久靶心）**：watchcontract 纯类型 + 投影/解析函数离线断言（参照本工程 `arkts-pure-logic-offline-verify` 手法：纯逻辑拷 .ts 跑 tsc --strict + 断言）。覆盖：CompanionPrompt→WatchCard 投影正确、WatchDecision 解析、畸形/未知版本静默忽略、cardId 对账幂等。**底层 Wear Engine 换了这些测试不动。**
- **手机路由**：WatchBridge 入站分发离线断言——打卡走 CheckinDao（mock）、companion 在场转交/离页入队、高风险不后台执行、幂等。
- **Wear Engine 链路**：只能真机（G0 探针 + US-1~US-10 真人抬腕）。**这部分无法离线自动化，显式列入真人验收清单。**
- **手表 UI**：真机逐屏目视 + dumpLayout 量 bounds（参照 harmonyos-device-layout-forensics）；圆屏裁剪/按钮命中要实测。
- **「完成」定义**：G0 报告全绿 + 线协议/路由离线断言全过 + US-1~US-10 真机逐条通过（依赖 G0-d 的项按实测形态验）+ pre-commit 编译门禁过。**静态尺全绿不等于完成，必须真机走查。**

---

## 11. 明确不做（本次边界）

- ❌ 手表独立联网 / 直连 BFF / 手表端跑 AI 或 LLM。
- ❌ 手表端改行程、做决策、存业务态（手表只渲染+回 key）。
- ❌ 复杂手表交互：地图、行程编辑、规划、支付、登录（手表不做身份，复用手机版）。
- ❌ Lite Wearable（GT/FIT/D 系列，JS 类 Web 范式）——本方案只覆盖 Watch 5 这类智能穿戴（ArkTS）。
- ❌ Android/iOS 手机配对的手表（有径是鸿蒙 NEXT 应用，装不上 Android/iOS）。
- ❌ 把手机玻璃材质/设计 token 整套搬上手表。
- ❌ 实况窗（Live View）上手表——那是另一条 AGC 权益线，与本方案无关。
- ❌ 通知按钮交互（A 路径，已证伪）。

---

## 12. 补充说明

### 12.1 风险台账
| 风险 | 等级 | 应对 |
|---|---|---|
| Wear Engine 第三方准入未证实 | **高（地基）** | G0-a 硬闸门；已申请被驳回，按新模板+去 NOTIFY+补 UX 图重申 |
| **手机未活跃 P2P 投递失败（F10）** | **高（核心 UX）** | §7.1 三方向待用户拍板；决定「手机揣兜里」卖点能否成立 |
| 手表只能拉取不能推送 | 中 | G0-d 定 UX 形态，US 措辞据实修订 |
| 执行器生命周期丢决策 | 中 | §7 常驻 Bridge + 队列（F7 已定位） |
| 两端协议漂移 | 中 | watchcontract 单一真源 + 协议离线断言 |
| 手表续航/后台限制 | 中 | 薄端、稀疏消息、不保活；G0 实测后台行为 |
| 多 entry 同 bundle 打包机制不熟 | 中 | 先跑官方 wearable 模板再合并 |

### 12.2 分发与权益
- 手表应用上架走华为手表应用市场（AppGallery 穿戴），需审核；与手机版同 bundleName。
- Wear Engine 若需签协议/申请权益（G0-a 揭示），按华为开发者流程办理，**这是用户侧动作，Trae 不代办**。
- 签名复用现有 default/release 配置；release Profile 是否需为 wearable 增补设备类型，按 AGC 实际要求核对。

### 12.3 来源
- 官方 Wear Engine Kit SDK 页：https://developer.huawei.com/consumer/cn/sdk/wear-engine-kit/
- Wear Engine Kit 实战（社区，ArkTS import/权限）：https://developer.huawei.com/consumer/cn/forum/topic/0208228748676927525
- 穿戴侧应用开发方案及 ArkTS 支持（官方 FAQ）：https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-arkui-1520
- WATCH 5 应用市场支持应用（独立/非独立分类）：https://consumer.huawei.com/cn/support/content/zh-cn16053381/
- 通知跨设备协同约束：https://device.harmonyos.com/cn/docs/apiref/harmonyos-guides/notification-glossary
- 真机取证：本仓提交 `8bb11d0`（watchprobe）+ `Docs/调试探针手册.md`

### 12.4 关键代码锚点（Trae 起手读这些）
- `entry/src/main/ets/companion/CompanionTypes.ets` — 接缝数据结构（F6）
- `entry/src/main/ets/companion/CompanionStore.ets` — 状态总线/执行器（F7）
- `entry/src/main/ets/companion/CompanionEngine.ets` — 大脑（不改语义）
- `entry/src/main/ets/pages/OnTripPage.ets:244/252/1502/1557/1753` — 执行器注册/点选/执行/打卡
- `entry/src/main/ets/data/CheckinDao.ets:30` — 打卡写入口与 source 口径（F8）
- `entry/src/main/ets/common/location/ArrivalNotice.ets` — 到站通知（出站时机/兜底）
- `entry/src/main/ets/entryability/EntryAbility.ets` — watchprobe 探针模式（G0 探针仿此）
- `build-profile.json5` / `entry/src/main/module.json5` — 模块/签名/设备类型（F9）