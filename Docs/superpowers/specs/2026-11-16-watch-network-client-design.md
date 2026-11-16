# 有径手表轻交互 · 全网络客户端规格说明书（转交 Trae）

- 日期：2026-11-16
- 状态：**设计稿 · 含未通过的地基硬闸门 G0-N（切片0），通过前不得铺业务 UI**
- 取代：`2026-11-13-watch-interaction-b-path.md`（Wear Engine P2P 版，已废弃，仅留作取证历史）
- 转交对象：Trae（独立实现，本文自包含）
- 目标设备：HUAWEI Watch 5（wearable，HarmonyOS 5+，API 18+）+ 鸿蒙 NEXT 手机（实测 Pocket 2）
- bundleName：`com.youjing.app`（手机与手表同应用）；AGC APP ID `6917619826312400726`
- targetSdkVersion：26.0.0（API 26，恰是 Push Kit 补齐穿戴实况窗推式下发的版本）

---

## 0. 给 Trae 的执行须知（先读）

1. **本方案不用 Wear Engine。** 上一版走 Wear Engine P2P，真机证 `1008500004` 需 AGC 服务申请，申请被华为驳回（2026-11-16），且驳回信揭示「手机 App 未活跃时手表→手机 P2P 发送失败」的平台硬约束，直接打死「手机揣兜里抬腕点」的核心场景。**故整体改为手表独立联网客户端，卡片与决策都走 BFF + Push Kit，绕过 Wear Engine 审批。** 不要复活 Wear Engine 代码路径。
2. **probe-first**：切片0（§4）是新 G0，先真机证「手表能作为同一账号的网络客户端往返一条决策」，再铺 UI。地基没验真前不盖楼。
3. **手机仍是业务裁决者**。手表只渲染卡片、回传选项键；所有行程改动/打卡落库都在手机侧执行（CompanionEngine / CheckinDao）。BFF 只是传输与暂存桥，不做业务决策。
4. **BFF 公网部署是硬前置**（反转了此前「服务器暂缓」决定，用户已拍板复用有据服务器 youju.chat）。部署走现有 `youju-backend-prod-deploy` 流水线；这是用户侧运维动作，Trae 不代办登录/支付/服务器操作。
5. 日志走 `common/logger/Logger`（hilog，`YouJing.` 前缀，`%{public}s`），禁 console.*。构建装机用 `tools/build_install.sh`（多设备 `HDC_TARGET=`）；hdc 绝对路径 `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc`。
6. 签名复用 `build-profile.json5` 的 default/release signingConfig，**按名引用，证书路径/密码不进任何新文件**。
7. 第三方校验 **fail-closed**：idToken 验签未过/凭据缺失一律拒绝，不降级放行（沿用本工程 fail-closed 纪律）。
8. 验收真机逐屏跑；手表侧大量行为只能真人抬腕验，脚本注入不可靠——「需真人验证」项显式列清单，不假装自动化覆盖。

---

## 1. 问题陈述与转向理由

有径定位「保姆级 AI 行程助手」，核心是**少掏手机**：行中到站/规划外到访/该不该调整，助手端出带默认推荐的请示卡，用户一键拍板。抬腕在手表上确认「打卡/跳过」是自然延伸。

探索历程（取证见 §2）：
- **A 路径**（手机通知按钮镜像手表）真机证伪：手表只镜像文字，不透传第三方按钮。
- **B 路径·Wear Engine P2P** 版：真机证需 AGC 服务申请；申请被驳回；驳回信第 4 条揭示**手机 App 未活跃 → 手表→手机 P2P 发送失败**，与核心场景冲突。
- **本方案·全网络客户端**：手表独立联网，卡片经 BFF+Push Kit 下发、决策经 BFF 回传手机同步。华为驳回信本身就建议「手表联网直同步服务器」，本方案采纳并做彻底——**连卡片下发也走网络，不再依赖 Wear Engine**。

---

## 2. 已验证事实（证据）

