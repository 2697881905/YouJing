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


## 5. 逐屏实拍走查：真机截图上看得到的问题清单（2026-10-26）

之前我只跑静态尺就报「界面已收口」，口径是错的——尺量的是 token 有没有用对，量不出
"这屏看起来对不对"。这一轮把真机整屏截图逐张看了（屏8 行程详情、屏2 新建行程、费用、我的行程），
下面每条都是截图上肉眼可见的，标了严重度与是否已修。

### 已修（本轮）

| # | 屏 | 问题 | 修法 |
|---|---|---|---|
| 1a | 屏2 / 屏3 | **钉底按钮条被悬浮 dock 直接压住**——「开始规划」那颗主按钮上叠着 dock 的蓝色选中条 | 新增 `LayoutTokens.floatingDockClearance = 112`（按真机实测 dock 板 bounds `[55,2340][1080,2515]`、屏高 2690px、密度 3.125 推得：屏底到 dock 顶边 = (2690−2340)/3.125 = 112vp），`TripInputPage` 与 `PreferenceQAPage` 两处钉底条的 bottom 内边距从 `md`(16) 换成该档位 |

顺带查出同类：滚动内容用的 `bottomScrollReserve = 94` **小于** dock 实际占的 112vp，
所以凡是把主 CTA 放在滚动区末尾的页（费用页的「+ 记一笔」）净空也偏紧——这条还没改，
因为把 94 抬到 112 会影响所有列表页的尾部留白，属视觉判断，留给你定。

### 未修：屏8 行程详情

2. **【高，已修】底图首帧不收敛**：截图上两个白色气泡挤成一坨、其中一个压在卡片上沿。
   真因不是「`fitBounds` 没实现」——`MapStops.bounds` + `newLatLngBounds` 都在，
   而是**收敛只在父组件显式发 `fit` 指令时才做**，屏8 的地图卡不发，于是停在
   `aboutToAppear` 给的 `stops[0]` + `DEFAULT_ZOOM(11)`。已改成 `onReady` 首帧就 `moveCamera(cameraFor(stops))`。
   另更正一处我的误判：这条行程含**八达岭长城**，市域尺度本身是对的，不是坐标混入。
3. **【中】Day1/Day2/Day3 分段栏选中态太弱**：选中是深灰底、未选是黑底，
   肉眼看像三个独立按钮而不是一个分段控件。
4. **【中】meta 行几乎读不清**：「Day 1 · 07月01日」下面那行「王府井-东城核心 出发 · 第 1 日 · 标准」
   字号小 + 灰度低，实拍上已接近不可辨。
5. **【中】时间轴断在半空**：09:00 那一站下面蓝色竖轴只画了一小段就没了，
   页面下方约四成屏高是空白——内容不足时没有兜底排版。
6. **【低】「为什么排在这里」卡片末行孤字**：断句成「…动线由 / 近及远。」，末行只剩三个字。

### 未修：屏2 新建行程

7. **【中】标题语义重复**：顶栏已经是「有径 / 设定出行基础参数」，页内又写一遍
   「开启一次有迹可循的旅程 / 设定出行基础参数，AI 将基于…」，同一句话说两遍。
8. ~~【中】同行人数档位是 1 / 2 / 4：缺 3~~ —— **翻案，不是缺陷**。
   底稿帧 `屏2_行程基础输入_7d2eafa8/code.html` 原文写着
   "three 32px pill quick-picks **1 / 2 / 4**"，是设计契约；且 `partyOptions()` 会在实际人数
   不在档位里时把它补进去，不会出现选不中的情况。未选档无描边这一点帧里也是 `background: transparent`。
9. **【中→已修】预算档位那条看着像进度条**：件本身是官方 `Slider(OutSet)`，
   但 `blockColor` 取了 `surfaceElevated`——深色档 #1E1E1E 压在底轨上**把手几乎看不见**，
   整条就退化成进度条。已把把手改成 `primary`（两档都对比）。
   帧里只画了 4px 底轨、没有把手规则，所以这是「帧未规定」而非「帧规定不可见」；
   若你认为该严格照帧保持无把手，这一条要回退。
10. **【低】四张字段卡纵向间距偏松**，首屏放不下、必须滚。

### 未修：费用页

11. **【高】分段栏「预算 | 实际」选中态不可辨**：两格同底色、同字色、同字重，
    截图上完全看不出当前在哪一档。
12. **【中】hero 卡第二行小字低对比**：「预算 ¥16000 · 各天预估合计 ¥1540 · 2 人 · 3 天」
    是最关键的汇总信息，却用最小最灰的一档。

### 未修：我的行程页

13. **【中】三张行程卡完全同构**：除日期外没有任何视觉区分（同一组 8 景点 / 5 段 / ¥1540 / 同一张日序点条），
    一屏三张几乎一样的卡，扫读不出主次。
14. **【中】卡片底部那条蓝色细线语义不明**：截图上看像渲染残留，实际是状态条还是分隔条不清楚。
15. **【低】日序圆点 1–5 太小、间距太紧**，缩略状态下基本糊成一条。

### 修完之后的实拍复验（同一台机、同一批深链，`/tmp/ck_itinerary.png`、`/tmp/ck_tripinput.png`）

| 条目 | 复验结果 |
|---|---|
| §5.1 钉底按钮被 dock 压住 | **确认已修**。「开始规划」现在完整浮在 dock 之上，间距正常 |
| §5.9 预算滑杆看不见把手 | **确认已修**。蓝色圆把手清晰可见。**但**：帧原文是「4px track #E9E9EC with #0066CC fill, flanked by …」——**帧里根本没有把手**，所以这是一处为可用性的**有意偏离**，要你确认是否接受 |
| §5.2 地图首帧不收敛 | **没修好，我的归因错了**。改前改后两张截图构图完全一致。八达岭 + 故宫本来就跨这个市域尺度，所以"停在张家口→北京"是对的；真正可见的问题是**气泡被地图卡上沿裁切**、以及多站气泡之间没有编号区分。首帧 `moveCamera` 那条改动留着无害（宿主不发 `fit` 时的兜底），但它没解决这条 |
| §5.11 深色分段栏选中态 | **已修**（重测见下）。旧判定作废——装机重拍费用页（`/tmp/seg2.png`，已含 `isDarkMode` 播种与文字色两处改动），「预算」「实际」两格**依旧完全同色**。两次改动都没产生可见差别，不再叠第三次猜测。详见「§5.11 现场记录」 |

另外两条我此前判错、已按底稿帧翻案的：§5.8 人数档位 1/2/4 是帧原文；
§5.9 里「经济/舒适」两个标签也是帧原文（"flanked by 11px #69696E 经济 and 舒适"），不是缺档。

**这一页要记的方法论**：我三次把"看起来不对"直接写成缺陷（fitBounds、人数档位、预算标签），
前两次靠读代码和读帧翻案，第三次靠改完再截图才发现没修好。
结论是——**改完必须回到同一张机位再拍一次**，否则"已修"只是我的一句话。

### §5.11 现场记录（深色分段栏选中态，未解）

已做的两次改动与结果：
1. `ImmersiveSegmentBar` 在 `isDark && !lightContent` 分支补
   `fontColor=on_dark_degraded` / `selectedFontColor=on_dark`（选中纯白 vs 未选 60% 白，
   理论差 2.46 倍亮度）。
2. `EntryAbility.onCreate` 播种 `isDarkMode`（`e206e77`）——此前它只在 `onConfigurationUpdate` 里写。

**⚠ 下面这条「仍未修」的结论本身要作废重测**：那次复测跑在 `e206e77` 的产物上，
而 `e206e77` 的播种写的是 `config.colorMode === COLOR_MODE_DARK`——实测 `colorMode=0`（NOT_SET），
所以那一版 `isDarkMode` **依然是 false**，我补的文字色分支从来没执行过。
拿一个根因还在生效的构建去判「修复无效」，是我又犯了一次「测了个没生效的东西」的错。
`b985c30` 换成资源法之后 `isDarkMode=true` 已被日志证实，但分段栏**还没有在这一版上重测过**。
所以下面所有「两格同色」的读数只能算 `isDarkMode=false` 条件下的旧证据，不能当结论。

**重测结果（`b985c30`/`6fc6f0a` 产物，深链 `route=Expense` 直达、全程零点击；按 dump bounds 校准）**：

| 格 | bounds | 字色最亮 | 亮度 | 底色中位 |
|---|---|---|---|---|
| 预算（选中） | [264,411][352,462] | `#FFFFFF` | 1.000 | (65,65,65) |
| 实际（未选） | [772,411][860,462] | `#CACACA` | 0.591 | (63,63,63) |

两格字色**已经不同**（纯白 vs 降级白），§5.11 判定为**已修**——
生效的是「`isDarkMode` 资源法播种」+「`fontColor`/`selectedFontColor` 两处改动」的叠加，
单独任何一处都不够：分支进不去，文字色就从来没被赋过值。
假设 (b)/(c) 也随之排除：官方 `SegmentButton` 的 tab 档**是**认这两个字段的。


三种可能的当前状态：
`b985c30` 的日志给出 `config.colorMode=0`（NOT_SET），假设 (a) 坐实：旧的 `=== COLOR_MODE_DARK`
在冷启恒 false，所以深色档下那段分支从来没走过。改用资源法（解 canvas/ink 比亮度）后日志
报 `isDarkMode=true`，**但两格读数依旧相同（最亮都是 64）**，所以剩下的解释是 (b)/(c)：
官方 `SegmentButton` 在设了 `backgroundSystemMaterial` 时忽略 `fontColor/selectedFontColor`，
或被材质轨道统一底色吃掉。（注：这次采样行没按 dump bounds 校准，读数待复测。）
同一次改动还带出一条新的窄缺陷：**isDarkMode=true 之后底图仍是亮色路网主题**（#1D6F6E），
说明 `TripMapView.applyTheme` 并没有真的把底图切暗——这条比「深色档判定」更具体，也还没修。

- (a) `onCreate` 时 `context.config.colorMode` 不是 DARK（随后 `setColorMode(NOT_SET)` 才定档），播种仍是 false；
- (b) 官方 `SegmentButton` 在设了 `backgroundSystemMaterial`（本页 `overrideTrackMaterial: true`）时忽略
  `fontColor/selectedFontColor`；
- (c) 选中态生效了但被材质轨道统一底色吃掉，肉眼分不出。

**一条能一刀分开的判据（下次上机跑）**：切到「地图」tab 看底图是否转暗色主题——
底图主题同样只吃 `isDarkMode`（`TripMapView.applyTheme`）。底图变暗 ⇒ 播种生效，问题在 (b)/(c)；
底图仍绿 ⇒ 播种没生效，问题在 (a)。这次没跑完：截图后设备被真人取走，dock 标签已从 dump 消失。

旁证支持 (a)：本轮改前改后的行程详情页截图里整屏是深色档、底图却是绿色浅色路网配色，与「isDark 为 false」一致。

### 地图 tab 修好之后又翻掉我自己的两条判读（`/tmp/m4.png`、`/tmp/lg2.png`）

- **「底图仍亮色路网」是我看错了**：`isDarkMode=true` 之后底图已经是夜间主题（深色路网），
  我拿一个区域均值 `#1D6F6E` 就下结论，没看图。`TripMapView.applyTheme` 走的是
  `controller.setDayNightMode(NIGHT)`，代码本来就没问题。
- **「地图收敛没给 dock 让位」也是我编的**：`MapPage` 传的是 `FIT_BOTTOM_PX = 600`，
  而 dock 只占屏底 350px（2690−2340），早就盖过了。截图右下角被裁的「颐和园」是**底图自带路网标注**，
  不是我们的 marker 或文案，改不了也不该改。
- 真正修好的是取数：地图 tab 现在标题「北京 · 3天2晚 / 8 站」、8 个编号 marker、连线都在（`b985c30`）。

**新发现一条真缺陷（rootMode 标题栏）**：`我的行程` 页的标题栏里，
菜单圆钮渲染在**右上角独立一行**，大标题「我的行程 / 19 条」掉到它下面左对齐——
钮和标题不在同一行。而 destination 模式（被别的页 push）下是同一行。
这是 rootMode 把 `.titleBar()` 从 `HdsNavDestination` 挪到 `HdsNavigation` 之后才出现的，
得单独查 `HdsChrome.bar()` 在 Navigation 档下的标题样式（`MINI`/大标题）怎么给。
顺带纠正一次探针失误：我按 `y<230` 过滤可点节点找不到登出钮，其实是它在 `y≈325`，
**过滤条件写错，不是控件没渲染**——别把探针的漏判当成 App 的缺陷。

### §5 判读的实测复核：几条「低对比 / 看不清」是我目测错了（bounds 校准法）

用「深链直达目标页（全程零点击）→ dumpLayout 取节点 bounds → 只在框内取样」重量，
结果把我原先靠看 620px 缩小截图下的判断推翻一批：

| 条目 | 我原先说 | 实测 | 判定 |
|---|---|---|---|
| §5.3 屏8 Day 分段栏选中态弱 | 像三个独立按钮 | 选中 `#FFFFFF` 9.89:1 / 未选 `#CBCBCB` 5.64:1 | **已修**（与 §5.11 同源，`isDarkMode` 修好后一起生效） |
| §5.4 meta 行几乎读不清 | 低对比 | `#B1B1B3` on `#121212` = **8.75:1** | **作废**，我误判 |
| §5.12 费用 hero 小字低对比 | 最小最灰一档 | `#B6B6B8` 8.22:1、`#ACACAE` 7.27:1、`#C4C4C6` 9.56:1、说明文字 9.05:1 | **作废**，全部远超 AA |
| §5.5 下方四成屏高空白 | 约 40% | 正文最底 y=1771、dock 顶 2340 → 留白 **182vp ≈ 屏高 21%**，且因这条行程 Day 1 只有两站 | **改口径**：不是布局 bug，是短列表无兜底排版的视觉问题 |

**方法上的教训（写死在这里）**：对比度、字号、"看不清"这类判断**不能靠缩小截图目测**——
620px 宽的整屏缩略图会把 11–13vp 的小字糊掉，看着就是"淡"。
必须按节点 bounds 在框内取样，且深浅两档分别量。
§5 里剩下的「低对比」类条目在这一条方法修正完成之前，都只算待测，不算缺陷。

复核后 §5 仍然站得住的，只有需要看图才能判的排版/设计类：
§5.6 卡片末行孤字断句、§5.7 顶栏与页内标题语义重复、§5.13 三张行程卡完全同构、
§5.14 卡底蓝色进度条无标注读起来像残留线、§5.15 日序圆点偏小。
这几条要么属文案/设计定稿（归用户），要么需要逐屏大图目视，不能靠数值判。

### 结构性根因（本轮开始补）

有此前**零屏幕适配层**：全仓 grep 无 `breakpoint / isWidePane / foldStatus / windowSizeChange /
expandSafeArea`，六个页面的卡片全是单列 `List`（全仓零 `Grid`、零 `lanes`），
宽屏（折叠展开 / 平板 / 2in1 自由窗口）下卡片会被整屏拉宽、行长失控。
本轮已补 `utils/breakpointCenter.ets` + `utils/responsive.ets`（照有据移植，断点按窗口宽 vp），
六个列表页挂上 `List.lanes`（sm 1 / md 2 / lg 3）。
另外 `LayoutTokens.contentMaxWidth = 720` 这一档此前零消费方，也一并记在这里。


## 4m. 对比度尺在「小字 + 饱和/半透明底」上系统性低读（2026-10-26，第三次撞同一堵墙）

§4l 量完 dock 之后，把 `tools/audit_contrast.py` 直接跑在深色档那一帧上，它报了 6 处低于阈值：

| 尺报的 | 精算真值 | 判定 |
|---|---|---|
| 行程 1.46:1 / 我的 2.19:1 / 地图 3.21:1 / 费用 3.53:1 | 未选 `muted #97979E` on 板 `#202022` = **5.60:1**；选中 `primary #0A84FF` = **4.46:1** | 尺误报（板是半透明材质 + 10fp 细字） |
| 华为账号一键登录 3.18:1 | 深色 `onPrimary` 是 **`#121212`**（不是白）on `#0A84FF` = **5.14:1**；浅色白 on `#0066CC` = **5.57:1** | 尺误报 |
| 仅使用 UnionID 静默授权… 3.02:1 | `muted` on `canvas` ≥ 6:1 | 尺误报 |

**结论：这条尺在「小字号 + 饱和色/半透明底」上会系统性低读 1.5～2.5 个点**，
它的深色档输出**不能直接当改色依据**——按它去"修"这些行会把本来达标的配色改坏。
判读顺序仍是：`color.json` 精算 → 像素只用来发现"根本没画出来"（§4i 立的规矩，这是第三次实证，
前两错分别是拿像素当 3.59:1 的结论、以及把遮挡框的采样当真实底色）。

机制上两处叠加：① 框内取"对侧最极端 2% 均值"当字色，10fp 笔画覆盖率不到 5%，
jpeg 的色度噪声会把这批像素往底色拉；② 底色取框内中位数，而 dock 板是半透明材质、
主按钮是饱和蓝，中位数本身就不是文字真正压在的那层色。

**顺手排掉一个真可疑点**：`onPrimary` 在深色档是 `#121212`（深色档主按钮用近黑字压亮蓝），
浅色档才是白字——两档都过 AA，不是缺陷。

要补的话有两条路（都还没做）：给尺的 dock/按钮类节点加"精算优先"白名单，
或者把采样底色从"框内中位数"换成"该节点祖先链上第一个不透明 `backgroundColor`"。
前者 20 行、后者要重走祖先链。


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


