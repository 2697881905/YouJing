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

## 10. 覆盖对表（2026-11-06 收口时逐条核过，证据=文件/提交/读数）

「按有据的界面结构和布局体系来」到底落到哪、还剩哪——这张表是判据，不是进度汇报。
有据侧全部以 `HarmonyProject1` 当前源码为源，逐条比到有径的实现点。

| # | 有据的结构件 | 有径的实现点 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| 1 | `utils/navInset` 纯几何判定（三键/悬浮球/手势） | `utils/navInset.ets` | **已落地** | 5 例 hypium；`e36001a` |
| 2 | `utils/navMode` 胶水层（settings 权威 + avoidArea 兜底 + 键观察者 + 响应式发布） | `utils/navMode.ets` | **已落地** | 真机 `showType=-1`、模拟器走兜底判对；`64709ad` |
| 3 | 底部避让量单源消费（`@StorageLink` + build 内直读） | `pages/Index` 的 `dockNavInset` | **已落地** | dock 顶边 2340→2427px；第 19 把尺 `audit_inset_source` |
| 4 | 系统栏图标明暗补设通道（HDS 回顶会回写） | `utils/systemBar.ets` | 代码落地，**观感待真人** | 注入 fling 触发不了遮罩，脚本自证是假绿 |
| 5 | 外层宿主 `Navigation`（独立栈 + `hideTitleBar`） | `Navigation(HOST_NAV)` | **已落地** | 宿主绑独立栈这条做成 R6 尺；`9ad23e9` |
| 6 | 每格自带 `HdsNavigation` + `titleBar`（五格同构） | 五格各自 `this.pathStack` | **已落地** | R6 扫出 6 个绑定点 = 宿主 1 + 五格 5 |
| 7 | 顶栏 `avoidLayoutSafeArea` + `maskExtraHeight: 0` + blur 50 两态 | `HdsChrome.bar()` | **已落地** | 与有据同一份字段；磨砂出图 Δ≈−9.5（§5ci 续 176 期） |
| 8 | 「没有带子概念」：顶边基色交给栏体 | — | **平台不支持，已证伪** | 栏体给实心色时 dump 的 `TitleBar` 仍 `#00000000`；同机位三列对照（§5ci 续 198） |
| 9 | dock `barFloatingStyle`：材质 / `barBottomMargin` / `barSideMargin` / **`barWidth`** | `pages/Index` `barFloatingStyle` | **已落地** | 材质同为 IMMERSIVE/EXQUISITE；`barBottomMargin` 走单源键；**板宽 2026-11-06 续 205 补齐**：设 `barWidth` 前官方排成 328.3vp，设后真机 `[99,2427][1037,2602]` = **300.2vp，与有据逐像素相同** |
| 10 | dock `gradientMask`（92vp 渐变遮罩） | `gradientMask` + `glass_bar_gradient_mask` | **已落地并 A/B 复拍** | 契约 §1067 三处玻璃面都要，此前整条漏；`audit_colors` 52→53 件偏差 0；`b55ba6b`。A/B：「我的」格 dock 背后无内容当对照位，栏内逐行 +2/+1/+5/+7/+6 L，dock 上方无带子、下方无亮边；hypium 251/251（§5ci 续 200） |
| 11 | dock `barWidth` 档位（medium/large 同值治「切页忽长忽短」） | `barWidth: { 300 / sm?420:560 / 560 }` | **判「不跟」已推翻，现按档显式给** | 原判据只验了**症状**：Mate X7 展开态（707.2vp）实测有径规划格与「我的」格 dock 读数相同（321.9×56vp），有据那条跳宽缺陷不复现，于是判「没有差异可治」。**漏问的是绝对宽度**：不设 `barWidth` 时官方按内容排成 328.3vp，而有据设 `smallWidth:300` 实量 300.2vp（`HarmonyProject1` `Index.ets:2007` + 它 `cardTokens` 注释里的 `[99,2427][1037,2602]`），契约也要 300 ⇒ 并排放就是两条长短不同的玻璃条。续 205 补上三档后手机档逐像素对齐有据。**两档都量过了**：手机档逐像素对齐有据；md 档在 Mate X7 模拟器（707.2vp）实测 dock 板 `[230,2153][1980,2328]` = **560.0×56vp**、中心即窗口中心、规划格与我的格两次读数完全相同（切页不跳宽），胶囊容器 162.88vp 对上公式 162.9、跟位 +0.5/+1.0px（§5ci 续 208） |
| 12 | 悬浮玻璃的 API 门（`@since 6.1.0(23)`） | 无门 | **不该跟** | 有径 `compatibleSdkVersion 26.0.0`，门是死代码 |
| 13 | 顶栏跟手收起 `dynamicHideTitleBar` + `bindToScrollable` | 未合入 | **待真人**（任务 #26） | 前提是 `enableComponentSafeArea=false`，正是第 8 条撞车处 |
| 14 | dock 液态选中胶囊（`dockPill*` 覆盖层 + 按压缩放 + 落影收紧） | **已移植**（`components/HdsMiniBarButton.ets` + `pages/Index` 覆盖层） | **五格逐位核过 + 浅色档已量，观感待真人** | 官方件里没有这条路：SDK `hds_tabs.json` 的 attrs 全表（`barMode/barWidth/barOverlap/barBackgroundColor/barBackgroundEffect/barBackgroundStyle/fadingEdge/divider/customContentTransition/onSelected`…）**没有任何选中指示器属性**，只能做覆盖层 + 内联官方 `hds_button` 源码（有据 `components/HdsMiniBarButton.ets`，6.3KB）。有据动机出自华为开发者联盟文章《对沉浸光感tabbar的优化改造》，其基线 §7.6.32 逐条对表：**痛点①（高光与图标同层）不存在**（TabBar 下只有 5 个 Column、无表面节点），**痛点②（选中只靠 fillColor，通透背景下辨识度不足）正中**——有径是同一形态（选中只换 `primary` vs `icon`），所以这条对我们同样成立。已知两个必躲的坑：`componentUtils.getRectangleById` 对 TabBar 子树 y 偏低 88px（实测槽位 y=2439、接口回 2527），要用 `onAreaChange` 窗口坐标并与 `.position()` 同源；胶囊里那份不能用 `@Builder` 传参（值快照不刷，要靠 key 随 `dockPillCovered` 的 `ForEach` 强制重建）。另：真磨砂必然糊掉下层官方图标，**胶囊内复制一份内容是必需品不是美化**；浅色档 Dock 已到 251/上限 255，体积只能靠反向压暗做（§7.6.27 结论 3）；真机核对：容器 106.2×78.4vp 与公式 0 差、中心 x/y 各差 0.5px/1px、副本对官方残差 dx=1px dy=4px（有据同源残差，我试的第三种算法反而错到 88px 已退回）；连点「我的↔规划」切页正常（命中没被吃）；**五格逐位**（续 203）：dock 板 `[55,2427][1081,2602]`，五格胶囊中心减槽中心**同为 +0.5px**、胶囊内副本五格分别落「地图/行程/规划/费用/我的」；**已知边界**：首末两格胶囊溢出 dock 板 33px（=10.6vp，出自 `pitch×1.22` 公式本身，有据同值，未擅自收窄以免五格宽度不齐）；**浅色档已量**（续 203，App 级 setColorMode 探针）：画布 255 / dock 252 / 胶囊 249，表面差 **−0.026**，即浅色档胶囊比 dock **暗** 3 级——与有据 §7.6.27「白面到 251 无向上余量、体积只能反向压暗」同型，深色档则相反为提亮。剩观感与按压缩放两项（md 档已量：胶囊跟位 +0.5/+1.0px、玻璃本体 130.9vp 不探出 560vp 板，§5ci 续 208） |
| 15 | 一镜到底转场（`customNavContentTransition` + `componentSnapshot`） | **零实现** | **未开始** | 属转场体系不是布局骨架；要不要做是产品取舍，没替用户拍 |
| 16 | 胶囊盖住的官方页签整份隐掉（`opacity(dockPillCovered===i ? 0 : 1)`） | `pages/Index.tabLabel` 已补 gate | **已修并真机复拍**（sm 档） | 有据 `Index.ets:1499-1505` 原话"留着它只会在玻璃下面糊出一团同色光晕"；有径此前全仓 0 处该 gate ⇒ 选中格三层同色叠印。这是续 202 请用户判观感时**没交代的已知缺陷**，先修再判（§5ci 续 206）。**手机档已验（续 220）**：浅色档 sm 上被盖那颗外层 Column 读 `opacity=0.000000`（`[533,2439][602,2590]`），实拍玻璃下无第二份图标。**md 档也已验**：被盖那颗的外层 Column 在 dump 里读 `opacity=0.000000` 且随选中迁移（规划格 `[1070,2165][1139,2316]`、我的格 `[1740,2165][1809,2316]`），两颗文字节点自身仍是 1——gate 挂外层才是正确形状（§5ci 续 208）；手机档实拍仍待设备空出 |
| 17 | 系统栏六字段（含 `isNavigationBarLightIcon` + 两条 `*ContentColor`） | `utils/TopStrip` 已补齐 | **已修 + 模拟器对照量过（手机档待实拍）** | 有据 `EntryAbility.ets:135/149-155` + 两条实证注释：审核问题④「不设内容色 ⇒ 应用主题≠系统深浅时浅底白字，对比度 1.1<3」；2026-10-25「`statusBarContentColor` 只染文字，图标仍按系统渲白，故开关与内容色两处同设」。有径此前只给 3 字段（§5ci 续 206）。**原始触发条件已对照量过**（§5ci 续 209）：模拟器系统档浅色 + App 级 `darkprobe` 钉深色 ⇒ 带子中位 18 与画布同值（系统栏透明生效）、带子最亮 2% 均值 **253**（时间与信号/电量图标全近白压深底）；`lightprobe` 下最暗 2% 均值 **50**（深字压浅底）。改前只设图标开关不给内容色，这一档文字会跟系统浅色走，就是那个 1.1:1。手机档实拍仍待设备空出 |
| 18 | 页签左右滑动切页 `.scrollable(true)` | `.scrollable(true)` + 胶囊起飞迁 `onAnimationStart` | **已落地并真机验通主路径** | 有据 `Index.ets:2020` 明确开放。**我上一轮推荐的「按格开」（方案 c）被自己推翻**：`Tabs.scrollable` 是整条 bar 的全局开关，按格开会造成"能从规划滑走、却滑不回来"的不对称导航。改为照有据打开（b），并把胶囊起飞从 `onChange` 迁到 `onAnimationStart`（有据 `:2021`：onChange 落定后才发、玻璃晚半拍）。真机（续 221）：规划→左滑=费用 ✓、费用→右滑=规划 ✓，费用摘要卡上左滑=我的 ✓（Tabs 正常吃手势）。**未验的一格**：`ExpensePage.ets:901` 收据行 `.swipeAction` 与 Tabs 的仲裁——该行程无任何收据故无样本；最坏后果是"删除入口滑不出来"而非误删，回退=一处开关 |
| 19 | 顶栏栏级沉浸材质 `systemMaterialEffect {101,0}` | `design/HdsChrome.ets` **0 处**栏级材质 | **已挂起（与第 20 行是同一个改动）** | 真机取证（§5ci 续 222）：地图格顶栏条带 y100–260 全 255（`map_strip_base` 纯白带），底图从 y=300 才开始 ⇒ **栏体下面从来没有内容**，没穿底就没有可折射对象，材质上去是白压白；而穿底会请回第 8 行证伪过的顶边硬台阶。要在真机同时验"折射出没出"与"顶边有没有台阶"，配方与判据在任务 #31 |
| 20 | 穿底采样链（子页 `enableComponentSafeArea:false` + `clip(false)` + `bindToScrollable`） | 恒 `true`；`clip(false)` 只在胶囊层；`bindToScrollable` 0 命中 | **与第 8 条撞车，未做** | 有据 7 个子页 false。这正是任务 #26 的前提，也是续 198 证伪的那块顶边几何 |
| 21 | 回弹边缘效果 `EdgeEffect.Spring {alwaysEnabled:true}` | 14 处全部带（13 处续 207 补齐） | **代码已对齐，手感待复拍** | 有据 43 处 Spring、**40 处带 alwaysEnabled**（实测计数）；有径此前 14 处只 1 处带。后果：内容不满一屏时有据有橡皮筋、有径拉不动（读起来像卡死）。滚动行为尺 `tools/audit_scroll_actions.py` 扩第二条钉住"裸 Spring 即偏差"，probe 加三组控制样本，先跑红抓到 13 处、改完全绿（§5ci 续 207） |
| 22 | 贴底控件第二避让通道 `bottomBarInsetVp` | 发布该键、**0 消费方** | **暂时无落点** | 有据由 `DetailActionBar`/`ChatView` 消费（手势档也留 16vp、键盘聚焦归零）。有径没有常驻贴底输入栏，钉底条全走 `floatingDockClearance`；等有评论/输入栏那屏再按有据接。另：`floatingDockClearance` 的按档派生（26 处）已决定**不做**，理由见 §5ci 续 223（只在三键档咬人、用户是手势档、换来的是每屏 −4vp 的批量摆动） |
| 23 | 页签格尺寸档（图标 24 / 图文距 3 / 槽盒 64×54） | 图标 `IconSizes.control`=22、`SpaceTokens.xxs`=4、无槽盒 | **不改（先动契约）** | 差 2vp/1vp，且会连带胶囊副本按 `pitch×1.22` 反算的位置。有径的 22 来自自身 token 契约，改它要先改契约，不值当在没眼睛时做 |
| 24 | 按钮标签字档 = `callout` 14（`DesignButton.ets:91`） | 现为 `body` 16（`YoujingButton.ets:54`） | **已裁决：保留 16（有意偏离有据）** | DESIGN.md:922 把 buttons 归 `body`；:809 按「16px semibold 不算 WCAG 大字」论证过实心主钮对比度。改 14 是全 App 尺度摆动且那段论证要重算（§5ci 续 222） |
| 25 | 选中胶囊表面 = 实心 `brandSolid` + 白字（`ChipRow.ets:80`） | `primaryTint` + `ink` + 1px `primary` 描边（`TripInputPage.ets:561`） | **已裁决：保留 tint+描边（有意偏离有据）** | 有径契约只有一套选中语义（`option-chip`），城市胶囊与四题选项卡共用；改实心要么把选项卡也染成整块蓝、要么把契约拆两套。有据无"整卡选中"对照件（§5ci 续 222） |
| 26 | 胶囊高度 = `segmentedHeight` 36（`ChipRow.ets:23`） | `minTouchTarget` 44（`TripInputPage.ets:557`） | **已裁决：保留 44（有意偏离有据）** | 「Min touch target 44×44」是硬线，收到 36 破命中区（§5ci 续 222） |
| 27 | 空态：图形 44 + 标题 `headline` 18 serif，件被 12 个文件消费 | 图形 48 + 标题 `title` 21 serif，`EmptyState(` 消费方 0 | **档位已裁决：保留 48/21；接线待做** | 有径图形档封闭为 22/48，44 是命中盒不是图形档；件与 TripsPage 内联同规格，接线对那屏像素中性，其余屏逐屏量（§5ci 续 222） |
| 28 | 通用卡内缩钉 16（`BaseCard.ets:12`；它自己的 `CARD_PADDING` 0 消费、`PublishSection.ets:23` 又覆盖成 12） | **有径内部不一致**：同一 `RadiusTokens.card`(20) 配 `sm`=12 共 26 处、配 `base`=16 共 18 处 | **已收口**（22 处改到 16、尺归 0；手机档行程屏实拍 16.0×2，续 220） | 与「跟不跟有据」无关，是有径自己同一种卡两屏跳 4vp；批量收口属「改完必须逐屏量 bounds 反证」类（§5ci 续 212） |
| 29 | 吸顶组头底板（`PublishTagPanel.ets:83-86` 定高 36 + `elevated` 实底板） | 逐处读 builder 本体后定案：`OnTripPage`/`BadgePage`/`ItineraryPage:800` 有 canvas 底板；**`SpotPickPage:238-247` 与 `AreaMorePage:94-101` 是裸 Text 无底板** | **已修（滚动实拍待做）** | 无底板时吸顶行文字与滚过来的行叠成两行；两处各加 `.backgroundColor(ColorTokens.canvas)`（跟本仓三处一致，不抄有据的 `elevated`）。另拦下我自己顺手加的横向内缩——这两页 List 已带 `left/right: base`，再加就是 32vp 新错位（§5ci 续 218） |