| # | 事实 | 证据 | 影响 |
|---|---|---|---|
| F1 | 手机通知按钮→WantAgent→App 回传通 | hilog `Probe.Watch: action=checkin`（commit 8bb11d0） | 手机回传机制思路可参考 |
| F2 | 提醒通知（SOCIAL_COMMUNICATION 槽位）镜像到手表显文字 | 真机手表收到文字 | 通知仅作文字兜底 |
| F3 | 静默通知（无槽位）不转发手表 | 系统日志 `isSilence` | 兜底通知必须带提醒槽位 |
| F4 | 第三方通知 actionButtons 不透传手表 | 真机：手机有按钮、手表无 | A 路径死 |
| F5 | Wear Engine P2P 需 AGC 服务申请；手机未活跃时手表→手机发送失败 | 真机 `1008500004` + 华为驳回信 2026-11-16 第 4 条 | **Wear Engine 路径放弃** |
| F6 | **Account Kit 支持 Wearable** | 华为穿戴开放能力清单（HDD 北京站）列 Account Kit | 手表可同华为账号登录→同 uid |
| F7 | **Push Kit 支持 Wearable，设备离线缓存、上线再推**；API 26 补齐穿戴实况窗推式下发 | 官方 Push Kit 简介「支持 Phone/Tablet/PC/Wearable/TV」+「离线缓存」；HarmonyOS7 实录 35 | 卡片下发抬腕即见、离线不丢 |
| F8 | `CompanionPrompt/Option/Action` 纯数据无 @kit 依赖 | `companion/CompanionTypes.ets` | 现成接缝，投影给手表 |
| F9 | 助手执行器只在 OnTripPage 存活时注册 | `OnTripPage.ets:244/252`、`CompanionStore.ets:30` | 手机同步执行需常驻路由（§7） |
| F10 | 打卡独立动作，source='arrival'\|'manual'，evidence 可空 | `CheckinDao.ets:30`、`OnTripPage.ets:1753` | 手表打卡 source=manual，不伪造凭证 |
| F11 | Trae 已建 watchcontract 线协议 + 手表 UI + WatchBridge/Route（P2P 版） | `watchcontract/`、`wearable/`、`entry/.../watch/` | 协议与 UI 复用，传输层换网络 |
| F12 | BFF 已有鉴权/幂等/限流中间件、AppError/HttpError 分层 | 工程知识卡「BFF 请求中间件」 | 复用鉴权，新增 watch 路由与暂存 |

来源见 §14.3。

---

## 3. 方案概述

```
┌────────── 手机（业务裁决者）──────────┐
│ CompanionEngine（纯逻辑大脑，不改语义）│
│   │ 产出 CompanionPrompt               │
│   ▼                                    │
│ WatchOutbox（新增）                    │
│   ├─ 投影 WatchCard → POST BFF         │
│   └─ 同步：拉 BFF 待执行决策 → 路由执行 │
│        ├─ 打卡 → CheckinDao.set(manual)│
│        └─ 请示 → 常驻执行器/待办队列    │
└───────────────┬────────────────────────┘
                │ HTTPS + idToken（Account Kit）
        ┌───────▼────────┐   Push Kit（穿戴推送，离线缓存）
        │  BFF（公网）    │ ─────────────────────────────►┐
        │ 复用有据服务器  │                                │
        │ 暂存卡/决策/token│ ◄── HTTPS + idToken ──┐       │
        └───────▲────────┘                        │       │
                │ 手机拉决策                       │       │
┌───────────────┴─────────────────────────────────┴───────▼──┐
│ 手表 wearable 模块（独立联网客户端·薄端）                     │
│  ├─ Account Kit 登录（同华为账号）→ idToken                  │
│  ├─ 注册 Push token 到 BFF；收 Push → 渲染 WatchCard         │
│  └─ 点选 → POST WatchDecision 到 BFF（不持业务态、不决策）    │
└────────────────────────────────────────────────────────────┘
```

**核心原则**：手表与手机请示卡**同源**（CompanionPrompt 投影），回传选项键**同义**（option.key）。手表只是给同一个大脑加了一块远程网络屏幕。BFF 是传输/暂存桥，**不做业务裁决**。

**稳定接缝**：`WatchCard`/`WatchDecision` 线协议（复用 Trae 已建的 watchcontract，单一真源）。传输从 P2P 换成 HTTPS+Push，协议不变；两端可独立测试。

