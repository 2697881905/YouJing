# INIT_REPORT.md · 有径工程初始化报告（P1–P7）

> 生成日期：2026-10-15。初始化流程 P0–P7 全部完成，验收清单见第 2 节，遗留事项见第 4 节。


## 4d. 字段落点复核（2026-10-25，脚本扫 + 人工分类）

`model/*.ets` 的 12 个接口共 131 个字段，用 `\.字段名` 在 `pages/` `components/` `widget/` 里找读方，
31 个一次都没被 UI 读过。按消费层分类（注意：`.field` 也会匹配到**写值**的 DAO/解析器，
所以"非 UI 有引用"不等于"有消费方"，逐条人工看过）：

| 类别 | 字段 | 结论 |
|---|---|---|
| AI 产出、界面不显示 | `TripOverview.summary` / `.highlights`、`TripDay.risk` / `.accommodation` / `.intensity` / `.dailyCost` | 已在任务 #29 等用户定点，不自己加卡 |
| 全库零引用 | `PlanParams.tagAffinity?`；`CheckinMark` 接口本身（DAO 走 `ValuesBucket` + `Record<id,ms>`，从不构造它） | 属阶段 1 冻结契约的表面；删或补用途由用户定（P0「决策不抢跑」） |
| prompt/种子层在用 | `Spot.nearbySpotIds`、`Area.source` / `.updatedAt`、`DataProvenance.*`、`Expense.activityId`、`CheckinMark.activityId`、`SelectedSpot.userNote`、`AccountState.loginAt` | 合理：它们服务于提示词、幂等或分区，不是给用户看的 |
| 景点库字段，界面一个没露 | `Spot.brief` / `.entranceTip` / `.nearestMetro` / `.provenance`、`SpotBooking.releaseTime` / `.closedDay` / `.difficulty`、`Area.description` / `.commerceTags` / `.priceRange` | 与 §4b-4 同一件事：底稿要显示这些就得先把它们带进 Activity/AI 契约，否则屏8/屏10 只能显示模型里真有的字段 |
| 特别提醒 | `SpotBooking.advanceDays` | 日历提醒一律提前 1440 分钟。`CalendarSync` 头注释已写明原因：`Activity` 不带 `booking`（AI 契约里没有），要按景点各自要求提前，得先扩阶段 1 契约 → 与 #29 同族，等用户定 |

**不是缺陷的一条**：`checkin.checked_at` 确实落库、`CheckinDao.listForTrip` 也返回时刻，
但屏15 只用「这个节点有没有卡」，已打卡列表显示的是**计划时间**（帧 7fc140cd 也是这么画的），
所以界面没有承诺过"显示打卡时刻"。


## 4l. #21 收口：⑥ 根页内联落地、④ 随之消失、⑤ 两档 dock 量完（2026-10-26，真机）

分支 `wip/hds-tabs-initial-index` @ `45923da`。

**⑥ 已修（结构）**：`MapPage`/`ExpensePage`/`TripsPage` 各加 `rootMode`，根页模式下本页自带
`HdsNavigation(this.pathStack){ rootShell() }.titleBar(同一份 spec).navDestination(routerMap)`，
正文抽成 `@Builder rootShell()` 两支共用；被别的页 push 时仍走原 `HdsNavDestination` 分支。
`Index` 的三个 `TabContent` 直接放页面件，`TabRootHost` 与 `PENDING_ROUTE_KEY/PENDING_PARAM_KEY` 整套删除。

改之前先把 ⑥ 的代价估错了两处，都纠正在这里：
1. 以为要把三页的标题栏状态提到 `Index` 用 `@Link` 共享——其实
   `HdsNavigationAttribute.titleBar` 与 `HdsNavDestinationAttribute.titleBar` 收同一个
   `HdsNavigationTitleBarOptions`，`HdsChrome.bar()` 本来就返回它，原地换挂载点即可。
2. 以为 `routerMap` 留在 `Index` 会成环——`AppRouter ↔ 页面` 的循环 import **实测能编过**
   （`routerMap` 是提升的函数声明）。
另外排除过一条"小修法"：SDK 里 `hideBackButton`/`backButtonIcon` 只有栏级、NavDestination 没有
逐页返回件开关，`hideBackButton(true)` 会把「我的」栈里 Itinerary/OnTrip 的返回件一起削掉，不能用。

**④ 已修（随 ⑥ 消失）**：上一轮装的 debug 探针真机读出标题是「未识别路由 **[]**」——
`routerMap` 收到的是**空名**，不是 'Expense'。根因就是宿主在自己的 `Navigation` 绑上栈之前 push。
那条 pending-push 路整条删掉之后，冷启 `--ps route Expense` 直接落到费用页
（`/tmp/docktabs-run4.log`，同轮 hypium **81/81**，四页签点切与各 tab 正文照旧真数据）。
`Back` 在根页也不再弹成空白 tab——根页不在栈上，实测退到后台的有据，是根页应有的行为。

**⑤ 两档 dock 视觉量完**（按 dump 里 bar 容器真实 bounds `Stack[55,2340][1080,2515]` 取样，
不再用固定扫描行——那会打到页面内容）：

| 档 | 板体实测（10112 点众数） | 未选标签 `muted` | 选中标签 `primary` |
|---|---|---|---|
| 深色 | `#202022` | 5.60:1 过 | **4.46:1 差 AA 0.04** |
| 浅色 | `#FAFBFD`（近白微冷，官方板**有画**） | 5.10:1 过 | 5.20:1 过 |

浅色档是靠临时 `setColorMode(LIGHT)` 钉出来的（只钉本 App，不动系统设置），量完已还原：
`grep TEMP` = 0，工作树与 `45923da` 无差异，产物重装过。

**深色那一格要单独说**：按 token 底 `surface_elevated #1E1E1E` 算是 4.57:1（§4i 就是这个数），
但官方 `HdsTabs` 的板实测比 token 亮 2 级，落到 `#202022` 就只剩 4.46:1。
也就是说**换官方 dock 之后，选中态蓝的余量被板的实际色吃掉了**。
这正是 §4i 留给用户的那条决定（`#2E96FF` 5.50:1 / `#4DA6FF` 6.52:1），
现在多了一条实测依据：不是"要不要加余量"，而是"官方板比 token 板亮，选中蓝贴线"。
代拍不改色——深色选中蓝是深色帧自己写的 `#0A84FF`，改它属动设计定稿。


## 4k. #21 真机六项验收：四项过、一项失败未归因、一项把推断升成实测（2026-10-26，中途设备被真人取走）

一轮 `tools/verify_dock_tabs.sh` 跑完，证据在 `/tmp/docktabs-run2.log` 与 `/tmp/docktabs-run2/`。

