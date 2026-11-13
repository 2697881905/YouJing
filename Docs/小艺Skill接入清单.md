# 小艺 Skill 接入清单（有径）

> 日期：2026-10-23。**应用侧已完成并真机验证；平台侧需要你在小艺开放平台操作。**
> 本项目走的是 API 26 的「应用内 Skill」（app skill），不是旧的 IntentsKit 意图声明。
> 旧的 `resources/base/profile/insight_intent.json` 与 `PlanTripExecutor` 已于 2026-10-25
> 删除（死代码：无注册入口，唯一写方消失后 `IntentHandoff` 一并移除），
> 小艺入口以本文的 Skill 为准。
>
> **2026-10-23 真机测试修正**：手机系统禁止后台应用拉起 UIAbility，
> Skill 里 `startAbility` 必报 `201`（`ohos.permission.START_ABILITIES_FROM_BACKGROUND`
> 仅系统应用可用；`startSelf()` 仅 PC/2in1）。因此链路改为
> **Skill 落盘预填 → 用户打开有径时 EntryAbility 消费 → 自动推屏2**，
> 小艺回复如实说「已记下，打开有径即可继续」。详见 §E.7。
>
> **2026-10-23 16:42 已上架**：范围「仅自己使用」，上架记录 `1.0.0`（渠道：资源库），
> 控制台 Skill 列表状态为「已上架」。无需等待审核，账号下可直接调用。
>
> **2026-11-13 契约变更（1.0.0 → 1.1.0）**：修掉两条实测缺陷——
> ① 过去日期不再被静默改写（Skill 侧直接拒，深链侧屏2 明示纠正）；
> ② `days=1` 就是 1 天（Want 与 Skill 两条路径口径统一）。
> 契约变了版本必须跟着升，**回平台重新导入前小艺手里仍是 1.0.0**。详见 §F。
>
> **2026-10-23 屏2 预填补齐**：小艺开的是新行程，预算不再沿用上一段草稿，固定回到默认
> `¥8,000/人`（`BudgetConfig.DEFAULT`）；人数 chip 原为固定 1/2/4，现会把小艺带来的
> 3、5 等人数补进选项并高亮。仅 App 侧改动，`SKILL.md` 契约未变，无需重新上架 Skill。

## A. 先看结论

| 项 | 值 |
|---|---|
| Skill 名 | `youjing-plan-trip` |
| 能力 | 记下目的地 / 出发日 / 天数 / 同行人数；用户打开有径后自动进入屏2「行程规划」并预填 |
| 契约文件 | `entry/skills/youjing-plan-trip/SKILL.md`（随 HAP 打包） |
| 入口脚本 | `entry/skills/youjing-plan-trip/scripts/PlanTripSkill.ets` |
| 注册声明 | `entry/src/main/module.json5` → `skillProfiles` |
| 版本 | `1.1.0`（`skillProfiles.version`，平台侧需与之一致；`1.0.0` → `1.1.0` 是 2026-11-13 的契约变更，见 §F） |
| 真机注册证据 | 启动日志 `YouJing.EntryAbility: Skill 注册 1 个: youjing-plan-trip` |
| 平台侧要做什么 | 新建 / 导入 Skill → 真机测试 → 发布（见 §B） |

平台**不需要你手工填槽位**：SKILL.md 里已经写好 `exec-cli` 与完整 JSON Schema，
平台导入后按它识别 `planTrip` 的参数与返回值。这是应用内 Skill 与旧「意图」方案最大的区别。

## B. 你在小艺开放平台要做的（按顺序）

### B0. 前置条件

1. 一台 **HarmonyOS 7.0** 真机，且小艺 App 为 **Beta 版**（应用内 Skill 的真机测试走 Beta 小艺）。
2. 要测的 HAP 已安装到该真机；bundleName 必须是 `com.youjing.app`。
3. AGC 应用「有径」已注册（已完成，APP ID `6917619826312400726`）。
4. 用与 AGC 同一账号登录小艺开放平台。

### B1. 新建 / 导入 Skill

1. 打开小艺开放平台控制台：<https://developer.huawei.com/consumer/cn/hag/hagindex.html#/>
2. 进入 **Skill** → **新建 Skill**。
3. 选择「导入 Skill / 从应用导入」这类入口（应用内 Skill 的包就在 HAP 里）。
   如果当前控制台只提供「上传 Skill 包」，就上传**当前签名的 HAP**
   （`entry/build/default/outputs/default/entry-default-signed.hap`）。
   控制台文案可能随版本调整，以页面实际入口为准。