---

## 4. 切片分解与构建顺序

| 切片 | 内容 | 独立验证判据 |
|---|---|---|
| **0 地基探针（G0-N，硬闸门）** | BFF 公网可达 + 手表 Account Kit 登录拿 idToken + BFF 验签过 + 手表 POST 一条决策 + BFF 落库 + 手机拉到 | 真机：手表登录→BFF 验签→决策往返→手机读到，全链 hilog/落库证据 |
| 1 卡片下发 | 手机投影 WatchCard→BFF→Push Kit 推手表→手表渲染 | 真机抬腕见卡，文案/选项/推荐项与手机对表 |
| 2 决策闭环 | 手表点选→BFF→手机同步执行（打卡/请示）+幂等+账号隔离 | US-2/3/6/7/10 真机逐条 |
| 3 体验/上架 | 断连/过期态、推荐高亮、通知文字兜底、手表上架 | 真人抬腕清单全过 + 上架审核 |

**构建顺序 0→1→2→3。切片0 不通过则停摆**，回到 §4.1 决策树，不硬铺 UI。

### 4.1 G0-N 必须逐项拿证据
| 项 | 问题 | 通过判据 |
|---|---|---|
| G0-N-a 公网可达 | 有据服务器上有径 BFF 公网 HTTPS 可达？ | 手表/手机 curl 通；证书有效 |
| G0-N-b 手表登录 | Watch 5 上 Account Kit 能否登录拿 idToken？ | 真机手表登录成功，idToken 含 unionId |
| G0-N-c 验签 | BFF 用现有 JWKS 路径验手表 idToken？ | 验签过→uid 与手机一致；伪造 token 被拒（fail-closed 正对照） |
| G0-N-d 决策往返 | 手表 POST 决策→BFF 落库→手机拉到？ | 真机一条决策端到端，落库可查 |
| G0-N-e Push 可达 | BFF 经 Push Kit 推到手表？离线缓存？ | 真机抬腕收到推送；关网再开验证缓存补推 |
| G0-N-f 手表联网 | 手表 WiFi/eSIM 独立联网稳定？后台网络策略？ | 真机手表脱离手机蓝牙仍能 HTTPS |

### 4.2 G0-N 失败决策树
- **b 失败（手表 Account Kit 不可用）**：改「手机预置 token」——手机登录后给手表配一个长效设备令牌（配对方式待定：扫码/同账号自动），BFF 按令牌识别 uid。需补设计，不硬闯。
- **e 失败（Push 不可达/不稳）**：卡片下发改手表前台轮询 BFF（打开即见，非抬腕即见），UX 降级并告知用户；离线缓存优势丢失。
- **a/f 失败（公网/手表联网不稳）**：BFF 部署或手表网络是前置，先解决；期间手表端明示「未连接」。

---

## 5. 架构组件

### 5.1 BFF 新增（复用有据服务器，Express）
- **鉴权**：复用现有 idToken 验签中间件（JWKS、issuer、RS256/PS256，unionId→uid）。手表与手机同验签路径。**fail-closed**。
- **新增路由**（示意，命名 Trae 按 BFF 现有风格定）：
  - `POST /watch/push-token`（手表注册 Push token，auth=手表 idToken）
  - `POST /watch/card`（手机投影卡片，auth=手机 idToken）→ 暂存 + Push Kit 推该 uid 的手表 token
  - `POST /watch/decision`（手表回传，auth=手表 idToken）→ 暂存决策（幂等键 cardId+optionKey+uid）
  - `GET /watch/decisions?since=`（手机拉待执行决策，auth=手机 idToken）
  - `POST /watch/decision/ack`（手机执行后确认，BFF 标记已消费）
- **暂存层**：BFF 需持久化卡片/决策/push-token（按 uid 分区）。**Trae 起手评估 BFF 现有存储**（知识卡载 BFF 有路由/中间件，存储形态待核）；若无合适存储，切片0 先引入轻量持久化（按 BFF 现有栈选型，不擅自引重型依赖）。
- **Push Kit 服务端**：BFF 集成 Push Kit REST（拿应用级 access token，向手表 push token 下发）。Push Kit 需 AGC 开通（用户侧）。
- **幂等/限流**：复用现有中间件。