| 项 | 结果 | 证据（dump 文字） |
|---|---|---|
| ① 四页签点切 | **通过** | 地图→「北京 · 3天2晚 / 09:00–13:00 故宫博物院 / 13:15–18:15 八达岭长城 / 18:30–22:30 颐和园」；费用→「预算 ¥16000 · 各天预估合计 ¥1540 · 2 人 · 3 天 / ¥0 已花 / 记一笔」；我的→「我的行程 / 8 景点 / 5 段通勤 / ¥1540 / 已生成」；行程→启动页 |
| ② 费用 tab 根页 | **通过** | 根页由 `TabRootHost` 自推成功，顺带证明冷启 ACTIVE_TRIP 种子在真机是通的（含 §4j 那条分区修复） |
| ③ 冷启 route=Itinerary / TripInput | **通过** | 屏8「Day 1 · 07月01日 / 需预约 / 为什么排在这里」；屏2「目的地 北京 / 10月26日 – 10月28日 / 2 位成人 / ¥8000 / 人 / 开始规划」 |
| ④ 二次深链同一个 tab | **失败，未归因** | 冷启 `--ps route Expense` 落在 ComingSoonPage（「这个页面 / 还在准备中，稍后回来试试」），而 `'Expense'` 明明在 `routerMap` 里 |
| ⑤ 深浅两档 dock 视觉 | **未验** | 固定扫描行的探针会打到页面内容（费用页 y=2540 是 `#0C0C0C`、地图页是 `#212121`），改按节点 bounds 采样时设备已在深色档；浅色档要临时钉色档，没做 |
| ⑥ 弹栈边界 | **确认是缺陷** | 「我的」tab 按 Back 之后 dump 只剩「行程 \| 地图 \| 费用 \| 我的」+ 状态栏，正文空 |
| ⑦ hypium 回归 | **81/81 通过** | `Tests run: 81, Failure: 0, Error: 0, Pass: 81` |

**⑥ 把 §4j 那条从推断升成实测**：tab 根页走 `pushPath` 的代价是真的——返回手势弹掉栈底就只剩一条 dock。
有据的路线 B（根页内联在 `TabContent`）因此不是风格洁癖，是这条缺陷的正解。

**④ 归因停在门口**：给 `routerMap` 的 else 分支加日志被编译器判死
（10905204 `'Logger.warn(...)' does not meet UI component syntax` —— **@Builder 体内不许写普通语句**），
改成把没认出来的路由名直接画进 ComingSoonPage 标题再 dump 读；探针包刚装好，
前台已经变成有据在被人翻（同一页面两次观测自己从「圈子」变成「首页 / 加载失败, 请求失败, 重试」）。
按「撞真人用手机就立刻停手」停在这里，探针已还原。

**顺带证明脚本的守卫有效**：第一次跑就是在 tap 之后撞上真人取手机，
`assert_front` 在下一跳前读到 dock 标签 0/3 直接中止整跑，没有把点击打进别人的 App。

**分支判定：不可合入。** main 仍是单栈 + 自绘 dock 的可用状态。
分支上挂着三条待办：④ 归因（探针思路已留）、⑤ 浅色档 dock、⑥ 根页内联
（要动三个页面的标题栏状态归属，是有径对齐有据路线 B 的最后一段）。


## 4j. #21 分支静态审查：修掉三处，留一条结构性缺口（2026-10-26，无设备）

真机被占，先跑不依赖设备的一遍。`assembleHap` BUILD SUCCESSFUL，七把静态尺
（色 / 字 / 几何 / 材质 / 字族 / tnum / 投影）在 `wip/hds-tabs-initial-index` 上全部 0 偏差；
产物按 `UP-TO-DATE` 那条老坑核过——`ets/modules.abc` 里查到新符号
`routeOwnTab` / `onPendingChange` / `onActiveTripChange`，确认这次 4.9s 的增量构建真编进去了。

审查四栈骨架本身，翻出三处代码可见的缺陷，都已改在 `pages/Index.ets`：

| # | 症状 | 根因 | 改法 |
|---|---|---|---|
| 1 | 同一个 tab 的第二次深链静默丢失，只有该 tab 首次被建出来时生效 | 待路由只在 `TabRootHost.aboutToAppear` 里读一次，而 `TabContent` 建完后一直活着，不再有第二次 `aboutToAppear` | `PENDING_ROUTE_KEY` 挂 `@StorageProp` + `@Watch`，消费逻辑收进 `routeOwnTab()`，首帧与后续变更走同一条路 |
| 2 | 「还没有可选行程」占位会永久钉在屏上 | `build()` 里直读 `AppStorage.get(...)` 不建依赖；活跃行程是异步种下的，首帧读到空值后再没人重算 | `ACTIVE_TRIP_KEY` 同样挂成 `@StorageProp` + `@Watch`，行程一落定就补推根页 |
| 3 | 冷启种下的活跃行程可能取错分区 | `Index.aboutToAppear` 跑在 `EntryAbility.bootstrap` 的 `await AccountStore.init()` **之前**，而 `TripDao` 一律按 `AccountStore.uid()` 收口（`AccountStore` 头注释第 7 行就是这条铁律）→ 拿游客键种出的行程 id，到真账号分区里查不到 | 种子改成 `AccountStore.init(ctx).then(() => TripDao.listSummaries(ctx))` |

**没改、留给真机判的一条（结构性）**：地图 / 费用 / 我的三个 tab 的根页是 `pushPath` 上去的
`HdsNavDestination`，不是 `Navigation` 的内容区。后果是根页顶栏带官方返回钮、返回手势也成立，
而弹掉栈底那一条就露出 `TabRootHost` 的空占位——一个空白 tab。
有据的口径是「路线 B」：四个主 tab 的根页都作为内容区直接写在 `TabContent` 里
（`HarmonyProject1/pages/Index.ets:1335-1395`，`HomeTab` / `CircleTab` / `MessagePage` /
`HdsNavigation() { ProfilePage(...) }`），没有一个走栈。
有径要一致，得让 `MapPage` / `ExpensePage` / `TripsPage` 支持「根页模式」——
它们同时也被别的页 push，不能直接改成裸内容。这条既不在原五项验收里、
也必须真机看弹栈行为才判得准，先记不做。


## 4i. #28-⑩ 深色 dock 标签复测（2026-10-25，临时钉色档后还原）

上一轮我按对比度尺写下「深色未选标签 3.59:1，低于 AA」，并据此列了三个改色方案。
这次真机复测（临时 `setColorMode(DARK)` → 装机 → 截图 + `dumpLayout` → 还原）推翻它：

| 标签 | 色对（token） | 精算 | 像素实测 | 结论 |
|---|---|---|---|---|
| 未选（地图/费用/我的） | `muted #97979E` on dock 实底 `#1E1E1E` | **5.74:1** | 6.77:1 | 达标，且是四格里最好的 |
| 选中（行程） | `primary #0A84FF` on `#1E1E1E` | **4.57:1** | 3.91:1 | 达标但余量薄 |

dock 板底色实测灰阶 30 ≈ `#1E1E1E`，与 `surface_elevated` 深色值一致（深色下 dock 不走玻璃，
`glassOn && !isDark` 那条取舍生效）。

**上一轮那个 3.59:1 错了两处**：底色取错（量到的是 dock 之外的区域），归因也错
（被说成"未选标签"，其实未选标签是最达标的，接近阈值的是**选中**标签的蓝）。

**像素法在这里双向都不准**：未选像素比精算高 1.03、选中低 0.66 —— 10px 细笔画 + 本机
`snapshot_display` 只出 jpeg，色度噪声足以把 4.5 线附近的读数推 ±1.5。
所以这类判读以 `color.json` 精算为准，像素只用来发现"根本没画出来"。（同一坑第二次实证。）

**决定：不改色。** 选中标签的蓝是深色帧自己写的 `#0A84FF`，改它属动设计定稿；
4.57:1 已过线。若你要给选中态加余量，最小改动是 `#2E96FF`（5.50:1）或 `#4DA6FF`（6.52:1），
这条留给用户定，不代拍。

顺带记一条设备状态：复测后系统已自动切到深色（22 点后），App 跟随显示深色——
这是系统主题，不是遗留的钉死；`grep TEMP` = 0，`setColorMode` 已回 `NOT_SET`。


## 4g. #28 官方控件换型的逐条取舍（2026-10-25，用户授权「都要做」后代拍）