## 5b. 视觉/排版深度优化第一轮（2026-10-26 深夜，真机复拍为证）

用户口径：「UI 布局、排版、设计一塌糊涂……用户业务流程混乱，组件 UI 排版布局交错」。
这一轮不再跑静态尺，而是**先把真机整屏截图逐张看一遍**，把「交错」按像素定位到具体节点，再改。

### 实拍查出的根因（改前）

| 屏 | 现象 | 真因 |
|---|---|---|
| 首页（tab 行程） | 主按钮与「仅使用 UnionID…」声明被悬浮 dock 直接压在下面、声明文字被挤到系统导航条上裁掉 | `YoujingStartPage` 底部区**完全没有 dock 净空**（该页从没挂过 `floatingDockClearance`） |
| 首页 | 按钮写「华为账号一键登录」，实际动作是 `pushPath('TripInput')` | 屏1 还是「首启 + 静默登录」那一版，而登录闸门早已搬到 `Index` 的 `LoginView`——**同一件事问两遍，且标签撒谎** |
| 首页 | 卡下方约四成屏高空白 | 一张编出来的京都演示动线常驻首页，真行程反而在「我的」页签里 |
| 我的行程 | 单卡占屏 1/3、19 条只见 2.5 张；「已结束」上下印两遍；`¥1540` 胶囊贴住「5 需预约」读成「5¥1540」 | 卡里那条 1–5 圆点行是 `ForEach([0,1,2,3,4])` **硬编码 5 格**，3 天行程也画 5 格——假数据 + 白占 44vp |
| 新建行程 | 顶栏「有径 / 设定出行基础参数」+ 页内第二行「设定出行基础参数，AI 将基于…」同句两遍 | §5.7 |
| 新建行程 | 预算档位卡同时挂 chevron（读起来是「点这里选择」）和 Slider | chevron 点了没有任何动作，两个控件互相竞争 |
| 流程 | 从「我的」页签点「创建新行程」→ 后续页推到看不见的 tab-0 栈上，表现为**点了没反应** | `TripsPage` push 到 `MINE_NAV`，而 `TripInputPage` 内部硬用 `APP_NAV` |
| 流程 | 列表非空时，这一屏**没有任何新建入口**；右上角只有一枚没标签的人像钮 | 创建入口只写在空态分支里 |

### 这一轮做了什么

1. **首页重排**（`YoujingStartPage`）：主 CTA 上移到首屏可见处并改名「开始规划新行程」（去掉人像图标与 UnionID 脚注）；
   演示预览卡**只在还没有行程时出现**；新增「最近行程」三条真数据（`TripDao.listSummaries`，可点回屏8/屏15）
   \+ 「查看全部 N 条行程」跳「我的」页签；整页给 dock 让出 `floatingDockClearance`。
2. **我的行程卡重排**（`TripsPage`）：删掉硬编码的 1–5 圆点行；三态徽章（旅行中/未出发/已结束）进标题行右侧；
   `¥` 金额从三格统计里挪出来、自带「总花费」标签；状态只说一次；卡内边距 `lg`→`md`。
   日期行补真实天数（`· 3 天 ·`）。顶栏新增官方 `plus` 的**新建行程**菜单项（此前列表非空就没有创建入口）。
3. **新建行程页**：删掉与顶栏重复的那一行（**保留帧声明的衬线大标题**——字族尺把它钉在 `屏2 serif 槽`，
   删干净会报「槽位漏做」，重复的其实只是副标题那句）；预算卡去掉那枚无动作的 chevron；四张字段卡内边距统一 `lg`→`md`。
4. **流程硬伤**：`AppNav` 新增 `requestTab()` / `enterPlanningFlow()`，`Index` 用 `@StorageProp + @Watch`
   在运行期调 `hdsController.changeIndex()`（冷启那条路仍只认 `HdsTabs` 的 `index` 初值，两者不冲突）。
   创建入口一律「先切回行程 tab，再把第一页推进 `APP_NAV`」。
5. **全链路步骤指示**：新增 `components/FlowSteps.ets`（五段进度轨 + 「第 N / 5 步 · 名称」），屏2 已挂上。
6. **dock 净空**：费用页与我的行程页的滚动区底部从通用 94 换成实测 `floatingDockClearance`(112)。

### 真机复拍结果（同一台机、同一批深链，`/tmp/w1.jpeg`、`/tmp/w_Trips.jpeg`、`/tmp/w_TripInput.jpeg`）

| 条目 | 结果 |
|---|---|
| 首页主按钮被 dock 压住 / 声明被裁 | **确认已修**。CTA 完整浮在 dock 之上、且在首屏可见处；脚注已去掉 |
| 首页按钮标签撒谎「华为账号一键登录」 | **确认已改口**为「开始规划新行程」，与动作一致 |
| 首页四成空白 | **确认已填**：换成三条真行程 + 查看全部 |
| 我的行程 单卡占屏 1/3 | **确认已修**：同屏从 2.5 张涨到 3.2 张，`¥1540` 与「总花费」同列、不再粘住「5 需预约」 |
| 我的行程 「已结束」印两遍 | **确认只剩一处**（标题行徽章 + 末行「已结束 · 100%」） |
| 我的行程 假 1–5 圆点行 | **确认已删** |
| 新建行程 标题重复 | **确认已修**，且字族尺 `fontfamily` 归 0（衬线槽保住） |
| 新建行程 预算双控件 | **确认只剩 Slider** |
| 步骤指示 | **实拍已出**：「第 1 / 5 步 · 基础信息」+ 五段进度轨，首段蓝、余段分隔色 |
| 七把静态尺 | colors / type / geometry / material / fontfamily / tnum / elevation **全部 exit 0** |
| 装机产物新鲜度 | `strings -a modules.abc \| grep -c tripTotal` = 4（防 hvigor 复用旧产物） |

### 这一轮**没**验到的（写清楚，不当已修）

- ~~**从「我的」页签点新建 → 是否真落到行程 tab**~~ **已真机验通**（`/tmp/g2.jpeg`）：
  `route=Trips` 直达「我的」→ 顶栏 `+`（bounds `[811,237][936,362]`，先垫一次 dock 空点击再单点）
  → dump 读到 `有径 | 开启一次有迹可循的旅程 | 第 1 / 5 步 · 基础信息 | 目的地 | 北京 …`，
  且截图上 dock 的**选中态已翻到「行程」**。`requestTab` + `Index.@Watch → changeIndex` 这条运行期通路成立。
  注：HDS 顶栏副标题「设定出行基础参数」在 dump 里读不到节点（顶栏文本不进 dumpLayout），只能靠截图确认在位。
- **屏3/屏4/屏5 的步骤指示**：只挂了屏2。屏3 自带「第 N/4 步」是帧原文，两套并存要不要统一待用户定。
- **三张行程卡仍然长得一样**：因为库里这几条真行程的目的地/日期/景点数**本来就相同**（测试数据），
  不是排版没改。要区分得靠数据本身有差异。
- **ImmersiveSurface 的流光**在深色档下于卡片下沿结成一团暖色光斑（首页实拍可见），
  本轮只把这张卡改成「空态才出现」，**光斑本身没动**。
- **hypium 未跑**：本轮全是 UI 层改动，没有设备空档跑 81 例。

### §5b 续：步骤指示铺满屏2–屏5（真机 dump 字面证据）

`components/FlowSteps` 挂到屏2/屏3/屏4/屏5。深链直达 + `dumpLayout` 读到的原文：

| 屏 | dump 文本 |
|---|---|
| 屏3 偏好追问 | `偏好追问 \| 第 2 / 5 步 · 出行偏好 \| 问题 1/4` |
| 屏4 选景点 | `选想去的地方 \| 第 3 / 5 步 · 选景点` |
| 屏5 住哪一片 | `住哪一片 \| 第 4 / 5 步 · 选住宿` |

**顺带修掉一处会读错的文案**：屏3 原本圆点行和顶栏副标题都写「第 N/4 步」，
说的却是**本屏四道题**——和主链进度同名不同义，用户会以为整条流程只有四步。
两处统一改口成「问题 N/4」，主链进度独占「第 N / 5 步」这个说法。

### §5b 新发现一条未修的显示缺陷（dump 抓到，不是目测）

屏4 `选想去的地方` 的 dump 文本序列里有一个孤立节点 `0.000000`——
一个经纬度以六位小数原样渲染进了界面。本轮没动它（不在本轮改动面上），记下来待查来源。

### §5b 续 2：屏8 行程详情（主屏）两处实拍缺陷

`route=Itinerary` 直达实拍（`/tmp/xItinerary.jpeg` → 改后 `/tmp/y8.jpeg`）：

1. **200vp 的深蓝渐变空盒**：当天没有任何落点时，地图卡照样按 `mapHeightCompact` 撑满，
   只在角落贴一枚「当日暂无安排」——主屏三分之一面积既无信息也不可点。
   改成**没落点整块不出**（连带删掉那段 `routeBgTop/routeBgBottom` 渐变兜底，它已不可达）。
2. **空白天原来只有一行 12vp 灰字**，下面五成屏纯黑，且**没有任何前进通路**：
   用户站在这屏既加不了节点也退不出去。按契约 empty-state 规格补齐
   （48 展示档图标 + title 衬线 + 240 限宽说明 + 一个主按钮「去添加景点」→ 屏9 编辑页带 `EditTarget`）。

**仍未解决（不当已修）**：空白天补完兜底后，下方仍有约四成屏高纯黑——
`List` 的 ListItem 不会自己垂直居中。要治得给空态单独走「非 List 的居中布局」分支，本轮没做。

### §5b 续 3：屏15 旅行中三处 + 一条我记错的「缺陷」

**先撤回一条**：上一轮我记「屏4 dump 里有个孤立文本节点 `0.000000`，像是经纬度原样渲染进界面」——
**这条不成立，是我误判**。取那个节点的完整属性：`type: "Progress"`、`bounds [50,609][1086,622]`、
`text/originalText: "0.000000"`。`dumpLayout` 会把 `Progress` 的**值**报成 text（与 OnTripPage 里
「真机实测 1.000000」那条注释同一机制）。全仓 grep `toFixed(6)` 零命中，界面上也没有这串字。
**教训**：dump 读到的文本要先回查它属于哪种节点类型，别看见数字就当渲染缺陷。

**屏15 实拍（`/tmp/xOnTrip.jpeg` → 改后 `/tmp/z15_top.png`）三处已修**：

| 问题 | 修法 |
|---|---|
| hero 卡上「今日暂无安排」**印两遍**（标题一行、meta 又一行） | `heroMeta()` 在 `current === null` 时返回的就是同一句；改成空态下不渲染这一行 |
| 今天没有节点时「完成打卡」仍是**可点按钮**（打卡没有对象） | 该按钮整颗按 `current !== null` 门控；「记一笔费用」保留（记账不依赖节点） |
| 「还没有打卡节点」只说没有、不说为什么 | 改口「今天还没有走过任何节点，打卡后会出现在这里」 |

**另查出一条系统性渲染缺陷（影响所有上流光的表面）**：
`ImmersiveSurface` 的官方 `HdsVisualComponent` 边光**画到卡片几何之外**——屏15 实拍里那弧紫光
悬在卡片上沿之上、落在页面黑底上，看着就是渲染残留（首页那张预览卡下沿的暖色光斑同一根因）。
原实现只 clip 了流光层自己，没 clip 容器。给外层 Stack 补 `.borderRadius(this.radius).clip(true)`
后复拍：紫弧消失，光只留在表面圆角内侧。
**这条是几何缺陷、不是审美取舍**，与「流光要不要上更多表面」那件待用户定的事无关。

**仍未解决**：屏15 短内容时下方仍有约六成纯黑（`List` 的 ListItem 不会垂直居中）；
屏15 这次是拿一条**已结束的过去行程**拍的（深链不带 tripId → 回落 `activeTripId`），
所以「旅行中」页对着过期行程本身没有真实语义，正常入口（我的行程卡 → 在途才进屏15）不会这样。

### §5b 续 4：屏16 分享与导出、屏9 编辑行程

`route=Share` / `route=EditItinerary` 直达实拍（改前 `/tmp/pShare.jpeg`、`/tmp/pEditItinerary.jpeg`；
改后 `/tmp/qShare.jpeg`）：

| 屏 | 缺陷 | 修法 | 复拍 |
|---|---|---|---|
| 屏16 | **钉底动作条整条被悬浮 dock 压住**，「内容在本机生成…」说明裁掉半行 | 底部内边距 `xl`(24) → `floatingDockClearance`(112)，滚动预留同步加一档 | 确认已修：两颗钮与说明完整浮在 dock 之上 |
| 屏16 | 帧里那块 140vp 的「行程纸」**任何状态下都是空的**，实拍读起来就是一张没加载出来的占位图 | 删掉（抬头已有目的地与日期，三统计紧跟其下，不丢信息） | 确认已消失 |
| 屏9 | 空态文案「**未指定行程**」是说给开发者听的；且顶栏三颗钮（完成/⊕/撤销）在这种状态下全都可点 | 分成两种：没带行程 → 「没有带进行程 / 从「我的行程」里选一条行程再进来」；当天没节点 → 「这一天还没有节点 / 点右上角 ⊕ 可以补选景点」 | 未复拍（改动是文案与排版，无新交互） |

**代拍一条（可否决）**：那块「行程纸」是底稿声明的装饰块，但它从不装内容。
我按「装饰件要么有活干、要么删」的原则删了；要保留就得往里放真信息（目的地题头 / 逐日点条），
那是新设计，没替用户做。

### §5b 续 5：钉底层没让位 dock 是**系统性**的，一次扫完

前两屏（屏16、屏7）拍出来之后不再一屏一屏撞，改成全仓扫
`Stack({ alignContent: Alignment.Bottom })` 的钉底层，逐处看它给 dock 留了多少：
**只有屏2/屏3 当年补过 `floatingDockClearance`，其余全是 `lg`(16) 或 `xl`(24)**——
而悬浮 dock 实测占屏底 112vp。

| 屏 | 钉底层原净空 | 改后 | 真机复拍 |
|---|---|---|---|
| 屏7 生成受阻 | `xl` 24 → 第三颗「去掉这个景点」整颗压在 dock 背后 | `floatingDockClearance` | 三颗钮完整浮在 dock 之上 |
| 屏4 选景点 | `lg` 16 | `floatingDockClearance`，滚动预留 `stickyBarScrollReserve + floatingDockClearance` | **已复拍**：「跳过选择 / 确认选择」两颗钮完整浮在 dock 之上 |
| 屏5 住哪一片 | `lg` 16 | 同上 | 已复拍（`/tmp/sStayPick.jpeg`），钉底条不再进 dock |

补拍之后**又在屏4 看到两条新的**（本轮未修，按严重度排）：
- 【中】吸顶的「已选 0 / 可用 1 天 · 建议上限 4 个」这条灰带**下沿被裁**，它下面那根选择进度线只露一半；
  紧接着的分组头「必去 · 7」上沿又被灰带压住——两条头贴在一起，读起来像渲染错位。
- 【低】主链步骤指示（`第 3 / 5 步`）与这条「已选…」灰带之间没有间距，两段信息挤成一块。
| 地图页 站点条 | 只 `sm` 8，整条坐进 dock 里（实拍「:30-」「和园」各露半截） | 加 `margin bottom: floatingDockClearance` | 站点条三张卡完整可读 |

**没改的两处及理由**：
- 屏8 `ItineraryPage:1075` 那个 `xl` 住在 `bindSheet` 的面板内容里，半模态面板不在 dock 之下，不该让位；
- 地图页顶部「全程 / Day 1 / Day 2 / Day 3」看着像右侧裁切，读代码是
  `Scroll(ScrollDirection.Horizontal)` + 两侧 `lg` 内缩，**本来就是横向可滚的胶囊轨道**，不是缺陷。

**这一类的通用规矩（写在这里免得再撞）**：凡是 `Stack({alignContent: Bottom})` 里钉底的
动作条 / 信息条，一律给 `LayoutTokens.floatingDockClearance`；放在 `bindSheet` 里的不算。

### §5b 回归闸门

钉底清扫之后的产物上重跑真机 hypium：**`Tests run: 81, Failure: 0, Error: 0, Pass: 81`**。
七把静态尺在每一次构建后都跑，本轮全程 exit 0。

### §5b 续 6：屏4 吸顶层与费用页 0 值进度条（复拍确认）

- **屏4**：「已选 0 / 可用 1 天 · 建议上限 4 个」这条灰带原来钉死 `height(56)`，
  内容居中后进度条正好压在灰带下沿上，读起来像灰带被裁了一半；且它与上方步骤指示之间零间距，
  两段信息挤成一块。改成上下各留一档内缩、去掉定高，步骤指示下方补一档间距。
  复拍 `/tmp/nSpot_top.png`：进度轨完整落在灰带内，两段信息分开。
- **费用页 hero**：进度条原来单独一条、**没有读数**——已花 0 时就是一个空轨，
  实拍读起来是「卡里的一条分隔线」（与 §5.14 那条蓝线同一类）。
  改成同排给「已用 N%」读数，轨色压到 `surface-sunken` 与卡面分开。
  复拍 `/tmp/nExp_top.png`：轨与读数都在，不再像分隔线。

七把尺 exit 0（本轮全程如此）。

### §5b 续 7：屏8 有内容时的三处交错（真机点进真行程才看得到）

前面几轮屏8 都是拿**无 tripId 的深链**拍的，只拍到空态。这轮从「我的行程」点进真行程
（`uitest` 垫一次空点击再单点卡片中心 `[50,1060][1086,1546]`），拍到三条真缺陷：