### 5.2 手表 wearable 模块（Trae 已建骨架，换传输层）
- Account Kit 登录（同华为账号）→ idToken；未登录态明示「需登录」。
- 注册 Push token；收 Push → 解析 WatchCard → 圆屏渲染（ArcButton，一屏一卡，推荐项高亮）。
- 点选 → HTTPS POST WatchDecision；成功显示「已提交」，失败显示「未连接/重试」。
- **不持业务态、不决策、不改行程**；仅可选一个小的「待发送决策」离线队列（网络断时暂存，联网补发，带时间戳）。
- 复用 `watchcontract` 协议与现有手表 UI；**删除/停用 Wear Engine 接收路径**。

### 5.3 手机侧（替换 WatchBridge 的 P2P 传输）
- `WatchOutbox`：CompanionStore.show 钩子 → 投影 WatchCard → POST BFF；dismiss → 撤卡（BFF 标记 + 可选 Push 撤）。
- `WatchSync`：手机活跃/进行程页时拉 BFF 待执行决策 → 路由执行（§7）→ ack。
- 保留 Trae 已建的 `WatchRoute`（路由决策表/前置校验，纯逻辑）与打卡落库逻辑；传输层 `WearEngineTransport` 替换为 `HttpWatchTransport`。

---

## 6. 身份鉴权

- 手表 Account Kit 登录同一华为账号 → idToken（含 unionId）。BFF 验签（复用手机版 JWKS 路径）→ uid 与手机一致 → 决策自动落到该账号当前活跃行程。
- **手表无独立业务身份**，复用华为账号；账号切换后旧 token 失效，旧决策被 BFF/手机按 uid 丢弃。
- fail-closed：验签未过/过期/缺凭据一律 401，不放行。正对照：真 token 过、伪造 token 拒。
- G0-N-b 若手表 Account Kit 不可用 → §4.2 手机预置令牌兜底（需补设计）。

---

## 7. 手机侧路由（F9 执行器生命周期）

手表决策经 BFF 暂存，**手机同步时才执行**——天然规避「手机未活跃」问题（决策在 BFF 等着，手机活跃再拉，不丢）。这是全网络架构相对 P2P 的根本优势。

**同步触发时机（明确）**：① App 回前台（onForeground）；② 进入行程页（OnTripPage.aboutToAppear）；③ 收到 BFF 经 Push Kit 发来的「有新决策」提醒（可选，手机侧 Push）。三处任一触发即拉 `GET /watch/decisions?since=`，执行后 ack。不做高频后台轮询（省电）；手机长期不活跃则决策一直在 BFF 等待，回前台一次性消费。

- **打卡决策**：WatchSync 拉到 → `CheckinDao.set(ctx, tripId, stopKey, true, null)`，`source='manual'`（F10，不伪造到站凭证）；刷新万能卡片；行程页在场则 reload。
- **请示决策**：行程页在场 → 转交页面执行器（保留撤销快照/toast）；不在场 → 落待办队列，回页消费；**高风险（stake=high）不后台静默执行，留回页确认**。偏好降级闭环（CompanionPrefs.recordChoice）照记。
- **幂等**：决策按 cardId+optionKey+uid 去重；ack 后 BFF 标记已消费，重复拉取不重复执行。
- **账号隔离**：决策带 uid，手机只执行当前登录 uid 的决策。

---

## 8. 线协议（复用 watchcontract，单一真源）

沿用 Trae 已建的 `WatchCard`/`WatchDecision`（JSON，扁平）。传输承载变了：
- 手机→BFF→手表：WatchCard 走 `POST /watch/card` + Push Kit 推送体（注意 Push 消息体大小限制，超限则 Push 只带 cardId，手表收 Push 后回 BFF 拉全卡）。
- 手表→BFF：WatchDecision 走 `POST /watch/decision`。
- 字段语义不变：cardId 去重、optionKey 回传、`__dismiss__` 划掉、recommendedKey 高亮、ts 过期。
- **协议离线断言复用** `tools/verify_watch_contract.sh`（Trae 已建 73 条）；新增传输层契约测试。

---

## 9. 错误处理