4. 绑定信息：
   - 应用 / bundleName：`com.youjing.app`
   - Skill 名：`youjing-plan-trip`
   - Skill 版本：`1.1.0`（必须与 `module.json5` 的 `skillProfiles.version` 相同）
5. 导入后核对平台解析结果：
   - 触发场景：`帮我规划去北京的行程`、`安排一次上海三天两晚的旅游`、`下个月去广州玩四天，两个人`
   - 场景 1（`planTrip`）参数：`arg1` 目的地、`arg2` 出发日 `YYYY-MM-DD`、`arg3` 天数、`arg4` 人数
   - 返回值：`success` 带 `destination/startDate/days/people/route/launched/message`；
     手机上 `launched=false`（参数已记下），`message` 可直接作为回复；
     失败为 `ERR_INVALID_PARAMS` 或 `ERR_INTERNAL`，均带 `suggestion`

### B2. 真机测试

1. 在平台点「真机测试」，按提示选中已安装有径的设备。
2. 对小艺说：
   > 帮我规划去上海的行程，12 月 20 号出发，4 天，3 个人
3. 预期链路：
   - 小艺命中 Skill → 调 `planTrip`
   - 参数写入 `SkillPrefill`；`startAbility` 在手机上返回 201，属预期
   - 小艺回复：`已记下：上海，12月20日出发，4天，3人。打开「有径」会自动进入行程规划页并填好这些信息。`
   - 用户点开有径 → 屏2 显示：`上海` / `12月20日 – 12月23日` / `4天3晚` / `3 位成人`
   - Skill 返回 `status=success`，`data.launched=false`，`data.message` 同上
   - **2026-10-23 16:31 已按此链路真机复测通过**：小艺原话「已记下：上海，10月24日出发，
     3天，2人。打开「有径」会自动进入行程规划页并填好这些信息～」；打开有径后屏2 实测
     `上海 / 10月24日 – 10月26日 / 3天2晚 / 2 位成人`。
4. 再测两条边界：
   - 说「帮我规划去成都的行程」→ 不应拉起，返回 `ERR_INVALID_PARAMS`，
     `suggestion` 为「目前只支持北京、上海、广州、深圳，你想去哪一个？」
   - 只说「帮我规划去上海」不给日期 → 小艺应先追问日期（SKILL.md 的「不要调用的情况」已写明）

### B3. 发布

平台给三档发布范围：

| 范围 | 用途 |
|---|---|
| 仅自己可用 | 先自测，不对外 |
| 发布到小艺 | 小艺能调用，但不进 Skill 广场 |
| 上架 Skill 广场 | 公开可搜索 |

首次建议先选「仅自己可用」跑通 B2，再按需要升级。审核通常 **1–3 个工作日**。
开发文档 §8 已把「Skill 上架有延迟」列为风险，所以 App 内主链不依赖 Skill。

> 实测（2026-10-23）：「仅自己使用」上架即时生效——16:42 提交后列表状态即为「已上架」，
> 上架记录为 `1.0.0 / 资源库`；发布表单随后自动把下一版预置为 `1.0.1`。

### B4. 以后改 Skill 的发布流程

1. 改 `SKILL.md` / `PlanTripSkill.ets`。
2. 提升 `entry/src/main/module.json5` 里 `skillProfiles.version`（如 `1.0.1`）。
3. 重新构建并签名 HAP，装到测试机。
4. 回平台重新导入 / 提交新版本，再审一次。

> 只改脚本不改 SKILL.md，平台侧看到的契约不变；只改 SKILL.md 不改版本，平台可能仍拿旧契约。

> **2026-11-13 已按此流程走过一轮**：`1.0.0` → `1.1.0`（契约变更：出发日不得早于当天）。
> 新 HAP 必须回平台**重新导入 / 送审**；在重新导入之前，小艺手里的仍是 1.0.0 契约
> （旧契约允许过去日期）。

## C. 应用侧已实现（我做的，真机验过）

### C1. 注册声明

`entry/src/main/module.json5`：

