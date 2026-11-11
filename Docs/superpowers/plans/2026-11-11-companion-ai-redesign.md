# 伴随式 AI 助手 · 交互逻辑大改造 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把有径从「表单 wizard + 一次性 AI」改造成「伴随式 AI 助手」——助手站在现实这边，计划 vs 现实有后果时就地浮出可点选的请示卡片，用户一键/一句话/划掉响应，处久了低风险决定降级为通知。

**Architecture:** 叠加层，不重组五 tab 导航。新增 `companion/` 纯逻辑层（大脑：计划 vs 现实比对、后果评估、请示选项生成、偏好降级）+ 全局浮层（决策卡 + 常驻触点，挂 Index mainTabs 的 Stack，返回键走 overlayBackGuard）+ 各屏集成。大脑复用现有纯函数 TripSignals.suggest / SkipPlanner.* / Geo.arrived，产出与 TripSuggestion/ReplanOutcome 同形的结构；落库撤销复用 OnTripPage.commitDay 链路。

**Tech Stack:** ArkTS V1 严格模式（仅 .ets）；官方 ArkUI + Hds 组件；现有组件 OptionCard/ChipRow/SoftChip/GlassPanel/YoujingButton/GlowInput/TimelineNode；hypium 单测 + tools/verify_*.sh 离线断言。

**Spec:** 设计讨论见会话记录与 `/Users/itxiaobai/.qoder-cn/projects/-Users-itxiaobai-HarmonyProject2/memory/youjing-companion-ai-redesign.md`。已定：请示性 / 点选卡片为主语音为辅 / 就地浮现 / 助手站现实这边 / 叠加不重组 / 组件与软件一致 / 偏好降级带护栏。

## Global Constraints

- ArkTS V1 严格：禁对象解构；对象字面量必须具名 interface；@State 避开 tabIndex/width/height 保留名；@Builder 内不写普通语句；函数回调不加 @Prop；@Link 无默认值父侧 $绑。
- 只用官方 + Hds 组件，不自绘控件，不引第三方依赖，不新增页面/路由。
- 隐私本机优先：行程/打卡/账本/偏好只落本机，不上云；定位仅前台订阅。
- 服务器暂缓：判断层先用端侧规则；自由多轮对话后置（不在本计划）。
- 通知/实况窗 AGC 未获批：伴随层主要前台工作，不依赖锁屏卡片。
- 杨凌单点验证；坐标近似（300m 半径），交互必须为「测不准」留余地。
- 组件一致性：决策卡 = OptionCard/YoujingButton/GlassPanel + 现有 token；动效走 MotionTokens 五档；色/字/几何/间距走 ColorTokens/TypeTokens/RadiusTokens/SpaceTokens。
- 建议口径跟 owedKey（欠站），不跟 hero 钟点站 current（TripSignals.ets:41-48 钉死的历史缺陷）。
- 每阶段独立可测、可回退；高频提交；TDD。

## 分阶段路线图（每阶段独立交付，各自细化计划）

- **Phase 1（本计划详述）：伴随核心逻辑层** — `companion/CompanionEngine.ets` + `companion/CompanionPrefs.ets` 纯逻辑 + hypium + 离线断言。旗舰能力「规划外到访 → 请示卡」的大脑。不含 UI。
- **Phase 2：决策卡组件 + 全局浮层 + 常驻触点** — `components/CompanionCard.ets`（OptionCard/YoujingButton/GlassPanel 搭）、Index 全局浮层挂点、overlayBackGuard 接入、触点（ChipRow 快捷短语 + 按住说话 + GlowInput 兜底）。
- **Phase 3：行中集成** — OnTripPage 的 signalBar 升级为伴随请示卡；规划外到访检测（ArrivalWatcher + 停留闸 + POI 识别）接 CompanionEngine；执行选项接 SkipPlanner/commitDay。
- **Phase 4：行前草案先行** — 一句话提主入口（GlowInput），本机规则即铺草案（现有时间线），QA 降级为上下文 OptionCard 追问，bindSheet 就地改。
- **Phase 5：行后 + 偏好学习闭环** — 回顾伴随、偏好降级 UI 透明化（「照你习惯…」）、纠正回弹。

---