| 场景 | 处理 |
|---|---|
| 手表离线 | Push Kit 缓存，上线补推（F7）；手表决策离线队列暂存，联网补发 |
| 手机未活跃 | 决策在 BFF 暂存等待，手机活跃拉取执行（不丢，§7） |
| 验签失败 | fail-closed 401；手表提示重新登录 |
| 重复决策 | 幂等键去重 + ack 标记 |
| 跨账号 | uid 不符丢弃 |
| 卡片过期 | 手表 10min 自清 + 手机 30min TTL（沿用 Trae 已建） |
| Push 不可达 | 降级手表前台轮询（§4.2），UX 告知 |
| BFF 不可达 | 手表明示「未连接」，不假装成功；手机请示卡照常手机点 |

---

## 10. 用户故事（编号·可独立验证）

- **US-1 抬腕见卡**：手机浮请示卡 → BFF Push → 手表抬腕见同标题/选项/推荐项。验证：两端文案对表 + Push 到达。
- **US-2 手表点选生效**：手表点选项 → BFF → 手机同步执行，与手机点同一选项一致。验证：手表点「挪明天」后手机行程页该站挪明天可撤销。
- **US-3 手表打卡**：手表点打卡 → checkin 表 source=manual、无伪造坐标、进度刷新。验证：查表 source=manual lat/lng=0。
- **US-4 推荐高亮**：recommendedKey 按钮高亮，与手机一致。
- **US-5 划掉/超时**：`__dismiss__`/过期 → 手机收卡、行程无改动。
- **US-6 幂等**：同决策连点/补发只执行一次。验证：连点两次打卡仅一行。
- **US-7 手机未活跃不丢**：手机后台/锁屏时手表点打卡 → BFF 暂存 → 手机回前台拉取落库。验证：退桌面后手表打卡，回手机见进度更新。（**这是全网络架构核心优势，P2P 版做不到**）
- **US-8 断连降级**：手表断网明示「未连接」，按钮不假装成功；恢复后离线队列补发。
- **US-9 通知兜底**：手表 App 未装/未开，到站提醒通知（带提醒槽位）仍镜像文字（F2/F3）。
- **US-10 账号隔离**：切账号后旧卡决策被丢弃，不写新账号数据。
- **US-11 手表登录**：手表 Account Kit 登录同华为账号，uid 与手机一致；未登录明示。验证：BFF 验签 uid 对表。

---

## 11. 已定决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 传输架构 | 全网络客户端，**弃用 Wear Engine** | 驳回 + 手机未活跃 P2P 失败；网络绕过审批 |
| 裁决位置 | 手机唯一裁决，BFF 仅传输/暂存，手表薄端 | 业务大脑/DAO 在手机 |
| 手表身份 | Account Kit 同华为账号→idToken→uid | F6 官方支持；与手机同验签 |
| 卡片下发 | Push Kit（穿戴，离线缓存） | F7 官方支持；抬腕即见 |
| BFF 部署 | 复用有据服务器 youju.chat | 用户拍板；现有发版流水线 |
| 复用接缝 | CompanionPrompt→WatchCard（watchcontract 单源） | F8；Trae 已建 |
| 手表打卡凭证 | source=manual，evidence=null | F10；不伪造 |
| 手机未活跃 | 决策 BFF 暂存，手机活跃拉取 | 全网络根本优势 |
| 高风险动作 | 不后台静默执行，留回页确认 | 助手「高风险恒请示」 |
| 已有代码 | 复用 watchcontract/手表 UI/WatchRoute；P2P 传输换网络 | F11；不浪费已验证资产 |

---

## 12. 测试决策（接缝处测）

- **线协议（最高接缝）**：watchcontract 投影/解析/幂等/账号隔离离线断言（复用 verify_watch_contract.sh 73 条 + 新增）。传输换网络这些不动。
- **BFF watch 路由**：验签 fail-closed（真 token 过/伪造拒）、幂等、uid 分区、决策暂存/拉取/ack。服务端测试套件（BFF 已有 test 栈）。
- **手机路由**：WatchSync 分发离线断言（打卡走 CheckinDao mock、请示在场转交/离页入队、高风险不后台执行）。
- **网络/Push/手表 UI**：只能真机（G0-N + US 真人抬腕）。显式列真人验收清单，不假装自动化。
- **「完成」定义**：G0-N 全绿 + 协议/BFF/路由测试过 + US-1~11 真机逐条 + pre-commit 编译门禁过。静态尺全绿≠完成。