```json5
"skillProfiles": [
  {
    "name": "youjing-plan-trip",
    "abilityName": "EntryAbility",
    "srcEntries": [
      "../../skills/youjing-plan-trip/scripts/PlanTripSkill.ets"
    ],
    "version": "1.1.0"
  }
]
```

构建后 HAP 内 `module.json` 的 `srcEntries` 会被规范化为
`@normalized:N&&&entry/skills/youjing-plan-trip/scripts/PlanTripSkill&`，属于正常现象。

### C2. Skill 入口契约

`PlanTripSkill.ets` 是薄适配层，只做四件事：

1. 校验 `argv`（位置参数依次为目的地、出发日、天数、人数）。
2. 把四参写入 `data/SkillPrefill`（Preferences 分片 `youjing_skill_prefill`，取后即删，2 小时过期）。
3. 尽力 `startAbility`（PC/2in1 可能成功；手机上必 201，属预期，不改变返回）。
4. 用 `scriptManager.completeArkTSScriptInApp` 回 `result`；`launched` 如实反映是否拉起。

入口签名（平台按 SKILL.md 调用）：

```ts
public async planTrip(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void>
```

参数映射：

| argv | 含义 | 规则 |
|---|---|---|
| `arg1` | 目的地 | 只接受 北京 / 上海 / 广州 / 深圳 |
| `arg2` | 出发日 | 必须是真实存在的 ISO 日期（`2026-02-30` 会被拒），且**不得早于当天**（过去日期会被拒，`ERR_INVALID_PARAMS` + suggestion） |
| `arg3` | 天数 | 1–30 整数；省略时默认 3（`1` 就是 1 天，不是「没给」） |
| `arg4` | 人数 | 1–30 整数；省略时默认 2 |

区间与实现**同源**：`entry/src/main/ets/utils/TripLimits.ets` 是全工程唯一口径，
Skill 脚本、深链 Want、草稿预填校验共用它（2026-11-13 修缺陷 B 时新增）。

预填落盘（主路径）：

```ts
{
  destination: '上海',
  start: '2026-12-20',
  days: 4,
  people: 3,
  savedAt: Date.now()
}
```

`EntryAbility` 的消费时机：

- **冷启动**：`loadContent` 完成后 `bootstrap()` 置 `contentReady`，若已可见则取预填。
- **热启动 / 从后台返回**：`onForeground()` 置 `visible` 后取预填。
- **后台被 Skill 绑起**：`visible=false` 时不取，避免进程被杀导致预填丢失。
- 取到后写入 `PlanDraft.basic`（`days` 反算 `endDate`）并 `pushPath('TripInput')`。
- 预算固定写 `BudgetConfig.DEFAULT`（¥8,000/人）：Skill 没有预算参数，且这是一段新行程，
  不应静默继承上一段草稿；其余风格/节奏/选点仍在 `PlanDraft.fresh()` 时清空。
- 屏2 人数 chip 以 1/2/4 为底，若 `people` 不在其中（如 3、5）则补入并参与高亮，
  避免「数字对但 chip 不高亮」。

外部 Want 通道仍保留（`aa start` / 深链）；`applyWant` 成功应用参数时会清掉
盘上的 Skill 预填，避免同一次请求被消费两次。

### C3. SKILL.md 契约

按官方样例（`guide-snippets/.../ArktsSkillDevelopmentGuide`）对齐，包含：

- YAML `name` / `description`
- `## 触发场景`：典型话术 + 不调用的情况
- `### 场景1:预填并打开行程规划(planTrip)`
  - `**触发场景**`
  - `**执行参数**`：exec-cli 示例 + 完整命令对象 Schema
    （`command` / `skillName` / `scriptPath` / `functionName` 全为 `const`，`args` 要求 `arg1`、`arg2`）
  - `**执行返回值**`：成功 / 参数非法 / 内部错误三组示例 + 带 `oneOf` 与 `required` 的完整 Schema

### C4. 已验证的证据