| 编号 | 议题 | 决定 | 依据 |
|---|---|---|---|
| ① | 屏11 分类行 → `ChipGroup` | **不换** | 官方 `@ohos.arkui.advanced.ChipGroup` 确实存在，但屏11 那一行是"分类图例 + 金额"，不是可多选筛选器；换成 ChipGroup 会把图例伪装成筛选态。现状已是官方 Button 胶囊 |
| ② | 屏2 城市选择 → `bindMenu`/`Select` | **不换，保留 `bindSheet`** | 面板里有 `Search` + 分组列表，`bindMenu` 装不下搜索框；`Select` 只支持单层选项，城市要按省份分组 |
| ③ | 屏4 优先级 → `bindMenu` | **已做**（提交见下） | 四档离散选择本就该摊开给用户看，原来的"点一下循环一档"看不见其余选项；顺带接上零消费方的 `getMenuImmersiveMaterial()`（载体 `MenuOptions.systemMaterial`，`ContextMenuOptions` 继承字段已核 SDK） |
| ⑤ | 屏3 步骤条 → `Progress` | **不换** | 五段离散点位用连续量 `Progress` 表达会丢"第几题"的信息；现状是官方 `Circle` 形状件 + tnum 文本 |
| ⑥ | 四处 27–33vp 胶囊命中区 | **接受现状，待真机手感** | `responseRegion` 已证扩不到组件边界外；再扩要动帧锁死的视觉高度。热区已在官方 Button 边界内（44vp 钮），风险是视觉胶囊本身小 |
| ⑦ | 屏3b 末题「生成行程」实跳屏4 | **已改口「选景点」** | 按钮做的是"去选景点"，生成在屏4 之后的屏6；底稿文案会让用户以为点完就出行程 |
| ⑧ | 图标档 12/14/18 与禁令 7 冲突 | **已闭环，禁令不必修订** | `audit_type.py` 现报图标字面量 0 处——那 7 处随控件换官方件消失了，`IconSizes` 仍只有 `control: 22` / `display: 48` 两档 |
| ⑨ | dock 光晕尺寸（帧自身不一致） | **取按格 68×56，不做 180×180 氛围大光** | 帧内两值冲突，按格档与四格 dock 的物理布局一致；大光属氛围层，加它会与"材质只四处"的克制原则打架 |
| ⑩ | 深色 dock 未选标签 3.59:1 | **暂不改色，需重测** | 精算 `#97979E` 对深色画布 `#121212` = **6.46:1**（对 dock 实底 `#1E1E1E` 也有 5.6:1），远高于 4.5——当初那个 3.59 是像素尺把底色取错了（大概率量到玻璃板/壁纸亮区）。改色前要先在深色真机重测一次，别拿错数据改对设计 |

③⑦ 两处已落代码；①②⑤⑥⑧⑨⑩ 是"决定不做/待重测"，理由如上，不再逐条回问。


## 4h. #29 六个 AI 字段的落点（2026-10-25，用户授权「都要做」后代拍）

真机 DB 实测这六个字段都是「AI 产出 → 校验 → 整份进 RDB，但界面一处不显示」。
落点选择的原则：**帧没声明的槽位不新造界面**，优先接进既有输出面（分享文本）
与既有格子（日标题右侧、费用页副标题）；`risk` 例外，见末行。

| 字段 | 落点 | 口径 |
|---|---|---|
| `overview.summary` | 屏16 分享文本首段第二行 | 空则不出行 |
| `overview.highlights` | 屏16 分享文本「亮点：A · B」 | 空数组不出行 |
| `day.intensity` | 屏8 日标题右侧（`主题 · 节奏`）+ 分享文本 Day 行 | 标签与屏3b 用户选项同一套词（轻松/标准/紧凑，`CategoryStyle.pace`）；认不出的值返空串不猜 |
| `day.dailyCost` | 分享文本 Day 行「预估 ¥N」+ 屏11 预算档副标题「各天预估合计 ¥X」 | 真机核过 `overview.total_cost` 恰等于各天 `daily_cost` 之和（1540 = 540+540+460）；它跟「人均总预算 × 人数」量的不是一回事，所以标签按口径写直，不叫"规划预估" |
| `day.accommodation` | 分享文本每天末行「当晚住 · X」 | 见 §4e-②；界面位置仍待用户定 |
| `day.risk` | 分享文本 Day 行下「⚠ X」+ 屏8 日标题右侧（有值才并进同一格） | 此前 **0/55 有值**——不是模型不写，是提示词从没要求过。补了第 10 条规则，并明确"没有风险就省略，不要为凑字段编造" |

用例 +2（六字段合成与 risk 有无两态），真机 **81/81**。


## 4f. 近四个提交的回归状态（2026-10-25，含一条被设备挡住的验证）

`2cacbd5`（材质尺+吸顶）之后又落了 4 个提交：`47e695e` 字族尺与三处 serif 槽、
`3517ed9` tnum 尺与三处数字表面、`85218cb` 卡片衬线的编译器原文、`ff0d5b8` 尺子白名单更正。
**真机 hypium 回归（79 例）目前只跑到 `2cacbd5` 那一次**，这 4 个提交没有设备级用例证据：

| 已验 | 未验（及原因） |
|---|---|
| 每个提交都过 pre-commit 构建闸（hvigor assembleHap debug）；七把静态尺在 HEAD 全部 exit 0；`47e695e` 的三处衬线改动有真机截图目视证据（屏15「颐和园」、屏10「故宫博物院」裁图已是宋体）；`85218cb` 有编译器报错原文 | ~~`3517ed9` 之后的 4 个提交未重跑 79 例~~ **已于 2026-10-25 20:11 补验闭合**：设备解锁后在当前 HEAD `11d9dc6` 重新构建 ohosTest 包（产物 20:11:45）、装机、跑 `aa test`，结果 `Tests run: 79, Failure: 0, Error: 0, Pass: 79, Ignore: 0`；主包 `assembleHap debug` 同批复跑 BUILD SUCCESSFUL |

补验过程记录：锁屏期间共尝试 6 次，全部 `10106102 The device screen is locked during the application launch, unlock screen failed`
（developer mode 不能自动解锁），期间**没有**代输密码、改设置或唤醒屏幕去绕开；
一次把锁屏时钟组件（截图均亮 104）误读成桌面，据 `dumpLayout` 的可见文本（日期 + 通知 + 运营商）当场纠正。

解锁后一条命令即可补验：
`hdc shell "aa test -b com.youjing.app -m entry_test -s unittest OpenHarmonyTestRunner"`
（本轮这 4 个提交只碰 UI 属性与 tools/文档，未动 `utils/`、`model/`、`data/` 里被用例覆盖的纯逻辑，
所以用例预期仍绿——但**预期不等于证据**，跑过之前这条就挂着。）


## 4e. 显示完整性复核（2026-10-25，真机 DB 取证，非脚本推断）

§4d 问的是"字段有没有被 UI 读过"，本轮把问题反过来问一次：**屏8 时间线行与屏10 节点详情这两张表面，
有没有哪个字段在真数据里明明有值、却因为渲染路径到不了而永远不上屏**。
取证方式：`hdc file recv` 把设备上的 `youjing.db` + `-wal` + `-shm` 一起拉下来（只 attach .db 会漏掉 WAL
里的新行），对 19 个测试行程的 **96 条 activity / 55 条 trip_day / 110 条 meal** 逐列统计填充率。