---

## 13. 明确不做

- ❌ Wear Engine（任何 P2P/模板通知路径）——已放弃。
- ❌ 手表端跑 AI/LLM、改行程、做业务决策、持业务态（离线决策队列除外）。
- ❌ 手表复杂交互：地图、行程编辑、规划、支付。
- ❌ Lite Wearable（GT/FIT/D，JS 范式）；Android/iOS 配对手机。
- ❌ 手机玻璃材质/token 整套搬手表。
- ❌ 实况窗上手表作为主交互（Push Kit 实况窗可作卡片载体，但交互仍在手表 App）。
- ❌ 通知按钮交互（A 路径，证伪）。

---

## 14. 补充说明

### 14.1 风险台账
| 风险 | 等级 | 应对 |
|---|---|---|
| 手表 Account Kit 可用性 | 高（地基） | G0-N-b 硬闸门；失败→手机预置令牌兜底 |
| Push Kit 穿戴到达率/开通 | 高 | G0-N-e；AGC 开通（用户侧）；失败→轮询降级 |
| BFF 公网部署（反转暂缓） | 高 | 复用有据服务器；切片0 先证可达 |
| BFF 暂存层选型 | 中 | 起手评估现有存储，轻量引入 |
| 手表续航/后台网络 | 中 | 薄端、Push 唤醒、稀疏轮询 |
| 手表独立联网稳定 | 中 | G0-N-f 真机验 WiFi/eSIM |

### 14.2 分发与权益（用户侧动作）
- BFF 部署到有据服务器（youju-backend-prod-deploy 流水线）。
- Push Kit AGC 开通 + 穿戴推送配置；手表应用上架华为手表应用市场。
- Account Kit 手表侧配置（同 APP ID）。
- 签名复用现有配置；release Profile 是否需为 wearable 增补设备类型，按 AGC 核对。

### 14.3 来源
- Push Kit 简介（支持 Wearable + 离线缓存）：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/push-kit-introduction
- Push Kit 穿戴推送实践：https://www.cnblogs.com/HarmonyOSSDK/p/22317928
- HarmonyOS7 API26 穿戴实况窗推式下发：https://ost.51cto.com/posts/49937
- 华为穿戴开放能力清单（含 Account Kit/Push Kit）：https://developer.huawei.com/consumer/cn/information/news/0f66fe2fa0b8476abc2d029eb5748c3b
- 穿戴侧开发方案及 ArkTS 支持：https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-arkui-1520
- Wear Engine 驳回信（2026-11-16，用户邮件）+ 探针报告 `Docs/analysis/WearEngine探针-2026-11-13.md`
- 通知真机取证：commit `8bb11d0`

### 14.4 代码锚点（Trae 起手读）
- `watchcontract/src/main/ets/WatchProtocol.ets` / `WatchProjection.ets` — 线协议+投影（复用）
- `entry/src/main/ets/watch/WatchRoute.ets` — 路由决策表（复用）；`WatchBridge.ets`/`WearEngineTransport.ets` — 传输换网络
- `entry/src/main/ets/companion/CompanionTypes.ets`/`CompanionStore.ets`/`CompanionEngine.ets` — 接缝与大脑
- `entry/src/main/ets/pages/OnTripPage.ets:244/252/1502/1557/1753` — 执行器/点选/执行/打卡
- `entry/src/main/ets/data/CheckinDao.ets:30` — 打卡写入口与 source 口径
- `wearable/` — 手表模块（换传输层）
- BFF 服务端（Express，鉴权/幂等/限流中间件）— 新增 watch 路由与暂存
- `tools/verify_watch_contract.sh` — 协议离线断言（复用扩充）

### 14.5 审查说明
本规格由主代理逐项自检（占位符/内部一致性/范围/模糊性）；**本轮通用子代理不可用，未做独立子代理二轮审查**，请用户审查时留意。