| 现象 | 根因 | 修法 | 复拍 |
|---|---|---|---|
| 日标题与 meta **同行互撞**，末尾「标准」被裁出右沿 | `dayHeader` 是 `Row{日标题, Blank(), meta}`，21vp 衬线日标题 + 长 meta 超出屏宽后 **`Blank()` 塌成 0**，两段文字直接贴上、末段溢出被裁 | 拆成两行 `Column`，meta 限一行带省略号；`height(dayDividerHeight)` 换成 `constraintSize({minHeight})`，两行才装得下 | 确认已修：「Day 1 · 07月01日」与「王府井-东城核心 出发 · 第 1 日 · 标准」各一行，**「标准」完整可读** |
| 时间轴竖线**从节点一路画进下方黑里** | `stopRow` 的 spine `Column.height(isLast ? 12 : '100%')`——这一行没有定高，**百分比按视口高解析**，所以竖线是一整屏长 | 换成具名行高 `itineraryRowMinHeight`(76)，与首启预览卡同一档；Stack 同步去 `'100%'` | 确认已修：竖线只在节点→通勤腿→下一节点之间 |
| 「需预约」右边一块**悬空的 36×48 深色方块** | 那是景点缩略位，但 `Activity`/AI 契约里**根本没有图片字段**，它永远填不上 | 删掉（与屏16 那块空「行程纸」同一判据：装饰件要么有活干、要么删） | 确认已消失 |

顺带：空白天补的兜底改成 `.height('100%') + justifyContent(Center)`，
空态不再贴在 List 顶上留五成黑（§5.5「断在半空」的另一半）。
复拍整屏：Day 1 两站两段通勤腿**一屏放得下**。

**留下的小瑕疵（未改，记在这里）**：节点圆与站名首字之间只有 `sm`(8) 间隙，实拍偏紧；
「需预约」胶囊孤悬在行最右。两条都属"能看但不够舒服"，改动会牵动行宽，先不叠。

### §5b 续 8：屏10 节点详情面板（真机点开拍的）

先记一条**探针教训**：我按缩小截图估的 y 坐标（1030/1075/1120）连点三次都没开面板，
一度判成「屏10 打不开」的流程缺陷。用 `uitest dumpLayout` 取到行的**真实 bounds**
`Row [50,1399][1086,1802]` 后一次就开——**落点要来自 dump，不要来自目测**。
（先用「点 Day 2 分段看日标题有没有变」证明 uitest 打得进去，才排除掉设备被占用的可能。）

面板本身排版是成立的（四格统计 / 预约状态 / 到达方式 / 预约提示 / 为什么排在这里 / 动线位置三节点 / 两颗动作钮），
只有一处真缺陷：

- **左上一块 96×128 的纯黑 `mediaThumb` 占位**——`Activity`/AI 契约里没有图片字段，它永远填不上，
  还把站名挤成窄列，实拍折成「北京环球度 / 假区」两行。删掉。
  复拍 `/tmp/u10.jpeg`：「故宫博物院」单行满宽，徽章与地址各归位。

**留下未改**：分享钮（↗）与官方 ✕ 在右上角挤得偏近（`bindSheet showClose` 占右上角那条老坑）；
「到达耗时 / 门票费用」两格显示「—」是诚实占位，不是缺陷。

## 5c. 流程缺陷：同意弹窗让你同意一份**读不到**的政策（已修）

`PrivacyConsentDialog` 自己的头注释写着「①《隐私政策》②《用户协议》**可点开看原文**」，
但三处入口（隐私弹窗两个链接 + 登录页勾选行两个链接）实际都只调 `toastDocPending()`——
弹一条 1.8 秒的「协议原文页面整理中」。**用户被要求同意一份自己读不到的政策**，
这是本轮认定的最严重流程缺陷（既是体验问题，也是上架合规问题）。

**修法**：新增 `common/constants/LegalDocs.ets`（正文）+ `components/LegalDocReader.ets`（阅读器），
两处宿主都**就地展开**：
- 隐私弹窗：`@State reading` 非空时整块正文换成阅读器 + 「返回」；
- 登录页：`bindSheet` 承载（正文是静态文本，不涉「bindSheet 内容不随父 @State 重绘」那条坑）。

不 push NavDestination 的理由写进了阅读器头注释：CustomDialog 里推路由会留下
「返回后弹窗还在不在、要不要重问」的竞态。`toastDocPending` 与它的两条调用一并删除。

**正文来源**：逐条按当前实现写（RDB 私有目录、Account Kit 只取 UnionID、
日历明示同意、卡片本机渲染、SkillPrefill 取后即删、无云同步故卸载即清），
不是套模板。**上架前须法务复核**——文件头已写明这是"应用实际怎么做"的事实描述、不构成法律意见。

**取证方式**：临时把 `Index` 的同意判定改成恒真（`PROBE-TEMP`），装机拍到弹窗与展开后的阅读器
（`/tmp/cd1.jpeg`、`/tmp/cd2.jpeg`），**验毕还原并 grep 确认零残留**，再装回与源码一致的产物。
没有动用户的账号会话或本机数据去换这条证据。

**留下的小瑕疵**：阅读器自带一层 `surfacePanel` 圆角底，套在弹窗自己的圆角底里，
实拍有双重边框感；正文第二节的末行正好被滚动区下沿切住（滚动容器的正常行为，但首屏读不完一条）。

## 5d. 流程侧收口：屏7 两条路打同一个目的地 / 返回栈弹错 / 死代码

| 项 | 现象 | 修法 | 证据 |
|---|---|---|---|
| 屏7 重复落点 | 「两条可行修法」每行 `pushPath(fix.route)` 把屏3/屏4 堆到失败页**上面**，而底部三颗钮又 `popToName` 同两个页面——同一目的地两条路、栈结果不一样，失败页还被压在下面留在栈里 | 抽 `goFix()`，与底部按钮统一成「能回到该页就回、回不去再 push」 | 编译过；行为待真机走一遍生成失败链 |
| 屏7 按钮名不对实 | 「换一天」实际落到屏2 基础输入（城市/日期/人数/预算都在那），不是只换一天 | 改口「**改出行日期**」 | dump 读到 `再试一次 \| 改出行日期 \| 去掉这个景点` |
| `ComingSoonPage` 弹错栈 | 它是「没认出来的路由名」的统一落点，四条 tab 栈都可能渲染它，却硬用 `APP_NAV.pop()` → 从地图/费用/我的那三条栈进来时「返回行程」点了没反应 | 改由 `NavDestination.onReady(ctx => ctx.pathStack)` 拿**自己所属**的栈 | 编译过（`NavDestinationContext` 在本 SDK 可用） |
| 死代码 | `AppRouter` import 了 `YoujingStartPage` 却不在 `routerMap` 里；`PENDING_ROUTE_KEY`/`PENDING_PARAM_KEY` 全仓零读零写 | 删 | grep 零残留 |

**查过、确认不是缺陷的一条**：屏6 「取消」原来我怀疑它只 pop、生成还在后台跑。
读代码：`aboutToDisappear` 置 `cancelled = true`，`run()` 在**每一段**都查它并提前返回——
取消确实中止。所以没加二次确认（那只会给一个本来就安全的动作添摩擦）。

## 5e. 屏幕适配：第一次拿到「断点确实驱动布局」的证据（任务 #39）

此前状态是**双向的空**：`LayoutTokens.contentMaxWidth = 720` 零消费方，
`responsive.contentMaxWidthForBreakpoint()` 也零消费方——适配地基铺了，没有一处用。
而宽屏/折叠展开**一帧实拍都没拿到过**（设备是 1136×2690 的直板机）。

**这一轮第一次把机制验通**：临时在 `Index.aboutToAppear` 把
`AppStorage('currentBreakpoint')` 钉成 `'lg'`（`PROBE-TEMP`，验毕已还原、grep 零残留），
装到真机后 `我的行程` 列表**真的从 1 列变 3 列**——
dump 里「景点」标签的 x 起点是 `87 / 432 / 778` 三个值。
所以 `breakpointCenter → AppStorage → @StorageProp → List.lanes` 这条链是活的，不是死代码。

**同一帧还拍到一件重要的事**：卡片在 ~101vp 的列宽下整个崩版——
站名「北京」被压成「···」、三格统计竖排、「已结束 · 100%」逐字换行。
这是**物理上到不了**的宽度（`lg` 意味着窗口 ≥840vp，三列时每列约 270vp），
但它说明卡片自身没有最小列宽保护，一旦有人调阈值就会真崩。

于是补了 `entry/src/ohosTest/ets/test/Responsive.test.ets`（5 例）把这件事钉住：

| 用例 | 钉的是什么 |
|---|---|
| `lanes_follow_breakpoint_ladder` | sm/md/lg → 1/2/3 列；未识别串一律退回单列（不能让 `List.lanes` 拿到 0） |
| `only_sm_is_narrow_pane` | `isWideBreakpoint` 只在 sm 为假 |
| `long_form_is_uncapped_on_phone_and_capped_on_wide` | 手机档必须返回字符串 `'100%'`——返回数字的话 `constraintSize.maxWidth` 会拿到比屏宽还小的值、把表单压窄 |
| `every_ladder_step_keeps_lanes_readable` | **每档起始宽 ÷ 列数 ≥ 180vp**（180 就是上面那帧崩版的量级）；同时钉住 `BP_MD_MIN_VP=600`/`BP_LG_MIN_VP=840`，防止有人把 md 调到 320 让手机也进多列 |

配套改动：`breakpointCenter` 里 600/840 原来是第 40 行三元里的裸数字，提成具名导出，
测试才钉得住。**真机宽屏渲染仍未验**——这 5 例验的是映射与安全边际，不是某个设备上的像素。

**接上了 `contentMaxWidth` 的消费方**（`utils/responsive.ets` 原来那个
`contentMaxWidthForBreakpoint(bp, phoneWidth)` 返回数字、手机档没法表达"不收窄"，
改成 `longFormMaxWidth(bp, capVp): Length`，手机返回 `'100%'`）：
- `LegalDocReader`（协议正文——长散文最容易被拉宽）
- 屏2 表单（不收窄的话宽屏上一行「目的地」能拉到八百多 vp）
- 屏8 时间轴（**不能按断点分栏**，会打断主轴竖线，所以走"收窄 + 居中"这条路）

上限值由消费方从 `LayoutTokens.contentMaxWidth` 传入，因为
`ARCHITECTURE` §分层明文规定 `utils/` 只能依赖 `common/`、**不得引用 `design/`**。

**顺带修掉我自己上一轮引入的脆弱设计**：行程卡的「总花费」先做成第四格统计，
这一帧里四格在窄列中竖排、`¥1540` 拆成三行。改成三格统计 + 金额进末行右端带标签。
三格比四格在所有宽度下都更稳。

**闸门**：七把尺 exit 0；真机 hypium 从 81 例涨到 **102 例全过**（含新增 5 例 Responsive）。

## 5f. 完整建行程链真机走通（首页 → 屏8），并修掉主入口的 8 秒无反馈

用 `dumpLayout` 定位 + 点击的脚本走了一遍全流程，每一跳都校验落点：

| 跳 | 到屏 | 步骤指示 | 耗时 |
|---|---|---|---|
| 首页 点「开始规划新行程」 | 屏2 基础输入 | `第 1 / 5 步 · 基础信息` | **改前 8s / 改后 2.0s** |
| 屏2 点「开始规划」 | 屏3 偏好追问 | `第 2 / 5 步 · 出行偏好` + `问题 1/4` | 1.9s |
| 屏3 四题各点「下一题」，末题钮为「选景点」 | 屏4 选景点 | `第 3 / 5 步 · 选景点` | — |
| 屏4 点「确认选择」 | 屏5 住哪一片 | `第 4 / 5 步 · 选住宿` | — |
| 屏5 点「就住这里」 | 屏6 → 屏8 | 屏8 出真行程 | — |

终点屏8 实测文本：`北京 · 3天2晚 | Day 1 · 10月27日 | 南锣鼓巷-鼓楼 出发 · 第 1 日 · 标准 |
09:00 故宫博物院 需预约 | 地铁 22分钟·2站 | 13:15 八达岭长城 …`——**五档指示全程逐级推进、无一档卡住**。

### 走查逼出来的一条真缺陷（已修）

首页主 CTA 按下后**界面零反馈约 8 秒**（日志 `00:05:19 按下 → 00:05:27 静默登录成功`）。
根因：`enterApp()` 无条件再跑一次 `AccountStore.login()`，而 `Index` 的登录闸门
**已经保证走到这屏时分区状态是确定的**——真账号用户每次点主按钮都白等一次账号接口往返。
日志里还能看到该往返报 `Incorrect context parameter type` 后静默退回游客分区。

修法：`AccountStore.isGuest()` 为假时直接进；游客才登录并归户；
按钮加 `@State starting` → 文案「正在准备…」+ `disabled`，并做重入保护。
**实测 8s → 2.0s**（含脚本 0.4s 轮询与 dump 开销，实际接近即时）。

### 两条我判错、当场翻案的（记下来免得再犯）

1. 「点了两行景点，`已选 0` 没变」→ **不是缺陷**。`SpotPickPage` 源码写明是故意的：
   「整行可点会误触，点名字就改了优先级」，热区只收在右端 24vp 指示器上，
   点开官方 `bindMenu` 四档。**是我的探针假设"整行可点"错了。**
2. 随后我在屏4/屏8 之间跟丢了当前屏（`dump` 拿到的 `故宫博物院` bounds 其实是屏8 的），
   又去屏8 上找屏4 的指示器。**教训：每一跳都要先断言当前屏再动作**，
   不然就是在替一个不存在的缺陷改代码。屏4 的 `bindMenu` 交互因此**仍未验**。

### 顺带记下的一条设计疑问（未改，归用户）

屏4 分组头写「必去 · 7」（这是**景点库自带优先级**），而吸顶条写「已选 0」（这是**我的选择**）。
两个"必去/已选"挨着出现，用户很可能读成矛盾。要治得先定：分组头是否改叫
「库内标为必去」，或者干脆取消分组、只按我的选择计数。属文案与信息架构取舍，没替他拍。

### §5f 续：屏4 核心交互验通 + 补一条"怎么选"的引导

**验通**（此前一直挂着"未验"）：点行右侧 24vp 圆环 → 官方 `bindMenu` 弹出
`必去 / 想去 / 可去 / 取消标记` 四档 → 选「可去」后吸顶条 **`已选 0` 变成 `已选 1`**。
菜单材质与分隔线都是官方绘制，观感合格。
（上一轮记的"点两行没反应"确认是**我探针的错**：整行刻意不可点，源码写明了理由。）

**新发现并修掉一条**：这一屏的核心动作**只有那枚细圆环一个入口**，而屏上没有任何提示——
新用户站在这屏不知道该怎么"选"。补一行只在 `已选 == 0` 时出现的引导
「点每行右侧的圆环，标记必去 / 想去 / 可去」，选过一次即消失（不重复教育）。
真机复拍 `/tmp/g4hint.jpeg`：引导落在吸顶条内、进度轨完整可见，右侧圆环被指了出来。

**探针踩到的两条文本歧义（记下来）**：
- 断言串要用**该屏/该控件独有**的词。`必去` 会先匹配到分组头「必去 · 7」而不是菜单项；
  `设定出行基础参数` 是 HDS 顶栏**副标题**，根本不进 dumpLayout（本轮 §5b 已记过一次）。
- `bindMenu` 的菜单项在 dump 里**成对出现**（`必去,必去,想去,想去,…`），
  `find_bounds` 取第一个可能不是可见那个，导致点了没生效。用独有词（`可去`/`取消标记`）可避开。

## 5g. 屏15 真在途态首拍：修掉一条、**撤回一条我上一轮的「已修」**

走到这一步才第一次拿到屏15 的**真在途态**（前面几轮都是无 tripId 深链回落到的已结束行程，
hero 是空的）。用脚本从屏12 精确点中「旅行中」徽章所在卡（chip y=590 落在 Button
`[50,537][1086,1023]` 内）进入。

### 已修并复拍确认：没有通勤数据时不再画一条空腿

`nextLeg` 在下一段没有通勤信息时是空串，但**虚线段与交通图标照画**——
实拍就是「本地午餐」上方悬着一个**没有文字的步行小人 + 一段虚线**，读不出任何信息。
改成 `if (this.nextLeg.length > 0)` 才出整条腿。复拍 `/tmp/m15.jpeg`：悬空图标消失。

### **撤回**：§5b 续 3 里我写的「流光边光已修」不成立

上一轮我给 `ImmersiveSurface` 外层 Stack 补了 `borderRadius + clip(true)`，
在**空 hero 态**下复拍（`/tmp/z15_top.png`）看到紫弧消失，就记成「已修」。
这次在真在途态复拍（`/tmp/m15.jpeg`）：**边光仍然越过卡片上沿**，蓝→品红的一条带骑在卡片顶边上、
约 15px 悬在页面黑底里。空态那次是**卡片更矮、采样位置不同**掩盖了它——
又一次「测了个没生效的东西」。

又试了第二种假设：`secondEdgeFlowLight` 的 `endPos: -0.5` 是负值、可能往边界外画，
改成 `{0.5, 1}` 后复拍**无可见变化**，**已回退成与有据定稿一致的原值**，
并在代码注释里写明这条实验无效。

**两次改动都产生不了可见差别，不再叠第三次猜测。** 剩下的解释只有：
`HdsVisualComponent` 的 scene 走独立合成层，**不吃父容器的 clip**——
那么能真正消掉它的唯一办法是**不给这张卡上流光**（去掉 `ImmersiveSurface` 包裹）。
这属设计取舍（"沉浸光感"是有据定稿要的语言），**没替用户拍**。
受影响表面：屏15 hero、屏1 首启预览卡（后者已降为空态才出现）。

