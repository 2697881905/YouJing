# 有径布局结构体系迁移到有据形态 — 设计（方案②：分层迁移）

日期：2026-11-05　作者：agent（用户拍板方案②）
范围：窗口/系统栏、壳层、顶栏接口、顶栏行为四层。不含业务页面重构。

## 0. 决策记录

| 项 | 状态 |
|---|---|
| 迁移目标 | **已定**：结构与观感两者都要，一次迁完（用户选） |
| 迁移路径 | **已定**：方案②分层迁移，L1→L2→L3→L4，每层独立装机复验独立回退 |
| 冲突时谁让位 | **已定（2026-11-05 用户拍板）**：**有据优先**。原话「两个 App 是同系列产品，所以设计语言要保持一致，有据是我打磨许久的 App，所以按照有据的界面结构和布局体系来」——结构与界面**都**按有据，不再分域 |
| 契约文件 | `~/Pictures/…/DESIGN.md` 仍由用户持有；**我不擅自改它**。凡本次迁移使契约值失效的条目，逐条列进 §6A 交用户确认后修订（改的是契约跟实现，不是实现跟契约） |
| L4 状态 | 由「待授权」改为**在范围内**：顶栏跟手收起、dock 尺寸基准等观感项按有据落地 |

## 1. 目标与非目标

**目标**
- G1 **几何量单源**：底部避让、导航方式判定、系统栏补设三件事各有一个模块负责，页面只消费，不再在壳层/页面里各写一遍。
- G2 **壳层形态对齐**：外层 `Navigation(hideTitleBar)` + 五格「格内自带 HdsNavigation + titleBar」+ 顶栏配置唯一入口。
- G3 **顶栏行为对齐**：跟手收起（`dynamicHideTitleBar` + `bindToScrollable`）与模糊终态。
- G4 **每层可独立复验、可独立回退**；18 把尺跟着每层同步改，不允许出现"整片红"的中间态。

**非目标**
- 不改数据层、商业化链路、BFF。
- 不引入有据的业务组件（互动栏、输入栏、详情页等）。
- 不追求与有据像素一致，只追求**同一套结构决策**：同一个量的来源只有一个地方。
- L1–L3 期间不改任何颜色、字号、间距。

## 2. 现状对照（带证据）

| 维度 | 有据 | 有径（现在） | 差异的实际后果 |
|---|---|---|---|
| 底部避让 | `utils/navMode.ets`：`settings 'float_navigation_info'` 为权威信号 + 「避让矩形是否横贯整屏」兜底，发 `BOTTOM_NAV_INSET_KEY` / `BOTTOM_BAR_INSET_KEY` | `pages/Index.ets:246` `barBottomMargin = floatingDockBottomMargin(28) + this.navIndicatorHeight`，**只看高度** | 手势条实测 27.9vp、真机三键栏 27.8vp，区间重叠判不开（记忆 `harmonyos-nav-mode-by-rect-width`）。三键设备上 dock 位置与末行净空都会错 |
| 系统栏补设 | `utils/systemBar.ets`：四连发 400/1000/1800/3000ms，滚动宿主在偏移回 0 时调 `requestSystemBarRefresh()` | 只有 `EntryAbility` 的配置变化 / 回前台 / 挂载期 3s 单发 + `TopStrip.paint` 设 `isStatusBarLightIcon` | 有据真机实证（2026-10-25）：HDS 在**滚回顶部**时会回写系统栏属性覆盖应用设置，SDK 无关停人口。有径现在没有这条通道 ⇒ 图标可能被渲成不可见 |
| 壳层形态 | `Stack > Navigation(hideTitleBar(true), mode Stack, clip(false)) > Stack > Column > HdsTabs` | `Index` 直接 `HdsTabs`；规划格内嵌 `HdsNavigation`，其余四格在页面内 `rootMode` 自带 | 同一件事（顶栏避让、带子归属）在两个位置各写一遍。**今晚那条 `.padding({top: statusBarHeight})` 就是这类重复的产物**：栏体已经在避让，壳层又避让了一次 |
| 顶栏收起 | `dynamicHideTitleBar({ hideBottomBuilder: true, mode: SCROLL_UP_TO, hideOffset: 0, hideRatio: 1.0 })` + `bindToScrollable` | 只有 `IMMERSIVE_GRADIENT_BLUR` 的 scrollEffect，栏体不跟手收起 | 观感差异，属 §6 冲突项 1 |
| 状态栏带子 | 无此概念：系统栏透明 + 页面铺穿 | `utils/TopStrip.ets`（视图层涂 + 系统栏透明 + 图标明暗） | A 档 + 撤 padding 后问题已消失，`TopStrip` 只剩"窗口背景色 + 图标明暗"两处职责，L3 把它收窄 |

## 3. 分层设计

### L1 几何单源（观感零变化）