| 项 | 证据 |
|---|---|
| HAP 内含契约 | `unzip -l ...hap` 见 `skills/youjing-plan-trip/SKILL.md` |
| 系统注册 | 启动日志 `Skill 注册 1 个: youjing-plan-trip` |
| 下游预填（2026-10-23 记录） | `aa start` 传同一组 Want 参数：屏2 显示 `上海 / 8月1日–8月4日 / 4天3晚 / 3 位成人` |
| App 存活时复用 | `onNewWant` 日志 `外部预填 route=TripInput …`，页面栈不重建 |
| 平台真机调用（2026-10-23 记录） | 2026-10-23 15:54 小艺日志 `execCli2 payload=...--args '{"arg1":"上海","arg2":"2026-08-01","arg3":"4","arg4":"3"}'`，参数解析无误 |
| 失败真因 | 同次调用返回 `code:-1`，`errMsg: startAbility failed: 201 The application does not have permission to call the interface.` |
| 修正后复测 | 16:31:34 日志 `已写入预填 上海 2026-10-24 3天 2人` → `startAbility 未获准 code=201` → 16:32:44 `取出预填` + `Skill 预填 上海 2026-10-24→2026-10-26 2人`；屏2 五项对表通过 |
| 2026-11-13 契约修复复跑 | 离线 `SKILL_ASSERTIONS_OK cases=120`（打真实生产代码）；真机 `SKILL_PROBE_OK`：`days=1` → `1天`、过去日期 → 屏2 改今天起算且 toast 明示、越界天数被忽略 |

> `bm dump -n com.youjing.app` **不会**列出 `skillProfiles`（只列 ability 的 home skills），
> 不要用它判断 Skill 是否注册；以 `skillManager.getSkillInfosForSelf` 的启动日志为准。
> 该日志受 `BuildConfig.IS_DEBUG` 门控，release 包不打印，但注册本身不受影响。

## D. 本地自验（不依赖平台）

```bash
# 冷启动 / 前台改参：与 Skill 下发的 Want 完全相同
hdc shell aa start -a EntryAbility -b com.youjing.app \
  --ps route TripInput --ps destination 上海 --ps start 2026-12-20 --ps days 4 --ps people 3
```

真机实测（2026-11-13 复测）：屏2 显示 `上海 / 12月20日 – 12月23日 / 4天3晚 / 3 位成人`。

另外两条边界（2026-11-13 新增，缺陷修复后的期望）：

```bash
# 单日 1 天：days=1 就是 1 天（修缺陷 B 之前这里会显示 3 天 2 晚）
hdc shell aa start -a EntryAbility -b com.youjing.app \
  --ps route TripInput --ps destination 上海 --ps start 2026-12-20 --ps days 1 --ps people 2
# → 屏2 显示 12月20日 – 12月20日 / 1天

# 过去日期：屏2 改为今天起算并弹 toast 明示，长度不变（修缺陷 A）
hdc shell aa start -a EntryAbility -b com.youjing.app \
  --ps route TripInput --ps destination 上海 --ps start 2026-09-14 --ps days 4 --ps people 3
# → 屏2 显示 今天 – 今天+3 / 4天3晚 + toast「预填的出发日期 9月14日 已过期，已改为今天起算（4天不变）」
```

> 过去日期在**深链 Want 侧照写草稿**、由屏2 统一改写并明示；Skill 脚本侧则直接拒
> （`ERR_INVALID_PARAMS` + suggestion）。两侧口径不同是因为承诺方不同：
> 小艺说了什么必须和界面显示的一致，所以入口就拒；深链没有人格化回复，明示即可。

局限：设备 `/system/bin` 下没有 `ohos-arkTSScript` 命令，**无法用 hdc 直接调 Skill 函数**；
本地只能验证 Skill 的下游（Want → 草稿 → 屏2）。真正的「小艺说一句话 → 调 Skill」
必须在平台真机测试里完成。

## E. 已知边界与雷区

1. **只支持四城**：北京 / 上海 / 广州 / 深圳。种子库未覆盖的城市直接返回 `ERR_INVALID_PARAMS`，
   不要靠模型硬编。
2. **出发日期必填**：用户没说日期时，SKILL.md 要求先追问，不代填今天。
3. **HarmonyOS 7.0 + Beta 小艺**：低版本或正式版小艺可能看不到应用内 Skill，这不是应用侧 bug。
4. **平台导入的是「当前签名 HAP」**：换签名 / 换版本后要重新导入；调试签名每次重装不必重新导入，
   但 Skill 内容变了必须升版本。