### 顺带确认生效的前几轮改动（真在途态）

- 「今日暂无安排」不再上下印两遍；空态下**「完成打卡」整颗不出现**（`/tmp/k15.jpeg` 文本序列里没有它）；
- 分组空态新文案「今天还没有走过任何节点，打卡后会出现在这里」在位；
- 屏12 的三态徽章在真数据上成立——同一列表里「旅行中」与「已结束」区分出来了。

### 屏14 触达面板仍未拍到

从屏10 的「加入日历提醒」进屏14 这条路，脚本在屏12/屏8/屏15 之间跟丢了当前屏两次
（断言串撞词），本轮没走完。**仍记为未验**，下轮第一优先。

## 5h. 屏14 触达面板与屏12b 空态拍到（最后两屏），并避免一次误报

**屏14 触达面板**（`/tmp/n14.jpeg`，从屏8 → 屏10 → 「加入日历提醒」进入）：
排版合格——衬线大标题 + 说明 + 三行开关（日历同步 / 行程卡片 / 提醒，各带一行说明）
+ 「写入内容预览」实框 + 两颗动作钮（仅本机保存 / 同意并写入）。**流程没坏。**

**差点误报的一条**：截图里三个开关**全蓝**，看着像"明示同意面板却默认替你授权"。
查代码才没写进缺陷：`syncCalendar=false`、`syncRemind=false`、只有 `syncCard=true`，
且 `aboutToAppear` 会回读 `CalendarSync` 的持久化 flags——
**这台机上三个都开过**（前几轮验收写过），所以显示为全是真实状态的还原，不是预授权。
**教训：开关态要先分清"默认值"与"回读持久化状态"再判。**

**屏12b 空态**（临时把 `TripsPage.reload()` 的赋值改成 `this.trips = []` 拍到，
`/tmp/o12b.jpeg`，**验毕已还原并 grep 确认零残留**）：
图标 + 「还没有行程」衬线标题 + 说明 + 「创建新行程」主钮，垂直居中，规格对。
拍到一处该修的：**空态下还挂着「搜索目的地或日期」**——没有可搜内容却摆一个输入框，
会让人以为控件坏了。改成 `if (this.trips.length > 0)` 才出。复拍还原后搜索框正常回到有行程的列表上。

**没改的一条（帧自身的规定）**：屏12b 说明文字折行后末行只剩「的路」两字，
属 §5.6 那类孤字——但源码注释写明「说明限宽 240 才能落回稿件的标准双行折行」，
是底稿定的双行形态，不是实现偏差，所以没动宽度。

**顺带**：屏14 「行程卡片」的说明「桌面常驻今日节点，随系统周期刷新（最小 30 分钟）」
折行后「钟）」单独掉一行，收短成「常驻桌面，随系统周期刷新（最小 30 分钟）」，
30 分钟这个诚实口径保留。

至此**逐屏实拍覆盖完成**：首页 / 屏2 / 屏3 / 屏4 / 屏5 / 屏7 / 屏8 / 屏9 / 屏10 / 屏11 /
屏12 / 屏12b / 屏14 / 屏15 / 屏16 / 费用 / 地图 都有真机截图证据。
未验项收窄到：屏6 生成中（进行中态拍不到，直达即落屏7）、屏13 桌面卡片（前几轮已验收）、
屏7 `goFix` 与 `ComingSoon` 换栈的完整链路、真机宽屏渲染。

### §5h 续：屏4「必去」一词两义（我自己留的裁决项，已定并验通）

查清后比我上轮的描述更具体：**同一屏上「必去」被当两个东西用**。
分组头 `必去 · 7` 来自 `Spot.tags` 里的 `SpotTag.MUST_SEE`（`rebuildGroups` 按库内标签分组），
是**景点库的分类**；而圆环菜单里的 `必去` 是**用户要做的标记动作**
（`priorityMenu` → `setPriority`）。于是出现「必去 · 7」与「已选 0」并排的矛盾读感。

**决定**：改动作侧，不动数据侧——`SpotTag` 是种子库与 RDB 里既有的语义，改它牵动数据层；
而**底稿帧本来就把这格写成 `aria-label="设为必去"`**，是实现时把「设为」丢了。
补回动词前缀后：分组头 `必去`（名词，库分类）／菜单 `设为必去 · 设为想去 · 设为可去 · 取消标记`（动作）。

真机复拍（`/tmp/q_menu.jpeg`、`/tmp/q_after.jpeg`）：
- 菜单四项读到 `设为必去 / 设为想去 / 设为可去 / 取消标记`；
- 选「设为想去」后吸顶条 **`已选 0` → `已选 1`**；
- **上一轮没验到的那条引导消失逻辑同时确认生效**——选过一次后
  「点每行右侧的圆环…」不再出现（不重复教育）。

### ComingSoon 换栈修复已验通

`--ps route BogusRoute` 直达：落点渲染 `未识别路由 [BogusRoute] | 还在准备中，稍后回来试试。 | 返回行程`，
点「返回行程」正常弹回首页（`有径 | TRACEABLE ROUTES | …`）。
`NavDestination.onReady(ctx => ctx.pathStack)` 这条通路成立。
（debug 包把路由名直接印进标题是**故意的**——dumpLayout 能读到是谁推了不存在的落点。）

### §5h 续 2：同类底部净空缺陷还剩三处，一并收口

上轮扫钉底层时漏了一类：**列表滚动区的底部预留**。`bottomScrollReserve = 94`
比 dock 实占的 112 少 18vp，凡是**把卡片排在列表末尾**的页，最后一张卡下沿会藏进 dock。
本轮补掉三处：屏8 `ItineraryPage`、屏9 `EditItineraryPage`、屏15 `OnTripPage`
→ 改用 `floatingDockClearance`。

**刻意保留 `bottomScrollReserve=94` 的两处及理由**：屏2 `TripInputPage` 与屏3 `PreferenceQAPage`
各有一条**钉底 CTA**，那条钉底自己已经让出 112，滚动区只需盖过钉底条自身高度（约 88），
94 是对的——再抬就是重复让位。

### 屏8 节点圆与站名之间补一档间距

`stopRow` 的站名 Column 原来**没有任何左内缩**：节点槽宽 24、圆占 22，
站名首字几乎贴着主轴圆（真机屏8 复拍可见）。补 `.padding({ left: sm })`。

### 屏7 修法行的 `goFix` 兜底路径已真机验通

`route=GenerateFailed` 直达（栈里没有屏3/屏4）→ 点「回选点页增减景点」
→ 落到屏4，dump 读到 `选想去的地方 | 第 3 / 5 步 · 选景点 | 已选 0 … | 点每行右侧的圆环…`。
即 `popToName` 落空时走 push 兜底这条分支成立。

### 本轮**没验到**的（设备中途被真人取用，已停手）

- 屏8 圆-字间距、屏8/屏9/屏15 列表末尾净空这两处**只过了编译与七把尺，没有真机复拍**：
  脚本在按 Back 之后 dump 到的是另一个 App 的界面（`推荐影片 | 经验分享 | #影视剧集`），
  按既有规矩**立即停止注入点击**，没有抢用设备。
  屏7 的 `goFix` 是在那之前验完的，证据有效。
- 屏6 生成中仍未拍到（直达即落屏7，进行中态窗口太短）。
- 屏9/屏15 的末尾净空与屏8 间距，**下次上机第一批复拍**。

### §5h 续 3：把这几轮归纳出的缺陷**当规则去扫**，而不是撞一个修一个

设备被真人占用、拍不了照的这段时间，正好做模式化扫描。三条规则来自本轮实际修过的缺陷：

| 规则 | 扫描方式 | 结果 |
|---|---|---|
| **① 空态不该挂搜索/筛选控件** | 全仓 `Search(` 只有两处 | 屏12b 已修；**屏5b `AreaMorePage`（全部区域）同一形态漏了**——loading 与「还没有这座城市的区域数据」两种状态下都还挂着搜索框。按同一判据补 `if (!loading && areas.length>0)` |
| **② 永不填充的装饰占位块该删** | 找「`Column()` 只有尺寸 + 底色、无子节点」 | 命中 5 处，逐一看过：卡片 2vp 主色分隔条、地图底色、`FlowSteps` 进度段、屏1 时间轴竖线——**都是真在干活的线/底**；只有 **屏4 行首那块 36×48 `surfaceSunken` 缩略位**是死的。`grep -c "Image(" SpotPickPage.ets` = **0**，`Spot` 契约里也没有图片字段，它永远是空灰块 → 删。这是同一类的第三处（屏8 行内、屏10 面板、屏16 行程纸之后） |
| **③ 无定高父级里的 `height('100%')`** | 全仓列 `.height('100%')` | 46 处命中，但绝大多数挂在 `List`/`Stack`/`Scroll` 这类**有确定父高**的容器上，是正常写法。这条规则**没法机判**，只能像屏8 `stopRow` 那样逐个看父级——所以没做 wholesale 改动，只记下：屏8 那处是肉眼实拍发现、不是扫出来的 |

**方法上的收获**：撞到一个缺陷就顺手修，只会修成点状；
把缺陷写成可 grep 的形态（空态+Search、无子节点+定高+底色），
才能在一次扫描里把同类清干净。屏5b 那条就是靠规则①捞出来的——
我早在屏5b 截图里见过那个形态，当时没修。

### §5h 续 4：又两条规则回扫 + 屏6 静态审（设备仍被占用）

| 规则 | 命中 | 判定 |
|---|---|---|
| **裸 `Text()`/`SymbolGlyph()` 直接挂 `onClick`**（应为官方 Button） | 2 处 | **都是假阳性**——`PrivacyConsentDialog:33` 与 `LoginView:132` 是**句内联文本链接**（`Span` 包不进 `Button`，`Text/Span.onClick` 就是 ArkUI 的正确写法）。**结论：「去自绘」那轮确实收干净了**，这条规则现在是清的 |
| **可点节点热区 < 44vp** | 12 处 | 11 处是扫描器把行内 22/28 的**徽章高度**算进了父链（徽章是标签不是控件）。**唯一真命中**：屏8 地图卡上的 `Button('全图')` 写死 `.height(28)`，低于平台最小热区 → 改 `LayoutTokens.minTouchTarget`(44)。旁边那枚 28 高的摘要 chip 是标签，两者不再等高是对的——**高度差本身就在说"这个能按"** |

**屏6 生成中**（一直没实拍、这轮做静态审）：版式成立——大标题 + 已选摘要 + 进度条 +
四段 stage 勾选 + 两张骨架卡 + 取消钮。骨架块是**会被替换的真占位**，不属于"永不填充的死块"。
但**钉底的「取消」和屏7 是同一处漏网**：只留 `xl`(24)，这一屏也在悬浮 dock 上 → 改 `floatingDockClearance`。

**未复拍清单（设备连续两轮被真人占用）**：屏5b 空态搜索框、屏4 缩略位删除、
屏8 圆-字间距、屏8/9/15 列表末尾净空、屏6 取消钮、屏8「全图」热区。
全部只过编译 + 七把尺。**下次设备空出来第一批一次性复拍这六处。**

## 5i. 第九把尺：`tools/audit_layout_patterns.py`（版式缺陷模式）

这几轮靠实拍**逐个**发现的版式缺陷，全部可以规则化。这把尺把五条规则固化下来，
下次不再靠撞。它量的是"这屏看起来对不对"，与前八把（色/字/几何/材质/字族/tnum/投影 +
设备侧对比度）不重叠。

| 规则 | 抓什么 | HEAD 上的结果 |
|---|---|---|
| **R1** | `Stack({alignContent: Bottom})` 的钉底块底部净空没用 `floatingDockClearance` | 0 |
| **R2** | 只有尺寸+底色、**没有子节点**的装饰空块（`Spot` 无图片字段那一类） | 0 |
| **R3** | 官方 `Button` 写死小于 44vp 的宽高（热区不足） | 0 |
| **R4** | 裸 `Text`/`SymbolGlyph` 挂 `onClick` 当按钮（应换官方 Button） | 0 |
| **R5** | 同一文件里出现多次的中文字面量（「今日暂无安排」印两遍那一类） | 13（**提示级，不卡退出码**） |

**尺自身的三条设计约束（都是本仓库既有教训）**：

1. **先反证再信 0**：`--self-test` 注入一个已知阳性（20×20 的 Button + 裸 Text.onClick），
   确认 R3/R4 抓得到才算尺可用。跑法：`python3 tools/audit_layout_patterns.py --self-test`。
2. **豁免必须带断言**。R1 有两条豁免（`MapPage`、`SpotPickPage`）：它们的 Bottom Stack
   只有**一个**子节点——一个装着内容与钉底块的容器列，静态分不出"容器"与"钉底块"。
   豁免只在**文件里确实存在 `floatingDockClearance`** 时才放行；
   实测把 `MapPage` 那行 margin 删掉，尺立刻从 0 变 1 报红，还原后归 0。
   **不带断言的豁免等于把规则关掉。**
3. **R1 前两版报了 12 处、6 处噪声**（先扫整棵子树、后只看最后一个直接子节点），
   都不是真缺陷。尺报噪声比不报更糟——会被当成"已知豁免"忽略掉真问题。

**R5 为什么不卡退出码**：一个标签在顶栏和正文各出现一次是正常写法
（「我的行程」「退出登录」「新建行程」都是），它只能提示"去核对是否同屏重复展示"，
不能机判。当前 13 处逐条看过，真缺陷（屏15「今日暂无安排」）已修，
剩下的都是合法复用。

**尺的计数口径变了**：静态尺从七把变**八把**（新增 layout_patterns），
加设备侧对比度尺共**九把**。`hooks/pre-commit` 仍只跑构建闸（hook 不随仓库分发），
**改过版式后手动跑这一把**。

## 5j. 本轮新加配色的离线精算对比度（不依赖设备）

这几轮我新增了若干前景/底色配对，**都没算过对比度**——设备侧的 `audit_contrast.py`
要 dump + 截图，设备被真人占用时跑不了。改用纯离线精算：
读 `resources/{base,dark}/element/color.json`，**带 alpha 的先按 canvas 合成**再算 WCAG 比值
（与既有教训一致：像素读数要先按 color.json 精算复核）。
注意资源名是 snake_case，`ColorTokens.primaryTint` 要映射成 `primary_tint` 才查得到。

| 配对 | 浅色 | 深色 | 判定 |
|---|---|---|---|
| 屏12 徽章「旅行中」`onPrimary` on `primary` | 5.57 | 5.14 | AA 正文 ✓ |
| 屏12 徽章「未出发」`body` on `primaryTint` | 5.89 | 6.27 | AA 正文 ✓ |
| 屏12 徽章「已结束」`muted` on `surfaceSubtle` | 4.88 | 5.40 | AA 正文 ✓ |
| 屏12 卡「总花费」`ink` on `canvas` | 17.89 | 16.76 | AA 正文 ✓ |
| 费用页「已用 N%」`muted` on `surfaceElevated` | 5.10 | 5.74 | AA 正文 ✓ |
| **屏4 引导小字** `muted` on `surfacePanel` | **4.76** | 5.06 | AA 正文 ✓（**最紧的一组**） |
| 首页 最近行标题 `ink` on `surfaceElevated` | 16.71 | 14.91 | AA 正文 ✓ |
| 屏2 未选人数钮字色 `body` on `surfaceElevated` | 6.40 | 7.05 | AA 正文 ✓ |

**结论：八组全部过 AA 正文级（≥4.5），无需改色。**
最紧的是屏4 引导小字 4.76——它是 `overline`(11vp) 档的最小字，
离阈值只有 0.26 余量；**以后若调 `muted` 或 `surfacePanel`，这一组要第一个复算。**

**方法记下来**：`audit_contrast.py` 需要设备，但**配对对比度可以离线精算**，
设备被占用时不必停下这条验证。

### §5j 续：最紧的两组**决定不换色**（附理由，别下次又来回改）

备选算过了：`body` 替 `muted` 会把屏4 引导从 4.76/5.06 抬到 5.97/6.21、
屏12「已结束」徽章从 4.88/5.40 抬到 6.13/6.63。**决定不换。**

理由：这两处按契约都是**次要说明/状态标签**，`muted` 是标签色、`body` 是正文色；
换成 `body` 会让一行 11vp 的提示在视觉上与正文抢层级——
那是用对比度换来的**排版倒退**，而 4.76/4.88 本身已过 AA 正文级（≥4.5）。
**若以后 `muted` 或 `surfacePanel`/`surfaceSubtle` 任一处被调暗，这两组要第一个复算**，
届时优先降底色的明度、而不是升字色。

## 5k. 零消费方 token 全量清点（44 项，逐条给理由，防止下次重复调查）

`design/` 七个 token 文件里 **44 个键没有任何消费方**。逐条分三类，**只有第三类需要动**：

### ① 契约镜像——必须存在，几何尺逐条比对 DESIGN.md（28 项，不动）
`LayoutTokens`：`gridBaseline` `itemGap` `blockGap` `sectionGap` `titleBarHeight` `tabBarHeight`
`floatingDockWidth` `floatingDockSideMargin` `itinerarySpineWidth` `postCardPadding`
`composeGenreCardHeight` `composeBodyHeight` `profileStatWidth` `tabItemWidth` `tabSideMargin`
`tabBottomGap` `safeAreaFallback`；`SpaceTokens`：`lgLoose` `twoXl` `threeXl` `fourXl` `bottomReserve`；
`RadiusTokens.none`（0 圆角=默认）；`ShadowTokens.contact` `popover`（理由见 §4f 投影那一节）。
**删它们会让 `audit_geometry.py` 报「契约缺 token 字段（必须补）」**——尺要求契约的每一项都在表里。