| 结论 | 证据 | 处理 |
|---|---|---|
| 原假设「悬空分隔符」不成立，不改代码 | `TripParser.reqStr()` 对空串直接抛 `TYPE_GUARD_FAILED`，而 DB 里 59 条有通勤的 activity 中 `transport_mode`/`transport_detail` 空值 **0 条**，`address`/`location` 空值 **0 条** | 不给到不了的场景加兜底；`transitLeg()` 那行未门控的 `· ${detail}` 保持原样 |
| `Activity.location` 是**零信息量字段**：96/96 行里它要么等于 `address`（82 行）要么等于 `title`（14 行），没有一行带独立信息 | `select sum(location=address), sum(location=title), count(*) from activity` → `82 \| 14 \| 96`；`where location<>address and location<>title` 返回 **0 行** | 帧 屏10 的地址槽写的是「京都市伏見区深芝藪町 68 · 山脚入口」＝ `address · 入口别称` 两段。现契约填不出第二段：提示词从没定义过 `location` 的语义，模型就照抄。要填只能扩 prompt（`location` 改指入口/点位别称），属阶段 1 契约改动，**等用户定**，不在显示层硬凑 |
| `TripDay.accommodation` 55/55 全有值，但**全 App 没有一个消费方** | 填充率 55/55；`grep accommodation` 在 `ets/` 里只命中 `LlmClient.ets:138`（写入处）与数据层，界面/日历/卡片都不读 | 屏15 选的住宿区域在 App 内不显示，而 13 帧里"住宿"只作为**费用分类名**出现（屏11/屏13），没有任何一帧声明「今晚住 X」这一行 → 加行属新设计，进 §4b 待确认清单，不自作主张 |
| `Meal` 有名字有价格（110/110 `estimated_cost>0`），屏15 帧却声明了一行 `07:40 早餐 ¥900 已打卡` | 帧文本抽出来是「07:40 / 早餐 / ¥900 / 已打卡」；`Meal` 只有 `type/name/location/note/estimatedCost`，**没有 `time`、没有 `id`** | 无 `time` 就没法和 activity 同列排序，无 `id` 就进不了 `checkin(trip_id, activity_id)` 那张表。要落实这行得同时扩两处契约 → 与 #29 同族，等用户定；本轮不拿 `type` 猜时刻、也不造合成主键 |
| `TripDay.risk` 0/55、`Meal.note` 0/110 填充 → 界面不显示它们是**对的** | 同上两条 SQL | 不动。提示词没要求模型产这两项，显示层挂了也只会永远空 |

一句话口径：这两张表面**没有"有值却没上屏"的渲染缺陷**；真正的缺口全在契约侧——
`location` 语义未定义、`accommodation` 无落点、`Meal` 缺 `time`/`id`。三条都要动阶段 1 冻结契约，等用户拍。


## 1. 完成清单

**目录骨架**（P1，`entry/src/main/ets/`）：pages / components / model / data / ai / mock / utils / design / common/{config, constants, error, logger}，职责与依赖方向见 `Docs/ARCHITECTURE.md`。

**文档**（Docs/）：
- `ARCHITECTURE.md`：目录职责表、依赖方向规则、与开发文档 §5.4 差异、命名与标识规范、UI 约定（P1/P4/P5）
- `TECH_STACK.md`：版本锁定表、依赖管理策略、变更记录区（P2）
- `CONTRIBUTING.md`：提交规范、分支策略、本地验收清单、hook 启用步骤（P6）
- 根 `CHANGELOG.md`：Keep a Changelog 结构，首条目「工程基线初始化」（P6）

**源码**：
- `common/constants/BuildConfig.ets`：IS_DEBUG / BUILD_MODE_NAME 单点定义（P3）
- `common/config/ApiConfig.ets`：BASE_URL / LLM_CHAT_ENDPOINT 占位（P3）
- `common/config/MockConfig.ets`：USE_MOCK_DATA 开关（P3）
- `common/logger/Logger.ets`：hilog 封装，YouJing. 前缀，debug 受 IS_DEBUG 门控（P4）
- `common/error/AppError.ets`、`common/error/ErrorCode.ets`：1xxx–4xxx 区段 14 码（P4）
- `entryability/EntryAbility.ets`：onError 接入 Logger.error（P4）
- `design/ColorTokens|SpaceTokens|FontTokens|MotionTokens.ets`：视觉常量单一事实源，数值为占位基线（P5）