## Phase 1：伴随核心逻辑层

**Files:**
- Create: `entry/src/main/ets/companion/CompanionTypes.ets`（共享类型）
- Create: `entry/src/main/ets/companion/CompanionPrefs.ets`（偏好计数/降级，纯逻辑）
- Create: `entry/src/main/ets/companion/CompanionEngine.ets`（规划外到访请示生成，纯逻辑）
- Test: `entry/src/ohosTest/ets/test/Companion.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`（注册）
- Create: `tools/companion_check.ts` + `tools/verify_companion_logic.sh`（离线断言）

**Interfaces:**
- Consumes: `model/Trip.ets` 的 `TripDay/Activity/ActivityCategory`；`utils/DateUtils`（如需）。
- Produces（后续 Phase 依赖）:
  - `CompanionPrompt { id, kind, title, detail, options: CompanionOption[], recommendedIndex, stake, mode }`
  - `CompanionOption { key, label, subline, action: CompanionAction }`
  - `CompanionAction { kind, targetId, deltaMin, placeName }`
  - `CompanionEngine.unplannedArrival(input: UnplannedInput, prefs: CompanionPrefs): CompanionPrompt | null`
  - `CompanionPrefs.modeFor(key): 'ask'|'notify'` / `recordChoice(key, optionKey, recommendedKey)` / `correct(key)`

### Task 1: 共享类型 CompanionTypes

**Files:** Create `entry/src/main/ets/companion/CompanionTypes.ets`

- [ ] **Step 1: 写类型（无逻辑，直接定义）**

```typescript
/** 伴随助手共享类型（纯数据，无 @kit 依赖，可离线断言）。 */

export type CompanionStake = 'low' | 'high';
export type CompanionMode = 'ask' | 'notify';
export type CompanionKind = 'unplanned_arrival' | 'unknown_place';
export type CompanionActionKind = 'move_tomorrow' | 'quick_visit' | 'keep_plan' | 'record_place' | 'none';

export interface CompanionAction {
  kind: CompanionActionKind;
  targetId: string;      // 受影响的计划节点 id；无则空串
  deltaMin: number;      // 顺延量；无则 0
  placeName: string;     // 新地点名；无则空串
}

export interface CompanionOption {
  key: string;           // 稳定意图键（偏好计数用）
  label: string;         // 主文案
  subline: string;       // 后果说明
  action: CompanionAction;
}

export interface CompanionPrompt {
  id: string;            // 去重键
  kind: CompanionKind;
  title: string;
  detail: string;
  options: CompanionOption[];
  recommendedIndex: number;
  stake: CompanionStake;
  mode: CompanionMode;   // 由偏好降级决定
}

/** 规划外到访的输入（POI 识别由集成层做，引擎只吃结果，保纯逻辑）。 */
export interface UnplannedInput {
  recognized: boolean;   // 是否识别出地点
  placeName: string;     // 识别出的地点名（未识别空串）
  estVisitMin: number;   // 该地点典型游览时长（分钟）
  day: TripDay;          // 当日计划
  nowMin: number;        // 当前时刻（0-1439）
}
```

（import TripDay from '../model/Trip'）

- [ ] **Step 2: Commit** `feat(伴随): 共享类型 CompanionTypes`

### Task 2: 偏好降级 CompanionPrefs（TDD）

**Files:** Create `companion/CompanionPrefs.ets`；Test `ohosTest/ets/test/Companion.test.ets`

**降级规则**：同一决策键连续选推荐项 ≥3 次 → notify；用户纠正一次 → 立刻回 ask；高风险键永不降级（由引擎传 stake 控制，Prefs 只管计数）。

- [ ] **Step 1: 写失败测试**（Companion.test.ets 起 describe('CompanionPrefs')）