### ② 被官方组件接管——不是死代码，是"官方替我们做了"（9 项，不动）
`MotionTokens` 全部 7 键：契约要「主按钮按下 scale(0.97)+140ms」，
`YoujingButton` 头注释写明 2026-10-24 去自绘时**刻意删掉手抄实现**，
改由官方 `Button` + `stateEffect` 提供（手抄那份在深色档偏色）。
`LayoutTokens.mediaThumbWidth/Height` `spotThumbWidth/Height` 4 键：
本轮删掉三处永不填充的缩略位后归零，但它们是契约 `media-aspect-ratio` 那一族的镜像值，
**留着当镜像，不是留着当待接线的坑**。

### ③ 真该删——已删（1 个文件）
**`design/FontTokens.ets`**：8 键全零引用、无任何尺读取，而且头注释写着
「pages/components 中 fontSize/fontWeight 一律引用本文件，禁止裸数值」——
**与实际约定（`TypeTokens` 角色档）直接冲突**，值还对不上（12/14/16/20/24 vs 12/14/16/18/21/32）。
一个谎称自己是唯一字阶来源的死文件，是下一位开发者（或下一次的我）最容易踩的坑。
已 `git rm`，并同步改 `Docs/ARCHITECTURE.md` 两处指向它的句子
（分层表 `design/` 行 + §禁止裸样式值，改成列全七个真在用的 token 文件、
并写明字号字重走 `TypeTokens` 角色档、不许自由组合）。
删后 `assembleHap` 通过、七把尺照旧 exit 0。

### 顺带记下的一条误判
我一度以为"`MotionTokens` 零消费 = 契约要求的按压反馈没实现"，
差点去 `YoujingButton` 上加回 `scale(0.97)`。读了文件头注释才发现是**官方组件接管**、
且手抄版有深色偏色的实测理由。**查过才没把一处正确的实现改错。**

## 5k0. 屏号对照表（**别再拿"屏11"指两个不同页面**）

本轮自查发现文档里"屏11"被混用过：底稿 **屏11 = 费用视图**（`ExpensePage`），
而我有多处把 `AreaMorePage`（全部区域）写成"屏11"——那个页面在底稿里是 **屏5 的下一级（屏5b）**。
以下是对照表，后续所有条目按这张表写。

| 底稿屏号 | 页面 | 代码文件 |
| --- | --- | --- |
| 屏1 | 首启与静默登录 | `LoginView` / `YoujingStartPage` |
| 屏2 | 行程基础输入 | `TripInputPage` |
| 屏3 / 屏3b | 偏好追问（单选态 / 多选变体） | `PreferenceQAPage` |
| 屏4 | 景点选择 | `SpotPickPage` |
| 屏5 | 住宿区域选择 | `StayPickPage` |
| 屏5b | 全部区域（搜索/选片区） | `AreaMorePage` |
| 屏6 | 行程生成中 | `GeneratingPage` |
| 屏7 | 生成受阻 | `GenerateFailedPage` |
| 屏8 | 行程时间线主视图 | `ItineraryPage` |
| 屏9 | 行程时间线编辑态 | `EditItineraryPage` |
| 屏10 | 单个活动节点详情 | `ItineraryPage` 详情面板 |
| 屏11 / 屏11b | 费用视图 / 超支态 | `ExpensePage` |
| 屏12 / 屏12b | 我的行程 / 空状态 | `TripsPage` |
| 屏13 | 万能卡片 | `widget/TodayTripCard` |
| 屏14 | 持久化与系统触达 | `ItineraryPage` 的触达面板 `systemAccessSheet()`（bindSheet，**不是独立页面**） |
| 屏15 | 旅行中模式 | `OnTripPage` |
| 屏16 | 分享与导出 | `SharePage` |

（`ls ~/Pictures/有径/有径-设计底稿-v1/frames` 是权威清单；每屏另有 `*dark_*` 同名深色帧。）

> 表里这行「屏14 → `SettingsPage`」是错的（本轮改）：全仓没有 `SettingsPage`，
> 我按这张表去真机上找"设置页入口"，在「我的」页顶栏找了半天落点、白点了一次屏幕。
> 屏14 是屏8/屏10 里那颗「加入日历提醒」唤起的**半模态面板**，§5h 早已实拍过。
> **教训：对照表指到不存在的文件时，先 `grep` 代码里帧的字面标题，别按表找入口。**

## 5l. 主链流程复审（不截图，纯读跨页跳转）——查出 1 个 P0 并修

前面各轮都在**逐屏看一屏之内**的问题。这一轮换了个口径：**顺着用户的动线读代码**，
从首页 → 屏2 → … → 屏8 → 屏10/15/16，只问一件事「这一步点下去，用户到底到哪了」。
这类缺陷单屏实拍是看不出来的——按钮本身画得没问题，**点了没反应**要跨页才现形。

### P0（已修）：从「我的」页签点开行程后，这一屏的操作按钮全部失效

证据链（逐条 `grep`/读码核对，不是推测）：
- `pages/TripsPage.ets:314` 用的是 `this.pathStack`（= `MINE_NAV`）push `OnTrip` / `Itinerary`；
- `pages/ItineraryPage.ets:46`、`pages/OnTripPage.ets:91` 却都写死
  `private pathStack: NavPathStack = APP_NAV;`；
- 于是 `ItineraryPage.ets:1154`(全图) `:1205`/`:1274`(编辑) `:1270`(分享) 与
  `OnTripPage.ets:646`(记一笔费用) **把路径推到了当前根本不可见的 tab-0 栈上**
  ——屏照常渲染在「我的」栈里，点这些按钮界面一点动静都没有。

这和之前 `enterPlanningFlow` 修的是同一类错，**当时只修了入口，没修这两页**。
修法与 `ComingSoonPage` 同法：让页面从自己的 `NavDestination` 拿栈——

```ts
.onReady((ctx: NavDestinationContext): void => {
  this.pathStack = ctx.pathStack;
})
```

保留 `APP_NAV` 作字段默认值，深链直启（`--ps route Itinerary`）行为不变。

### P0-2（已修）：App 已存活时，深链只改页签索引、不切页签

`EntryAbility.routeTo()` 原来只 `AppStorage.setOrCreate(TAB_INDEX_KEY, tab)`。
`TAB_INDEX_KEY` 是 `HdsTabs` 的**初始**页签（`Index` 头注释记过实测：冷启只能靠 `index` 初值），
运行期改它不切页签 → 卡片/快捷入口点进去停在首页。补 `requestTab(tab)` 走
`Index` 的 `@Watch` → `changeIndex`；冷启时 `@Watch` 不为初值触发，两条路不打架。

### P2（顺手清掉的两处死块）
- `ItineraryPage.ets:849` 屏10 数据面板的第四格「门票费用」值**恒为「—」**——
  `Activity` 模型里没有票价字段，永远填不上，实拍就是面板中一个假数据位。删（三格比四格稳）。
- `MapPage.ets`（改动前 :266）一个字面 `Row() {}` 空容器，什么都不装。删。

### 尺子自己的三个修正（`tools/audit_layout_patterns.py`）
- **R2 第一版扩展报了 17 处假阳性**：`Column() {` 花括号式容器被 `chain_at` 连子树一起吃进来。
  拆成两条精确判定——(a) 自闭式 `Column()` 只带尺寸+底色；(b) `Column() {` 且同缩进的下一非空行就是 `}`。
- R5（重复字面量）**只是信息，不该卡退出码**——改为无条件不门控，删掉 `--allow-r5` 开关。
- 反证阳性样本不能喂 `MapPage.ets`（它在 R2 白名单里，等于自问自答）；
  改喂 `ComingSoonPage.ets` 后 R2 抓得到、还原后归 0。**尺子报 0 前先确认它抓得到东西。**

### P1 之一（已修）：规划链**重进**会把前面的选择清掉
（触发条件见 §5m 的更正：不是"往前再返回"，而是"被 pop 掉之后重进"。）
- `PreferenceQAPage.ets:31` 的答案数组是字面量初值 `['leisure','comfort','public','']`，
  `syncDraft()`(`:79`) 只往 `PlanDraft` 写、`aboutToAppear` 从不读回来 →
  退回屏2 再点「开始规划」，四道题全回默认档。
  改为 `aboutToAppear` 从草稿起答（`PlanDraft.fresh()` 在首页进链时置空实例，
  所以**新行程仍从默认档起**，两条要求不冲突）。
- `SpotPickPage` 同病：`:181` 把标记写进 `selectedSpots`，回来不还原 `priorities` →
  圆环全空、底部「已选 N」归 0。改为载完景点按草稿回填，并用 `some(s.id===...)`
  滤掉本次景点集里已不存在的 id（换目的地后不会带出幽灵计数）。
- `StayPickPage` 原来是**无条件** `selectedId = list[0].area.id`——从后一步回来换住宿，
  选中态跳回第一个候选。改为优先还原 `PlanDraft.selectedArea.areaId`（命中候选列表才用）。
- 屏2 `TripInputPage` 查过：`:43-48` 本来就从 `PlanDraft.basic` 起值，**这屏没问题**。

### P0 补充（同一类错，复审时漏了两页）
`EditItineraryPage.ets:34` 也写死 `APP_NAV`，而它在 `:219`/`:243` 用 `this.pathStack.pop()`——
屏8 迁到任意 tab 栈之后，从「我的」进来的编辑页**返回按钮弹在看不见的栈上**。
同法补 `onReady`。`SharePage.ets:37` 的 `pathStack` 字段全页零使用（死字段），删。

### P1：查出来了、**这一轮还没动**的
1. **费用页无行程时的空态文案仍在引导一个不可达的操作**——`ExpensePage.ets:136-147`
   从 dock 进来没有行程上下文时会退到最近一条行程（这个处理是对的），
   但本机一条行程都没有时只 `Logger.info(...)` 保持空态，页面文案（`:557`）仍是
   「还没有记账，下面记一笔后这里会出现分类」——**没有行程时"记一笔"落不了地**，
   该引导的是「先规划一条行程」。（这条只读了码，没真机验过记账失败路径。）
2. `ACTIVE_TRIP_KEY` 写 5 处（`ItineraryPage:80`/`OnTripPage:147`/`Index:96`/`ExpensePage:157`/`EntryAbility:259`）、
   真读取 0 处（`Index:90` 只判空），与 `AppNav.ets:23` 注释承诺的「当前活动行程」不符——**没有消费方，不算落实**。
3. 三个 tab 根页（`MapPage:58`/`ExpensePage:127`/`YoujingStartPage:58`）只在 `aboutToAppear` 取一次数：
   在别处新建/编辑完行程再切到这些页签，看到的还是进入时那份数据。

### 未验（设备未复拍，不写「已修」）
上面两个 P0 只做了**读码级**验证；真机要点：从「我的」页签点开一条行程 → 依次点
分享 / 编辑 / 全图 / 记一笔，确认都真的跳转。`BUILD SUCCESSFUL` + 八把尺 exit 0 只证明能编译。

## 5m. 真机验收 §5l 的两个 P0（装机实测，非读码）

装机 `entry-default-signed.hap`（md5 `168ab372…`），全程 `uitest dumpLayout` 断言屏幕，
每一步点击前重新 dump 确认前台。**动线：dock「我的」→ 点开一条行程**（走 MINE_NAV，
正是修前会失效的那条路）。

| 按钮 | 修前 | 实测结果 |
| --- | --- | --- |
| 屏8「全图」 | 推到不可见的 tab-0 栈 | ✅ 跳到地图页，站点栏出现「全程 / Day 1 / Day 2 / Day 3 + 3 个节点」 |
| 屏8 顶栏分享 | 同上 | ✅ 进屏16「分享与导出」，副标题「北京 3天2晚 · 8 个节点」 |
| 屏8 菜单「编辑行程」 | 进得去，但**编辑页的「完成」弹不回来** | ✅ 进编辑页 → 点「完成」→ 回到屏8（`EditItineraryPage` 的 `pop()` 走对了栈） |
| 屏15「记一笔费用」 | 同 P0 | ✅ 进费用页，且带对了行程上下文「北京 · 2026-10-27 – 2026-10-29」 |

`§5l` 末尾那段「未验」到此销账：四个按钮全部实测通过。

### 一处**我自己写错的因果**，趁有证据改掉
`§5l` 原话是「用户走到屏4 想改偏好、回退进这屏，四道题全回默认档」。**这句不对。**
真机：屏4 → 返回 → 屏3，标题栏仍是「问题 4/4」——
`NavDestination` 往前推时**前一屏实例不销毁**，所以"往前再返回"这条路本来就不丢状态。
真正丢的是**被 pop 掉之后重进**：组件是全新实例，初值只剩字面量。

于是补了一个能区分两种解释的判据（不是"看着没坏就算过"）：
先把屏4 pop 掉、再从屏3 前进一次，拿到**全新实例**——
实测新实例显示 **「已选 1 / 可用 3 天」**，而 `priorities` 的代码初值是 `[]`，
只有从草稿还原才可能出 1。**这条才算验到点上。**

### 顺带发现的一个 P2（未修，先记账）
子页面上**再点当前页签的 dock 项没反应**：从「我的」进到屏8 后，dock 仍高亮「我的」，
此时点「我的」既不弹回列表根、也没有别的反馈（实测两次，屏幕不变）。
系统级惯例是"重点当前页签 = 回到该页签根"。修之前要先确认
`HdsTabs` 有没有同页签重复点击的回调（`onChange` 在同值时不触发），
**没确认前不动**——这条属于"点了没反应"家族，但和 P0 不同源，别混着记。

### 这一屏顺带拍到的是深色档
01:24 系统自动切了深色，屏15/费用页/编辑页的深色帧是**这轮第一次拍到**：
卡片、进度条、图标、dock 都跟着翻，未见"深色下隐身"的元素。
（`hdc file recv` 才是收文件的写法，裸 `hdc recv` 静默不落地，害我第一次读图失败。）

## 5n. tab 根页切回不重取数据（P1 之一，已接线，**真机未验**）

主链复审 P1 第 3 条：四个 dock 根页只在 `aboutToAppear` 取一次数。
在别处新建/编辑完行程、或记完一笔费用，切回对应页签看到的还是第一次进入那份。

接线走的是**这工程里已经验通的那条反应式通路**（`TAB_SWITCH_KEY` → `Index` 的
`@StorageProp + @Watch`），没有引入 `onVisibleAreaChange` 之类本页未验过的 API：

- `AppNav.ets`：新增 `TAB_SHOWN_KEY` + `announceTabShown(index)` + `isTabShownTick(value, index)`；
  值带时间戳，所以同一页签连切两次也能触发 `@Watch`。
- `Index.ets:186` `HdsTabs.onChange` 里广播一条（`onChange` 只在**真的换页签**时触发，
  重点当前页签不触发——那条是 §5m 记的另一个 P2，没混在这里修）。
- 四个根页各加 `@StorageProp(TAB_SHOWN_KEY) @Watch('onDockShown')`，
  **序号对上才重取**：首页 `reloadRecent()`（把原来写在 `aboutToAppear` 里的取数抽成方法）、
  地图/费用 `reload()`、我的 `reload().catch(...)`。

`BUILD SUCCESSFUL`、八把尺 exit 0。**真机行为未验**——设备这一时段疑似有人在用
（Back 退出后落在别的 App 界面上），不抢设备。待验三件事：
① 切页签不闪、不重复取数；② 新建一条行程后切回「我的」和「行程」能看到它；
③ 深色档下切页签无额外白帧。

## 5o. 逐屏实拍收口：屏5b（全部区域）两处真缺陷（dock 压内容 + 词中间断行）

沿"切页签 → 走链 → 逐屏拍"的路子把 §5m 遗留的复拍项补做。深色档，
帧存 `~/Pictures/有径/走查帧-2026-10-27/`（`/tmp` 重启即空，别再往那儿放）。

### 已验通过的复拍项
- **屏8 列表底部净空**（`g8_bottom`）：末站「颐和园 18:30」整行停在 dock 之上，留白充足。
- **屏15 列表底部净空**（`g15_bottom`）：内容早于 dock 结束，无重叠。
- **屏4 行版式**（`h4_rows`）：删掉 36×48 空缩略位后，行内是"名字+需预约 / 区·停留建议 / 预约规则"
  三行 + 右侧圆环，没有空洞也没有挤压。
  顺带**排除一条幻影**：我目视以为那条灰色信息带右边缘被切，逐行取像素后
  确认 `x=0…1080` 整条同色 `(40,39,44)`，看到的是下方列表面板的边，不是缺陷。
- **屏8「全图」热区**：`dumpLayout` 量到 `[962,1011][1086,1149]` → 高 138px ÷ 3.125 = **44.2vp** ✓。

### 缺陷一：屏5b 最后一整行压在浮动 dock 底下（`h11_areamore`）
dock 是覆盖层，`AreaMorePage` 的 `List` 只给了左右 padding，没给底部净空 →
末片区域的「到机场 30 分钟…」整行画在 dock 毛玻璃底下。
全工程扫了一遍 `floatingDockClearance`：**14 个页面里只有这一屏是 0 次**，
补 `bottom: LayoutTokens.floatingDockClearance` 一处收口。
复拍 `i11_bottom`：末行「郎园-四惠东」完整停在 dock 之上 ✓。