**工程配置**：
- `.gitignore`：增补 .preview、签名/密钥文件（*.p7b/*.cer/*.p12/*.csr/*.jks/*.keystore）、.workbuddy/（P3）
- `code-linter.json5`：启用 no-explicit-any / no-unused-vars / explicit-function-return-type / no-console（P6）
- `.gitmessage.txt` 提交模板 + `.git/hooks/pre-commit` 零依赖门禁（console/any 扫描 + hvigor 编译检查），拦截演示通过（P6）
- git 仓库初始化（main 分支），P1–P7 共 9 笔提交全部符合 `type(scope): 中文摘要` 规范

**标准重建流程（固化）**：`pkill -f hvigor` → 删除 `.preview/` → `hvigorw clean` → `assembleHap`。后续凡增删页面或遇到诡异的 `@Entry decorator` 报错（hvigor daemon 缓存假错），先执行此流程再排查代码。构建命令需带 `DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk`。

## 2. 终验结果（P7 验收清单）

| 验收项 | 结果 |
|---|---|
| 全量构建（clean 后 assembleHap debug） | ✅ BUILD SUCCESSFUL，32/33 任务实跑，产物 `entry/build/default/outputs/default/entry-default-unsigned.hap` |
| 目录结构与 ARCHITECTURE.md 一致 | ✅ 11 个目录逐一对应 |
| 配置单点扫描（P3 复跑） | ✅ 业务目录 URL/IP 零命中；IS_DEBUG 全工程仅 BuildConfig.ets 一处定义 |
| token 裸值扫描（P5 复跑） | ✅ pages/components 裸色值零命中、fontSize/padding/margin/gap 裸数值零命中 |
| ErrorCode 码值无重复 | ✅ 14 码，重复 0 |
| TECH_STACK.md 与实际配置一致 | ✅ 逐项核对通过；`ohpm install --all` 后 lock 零 diff；运行时依赖为空 |
| git log 符合提交规范 | ✅ 不合规提交数 0 |

## 3. 工具链版本快照

见 `Docs/TECH_STACK.md` 版本锁定表（不在此重复罗列）。关键项：API 26 / DevEco Studio 26.0.0.851 / hvigor 6.26.8 / 内置 Node v24.14.1 / ohpm 26.0.0.630。

## 4. 已知限制与待办

1. **bundleName 已定稿** `com.youjing.app`（2026-10-15，参考有据 com.youju.app 命名）；AGC 应用已注册（2026-10-23，应用名「有径」，APP ID `6917619826312400726`，项目「有径」/ projectId `101653523865420226`），上架前需核对应用市场重名。
2. **调试签名已就绪**（2026-10-20 生成，2026-10-23 换 Profile）：证书与 p12 由 DevEco 自动签名生成（有效期 2026-10-20 → 2027-10-20）；Profile 含 4 台设备；Profile 改用 AGC 手动创建的 `youjing-debug-20261023` —— 自动签名生成的 Profile 带随机 `app-identifier`（`6918745435470575450`），Account Kit 报 `1001502003`；手动 Profile 的 `app-identifier` 才是 APP ID。Profile 内嵌证书与本机 `.cer` 同一张，`hdc install -r` 签名一致，登录态与行程数据跨重启保留。签名材料仅存本机 `~/.ohos/config/`，signingConfigs 不入 git（build-profile.json5 已 skip-worktree）。Profile 有效期至 2027-10-20，到期需重签；release 签名上架前仍需单独申请。
3. **应用名称未定**：AppScope label 当前为 "YouJing"，中文名「有径」待品牌资源定稿后替换。
4. **API 26 最低兼容范围未评审**：compatibleSdkVersion=26.0.0 意味着不兼容更低版本设备，上架前需评审覆盖面。
5. **小艺 Skill 应用侧已落地（2026-10-23）**：走 API 26 的应用内 Skill——`module.json5` 的 `skillProfiles`
   注册 `youjing-plan-trip`，契约在 `entry/skills/youjing-plan-trip/SKILL.md`，入口为 `PlanTripSkill.ets`；
   启动日志实测 `Skill 注册 1 个: youjing-plan-trip`，HAP 内含 SKILL.md，Want 下游预填真机通过。
   平台侧新建 / 导入 Skill 需用户在小艺开放平台操作，步骤见 `Docs/小艺Skill接入清单.md`。
   `ApiConfig` 是 LLM HTTP 备选端点占位，与本 Skill 无关。
6. **日志输出已真机补验通过**（2026-10-20，本地模拟器）：四级 Logger 临时调用注入 → 签名 HAP 安装启动 → hilog 按 `YouJing.` 过滤抓到 D/I/W/E 全部四条（domain A00100），验毕临时代码已删除、还原版已重装。
7. **deveco_mcp 的 PROJECT_PATH 指向 HarmonyProject1**（旧工程）：MCP 的 build/check 工具对本工程无效，初始化期间一律以本地 hvigor 直跑替代；需在 MCP 配置中改指向本工程后方可使用。
8. **LSP 静态检查（check_ets_files）不可用**：20s 超时无诊断返回，静态检查以 hvigor CompileArkTS 为准。
9. **设计 tokens 数值为占位基线**：色值/间距/字号待用户 UI 设计定稿后替换（单点改 token 文件即可全工程生效）。
10. **ohosTest 进程拿不到合法模块 context**（2026-10-22 探针用例实测）：测试进程只挂 ApplicationContext，`relationalStore.getRdbStore` 报「Parameter error.Illegal context.」、`preferences.getPreferences` 报「The context is invalid.」，`application.createModuleContext()` 亦直接报「must be a context of stageMode」。因此 RDB 读写、迁移、账号分片持久化**不能**写成 hypium 用例，只能在真机 App 内以启动日志 + 界面走查验收；纯逻辑（Schema 守卫、Prompt、种子映射、登录态兜底）仍走 hypium。若后续要补 DB 单测，需在 ohosTest 侧加 TestAbility 并由 runner 启动后取 context。
10b. **阶段 10 两项按数据/凭据缺口暂缓（不编数）**：
    - **预算协同分析**：需要各住宿区域「价位段/晚」真值。种子库 `area` 只有 `priceTier`（经济/舒适/豪华）
      与 `price_range` 字段位，**未采集到价格数据**，故不生成任何金额结论；
      已把 `priceTier` 落到消费方（屏5 区域卡元信息行 + PromptBuilder 住宿区域行），
      等真实价位数据到位后只需补 `price_range` 灌入与一段换算。
    - **足迹地图**（2026-10-24 已落地，此项收口）：当初两条缺口都已补——
      ① AGC 开通地图服务并重出调试 Profile（新 p7b 的 `app-services-capabilities` 带
      `com.huawei.service.mapkit`，旧 p7b 该项为 null；证书与四台设备不变，只换 profile），
      `module.json5` 补 `ohos.permission.INTERNET`；
      ② 逐条经纬度：128 景点 + 144 片区由 Photon(OpenStreetMap) 按名称/锚定站名地理编码，
      WGS84→GCJ02 后写进 `seed/*.jsonl` 的 `la/lo`（271/272 成功，仅深圳「宝安青少年宫-滨海文化公园」
      没编出来，该行不落点）；`DataSeeder` 加种子版本闸门 `v2-geo-2`，已装机也会 upsert 回填。
      三处呈现已换成真底图并真机验收：屏5 候选三片（互斥、不连线）、屏8 当日面板（分段动线 + 全图入口）、
      dock「地图」全程页（Day 切换 + 站点条 + 点站点飞镜头）。详见 §4b-6/8。
10c. **玻璃点位①③按色彩模式分流（2026-10-23 双模式实测定案）**：
   顶栏与浮动 dock 接 `uiMaterial.ImmersiveMaterial`（顶部 ULTRA_THIN、底部 THIN，均带投影）。
   真机同页两模式对比：
   - **浅色**：dock 标签清晰，滚动内容被虚化成柔和色块，玻璃观感成立 → **采纳材质**；
   - **深色**：近黑底上模糊≈透明，「建议停留…」「步行 15分钟…」直接穿透压到
     「行程/地图/费用/我的」标签上，可读性明显变差，且 ULTRA_THIN/THIN/THICK 三档截图无可辨差异
     → **回退实色** `surfaceElevated` + 1px 描边（深色零阴影契约不变）。
   实现条件为 `glassOn && !isDark`；点位②分段控件与两处 Sheet 材质不受模式影响，一直走系统材质。
   点位④（吸顶日标题）底稿本就是无底文字行，未擅自加胶囊材质，待设计定。
11. **Account Kit 已接入**（2026-10-23 完成）：AGC 侧 APP ID / Client ID 均为 `6917619826312400726`，调试证书 SHA256 指纹 `86:6F:…:CF:70` 已登记，Client ID 与 APP ID 相同（无需 `client_id` metadata）；`AccountConfig.ACCOUNT_KIT_ENABLED=true`。真机验收：屏1 点击后 `LoginWithHuaweiID error_code=0`、`YouJing.Data.AccountStore: 静默登录成功 uid=AABKND***`，落到屏2；冷重启日志「恢复登录态 kind=huawei uid=AABKND***」。游客期数据归户走 `TripDao.adoptGuestData`（同一事务迁移 trip / expense / checkin 三表，
真机日志 `trip=6 expense=1 checkin=1`）；桌面卡片的独立进程在刷新前先 `AccountStore.init`
恢复 UnionID 分区，主应用在归户 / 生成 / 编辑后由 `WidgetSync.refreshAll` 主动回灌。
换签名时必须用 AGC 手动 Profile（见 #2）。
12. **`AceSheet: radius is not correct type` 是框架噪声，非本工程配置问题**（2026-10-23 归因实验）：
    真机每次开半模态都在 E 级日志打这一行，怀疑过是 `SheetOptions.systemMaterial` 传错。
    对照实验：屏2 城市面板是**不带** `systemMaterial` 的裸 `bindSheet`（只有 height/backgroundColor/showClose），
    `hilog -r` 清缓冲后单独打开它，同样报这一行（还伴随 I 级 `Bottom offset invalid`）。
    全工程没有任何一处给 bindSheet 传 `radius`，SDK `@ohos.arkui.uiMaterial.d.ts` 里也没有 radius 字段。
    结论：API 26 下 bindSheet 应用自身默认圆角时的框架内部报错，视觉结果（圆角与材质）真机截图均正常，
    后续走查**不要**再把它当缺陷查。

## 4b. 需要产品/设计确认的文案改动（agent 已按「能力对齐文案」原则改口）

1. 屏14「行程卡片」副文案：`每 15 分钟刷新` → `随系统周期刷新（最小 30 分钟）`。
   原因：`form_config.json` 的 `updateDuration` 最小粒度是 30 分钟，15 分钟做不到。
2. 屏16 主按钮与说明：`复制链接 / 链接 7 天内有效` → `分享行程文本 / 内容在本机生成，不上传服务器、不含账号信息`。
   原因：本项目纯 ArkTS 无后端，生成不了带有效期的分享链接；改为走系统分享面板发行程文本 + `.ics` 文件。
3. 屏15 底部说明：`打卡会同步到日历和卡片` → `打卡与记账只存本机，不上传服务器`。
   原因：打卡目前不回写日历事件、也不触发卡片即时刷新（卡片按系统周期刷新），原句是兑现不了的承诺。
4. 屏10 详情面板删掉底稿里的 mock 事实（山脚入口 / 开放时间全天 / 建议时段 06:30–08:00 / 红叶季拥挤 /
   上一站「一条」下一站「东福寺」/ 门票 ¥0），改为只显示模型里真有的字段，无数据即显示 `—`。
   若这些字段要保留，需要 Spot 库补营业时间、票价、拥挤提示三类数据，并在 Activity 上带 spotId。
5. 屏14「写入内容预览」第四行：`备注 行程第 N 天 · 步行到达` → `备注 <地点>[ · <排期理由>]`。
   原因：日历事件的 description 实际写的是 `location`（有 `reason` 时附在后面），原句既多写了没落库的
   「行程第 N 天」，又在当日首站（`transport` 为空）时把不存在的通勤说成「步行到达」。
   预览与真写入对齐后，同时修掉屏10 动线条首/末站的越界序号（前一格显 `0`、后一格显 `N+1`）。
6. dock「地图」落点页：`骨架占位 / 路由「Map」将在后续批次按设计底稿落地` →
   标题「地图视图」+ 一句说明（要接 Map Kit、需 AGC 开通并重新签名、动线现按时间线呈现）+「返回行程」按钮。
   原因：原句是工程内部话术（批次、路由名），却已经出现在装机可点到的路径上。
   **2026-10-24 更新**：这一格已经是真地图页（`pages/MapPage`），不再是说明页。
   底稿 39 帧里 dock 四项含「地图」但没有对应地图帧，用户授权按现有设计语言出 v1：
   满屏底图 + 顶部「全程 / Day N」芯片 + 右上「全览」+ 底部站点条（点站点飞镜头）+ 共用 dock；
   浮层用 `hitTestBehavior(Transparent)` 让手势穿到地图，dock 与屏8 同款材质/深色零阴影口径。
   没有 tripId 时 dock「地图」直接回「我的行程」，不给一张空底图。**待用户视觉验收**。
7. 屏5 区域卡三列：`步行 12分钟｜到首个景点` `34分钟｜日均通勤` `9 家｜舒适型房源` →
   `45分钟｜到机场` `12分钟｜到火车站` `高｜餐饮密度`。
   原因：底稿那三项要的是路径规划与住宿库存，本项目两者都没有（§7 明确不接第三方住宿服务），
   而代码里此前是按卡片序号现算的 `8 + i * 4` / `30 + i * 6` / `9 + i * 7`——用户看到的却是真数。
   新三列全部取 `Area` 真字段（`airportMinutes` / `trainStationMinutes` / `diningDensity`），版式不变。
8. 屏5 顶部地图卡：`动线地图 · Map Kit 批次接入` → 候选片区图例（三枚芯片 +「按推荐顺序排列」）。
   原因有二：原句把「批次」这种工程话术露到用户界面；更根本的是**画不出真位置**——
   `DataSeeder.toArea` 给所有片区填的是 `DistrictCoords.lookup(city, city)`，即同城 36 个片区共用
   同一个城市质心坐标（表里根本没有 `city:city` 键，四城全部落到兜底值深圳那一个点上），
   按经纬度布点等于编位置。所以这格只留 route-paper 底色 + 芯片，不暗示相对方位。
   同屏底部按钮 `帮我选（按通勤最短）` → `帮我选（推荐第一片）`：处理函数就是选 `picks[0]`，
   「通勤最短」是它没做的事。
   **2026-10-24 更新**：两条前置条件都已具备（逐片坐标 + 地图服务凭证），这格换成真实底图，
   三枚候选片按各自坐标落点；三片是互斥选项不是途经点，所以 `TripMapView({ route: false })` 不连线，
   只留一枚「本次候选的三片 · 按推荐顺序」浮层说明。坐标仍缺的行自动退回图例形态。
9. 屏5 区域卡副信息行 `maxLines` 1 → 2：加进「锚定 X站」后最长串实测 30 字
   （深圳 大鹏-较场尾「舒适档 · 地铁 E11接驳 · 锚定 大鹏中心(公交接驳)」），单行必截。
   当前四城首屏 12 张卡最长 26 字，两行内可完整放下，真机已无省略号。
10. 屏5 角标：`AI 精选 1` → `精选 1`；第二/三名的 `交通枢纽` 改成按 `Area.group` 取
    （core=核心地段 / commercial=商圈便利 / metro=交通枢纽）。
    原因有二：片区顺序来自种子库的编排顺序，模型没有参与区域排序（它只排景点），「AI 精选」是替模型认领了
    人做的事；旧写法是 `i === 0 ? … : (commercial ? 商圈便利 : 交通枢纽)`，于是北京「前门-大栅栏」、
    上海「外滩-十六铺」、深圳「香蜜湖-农园」这三片 `group=core` 全被贴成「交通枢纽」。
    真机复验：北京三片角标现为 精选 1 / 核心地段 / 商圈便利。
11. 桌面卡片 2×2 的标题与 footer 在真机上被系统省略号截断（`Day 1 · 10月…`、`还有 1 个需预约节点 · …`）。
    原因：底稿屏13 的 Widget A 在 360vp 机身框里画满了容器宽（328px），真机 2×2 格的文本区
    dumpLayout 实测只有 134vp（`[87,1152]–[507,1451]`）；实现已把标题降到 18（底稿 21），仍放不下
    `Day 1 · 10月23日`，footer 11 号也放不下 16 字。**已定（2026-10-23，用户选 a）**：
    接受系统省略号，完整信息回 App（点卡片直达屏8），不另做 2×2 收口文案。
    2×4 的 16 内缩已补上真尺寸通路（见 §6 卡片验收）。

12. 屏12b 空状态文案与帧不同，**未擅自改**（2026-10-24 逐帧对表时登记）：
   帧 7991fe5b 说明句「选一座城市，四道题就能拿到一份能直接走的行程」+ 主按钮「规划新行程」，
   实现是「从一座城市开始，让有径替你排好每天的路」+「创建新行程」。
   本轮只对齐了可度量的部分（逐段间距 16/8/24、说明限宽 240 形成双行、48 展示档图标），
   措辞属产品口径，等你定；定了之后一并复核 §4b 前 11 条。

13. 屏6 四段进度里的「估算步行耗时」**保留待确认**（2026-10-25 逐帧对表登记）：
    模型确实会按提示词规则 2 产出带 `mode/duration/detail` 的通勤腿，但 App 自身不算步行耗时
    （只有屏5「帮我选」用 haversine 算直线距离）。若你认为这一格应严格对应 App 的计算，
    改成「估算通勤耗时」更准。

## 4c. 阶段 2 验收：空 / 部分 / 异常 三态走查（2026-10-23 真机）

| 态 | 屏 | 结论 | 证据 |
|---|---|---|---|
| 空 | 屏11 费用 | 通过 | 无 tripId 直达：`预算 ¥0 · 0 人 · 0 天`，分类区与流水区各自显示引导文案 |
| 空 | 屏15 旅行中 | 通过 | 无 tripId 直达：`今日暂无安排` + `还没有打卡节点`，按钮不崩 |
| 空 | 屏16 分享 | 通过 | 无 tripId 直达：`行程未就绪`，统计三格为 0 |
| 空 | 屏12 行程列表 | 通过 | 临时把列表读取短路成 `[]`（不删任何用户数据）后真机见 `还没有行程` + 引导语 + `创建新行程`，验毕还原 |
| 部分数据 | 屏8 / 屏10 | 通过 | 活动缺 `transport` → 不画通勤腿、详情显 `—` 与「当日首站，无通勤」；缺 `note`/`reason` → 对应块整体不渲染 |
| 异常 | 屏7 生成受阻 | 通过 | 临时置 `USE_MOCK_DATA=false` 走 HTTP 分支真跑：日志 `生成失败 code=4004: 两次生成均失败: LLM 端点未配置（ApiConfig 占位）`，屏7 显示「试了两次都没排通」+ 该诊断，两条修法可跳转；验毕开关还原 true |
| 异常 | 生成前校验 | 通过 | hypium `guard_*` 系列 + `retry_exhausted` + `guard_end_time_not_later`（40/40） |

原始诊断文本只在 `BuildConfig.IS_DEBUG` 为真时露出，release 显示引导语，不把 `ApiConfig 占位` 这类技术文本甩给用户。

## 5. 发布前 checklist

- [ ] `BuildConfig.IS_DEBUG` 翻转为 false（手动，禁止 hvigor -p 透传）
- [ ] `MockConfig.USE_MOCK_DATA` 置为 false
- [ ] 网络配置（ApiConfig）变更后执行全量重编并重装 HAP
- [ ] 签名配置就绪（release 证书 + Profile）

## 6. 当前进度（开发文档 §6 十阶段）

阶段 1–10 全部落地并真机验收（屏1–16 + 种子库 + Schema 守卫 + RDB v1→v4 + LLM 离线闭环 +
多轮交互全流程 + 账号分区 + 日历真写入 + 卡片真数据 + 外部拉起参数通道 + 费用落库 + `.ics` 导出）。
hypium 40/40（2026-10-25 基线已升到 66/66，见 §7.3）；RDB/账号/日历路径按已知限制 #10 走真机验收。

**十阶段里没做的只剩三项，都不是代码缺口而是数据/凭证缺口：**

| 项 | 缺什么 | 需要谁动 |
|---|---|---|
| 预算协同（阶段10） | 种子库没有「区域真实价位区间」字段，任何分档差异都会是编造数字 | 产品定数据来源，或砍掉该功能 |
| ~~足迹地图（阶段10）~~ 已落地 2026-10-24 | AGC 地图服务已开通并重出调试 Profile；逐条经纬度已进种子库；屏5/屏8/dock 三处真机出图 | 仅剩用户对地图页 v1 的视觉验收（浅色模式未逐屏走查） |
| 小艺 Skill 平台侧（阶段9） | 应用侧已按 API 26 应用内 Skill 完成并真机验证（注册日志 + Want 下游）；平台侧新建 / 导入 Skill 仍需用户操作 | 见 `Docs/小艺Skill接入清单.md`，用户执行 |

另有两项待用户决策：§4b 前十处改口文案确认、点位④吸顶日标题是否给胶囊材质
（§4b-11 卡片 2×2 截断已定 (a) 接受省略号）。Account Kit 的 AGC 凭证已于 2026-10-23 配齐并真机验收。

**2026-10-23 今日改动后的全链路复跑**（真机，逐步截图 `f1_屏1`…`f7_屏8`）：
屏1 静默登录 → 屏2 开始规划 → 屏3 四步追问（末题 CTA 是「生成行程」，不是「下一题」）→
屏4 选点（`已选 0 / 可用 3.0 天 · 建议上限 12 个` 为真派生）→ 屏5 三片角标 精选 1/核心地段/商圈便利 →
屏6 生成 → 屏8 渲染 `北京 · 3天2晚` + Day 1 故宫/八达岭/颐和园 + dock 四标签。七段全 OK。
屏8/10/11/12/14/15 的 dock 与面板链见 §4b-6 与提交记录；hypium 40/40（当时基线）。

**2026-10-23 14:25–14:33 「有径 · 今日」卡片真机验收**（用户在桌面自行放置，formId `996982405`）：

| 项 | 证据 | 结论 |
|---|---|---|
| 真值渲染 | 桌面截图 + dumpLayout 文本节点：`有径 · 今日` / `Day 1 · 10月23日` / `09:00 故宫博物院` / `13:15 八达岭长城` / `18:30 颐和园` / `还有 1 个需预约节点 · 18:30 前` | 与屏8 北京行程 Day 1 三站一致 |
| 数据来源 | hilog `YouJing.Data.DatabaseHelper: RdbStore 就绪 v4` → `YouJing.Data.TripDao: 今日卡片 trip-1792723833719 Day 1 · 10月23日 还剩 1 站 · 共 3 站` → `YouJing.Widget.TodayTrip: 回灌卡片 996982405 2*2` | 卡片进程直读 RDB，不是缓存的占位数据 |
| 点击通路 | 点卡片 → `com.youjing.app/EntryAbility` FOREGROUND，落屏8 `Day 1 · 10月23日`；Back 回屏2，Home 回桌面 | `postCardAction` router + `tripId` 参数生效 |
| 重装自愈 | `hdc install -r` 后系统重拉 provider：`onAddForm 996982405 2*2` + 回灌，卡片内容不变 | 改版本不丢桌面卡片 |
| 尺寸通路 | 新增 `dimensionOf(want)` 读 `ohos.extra.param.key.form_dimension`，落 preferences `widget_form_dims`，每次回灌带 `dimension` | 2×4 的 16 内缩此前恒走 2×2 默认值（死分支）；2×2 已实测 `2*2`，2×4 桌面形态未实机放置，只有代码通路 |

`extension_running_timeout_monitor` 的 `duration: 14s, limit: 10s` 不是崩溃：provider 在 1s 内完成
`onAddForm` + `updateForm`（14:25:51），监控触发后走 `onStop`、进程 `exit with code:0`，
属系统对 form 扩展的空闲回收；下次刷新由新进程处理，与 `AceSheet radius` 一样归为框架噪声。

2×2 真机格宽 134vp 与底稿 328px 画布的差异导致标题/footer 截断；2026-10-23 用户定为 (a)
接受省略号、完整信息回 App（点卡片直达屏8）。

**2026-10-23 14:46–14:55 Account Kit 真机接通**：此前 `1001502003 Invalid clientId or profile`
的根因不是 Client ID，而是 DevEco 自动签名 Profile 的 `app-identifier` 为随机值
（`6918745435470575450`，≠ AGC APP ID）。在 AGC 新建调试 Profile `youjing-debug-20261023`
（应用「有径」/ 证书 `auto_debug_10086000824313557.cer` / 4 台设备），把下载的 `.p7b`
换入 `build-profile.json5` 后重建安装：`LoginWithHuaweiID error_code=0`，App 日志
「静默登录成功 uid=AABKND***」，屏1 → 屏2；冷重启后「恢复登录态 kind=huawei」。
新旧 Profile 内嵌的 development-certificate 完全相同（本机 `.cer` 指纹 `86:6F:…:CF:70`），
因此 `hdc install -r` 签名一致，无需卸载。下载的 Profile 存于 `~/.ohos/config/`
（用户指定位置），`~/Downloads` 的重复件已删。

**2026-10-23 15:00–15:20 小艺 Skill + 数据归户 + 卡片分区修复（真机）**：

- **Skill 契约**：`entry/skills/youjing-plan-trip/SKILL.md` 按官方 `ArktsSkillDevelopmentGuide` 样例重写——
  执行参数给出完整 `exec-cli` 命令对象 Schema（`command/skillName/scriptPath/functionName` 全 `const`），
  执行返回值给成功 / 参数非法 / 内部错误三组示例 + 带 `oneOf`/`required` 的完整 Schema；5 个 JSON 块本地解析全通过。
  重新构建后 HAP 含 `skills/youjing-plan-trip/SKILL.md`，启动日志 `Skill 注册 1 个: youjing-plan-trip`。
  设备无 `ohos-arkTSScript` 命令，Skill 函数本身只能等平台真机测试；下游用同一组 Want 参数验证：
  屏2 显示 `上海 / 8月1日–8月4日 / 4天3晚 / 3 位成人`。
- **归户补全**：`adoptGuestData` 在同一事务迁移 `trip` / `expense` / `checkin` 三表，
  真机日志 `游客数据归户 uid=AABKND*** trip=6 expense=1 checkin=1`。消费端复验：
  屏15 费用页显示「故宫门票 ¥320 / 已花 ¥320 / 分类 门票」，旅行中页显示「故宫博物院 已打卡」。
- **卡片分区修复（本轮新发现）**：桌面「有径 · 今日」在归户后仍显示「今天没有行程」。
  根因是 FormExtensionAbility 是独立进程，卡片刷新只走 `TripDao` 默认游客分区，读不到已归户到 UnionID 的数据。
  修复：provider 在 `refresh` 前 `AccountStore.init(this.context)` 从 preferences 恢复 UnionID；
  新增 `widget/TodayCard.ets` 共享卡片数据映射 + `WidgetSync.refreshAll`，主应用在归户 / 生成 / 编辑 /
  冷启动时主动回灌，卡片不用等 30 分钟定时。真机日志 `Widget.TodayCard: 已刷新卡片 996982405 2*2`，
  桌面截图显示 `Day 1 · 10月… / 09:00 故宫博物院 / 13:15 八达岭长城 / 18:30 颐和园 / 还有 1 个需预约节点…`
  （2×2 截断为用户已定的 (a) 接受省略号，见 §4b-11）。
- **主链复跑**：真账号（UnionID）下屏1 → 屏2 → 四步偏好 → 选 3 个景点 → 选王府井片区 → 生成 → 屏8；
  新行程在列表首条显示 `3 景点 / 2 段通勤 / ¥1140`。`BuildConfig.IS_DEBUG` 保持 true（debug 包）。

## 7. 2026-10-25 批次：健壮性与契约收口

> 详细清单见 `Docs/完成度评估与待办清单-2026-10-25.md`；验收证据见 `Docs/验收说明-2026-10-25.md`。

### 7.1 修了什么（按风险）

| 类别 | 条目 | 影响面 |
|---|---|---|
| 数据 | RDB 迁移改累积式（`oldVersion < N`），新增 v5 `spot.confidence` | 任意旧版本库可跨级升级；模拟器实测 `迁移完成 4 → 5` |
| 数据 | 种子解析补 5 个安全原语 + 枚举白名单 + 坏行跳过 | 缺键/脏值不再在首启 bootstrap 抛 TypeError |
| 数据 | `pickEnum` 修白名单回退（脏值写 undefined） | ohosTest `toArea_whitelist_fallback` 抓出并转绿 |
| 数据 | 打卡/记账删除补 `user_id` 分区；`todayPlan` 日期预筛 | 同机多账号越权、卡片刷新成本 |
| 数据 | `isValidIsoDate` 加真实日历回检 | `2026-02-30` 不再穿透草稿/深链/Skill |
| 功能 | 屏7 重试 `replacePath`、两按钮落点对齐；屏6 取消竞态；屏2 日期按今天；屏4 空态；预填城市如实回显；深链 null 参数；屏1 登录失败不阻断 | 用户可见 7 处 |
| 契约 | 选项 chip 回 tint 配方（minHeight 56）；日标题 serif；时间线行距 12；行高改 min；sheet 内材质删除；待定→warning；金额徽章中性；地图站点条去玻璃；dock 描边门控；分段控件接材质；卡片 surface-elevated + hairline；图标 7 处回档；chevron faint→muted；分组卡去分隔线；千分位去除；屏3 圆点进度；屏6 骨架镜像；屏9 拖动态改竖条 | 设计契约 18 处 |
| 纪律 | 入口层改走 Logger；删 4 件死代码 + 1 处死配置；ForEach key 稳定化；应用名/描述占位符替换 | 可维护性 |
| 测试 | 新增 MapStops/TodayCard/StyleConfig 三组，DataSeeder 扩到 8 组 | 66/66 通过 |

### 7.2 本轮决策登记（与文档有张力处，逐条给理由）

1. **选项 chip 回摆到 tint 配方**（推翻 2026-10-24「去自绘统一官方 EMPHASIZED」）：
   DESIGN.md §9 的 `primary-tint 底 + 1px primary 描边 + ink 字` 是实测结论（tint 底蓝字双端 sub-AA），
   且实心 chip 与同屏主按钮构成双实心蓝（禁令 1）。外壳仍用官方 Button，只换颜色 token。
2. **`SpaceTokens` 不批量改名**：值与 DESIGN 阶梯一一对应，仅命名差一档（实现 xs=4 / 契约 xxs=4）。
   全量改名涉及 ~100 处引用且无视觉收益，改为在文件头落对照表。
3. **分段控件宿主传 `overrideTrackMaterial: true`**：组件自书「ULTRA_THIN 轨道需与 lightContent 同值」，
   两处宿主的轨道下都是实色背板（非滚动内容），故 lightContent 保持 false。**待真机看观感**。
4. **屏6 生成标题保留 serif 内嵌数字**：「serif 不上数字」的例外来自契约自身组件示例
   （`ai-generating-panel` 的标题就是「正在为你规划 5 天行程」），帧与契约一致，不另改。
5. **`京都（演示）` → `京都（示例数据）`**：保留 mock 演示城（用于无种子库的演示与回归），
   但把「演示」这类工程话术换成用户能理解的数据属性说明。
6. **不做 `service/` 编排层**：`GeneratingPage` 的生成编排虽在页面内，但按 P0 硬约束的字面口径
   （页面不得直接操作 RDB、不得直接发起 LLM 请求）已合规；抽门面属结构调整，先改文档再动手。
7. **`AreaPick` 从 `mock/` 移入 `model/`**：页面不该依赖 mock 目录（ARCHITECTURE 依赖表），
   mock 演示数据与页面共用同一视图模型。
8. **`provenance.confidence` 落库**（v5）：§3.2 溯源组的「可信度」此前算了就丢；补列后
   `SpotDao` 读写闭环，种子重灌（`v2-geo-3`）回填。

### 7.3 测试与验证基线更新

- hypium：**66/66**（此前文本 50 例；新增 MapStops 6、TodayCard 2、StyleConfig 5、DataSeeder +3，
  删模板 `Ability.test` 1）。
- 构建：`assembleHap` debug + ohosTest 均 BUILD SUCCESSFUL（本机 hvigor 直跑，签名配置临时注入后还原）。
- 三把尺子：色 48 件 0 偏差 / 字号 0 违规（图标档 7→0）/ 几何 0 偏差。
- 运行时：模拟器实走屏1→2→3→4→5→6→8→11→12，日志见《验收说明》。