5. **不要把 Client Secret、签名口令等写进 SKILL.md 或脚本**；Skill 包会随 HAP 分发。
6. **发布有延迟**：审核 1–3 个工作日；App 内闭环不依赖它。
7. **手机后台禁止拉起界面（实测 201）**：`UIAbilityContext.startAbility` 从后台调用需要
   `ohos.permission.START_ABILITIES_FROM_BACKGROUND`，该权限仅系统应用可用；
   `startSelf()` 在手机上返回 801（仅 PC/2in1），`startSelfUIAbilityInCurrentProcess` 同样仅 PC/2in1，
   `ApplicationContext.startSelfUIAbility` 只在延迟退出窗口内有效。
   因此**不要**再把「小艺说完自动弹出有径」当验收标准；正确标准是：
   小艺如实回复已记下 → 用户点开有径 → 屏2 已预填。
   Skill 里的 `startAbility` 仅保留给 PC/2in1 尽力尝试，失败不改变 `success` 与参数落盘。
8. **出发日不得早于当天**（2026-11-13 契约变更，`1.0.0` → `1.1.0`）：
   过去日期在 Skill 脚本侧被拒（`ERR_INVALID_PARAMS` + suggestion「出发日期 … 已经过去了，
   请给一个今天或将来的日期。」），深链 Want 侧照写草稿、由屏2 明示纠正成今天起算（长度不变）。
   小艺在对话里给出过去日期时，应**追问一个将来的日期**，而不是把同一句换个说法再调一次。
9. **`days=1` 就是 1 天**（2026-11-13 修复）：Want 与 Skill 两条路径的 `endDate` 口径统一，
   区间共用 `utils/TripLimits.ets`（1–30 天 / 1–30 人）。

## F. 2026-11-13 契约修复记录（缺陷 A / B）

测试出处：`Docs/小艺Skill测试报告-2026-11-13.md`（含修前实测证据与修后复跑结果）。

| 缺陷 | 根因 | 修法 | 修后实测 |
|---|---|---|---|
| A · 过去日期被静默改写 | `TripInputPage.ets` 丢弃过期草稿日期；Skill 侧也不拦 | ① Skill 脚本拒过去日期（`ERR_INVALID_PARAMS` + suggestion）；② Want 侧照写草稿；③ 屏2 统一改写为今天起算、**长度不变**，并 toast + 日志明示 | 屏2 `今天 – 今天+3 / 4天3晚`，toast「预填的出发日期 9月14日 已过期，已改为今天起算（4天不变）」 |
| B · Want 路径 `days=1` 被当成 3 天 | `EntryAbility.applyWant` 的 `days > 1` 门槛 | 改 `days >= 1` 并把区间收敛到 `utils/TripLimits.ets`（1–30），与 Skill 通道同源 | 屏2 `12月20日 – 12月20日 / 1天` |

改动文件：`PlanTripSkill.ets`、`EntryAbility.ets`、`TripInputPage.ets`、
`utils/DateUtils.ets`（新增 `isUpcoming`）、`utils/TripLimits.ets`（新增）、
`SKILL.md`、`module.json5`（版本 `1.1.0`）。

> **平台侧必须做的事**：回开放平台**重新导入 / 送审 1.1.0**。在那之前小艺手里是 1.0.0 契约，
> 仍允许过去日期——App 侧已修，但平台不改契约就等于没修。

---

## G. 你的操作清单（打勾即可）

- [x] 准备 HarmonyOS 7.0 真机 + Beta 小艺，安装当前签名 HAP
- [x] 登录小艺开放平台（与 AGC 同账号）
- [x] Skill → 新建 Skill → 导入 Skill（bundle `com.youjing.app`，skill `youjing-plan-trip`，版本 `1.0.0`）
- [x] 核对平台解析出的触发场景 / `planTrip` / 参数 Schema
- [x] 真机测试「帮我规划去上海的行程」→ 小艺先追问日期；补「明天」后回复「已记下」；
      点开有径后屏2 预填正确（实测 `上海 / 10月24日–10月26日 / 3天2晚 / 2 位成人`）
- [x] 测试不支持城市与缺日期两条边界（杭州被四城白名单拦下；未给日期时小艺先追问）
- [x] 2026-10-23 16:42 按「仅自己使用」上架 `1.0.0`（渠道：资源库），控制台状态「已上架」
- [ ] 2026-11-13 契约变更（`1.0.0` → `1.1.0`）：回平台重新导入并送审，
      否则小艺手里还是 1.0.0 契约（允许过去日期）