### 缺陷二：屏5b 每行元信息在**词中间**断行（`h11_areamore`）
`舒适档 · 地铁 14号线/16号线 · 锚定 丽/泽商务区` ——CJK 排版引擎会在任意字之间换行，
三件信息挤一条 `maxLines(2)` 长句，就会把站名劈成两半。这正是"排版交错"的形态之一。
改成**一行只放一件语义完整的事**。

**这里踩到一个自己造出来的新缺陷，记下来别再来一遍**：
第一版三行都设 `maxLines(1)+Ellipsis`，复拍发现第三行「到机场 45 分钟 · 到火车站 12 分钟 ·」
后面的**餐饮密度整条被省略号吃掉**——把"劈词"换成了"丢信息"，没修好。
于是量了文本列右边界（749px）：把餐饮密度**挪到有富余的锚定行**，
再复拍逐行取 bounds：档位+地铁 544~655、锚定+密度 614~727、机场+火车站 657~678，
**顶到边界的行数 0**。信息一条不少，也没有半截词。
（判"截断修好了"必须两侧都量化：既看有没有劈词，也看有没有被省略号吞掉。）

### 顺带澄清一条被误判成缺陷的行为
编辑一条行程后它在「我的行程」列表里**跳到了第一位**。查下来不是 bug：
`TripDao.listSummaries` 就是 `ORDER BY t.updated_at DESC`（最近改动优先），
而 `saveTrip` 是删行重插并写 `updated_at = Date.now()`。规则自洽，**不改**。
唯一的毛刺是"没改内容只点完成也会重排"——属可接受语义，留档防止下一轮来"修"它。

## 5p. `ACTIVE_TRIP_KEY` 从「写 5 读 0」变成真有人消费（双向实测）

§5l 记的 P1 第 2 条：这个键被 5 处写入，但除 `Index:90` 判空外无人读，
`AppNav.ets:23` 注释却写着「地图/费用 tab 的根页靠它选路」——**注释承诺的行为没落实**。

接法（不引入新机制，仍走 §5n 那条已验通的 `@Watch`）：
地图/费用两个根页在切回时，若自己是 `rootMode`（不是被 push 带参进来的），
且 `activeTripId()` 与自己当前 `tripId` 不同，就把上下文换成后者再 `reload()`。
效果：**刚看完行程 B 再切「地图」/「费用」，看到的是 B**，
而不是永远停在第一次进页签时按 `updated_at DESC` 兜底挑中的那条。

真机双向实测（同一份安装包，`aa start` 冷启后走）：
| 步骤 | 期望 | 实测「费用」页标签 |
| --- | --- | --- |
| 我的 → 打开 10-27 那条 → 返回 → 切「费用」 | 跟到 10-27 | `北京 · 2026-10-27 – 2026-10-29` ✓ |
| 我的 → 打开 07-01 那条 → 返回 → 切「费用」 | 跟到 07-01 | `北京 · 2026-07-01 – 2026-07-03` ✓ |
两条都是**判别性**的：列表按 `updated_at DESC` 排，`rows[0]` 恒为 07-01 那条，
所以第一行（10-27）只有"跟随最后打开的行程"才可能出得来。

## 5q. 重点当前页签 = 收回该页签根页（§5m 那条 P2 已修，实测通过）

`HdsTabs` 的 `onChange` 在**同值**时不触发，所以"再点一次当前页签"原来什么都不会发生
（从「我的」点开行程后再点「我的」，界面纹丝不动，用户读到的是"dock 坏了"）。
SDK 声明文件 `components/hds_tabs.json` 里翻出继承自 `Tabs` 的 **`onTabBarClick`**，
它每次点击都触发 → 用它实现系统惯例。

```ts
.onTabBarClick((index: number): void => {
  if (index !== this.currentTab) { return; }
  const stack: NavPathStack = stackOfTab(index);
  if (stack.size() > 0) { stack.clear(); }
})
```
`AppNav.stackOfTab(index)` 按页签序号取栈（`stackOfRoute` 是按路由名，这里用不上）。
用 `clear()` 而不是 `popToIndex(0)`：根页不是 NavDestination，
`popToIndex(0)` 只会停在第一条被 push 的子页上，收不回根。

真机实测（冷启后）：
`我的`根 → 点开行程（屏8 压在 MINE_NAV 上）→ **再点「我的」→ 回到「我的行程」根** ✓；
`行程`/`我的` 正常切页签不受影响 ✓。

### 顺带挖出一条更大的流程缺口（**未修，需要产品决定**）
主链**没有"继续未完成的规划"这条路**：`YoujingStartPage.enterApp()` 一进来就
`PlanDraft.fresh()`，所以只要回到首页点「开始规划新行程」，之前走到屏3/屏4/屏5 的草稿必然作废。
配合这条新加的"重点页签收回根页"，用户中途误触 dock 就会看到进度没了。
两条走法，得用户拍：
① 首页在草稿非空时把主 CTA 换成「继续未完成的规划」，走 `enterPlanningFlow` 直接落到当时那一屏；
② 保持"每次都是新规划"，但把 dock 收回根页对主链页签（行程）豁免。

## 5r. 费用页「没有行程」时不再引导一个点了没反应的动作

§5l 的 P1 第 1 条。原来本机没有行程时只 `Logger.info(...)` 保持空态，
页面照样挂着「还没有记账，下面记一笔后这里会出现分类」和一颗「记一笔」按钮——
而 `saveExpense()`(`:230`) 在 `trip === null` 时**直接 return**，
用户点了没有任何反馈（又一个"点了没反应"）。

改法：`reload()` 的 `rows.length === 0` 分支置 `noTrip`，页面上
- 分类支出空态文案换成「还没有行程，先规划一条才能记账」；
- 那颗「记一笔」整颗换成主按钮「开始规划新行程」，走 `enterPlanningFlow('TripInput')`
  ——和首页同一个入口，先切回「行程」页签再 push，不会把主链推进不可见的栈。

**验收边界（别当成已验）**：`noTrip` 分支**未真机验过**——这台机器上有 20 条真行程，
要复现"零行程"只能删掉用户数据，而清不清归用户、agent 不代删。
已验的是**没有回归**：有行程时费用页正常（文案仍是"还没有记账…"、
「记一笔」点开记账面板出现「金额与名称只存本机行程」+「保存」✓）。

## 5s. 第一次拍到宽屏真机帧（Mate X7 展开 2210×2416 ≈ 707vp → `md` 档）

之前所有轮次的界面证据都是 1136×2690 的手机帧，**宽屏/折叠屏零帧**。
这轮把本机已有的模拟器启起来补上了第一帧。

**可复现的启法**（下次别再重新摸索）：
```sh
cd ~/.Huawei/Emulator/deployed && nohup \
  /Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator -hvd "Mate X7" &
# 约 90s 后 hdc list targets 出现 127.0.0.1:5555
hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 127.0.0.1:5555 shell "aa start -b com.youjing.app -a EntryAbility"
```
（`Emulator` 会自己补 `-bootmode restart_coldboot<uuid>`；日志里那句
`GLib: g_hash_table_remove_all` 是无害告警，不影响启动。）

### 拍到的一条宽屏缺陷：屏1 登录页**完全没有宽度上限**
帧：`~/Pictures/有径/走查帧-2026-10-27/{w1,o1,p1}_*_x7.jpeg`。
`LoginView` 的根 `Column` 是 `.width('100%') + padding(pagePaddingWide)`，
在 707vp 宽下：主按钮「华为账号一键登录」拉成一条横贯整屏的巨型胶囊，
说明文字一路排到右边缘。工程里别的长表单都走了
`longFormMaxWidth(bp, contentMaxWidth)` 上限（屏2、协议正文），**这屏漏了**。

修法已想清楚但**这轮没动手**，因为改完验不了（下一条）：
不能给根 `Column` 加 `constraintSize`——根要铺满整屏当 `canvas` 底色，
一收窄两侧就出现色带。正确做法是在 `Blank()` 之后套一层
`Column(){ … }.width('100%').constraintSize({ maxWidth: longFormMaxWidth(this.bp, LayoutTokens.contentMaxWidth })`
并把根的 `alignItems` 改成 `Center`（手机档 `longFormMaxWidth` 返回 `'100%'`，行为不变）。

### 一条**没有定论**的观测，别当缺陷记账
模拟器上想进主界面看宽屏的 首页/我的/屏8/屏4，卡在屏1 的同意闸门：
按 `dumpLayout` 读到的 Checkbox 真实 bounds `[76,1815][151,1890]`、
点它的中心 `(113,1852)`，**回读 `checked` 仍是 `false`**，
于是「暂不登录，使用本机游客空间」按 `!agreed` 保持禁用（`LoginView:64`）——
**这个禁用本身是对的**（明示同意、不默认勾选）。
没定论的是点不动：可能是 `uitest uiInput click` 在这台模拟器上的注入问题
（同一台机器上「同意并继续」这颗大按钮点是有效的），也可能是
`Checkbox` 只有 24vp 命中区在宽屏档下的真实缺陷。
**两种解释都还没排除，所以不改代码、不写"已修"**；下一步该做的是
在真机上做同一个动作做对照（真机 density 3.125、同一份代码）。

### 宽屏还欠的帧
首页 / 我的（`List.lanes` 在 md 档该出两栏）/ 屏8 时间轴 / 屏4 行 / 费用页零行程态
——都堵在上面那道同意闸门后面。`noTrip` 分支本来在这台零数据的模拟器上可以顺手验掉，
同样没进去。**这是下一轮的第一优先级**：先进得去，再谈宽屏收口。

### §5s 补：屏1 宽屏上限**已接并拍到帧，但效果不够**（要用户拍一个数）
`LoginView` 加了断点上限：根 `Column` 保持铺满整屏当底色，
在 `Blank()` 之后套一层内容 `Column`，给它
`.constraintSize({ maxWidth: longFormMaxWidth(this.bp, LayoutTokens.contentMaxWidth) })`
并把根 `alignItems` 改成 `Center`。手机档 `longFormMaxWidth` 返回 `'100%'`，**行为不变**。

Mate X7 展开实测（帧 `q1_login_x7.jpeg`）：内容列从"整屏宽"收到 `contentMaxWidth`
（bounds 量到正文行 190…2148 ≈ 626vp，整屏 707vp）并居中 ✓，
但**目视仍然太宽**——说明文字一路排到右边缘、主按钮还是一颗横贯的巨型胶囊。
原因不在实现：`contentMaxWidth` 这个契约值本身就有 626vp，
而 707vp 的 md 档只比它宽 80vp，"套上限"能省的就这么点。

**要更窄只有两条路，都归用户定**：
① 登录/协议这类**单列表单**另用一个更小的上限（工程里现在没有这个档）；
② 沿用 `contentMaxWidth`，接受宽屏就是"一行能放更多字"的观感。
我不会为了让截图好看去改 `~/Pictures` 里那份契约值。

## 5t. 回看已拍帧又抓到同族缺陷：屏5 的站名也被劈成两半

不是新走查，是**把上一轮已经拍下来、但没逐张看过的帧翻出来看**（`h5_stay.jpeg`）。
屏5 卡片那行 `舒适档 · 地铁 6号线/8号线 · 锚定 南锣鼓巷` 实拍成
「锚定 南锣鼓/巷」——和 §5o 屏5b 是**同一族**（三件信息挤一条 `maxLines(2)` 长句，
CJK 在词中间断行）。当时只修了用户指到的那一屏，**同族的另一屏还在**，
这正是"修截断类缺陷要一次量化每一侧"的老毛病又犯了一次。

改法与屏5b 一致：`areaMeta()` 拆成 `areaMetaTop()`（档位·地铁）与
`areaMetaAnchor()`（锚定·站名），各 `maxLines(1)+Ellipsis`，一行只讲一件事。
原来那句注释说"最长 30 字，单行必截故给两行"——**拆完就不成立了**，
最长的一条（`锚定 大鹏中心(公交接驳)`）单行放得下，所以那两行注释一并改掉。

### 顺带把布局尺 R4 的"写死行号白名单"拆了
给 `LoginView` 加宽度上限后行号一移，R4 立刻报出一条**假阳性**
（`LoginView.ets:139 裸 Text 挂 onClick`）——因为白名单是按 `(文件, 行号)` 记的。
根因是匹配器用 `chain_at()` 把整棵子树一起吃进来，于是
`Text() { Span('《隐私政策》').onClick(...) }` 这种**句内联链接**（ArkUI 唯一写法）也被误判。
改成只查节点**自己的** `.属性` 链（`_own_attr_chain`：带子块就先跳到配对的 `}` 之后再收），
白名单清空。**自测仍然抓到注入的 R4 阳性**，不是把尺子调哑。

尺子一干净，就露出一条**真的**该改的：`PrivacyConsentDialog.docLink`
确实是裸 `Text(label).onClick`。换成官方 `Button` + `ButtonStyleMode.TEXTUAL`
（保留链接观感，把热区和 `stateEffect` 交回官方）。
真机验证走的是模拟器（`bm clean -n com.youjing.app -d` 清掉同意态，
**这台机器没有用户数据，才敢清**）：弹窗里「《隐私政策》」节点从一行文字
变成 `[542,1148][767,1273]` ≈ **72×40vp** 的按钮，点下去就地展开正文
（读到「有径是一款本地优先的行程规划工具…」这段只存在于协议文本里的句子）✓。

### 状态
八把尺全 exit 0（`layout_patterns` 的 R1–R4 均 0 处，R5 13 条纯提示）；
屏5 的拆行改动**尚未复拍**（要再走一遍建行程链到屏5），记在这里不当已验。

### 屏5 拆行已复拍（补上「尚未复拍」那句）
装机后重走建行程链到屏5，`dumpLayout` 读到两个独立单行节点：
`舒适档 · 地铁 6号线/8号线` `[103,1293][547,1337]`、`锚定 南锣鼓巷` `[103,1349][339,1393]`
——站名不再被劈开，两条都远短于列宽，没有被省略号截。
帧：`~/Pictures/有径/走查帧-2026-10-27/t5_stay_fixed.jpeg`。

## 5u. 宽屏继续走查被**登录闸门**挡住（记清楚挡在哪，别下次重新撞）

想在 Mate X7 上补齐 首页/我的/屏8/屏4/屏5 的 `md` 档帧，顺手把 §5r 欠的
`noTrip` 分支也验掉（这台模拟器零行程，正是那个状态）。两条路都没走通：

1. **游客入口点不动**：进主界面要么华为登录，要么「暂不登录，使用本机游客空间」，
   而后者按 `!agreed` 禁用（`LoginView:64`）。勾 `agreed` 要点那个 24vp 的 `Checkbox`——
   按 `dumpLayout` 读出的真实 bounds 点中心，回读 `checked` 仍 `false`（同一台机器上
   大按钮「同意并继续」点是有效的，所以不是坐标缩放问题）。
2. **深链也绕不过去**：`aa start --ps route Expense` 在同意态被 `bm clean` 清掉之后
   仍然停在屏1。看代码是对得上的：未登录时渲染的是登录闸门本身，
   `routeTo` 往 `APP_NAV` push 的目标被闸门压在下面。
   ——**顺带记一条真实现象**：首次安装、还没登录的用户，点桌面卡片/快捷入口
   是进不到那条行程的，会先看到屏1。已登录用户（含游客）不受影响
   （真机侧「点卡片落屏8」是验过的）。要不要给这条闸门加一句
   「登录后回到你刚才打开的行程」，属于产品决定，先记账不动。

**下一步该做的**（按性价比排）：
① 在模拟器上改用 `uitest` 的无障碍动作或直接给 `Checkbox` 所在行加宽热区来破闸门
   ——但**先判断这是不是真缺陷**：24vp 命中区本身就低于契约的 44vp 最小热区，
   真机上大概也难点，这条值得单独量一次；
② 破开后一次拍齐 首页/我的/屏8/屏4/屏5 的 `md` 帧 + `noTrip` 分支；
③ 屏6 生成中态（要真跑一次生成，会建一条新行程，归用户决定要不要建）。

本轮到此的**已验/未验**边界，逐条列清：
- 已验（真机）：屏8/屏15/编辑页/记一笔四枚按钮、屏5b 净空与拆行、屏5 拆行、
  dock 切回重取、跟随最后打开行程（双向）、重点页签收回根页、同意弹窗链接换官方按钮。
- 未验：`noTrip` 空态分支（要零行程环境）、屏6 生成中/取消态、
  屏1 宽度上限在 `md` 之外档位、宽屏的 首页/我的/屏8/屏4/屏5 帧。

## 5v. 同意勾选的热区只有 24vp（低于契约 44vp）+ 这台模拟器的点击边界

`LoginView` 那行「我已阅读并同意…」的 `Checkbox`，模拟器 `dumpLayout` 实测
bounds `[76,1798][151,1873]` → **24×24vp**，低于契约 `minTouchTarget` 44vp。
布局尺 R3 只量 `Button`，所以这条一直是尺子的盲区（不是"没缺陷"，是"尺子看不见"）。

改法：整行 `Row` 加 `.height(minTouchTarget)` + `.onClick` 切换 `agreed`，
行内的《隐私政策》/《用户协议》是 `Span` 自己的 `onClick`（子级先命中），不冲突。

**但这台模拟器验不了这条改动**：同一行上，官方 `Button`（「同意并继续」）注入点击有效，
而 `Checkbox`、以及现在这个带 `onClick` 的 `Row` 点完回读 `checked` 都仍是 `false`
（点行内离 Checkbox 420px 的空白处也一样）。
规律很一致：**这台模拟器上只有官方 Button 收得到 `uitest uiInput click`**——
所以 §5u 那条"模拟器点不动 Checkbox"更可能是工具边界，不是 App 缺陷，
这条改动的真机效果**待用户或下轮真机确认**（真机上要验的是：
点这行任意位置能勾上、点两个协议名仍然只打开协议不切换勾选）。