**读法**：1–7、9、10、11 已按有据落地（10 有 A/B 复拍；11 的「不跟」原判已在续 205 推翻并补齐，
手机档逐像素对齐，md 档待量）；8 是平台限制不是偷懒（有对照读数）；
12 经实测**判为不跟**（有径 API 26 上那道门是死代码）；
还剩两格都要真人眼睛：**13 顶栏跟手收起**（前提是穿底，正撞第 8 条）、
**14 dock 液态选中胶囊**（五格逐位 + 浅色档已量，剩鼓包/spring 落定的观感、按压缩放手感与 md 档宽度）。
所以「按有据的界面结构和布局体系来」这条目标**尚未全部达成**，本表就是它的剩余清单。

**2026-11-06 续 206 之后**：`barWidth` 那条（第 11 行）被判错教会我一件事——这张表原来是
按"我记得问过的维度"建的，不是按有据的实际配置面建的。所以做了一次源码级整表重扫，
新增 **16–23 共 8 行**（续 212 又加 24–29 共 6 行）：16/17 当场确认是我的缺陷并已修（都还没装机复拍，设备被真人占用）；
18 是交互决定，留给用户；19/20/21 只能靠像素或手感判，不盲改；22 当前没有落点；
23 要先动契约。**这张表现在 29 行。代码面仍未收口的是 9 行**（4、13、15、18、19、20、24、25、26、27 里去掉已修的 16/17/21/28/29 之后）：其中 4/13/14 要真人眼睛，15/18/24/25 要用户裁决，19/20 要像素判据；**另有 5 行代码已就位、只差复拍**（16、17、21、28、29），全部并进任务 #30 那一次设备会话
（4、13、15、16、17、18、19、20、21）——目标完成度按这张表算，不按提交数算。