**改什么**
- 新增 `entry/src/main/ets/utils/navMode.ets`（移植有据，键名沿用 `bottomNavInsetVp` / `bottomBarInsetVp` / `navMode` / `navBarSpansWidth`）。
- 新增 `entry/src/main/ets/utils/systemBar.ets`（移植四连发通道）。
- `Index` 的 `barBottomMargin` 改读 `BOTTOM_NAV_INSET_KEY`，且**必须在 build 属性里直接读该状态变量**——有据文件头写明「只挂 `@StorageLink` 而不在 build 里读变量是无效绑定」。
- `LayoutTokens.floatingDockClearance`（现在硬编码 112）改为「dock 高 + inset」派生，消掉第二处硬编码。
- `EntryAbility` 注册 `setSystemBarRefresher`；各滚动宿主在 `onDidScroll` 判定偏移回 0 时调 `requestSystemBarRefresh()`。
- `TopStrip` 职责收窄：只保留窗口背景色与图标明暗，不再涂系统栏色。

**验收**：三键 / 手势两态下的 dock 顶边与末行净空（模拟器可切三键）；深浅 × 明暗四组合下状态栏图标可见性。
**回退**：两个新模块整体删除，`Index` / `EntryAbility` 改动各自 revert，互不牵连。

### L2 壳层形态

**改什么**
- `Index` 外层加 `Navigation(APP_NAV) { … }.hideTitleBar(true).mode(NavigationMode.Stack).clip(false)`。
- 五格统一改成「格内自带 `HdsNavigation` + `titleBar`」，以现有规划格为模板；`stackOfTab(index)` 的分栈语义保留。
- 深链与小艺入口的 `routeTo` 目标栈语义**明确定为**：外层 `Navigation` 只作宿主（`hideTitleBar`），
  外部 `--ps route X` 仍按 `tabOfRoute` 先切页签、再 push 进**该页签自己的栈**（`stackOfTab(index)`），
  不得改推外层 APP_NAV——否则 16 屏深链验收与「回根清栈」两条现有行为会一起变。
  这层必须逐屏重验深链（16 屏现在全靠 `--ps route` 判定到达）。

**已知约束**：`TabContent` 只能有一个子组件（今晚踩过一次编译错），格内 `HdsNavigation` 必须包在单个容器里。
**验收**：16 屏逐屏深链到达 + dump 首个实质内容 y 值 + 带子与栏下中位色一致；hypium 全绿；`audit_bar_scroll` 的调用点计数与新位置对表。
**回退**：外层 Navigation 与五格改造分两笔提交，可单独回退。

### L3 顶栏接口对齐

**改什么**
- `HdsChrome.bar(spec)` 的选项面与有据一致：`avoidLayoutSafeArea` / `enableComponentSafeArea` / `fullBleed` / `barBackground` 语义统一，删掉有径侧不再需要的分支。
- **带子色决策从壳层移交栏体**：`stripName` 那层壳层涂色取消，`TopStrip` 只留窗口背景与图标；地图类的连续顶边走 `barBackground`（有据 §7.6 明确禁止用 `fullBleed` 换连续顶边，会翻转标题与分段的顺序）。
- 22 个调用点逐个表态（`audit_bar_scroll` 已管）。

**验收**：同 L2 的复验仪式，**外加浅色档**——补上既有欠账（浅色档地图格顶边连续性从未实拍）。
**回退**：接口面改动与带子移交分两笔。

### L4 顶栏行为对齐（唯一改观感的一层）

**改什么**：逐格接入 `dynamicHideTitleBar` + `bindToScrollable`，参数先取有据值，观感由用户现场确认。

**已知坑（都是真机踩过的）**
- `dynamicHideTitleBar` 配 `safeArea=true` 会让内容跑 2.2 倍速，`hideRatio` 治不了（记忆 `arkui-hds-dynamichide-safearea-double-speed`）。
- 注入 fling **不触发** HDS 滚动特效（记忆 `hdc-injected-fling-does-not-engage-hds-scroll-effects`）⇒ 这层验收必须真人复现后被动抓帧。
- HDS 溢出菜单 ⋯ 不吃注入点击。

**前置**：§6 冲突清单拍板后才动。默认不擅自开始。

## 4. 数据流与接口边界

```
navMode.ets ──写──▶ AppStorage(bottomNavInsetVp / bottomBarInsetVp / navMode / navBarSpansWidth)
                          │读（build 属性内直接读）
                          ▼
                    Index(dock barBottomMargin) / 页面末行净空

滚动宿主 onDidScroll(偏移==0) ──▶ systemBar.requestSystemBarRefresh()
                                        │400/1000/1800/3000ms 连发
                                        ▼
                              EntryAbility refresher ──▶ TopStrip.paint(窗口背景 + 图标明暗)

HdsChrome.bar(spec) ──▶ 栏体几何与避让（含带子覆盖）；页面不再自己读 statusBarHeight
```