留一条给尺子：R3 应该把 `Checkbox`/`Toggle` 这类可控件也纳入 44vp 检查，
不然这类缺陷会一直"全绿"。

## 5w. 「继续未完成的规划」试做了一次，**已回退**（记录为什么没成，别再走同一条）

§5q 那条最大缺口的第一次尝试：`PlanDraft.dirty()` + 首页在主按钮下面加一颗次级
「继续未完成的规划」（不 `fresh()`，直接 `enterPlanningFlow('TripInput')`；
屏2/3/4/5 现在都从草稿起值，所以从屏2 重进等于接着走）。
编译过、八把尺过，**真机跑出来是坏的**：

```
1 干净草稿，续规划入口应无: False      ← 对
3 回首页，续规划入口应出现: False      ← 错，按钮没出现
```

根因：`draftDirty` 只在 `reloadRecent()` 里赋值，而 `reloadRecent()` 挂在
`aboutToAppear` 和「dock 切回广播」两条路上。**从屏2 返回首页两条都不触发**
（首页实例一直活着，dock 也没动）——所以那颗按钮永远不出现。
一个"看起来该有却没有"的入口，比没有更糟，正是用户抱怨的半成品样。已 `git restore` 回退。

**能成立的接法**（下轮直接照这个做，不用再推一遍）：
脏标记要**由写草稿的那一方广播**，而不是由看它的那一方轮询——
`TripInputPage` 写 `PlanDraft.basic` 的那处（`:401` 附近）与
`SpotPickPage.confirm()`(`:181`)、`StayPickPage`(`:471`) 各调一次
`AppStorage.setOrCreate(DRAFT_DIRTY_KEY, '1:' + Date.now())`，
`enterApp()` 里 `PlanDraft.fresh()` 之后置 `'0:' + Date.now()`；
首页用 `@StorageProp(DRAFT_DIRTY_KEY) @Watch` 取值。
这条通路就是 `TAB_SWITCH_KEY`/`TAB_SHOWN_KEY` 已经验过两次的同一套机制，
不引入任何未验 API。

## 5x. 「继续未完成的规划」按 §5w 那套广播写法做完并真机验通

写侧广播、读侧 `@Watch`：
- `AppNav`：`DRAFT_DIRTY_KEY` + `markDraftDirty(boolean)` + `isDraftDirty(value)`（值带时间戳）。
- 四个写草稿的地方各广播一次 `true`：`TripInputPage`（写 `basic` 之后）、
  `PreferenceQAPage.syncDraft()`、`SpotPickPage.confirm()`、`StayPickPage`（选片确认）。
- `YoujingStartPage.enterApp()` 里 `PlanDraft.fresh()` 之后广播 `false`。
- 首页 `@StorageProp(DRAFT_DIRTY_KEY) @Watch('onDraftTick')` → `draftDirty`，
  `aboutToAppear` 再取一次初值（冷启时 `@Watch` 不为初值触发）。
- 按钮是 `SECONDARY` 档（禁令 1：一屏只许一颗实心主按钮），点它**不 `fresh()`**，
  走 `enterPlanningFlow('TripInput')`；因为屏2/3/4/5 现在都从 `PlanDraft` 起值，
  从屏2 重进等于接着上次的进度走。

真机验收（`aa start` 冷启后）：
```
1 干净草稿 应无按钮: False   ← 对
2 到屏3: 偏好追问 · 第 2 / 5 步 · 出行偏好
3 回首页 应出现按钮: True    ← §5w 那次就是死在这一步
4 续进落在: 第 1 / 5 步 · 基础信息（目的地字段还在）
5 再到屏3: 偏好追问 · 第 2 / 5 步
```
`BUILD SUCCESSFUL`、八把尺 exit 0。

### 主链现在的样子（业务流程收口状态）
首页 →〔基础信息〕→〔出行偏好〕→〔选景点〕→〔选住宿〕→〔看行程〕，
每屏顶部有 `FlowSteps` 五段进度轨 + 「第 N / 5 步」；
中途回退或回首页都不丢选择（§5l/§5m 的草稿还原 + 这一条的续规划入口）；
从「我的」页签进入任一页，按钮都推在自己那条栈上（§5l 的 P0）；
误触 dock 会收回该页签根页而不是"点了没反应"（§5q）。

## 6. 交接（本轮预算用完，下一轮从这里接，不必重新推导）

**闸门现状**：`8167c6b..HEAD` 共 43 个提交（本轮 15 个，`909f57b`…`7aa0fb1`），
工作树干净，`BUILD SUCCESSFUL`，八把尺 `colors/type/geometry/material/fontfamily/tnum/elevation/layout_patterns` 全 exit 0，
`hooks/pre-commit` 只跑编译门禁、尺子手动跑。真机 `192.168.3.2:46077` 装的是与 HEAD 一致的包，停在首页。
证据帧统一在 `~/Pictures/有径/走查帧-2026-10-27/`（**别放 `/tmp`，重启即空**）。

**下一轮按这个顺序做，每条都带锚点**：
1. **屏5「帮我选」的假路径会让屏7 无法补救**：`StayPickPage` 的 `helpPick()` 在
   `targets.length === 0` 或候选片区全缺坐标时，只 `toast` 一句"先按推荐顺序选了一片"就当成功；
   随后生成的行程没有真实片区锚点，屏7（`GenerateFailedPage`）的"可行修法"里
   没有一条能回到屏5 重选。改法：这条分支不要静默成功，直接把用户留在屏5 并高亮候选，
   或给屏7 补一条「回屏5 重选住宿片区」（`popToName('StayPick')`）。
2. **破开模拟器登录闸门补宽屏帧**：`Checkbox` 只有 24vp 且这台模拟器
   `uitest uiInput click` 只对官方 `Button` 生效（见 §5v）。
   破法二选一：给同意行换官方可点控件；或直接真机对照。
   破开后一次拍齐 首页/我的/屏8/屏4/屏5 的 `md` 档，顺手验掉
   费用页 `noTrip` 分支（模拟器零行程，`bm clean -n com.youjing.app -d` 可重看隐私弹窗）。
3. **屏6 生成中/取消态从未拍到**：要真跑一次生成（会建一条新行程，先问用户要不要建）。
4. **流程尾巴三条**：`OnTripPage` 的 `ongoing` 恒 false；`AppRouter` 的 `'Trips'` 分支不可达；
   `AccountStore.init` reject 时会白屏无兜底。

**待用户裁决（不要自己拍）**：
① 单列表单（屏1/协议）要不要另设比 `contentMaxWidth`(626vp) 更小的宽度档；
② `ImmersiveSurface` 边光越界要不要撤掉流光（已回退两次无效实验，见 §5b/§5c）；
③ 屏12b 末行「的路」是否保留底稿的 240 宽双行形态；
④ 首启未登录时点桌面卡片/快捷入口会先看到屏1（§5u），要不要「登录后回到刚才那条行程」。

**硬约束（本轮踩过，别再踩）**：`~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md` 是权威契约，
**不许为了让尺子过而改它**；清用户数据/删行程不代做；设备被真人占用立刻停手；
修截断类缺陷两侧都要量化（§5o）；"返回后状态还在"证明不了还原代码，要用被 pop 后重进的全新实例做判据（§5m）。

## 5y. 屏9 与底稿逐要素对表（UI alignment review）：这一屏是全工程最生疏的一屏

参考：`frames/屏9dark_行程时间线编辑态_1203d116/screen.png`（1600×1280 渲染图）
实拍：`走查帧-2026-10-27/e.jpeg`（真机 1136×2690，深色档，同一屏同一状态）。
两边都是深色、都是"编辑 Day 1 的三个节点"，可直接对表。

| 底稿要素 | 实拍 | 判定 | 本轮处置 |
| --- | --- | --- | --- |
| Day 头 `Day 1 · 10月12日 周六`（serif 21/700）+ 右侧 `东山区 · 步行 5.2km` | **整行不存在**，卡片直接顶到标题栏 | must-fix（缺内容 + 用户不知道在改哪一天） | ✅ 已补 `dayHeader()`，取词与屏8 同一套 |
| 钉底操作条 `撤销`(次级) + `保存修改`(实心主) | **不存在**；主操作只藏在标题栏三枚无文字图标里 | must-fix（主操作被藏 + 底部 60% 空白） | ✅ 已补 `actionBar()`，带 dock 净空；标题栏去掉重复的「完成」 |
| 行间交通段 `步行 12分钟 · 750m` 挂在时间轴脊线上 | 无 | must-fix（编辑页看不到"两站之间怎么走"） | ⬜ 未做，见下 |
| 每行时间右侧的**节点圆环**（选中行蓝环） | 无 | must-fix（行与行失去时间轴连接） | ⬜ 未做 |
| 容量提示 `拖到第 2 天 · 余量 3.5 小时` / `移走后第 1 天空 2.5 小时，可补一个可选景点` + `补一个` | 无 | must-fix（拖动没有正反馈，是这屏的核心价值） | ⬜ 未做 |
| 把手是 6 点网格 | 三条横线 `≡` | polish（图标语义） | ⬜ 未做 |
| 行右动作 `◇`(替换) `—`(删除) | 一个渲染成 `( )` 的图标 + 垃圾桶 | should-fix（替换图标读不出"交换"，垃圾桶语义可以但和底稿不一致） | ⬜ 未做 |

**结论**：屏9 之前只做到"能拖、能存、能返回"，**底稿要它承担的三个信息层
（哪一天 / 站间怎么走 / 拖动后余量多少）一个都没有**，所以它看起来像半成品里最生疏的一屏。

### 证据边界（不写成已验）
本轮结束时真机 `192.168.3.2:46077` **离线**（`hdc tconn` 返回 `Connect failed`，
`hdc list targets` 为空），所以 `dayHeader()` 与 `actionBar()` 这两处改动
**只有编译与尺子级证据**：`BUILD SUCCESSFUL`、八把尺 exit 0（含 R1 钉底让位 dock 0 处）。
**下一轮第一件事**：设备回来后重装包 → 我的行程 → 屏8 菜单「编辑行程」→ 复拍这一屏，
按上表逐条对，并把剩下四个 must-fix/should-fix 补完。

## 5z. 屏7 的「可行修法」补上回屏5 重选住宿片区这一条

`GenerateFailedPage.fixes` 原来只有两条出口：景点、节奏。
但**通勤起点是屏5 选的住宿片区决定的**——屏5 的「帮我选」在候选片区都缺坐标时
会退回推荐顺序（只 toast 一句"先按推荐顺序选了一片"），
这类受阻到了屏7 没有任何一条出口能回去重选，用户只能从头再走一遍链。
补中间一条 `换一片住宿再试 → route: 'StayPick'`，落点仍走同一个 `goFix()`
（在栈上就 `popToName`，不在就 `push`），不新增导航机制。

**验证边界**：这条要真机走「屏5 兜底 → 生成受阻 → 屏7 点第三条」才算验透，
而这条路径需要构造"候选片区全缺坐标"的数据，本轮未构造；
设备当前也离线。已验的是编译与尺子（八把尺 exit 0）。

## 5aa. 屏12b 空状态两处对齐底稿（顺带修掉一处「换行点交给引擎」的旧毛病）

设备重连后（新地址 `10.29.103.50:46077`，同型号 1136×2690）行程列表变成空态，
正好把屏12b 与底稿 `frames/屏12b_有径-我的行程空状态_06190639/code.html` 对表：

| 底稿 | 改前实拍 | 处置 |
| --- | --- | --- |
| 副文本原句「选一座城市，四道题就能拿到一份能直接走的行程」`14/400`，`max-width:240px` 双行 | 我们自造的句子「从一座城市开始，让有径替你排好每天的路」，实拍断成「每天 / 的路」 | ✅ 换回底稿原句 |
| 主按钮「规划新行程」 | 「创建新行程」 | ✅ 改回底稿用词 |
| 双行要"标准折行" | **底稿整句交给引擎在 240vp 里折，实拍断成「能直 / 接走的行程」**，把「直接」劈开 | ✅ 显式拆两行：`选一座城市，四道题` / `就能拿到一份能直接走的行程`，字句不变、断行点由我们选 |

复拍 `dumpLayout`：两个节点各自单行（高 51px），宽 394px/569px = 126vp/182vp，
都在 240vp 内，**没有劈词也没有截断**。帧 `走查帧-2026-10-27/x4_mine_empty_2line.jpeg`。

**这条的真正教训**：底稿写 `max-width:240px 形成标准双行折行`，
但 HTML 与 ArkUI 一样会在任意 CJK 字之间断行——**底稿的"双行"不保证断在词边界**。
所以对齐底稿不能只抄句子和宽度，还得把断行点固定下来。
屏5b/屏5/这一屏三处同族，都是同一个根因。

### 数据问题（需要用户确认）
本轮之前这台机器有 20 条行程，重连设备后「我的行程」与首页「最近行程」都变空态。
**我没有对手机执行过清数据**（`bm clean` 只打在模拟器 `127.0.0.1:5555` 上）。
两种可能待用户确认：① 重连时手动清过数据/重装过；② 账号 `uid` 变了导致
`WHERE t.user_id = ?` 查不到（数据还在库里但看不见）——②是真 bug，
要查的话最快路径是看 `AccountStore` 落盘的 kind/uid 与昨天是否一致。
App 自己的 `Ui.*` 日志在这台机器上抓不到（`hilog -x` 里按 pid 过滤只有系统 tag），
这条取证手段本身也要单独查。

## 5bb. 屏9 时间轴补完 + 屏15 补「完整行程」入口（真机复拍通过）

用户授权走完链建了一条测试行程（北京 10-27~10-29，生成只花 1.2 秒——
所以屏6 骨架屏**快到拍不到**，这条不是取证失败而是该态本身瞬时）。

**这一轮新查到的流程断点**：从「我的」点开一条**旅行中**的行程只会落到屏15，
而屏15 没有任何入口能进行程详情/编辑——点开就"困"在打卡页。
补 `OnTripPage.titleBarOptions()` 的「完整行程」菜单项（`pushPath('Itinerary', tripId)`）。
真机走通：我的 → 屏15 → 标题栏 → 屏8 → 菜单 → 屏9 ✓。

**屏9 按 §5y 对表补完三项**：
- 行间交通段：`地铁 22分钟 · 2 站` / `打车 18分钟 · 约 6km`，取 `act.transport`，
  挂在相邻两站之间（`legRow`，`idx > 0` 才画）。
- 每行时间右侧**节点圆环** + 脊线：把屏8 的圆环提取成 `components/TimelineNode.ets` 共用
  （色名→token 的映射原来长在 `ItineraryPage.dotColor`，`utils/CategoryStyle` 按 §分层
  不能 import `design/`，所以映射落在组件层）。屏8 同步换用该组件，**复拍无回归**。
- Day 头从 `Row` 改回 `Column`：Row 里右侧元信息被挤成「第 1 …」截断，
  改两行后「南锣鼓巷-鼓楼 出发 · 第 1 日 · 3 个节点」完整显示（与屏8 同一坑同一解法）。

**两处量化复核**（不靠目视下结论）：
- 「保存修改」文字右边界 1081px ≤ 内容右边缘 1086px，**没有溢出**——我目视以为它贴了屏幕边，量下来是错的。
- 节点圆环 bounds 与屏8 同档（22+2 描边、内点 `itineraryNodeDot`）。

**仍留一条不一致**：屏8 的脊线是**虚线**、屏9 是**实线**；屏8 交通段带模式图标、屏9 只有文字。
下一步统一（同一组件或同一画法），记为任务 #7 的收尾。

## 5bc. 屏9 容量提示补完（底稿最后一项 must-fix），顺带把停留时长算法提到 utils

底稿屏9 那句「移走后第 1 天空 2.5 小时，可补一个可选景点」+「补一个」链接，
实现里删完节点**什么反馈都没有**。现在 `removeAt()` 记下被删活动的停留时长，
列表下方出琥珀色提示条 + 官方 TEXTUAL「补一个」按钮（走 `openAdd()`），
`undo()` 一并清掉。

真机实测（同一条测试行程）：
- 点第一行垃圾桶 → 提示条文案 `移走后第 1 天空 4小时，可补一个可选景点` ✓（故宫建议停留正是 4 小时）
- 点「撤销」→ 节点回来、提示清空 ✓，**未落库**（没点保存修改就退出，行程数据不变）

算法提取：`durationText` 原来长在屏8，屏9 要第二次用同一份"分钟差→中文时长"，
复制必漂，故提到 `utils/TimeText.ets`（只依赖 model，不碰 design/，符合 §分层），
屏8 改为委托并复拍无回归（`建议停留 4小时 · 北京 东城区` 仍在）。

屏9 与底稿的对表到这里：**Day 头、节点圆环+脊线、行间交通段、容量提示、
钉底撤销/保存修改** 五项全部落地并复拍。剩两条 polish：
交通段补模式图标（屏8 有）、把手换 6 点网格（现在是三横线）。

## 5bd. 屏15 与底稿对表：下一站补节点圆环、餐次时间槽补占位

参考 `frames/屏15_有径-旅行中模式_fc4e40cd/screen.png`，实拍 `n15_ontrip_node.jpeg` / `o15_ontrip_slot.jpeg`：