```typescript
it('prefs_degrade_after_three_consistent_recommended', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
  const p = new CompanionPrefs();
  expect(p.modeFor('k')).assertEqual('ask');
  p.recordChoice('k', 'rec', 'rec');
  p.recordChoice('k', 'rec', 'rec');
  expect(p.modeFor('k')).assertEqual('ask');
  p.recordChoice('k', 'rec', 'rec');
  expect(p.modeFor('k')).assertEqual('notify');
});
it('prefs_correction_restores_ask_immediately', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
  const p = new CompanionPrefs();
  p.recordChoice('k', 'rec', 'rec'); p.recordChoice('k', 'rec', 'rec'); p.recordChoice('k', 'rec', 'rec');
  expect(p.modeFor('k')).assertEqual('notify');
  p.correct('k');
  expect(p.modeFor('k')).assertEqual('ask');
});
it('prefs_non_recommended_choice_resets_streak', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
  const p = new CompanionPrefs();
  p.recordChoice('k', 'rec', 'rec'); p.recordChoice('k', 'rec', 'rec');
  p.recordChoice('k', 'other', 'rec');
  p.recordChoice('k', 'rec', 'rec');
  expect(p.modeFor('k')).assertEqual('ask');
});
```

- [ ] **Step 2: 跑测试确认失败**（CompanionPrefs 未定义）
- [ ] **Step 3: 实现 CompanionPrefs**（纯逻辑：`private streak: Record<string, number>`；recordChoice 选推荐则 +1 否则归零；≥3 置 notify 集；correct 清零并移 notify；modeFor 查集。持久化留 Phase 5，本阶段内存态。）
- [ ] **Step 4: 跑测试确认通过**
- [ ] **Step 5: Commit** `feat(伴随): 偏好降级 CompanionPrefs + 测试`

### Task 3: 规划外到访引擎 CompanionEngine（TDD）

**Files:** Create `companion/CompanionEngine.ets`；Test 追加 describe('CompanionEngine')

**逻辑**：
- 未识别 → unknown_place 轻问卡（low，options=[record_place 推荐, none 跳过]）。
- 已识别：算后果——找当日 nowMin 之后第一个非交通/住宿节点 next；若 `nowMin + estVisitMin > next.sortMin`（挤占下一站）→ 有后果；否则 null（安静吸收，不打扰）。
- 有后果 → 三选项：① move_tomorrow（推荐，把 next 挪明天，targetId=next.id）② quick_visit（压缩游览挤进去，none）③ keep_plan（按原计划，地点记下次，record_place）。stake=low，mode=prefs.modeFor('unplanned_move_tomorrow')。

- [ ] **Step 1: 写失败测试**（构造 day fixture：nowMin=600，next 节点 time='11:00'(660)，estVisitMin=90 → 600+90=690>660 有后果；estVisitMin=30 → 630<660 无后果 null；未识别 → unknown_place）
- [ ] **Step 2: 跑测试确认失败**
- [ ] **Step 3: 实现 CompanionEngine.unplannedArrival**（纯静态；分钟换算 HH:mm→min 用 DateUtils 或本地纯函数；剔除 TRANSPORT/HOTEL；选项文案中文）
- [ ] **Step 4: 跑测试确认通过**
- [ ] **Step 5: Commit** `feat(伴随): 规划外到访请示引擎 CompanionEngine + 测试`

### Task 4: 注册 + 离线断言

**Files:** Modify `List.test.ets`；Create `tools/companion_check.ts` + `tools/verify_companion_logic.sh`

- [ ] **Step 1: List.test.ets 注册 companionTest**（import + 调用各一行）
- [ ] **Step 2: 离线脚本**（仿 verify_weather_logic.sh 拷树：model/Trip,Replan + companion/* + utils/DateUtils + tools/companion_check.ts；tsc --strict + node 断言）
- [ ] **Step 3: 真机 hypium 全量 + 离线脚本绿**
- [ ] **Step 4: Commit** `test(伴随): 注册 hypium + 离线断言脚本`

---

## Self-Review

- Spec 覆盖：Phase 1 覆盖「规划外到访请示 + 偏好降级 + 测不准轻问 + 后果 gating（安静吸收）」；其余 spec 点（点选卡 UI/触点/行前行后集成）在 Phase 2-5 路线图，各有归属。
- 占位符：无 TBD；Phase 2-5 为路线图（届时各自细化为独立计划，符合「每子系统独立计划」）。
- 类型一致：CompanionPrompt/Option/Action/UnplannedInput 在 Task 1 定义，Task 2/3 引用同名；CompanionPrefs.modeFor/recordChoice/correct 签名前后一致。