**隔离准则**：任何页面**不得**直接读 `statusBarHeight` / `navIndicatorHeight` 参与布局——由第 19 把尺机检（§5）。

## 5. 测试与复验协议

每层结束必跑，且**只有本轮构建成功才装机**（`tools/build_install.sh`，今晚已固化）：

1. `tools/build_install.sh default` → 装机
2. hypium 真机全量（当前基线 246/246）
3. 十八把尺 + 本 spec 新增的第 19 把
4. `python3 tools/verify_scroll_clearance.py`（滚到底净空）
5. `bash tools/verify_dock_tabs.sh` §4j 六项（需真人对表）
6. 逐屏被动抓帧复验，判据写死成数：**带子与栏下中位色差 ≤2**（今晚结案用的就是这条阈值），
   且首个实质内容 y 值 ≥ 状态图标区下沿（33.9vp → 实测 37.4~50.2vp 为合格）。

**新增第 19 把尺 `tools/audit_inset_source.py`**：禁止 `.ets` 里出现「`statusBarHeight` / `navIndicatorHeight` 直接参与 padding/margin/height 表达式」，唯一豁免是 `navMode.ets` 与发布点。
**阳性对照**：今晚被删掉的那道 `pages/Index` `.padding({ top: this.statusBarHeight })`——
  尺要拿它当已知阳性样本（还原到临时副本上必须报 1 命中），否则 0 命中不算证据。——尺必须能抓到它，否则 0 命中不算证据（记忆 `verify-the-scanner-before-trusting-a-zero`）。

## 6. 契约 vs 有据 冲突清单（2026-11-05 已全部拍板：**按有据**）

| # | 冲突项 | 有径契约现值 | 有据做法 | 默认处置 |
|---|---|---|---|---|
| 1 | 顶栏跟手收起 | 顶栏常驻 + 静止/滚动两态磨砂 | `dynamicHideTitleBar` SCROLL_UP_TO 跟手收起 | **按有据**，L4 落地 |
| 2 | dock 尺寸基准 | 宽 300 / 底距 28 / 预留 112 | 胶囊 328.3×56，整块预留 84vp | **按有据**，L1 起随 inset 一起改 |
| 3 | 栏面模糊半径 | `layout.glass-blur = 50` | 三处栏面同 50 | 已一致，无需决策 |
| 4 | 静止态图标明暗 | A 档起显式 `isStatusBarLightIcon` | 同思路 + 四连发补设 | L1 采纳（属结构，不属观感） |
| 5 | 吸顶组头材质 | sticky 组头吃不到 systemMaterial（实测） | 未用到该形态 | 有径侧保持现状并记档：**这条不是观感分歧，是平台能力缺失**，照搬不出一致效果 |

## 6A. 迁移后 `DESIGN.md` 需要跟着改的条目（我不擅自改，逐条交你确认）

| # | 契约条目 | 现值（有径） | 迁移后 | 落在哪层 |
|---|---|---|---|---|
| C1 | 顶栏行为 | 常驻 + 两态磨砂 | 跟手收起（SCROLL_UP_TO，hideRatio 1.0） | L4 |
| C2 | dock 尺寸 | 宽 300 / 底距 28 / 预留 112 | 胶囊 328.3×56 / 整块预留 84vp（含 inset 派生） | L1+L3 |
| C3 | 状态栏带子 | 四处玻璃面之一，壳层涂 | 无带子概念：系统栏透明 + 栏体铺穿 | L3 |
| C4 | 底部避让 | 常量 112 硬编码 | `navMode` 按导航方式派生 | L1 |

## 7. 里程碑

L1 → 复验 → 提交 → L2 → 复验 → 提交 → L3 → 复验 → 提交 → §6 拍板 → L4 → 复验 → 提交。
每层一个提交（用户既定偏好：一轮工作打包成一个提交；push 需单独授权）。

## 8. 明确不做

- 不照搬有据的业务组件与页面结构
- 不为过闸修改 `DESIGN.md`
- L1–L3 期间不改任何颜色、字号、间距、动效曲线
- 不在真人复现不了的状态上宣布"已验证"（注入 fling 触发不了 HDS 滚动特效这条，L4 尤其要守）

## 9. Day-0 待办（未答问题，不阻塞 L1）

1. ~~§6 冲突清单第 1、2 条要不要按有据改~~ → **已答：按有据**（L4 开工，§6A 清单生效）。
2. 迁移期间若某层实测出现非预期观感变化：默认**当层回退并归因**，不带着未知改动往下走（用户未特别指定，按最可逆项定；可随时改判）。
3. 既有产品待办（过去日期补记、真队列、D5 赠送口径、测试行程数据清理）不在本 spec，仍待用户拍板。