- 底稿的下一站一行是「11:30 + 节点圆环 + 天龙寺 + 需预约 + 建议停留 1小时 · 嵯峨野」。
  实现里**圆环和脊线都没有**，下一站像是飘在列表中间。用屏8/屏9 同一个
  `TimelineNode` 补上（内点按类别取色：餐次走琥珀，实测正确）。
- 餐次没有 `time`（`DayStop.time` 允许空串），列表行早就用 `kind`（早餐/午餐/晚餐）
  占时间槽，但**「下一站」这一行漏了**，实拍时间整列空白。补 `nextSlotLabel()`，
  复拍 `午餐 [50,1220]` 与 `本地午餐 [338,1216]` 同基线 ✓。
- `DayStop` 上没有 `category` 字段，类别只能按 `kind` 是否非空判（活动那份 `kind` 恒空串）——
  这是读结构得出的，不是猜的。

**屏15 与底稿仍有的差距（未修，记账）**：底稿 hero 卡的提示是「周一人少，10:00 后团队到达」
这类**当日情境**，实现里放的是「预约：官网/小程序预约」——数据源只有预约字段，情境文案没有来源；
以及 `ongoing` 恒 `false`（`OnTripPage:432`）导致底稿那条蓝色「进行中」行样式永不出现。

## 5be. 加支持城市「杨凌」（用户所在地），顺带暴露并修掉一处「地铁」硬编码

用户人在杨凌示范区，要求能以真实用户视角测自己的城市。

**接入面**（一次做完，全部真机跑通）：
- `seed/spots_yangling.jsonl` 10 个景点、`seed/areas_yangling.jsonl` 5 个片区，
  schema 与北京那份逐字段一致。
- `DataSeeder.CITIES` 加一条；`DistrictCoords` 加 `杨凌:杨陵区 [34.2727, 108.0811]`；
  `SEED_VERSION` `v2-geo-3` → `v2-geo-3-yl` 触发重灌（只灌 spot/area 两张表，
  **不动用户行程**）。
- 屏2 城市候选加「杨凌」。

**杨凌没有地铁**，而 UI 有三处把「地铁」写死：
`StayPickPage:182`（`地铁X线直达`）、`:242`（`地铁 ${lines}` / `无直达地铁`）、
`AreaMorePage:106`（档位行前缀）+ 搜索框 placeholder。
照这个写法，杨凌会显示成「地铁 公交1路/公交5路」这种自相矛盾的句子。
改法：**去掉前缀，让线路名自己带含义**——北京种子存的是「1号线」「5号线」，
读者照样知道是地铁；杨凌存「公交1路」也成立。兜底句改「无直达线路」。
这是"加一座城市"才暴露出来的耦合，四个种子城市互相掩盖着它。

**真机全链验证**：屏2 选杨凌 → 屏4 出「西北农林科技大学博览园 / 创新园 / 教稼园…」
→ 屏5 出「杨陵区政府-西农商圈 / 高铁南站-揉谷片区…」，档位行显示
`舒适档 · 公交1路/公交5路` ✓ → 「就住这里」→ 生成 → 屏8「杨凌 · 3天2晚」带 Day 1/2/3 ✓。

**数据诚实性声明（别当精确数据用）**：
- 腾讯地图 Skill 无可用 Key（`poi_search` 报未检测到 API Key），
  所以坐标**不是**地理编码结果：区中心与杨陵南站取公开值
  （杨陵区 34.2727/108.0811、杨陵南站 34.2536/108.0532），
  其余景点按公开资料里的**街道/村镇位置**（邰城路北段、杨扶路中段、河堤路、
  五泉镇王上村、揉谷镇田西村）给近似值，精度与 `DistrictCoords` 同一档，
  头注释已写明「待地理编码回填」。给一个 Key 我就能把 10 个点位换成真值。
- 景点的 `bk`（预约）字段一律不编：只有农高会会址标了「农高会期间现场登记」，
  其余 `req:false`；开放时间只在资料明确写了的条目上填。
- 机场分钟数是按"杨凌—西安咸阳国际机场"里程估的，**未实测**。

## 5bf. 屏11（费用视图）对表：金额千分位统一到 `MoneyText`，另有一条要产品定

参考 `frames/屏11_有径-费用视图_1ab099b1/screen.png`，实拍 `e11_expense_yangling.jpeg`（杨凌那条行程）。

**已修：金额格式**。底稿每一处金额都带千分位（`¥16,000`/`¥12,840`/`¥6,400`），
实现里是 `¥16000`——而且**六个渲染点各拼各的** `¥${n}`
（`ExpensePage.yuan`、`TripsPage:104`、`OnTripPage:432/472/519`、`TripInputPage:331`），
改一处必漏五处。提到 `utils/MoneyText.ets`（`group()` + `yuan()`，手写分组，
不依赖未验证的 `Intl.NumberFormat`），六处统一。
真机复拍：`预算 ¥16,000 · 各天预估合计 ¥1,540 · 2 人 · 3 天`、`剩 ¥16,000 · 还剩 2 天`、
屏12 `总花费 ¥1,540` ✓。

**顺带查到的一个真缺陷（已一并修）**：`ExpensePage` 的 `yuan()` 是模块级函数，
我第一轮批量替换时**它自己没拿到 import**（脚本按"struct 之前不插 import"判断，
而模块级函数正好在 struct 之前），编译报 `Cannot find name 'MoneyText'`。
——记下来：给"文件顶部函数"批量加依赖时，import 插入点不能按 struct 位置猜。

**需要产品定的（没动）**：底稿屏11 的「预算」档在**分类支出**区显示
住宿/交通/餐饮/门票四条**带进度条的计划金额**；
实现里这一区只读 `ExpenseDao.sumByCategory`（**已记的账**），
所以一条账都没记时整区只剩一句引导文案，看不到"计划里钱怎么分"。
`Trip` 聚合根里**没有按分类的计划金额字段**（只有 `day.dailyCost` 与 `overview.totalCost`），
要做这条得先决定：是 AI 出计划时就按分类拆（改协议 + 落库），
还是屏11 预算档改成不展示分类条（改底稿）。两条都不是我该自己拍的。

## 5cg. 屏16（分享与导出）对表：撤掉一屏两份的重复入口与误导性 chevron

参考 `frames/屏16_有径-分享与导出_074108e2/screen.png`，实拍 `g16_share` → 修后 `h16_share_fixed`。

| 底稿 | 修前实现 | 判定 | 处置 |
| --- | --- | --- | --- |
| 两个动作就是列表里两行，**没有钉底动作条** | 两行 + 底部又摆「导出 .ics」和「分享行程文本」两颗按钮 | must-fix（同一屏两套入口，点了其中一个另一个状态不同步） | ✅ 撤底部两颗，只留常驻诚实说明 |
| 行是**直接执行**的动作 | 行尾挂 `chevron_right`，读起来像"会进下一层" | must-fix（预期与行为不符） | ✅ 撤 chevron |
| 卡片=路线图带 + 三格统计 | 我上一轮删掉永不填充的行程纸后，只剩三格统计，**下面留了半屏空洞** | should-fix | ⬜ 未做，见下 |
| 副标题「京都 5天4晚 · 16 个景点 · 步行 24.6km」 | 「杨凌 3天2晚 · 8 个节点」 | acceptable-difference | 步行总公里数无数据来源，不编 |
| 第一行动作叫「分享链接」 | 「分享行程文本」 | acceptable-difference | 无后端生成不了链接，§4b 已登记改口 |

**仍缺的那半屏**：底稿的路线图带（编号圆点串在一条曲线上）是这屏的视觉主体。
实现里删掉空占位之后没有替代物 → 内容只占上半屏。
下一步用**真实节点数**画一条编号节点带（不引入任何假数据），补在这个位置。

顺带：本轮走这条路径时，「我的 → 旅行中的行程」只能落到屏15，
是靠 §5bd 新加的「完整行程」入口才进到屏8/屏16 的——**这条入口是这轮才补上的**，
说明之前所有"旅行中"的行程都到不了分享/导出/编辑。

### §5cg 补：路线带已画出来（真机复拍）
用**真实节点数**画底稿那条编号节点带：`1—2—3—4—5—6` + 副标题
「共 8 站，图上只画前 6 站」（超过 6 站不假装画全），下面一道浅色河带，再跟三格统计。
帧 `i16_share_ribbon.jpeg`。删占位留下的半屏空洞到此补上，且**没有引入任何编造数据**。

布局尺 R2 把「22vp 连接线」和「10vp 河带」报成空块——这两块是底稿声明的装饰原语，
属于白名单该管的对象，已带理由登记（不是放宽阈值：自测仍能抓到注入的空块）。

## 5ch. 交互契约全量对表（19 张浅色帧的 aria-label × 代码）＋第 10 把尺

本轮设备不可达（`hdc list targets` 空，手机断了、模拟器没起），所以换了个**不需要眼睛**的口径：
前 30 多轮都是"一屏一屏看画得像不像"，这轮问的是**底稿声明的交互，代码里到底有没有**。
这类缺陷实拍查不出来——按钮画得好好的，只是少了一个反向动作、少一个落点。

做法：把 19 张浅色帧 `code.html` 里的 `aria-label` 与 `<button>` 文案全量抽出来
（帧的 aria-label 就是这一屏的交互契约，之前只在单屏对表时用过），
逐条到 §5k0 对照表指定的实现文件里找字面量，未命中的列成清单人工判读。

| 帧 | 未命中项 | 判读 |
| --- | --- | --- |
| 屏2 | `1人/2人/4人` | **尺的假阳性**：代码是模板拼的 `${count}人`（TripInputPage:167），字面量查不到很正常 |
| 屏2 | `调整预算档位` | **真缺陷**：预算 Slider 整条链上没有任何可及名，读屏只会念"滑块"。✅ 已补 |
| 屏4 | `标为普通` ×7 | 帧里那颗钮的 aria 是**下一步动作**（已标必去的行显示"标为普通"）。代码用四选一菜单 + 点行循环，`取消标记`/`设为必去` 都在（SpotPickPage:114-117），反向动作没缺 |
| 屏5 / 屏16 | `返回` | 系统返回由 `HdsChrome.bar` 提供，不在页面里写文案 |
| 屏7 | `按建议修复` / `换一天` | 分别落成**具体修复行**（`goFix(fix.route)`，按失败码给不同建议）和「改出行日期」，语义都在 |
| 屏9 | `完成编辑` | 落成底部主钮「保存修改」→ `finish()` 回写并 `pop()`（§5y 这轮补的） |
| 屏11/11b | `更多` / `地图` / `我的` | 顶栏溢出钮与 dock 是共用组件，不在这两个文件里 |
| 屏12 | `搜索行程` | 官方 `Search` 的 placeholder「搜索目的地或日期」即其可及名 |
| 屏13 | `Widget C` | 帧给卡片尺寸变体起的标签，`TodayTripFormAbility` 按 dimension 分别供数 |
| 屏14 | 三个 `××开关` | `accessibilityText` 传的是模板 `title + 开关`（ItineraryPage:945），动态拼 |
| 屏16 | `复制链接` | **不实现，且理由要说清**：有径没有后端，生不出任何链接——摆一颗"复制链接"就是让用户复制一个空。帧的两个槽位由「分享行程文本」（系统分享面板）+「导出 .ics」占据，意图（把行程内容送出去 / 导成文件）都落实了。与 §5cg 撤掉空"行程纸"同一判据：**控件要么有活干，要么不放** |

**结论：19 张帧声明的交互，除"复制链接"这条被有意替换（无后端）之外，全部有落点。
业务流程没有缺动作。**

### 第 10 把尺：`tools/audit_a11y_name.py`

上面这类"名字漏了"靠实拍永远查不出来，所以做成常驻尺：
只查**官方语义控件**（Slider/Toggle/Checkbox/TextInput/TextArea/Search/Select/Rating）
的属性链上有没有 `accessibilityText`/`placeholder`/`label`/`title`；
`Button`/`Text` 不算（label 和内容本身就是名字）。全仓抓到 2 处：预算 Slider、屏1 同意勾选框，**都已补**。

尺子自己也要反证（旧教训：检测器报 0 多半是它漏判），`--probe` 三例常驻：
① 注入的裸 Slider 必须被抓到；② 属性链中间夹注释行不能把链截断；③ 注释后面紧跟的**兄弟控件**
的名字不能被算进本控件。三条全过才算尺子有效。

**第②条不是假想**：第一版尺子按"非 `.` 开头即停"走链，结果给**已经补好可及名**的预算 Slider
又报了一次漏写——它的链在 `.trackColor()` 和 `.accessibilityText()` 之间夹了 3 行解释把手颜色的注释。
改成注释/空行透明、遇第一条真语句即停，并用反证 ③ 卡住"透明"放开过头的新风险。

### 验证（本轮没有设备，所以只做可机判的那部分）

- `hvigor assembleHap` **BUILD SUCCESSFUL**；
- 按"UP-TO-DATE 会复用旧产物"那条老教训，解包核对 `ets/modules.abc` 里
  **确实含**「调整预算档位」「同意隐私政策与用户协议」两个字面量（hap md5 `13878394…`，10:56 产物）；
- 十把尺全部 exit 0（`audit_contrast` 需设备，本轮跳过）；
- 可及名是读屏行为，**看不见、也拍不到**，本轮不做屏幕断言。等手机回来要补的验收：
  设置→辅助功能→屏幕朗读，进屏2 听预算滑块是否念出"调整预算档位，当前 ¥8,000 每人"。

### 顺带查的一项流程完整性

`pushPath`/`replacePath` 的**所有**目标名 × `AppRouter.routerMap` 的注册名做集合差：
`未识别路由` 落点 0 处（用户不会点到"这页还没有"）；`OnTrip`/`Trips` 是 dock 根页、
不经 push，不是孤儿。**路由层没有断链。**

## 5ci. 第一次拿到宽屏真帧：契约的 720 阅读上限在整个 md 档是空话（已修）

手机仍不可达，改用 Mate X7 模拟器（`-hvd "Mate X7"`，2210×2416，密度 3.125 ⇒ 窗口 **707vp = md**）。
这仓的 `Responsive.test.ets` 文件头自己写着「宽屏/折叠展开的实机渲染至今没拿到一帧」——
本轮拿到第一帧，而且第一帧就查出东西。

**证据（uitest dumpLayout 的节点 bounds，不是目测）**：屏1 隐私说明段
`[62,1568][2119,1692]` ⇒ 宽 2057px ÷ 3.125 = **658vp**。14fp 正文下约 **47 个汉字一行**。
首页的预览卡更夸张：卡体 `[100,…][2110,…]` 通铺整屏，标题「Day 1 · 京都 东山步道」拉到 583vp，
三行节点的右侧 55%（x≈814→2110）**全是空白**——这就是「组件排版交错」在折叠屏上的形态。

**根因是一个数，不是五处代码**：`LayoutTokens.contentMaxWidth = 720`，来自 DESIGN.md
`content-max-width: 720px` / 「Reading column max 720px」——数值忠实，**但 720 比整块屏（707vp）还宽**。
`longFormMaxWidth` 老实现「宽屏（md 及以上）一律返回调用方传的 720」，
于是 `constraintSize({maxWidth: 720})` 在 600–720vp 这**一整个 md 档**里永不触发。
而 md 恰恰就是折叠屏展开态。契约那条规则在真机上等于没写。

**改法（一行档位规则，不动契约数值）**：`utils/responsive.ets` 里 md 档收到 **`BP_MD_MIN_VP`（600）**、
lg 及以上才用 `contentMaxWidth`（720）。600 不是我新发明的魔数，是断点表里已有的 md 下限：
600vp 窗口不受影响（恰为档位下限），707vp 窗口收到 600、两侧各 53.5vp，
读起来是"居中的一栏"而不是"被整屏拉宽的卡片"。两档单调（600 ≤ 720），折叠/展开不会跳列宽。
`contentMaxWidth` 与 DESIGN.md **一字未改**。

**为什么这一行值四处改**：`longFormMaxWidth` 已有四个消费方
（屏1 `LoginView:201`、屏2 `TripInputPage:390`、屏8 `ItineraryPage:1200`、`LegalDocReader:94`），
它们全都写对了、只是被这条惰性规则废掉。

**复测（同一机位、同一控件）**：装新包 + `bm clean`（只在这台模拟器上做过）回到首启，
同一段隐私说明从 **658vp → 588vp**，左边缘 62px → 168px，
「我已阅读并同意…」行右边缘 2043px ≈ **600vp 上限的边界**（(707−600)/2 = 53.5vp ⇒ 167–2042px）。
上限确实生效了，不是又一场"改了两遍看不出差别"。帧 `走查帧-2026-10-27/w1_md_login_capped.jpeg`。

回归测试同步改了口径（原来钉的是 `md → CAP_VP`，正是把惰性规则钉成"正确"的那条断言）：
现在钉 `md → BP_MD_MIN_VP`、`lg → CAP_VP`，并加两条单调性断言。

### 还没做（要说清，别当成已收口）

- **首页预览卡通铺**这一条本轮没改：它的容器不是 `longFormMaxWidth` 消费方，
  要收窄得给根 Column 加限宽并居中（结构改动），且首页在 md 下还有 `List.lanes` 并两列的选项，
  两条走法代价不同，我下轮按实测选，不这轮硬塞。
- 屏15 / 屏16 / 屏7 / 地图 **完全不消费断点**（grep 计数 0），宽屏下同样通铺。
  这几屏要有数据才拍得到（模拟器现在只有游客空态），属宽屏专项，未验。
- 手机（sm 档）不受此次改动影响：`longFormMaxWidth('sm')` 仍返回 `'100%'`，
  这条由测试第一行钉住，也是我不敢把 md 直接改成 520 的原因——**改动不能渗到手机档**。
