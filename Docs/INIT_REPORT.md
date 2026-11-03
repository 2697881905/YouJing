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

**硬约束（本轮踩过，别再踩）**：`~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md` 是家族契约文本，
**由产品负责人修订**；任何改动必须与 `design/*.ets` token 表、`tools/audit_*.py` 判据在**同一批提交**里同步
（尺只遍历契约侧：加行可能红、删行只会绿）——旧口径「是权威契约，不许为了让尺子过而改它」自 2026-11-02
契约 v2 起作废，新规矩全文与版本路标见 §5ci 续 84；清用户数据/删行程不代做；设备被真人占用立刻停手；
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

### §5ci 续：首页通铺用「对称内缩」而不是 maxWidth（数学已验，md 渲染未拍到）

宽屏那一帧里首页预览卡 `[100→2110]` 通铺 642vp、三行节点右侧 55% 空白。
先试的 `constraintSize.maxWidth` 在这屏**不能用**：它的子级全是 `width('100%')`，
父 Column 一旦被限宽就变成"左贴边 + 右侧空出一条"，比通铺更难看。
所以换成**两侧等宽内缩**：`(窗口宽 − 目标栏宽) / 2`。窗口实测宽由断点中心一并发布
（`KEY_WINDOW_WIDTH_VP`，它本来就量过一次窗口宽，不在页面里另挂 windowSizeChange），
新纯函数 `responsive.symmetricInsetForCap(窗口宽, 栏宽, base)` 算内缩量，
首页根的左右 padding 由 `SpaceTokens.lg` 改走它。手机档 `windowWidthVp ≤ 栏宽 + 2×base`
直接返回 base，**等于没改**。

**已验**：把这五个断言喂给真实函数体离线跑（`node --experimental-strip-types`）——
360→16、未测到宽(0)→16、632→16（临界不收窄、不会出负内缩）、707→54、1100→250，
与写进 `Responsive.test.ets` 的期望逐项一致；`assembleHap` 通过；十把尺 exit 0。

**没验（要说在前面）**：首页在 md 下的**渲染**一帧都没拍到。卡在首启的同意弹窗上——
`uitest uiInput click` 打在弹窗的「同意并继续」按钮坐标上连试两次，dump 里弹窗原样还在
（模拟器对弹窗层的注入点击不生效，属工具边界，不是 App 缺陷）。
所以这条目前只有"数学 + 编译"两级证据，**"折叠屏展开后首页确实变成居中的一栏"是未验项**，
要么手机连回来，要么请真人点一下同意，我才能报它生效。

### §5ci 续 2：把对称内缩铺到剩下三屏（屏15 / 屏16 / 屏7）

首页那条机制铺开后，剩下完全不消费断点的是屏15、屏16、屏7、地图。
**地图故意不改**：它的浮层是横向 chip 滚动条压在满幅底图上，宽屏本来就该满幅，
给它加内缩反而错。其余三屏的内容都是"单栏散文卡"，根容器左右都是 `SpaceTokens.lg`
写死，md 下会跟着整屏拉宽——所以统一换成 `this.wideInset()`（共 4 个钉底容器：
屏16 有 List 与底部说明两处，必须同一档，否则说明与列表左右不对齐）。

零手机风险是可证的：`symmetricInsetForCap` 在 `窗口宽 ≤ 栏宽 + 2×base` 时原样返回 base，
手机（360/393vp）落在这条以下，返回值与改动前的 `SpaceTokens.lg` 相同。

**证据级别要说清**：本轮只有「纯函数五档断言 + `assembleHap` 通过 + 十把尺 exit 0」。
这三屏的 md 渲染**一帧都没拍到**——模拟器卡在首启同意弹窗，
坐标点击（试了 2 次）与 `keyEvent KeyTab/KeyEnter` 键盘注入都进不到弹窗层，
属工具边界（不是 App 缺陷），不再叠第三种注入方法。
所以这三屏"折叠屏展开后确实收成 600vp 一栏"仍是未验项，与首页那条一起等手机连回。

### §5ci 续 3：跑起了 hypium 全量（103 例 0 失败），本仓第一次有设备侧回归证据

`entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap` 装进模拟器后：

```
aa test -b com.youjing.app -m entry_test -s unittest OpenHarmonyTestRunner -s class Responsive
  → Tests run: 5, Failure: 0, Error: 0, Pass: 5
aa test -b com.youjing.app -m entry_test -s unittest OpenHarmonyTestRunner
  → Tests run: 103, Failure: 0, Error: 0, Pass: 103
```

**过程里差点把 0 读成通过**：第一次我按类名猜 `-s class ResponsiveTest`，
报的是 `Tests run: 0` ——旧教训"检测器报 0 前先反证它抓得到"在这里同样成立，
`describe` 的标签是 `Responsive`（`Responsive.test.ets:21`），改对之后 5 例全跑。
**`Tests run: 0` 不是"没有失败"，是"什么都没跑"。**

意义：§5ci 那条"md 档上限改成 600"从此不只是我手算 + node 跑真函数——
它在真机 runner 里过的是**仓里那份 `Responsive.test.ets`**，
阈值、列数阶梯、对称内缩五档、两档单调性一起钉住。以后谁再动断点表，
这条会先红，不用等宽屏实拍（宽屏实拍仍然要补，两回事）。

顺带纠正一条旧记忆：`harmonyos-ohostest-context-limits` 说"ohosTest 只有 ApplicationContext，
RDB/preferences 拒绝"——那是 **DB/偏好类**断言的边界，纯逻辑与 utils 层的 103 例
在模拟器上全绿。别把那条当成"整个 ohosTest 跑不动"。

### §5ci 续 4：本仓第一次给"展示文案层"配回归（8 例，真机 runner 全绿）

`entry/src/ohosTest/ets/test/DisplayText.test.ets`（已登记进 `List.test.ets`）。
覆盖的都是本轮收口出来的统一入口，且全是纯字符串函数——不需要 DB、不需要权限、不需要眼睛：

- **MoneyText**：`999/1,000/16,000/1,234,567/1,000,000`（整百万是分组最容易错位的一档）、
  负数 `-1,240`（超支场景负号必须留在最前）、`1234.9 → 1,234`（金额无小数语义）、
  `¥0` 必须出字而不是出空（费用页那格不能凭空消失）。
- **TimeText**：`4小时30分钟 / 4小时 / 45分钟` 三档；
  **缺 endTime、时间倒挂、0 时长一律回空串**——这三种态 AI 与重排都造得出来，
  而 `-60分钟` 是"可读的胡说"。
- **广播字符串协议**：`<index>:<时间戳>` 的前缀匹配最怕多档互撞，
  专门钉 `'10:…'` 不算第 1 页签的广播、空串谁都不匹配；
  `draftDirty` 的 `0:` 必须显式写回（不写回首启会凭空冒"继续未完成的规划"）；
  最后一条把**生成器与谓词绑在一起测**（`announceTabShown(2)` 出来的串必须被
  `isTabShownTick(_, 2)` 认，键名直接引 `TAB_SHOWN_KEY`/`DRAFT_DIRTY_KEY` 常量而不是字面量），
  以后谁改了广播格式，这条先红而不是页面静默失灵。

全量从 103 例涨到 **111 例、0 失败**——同时反证了新文件真的被 `List.test.ets` 登记进去
（只跑单类通过不代表注册链通了）。

### §5ci 续 5：杨凌种子与四栈路由补上回归（全量 111 → 118 例）

新两文件已登记进 `List.test.ets`：

- **`YanglingSeed.test.ets`（3 例）**——杨凌是我本轮手写的真实 POI，
  没进原来那个"每城 30-50 行"的城市循环（它是 10 景点 / 5 区域，塞进去必红；
  把阈值调低又会废掉四座大城的质量线）。所以钉的是杨凌该钉的：
  每行都能被 `toSpot`/`toArea` 解析（坏行首启只静默跳过，不主动数就看不见）、
  **坐标必须落在 34.1~34.4 / 107.9~108.3 这个框里**——我给的是按公开街道/村落位置推算的
  近似值，写错一位就会落到西安甚至宝鸡，而地图照样画得出点、肉眼查不出来；
  再加 `DistrictCoords.lookup('杨凌','杨陵区')` 不回落 0/0（缺这一项时整城地图会空白且无报错）。
- **`NavStackRouting.test.ets`（4 例）**——把那个"四个按钮全推在看不见的栈上"的 P0
  修法钉成机器判据：每个页签拿到自己的栈、四条栈是四个不同实例、未知序号回落 `APP_NAV`、
  深链路由落回归属页签。

写这两份时自己踩的两个坑都当场改了：
① 先假设 `DataSeeder.CITIES` 是公开静态再测——`CITIES` 其实是**模块私有 const**，
这条根本编译不过，换成可达的行为判据（`DistrictCoords` 那条）；
② `tabs_do_not_share_a_stack` 第一版里 `seen = [...].map(...).length` **恒等于 4**，
是条永真的假断言，删掉，只留按实例去重的那条。

跑法与结果：`-s class NavStackRouting` → 4/0 失败；
杨凌那份类名是中文、`-s class` 过滤不到（只回空），
但全量从 **111 涨到 118、0 失败**，111+3+4=118 正好对上——
用总数反证两文件真进了 `List.test.ets`，而不是"过滤不到=大概没跑"。

### §5ci 续 6：宽屏那几条"未验项"实拍到了——并且当场抓出我自己贴错的容器

模拟器过了同意弹窗、进游客空间之后，`aa start --ps route <名>` 深链能用（`onNewWant` 会走 `routeTo`），
屏7 / 屏15 / 屏16 因此在 **707vp = md** 下第一次拍到真实 bounds。结果两条要说：

**① 我自己的脚本贴错了容器。** 屏7 第一次量出来内容左缘仍是 `x1=100px = 32vp`（等于没改）。
查下去不是我算的档位错，而是批量替换挑的是**带 `bottom: floatingDockClearance` 的那条 padding**——
屏7 那条在**底部动作条**上，真正通铺的是上面 `.layoutWeight(1)` 的内容列。
补改成同一个 `wideInset()` 后复测：overline `需要决定` 落在 **53.8vp**（正是算出来的 54vp 内缩），
卡内文本 **69.8vp**（54 + 卡内 16），左右缘对齐同一条基线。
教训写死：**批量贴锚点之后必须逐屏量 bounds 反证贴对了地方，"编译过 + 数值对"不等于改在生效的那条链上。**

**② 三条屏的宽屏 bounds 现在都有数**（同一机位、密度 3.125、窗口 707.2vp）：

| 屏 | 修前左缘 | 修后左缘 | 判读 |
| --- | --- | --- | --- |
| 屏1 协议正文 | 62px 起、正文宽 **658vp** | 上限生效，右缘 2043px = **600vp** 边界 | §5ci 那条一行规则改的 |
| 首页预览卡 | 卡体 100→2110（**642vp**，行右侧 55% 空白） | 卡体 169→2042 = **600vp 居中**，两侧各 54vp | 对称内缩 |
| 屏7 | 内容 **32vp** 通铺 | overline **53.8vp** / 卡内 **69.8vp** | 贴对容器后生效 |
| 屏16 | — | 列表内容左缘 **53.8vp** | 与屏7 同一基线 |
| 屏15 | — | hero 与列表 **69.8vp**，分组头跨 65.6→641.6vp | 收进 600vp 一栏内 |

**仍未验的部分要说在前面**：屏15/屏16 这次是**空行程态**（游客空间没有行程，画的是
「行程未就绪」「今日暂无安排」），容器与基线是对的，但**有真数据时的行宽、折行、截断没验**；
手机（sm 档）不受这些改动影响由 `symmetricInsetForCap` 的下限判断与测试第一行钉住。
深链在**未同意/未登录**时会被挡在屏1（本轮又是靠先点游客空间才绕开）——
这条仍挂在待裁决清单里。

### §5ci 续 7：宽屏把屏2 的一排同行人数钮切掉了——本轮没治好，记准确数字与两次失败尝试

进游客空间后走真链到屏2（`第 1 / 5 步 · 基础信息`），md 下实测：

```
同行人数卡：  Button 1  x=1687..1825 (44.2vp)   ← 契约最小热区，正常
              Button 2  x=1837..1975 (44.2vp)   ← 选中态底 #1A0066CC，正常
              Button 4  x=1987..2043 (17.9vp)   ← 被切：应为 138px，实测 56px
裁切边界：Scroll x=168..2043 clip=true
```

三颗圆钮 3×44.2 + 两条 3.8 间距 = **140vp**，而它们被摆成右缘齐 2043（= 卡片的*外框*边），
实际需要的左起点是 1556，被放到 1687——**卡片自己的 md(16vp) 内边距没有作用在这一行的右缘上**，
整行的可用宽度只剩 113.9vp，最后一颗就顶到 Scroll 的 clip 边被切。
同一屏所有字段卡的 x 都是 `168..2043`（600vp），而它们父 Column 的内容区是 `218..1993`（568vp）——
**卡片的 `width('100%')` 落在父级的 border box 上，比内容区每侧各宽 16vp**。
这条与 §5ci 的档位规则无关（把 cap 拿掉也一样会顶边），是屏2 自身的百分比宽/内边距口径问题，
`Responsive.test.ets` 与对称内缩都盖不到它。

**两次尝试都无可见差别，按老规矩不叠第三次**：
① 给 chip 行加 `flexShrink(0)`——bounds 与修前逐像素相同（说明不是收缩竞争，
而是那一行从一开始就只被分到 113.9vp），已 `git checkout` 回退；
②（前一轮）以为把 cap 收到 600 就能留出净空——不成立，卡片的溢出与 cap 同向。

**要治得先定口径**，两条带代价的走法留给下轮（手机在手时一并复拍 sm 档有没有同样的 16vp 溢出）：
- 把字段卡的 `width('100%')` 改成不吃父级 padding 的写法（改动小，但要逐卡复拍，
  且 sm 档现在是否真的没溢出必须先量，不能假设）；
- 或把这排圆钮从"右对齐贴卡边"改成与说明文字同一条左基线（视觉口径变了，属设计取舍）。

**本轮宽屏收口的实际账面**：屏1 / 首页 / 屏7 / 屏15 / 屏16 五处有 bounds 证据（600vp 居中一栏成立）；
屏2 有一处新缺陷、未修，已带数字登记。

补一条同轮实测（免下轮重量）：**屏2 的 600vp 上限本身是成立的**——
终屏文本左缘样本 `168px = 53.8vp`、右缘样本 `2043px = 653.8vp`，
正好是 (707−600)/2 的两侧净空，与屏1/首页/屏7/屏15/屏16 同一基线。
所以屏2 只剩上面那一排圆钮的 clip 问题，不是整屏没收窄。

另外记一条**流程走查的工具边界**（下次别再浪费回合）：模拟器上从屏2 往下推进没成功，
因为 dump 里找不到带「下一/继续/帮我选/生成」文本的推进钮——屏2 此刻可见节点只有
`第 1 / 5 步 · 基础信息` 与四张字段卡，主 CTA 的文本没进 dump 的可见文本节点。
要么用真机（点击与 dump 都正常），要么先用 `uitest` 按节点 id 找钮；
在模拟器上连试两轮选择器已属浪费，第三次不试。

### §5ci 续 8：屏2 那排圆钮查清并修好了——真因是 `constraintSize.maxWidth` 不重测子级

上面「续 7」里我只量到"卡片每侧各溢 16vp"，方向对、机制说错了。真正的证据是 dump 的
**`origBounds` 与 `bounds` 不一致**：字段卡 `bounds=[168,1226][2043,1438]` 而
`origBounds=[51,1226][2161,1438]` ——它的**真实宽是 675vp**（= 707 − 左右 pagePadding 32），
`bounds` 只是被 Scroll 裁出来的可见框。所以不是"父级 padding 没管住右缘"，而是：

> **`constraintSize({ maxWidth })` 只削自己，不重新测量子级。**
> 被削成 600vp 的列里，子级 `width('100%')` 仍按削前的 675vp 约束测量，
> 于是每侧溢 (675−568)/2 ≈ 53.5vp，最右那颗 44vp 圆钮正好顶到 clip 边被切成 56px。

改法：这类"要被削窄的容器"上限挂 **`.width(longFormMaxWidth(...))`** 而不是 maxWidth
——sm 档返回值本来就是 `'100%'`，手机档行为不变；md/lg 给了确定宽度，子级按它测量。
`responsive.ets` 的注释里把这条口径与原因写死了，免得下轮又被"统一改成 constraintSize"顺回去。

**自查抓出我这次批量改的两个错**（都当场改掉，没留到提交里）：
1. `LegalDocReader` 节点上原本已有 `.width(this.readerWidth)`——`readerWidth` 是**调用方传的**
   `@Prop`，我的替换把它顶掉了。这个组件回退成原写法（面板没有再套一层带内边距的父级，
   溢出问题在这儿不存在，两处口径本来就不同，不该统一改）；
2. `LoginView` 被我改成同一节点上挂**两条 `.width()`**，行为虽然后者胜、
   但读起来像"两个宽度在竞争"，删掉多余那条。

**修前后实测**（Mate X7 展开 707vp）：

| 量 | 修前 | 修后 |
| --- | --- | --- |
| 屏2 字段卡 | `orig` 675vp / 可见 600vp（溢出） | `orig == bounds` **568vp**（三张卡同宽） |
| 屏2 同行人数圆钮 | 第三颗被切到 **17.9vp** | 三颗都是 **44.2vp**，最右 1957 < 1993 |
| 屏1 协议段 | `orig` 宽于可见、靠 clip 收尾 | `orig == bounds`，588vp 落在 600vp 一栏内 |

十把尺 exit 0，`assembleHap` 通过。**手机（sm 档）没有重拍**：
按返回值 `'100%'` 与改前 `.width('100%')` 同义推断为零变化，
但这条属推断而非实测，手机连回后要复拍屏1/屏2/屏8 的 sm 档确认。

### §5ci 续 9：真链跑通到屏8（生成的真行程），并修掉屏8 那枚被切的「全图」钮

模拟器上把主链**整条走通**了（游客空间 → 首页主钮 → 屏2 → 屏3 四问 → 屏4 → 屏5 → 生成 → 屏8），
落地的是一条真生成的行程（`北京 · 3天2晚`、Day 1 故宫博物院 → 八达岭长城、`地铁 22分钟 · 2 站`）。
这比逐屏实拍更有分量：**业务流程本身在 md 档也是连得通的**，之前"从我的页签进去按钮失灵"
那类 P0 不会再被"每屏画得都对"掩盖。

顺手把 dump 的 `origBounds != bounds` 当探针扫了一遍终屏，抓出一处真缺陷并修掉：

| 量 | 修前 | 修后 |
| --- | --- | --- |
| 屏8 地图浮层「全图」钮 | bounds 39.7vp，`orig=[1869..2018]` 超出父级内容右缘 1993 → **被卡的 clip 切掉 8vp** | **47.7vp**，`orig == bounds`，右缘 1968 < 1993 |

根因又是一条百分比规矩：**`.width('100%')` 再加横向 `.margin()` 会整体右移、不被扣宽**
（这行原本 `.margin(mapOverlayInset - 8)` = 8vp，于是 100% 宽 + 左移 8 → 右缘溢 8vp）。
改成等值 `padding({left,right,bottom})`：内缩还在、钮不再被切。
与 §5ci 续 8 的 `constraintSize.maxWidth` 那条同族——**百分比尺寸与外边距/上限的组合，
只有 dump 的 orig 对表才看得见，静态审查与截图都查不出来。**

另外两处**量过之后确认不是缺陷**（避免下轮误当 bug 去"修"）：
- 屏3 的钉底条看着像 707vp 通铺，实际那是内层 Row 容器；真正的 CTA 钮在 `1691..2160`，
  左缘 50px 与本屏内容同一条 16vp 基线，是对的。屏3/屏4/屏5 是**双栏 lanes**、
  内容本来就铺满 pagePadding 之内，**给它们加 600vp 上限反而会把按钮与列表错开**——
  所以只有单栏表单的屏2 需要收窄，这个区别是靠量出来的、不是推的。
- 屏8 交通摘要那行 `orig` 比 `bounds` 高 25px，是我新加的 bottom padding 落在卡的 clip 内，
  行内钮与文字都完整可见，属可接受的盒模型差，不是被切。

### §5ci 续 10：dock 四页签带真数据全量复拍，以及一条我差点当成缺陷的假阳性

生成完行程后模拟器里有了真数据，把 dock 四个页签各拍一遍，用
`origBounds` 宽 − `bounds` 宽 > 1vp 当裁剪探针：

| 页签 | 屏 | 真数据在屏上的证据 | app 层裁剪 |
| --- | --- | --- | --- |
| 行程 | 首页 | 「继续未完成的规划」+ 最近行程行都在（草稿续播这条链在 md 也活着） | 无 |
| 地图 | 地图 | `北京 · 3天2晚` / 全程 / Day 1-3 站点 chip | 无（横向 Scroll 的 content 比视口宽属预期，不是溢出） |
| 费用 | 屏11 | `北京 · 2026-10…`、`预算 ¥16,000`、`¥0 已花` | 无 |
| 我的 | 屏12 | `北京 / 旅行中 / 8 景点 / 5 段通勤 / 5 需预约` | 无 |

顺带**结掉一条挂了几轮的未验项**：屏11 的 `noTrip` 与 rootMode 到底跟不跟 `ACTIVE_TRIP_KEY`——
生成一条行程后直接点费用页签，显示的就是这条真行程的预算与已花，说明"跟随当前活动行程"成立。

**假阳性一条，记下来免得下轮重踩**：同一批 dump 里屏15 的副标题
`09:00 开始 · 建议 4小时 · 已过 174分钟` 报的是"可见 171.8vp / 实需 212.5vp"，
看着像 md 下被裁掉尾字、正要照着改布局。真去干净复拍才发现
`bounds == orig == 212.5vp`，**根本没裁**——差别在于前一份 dump 是我自己
点开顶栏溢出菜单后拍的，画面里那枚 `关闭` 结点是弹层控件，
弹层在场时框架给内容层的是被压过的框。
所以判裁剪之前必须先确认**没有 popup/menu 弹层在场**（探针里加一条
`texts 含 关闭 → 这份 dump 不用于判裁剪`），否则就是在给自己的操作痕迹编缺陷。
这条与 §5「幻影缺陷（屏4 灰带被看成右侧切断）」是同一类错误，只是这次的成因是弹层。

### §5ci 续 11：屏11 的 `lanes(2)` 是贴错了对象——报告页不该并栏（已修，实测）

费用页那个「记一笔」主钮在 md 下只有 **337.6vp 且贴左半屏**（`50..1105`），官方预算/实际分段栏
也被压成半宽。查下来不是尺寸写死，而是**响应式贴错了对象**：
`ExpensePage:663` 给整条 List 上了 `.lanes(listLanesForBreakpoint(this.bp))`，
而这条 List 装的是「总览 + 分段栏 + 分类条形 + 最近记账 + 钉底 CTA」——
**一份报告，不是卡片墙**。并栏把每一节都塞进半宽栏里，主钮与分段栏就成了左半边一块。

去掉这一句（并清掉随之变成死代码的 `@StorageProp bp` 与 `listLanesForBreakpoint` import）后实测：

| 量 | 修前 | 修后 |
| --- | --- | --- |
| 「记一笔」主钮 | `50..1105` = **337.6vp**，贴左半屏 | `50..2160` = **675.2vp**，标签 1071..1221 正好居中 |
| 「分类支出」overline | 挤在半栏里 | `87..2123` = 651.5vp 通栏 |

顺带把六个用 `lanes` 的页面全查了一遍，**只有这一页贴错**：
屏12 的「规划新行程」在空态分支里、不在并栏的 List 内 ✓；
屏3/4/5 并的是可重复的选项卡/片区卡/景点行 ✓；屏5b 并的是区域卡 ✓。

**还留下一条没治的（记下数字，不在本轮开新战场）**：分段栏的轨现在仍是
`56..1069 ≈ 328vp` 半宽，与通栏的主钮不一致。要么是 `ImmersiveSegmentBar`
自己按内容定宽、要么是它外层容器的宽度没跟着通栏——得读组件才知道，
而本轮余量不够做完"读码＋改＋复拍"，所以留着，不当已收口。

另：为拿屏11b（超支态）真数据试过在记一笔表单里输金额，
模拟器的**输入法首启流程**连着弹了两次全屏授权（小艺输入法同意、中文键盘布局选择），
把注入的输入与点击整条劫走——属工具边界，不是 App 缺陷，按规矩不叠第三种尝试。
超支态目前仍只有代码路径与文案（`超支 ¥X · 主要来自<类目>`）经过审查，**没有实拍**。

### §5ci 续 12：费用页那枚定宽分段栏贴左的问题——用 ListItem 居中解决（实测）

续 11 留的尾巴查清了：不是容器没通栏，而是这个调用点传了 `itemWidth: 164`
（2×164 = 328vp，**恰好等于 sm 的通栏宽**——是按手机档量出来的定宽）。
md 下内容通栏后它就贴左、右边空出 347vp。
改法是给这条 List 加 `.alignListItem(ListItemAlign.Center)`：通栏的子级本身占满、居中不变，
只有这枚定宽栏被摆到中间。实测两枚标签中心从 308 / 816 → **851 / 1359**，
以屏中心 1105 对称；`分类支出`(1105) 与 `记一笔`(1146) 未受影响。

**过程里自己踩了一次编译错**：第一次把 `.alignListItem(...)` 写在 `List() {` 的花括号**里面**，
`CompileArkTS` 直接 10505001 报三次，而我随后那次"测量"读到的还是旧包
（install 装的是没重新产出的产物）——差点把"数值没变"当成改动无效。
按老规矩先确认 `BUILD SUCCESSFUL` 与产物 md5，再谈测量结果。

未测部分照旧要说：sm 档"定宽栏恰好通栏、居中即无操作"是**推算**，手机没连回来没法复拍。

### §5ci 续 13：**P0——键盘弹起时「记一笔」的保存键不在渲染树里，宽屏上根本记不了账**

为了拿屏11b（超支态）的真数据，在模拟器上把记一笔表单填起来（`uitest uiInput text` 这次通了，
金额框读到 `20000`、分类点了「住宿」），结果**保存这一步做不下去**：

```
键盘弹起后：root y=122..1410          ← 数字键盘占了 1410..2416（322vp 高）
工作表：bindSheet height:'85%'  →  实际可用高 = (1410−122)×0.85 = 1095px = 350vp
表单内容（标题+说明+两个输入框+两行分类+主键）≈ 440vp
保存 在 dump 的渲染树里：False
三次 uitest uiInput dircFling 0 3000（有效上滑）后：False   ← 不是"要滑一下"，是滑不出来
```

所以**在折叠屏展开态记一笔 = 填完金额后无法提交**，费用页与超支态在这台设备这个档位上整条走不通。
这条比本轮修掉的所有排版问题都严重，因为它断的是流程本身。

**为什么滑不动**：`recordSheet()` 里那个 `Scroll` **已经有** `.height('100%')` 和
`.scrollBar(BarState.Off)`——不是"忘了包 Scroll"。合理解释是 §5ci 续 8 那族的百分比口径问题：
`'100%'` 按**键盘弹起前**的约束解析，Scroll 以为自己拿到了 85%×整屏高，
内容也就没"溢出"，可视频口却只有 350vp，于是底部的主键被裁在可见区之外、又没有可滚的余地。
（另一条候选原因是 sheet 没走键盘避让模式，两者都能造出这个现象，**本轮没做完判别实验**。）

**没有在本轮动手的理由**：候选改法至少要试 `SheetSize.FIT_CONTENT` /
定高换成按可用高折算 / 窗口 `setWindowKeyboardAvoidMode` 三选一，
每一条都要重走"填金额→键盘弹起→上滑→看保存是否出现"这条链，
而这台模拟器的输入法首启刚吃掉两轮，剩余预算不够做完"改＋复拍"。
按老规矩不把没验证的改动当修复塞进去。

**顺带结掉/收紧的两条**：
- 屏11b（超支态）仍未见过真数据，但**原因变了**：不是"拍不到"，而是**这条路径在 md 上被上面那条挡住**。
  修好键盘/工作表这条，超支态才能实拍到。
- 其余工作表同一族要一起看：屏10 详情 `'85%'`、协议正文 `'78%'`、屏9 替换 `'70%'`、屏2 城市 `300` 定高。
  只有需要输入的那两枚（记一笔、以及将来若有表单）会撞上键盘高度，别的没输入也许可幸免——
  **这是下轮该逐个量的清单，不是已确认没问题**。

### §5ci 续 14：为这条 P0 做了两次实验，都没产生可见差别——所以它仍未修，账面如实

**实验一 `height: SheetSize.FIT_CONTENT`（替代 '85%'）**：复拍与 '85%' **完全同现象**——
工作表未输入时「保存」在树里（x=405..1805），点进金额框、数字键盘弹起后
`root` 压到 y=122..1410，「保存」从树里消失，`uitest uiInput dircFling 0 3000` 三次仍调不出，
`Scroll` 的 `scrollable` 依旧是 false。**已回退回 '85%'**——但这条要如实记两笔账：
第一次回退用脚本做字符串替换，锚点没匹配上、`assert` 直接抛错退出，
**文件其实一个字没改**，而我照着"已回退"写完提交说明就交了（`6301fc5` 正文里
那句"FIT_CONTENT 已回退"当时是假的）。下一轮先 `grep` 当前状态才发现
`height: SheetSize.FIT_CONTENT` 还在第 699 行，这次补真。
老规矩再次应验：**替换脚本必须断言命中数并回读文件；提交说明按 diff 写，不按意图写**
（同 [[verify-claims-before-commit-message]]）。

**实验二 给两个输入框加 `.enterKeyType(EnterKeyType.Done)` + `.onSubmit(saveExpense)`**：
按 `uitest uiInput keyEvent KeyEnter` 后表单没提交（`已花` 仍 ¥0、工作表仍在）。
但**这台模拟器根本送不进按键事件**——同一现象在 §5ci 续 6 出现过（同意弹窗上
`KeyTab/KeyEnter` 全部无效）。所以这条实验**是"无法判别"，不是"被证伪"**，
不能拿它当"键盘提交没用"的结论。这一对修饰本身零布局代价，先留着，
但它**没有被验证过**，不许写成已解决；真机上按软键盘「完成」是唯一能判别的下一步。

**为什么会走到这一步**：`recordSheet` 的 `Scroll` 已经有 `.height('100%')`，
键盘弹起却不进可滚状态——最像的解释仍是 §5ci 续 8 那族百分比口径：
`'100%'` 按**键盘弹起前**的 sheet 高度解析，Scroll 以为内容装得下，
于是主键被裁在可见区外、框架也不给它滚。要证实/推翻得看
sheet 在键盘态是否重新下发约束，这条留给下一步（也最需要真机）。

**账面**：屏11b 超支态依旧没有真数据；记账在 md 档仍是断的。
这条是本轮结束后**唯一还能称为 P0** 的项（task #9）。

### §5ci 续 15：**P0 修好了，而且是端到端实测**——主键移出滚动区、滚动区改定高

第三次实验成功。做法：`recordSheet` 从「`Scroll { Column { 字段…保存 } }`」改成
「`Column { Scroll(定高 300vp) { 字段… } ; 保存 }`」——**主键不再放进滚动区**，
滚动区也不再吃 `'100%'`。理由承接续 13/14：`bindSheet` 在键盘弹起后不按压缩后的窗口重量高，
所以任何"贴着 sheet 底边"的东西都会被推到可见区之外；
而给滚动区一个**确定高度上限**后，视口 + 紧跟其后的小计 ≈ 370vp 整体落在键盘之上，
主键的位置与 sheet 是否重量高**再无关系**。

实测（Mate X7 展开 707vp，费用页 → 记一笔 → 金额输 `20000`）：

| 状态 | 修前 | 修后 |
| --- | --- | --- |
| 无键盘时「保存」 | 在树里（`405..1805`） | 在树里（标签中心 1105）✓ 未退化 |
| 键盘弹起后「保存」 | **不在树里**，三次 dircFling 也调不出 | **在树里**，`y=1364..1409`，可见区底边 1409 → 落在内侧 |
| 点「保存」 | 无从可点 | 记进账：`已花 ¥20,000`、`已用 100%` |
| 超支文案 | 从未实拍过 | **`超支 ¥4,000 · 主要来自门票`** |
| 分类支出 / 最近记账 | 空态 | `门票 ¥20,000`、`12:27 门票 ¥20,000`（千分位正常） |

**屏11b（费用超支态）因此第一次拿到真数据**——之前"拍不到"的真实原因是这条路径被 P0 挡住，
不是状态不可观测。超支时进度条封顶 100%（`Math.min(100, …)`）与文案分色都按预期成立。

顺带确认：中途那两次失败实验没有白费——`constraintSize.maxHeight` 让 `Scroll` 的
`scrollable` 从 false 变 true，这一步把"stale '100%' 导致不进可滚状态"的机制坐实了，
才推出"别依赖滑动、把主键搬出滚动区"这条。单靠读码想不到这一层。

### §5ci 续 16：同族排查收口——六张工作表里只有「记一笔」具备触发条件

P0 修好后按 task #11 逐个查其余工作表会不会也被键盘把主键推出可见区。
判据不用"我没看到有问题"，用**机制的必要条件**：这条 bug 要成立，
表里必须有能把键盘叫起来的控件（`TextInput` / `Search`），否则窗口高度不会被压缩，
stale `'100%'` 也就无从触发。逐张数过（按 builder 花括号配对取整段正文再扫）：

| 工作表 | 键盘触发件 | 主操作 | 滚动容器 | 判定 |
| --- | --- | --- | --- | --- |
| `recordSheet` 屏11 记一笔 | **有** | 保存 | 有 | **就是这条，已修（续 15）** |
| `detailSheet` 屏10 节点详情 | 无 | 换一个时间 / 加入日历提醒 | 有 | 不会被键盘压缩 |
| `systemAccessSheet` 屏14 触达面板 | 无 | 仅本机保存 / 同意并写入 | 无 | 同上 |
| `docSheet` 协议正文 | 无 | — | 无 | 纯阅读 |
| `replaceSheet` 屏9 替换景点 | 无 | — | 无 | 同上 |
| `citySheet` 屏2 城市选择 | 无 | — | 无 | 300 定高，无输入 |

所以**这条 P0 是同族里的唯一实例**，不是"其他几张我还没验"。
`task #11` 按这个判据关闭。

**仍然留着的一处相关风险（不混淆成已解决）**：`detailSheet` 有两个主操作、内容又在滚动容器里，
键盘虽叫不起来，但如果哪块窗口矮到装不下整段内容，主操作仍可能要滑一下才见得到。
屏10 在 md 的可达性我这轮**没测到**：注入点击走到屏15 顶栏时误开了系统的
「悬浮窗 / 分屏 / 全景多窗」菜单，导航链断在那儿，已把设备复位。
这条挂在 `task #10`（真机复拍时一并走一遍屏10 → 换一个时间 / 加入日历提醒）。

### §5ci 续 17：屏10 详情面板是**同一条 bug 的第二个实例**（还没修，因为这一轮测不到它）

续 16 那句"六张表只有记一笔会踩"说早了。按 builder 花括号配对整段重扫 `detailSheet`
（`ItineraryPage.ets:736..924`，189 行）才发现：**它和 recordSheet 是同一个形状**——

```
L737   Column() {                 ← 工作表根
L739     Scroll() {               ← 滚动区：自己没有任何高度约束
L901       label: '换一个时间'      ← 两颗主操作都在滚动区里
L909       label: '加入日历提醒'
L917     .width('100%')
L918     .padding({...})          ← Scroll 的属性链到此为止，没有 height
L921   .width('100%')
L922   .height('100%')            ← 这条属于 L737 的根 Column，不是 Scroll 的
```

**上一条我写错过一次，是新尺子顶回来的**：我原来说 `L922 .height('100%')` 是
`Scroll` 的属性链、"与 recordSheet 修前一模一样"。做完花括号配对的尺子再跑，
全仓报 0 命中——我去核对缩进与配对才看清：`L922` 属于工作表**根 Column**，
`Scroll` 自己**根本没写高度**。结论方向不变（后果同样是主操作可能落在可见区之外且滑不出来），
但**成因不同**：recordSheet 是 `'100%'` 按压缩前解析、Scroll 以为装得下；
`detailSheet` 是 Scroll 无界，自然按内容撑开，被外层 Column 的可视高裁掉时同样不进可滚状态。
教训并入老那条：**机制句要用能配对/能复算的工具写，不要凭读码的眼力**
（[[verify-the-scanner-before-trusting-a-zero]]）。

之前那次全仓扫描报"0 命中"是**我的窗口只往后看 90 行**，而这两个主操作距 `Scroll() {` 有 162 行——
是扫描器的盲区，不是代码里没有。旧教训第 N 次应验：**检测器报 0 先反证它抓不抓得到**
（[[verify-the-scanner-before-trusting-a-zero]]）。

**为什么这条不必等键盘**：`bindSheet height:'85%'` 在 md 约 657vp、sm 约 731vp，
而详情面板里有「为什么排在这里」的理由正文、备注、预约信息，**长理由 + 短窗口**就能让内容超过这个高；
超过之后 `'100%'` 再次让 Scroll 不进可滚状态 → 两颗主操作滑不出来，
与记一笔那条同构，只是触发条件从"键盘弹起"换成"内容偏长"。

**没有这轮动手的原因（要说清不是偷懒）**：改法与 recordSheet 相同（主键搬出滚动区 + 滚动区定高），
但屏10 我这轮**一次都没打开过**——注入点击走到屏15 顶栏时误开了系统的
「悬浮窗/分屏/全景多窗」菜单，导航断在那里；深链需要 tripId，而 `hilog` 里没有可取的 id。
对一个正在工作且从未拍过的核心面板做结构手术、又无法复拍，等于拿"看着对"替换"验过"。
所以登记为 task #12，要求"改 + 打开屏10 复拍"一起做。

### §5ci 续 18：屏15 有真数据态的宽屏复拍（零裁剪），与"屏10 到不了"的三次失败

生成完行程、记过一笔账之后，模拟器上的屏15 第一次带着**真节点**处于 md 档。
用同一把 `origBounds != bounds` 探针扫：

- **app 层零裁剪**（Text/Button/Row/Column/List 全部 `orig == bounds`）；
- 左缘基线只有 `16.0 / 33.9 / 38.1 / 69.8 / 72.0 / 77.8 / 110.7 vp` 这几条，
  其中 `69.8 = 54(对称内缩) + 16(卡内 padding)`，与首页/屏7/屏16 同一条基线，
  hero、下一站、分组头没有各说各话。

**屏10 这轮仍然没拍到，原因如实记**（不写成"已排查无问题"）：
① 第一次在屏15 顶栏注入点击落在 `y=50`（状态栏），误开了系统「悬浮窗 / 分屏 / 全景多窗」菜单；
② 第二次用 dump 里真正的顶栏按钮 `x=2010..2135 y=267..392`、点其中心 (2072,330)，
   返回的树里**没有「完整行程」**，菜单没弹出来（`屏15 就绪: True` 但 `找到「完整行程」: False`）；
③ 深链 `--ps route Itinerary --ps param <tripId>` 需要 tripId，`hilog -x` 里没有可取的地方。
三次都失败，按老规矩不再叠第四种注入花样（模拟器对弹层/顶栏的注入本来就不可靠，
见 [[hdc-uitest-input-focus-append]]、[[harmonyos-emulator-cli]]）。
**所以 task #12 里那条"屏10 主操作可达性"依旧是未验项，改法也没动**——
不给一个从未打开过的核心面板做无法复拍的结构手术。

下一轮要么用真机（人手动点一下顶栏就能进屏10），要么给 `EntryAbility` 的深链补一条
"无 param 时取 ACTIVE_TRIP_KEY" 的通路，让屏8 能直启——那本身也是"外部拉起"该有的行为，
但它属于新增能力，不在本轮顺手做。

### §5ci 续 19：真机接通——屏8 补上"无 tripId 退到最近一条行程"，屏10 首次实拍

手机（Pocket 2，192.168.3.2:46077，1136×2690 ÷ 3.125 = **363.5vp = sm**）一连上就办成两件事：

**① 屏8 缺行程上下文时的行为与屏11 不一致（已修，真机验证）**：
屏11 早就"没有 tripId 就退到最近一条行程"（注释原话：不给一页 ¥0 死数据），
而屏8 的 `reload()` 只在 `tripId.length > 0` 时加载，**else 什么都不做**——
同一件事两屏两套行为，外部拉起（深链 / 小艺 / 桌面卡片）进来就是一页空白。
补成与屏11 同口径后真机实测：`aa start --ps route Itinerary`（不带 param）
落点直接是用户的真行程「杨凌 · 3天2晚 / Day 1-3 / 地铁 1 段 · 打车 1 段 / 高铁南站-揉谷片区 出发」。

**② 屏10 节点详情面板第一次被拍到**（之前整轮从未打开过）：
从屏8 点时间线行「西北农林科技大学博览园」进入，两颗主操作都在渲染树里、都没截断：

| 主操作 | bounds | 宽 | 截断 |
| --- | --- | --- | --- |
| 换一个时间 | x=175..425 y=2554..2613 | 80.0vp | 无（`orig == bounds`） |
| 加入日历提醒 | x=672..972 y=2554..2613 | 96.0vp | 无 |

屏高 2690，按钮底边 2613 → 在屏内留 77px（24.6vp）**没有被推出可见区**。
所以 §5ci 续 17/18 记的那条"Scroll 无界可能把主操作挤出去"在**手机 sm + 这趟真行程的内容长度下不成立**；
md（707×773vp，sheet '85%' ≈ 657vp）是否成立仍未测——这条继续留在 task #12，
但已经不再是"整屏没见过"，而是"只剩宽屏一档待量"。

顺带：这一轮第 12 把尺 `audit_label_fit.py` 报的一处"定宽放不下文案"被真机推翻
（TEXT 档按钮不吃胶囊内边距），尺子已改、代码已回退，见 `9c6cc6a`。
**真机在手的一个直接好处就是这类推断当天就能被证伪。**

### §5ci 续 20：屏10 两档都拍到了——sm 与 md 都没把主操作挤出去，task #12 按实测关闭

深链补好之后（`e576eaf`），707vp 模拟器也能走"屏8 直落 → 点时间线行"这条真路径了：

| 档位 | 设备/窗口 | 入口 | 换一个时间 | 加入日历提醒 | 判定 |
| --- | --- | --- | --- | --- | --- |
| sm | Pocket 2 真机 1136×2690（363.5vp） | 点「西北农林科技大学博览园」 | 80.0vp 无截断，底边 2613 < 2690 | 96.0vp 无截断 | 可见 |
| md | Mate X7 模拟器 2210×2416（707.2vp） | 点「故宫博物院」 | 80.0vp `orig==bounds`，y 1917..1976 | 96.0vp 同 | 可见（距屏底 440px） |

两档都是 `origBounds == bounds`（没有靠 clip 收尾），
所以 §5ci 续 17 记的"detailSheet 的 Scroll 无界会把主操作挤出可见区"
**在两档真实行程内容下都不成立**——task #12 关闭。

**残留的边界要留一句**：两档各只测了一趟真行程里的一个节点，
理由正文都不长；如果哪天 AI 给出特别长的「为什么排在这里」+ 备注，
内容高度才可能顶到 sheet 的上限。这条不由人盯，交给
`tools/audit_scroll_actions.py`（主操作困在百分比定高滚动区）与
`tools/audit_label_fit.py`（定宽放不下文案）两把尺常驻；
detailSheet 那种"Scroll 没写高度"的形态两把尺都抓不到，已在其源码注释处留痕。

### §5ci 续 21：sm 档全链回归扫出两条真缺陷——屏3/屏5 的主按钮**越出屏幕右缘**

真机在手，把改动过的屏在 **sm（Pocket 2 真机 1136×2690，363.5vp）** 上逐个深链复扫，
探针仍是 `origBounds != bounds`（越界与截断都会现形）：

| 屏 | app 层越界/截断 | 左缘基线 | 越过屏底的可点件 |
| --- | --- | --- | --- |
| 屏2 基础输入 | 0 | 16.0 ✓ | 0 |
| **屏3 偏好追问** | **1** | 16.0 | 0 |
| 屏4 选景点 | 0 | 16.0 ✓ | 0 |
| **屏5 住宿区域** | **1** | 16.0 | 0 |
| 屏8 时间线 | 0 | 16.0 ✓ | 0 |
| 屏11 费用 | 0 | 16.0 ✓ | 0 |
| 屏12 我的行程 | 0 | 16.0 ✓ | 0 |
| 屏5b 全部区域 | 0 | 20.8 ✓ | 0 |
| **地图** | **6** | 16.0 | 0 |

**屏3/屏5 那条不是"文字省略号"，是按钮出屏**：
主 CTA「下一题」`buttonWidth: 150`，实测 `bounds x=713..1136`、`orig` 宽 150.1vp，
**bounds 只有 135.4vp——右边缘正好压在屏幕宽 1136px 上**，
也就是说这颗钮有 15.5vp（48px）被屏幕右缘切掉；屏5 的「去生成」同形。
钉底条上它左边还有说明文案占位，说明这条 Row 在 sm 上没给主按钮留出应有的边距。
本轮**没改**：只剩两回合，凭猜把 150 调大或把 padding 重排，
很可能把屏3 那行别的件挤出屏（左侧是 `layoutWeight(1)` 的说明文字，改谁都有代价），
登记为 task #13 并写明必须连屏3/屏5/屏9 一起复扫（同一钉底条模板）。

**地图那 6 条要分开看，不是一律缺陷**：
`Row 363/1144vp` 是横向 chip 滚动区的内容总宽（预期，本来就该滚）；
但 `Button 71/132`、`Column 53/96`、`Row 53/73` 三处是站点 chip 被压——
底稿 §station 规则明确要求"站名 `max-width 96px + nowrap + ellipsis`"，
53/96 与 53/73 符合契约的省略号形态，**`Button 71/132` 是否属于同一契约口径需要下一轮判定**，
不能因为"帧允许省略号"就把所有命中一并放过。

### §5ci 续 22：更正 `b2fc423` 的标题——只有屏3 修好并验证，屏5 仍未修

那条提交的标题写「屏3/屏5 钉底主按钮…收到 120」，**diff 里只有屏3**。
屏5 那次替换的锚点 `buttonWidth: 150,` 在 `StayPickPage.ets` 里根本不存在
（整页只有一处 `buttonWidth: 200`，L482），断言失败直接退出、一个字没改，
我却按意图把两屏一起写进了标题。真机复测屏5 主键仍是
`bounds 135.4vp / orig [713..1182]`，右缘出屏 46px——**未修**。
那颗 150 不来自本页字面量（大概是某个共用组件的默认宽），
要找就得顺着 `YoujingButton` 的默认宽度去查，本轮回合用尽，留给 task #13（其中屏3 部分已完成并验证）。

同一天在 `6301fc5`→`f53b03c` 已经犯过一次同类错（"已回退"当时没发生）。
两次都是**提交前没有 `git diff --stat` 看清改了哪些文件**。
规矩补一条硬的：写提交说明前先 `git status --short` + `git diff --stat`，
标题里出现的每一个文件名都必须在 diff 里对得上，对不上就改标题或补改动。

### §5ci 续 23：屏5 钉底条不是"宽度写错"，是 sm 档**装不下**——需要一次设计取舍

顺着那颗被切的主键查到底：它 `label: '就住这里'` 没写 `buttonWidth`，吃
`YoujingButton` 的默认 **150**；外面那条 `.layoutWeight(1)` 是**自定义组件上的通用属性，被框架忽略**
（不拉伸），所以它一直是死宽 150。同排另一颗是硬编码 `buttonWidth: 200`，
label 为 **「帮我选（离景点最近）」**——按 `audit_label_fit` 的口径它自己就需要约 **177.6vp**。

于是 sm（363.5vp、内容宽 331.5vp）的算术是：`177.6(副) + 150(主) + 24(间距) > 331.5` →
**这条钉底栏在手机上根本放不下两个控件**，`Blank()` 塌成 0 之后主键被顶出右缘 46px。
我写脚本准备把 200 收到"反推可用宽"，脚本里的守卫算出 `需要 177.6 > 可用 157` 就**拒绝改动并退出**——
这正是我想要的行为：不能为了把一个按钮塞进去就把另一个的文字截掉（那只是把缺陷从右边挪到中间）。

**留给用户拍三条走法（各有代价）**：
1. 副键文案改短（如「就近选」/「帮我选」+ 说明移到别处）→ 视觉最省，但"离景点最近"这个卖点从字面消失；
2. sm 档把两颗钮改成上下堆叠（主键整行、副键在其下为文字钮）→ 都不截断，但钉底条变高、要吃更多 dock 净空；
3. 主键也走自适应宽（`fullWidth` 之外还要真把 `.layoutWeight` 生效——只能靠原生 Row 子层包一层，属结构改动）。
屏3 那条已按"主键本身文案只需 120"修好并真机验证；屏5 这条**登记为待决策，不是待改数字**。

### §5ci 续 24：更正续 23——屏5 不是"sm 装不下"，是 `.layoutWeight` 写在自定义组件上被静默忽略

续 23 的算术没错（200 + 150 + 24 > 331.5），但**前提错了一半**：我把主键当成
"要吃剩余宽"的件，实际它写的 `.layoutWeight(1)` 挂在自定义组件 `YoujingButton` 上，
**框架对自定义组件的通用属性不生效**，所以它一直是默认死宽 150 而不是被压住。
把权重移到原生 `Column` 包装层、主键改 `fullWidth: true` 之后，两个控件在 sm 上就同时放得下了：

| 量 | 续 23 的判断 | 真机复测（`8640a17`） |
| --- | --- | --- |
| 主键 bounds | 135.4vp、右缘压 1136px（出屏 46px） | **x=713..1087、119.7vp、`orig == bounds`**，距屏边 49px |
| 两段文案 | 需 177.6 + 150 才能放下 → 判为装不下 | 「帮我选（离景点最近）」113..613 完整、「就住这里」800..1000 完整 |
| 结论 | 要用户拍三条设计走法 | **不需要任何取舍，两条都保住**；task #13 关闭 |

教训两条：① **自定义组件上挂通用属性（`layoutWeight` 这类）会被静默忽略**，
这是"看起来写了却没用"的一类新形态，与前几轮的 `constraintSize.maxWidth 不重测子级`、
`width('100%') + margin 溢出` 同族；② 当算术说"装不下、只能牺牲一边"时，
**先怀疑是不是某个属性根本没生效**，不要立刻升级成设计取舍去麻烦用户——
这次我差点就把一个纯实现 bug 报成了产品决策。

### §5ci 续 25：sm 档全链复扫 8 屏——本轮改动在手机上零回归（含记一笔键盘态）

真机（Pocket 2，1136×2690 = 363.5vp）逐个深链复扫本轮改过的屏，探针同前
（`origBounds != bounds` 或 `bounds 右缘 > 1136` 记为异常）：

| 屏 | 异常 | 屏 | 异常 |
| --- | --- | --- | --- |
| 屏8 时间线（你的杨凌行程） | 0 | 屏3 偏好追问 | 0 |
| 屏11 费用 | 0 | 屏4 选景点 | 0 |
| 屏12 我的行程 | 0 | **屏5 住哪一片** | **0**（`8640a17` 修后） |
| 屏2 基础输入 | 0 | 屏5b 全部区域 | 0 |

**记一笔工作表在手机键盘态也验了**：`保存` 在渲染树里、`x=518..618 y=1495..1554`，
屏幕可用底边 1642 → **可见**。这条同时反证了 §5ci 续 15 那个修法
（主键出滚动区 + 滚动区定高）没有把手机档做坏——手机原本能点的按钮仍然能点，
宽屏则从"完全点不到"变成能点。

至此本轮所有落地改动的两档账面：**md 6 屏 + sm 8 屏都有 bounds 证据**；
仍欠的只剩 屏10 超长理由文案在 md 的边界、屏6 生成中态、屏13 桌面卡片、地图那颗 `Button 71/132` 的形态判定。

### §5ci 续 26：屏10 在 md 又复测一次（真行程内容），超长文案这条**故意不去测**

md（707.2vp）从屏8 点「故宫博物院」进详情：两颗主操作都在树里、`orig == bounds`、
`y=1917..1976` 远在屏高 2416 之内，面板里最长的文案是
「南锣鼓巷-鼓楼 出发 · 第 1 日 · 标准」（39 字）这个量级。

**剩下的"超长理由文案会不会把主操作挤出可见区"这一条，我没有去造数据测**：
要测就得往真行程里塞一段假 AI 理由，而屏10 是用户天天看的屏——
为了一条理论边界去污染可复现的真数据，不如把它写成"由尺子和代码约束兜住"的已知风险。
兜它的两条现有手段：`audit_scroll_actions.py`（主操作困在百分比定高滚动区）
与 `audit_label_fit.py`（定宽放不下文案）；detailSheet 那种"Scroll 没写高度"的形态两把尺都抓不到，
已在 §5ci 续 24 记为教训（自定义组件上的通用属性会被静默忽略）。

### §5ci 续 27：地图那 6 处命中判完——是横向站点条正常工作，判据用的是行为不是几何

真机（sm）深链进地图，逐个定位 `origBounds != bounds` 的节点：

| 命中 | 定位结果 |
| --- | --- |
| `Row 362.9 → 1143.7vp` | 站点条 Scroll 的**内容总宽**（3 颗 chip + 间距），本来就该滚 |
| `Button 71.0 → 132.2vp` | 第 3 颗 chip「杨凌渭河生态公园」**半露在视口右缘** |
| `Column 53.1 → 96` / `Row 53.1 → 73.3` / `Text 42.2 → 62.4` | 同一颗 chip 的内层节点，被视口裁 |
| `Stack/RelativeContainer 347.5 → 363.5`（y=20..95） | **系统状态栏**那层，不是本 App 内容 |

关键一步是**不去用几何下结论**（旧教训：判回归要量行为边界）：
在站点条上做一次 `swipe`，第 3 颗从 `x=969..1135 完整可见=False`
变成 **`x=66..366 完整可见=True`** —— 滑得出来、内容不被吃，
所以这是底稿要求的横向站点条正常形态（chip 半露本身就是在暗示"右边还有"）。
**地图页判定：无缺陷**，task 清单里那条"71/132 待判"就此了结。

至此本轮所有 `origBounds` 命中的处置完毕：
真缺陷 3 处（屏2 圆钮、屏8 全图、屏3/屏5 主键出屏）已修并真机复测；
其余命中要么是百分比/弹层造成的读数假象，要么是横向滚动条的预期形态。

### §5ci 续 28：屏16 在真机 sm 复测——路线图带的"只画前 6 站"如实播报

从屏8 顶栏进入屏16，真机实测渲染文本：
`分享这份行程 | 杨凌 3天2晚 · 8 … | 1 2 3 4 5 6 | 共 8 站，图上只画前 6 站 | 3 天 8 站 …`

两件事同时成立：
- 之前删掉空占位、用**真实节点数**补的那条编号节点带，在真行程（8 站 > 6）上
  按承诺只画 6 个圆点、并在副标题里**报出真实站数**，没有假装画全；
- 统计格「3 天 / 8 站」与顶栏副标题同源同一趟行程，屏16 整屏 `origBounds` 异常 **0**。

顶栏两颗钮（x=811..936、961..1086）在真机上注入点击是可以直达动作的
（模拟器上弹不出来那条仍是工具边界，不是 App 缺陷）——
这条也顺手记下来，免得下轮又去模拟器上试顶栏。

### §5ci 续 29：屏9「保存修改」也被切出屏幕——同一根因的第三种表现（已修真机验证）

顺路把链上最后一屏（屏9）在真机 sm 复测，抓到一颗异常钮：
`bounds x=463..1136`、可见 215.4vp、右缘正好压在屏幕宽上 —— **主键被切掉约 136vp**。

根因与屏3/屏5 同源但表现不同：这里写的是 `fullWidth: true`，
而 **`fullWidth` 在 `Row` 里等于"父级 100%"**（sm 内容宽 331.5vp），
同排还有一颗 120vp 的「撤销」+ 16vp 间距 → `120 + 16 + 331.5 > 331.5` 必然溢出。
也就是说这个家族有三种写法都会踩同一个坑：

| 表现 | 错误写法 | 后果（sm 实测） |
| --- | --- | --- |
| 屏3 | 主键定宽 150 + `Blank()` | 主键出屏 15.5vp |
| 屏5 | `.layoutWeight(1)` 挂在自定义组件上（被忽略） | 主键出屏 46px |
| **屏9** | **`fullWidth: true` 放在有兄弟件的 Row 里** | **主键出屏约 136vp** |

统一修法：**剩余宽用原生件承载（`Column().layoutWeight(1)`），主键再 `fullWidth` 填满它**。
真机复测：撤销 `x=50..425`（120.0vp）、保存修改 `x=463..1087`（199.7vp、`orig == bounds`、
距屏边 49px），两段文案完整，屏9 底部异常 **0**。

另外纠正一条我自己差点写错的判断：屏8 顶栏那颗溢出钮在 dumpLayout 里"点了没反应"，
截图一看菜单**是弹出来的**（「编辑行程 / 写入系统与提醒」都在）——
是 dump 抓不到弹层，不是 App 断链。教训：**弹层类交互要用截图判，不要用 dump 判**。

### §5ci 续 30：把这个家族做成第 13 把尺，顺手又抓到 5 处同源写法

上一轮的三种表现（屏3 定宽+Blank、屏5 权重挂自定义件、屏9 `fullWidth` 有兄弟件）
不是三个孤立 bug，是**同一条 ArkUI 盒模型规则**被踩了三次。所以做了
`tools/audit_button_width.py`，把**语法层面就能判死**的三类写成常驻尺：

| 规则 | 判据 | 为什么静态就能判 |
| --- | --- | --- |
| A | `fullWidth: true` 的 `YoujingButton` 直接挂在**有 ≥2 个非 Blank 兄弟件**的 `Row` 里 | `fullWidth` 在这种位置解成父级 100%，与兄弟宽度相加必然溢出 |
| B | `.layoutWeight(...)` 的属性链**直接挂在自定义组件上** | 框架静默忽略，"吃剩余宽"的意图 100% 落空 |
| C | 同一条链上既有 `.width('100%')` 又有**含横向的 margin**（对象式 `left/right` 或单值四边） | 实际占位 = 100% + 边距，必然往两边溢出 |

第 ④ 类「定宽 + `Blank()` 的算术到底够不够」（屏3 的原始形态）**故意没进这把尺**：
它要真机宽度才能判，静态估算正是 `audit_label_fit.py` 造出假阳性的那条路。

尺子自带的 `--probe` 反证时先失败两次，两次都是尺子自己的漏洞，值得记：
1. 属性链是从**抹掉字符串的掩码文本**里截的 → `.width('100%')` 里的 `'100%'` 已被抹成空格，C 类永远抓不到。改成结构用掩码、**取值用原文**。
2. 直属子件只排除了「落在别人实参括号里」，没排除「落在别人**正文**里」→
   把 `Row { 副键 Column { 主键(fullWidth) } }` 这个**标准修法写法**报成 A 类违规。
   两道都排之后，阳性样本（A/B/C 各 1，C 要对象式与单值式各 1）全抓到、修法写法不报。

全仓扫出 **5 处**（A 类 0 处＝上轮三屏的修法没被回退）：

- **B 类 3 处**：`ItineraryPage:920`（屏10 详情面板底排）、`ItineraryPage:1054`（屏14 系统触达）、
  `SpotPickPage:434`（屏4 确认选择）。三处都是主键写 `.layoutWeight(1)` 挂在 `YoujingButton` 上、
  实际一直是默认死宽 150、右缘不贴内容边。改成 `Column().layoutWeight(1)` + `fullWidth: true`，真机复测：
  - 屏10：`换一个时间` Button `x=50..550`（160.0vp）、`加入日历提醒` Column/Button `x=588..1087`（159.7vp），
    主键右缘**贴上内容边**、文案 `orig == bounds` 无截断。
    （改前的 1069 是按默认死宽 150vp 推算的位置，没拍到实图，只作差值参考。）
  - 屏4：`跳过选择` `x=50..425`（120.0vp）、`确认选择` `x=463..1087`（**199.7vp**；改前按 150vp 死宽推算右边会空约 50vp）——
    与已修的屏3/屏5/屏9 同一条几何（副键 50..425 + 主键 463..1087），五屏钉底条至此同构。
- **C 类 2 处**：`StayPickPage:433`（地图不可用兜底里的候选片 `Flex`，外层 `Column` 已给左右 md padding，
  再叠 margin 就是 100%+32）→ 删掉多余 margin；`TodayTripCard:188`（屏13 Widget B 的编号站点底线，
  原写 `width('100%') + margin({left:md,right:md})`，线**根本缩不进去**）→ 让位改交给外层 `Row` 的 padding。

**这两处 C 类是"改了但没拍到"的**，口径要说清：`StayPickPage` 那处在"该城市暂未提供位置信息"的兜底分支里，
当前草稿（北京）有坐标、进不去；`TodayTripCard` 那条只有 **2×4 卡**才画站点条，桌面现在挂的是 **2×2**
（真机 dump 证实卡内是三行 `Circle` 列表、没有条带）。两者都不打算靠造数据去凑一个状态，
等 2×4 卡上桌面（需要动用户桌面，属用户决定）或遇到无坐标城市时再补拍。

十三把尺本轮全绿（`audit_contrast` 仍需要设备在位）。

### §5ci 续 31：屏7 一次性抓到四条——内部术语上屏、条数写死、裸 Error、正文被动作条盖住

为了拍屏6 顺着流程走了一遍（模拟器 md 档），结果生成失败落在屏7，
而**屏7 这一屏自己就是本轮最集中的一批缺陷**（截图 `md-屏7-生成受阻-文案修后.jpeg`）：

1. **校验术语直接铺给用户**：副标题那行写的是 `两次生成均失败: days 不能为空数组`——
   `days`/`数组` 是 `TripParser` 的校验话术。原来 `detailText()` 的口径是"debug 版露原始诊断"，
   但 debug 版正是用户手上这一版。改法：新增 `failureDetail(code)`（与 `failureHeadline` 同一张纯映射表，
   进 hypium），**主副标题两版同一句人话**；原始诊断在 debug 版**另起一小行、明确标「调试：」**。
2. **条数写死在文案里**：标题「两条可行修法」，而 `fixes` 数组早已是三条（第三条"换一片住宿再试"
   是补通勤出口时加的）。真机两档都拍到了自相矛盾。改成 `${this.fixes.length} 条可行修法`。
   教训：**写死的数量词就是未来的 bug**，凡是"下面有 N 个"的文案一律从数组取。
3. **裸 `Error` 上抛把错误码丢了**：`GeneratingPage` 缺住宿时 `throw new Error('住宿区域缺失')` →
   屏7 拿到 `code=0`，标题落到兜底「生成没能完成」，明明 `ErrorCode.TRIP_NO_AREA_SELECTED(4003)`
   和对应文案都在。改成 `AppError(4003, …)` 后 md 实测标题「还没选住宿区域」、
   副标题「要先定下住哪一片，通勤起点才算得出来」、调试行「调试：住宿区域缺失」。
4. **正文被钉底动作条盖住（md）**：这一屏是 `Stack(Bottom) { 正文 Column; 三颗钮 Column }`，
   正文不滚、动作条浮在上面 → 第三条修法「把每天的节奏调松」整行被「再试一次」压住，**滑不出来**。
   改成两段流式布局：正文段 `Scroll().layoutWeight(1)`，动作段排在流内。
   行为验证（不是量几何）：改后在 md 上滑一下，三条修法 `y=1053/1200/1346` 全部完整露出、
   没有任何一行落在按钮底下；改前那第三条是**永久不可达**。

两档复测：sm 屏7 全部文本 `orig == bounds`、零截断（正文本来就装得下，布局改动无回归）；
md 首屏仍会在折叠线切一行——那是"还能往下滑"的正常提示，不是遮挡。

配套回归：`FailureCopy.test.ets` 加两条——已知码的 detail 句逐字对表，
以及**"任何错误码的副标题都不许出现 `数组`/`schema`/`JSON`/`null` 这类内部词"**。
真机 hypium 全量 **120/120 通过**（原 118，加 2）。

### §5ci 续 32：进度条的可及名补齐，同时撞出一条**工具边界**——dumpLayout 根本不暴露 accessibilityText

走流程时屏4 的容量条在 dump 里是 `Progress text='0.000000'`（上一轮是 `100.000000`）。
读屏软件念的就是这个框架内部比例。全仓 6 处 `Progress(` 一处可及名都没写：
`TripsPage:302`、`GeneratingPage:164`、`ExpensePage:272`、`ExpensePage:570`、
`SpotPickPage:357`、`OnTripPage:666`（`OnTripPage` 那条注释里"真机实测 1.000000"其实早就撞见过）。
逐处补上带上下文的句子（`已选 N 个景点，按 X 天建议上限 Y 个` / `预算已用 N%` / `本程已完成 N%` …），
并把第 10 把尺 `audit_a11y_name.py` 的受管控件从 8 类扩到含 `Progress`/`Gauge`
（`LoadingProgress` 靠 `(?<![A-Za-z0-9_])` 天然排除，probe 里做了反证）。

**边界（这条更要紧）**：补完之后在模拟器上复拍，`Progress` 节点的
`text/description/hint` 仍是 `0.000000 / 空 / 空`。同屏 12 颗**已知写了 `accessibilityText`
的 Button** 在 dump 里 `desc` 也全是空——
所以 **`uitest dumpLayout` 不暴露应用侧 accessibilityText，它不是这项的判据**。
这一条改动只能算"代码级 + 静态尺子"两重保障，**读屏真声未验**（要验得开屏幕朗读，
那是用户设备上的可见改动，没做）。教训和"弹层要用截图判、不能用 dump 判"同族：
**先确认这把尺量得到，再拿它的 0 说事**——否则会把"抓不到"当成"没写"或"写好了"。

另记一条 md 实测：屏4 主键经家族修法后在 md 上吃到 `x=463..2161`（**543.4vp**），
副键 120vp。它在 DESIGN 契约 720 的内容宽以内、也与其余四屏同构，本轮不动；
若要在宽屏收主键宽度，那是一次独立的设计取舍，需要用户点头。

### §5ci 续 33：深色档第一次成规模走查——做了个只钉 App 的 darkprobe，量出 1 处真低对比

深色档此前一直走不了：本机没有 `settings` 命令可切系统深色（第 4 把尺的文档里就写着这条），
而把用户的手机翻成深色去截图是他设备上的可见改动。
解法是 **App 级** `setColorMode(COLOR_MODE_DARK)`，只在 debug 版、只在显式带参数时生效：

```
aa start -b com.youjing.app -a EntryAbility --ps darkprobe 1 [--ps route <屏>]
```

第一次做出来是假的：日志 `isDarkMode=true`、截图却整屏浅色。原因是
`onWindowStageCreate` 里那句"跟随系统"的 `setColorMode(NOT_SET)` 在 `onCreate` **之后**跑，
把探针又翻回去了（`EntryAbility` 里已加 `darkProbe` 门控跳过这次复位，并写了为什么）。
这条值得记：**判断"深色没生效"之前先确认是谁把它复位了**，别去改 token。

修好后真机 sm 逐屏量（帧存 `~/Pictures/有径/走查帧-2026-10-27/dark-*.jpeg`）：

| 屏 | 低于阈值 |
| --- | --- |
| 行程 / 费用 / 我的行程 / 行中 / 屏2 / 屏3 / 屏4 / 屏9 / 屏16 / 屏7 / 我的 tab | **0 处** |
| 屏8b 地图 tab | 编号 `1/2/3` 3.55~3.63、`我的` 4.49 |
| 屏5 选住宿 | `20分钟`/`40分钟` 2.48/2.58 —— **这两条是假阳性**，见下 |

**唯一一处真低对比**：地图 tab 底部站点卡的编号 `Text(\`${stop.index}\`)` 用 `primary` 写在卡面上。
按 `resources/dark/element/color.json` 精算（像素法在 4.5 附近不可信，JPEG 噪声会压低细字）：
`primary #0A84FF` 对 `surface_panel` = **4.03:1**、对 `surface_subtle` = 4.30:1，
而它是 12vp/600 的小字 → AA 门槛 4.5。浅色档同一对是过的，**这是深色档 token 配对本身的问题**，
不是某处写错颜色：要么给深色档的小号品牌字另给一档更亮的蓝（动契约），
要么把编号从品牌蓝退到 `body`（6.21:1，但丢掉"编号=地图气泡号"的呼应）。
两条都要改设计口径，**留给用户拍**，本轮不擅自动 `~/Pictures/有径/…/DESIGN.md` 那一侧。
`我的` 4.49 是悬浮 dock 的**玻璃**标签，底色是底下地图的模糊，随内容变——不是色对失败。

**假阳性那条把第 4 把尺的两个洞补上了**：屏5 那两个框在 dump 里是
`x=100..240 y=2309..2360`，裁出来里面**根本没有字**——列表视口外的节点 dump 仍给完整 bounds，
框采到的是 dock 的圆角边。于是加了两道判据：① 差异像素覆盖率必须在 1%~60%（字形区间）；
② **有差异的行数占比 ≥20%**（真字形一行行铺开，一条边只占两三行）。
加完 `20分钟` 被正确排除；`40分钟` 仍漏（圆角边斜穿整框，逐行都有点）——
肉眼核对已确认它未渲染，**这条残留边界写在这里**，不再拿它当缺陷。

### §5ci 续 34：地图卡编号改实心蓝底 + on_primary——上一轮那条"留给用户拍"其实不必等

续 33 把深色档唯一一处真低对比（地图 tab 底部站点卡编号 4.03:1）当成"要动契约、留给用户拍"。
复核后发现**不用动契约**：契约 §8 本来就写着"深色下实心语义色上的标签用 `on_primary`"，
而 `on_primary` 对 `primary` 这一对浅色 5.57 / 深色 5.14 **两档都过**。
所以改的是**用法**（裸品牌蓝小字 → 实心蓝圆 + `on_primary` 数字），token 一个没动。
顺带把卡片编号和地图气泡编号变成同一种语言——原来气泡是蓝底黑字、卡片是蓝字，
本来就是同一站点的两个视图却各说各话。

两档同机位复拍（`dark-Map-编号徽章后.jpeg` / `light-Map-编号徽章后.jpeg`）：
深色档编号 `1/2/3` 从低对比名单里消失，浅色档 **0 处**（无回归），
节点 bounds 也从文字尺寸变成 18×18vp 圆。
地图 tab 深色档仍剩 `地图` 3.09 / `我的` 4.49 两条——那是悬浮 dock 的**玻璃**标签，
底色是底下地图的模糊、随内容变，不是色对失败，不在这一轮动。

教训：报"要用户拍"之前先回去读契约。这次契约里已经有答案，是我先把它当成了设计缺口。

### §5ci 续 35：屏13 2×4 卡按帧重排——原来不是"线缩不进去"，是整张卡装错了 Widget A

用户点头后把 2×4 卡加上了桌面（桌面第 4 页，与 2×2 并排），第一次实拍就把上一轮的判断推翻了：
站点条那条线**本来就画对了**（`Row` padding 让位后，线尾正好落在首末节点圆心 `x=140..996`，
节点圆 `103..178 / 958..1033`，圆心 140.5 / 995.5 —— 与帧 `.route-line{left:12px;right:12px}` 同解）。
真问题在**整屏排版**：2×4 里画的是 Widget A 的全套（日标签、meta 各占一行、三行时刻表、页脚）
再补一条站点条，而 **2×4 与 2×2 净高相同（都是两行格子），只是宽一倍** →
页脚 `y=2168` 落在卡底 `2163` 之外，**整条页脚在真机上根本没画出来**。

读帧 `屏13_有径-万能卡片_7fc1cb85/code.html` 的 Widget B 段，它给的排法是
**日标签与 meta 并成一行**（`justify-content: space-between; align-items: baseline`）+ 站点条。
照它并成一行的省出的 77px 正好还给站点条；时刻表在宽卡限到三行（`visibleRows()`），
总站数由站点条报，页脚在宽卡不再要那 4vp 上边距。真机复测：
**出卡文本 0 条**，页脚 `y=2116..2156`（离卡底 7px），三行站名在宽卡**不再截断**
（2×2 上同一批站名全是 `…`）——宽卡的价值这次真的兑现了。

顺手纠正我自己上一轮写进文档的一句：当时把 C 类那处判成"改了但没拍到"，
其实拍不到不是因为进不去分支，而是**我拿的是 2×2 的桌面**。以后"进不去的状态"
要先问一句是不是设备/尺寸没摆对，再下"造数据才能到"的结论。

### §5ci 续 36：屏11 分类预算落地（用户口径"都要"）——存储、工作表、行内对照三段

**数据层**：`trip` 表加 `category_budget` 一列（v6→v7 迁移，存量行默认 `'[]'`，
真机日志见 `迁移完成 6 → 7`）。纯逻辑单独成文件 `utils/CategoryBudget.ets`
（解析 / 取上限 / 画条基线 / 百分比）——埋在 TripDao 里就等于测不到（ohosTest 拿不到 RDB）。
解析口径：**只认六档稳定码、只收正数，脏条目整条丢掉而不是猜**。

**交互**：「分类支出」分组头右侧加 `分类预算` 入口 → 工作表六档各一个数字框，
留空 = 该类不设上限；合计行实时跟着草稿走，超过行程总预算时整行转 danger（只提示不拦保存）。
主键在滚动区之外、滚动区吃定高上限（记一笔那条 P0 的形状）。

**行内对照**：设了上限的分类，进度条**改按自己的上限画**（不再一律占总额），
右侧从一行变两行：`¥实花` + `上限 ¥X` / `超 ¥Y`（超了整行转 danger），
进度条可及名也带上限。没设上限的分类保持原样。

真机（Pocket 2，sm）验证到的：
- 工作表打开、两档填 6000/2000 → 合计行实时 `合计 ¥8,000 · 行程总预算 ¥16,000`；
- 保存 → `saveCategoryBudgets trip-… n=2`；
- **冷启后重开仍回填** `TI='6000' TI='2000'`、合计 ¥8,000 —— 这条才是"落到存储"的判据，
  只看工作表收起证明不了（内存里也长这样）；
- hypium 新增 4 例（脏 JSON、稳定码封闭、0 是"不设上限"的哨兵、封顶/除零），全量 **124/124**。

没验证到的，写清楚：
1. **行内两行对照没实拍**——手机上的杨凌行程 `已花 ¥0`，分类列表还是空态。
   要拍到得有真实记账；不打算为了截图往用户行程里塞假支出。
2. **键盘弹起时「保存」点不到**（真机踩到一次：脚本第一次点保存没生效，收起键盘后再点才落库）。
   已把滚动区上限从 320 收到 200、sheet 从 70% 收到 55%，并给最后一档加 `Done + onSubmit` 作并列通路；
   但 IME 键注入不到（与记一笔那条同边界），**这条键盘路径未做真机验证**。

### §5ci 续 37：地址不再让模型写——提示词第 12 条 + 按景点库回填（用户拍板的「省 token 第一刀」）

**动机**：真机直连实测 3 天行程花掉 ¥0.21，用户明确说贵。逐段看输出构成，模型把每个活动的
地址整段重写（「北京市延庆区八达岭镇八达岭长城景区」）占了可观一块——而这些字段**景点库里本来就有**，
模型重写既烧 token，又多一个写错地址的幻觉面。

**改动三段**：
1. 提示词第 12 条：`address` 一律空串、`longitude/latitude` 一律 0，明确告知「App 按景点库回填」；
2. Schema 侧同步放开：`address` 从 `required` 移除、允许空串；`TripParser` 用新增的
   `strOrEmpty` 解析（缺字段→空串，类型错仍报）。只改提示词不改守卫会以
   `address: 期望非空 string` 失败——这条在真机撞过一次；
3. 新增纯逻辑 `utils/TripEnrich.ets`：先精确同名、再退「一方完整包含另一方」（模型常加
   「北门」「景区」），**匹配上就以库为准覆盖**（库是溯源过的真值，模型写的那份非空也不可信）；
   匹配不上原样保留不猜；活动地址仍为空时用 `trip.destination` 兜底，屏8 的 meta 行不留白。
   `LlmClient` 在其后调用并打日志 `回填地址 N 条`。

**离线同题量测**（走 App 自己的 PromptBuilder/TripParser，非手工构造）：
`PARSE OK days=3 acts=21 meals=9`、`回填 12/21 条`（其余 9 条是库外自造活动如「午餐：蘸水面」，
走目的地兜底）、输出 **2927** token（同题基线 3723，**−21%**）。

**顺带抓到一条测试完整性问题**：`USE_MOCK_DATA` 翻成 false 后，`LlmPipeline` 里三条离线闭环用例
跟着全局开关去打真 DeepSeek——既超 hypium 5s 用例时限（`Error: execute timeout`），**又在花真钱**。
已改为显式传 `MockLlmTransport`（新增 `genOffline` 帮手）。口径：**离线用例的传输层必须是显式参数，
永远不跟全局开关走**。

**真机验证**：新增 `TripEnrich.test` 4 例（空值回填 / 模型地址被覆盖 / 后缀匹配 / 库外落目的地），
全量 **128/128 通过、0 Error**（三条原超时用例恢复）。真模型跑一遍新管线的账单对照，等下一次真机生成时读日志
`LLM 用量 model=… in=… (cache 命中 …) out=…` 与 `回填地址 N 条`。

### §5ci 续 38：屏11 补齐取证时抓到三个真缺陷——「记一笔」整颗按钮点不动是其一

为了拍「分类预算行内两行对照」这张图，真机走了一遍记账，连带查出三处：

1. **「记一笔」点了完全没反应**（P0，屏11 唯一主操作）。根因：`rootShell` 的根 Column 上
   连着挂了 **两张 bindSheet**（记一笔 + 分类预算）。一个节点只能挂一张，后挂的覆盖前一张——
   分类预算的 sheet 上线时，把记一笔的绑定顶掉了，按钮的 `showRecord=true` 也就无处可弹。
   修法：记一笔的面板挂回它自己的按钮。**规矩：一个节点只挂一张 bindSheet，多张面板分挂各自宿主。**
2. **冷启后第一次进「费用」看错行程**。`@StorageProp` 的初值不触发 `@Watch`，本页又是新建的，
   于是只走 `reload()` 的空 tripId 分支退到 `rows[0]`；用户刚打开的是行程 B，账单却是 A。
   修法：`aboutToAppear` 先认 `activeTripId()`（最后打开的那条），没有才退最近一条。
   真机判据：冷启 → 打开杨凌 → 切「费用」，副标题从「北京 · …」变成「杨凌 · …」。
3. **行内第二行的 `margin top: 2` 不在间距阶梯上**（第 7 把尺 `audit_geometry` 报 1 项），改 `SpaceTokens.xs`。

**取证结果**（Pocket 2，sm，两张假账拍完即删、已花回到 ¥0）：
- 交通（上限 2000，实花 2500）→ `¥2,500` + **`超 ¥500`**（danger 红）；
- 住宿（上限 6000，实花 800）→ `¥800` + `上限 ¥6,000`（muted）；
- 全部文本节点 `origBounds == bounds`（0 处裁剪）；
- 截图：`~/Pictures/有径/走查帧-2026-10-27/sm-屏11-分类预算行内对照.jpeg`。

**没验证到的**：删除走的左滑→垃圾桶→确认框链路是脚本注入的（本次两笔记账都删成功、
列表与总额都回到空态），但「键盘弹起时保存键是否可达」这条老 P0 仍未修（同 §5ci 续 36 第 2 条）。

### §5ci 续 39：「记一笔」六档分类只看得见三档，默认那档恰好在视口外——同步否掉 FIT_CONTENT

续 38 修完按钮之后，第一次把「记一笔」面板本身看全（此前只 dump 到三枚胶囊）：

1. **默认分类不在屏上**。面板滚动区定高 300vp（键盘避让的产物），标题+副标题+两个 72px 输入
   已经吃掉 254vp，留给分类 46vp；六档胶囊按 `Flex(wrap)` 排两行（44+8=52vp/行），
   第二行整行落在视口外——而默认选中的**门票**就在第二行。真机 dump 里树上只有
   住宿/交通/餐饮三枚、且三枚都未选中；用户看到"没选"、保存下去记的却是门票。
   修法：六档改一行等宽胶囊（`Row` + 每枚 `layoutWeight(1)`、横向内边距归零），
   实测每枚 146px(46.7vp)×138px(44vp)，轨道 100–1036px，全在 300vp 视口内。
   高度 44vp 仍等于 `minTouchTarget`，宽度 46.7vp 也在 44 之上。
2. **顺带否掉 `SheetSize.FIT_CONTENT`**（这是第二次试，这次是同尺寸对照）：
   FIT_CONTENT 下面板顶落到 y≈1296px，「没键盘」时确实把下方 350vp 的空材质收掉了、观感更好；
   但键盘一弹起，bindSheet 只把面板上移"刚好露出聚焦输入框"那么多（1296→1142px），
   名称/分类/保存整块压在键盘底下——dump 里 `保存` 已不在树上，键盘顶 1643px。
   85% 定高反而把内容顶在 y≈493px，保存停在 476–495vp，键盘顶 526vp，主键留得住。
   **结论：这条面板的高度是"主键可达"换来的，不要为了去掉下方材质空白改成 fit-content。**

**取证**（Pocket 2，sm，1136×2690，密度 3.125）：
- 无键盘：六枚胶囊全在树上（住宿 100–246 … 其他 890–1036，y 1287–1425），
  门票底 `#1A0066CC`（primary tint）＝选中态在屏上；
- 键盘弹起（键盘顶 1643px）：`保存` [518,1489][618,1548] ＝ 476–495vp，仍在键盘之上；
- 端到端：金额 12 + 点「购物」→ 保存 → 已花 ¥12、分类支出「购物 ¥12」、最近记账「购物 ¥12」；
  左滑→垃圾桶→确认删除后回到 已花 ¥0 / 今天还没有记录；
- 截图：`sm-屏11-记一笔六档一行.jpeg`、`sm-屏11-记一笔键盘弹起保存可达.jpeg`（同目录）；
- `assembleHap` BUILD SUCCESSFUL；十把静态尺全部 exit 0。

**边界**：md 档（折叠展开 707vp）仍未实测——模拟器 `127.0.0.1:5555` 的文件/安装服务卡死、
且应用数据被清到首启同意页，本条与续 36 的 md 项一起挂着。六枚等宽胶囊在 md 上会变宽
（通栏 683vp ÷ 6），不会换行，但宽度只由 `layoutWeight` 均分，没有实拍。

### §5ci 续 40：¥0.21 不是 Pro 价——是 Flash 的多轮调用，顺手堵住三个「账单会无声翻倍」的口子

用户看到一次生成花了 ¥0.21，怀疑走了 DeepSeek V4-Pro。查下来**模型一直是 Flash**，
但确实有三个计费口径风险会让账单在「不改代码」的情况下翻倍，已修。

**一、先证伪「用了 Pro」**

- 新旧两把 key 的 `/models` 都只列 `deepseek-flash` 与 `deepseek-v4-pro`，没有别的；
- 旧配置里的 `deepseek-chat` 是 2026-07 退役的别名，实测（新 key + 旧 key 各一次）
  返回体 `"model":"deepseek-flash"`，且回答不含 `reasoning_content` —— 落到的是 **flash 非思考变体**；
- 单次生成的实测 token（杨凌 3 天、1 个必去景点）：输入 1.3k、输出 1.6k–3.7k。
  按 Flash 空闲价（命中 ¥0.02 / 未命中 ¥1.00 / 输出 ¥4.00 每百万 token）一次 **¥0.007–0.016**，
  高峰价翻倍 **¥0.014–0.032**；要花到 ¥0.21 得 **6–13 次调用**。
  Pro 同尺寸一次约 ¥0.02–0.05（输出 ¥13.50/M），单次也凑不出 0.21。
- 结论：0.21 是今天多轮真机测试的累计——其中两轮因响应信封/字段解析失败，各自触发了
  「失败重试一次」，**每次失败都按整份 token 计费**。核对方式：控制台「用量统计」按模型看，
  应当只有 deepseek-flash 的 token，没有 v4-pro 的行。

**二、三个口径风险（都已修）**

1. **别用退役别名**。`LLM_MODEL` 原值 `deepseek-chat`，服务端当前映射到 flash **非思考**；
   映射一旦改成 flash 思考或 pro，账单会无声翻倍/×3.4，端上毫无感知。改为在售 id `deepseek-flash`。
2. **flash 默认开思考**。官方 `/models` 里 `effort.default_level = high`，思维链 token 混在
   `completion_tokens` 里按输出价计费。旧别名恰好是非思考变体，以前"没配也便宜"纯属运气。
   `ApiConfig` 新增 `LLM_THINKING_DISABLED = true`，请求体显式发 `thinking:{type:'disabled'}`。
3. **没有输出上限**。非思考模式服务端默认只给 8K，长行程 JSON 被截断（`finish_reason=length`）
   → TripParser 判失败 → 重试 → 双倍账单且用户看到屏7。新增 `LLM_MAX_TOKENS = 16384`，
   并在 `finish_reason=length` 时写 warn。

**三、顺带抓到一个真会翻倍的失败**

改完第一次真机生成：`days[0].meals: 缺字段`（抵达日整个 meals 键被省略）→ 自动重试才成功，
一次生成付两份钱。提示词补第 13 条「七个键一个都不能省，没有用餐安排也要给 []」，
重跑一次 **attempt=1 直接成功**，Day 1 正常带午/晚餐。

**四、用量日志补全**

`ChatUsage` 增解析 `completion_tokens_details.reasoning_tokens`；日志从
`model/in/cache/out` 扩到 `model/in/cache/out/(思考 N)/结束=finish_reason` ——
以后「钱花在哪一段」直接从 hilog 回答，不用再翻控制台。

**取证**（Pocket 2，sm，2026-10-27 18:50 与 18:52，均为**空闲时段**）：

| 轮次 | 调用 | 输入（命中） | 输出 | 结束 | 结果 |
|---|---|---|---|---|---|
| 改前 | 1 | 1312（1024） | 1717 | stop | 解析失败：days[0].meals 缺字段 |
| 改前 | 2 | 1312（1152） | 1601 | stop | 成功，合计 ≈ ¥0.0138 |
| 改后 | 1 | 1374（256） | 3674 | stop | attempt=1 成功，≈ ¥0.0158（高峰价 ≈ ¥0.032） |

- 改后日志原文：`LLM 用量 model=deepseek-flash in=1374 (cache 命中 256) out=3674 (思考 0) 结束=stop`；
- 截图：`~/Pictures/有径/走查帧-2026-10-27/sm-屏8-真LLM生成含餐次.jpeg`（Day 1 · 11:30 午餐、17:30 晚餐）；
- `assembleHap` BUILD SUCCESSFUL；仓库版 `ApiConfig.API_KEY` 仍是空串，真 key 只在本机
  （skip-worktree），换入的新 key 未进任何提交。

**五、单价口径（官方价页 2026-10-27 现查）**

- Flash：命中 ¥0.02 / 未命中 ¥1.00 / 输出 ¥4.00 每百万 token；Pro：¥0.15 / ¥4.50 / ¥13.50。
- **高峰时段＝北京时间工作日 9:00–12:00、14:00–18:00**，其余时段（含周末、法定节假日全天）半价。
  同一趟行程白天生成比晚上贵一倍——要省钱就避开这两个窗口。

**边界**：思考关闭后规划质量只做了 1 次实拍核对（Day 1 动线、餐次、公交段都在），
样本不足；若后续出现字段缺失/动线不合理，先把 `LLM_THINKING_DISABLED` 置 false 复测再谈提示词。
旧的 `deepseek-chat` 别名在控制台可继续观察，本工程不再依赖它。

### §5ci 续 41：切片1 A+B 落地——屏8 地图落点能点回时间线，日标题带上「今天多挤」

用户批的 A+B 两件事都进了屏8，纯加法，没有改任何既有交互：

**A、列表↔地图联动**

- `TripMapView` 早就有 `request`（`focus:<index>:<seq>`）与 `onStopClick`，屏8 一直没接；
  这次接上：点地图落点 → 镜头飞过去 + 时间线 `scrollToItemInGroup` 滚到对应行 + 该行
  用 `primary_tint` 亮 1.6 秒（行已可见时光滚是没有任何反馈的）。
- 反查不是简单加一：`MapStop.index` 是**滤掉交通节点与坏坐标之后**的序号，
  直接当 `activities` 下标会错行。新增 `MapStops.activityIndex(day, index)`，与 `fromDay`
  共用新抽出的 `eligible()`，两处不会再漂（单测钉死「第 2 个落点 → activities[3]」这种含隔离项的样本）。
- `scroller` 必须是 `ListScroller`——`scrollToItemInGroup` 只在子类上，基类 `Scroller`
  没有这个方法（第一次编译就撞在这，报 `10505001`）。
- 组号口径：List 里 `ListItem` 也按组计数，所以地图卡在场时 `ListItemGroup` 是第 **1** 组；
  组内下标 = 活动下标 × 2（每站先出站点行、再出通勤腿）。
- 地图页（dock「地图」）补齐另一半：站点条从 `Scroll + Row` 换成官方 `List`，
  点气泡时 `scrollToIndex(pos, true, CENTER)` 把对应站点卡带回视野。定宽卡用
  `alignListItem(Center)`，不用 `lanes`（分栏会把 132 宽的卡压成半宽）。

**B、当日负载三态条**

- 新增 `utils/DayLoad.ets`（纯逻辑，不引 @kit）：**Σ停留 + Σ通勤** 对 **600 分钟**窗口。
  不按「最后结束 − 最早开始」算——「上午两小时 + 晚上两小时」的跨度是 11h，
  但真正被占用的只有 4h，算跨度会天天报「今日 11h」。
  交通类节点自身的时段计入通勤、不进停留；`transport.duration` 一律再加。
- 三态：`>100%` 危险、`80–100%` 提醒、其余正常。读数 `今日 8.4h · 建议 ≤10h` /
  `今日 10.1h · 超建议 0.1h`，微条 3vp（`LinearStyleOptions.strokeWidth`），
  常态走品牌蓝、只有高负载才转语义色。
- 超载态多一枚 `去减一站`（`TEXTUAL` 胶囊，44vp 高），直达屏9 当日编辑；
  没超的时候不出现，避免每屏都挂一个红字入口。
- 条挂在**吸顶日标题**里而不是 Day 分段栏：`ImmersiveSegmentBar` 是官方 `SegmentButton`，
  条目只有纯文本、没有逐条自定义 builder 的口子；为了塞 3vp 微条去自绘一条 tab 栏，
  等于用自绘换掉官方组件（本项目禁令），不换。

**取证（Pocket 2 · sm · 2026-10-30 10:22–10:24，真机 1136×2690 px，密度 3.125）**

| # | 动作 | 可量证据（uitest dumpLayout 的 bounds） | 结论 |
|---|---|---|---|
| 1 | 进屏8 Day 1 | 负载条 `[50,1428][692,1438]`（高 10px=3.2vp）+ 读数 `[717,1411][1086,1455]` | warn 态出现，读数「今日 8.4h · 建议 ≤10h」 |
| 2 | 点地图气泡（坐标 603,590） | 列表整体上移（12:00 行 2068→638）；被点中的行 `[50,1178][1086,1530]` 背景 `#1A0066CC`；无 sheet 弹出 | A 生效：滚到行 + 高亮，且没有误开详情面板 |
| 3 | 切 Day 2 | `[446,758][861,802]` 读数「今日 10.1h · 超建议 0.1h」+ `去减一站` `[886,711][1086,849]`（高 138px=44vp） | 超载态与出口都出现 |
| 4 | 点「去减一站」 | 顶层变「编辑行程 / Day 2 · 10月28日 · 8 个节点」 | 出口直达屏9，粘在吸顶头里的 Button 可点（不是 ListItem 里那类点不动的胶囊） |
| 5 | 地图页点第 3 张站点卡 | 卡 1 `[75,2077][131,2133]`→`[1,2077][17,2133]`，卡 3 `[950,…]`→`[399,…]` | 站点条被 `scrollToIndex` 带到居中 |

- 截图：`~/Pictures/有径/走查帧-2026-10-27/sm-屏8-切片1-当日负载条-warn.jpeg`
  与 `sm-屏8-切片1-超载态与去减一站.jpeg`；
- 单测：`DayLoadCalc` 7 例 + `MapStops` 8 例真机全绿（`aa test -s class`）；
- 静态尺 12 把（`tools/audit_*.py` 无参档）全部 exit 0。

**边界**

- `audit_contrast`（第 4 把尺）没能在屏8 跑成：取证到一半手机被真人切到同族 App「有据」，
  按「脚本点击不撞真人」的口径立即停手。三项新字色改用 `color.json` 精算（比 jpeg 像素
  更准，见记忆 `hdc-snapshot-jpeg-only-contrast-noise`）：muted 5.46 / warning 4.86 /
  danger 5.44（浅色），深色 6.46 / 9.11 / 5.50，都过 4.5。
- 第 2 行「点的是第几个落点」：画面里 4 枚图钉挤在同一片校区、后画的盖住先画的，
  注入点击命中的是**最上层那枚**，所以只能证明「点落点→滚到某一行并高亮」这条链成立，
  序号到行的映射由单测兜底；室外分散点位下的点选留到下次走查补。
- md（折叠屏展开）档没量；屏9 的既有 md 欠账不变。
- 本轮零 LLM 调用（没碰生成链）。

### §5ci 续 42：围栏的两道闸门合流成一个——官方回信说「已在 AGC 提交、审核中」

Location Kit 运营团队 2026-10-30 回复（原文见 `Docs/围栏与后台唤醒开通清单.md` §一）：
**申请已由 AGC 受理、目前审核中，通过后会收到系统通知、服务随即可用；邮件渠道不单独开通。**
这条把此前并列记录的两道闸门（邮件开通 / AGC 围栏后台唤醒）并成同一个**审核闸门**，
也解释了 10-27 探针「注册成功、事件零回调」不是我们配置错，而是服务未生效。

清单文档相应改写：

| 原内容 | 现在 |
|---|---|
| 闸门 1 状态「10-28 已发、10-30 无回复」+ 追信规则表（11-02 追信 / 11-05 停等） | 删除追信计划；改为「以审核结果为准」，不再自己编截止日 |
| §一-b 追信稿 | 整段删除，只留已发送的原邮件稿（补材料时可复用） |
| 闸门 2 单列 AGC 申请 | 与闸门 1 合流为 §一；§二 降级为「AGC 材料留档，备驳回后补齐重提」 |
| 复测判据 B「同时验证闸门 2」 | 改为「同时验证围栏后台唤醒是否随同一审核一并生效」 |

**排期结论**：审核结果未出期间，切片 2 只按 **T1**（前台 `locationChange` 到达检测 + 勋章落库）
排期；T2 系统围栏不进本期范围，等系统通知后再按复测清单 A/B/C 判定。
本轮只改文档与记忆，未动代码、未构建、零 LLM 调用。

### §5ci 续 43：切片2 T1 落地——屏15 前台到站检测 + 打卡位置凭证（无设备轮）

用户批准 T1 设计，同时明确「暂时不能用模拟器或者是真机，另一个任务正在模拟器调试」。
所以这一轮的验收口径是**离线可证的才算**：纯逻辑用 tsc + 断言、迁移用源码里的原句喂 sqlite、
构建产物用 ABC 特征串反证；凡是要屏幕/定位/权限的，一律写进下面的「未验」清单，不冒充通过。

**做了什么（五处，纯加法）**

| 位置 | 内容 | 要点 |
|---|---|---|
| `module.json5` + `string.json` | `ohos.permission.LOCATION` / `APPROXIMATELY_LOCATION`，`when: inuse` + 用途说明串 | 只要前台；与围栏无关，不受 AGC 审核阻塞 |
| `utils/Geo.ets` | `ARRIVAL_RADIUS_M = 300`、`distanceM`、`arrived`、`distanceText` | 半径取 300m：10-27 探针室内 acc≈237m，100/200m 只剩噪声；**精度只显示、不参与判定**，否则一次室内漂移就会被判成「已到站」 |
| `data/DatabaseHelper.ets` | `DB_VERSION` 7→8，checkin 加 6 列 `uuid/latitude/longitude/accuracy_m/distance_m/source` | 存量行 `source` 默认 `'manual'`、坐标 0——回填不了的不假造，勋章按这个字段区分 |
| `data/CheckinDao.ets` | `set(..., evidence: CheckinEvidence \| null)`，写 `uuid`（`util.generateRandomUUID`）与 `source` | 有凭证→`arrival`，无凭证→`manual`；`null` 不是异常路径，是「手动打卡」的正常口径 |
| `common/location/ArrivalWatcher.ets`（新增） | 只订阅「仅使用期间」的 `locationChange`，10s / 20m 一档 | `canIUse` 门禁 + `isLocationEnabled` + 权限申请；**退订先摘回调再 `off()`**（Map Kit 那次拆除期反调的教训） |
| `pages/OnTripPage.ets` | hero 多一行「已到站 · 距站点 12m」/「距此站 320m」；到站打卡才带坐标 | 只在「今天 + 当前站有坐标 + 拿到前台定位」时订阅；离开页面/切到非今天/换站无坐标立即退订并清状态 |

两条并发细节写进代码而不是文档：权限弹窗还在时页面退订、或又发起一次 `start()`，
旧的那次靠 `ArrivalWatcher` 内的取消令牌作废（不能把回调打进已销毁的页面）；
页面侧用 `watcherStarting` 挡重复 `start()`。

**离线证据**

| 闸门 | 命令口径 | 结果 |
|---|---|---|
| Geo 纯逻辑 | 拷成 `.ts` + DevEco 自带 tsc `--strict` | 0 诊断 |
| Geo 断言 | 21 条（含屏5 老的 `distanceKm/meanDistanceKm/argminMean` 三条防退化） | `ALL PASS 21/21` |
| 半径边界 | 300 含端点、300.001 不含、0 算到站、-1/NaN/∞ 不算 | 全过 |
| 文案边界 | `999.2m`→`999m`、`999.6`→`1km`（先取整再分档）、`-1`/`NaN`→空串 | 全过 |
| 真实地理 | 故宫→天安门 ≈1.0km，判「未到站」；同点判「已到站」 | 全过 |
| v8 迁移 | 从源码正则抽出**原句**喂 sqlite：v4→v8、v7→v8 | `PASS 2/2`；两路都得到 10 列，存量行默认 `('',0,0,0,0,'manual')` |
| 覆盖写 | 同 `(trip_id, activity_id)` 二次打卡 | `ON_CONFLICT_REPLACE` 后仍 1 行、`checked_at` 更新 |
| 主 HAP | `assembleHap` | BUILD SUCCESSFUL |
| 测试 HAP | 同（ohosTest） | BUILD SUCCESSFUL |
| 产物新鲜度 | `strings modules.abc`：`syncArrivalWatcher` 2 / `evidenceNow` 2 / `refreshArrival` 2 / `ARRIVAL_RADIUS_M` 1；三条新用例名各 1 | hvigor 报 UP-TO-DATE，靠特征串反证编进去了（[[hvigor-up-to-date-stale-artifact]]） |
| 静态尺 12 把 | colors/type/geometry/material/fontfamily/tnum/elevation/a11y_name/button_width/label_fit/layout_patterns/scroll_actions | 全部 exit 0 |
| 第 13 把（对比度） | `audit_contrast.py` 需 dump+jpeg | 无设备 → exit 2（用法提示），**这轮没跑** |
| 到站行配色 | color.json 精算，底是 hero 的 `surface_elevated` | 浅色 success 5.42 / muted 5.10；深色 8.25 / 5.74，均过 AA |

**未验（等设备空出来第一件）**

- hypium 全量没跑。Geo 新增 3 条，但**总数不推一个假数字**：最后一次设备级记录是 81，
  而源码现在有 136 处 `it()`、其中还有按循环生成用例名的（`seed_counts_${c}`），
  两者不同源（81 来自更早的源码状态），要对齐得等设备。
- 权限弹窗外观、「本次允许 / 拒绝」两条路径、拒绝后静默降级成手动打卡。
- 真实的 `locationChange` 回调是否按 10s/20m 到达；hero 那行在真机上的渲染与换站刷新。
- 打卡后 `checkin` 表里 6 个新列的实际取值（含 `distance_m` 是否落在半径内）。
- v7→v8 在**真实 RdbStore** 上的迁移（sqlite 只是同句复现，不是同一实现）。
- 「权限弹窗还开着时离开页面」只有代码级的令牌兜底，没有设备级证据。

**两条分寸**

1. **`utils/Geo.ets` 是先误覆盖、再从 git 恢复后做加法**：我第一次写这个文件时把屏5 已有的
   `distanceKm/meanDistanceKm/argminMean` 整份盖掉，`git diff` 当场看出来，`git checkout --`
   还原原文后只追加新方法。所以这轮的断言里特意留了三条老接口的用例，防的正是这种退化。
2. **顺手发现一处既有隐患（本轮不改）**：`(oldVersion === 0)` 新建库路径下，
   `trip.user_id` / `spot.confidence` / `meal.time` 这三列建表语句里已经有了，后面的
   `ALTER TABLE ... ADD COLUMN` 必然重复（sqlite 复现报 `duplicate column name`）。
   代码里 `store.executeSql` **没有 await**，拒绝不会进 `catch`——真机装过多次新库没出过问题，
   但那是观察，不是这轮实测，**机制没验就不写结论**。T1 加的 6 条 ALTER 不受这条影响
   （`CREATE TABLE checkin` 不含新列）。无设备验证前不动它，先记在这里。

本轮零 LLM 调用（没碰生成链）。

### §5ci 续 44：T1 真机取证（Pocket 2）——单日屏8 空白是官方分段栏首帧改内部状态，顺手证完权限三态、到站行、凭证落库与离场退订

设备：Pocket 2（`192.168.31.38:46077`，1136×2690 设备像素，密度 3.125）。所有注入点击前重新 dump 断言前台，跟丢即重来。

**本轮修的缺陷（真机抓到，非猜测）**

用真机生成一条 1 天行程（杨凌 2026-10-30，8 站）后，屏8 只剩标题栏「杨凌 · 1天0晚」，正文 **0 个文本节点**；同一构建下 7 天行程正常。拉 DB 逐表核对：trip_day 1 天、activity 8 条齐全，先排除数据问题。hilog 同期抓到：

```
FIX THIS APPLICATION ERROR: @Component 'SegmentButton':
State variable 'buttonBorderRadius' has changed during render!
```

（tag `E C03947 …/AceStateMgmt`、包名 `com.youjing.app`；原文按本轮抓取记录引用，该行已随后续日志滚出环形缓冲。）

即官方 `SegmentButton` 只有 1 个 item 时会在首帧改内部 `buttonBorderRadius`，触发「render 期间改状态」把整棵内容子树中断。修法两层：

1. `ItineraryPage`：`days.length > 1` 才挂分段栏——一天也没有可切换对象，日标题本来就带 Day 1。
2. `ImmersiveSegmentBar`：`items.length > 1` 才渲染官方控件，防其它调用方踩同一坑（屏11 固定「预算/实际」两项不受影响）。

复测：1 天屏8 恢复（地图卡 + 时间线 + 负载条「今日 9.7h · 建议 ≤10h」）；7 天行程分段栏照常渲染，无回归。

**权限三态（真机）**

用 `atm perm -c/-r/-g`（仅调试包可改）制造状态，再走真实弹框（没走设置页导航）：

| 状态 | 操作 | 观察 |
|---|---|---|
| 未决定 | 进屏15（当前站 19:00 博览园，有坐标） | 系统弹「允许“有径”访问你的位置？」，理由文案完整：「用于判断你是否已到达当前行程站点，到站时可打卡并记录位置凭证；位置只存本机」；精确位置开关默认开 |
| 仅使用期间允许 | 点「仅使用期间允许」 | watcher 订阅成功，hero 出现「距此站 3.7km」（muted 灰），状态栏出现定位指示 |
| 不允许 | 重置授权态后在弹框点「不允许」 | 无崩溃；到站行整行不渲染；「完成打卡」仍在；hilog `YouJing.Location.Arrival: 定位权限未授予，到站检测降级为手动打卡`；`atm dump` 态为 grantStatus -1 / grantFlag 2 |
| 拒绝后再进 | 返回首页再进屏15 | 系统**不再弹框**，只多一条同句静默日志——「拒绝后不再二次劝说」在弹框层面成立；代码仍会调一次 `requestPermissionsFromUser`，系统静默返回拒绝 |
| 恢复 | 重置 → 弹框 →「仅使用期间允许」 | 到站行回来（1.5km），权限态 0/2；设备最终留在「仅使用期间允许」 |

**到站行与换站**

- 当前站换成 20:00 渭河生态公园（34.247,108.083）后，同一会话内到站行从「3.7km」刷新为「1.5km」——换站重订阅正常。
- 当前站是餐次（17:30 晚餐，lat/lng=0）时：到站行、进度条都不渲染（`Geo.usable` false、`totalMin=0`），watcher 退订，无崩溃。
- dump 里 y≈720 的 `100.000000` 是 `Progress` 的值被 dumpLayout 暴露成 text，不是可见文案（截图该处只有蓝条），勿当缺陷。

**打卡凭证落库（v8）**

手动打卡两笔（一笔在当前站无坐标的酒店、一笔在 3.7km 外的博览园）都落成：

| uuid | latitude/longitude | distance_m | source |
|---|---|---|---|
| `6ee27db7-…`（a8）、`3af7595c-…`（yl-002） | 0 / 0 | 0 | manual |

「没到站不给坐标」这条兑现。**到站分支（source=arrival、坐标非 0、distance ≤300）本机不可达**：手机离两个候选站 3.7km / 1.5km，且没有 mock 定位手段；300m 边界由 Geo 断言（300 含端点、300.001 不含）覆盖。这是边界，不外推成「到站打卡已真机验证」。

v7→v8：本机库是 T1 首装时从有数据的旧库迁上来的（checkin 10 列 + 既有 trips 都在），本轮装的是 v8→v8；新建库 v0→v8 仍只有 sqlite 同句复现，没有设备证据。续 43 记的 v0 路径 duplicate-ALTER 隐患继续挂着。

**生命周期**

- 离开屏15（Back→首页）：状态栏定位指示消失；再进来重新订阅、到站行重新出现；无崩溃。
- 编辑行程删掉 19:00 站 → 回屏15（`onShown` 触发 `reload`）→ 当前站变餐次，到站行消失。
- 非今天：深链 `--ps route OnTrip --ps param yangling-2026-12-27-7d` 进屏15，不申请权限、无到站行、无崩溃；但标题仍写「进行中 · Day 1」。产品路径不可达（首页对非旅行中行程直接进屏8），记为深链边界，未改文案。

**顺手发现（本轮不改）**

1. 打卡记录按 `(trip_id, activity_id)`，而补选复用了景点 id：删掉 19:00 的 `yl-002` 后在 17:15 补回同一景点，17:15 行直接显示「已打卡」——继承 21:49 的旧记录。要么补选换 id，要么删站时清 checkin，归入切片2 收尾。
2. 编辑页标题栏常驻 ⊕「补选景点」（`openAdd`），删除后那条「补一个」只是会话内捷径。自查纠错：一度误判为「保存后无法添加」，读源码后撤回。

**两条边界与分寸**

- 本轮没有新的 LLM 调用（夹具生成的那一次 flash ≈¥0.01 已在上一轮报过）。
- 真机脚本两次误触（首页 pad 点落到「开始规划新行程」、屏8 编辑图标偏 12px）都是靠「点完立刻 dump」发现的，已当场纠正，未留在结论里。

### §5ci 续 45：切片2 收尾——打卡收章弹窗 + 「我的勋章」墙（真机取证，含一次 jscrash 修复）

**做了什么**

勋章不建新表：全部从 v8 的打卡证据派生（`uuid/坐标/source` 已在 T1 落库）。

| 件 | 文件 | 要点 |
|---|---|---|
| 数据 | `data/BadgeDao.ets` | `checkin JOIN activity ON a.id = c.trip_id||':'||c.activity_id JOIN trip`，按 `user_id` 分区；餐次没有 activity 行，联表天然排除，不为餐次编章 |
| 纯逻辑 | `utils/BadgeBoard.ets` | 同名同城合并成一枚（trim 后去重）；`visits` 计次；任一次 `arrival` 即升级并保留最小 `distanceM`；首收时间/首行程取最早；城市组按最新章排序，组内按时间倒序；`badgeRoute()` 用行程区间决定回屏15 还是屏9 |
| 弹窗 | `components/BadgeEarnedDialog.ets` | 官方 `@CustomDialog`，只在「这一笔就是这枚章的首次收下」时由屏15 打开；文案如实写「到站打卡/手动打卡」 |
| 勋章墙 | `pages/BadgePage.ets` | 官方 `List + ListItemGroup`（吸顶城市头）、总览卡（medal+已收集 N 枚+城市数/最近日期）、行用官方 `Button(stateEffect)` 做壳；空态、加载态各一套 |
| 入口 | `pages/TripsPage.ets` / `AppRouter.ets` | 屏12 标题栏在 ⊕ 与头像之间加 medal 钮（三项全露出，退出登录未被折进 more）；路由名 `Badges`，深链 `--ps route Badges` 可达 |
| 用例 | `ohosTest/.../BadgeBoard.test.ets` | 10 例：空、同名同城合并、异城不合并、trim、空名丢弃、分组排序、findBadge 限城、来源/元信息文案、按行程区间选路由、本地日文本 |

**真机取证（Pocket 2，sm 363.5vp）**

| 路径 | 结果 |
|---|---|
| 深链 `--ps route Badges` | 直接落勋章墙：总览「已收集 3 枚 / 1 个城市 · 最近 10月30日」，标题副行「共 3 枚」，城市头「杨凌 3 枚」，三行按时间倒序 |
| 屏12 标题栏 medal 钮 | 截图确认三钮顺序 = ⊕ / 勋章 / 头像；点勋章 → 同一面墙 |
| 屏15 首次收章 | 补选「西北农林科技大学校园」→ 完成打卡 → 弹窗「已收下这枚勋章 / 西北农林科技大学校园 / 杨凌 · 手动打卡 / 行囊里已有 3 枚」 |
| 弹窗「查看勋章」 | 关弹窗 → push `Badges` → 墙里新章置顶，总数从 2 变 3 |
| 弹窗「继续行程」 | 弹窗消失，停留屏15，打卡态保持 |
| 勋章行 → 旅行中行程 | 点「西北农林科技大学校园」（今天在区间内）→ 屏15，当前节点正是该站 |
| 勋章行 → 已结束行程 | 点「杨凌渭河生态公园」（10月27–29）→ 屏9 行程详情（Day 1 · 10月27日），不是屏15 |

**中途抓到并修掉的 jscrash（本轮最重要的一条）**

第一次点「查看勋章」App 直接退回桌面。hilog 给出精确栈：

```
TypeError: Cannot read property close of undefined
    at onAction entry (entry/src/main/ets/components/BadgeEarnedDialog.ets:63:29)
  → com.youjing.app is about to exit due to RuntimeError
```

根因：`@CustomDialog` struct 里声明的 `controller: CustomDialogController` **不会自动注入**，
弹窗自己调 `this.controller.close()` 就是 undefined。项目里的 `PrivacyConsentDialog` 从不自己 close
（关闭权在宿主），本轮弹窗没有沿用这条口径。
修复：弹窗只回调 `onViewWall/onDismiss`；宿主新增 `closeBadgeDialog()`（先置空再 close，天然幂等），
`aboutToDisappear` 与两个回调统一走它。重装后两条出口都复测通过；修复后 hypium 全量 149/149。

**静态尺与构建**

- 构建：entry 与 entry@ohosTest 双 HAP BUILD SUCCESSFUL；新增文件无 ArkTS 报错（仅 `Function may throw exceptions` 警告级）。
- 十把尺全 0 偏差：colors / type / geometry / material / fontfamily / tnum / elevation / button_width / scroll_actions / label_fit。
  tnum 已覆盖新页的 `已收集 N 枚`、`N 个城市 · 最近…`、`N 枚` 与行内 `badgeMeta()` 调用点。
- hypium：149 例全绿（原 139 + BadgeBoard 10）。

**边界（没验到就不写成功）**

1. **空态未真机验**：本机账号已有 3 枚章，没有第二个空账号可用；`groups.length===0` 分支只经过代码阅读与纯逻辑空数组用例，UI 分支无设备证据。
2. **`source='arrival'` 的章未真机验**：手机离站点 1.5–1.8km，造不出到站打卡；来源文案的 arrival 分支只有纯逻辑用例。
3. **重复到访不弹窗未真机验**：验证路径要求「另一条行程里已收过的景点成为今天的当前站」，本机当前行程的当前站只有校园；`firstCheckinId !== tripId:key` 这条守卫只有代码证据。
4. **md/宽屏两列未量**：本机 sm；`listLanesForBreakpoint` 的 2/3 列在 Pocket 2 上不可达（用户另一台折叠屏未展开测）。
5. **深色档未拍**：沿用 token，未做单独夜间复拍。

**数据副作用（如实记）**

- 为造「首次收章」在本机测试行程补选了一站「西北农林科技大学校园」，并对它做了一次「取消打卡→再打卡」的往返；最终状态 = 已打卡，墙里 3 枚，没有删除任何既有行程或打卡。
- 本轮零 LLM 调用。

### §5ci 续 46：切片3 行中智能落地——屏15 天气行 + 建议条（跳过/顺延/忽略）+ 隐私 v2（真机取证）

**做了什么**

行中段第一条闭环：天气只读、建议只提议、改行程必须用户点。三层分工：

| 件 | 文件 | 要点 |
|---|---|---|
| 契约 | `model/Weather.ets` | `WeatherHour/WeatherDay/WeatherBrief`，小时粒度到当日分钟（`startMin`） |
| 取数/解析 | `common/weather/WeatherClient.ets` / `WeatherParser.ets` | Open-Meteo 免 Key；坐标在 `WeatherStore.targetOf` 里 `toFixed(1)`（约 11km）且只取当日首站；WMO code → 中文标签，解析不过即 null |
| 缓存 | `data/WeatherStore.ets` | 内存 + preferences 双层，TTL 30 分钟；无坐标/请求失败/解析失败都静默返回 null（页面不出天气行，不阻塞） |
| 简报 | `data/WeatherAdvisor.ets` | `今日 19°/4° 晴间多云 · 降水 0%`；`rainIn()` 只在目标时段取小时最大值，阈值 `RAIN_MIN_PROB=60` |
| 信号 | `data/TripSignals.ets` | 优先级 偏离 > 落后 > 有雨；偏离 = 有定位 + 距当前站 >1000m + 开始后 ≥10 分钟 + 未打卡 + 可跳过；落后 = 最后打卡之后首个未打卡站晚 ≥30 分钟（无可顺延站退化为跳过）；有雨 = 前方首个室外可跳过站在其时段内降水 ≥60% |
| 顺延 | `data/SkipPlanner.ets`（新增 `isShiftTarget/shiftRemaining`） | 只移动「未开始、非交通/住宿、未预约、非跳过占位」；每站先 +delta 再避开锚点（预约/交通/住宿/有时刻餐次/当前站剩余时段），次序只前进；越过 23:59 的项保持原时间并追加「待调整」；`shiftValid` 复核通过才落盘；`ReplanOutcome.changed?` 区分「没目标」与「真改了」 |
| 屏15 | `pages/OnTripPage.ets` | hero 内天气行（到站行之后）；建议条在 hero 之上，`warning` 标题 + SECONDARY 动作 + TEXT「忽略」；`performShift` 与 `performSkip` 共用快照/撤销/落库；`performSkip` 从「只能跳下一站」放宽为「任意可跳站点」，目标按 key 反查，找不到就提示重试、绝不猜站 |
| 忽略 | 同上 | 同类信号静默 30 分钟（`SIGNAL_MUTE_MIN`），换类立即重判；静默态随页面实例，切天清零 |
| 隐私 | `LegalDocs.ets` / `ConsentStore.ets` | 新增「今日天气」条（只发 0.1° 坐标、不发实时定位/账号/行程内容、结果本地缓存 30 分钟）；`CONSENT_VERSION` v1 → v2，老用户重问一次 |
| 用例 | `ohosTest/.../WeatherSignals.test.ets` | 9 例：WMO 标签与简报、解析契约、偏离优先于落后、阈值与打卡门槛、无顺延目标退化跳过、有雨阈值与室外判定、顺延基本/锚点/溢出、无目标与跳过占位 |
| 离线 | `tools/verify_weather_logic.sh` + `tools/weather_signals_check.ts` | 102 条断言；bundled tsc `--strict` 过检后由 node 执行 |
| 文档 | `Docs/行中智能方案.md` | 目标/边界、数据源与隐私、契约、屏15 呈现、任务拆解、验收、风险 |

**中途抓到并修掉的两处同意闸门缺陷（不修就发不出去）**

隐私正文改版会让老用户重新过闸，实测时一次撞出两条：

1. **点「同意并继续」弹窗不关**：hilog 已打 `已记录明示同意 version=v2`，但对话框仍在，用户被卡死。根因：`Index.onAgree` 只写了同意态，没有关闭控制器。修复：`this.consentDialog.close()`（`agree()` 先同步置位，关窗不等落盘）。
2. **Back 能绕过闸门**：`uitest uiInput keyEvent Back` 后弹窗消失、`ConsentStore.isAgreed()` 仍为 false，应用可直接使用——「不同意并退出」那条出口被绕过。修复：`onWillDismiss` 里只有 `isAgreed()` 才 `action.dismiss()`，其余一律不关。

两条都做了 Before/After 真机复测（Before：同意不关窗 / Back 关窗；After：Back 不关窗、同意关窗并落 v2）。修复验证用的是临时 `v2-test` 版本号，测完已回退 `v2` 并重建装机；`modules.abc` 内 `v2-test` 命中 0 次、`onWillDismiss` 命中 2 次。

**真机取证（Pocket 2，sm 363.5vp，2026-10-30 23:2x–23:5x）**

| 路径 | 结果 |
|---|---|
| 隐私政策第 3 条 | 面板内滚动可见「3. 今日天气」，正文与 `LegalDocs` 完全一致 |
| 老用户重问 | v1 同意态下装 v2 → 闸门重新出现；同意后再装同一 v2 → 不再重问（`install -r` 保留 preferences） |
| 天气行 | `今日 19°/4° 晴间多云 · 降水 0%`，真 Open-Meteo 数据 |
| 建议条渲染 | `比计划晚 882 分钟` / 「西北农林科技大学博览园」还没打卡，今天没有可顺延的站 / `跳过这一站` + `忽略`；深色档截图无截断 |
| 跳过动作 | 点 `跳过这一站` → `已跳过「西北农林科技大学博览园」，离线重排` + `撤销`；信号重算为 `比计划晚 688 分钟`，目标换成「午餐品尝杨凌蘸水面」 |
| 撤销 | 点 `撤销` → `已撤销重排`；条回到 `比计划晚 884 分钟`，博览园站恢复 |
| 忽略 | 点 `忽略` → 条立即消失 |
| 30 分钟静默 | 忽略后点 `完成打卡`（触发 reload → 天气缓存 → 重判同一 BEHIND），条没有回来；再取消打卡仍不回来 → 静默在同一页面实例内生效。退出重进形成新实例 → 条以 `比计划晚 897 分钟` 回来（静默不跨实例） |
| 非今天不亮 | 跨过 00:00 后再点同一行程 → 进入屏9 详情（已结束），不出现天气行/建议条 |

**构建 / 尺子 / hypium / 离线**

- 主 HAP：`entry-default-signed.hap` BUILD SUCCESSFUL（23:12，最终 v2 源码；abc 内 `比计划晚`/`open-meteo` 可检索、`v2-test` 0 次）。
- ohosTest HAP：23:36 重建 BUILD SUCCESSFUL（20 executed / 15 up-to-date）。
- 静态十把尺全 0 偏差：colors / type / geometry / material / fontfamily / tnum / elevation / button_width / scroll_actions / label_fit；`audit_contrast` 是运行期尺（要 dump+png 两个参数），不在这轮静检里。
- hypium 真机全量：`Tests run: 158, Failure: 0, Error: 0, Pass: 158, Ignore: 0`（基线 149 + WeatherSignals 9），`TestFinished-ResultCode: 0`。
- 离线：`WEATHER_SIGNALS_OK cases=102` + `WEATHER_LOGIC_OK`（bundled tsc `--strict`）。

**成本（本轮唯一一次真实 LLM 调用）**

- 为造「今天全未打卡」的行程触发「落后」信号，新建「杨凌 · 2026-10-30 · 1 天 · 7 景点/3 通勤」。
- hilog：`LLM 用量 model=deepseek-flash in=1374 (cache 命中 1152) out=1005 (思考 0) 结束=stop`，只调 1 次、无重试。
- 23:25 属非高峰（半价）：命中 1152×¥0.02/M + 未命中 222×¥1.00/M + 输出 1005×¥4.00/M = 高峰价 ¥0.0043，实际约 **¥0.0021**。

**边界（没验到就不写成功）**

1. **「顺延」按钮没有真机画面证据**：取证到 23:57 时，`isShiftTarget` 要求 `start ≥ now`，今日已无未开始站点 → 信号按设计退化为「跳过这一站」。这是时刻条件的硬边界，不是实现缺失：顺延的锚点/溢出/复核由 102 条离线断言与 3 个 hypium 用例（`shift_targets_and_basic` / `shift_respects_current_stop_and_overflow` / `shift_no_targets_and_markers`）覆盖，但「按钮文字 + 时刻整体后移」的端到端画面本轮没拍到。
2. **「有雨」未真机触发**：当日降水 0%，60% 阈值不达；只有离线 + hypium 证据。
3. **「偏离」未真机触发**：当前节点是晚餐（无坐标）→ ArrivalWatcher 不启动；且需要 >1km 实际位移 + 前台定位权限；只有离线 + hypium 证据。
4. **md/宽屏未量**：本机 sm 363.5vp；建议条两枚按钮（150+72vp）未在 md 复拍。
5. **静默不跨实例**：退出重进或换站新建页面会清零 `mutedKind`——本轮实测确认，按现状记录（没有做成跨页面持久化静默）。
6. 顺带核实：屏9 / 屏12 的 dump 里有 `99.166667` / `100.000000` 文本节点，截图对应位置不可见（Progress 内部值节点），不按上屏缺陷处理。

**数据副作用（如实记）**

- 新增并保留一条测试行程「杨凌 2026-10-30 · 7 景点/3 通勤」（本轮唯一 LLM 生成）；没有删除或改动用户既有行程。
- 为验证动作做了「跳过 → 撤销」「打卡晚餐 → 取消打卡」两个往返，最终站表与打卡记录均回到原状。
- 本机同意态 = v2（隐私正文改版后的最新版）。

### §5ci 续 47：切片4 行前便捷落地——屏2「一句话成行程」+ 本地意图解析 + 自动选点/住宿区（真机取证）

**做了什么**

一句话只做「表单预填」，不绕过既有 5 步流程，也不联网：

| 件 | 文件 | 要点 |
|---|---|---|
| 城市单点 | `common/constants/Cities.ets` | `CityDef { name, spotsFile, areasFile }` + 5 座种子城市 + 别名表 + 约 80 个未收录目的地；`DataSeeder` 改走同一份清单，避免两处城市表漂移 |
| 意图解析 | `utils/TripIntentParser.ets` | 纯函数、零 `@kit`：城市（含别名）、日期（今天/明天/后天/大后天/下周X/本周X/M月D日，跨年推断）、天数（X天X晚/X晚/X日游，跳过「第 X 天」这种序号）、人数（阿拉伯/中文数字、一家三口/两口子）、预算（元/千/万/中文数字，人均与总额两种口径，人均夹到 3,000–12,000）、风格/住宿档/交通/节奏、兴趣标签（亲子/小众/历史/必去 → family/niche/classic/must_see）；对不上的字段由页面保留原值并在预览里逐条说明 |
| 自动选点 | `utils/PlanAutoPick.ets` | `pickSpots`：每天上限跟节奏（轻松 3 / 标准 4 / 紧凑 6），带标签的景点优先、其余按热度补足，前 `min(天数, N)` 个 MUST、其余 WANT；`pickArea`：先按住宿档过滤（无匹配退回全部），再用 `Geo` 取到已选景点平均距离最近的区；`nearestArea` 同时给屏5「帮我选」复用，选住宿区只有一套规则 |
| 屏2 卡片 | `pages/TripInputPage.ets` | 标题「一句话成行程」+ 官方 TextInput + SECONDARY「识别」+ TEXT「填入示例」；识别前 `clearFocus()` 收键盘；错误态在卡片内用 danger 文本，现有错误：空输入、未收录城市（列出支持城市，绝不静默改目的地）、没认出目的地、城市数据不完整 |
| 识别预览 | 同上 | `bindSheet` 半模态：识别结果 6 行（目的地/日期/人数/预算/偏好/预选）+ 默认值说明；「直接生成行程」把字段写进 `PlanDraft` 后 push `Generating`（住宿区为空时禁用）；「去调整」关面板、表单已填好。原句只存在页面 `@State`，不落盘、不发送、不进 prompt |
| 屏5 复用 | `pages/StayPickPage.ets` | 「帮我选」改调 `PlanAutoPick.nearestArea`，删除本页那份平均距离实现 |
| 用例 | `ohosTest/.../TripIntent.test.ets` + `List.test.ets` | 7 例：整句解析、预算与偏好、未收录城市、日期/天数边界、人均夹取、节奏与标签选点、按档位+距离选区 |
| 离线 | `tools/verify_trip_intent.sh` + `tools/trip_intent_check.ts` | 69 条断言；bundled tsc `--strict` 过检后由 node 执行 |
| 调研 | `Docs/任意目的地数据管线.md` | Map Kit site API（SDK d.ts 核对）/ OSM+Photon / 腾讯·高德 / LLM 生成四条路线的取舍；Site→Spot、区县→Area 字段映射；开放问题与分阶段计划。本轮不实现任意城市 |

**中途抓到并修掉的四处缺陷**

1. **构建失败**：`DataSeeder` 里还留着 `c.city`，`CityDef` 只有 `name` → ArkTS 10505001（DataSeeder.ets:97/106/112）。改 `c.name` 后重建通过。
2. **解析器漏掉真实天数**：`第3天去故宫，去北京玩五天` 只匹配到「第 3 天」就把「五天」丢了（实际 0 天）。改为遍历所有匹配、跳过前面是「第」的序号，命中后返回 → 离线断言复测 `PASS 69/69`。
3. **预览不说标签**：句子里的「历史」只影响选点顺序，预览「偏好」行只有风格（美食），用户看不出被采纳。预选行追加「，经典优先」，与自动选点行为对齐。
4. **回根不刷新首页**（真机走查抓到）：直接生成后点「行程」页签回根，首页「最近行程」仍是旧数据（刚生成的上海不在、总数还是 9）。根因：`Index.onTabBarClick` 回根时只 `clear()` 栈，没像 `onChange` 那样 `announceTabShown`，四个根页的刷新广播收不到。补一行广播。修复用「编辑行程使站数 23→22，再点当前页签回根」验证：首页卡片立刻显示 `22 站`。

**真机取证（Pocket 2，sm 363.5vp，2026-10-31 00:35–00:47）**

| 路径 | 结果 |
|---|---|
| 空输入点「识别」 | 卡片内出现 `先写一句，比如「下周五去上海玩三天，两个人」`，按钮下移不遮挡 |
| 未收录城市 | 输入「下个月去西安玩三天」→ `「西安」还没有内置数据，目前支持 北京/上海/广州/深圳/杨凌`，不改目的地、不开面板 |
| 填入示例 | `下周五去上海玩三天，两个人，喜欢历史和美食，预算一万` |
| 识别预览 | 目的地 上海；日期 `11月6日 – 11月8日 · 3天2晚`（当天 10-31 周六，下周五 = 11-6）；人数 2 人；预算 `¥5,000 / 人`；偏好 `美食 · 舒适 · 公共交通 · 每天 4 站`；预选 `按每天 4 站预选 12 个景点 · 住宿区 南京东路-人民广场，经典优先`；说明 `按总预算 ÷ 2 人 折算人均` |
| 去调整 | 面板关闭，屏2 表单已是 上海 / 11月6日–11月8日 / 2 位成人 |
| 直接生成 | 生成页 `已选好 12 个景点 · 1 个住宿区域` → 行程页 `上海 · 3天2晚`（Day 1 外滩夜景与老城厢味道），TripDao 落库 `shanghai-20261106-foodie-2p`，地址回填 10 条 |
| 行程列表 | 「查看全部」第一条 `上海 2026-11-06 – 2026-11-08 · 3 天 · 2 人 · 23 景点` |
| 回根刷新（修复后） | 编辑该行程去掉 1 个节点（Day 1 8→7 节点，保存）→ 点当前「行程」页签 → 首页 `上海 · 22 站`，`查看全部 10 条行程` |

**构建 / 尺子 / hypium / 离线**

- 主 HAP：`entry-default-signed.hap` BUILD SUCCESSFUL（00:45，含回根刷新修复）；ohosTest HAP 00:49 重建 BUILD SUCCESSFUL。
- 静态十二把尺全 0 偏差（colors / type / geometry / material / fontfamily / tnum / elevation / button_width / scroll_actions / label_fit / a11y_name / layout_patterns）。
- `audit_contrast`：屏2 常态 0 处低于阈值、错误态 0 处；预览面板自身 0 处（唯一 3.57:1 的「第 1 / 5 步」在遮罩下的底层页面，非面板元素，无遮罩屏2 复测通过）。
- hypium 真机全量：`Tests run: 165, Failure: 0, Error: 0, Pass: 165, Ignore: 0`（基线 158 + TripIntent 7）。
- 离线：`PASS 69/69` + `TRIP_INTENT_OK`。

**成本（本轮唯一一次真实 LLM 调用）**

- hilog：`LLM 用量 model=deepseek-flash in=1863 (cache 命中 1024) out=3258 (思考 0) 结束=stop`，attempt=1、无重试。
- 00:42 为周六非高峰（半价）：命中 1024×¥0.01/M + 未命中 839×¥0.50/M + 输出 3258×¥2.00/M ≈ **¥0.0069**（高峰价约 ¥0.0139）。

**边界（没验到就不写成功）**

1. **未收录城市的「数据不完整」分支未触发**：5 座种子城市都有 spots/areas，`spots.length===0 || areas.length===0` 只有代码路径；线下新城市要等地图管线。
2. **「没认出目的地」文案未真机验**：空输入与未收录城市已验，但「一句没有城市名的话」没有单独走查（逻辑与前者同一条 return）。
3. **住宿区为空导致主按钮禁用未真机验**：种子城市片区库均非空，`pvCanGenerate=false` 分支只有代码证据。
4. **md/宽屏未量**：本机 sm；预览面板与两枚 120vp 按钮未在 md 复拍。
5. **浅色档未拍**：本机当前为深色，屏2 与预览只取了深色档；token 未新增颜色，沿用既有深浅双值。
6. **回根刷新的“新行程立刻出现”未二次生成复测**：修复后用「编辑→站数变化」证明回根会重取；为避免再花一次 LLM，没有重新生成新行程复现原始场景。

**数据副作用（如实记）**

- 新增并保留一条测试行程「上海 2026-11-06 – 11-08 · 3 天 · 2 人」（本轮唯一 LLM 生成）；为验证回根刷新，在屏9 移除了该行程 Day 1 的「酒店入住寄存与休整」节点（23→22 站），未删除任何既有行程。
- 原句未落盘；`PlanDraft` 里只有解析出的字段（城市/日期/人数/预算/风格/档位/交通/节奏/选点/住宿区）。
- 本机同意态 v2 未改动。

### §5ci 续 48：切片5 行后情绪落地——旅行回顾 + 城市套章 + 海报分享 + 周年横幅（真机取证）

**做了什么**

不建表、不碰 AI 契约、零 LLM：回顾/套章/周年全部从既有 `checkin`（活动打卡）、
`expense`、`trip` 聚合根派生；海报本机离屏生成，不上传、不申请相册权限。

| 件 | 文件 | 要点 |
|---|---|---|
| 回顾纯逻辑 | `utils/TripReview.ets` | `buildReview`：按天回放真实打卡、过滤已删除节点的孤儿证据、只把「首次打卡在本行程」的章算新章；`findAnniversary` 用月日比较支持跨年环绕；`anniversaryText` 按实际年份说（去年/2024 年的今天），跨年行程按落在次年的那段算 |
| 套章纯逻辑 | `utils/CityStamps.ets` | 「套」= 该城种子景点全集（北京/上海/广州/深圳各 32，杨凌 10）；名字精确匹配（归一空格），非种子章不冒充进度；`total=0` 不画 |
| 数据 | `data/TripDao.ets` | `TripSummary.checkinCount`：JOIN activity 的活动打卡数，只给「已结束且真的有景点打卡」的行程开回顾入口 |
| 数据 | `data/BadgeDao.ets` | `listForTrip` + 共用读取器，取数不再在页面里筛 |
| 数据 | `data/ShareExporter.ets` | `shareImage`：cache JPEG 以 `general.image` 交系统分享面板 |
| 回顾页 | `pages/TripReviewPage.ets` | 海报头卡、两枚动作、时间/凭证卡、逐日时间线（未打卡日如实写）、本次新章、行程总览；离屏快照海报 + 降级 |
| 行程列表 | `pages/TripsPage.ets` | 过去且有活动打卡的卡落回顾并写「已结束 · 可回顾」；其余落点不变；顶部周年横幅 |
| 勋章墙 | `pages/BadgePage.ets` | 城市组头「已收 / 总数 枚」+ 官方 Progress；集齐变 success 并出「已集齐城市套章」 |
| 路由 | `pages/AppRouter.ets` | `Review` 落点 |
| 用例 | `ohosTest/.../TripReview.test.ets` + `List.test.ets` | 6 例（回顾计数/孤儿证据/时间/周年命中与跨年/套章进度与集齐） |
| 离线 | `tools/verify_trip_review.sh` + `tools/trip_review_check.ts` | **57 条断言**，bundled tsc `--strict` 后 node 执行 |
| 方案 | `Docs/行后情绪方案.md` | 数据口径、交互、代码清单、边界 |

**中途抓到并修掉的缺陷**

1. **构建失败**：`VerticalAlign.Start` 不存在（ArkUI 只有 Top/Center/Bottom）→ 改 `VerticalAlign.Top`；`ImagePacker.packing` 在 API 26 已弃用 → 改 `packToData`。
2. **日标题主题行居中**：`dayHeader` 的 Column 没写对齐，主题文案默认居中，视觉上脱离了 Day 行 → 补 `alignItems(HorizontalAlign.Start)`，真机 bounds 从居中回到 x=50。
3. **海报 JPEG 白角**：卡片圆角外的透明区被 JPEG 压成白色，分享面板里四角发白 → 快照外垫 16vp 画布色（352vp 根宽），真机产物 1100×878、四角像素 `(18,18,18)`。
4. **回顾页同屏重复统计**：海报已有「打卡/新章/记账」三格，下面卡片又印一遍 → 撤掉重复三列，下面的卡只留到站次数与首次/末次打卡口径。
5. **周年文案会撒谎**：`findAnniversary` 允许任意往年命中，但文案写死「去年的今天」→ 改成按实际年份（`2024 年的今天`），跨年行程按今天落在的那一段年份算；离线断言补 3 条。

**真机取证（Pocket 2，sm 363.5vp，深色档，2026-10-31 01:33–01:46）**

| 路径 | 结果 |
|---|---|
| 行程列表可回顾判据 | 杨凌 10-30 的 9 站行程（有 2 条活动打卡）显示 `已结束 · 可回顾`；同天 7 站行程（0 活动打卡）仍是 `已结束 · 100%`，点进去是屏8 |
| 回顾页 | `旅行回顾`；海报 `杨凌 / 2026-10-30 – 2026-10-30 / 1 天 · 1 人 / 2 打卡 / 2 新章 / 未记账`；下方 `均为手动打卡 · 未带位置凭证`、`首次 10月30日 21:49 · 末次 10月30日 22:30` |
| 逐日时间线 | Day 1 `2 / 9`；两条真实打卡（17:15 排定 → 21:49 打卡；21:45 排定 → 22:30 打卡）；未打卡日（3 天行程的 Day 2）显示 `这天没有打卡记录` |
| 本次新章 | `本次收下 2 枚章` + 两枚章名/日期 |
| 行程总览 | 滚动到下方出现 `这趟的样子` + AI summary + 3 条 highlights（内容来自既有数据，不新增 LLM 调用） |
| 海报分享 | 分享面板 `分享 1 项 44.96 KB`，预览完整显示海报；cache 文件 1100×878、44,964 bytes；hilog `海报生成 …bytes=44964`，无降级日志 |
| 完整行程 | 回顾页点「完整行程」→ 屏8 `杨凌 · 1天0晚`（页面 onReady 取到 MINE_NAV 的栈，返回仍回回顾） |
| 空态 | 深链 `route=Review&param=yangling-20261030-1`（0 活动打卡）→ `这趟还没有可回顾的打卡` + `查看完整行程` |
| 城市套章 | 勋章墙 `杨凌 3 / 10 枚` + 进度条；3 枚章仍是原有 3 枚，没有新增/删除 |
| 对比度 | 回顾页 39 个文本节点 0 处低于阈值；勋章墙 22 个节点 0 处 |

**构建 / 尺子 / hypium / 离线**

- 主 HAP `entry-default-signed.hap` 01:48:58 BUILD SUCCESSFUL（回顾改用 `BadgeDao.listForTrip` 取本行程证据后重建）；ohosTest HAP 01:44:07 BUILD SUCCESSFUL。
- 静态十二把尺全 0 偏差（colors / type / geometry / material / fontfamily / tnum / elevation / button_width / scroll_actions / label_fit / a11y_name / layout_patterns）；`audit_contrast` 见上。
- hypium 真机全量：`Tests run: 171, Failure: 0, Error: 0, Pass: 171, Ignore: 0`（基线 165 + TripReview 6）。
- 离线：`PASS 57/57` + `TRIP_REVIEW_OK`。
- **零 LLM 调用**（回顾/套章/周年/海报均现算）。

**边界（没验到就不写成功）**

1. **周年横幅没有真机画面**：本机 10 条行程全部落在 2026–2027，没有 2025 年跨年行程命中今天（10-31）；函数与文案由离线断言 + 2 个 hypium 用例覆盖，`TripsPage` 顶部那条按钮的视觉/点击未实拍。
2. **城市套章集齐态没有真机画面**：本机只有杨凌 `3 / 10`，没有任何城市集齐；`complete=true` 的进度色与「已集齐城市套章」只有离线 + hypium 证据（上海 2/2 用例）。
3. **海报生成失败 → 文字分享的降级路径未真机触发**：快照/打包/写文件全部成功；catch 分支只有代码路径。
4. **浅色档未拍**：设备当前深色；回顾/海报/套章未新增颜色，全部走既有深浅双值 token。
5. **md/宽屏未量**：本机 sm 363.5vp；回顾页用 `symmetricInsetForCap` 收窄，海报固定 320vp（快照外框 352vp），未在 md 复拍。
6. **多城市分组未真机**：勋章墙只有杨凌一城有章；离线覆盖北京/上海/广州三组（含无种子数据的广州退回「N 枚」）。
7. **到站打卡未真机**：本机两条打卡均 `source='manual'`，「到站」标签与 `到站打卡 N 次` 的正数分支只有离线（arrival=true）+ hypium 证据。
8. **餐次打卡不进回顾**：与勋章同口径，只有餐次打卡的行程不会出现「可回顾」入口（入口按 JOIN activity 的打卡数判定）。本机被回顾的两个行程没有餐次打卡，未实测该边界。
9. **分享面板内的「保存至图库」是系统提供**：App 没有申请相册权限，也没有主动写相册；本轮没有选择任何分享目标，只验证面板拉起与图片预览。

**数据副作用（如实记）**

- 没有新增/修改/删除任何行程、打卡或费用；只读拉了 `youjing.db`（含 -wal/-shm）核对入口判据。
- App cacheDir 新增海报 JPEG（`youjing-review-yangling-20261030-001.jpg`），属可清理的运行期文件。
- 分享面板只拉起、未向任何目标发送；未改隐私同意态。

### §5ci 续 49：任意城市 Stage 1 真机探针 + RDB v9 孤儿数据清理（AGC 未过期间的旁路工作）

AGC 地理围栏/实况窗仍在审核，通知/实况窗承载层继续压着；本轮做两件不依赖它的事：
Map Kit 地点检索真机探针（任意城市数据管线的 Stage 1），以及删行程留下的孤儿数据修复。

**A. Map Kit 地点检索探针（只读，零 LLM，零 RDB 写入）**

临时 NavDestination 探针页调用 6 次 Site Kit 接口，取证后代码已删除、未提交；完整记录见
`Docs/MapKit地点检索探针-2026-10-31.md`。

| 调用 | 结果 |
|---|---|
| `searchByText(西安/景点, cityId=西安, isCityLimit=true, pageSize=20)` | `totalCount=500`、20 条；name/location/admin3/poiTypes 20/20；openingHours 多数有逐周文本；`rating/starRating` 恒 0，`reliability` 未返回 |
| `searchByText(博物馆, 不带 cityId)` | `totalCount=462`，前 20 条为卢浮宫/大英博物馆/宝马博物馆等全球结果 → **cityId 必填** |
| `searchByText(成都/景点, cityId=成都)` | `totalCount=500`，宽窄巷子/熊猫基地/武侯祠等本地结果 |
| `geocode(西安)` | 10 条；第一条「西安市」34.33365,108.81960，第二条「西安市中心」34.34208,108.94080 → 不能盲取第一条 |
| `nearbySearch(大雁塔, 酒店, 3000m)` | `totalCount=486`、20 条，带距离 146.3–851.3m → 住宿供给可判 |
| `searchById(大雁塔文化休闲景区)` | phone 有、website 无、description 546 字、abstractText 52 字、openingHours 空；评分仍 0 |

结论：Site Kit 已开通、无 1002600004、0 错误码；名称/坐标/区县/类型/营业时间可用，
**评分与预约不可得**（热度只能按检索秩，预约一律「以官方为准」），且存在重复
（西安城墙/城墙·碑林、兵马俑两条）与远郊混入（蓝田县水陆庵）。Stage 2 的约束与
开放问题（配额、缓存许可、去重阈值、Area 质量、LLM 成本）已写进探针报告；本轮不实现 Stage 2。

**B. RDB v9：孤儿打卡/费用清理 + 删行程级联**

- 改前真机库取证：`checkin` 孤儿 1 条、`expense` 孤儿 2 条（父行程已不存在），
  `trip_day/activity/meal` 孤儿 0——删除行程时子表无外键级联，打卡/费用漏删。
- `DatabaseHelper`：`DB_VERSION` 8→9；v9 迁移一次性删除五张子表里 `trip_id NOT IN (SELECT id FROM trip)`
  的行，只动父行程已不存在的孤儿。
- `TripDao.deleteRows` 拆成两条语义：`saveTrip` 重建行程树但**保留**打卡/费用（活动 id 不变）；
  `deleteTrip` 才删打卡/费用；并先按 `trip.user_id = 当前账号` 验归属，避免同 id 的他人行程被连带删除。
- 真机验证：安装后 `PRAGMA user_version=9`；五张子表孤儿全部 0；`trip=10 / checkin=4` 与迁移前一致。
- SQL 语义副本验证（不碰用户数据）：造一条合成 trip + checkin + expense 后，
  「save 路径」只删行程树、checkin/expense 保留 1/1；「delete 路径」全部清到 0/0。

**构建 / 尺子 / hypium / 离线**

- 主 HAP `entry-default-signed.hap` 02:09:59 BUILD SUCCESSFUL；ohosTest HAP 02:11:17 BUILD SUCCESSFUL。
- 静态十二把尺全 0 偏差；`audit_contrast` 本轮未改 UI，沿用上一轮结论。
- hypium 真机全量：`Tests run: 171, Failure: 0, Error: 0, Pass: 171, Ignore: 0`。
- 离线：`TRIP_REVIEW_OK cases=57` 保持（本轮未动回顾纯逻辑）。
- **零 LLM 调用**；探针 6 次 Map Kit 只读请求，无配额报错。

**边界**

1. **Stage 2 未实现**：只拿到数据可行性结论，任意城市仍未接入 UI/生成链路；Open 问题见探针报告。
2. **探针覆盖仅西安/成都两城各 1 个查询词**：未抽 10 城/多 POI 类型，`totalCount=500` 封顶后的
   分页质量、远郊比例、去重阈值还需 Stage 2 抽检。
3. **删行程级联没有走 UI 真机删除**：为避免删用户行程，只做了 DB 副本的 SQL 语义验证；
   真机只验证了 v9 迁移清理与既有数据不变。
4. **Map Kit 配额/缓存许可未确认**：端侧 key 是现成的，但检索结果能否落 RDB、缓存多久仍未知；
   Stage 2 设计按「只放内存、不落库」处理。
5. **探针代码已删**：`MapSiteProbePage` 与临时 `Probe` 路由不在提交里；当前产物是干净包。

**数据副作用（如实记）**

- v9 迁移删除了 1 条孤儿打卡、2 条孤儿费用（父行程已不存在，界面上本就不可见）；
  10 条行程、4 条有效打卡未改动。
- Map Kit 探针只发只读请求，没有创建/修改任何行程、打卡、费用或 spot/area 行。
- 本轮没有新建行程、没有生成行程、没有花费 LLM 额度。

### §5ci 续 50：Stage 2 任意城市只读接入——Map Kit 城市源 + 屏2/4/5/5b/6 来源与失败出口（真机取证）

在 Stage 1 探针结论上，把任意城市接进行前主链；结果**只放内存（30 分钟 TTL）、不写 RDB**，
内置五城/杨凌/京都 mock 行为不变。方案见 `Docs/任意城市接入方案.md`。

**做了什么**

| 件 | 文件 | 要点 |
|---|---|---|
| 纯映射 | `utils/MapCityMapper.ets` | 检索结果→Spot/Area；名称包含+近距同前缀去重；POI 类型→四值标签（映射不到进「其他」）；热度=检索秩；地址归属校验 |
| 数据源 | `data/MapKitCityStore.ets` | `searchByText('景点', cityId, isCityLimit=true)` 3×20 页；按区县 `nearbySearch('酒店')` 查供给；30min 内存缓存；无 RDB 写入 |
| 回退 | `data/PlanRepository.ets` | 种子优先；种子为空且 `isMapCity(city)` 才走 Map Kit |
| 城市判定 | `common/constants/Cities.ets` | `isMapCity` = 非内置五城、非京都 |
| 失败 | `ErrorCode` 1004 + `FailureCopy` | 标题「地图数据没取到」、副标题「地图服务没有返回这座城市的景点或住宿区，检查网络后再试」 |
| 屏2 | `TripInputPage.ets` | 一句话命中未内置城市不再拒绝；城市面板新增「其他城市」输入 + 使用；识别器不再提前 return，日期/人数/预算照常解析；副标题改为「识别在本机完成；未内置城市会联网查地图服务，不花模型额度」 |
| 屏4 | `SpotPickPage.ets` | 来源提示；Map Kit 空态「地图服务没取到/没有返回 X 的景点」+ 重试/换城市；新增「其他」分组 |
| 屏5 | `StayPickPage.ets` | 来源提示；区县卡显示「舒适档（未校准）· 地图服务区县」，隐藏 0 分钟等假字段 |
| 屏5b | `AreaMorePage.ets` | 组头「地图服务区县」；三行元信息改为未校准说明 |
| 屏6 | `GeneratingPage.ets` | 地图城市缺景点/住宿区抛 1004，不再只报 4003 |
| 用例 | `MapCityMapper.test.ets` + `List.test.ets` | 6 例（去重/映射/区县/套章/城市判定/地址归属） |
| 离线 | `tools/verify_map_city.sh` + `tools/map_city_check.ts` | 52 条断言 |
| 方案 | `Docs/任意城市接入方案.md`、`Docs/任意目的地数据管线.md` §8 | 数据流、去重、字段口径、页面、边界 |

**中途抓到并修掉的缺陷**

1. **无效 cityId 静默返回全国结果**：手工输入「不存在市」时 MapKit 返回红旗渠/岳阳楼/
   赛里木湖/泰山等 60 条，`isCityLimit` 拦不住。补地址归属校验后拒绝。
2. **城市归属字段用错层级**：第一次只用 `locality/adminLevel3`，把合法西安也全滤掉；
   真机地址样本证明 `locality=''、adminLevel2='西安市'、adminLevel3='雁塔区'`，
   **adminLevel2 才是市级**（adminLevel1 是省）。改为 locality/admin2/admin3 三项任一命中。
3. **一句话仍写「不联网也不花额度」**：Map Kit 城市会联网取数，文案改为如实说明。
4. **城市面板「使用」在百分比高 Scroll 里 + 禁用态低对比度**：把主操作移出 Scroll、
   去禁用（空输入点按给 toast）；重拍后面板自身 0 处低于阈值，唯一 3.57:1 是遮罩下的底层页面。
5. **来源提示 100% 宽 + 横向 margin**：改外层 padding。
6. **未内置城市解析器提前 return**：日期/人数/预算全丢；改为设置 unsupportedCity 后继续解析。
7. **屏4 未映射类型会被分组吞掉**：新增「其他」分组。

**真机取证（Pocket 2，sm 363.5vp，深色档，2026-10-31 02:36–02:48）**

| 路径 | 结果 |
|---|---|
| 西安一句话 | `去西安玩三天` → 预选 `按每天 4 站预选 12 个景点 · 住宿区 碑林区`；说明 `西安未内置，景点与住宿区来自地图服务；开放时间与预约以官方为准` |
| 西安生成 | 直接生成 → 行程页 `西安 · 3天2晚`，Day 1 `临潼东线：兵马俑深度看展+老城碑林夜景`；落库 `xian-20261106-3d2p` |
| Map Kit 数据 | `西安 raw=60 deduped=54 spots=54 areas=6 districts=6`；地址样本 `locality= / admin2=西安市 / admin3=雁塔区` |
| 手工其他城市 | 城市面板输入「成都」→ 使用 → 屏4 `经典 · 8/52`（60 条去重后 52 条经典）、宽窄巷子/熊猫基地等；屏5 `青羊区` + `舒适档（未校准） · 地图服务区县`；屏5b 6 个「地图服务区县」 |
| 坏城市 | 输入「不存在市」→ 屏4 `地图服务没取到不存在市的景点` + `检查网络后重试，或换一座城市` + 重试/换城市（不再返回全国结果） |
| 内置回归 | 北京默认城市→屏4 `必去 · 7`、故宫/八达岭/颐和园等种子数据，无地图服务提示 |
| 数据不落库 | 生成后 `spot` 仍 138 条、城市仍 上海/北京/广州/杨凌/深圳；`trip=11`（新增 1 条西安测试行程）、`checkin=4`、孤儿 0、`user_version=9` |

**构建 / 尺子 / hypium / 离线 / 对比度**

- 主 HAP 02:45:54 BUILD SUCCESSFUL；ohosTest HAP 02:46:52 BUILD SUCCESSFUL。
- 静态十二把尺全 0 偏差。
- hypium 真机全量：`Tests run: 177, Failure: 0, Error: 0, Pass: 177, Ignore: 0`（基线 171 + MapCityMapper 6）。
- 离线：`MAP_CITY_OK cases=52`、`TRIP_INTENT_OK cases=76`、`TRIP_REVIEW_OK cases=57`。
- `audit_contrast`：屏4 地图城市 27 节点 0 低、屏5 地图城市 23 节点 0 低；城市面板自身 0 低
  （唯一 3.57:1 的「第 1 / 5 步」在遮罩下的底层页面，非面板元素）。

**成本**

- 一次真实 LLM 调用：`in=1771 (cache 1024) out=2924 (思考 0) 结束=stop`，无重试。
- 32 分（周六非高峰，半价）：命中 1024×¥0.01/M + 未命中 747×¥0.50/M + 输出 2924×¥2.00/M
  ≈ **¥0.0062**（高峰价约 ¥0.0125）。
- Map Kit 6 次只读检索 + 6 次酒店供给查询/城，无配额报错。

**边界（没验到就不写成功）**

1. **评分/预约无可信字段**：热度按检索秩，预约一律不展示为事实；开放时间已取到但本轮没有展示。
2. **住宿区未校准**：档位固定舒适、通勤/餐饮留空；屏5b 仍会列出远郊县（大邑/邛崃/彭州、蓝田），
   默认三片由屏5 的距离排序压到近处，但没做硬距离过滤。
3. **只有西安跑完整生成**；成都只走到屏5/5b，未生成；无效城市只验了失败出口。
4. **无网/超时未真机断网验证**：坏城市走的是「返回全国结果→归属校验为空」路径，不是网络失败。
5. **缓存只在内存**：App 重启后重新检索；30 分钟 TTL 未在真机等满复测。
6. **Map Kit 配额/缓存许可**未确认；因此坚持不落 RDB。
7. **md/浅色档未量**：本机深色 sm；新页面颜色全部走既有 token。
8. **地址归属是文本匹配不是行政区划校验**：同名区县（如辽源市西安区）理论上可能误命中；
   只有西安/成都/坏城市三组真机样本。

**数据副作用（如实记）**

- 新增并保留一条西安测试行程 `xian-20261106-3d2p`（3 天 2 人，02:36 生成）；没有删除或改
  用户既有行程/打卡/费用。
- Map Kit 景点/住宿区只存在内存，`spot`/`area` 表未新增行。
- 未向任何第三方分享/上传数据；未改隐私同意态。

### §5ci 续 51：Stage 2.5 任意城市体验收口——热门城市快捷入口 + 住宿区按供给排序（真机取证）

**做了什么**

- **屏2 城市面板**：在「其他城市」输入下方加「热门城市（地图服务）」8 个快捷 chip
  （西安/成都/杭州/重庆/南京/武汉/长沙/厦门），点选直接填目的地并关面板；下面再分
  「内置数据城市」。新增 `POPULAR_MAP_CITIES` 常量，不伪造成种子城市。
- **住宿区候选**：MapKit 取数时对前 10 个区县查酒店供给（原 6 个），
  `buildAreas` 先按酒店供给降序、再按景点数，取前 8（原 6）。单区县酒店查询
  `1002603001`（零结果）按 0 处理，不阻断整城。
- 纯逻辑/用例：`MapCityMapper.test.ets` 补热门城市与「供给高但景点少的中心区优先」断言；
  离线 `MAP_CITY_OK` 从 52 条增到 56 条。

**真机取证（Pocket 2，sm，深色档，2026-10-31 03:14–03:18）**

| 路径 | 结果 |
|---|---|
| 城市面板 | 「其他城市」输入 + 「热门城市（地图服务）」8 chip（两行）+「内置数据城市」；面板可滚 |
| 热门城市点选 | 点「西安」→ 目的地立即变西安；开始规划 → 屏4 `景点来自地图服务`、`经典 · 8/45` |
| 住宿区 | 屏5 首推 `雁塔区`、`舒适档（未校准） · 地图服务区县`；屏5b 列表变为
  碑林/莲湖/新城/雁塔/未央/灞桥（市中心优先，不再是之前的大邑/邛崃/彭州混杂） |
| Map Kit 日志 | `西安 raw=60 deduped=54 spots=54 areas=8 districts=10`；1 个区县酒店查询零结果被容错 |
| 内置回归 | 本次未重新走北京；上一轮同一构建的北京种子路径已验，且本次只改城市面板/Area 排序，不碰种子取数 |

**构建 / 尺子 / hypium / 离线 / 对比度**

- 主 HAP 与 ohosTest HAP BUILD SUCCESSFUL；hypium **177/177**（用例数不变，新增断言在既有例内）。
- 静态十二把尺全 0 偏差。
- 离线：`MAP_CITY_OK 56`、`TRIP_INTENT_OK 76`、`TRIP_REVIEW_OK 57`。
- `audit_contrast` 城市面板：34 节点，2 处低于阈值（3.57:1「第 1 / 5 步」与 4.09:1「3天2晚」），
  两处都在**遮罩下的底层页面**，不是面板元素；面板内 chip/输入/说明 0 处。

**成本与数据副作用**

- 零 LLM；MapKit 只读请求增加（每城最多 10 个区县酒店查询），无配额报错。
- 没有新建/修改/删除行程、打卡、费用；MapKit 结果仍只在内存。
- 宽屏模拟器尝试（Mate X7）未产出结论：自定义 `-hdcPort 10001` 下 hdc 只能 shell，
  `file send/recv` 与 `install` 均挂死；默认 5557 被另一任务占用。宽屏/md 适配仍未验证。

**边界**

1. 供给排序是启发式：市中心通常酒店多，但远郊县仍可能在 8 个候选里；屏5 默认三片由距离排序压近。
2. 热门城市只放 8 个；其余仍可输入。
3. 城市面板在 sm 上需要滚动才能看到全部内置城市；未在 md/浅色复拍。
4. 本轮只验证了西安；成都的供给排序只有上一轮数据与纯逻辑断言，未重新走屏5。

### §5ci 续 52：Stage 2.6 开放时间接入 + 提示词地图口径修正（真机取证）

**做了什么**

- `Spot` 增可选 `openingHours?: string`；`MapCityMapper.commonHours` 把 MapKit
  `poi.openingHours.texts` 的逐周文本归并成「每日一致且单时段」：
  `8:30–17:00` / `全天开放`；闭馆、午休多段、各天不一致或缺数据一律留空。
- 屏4 景点行在「区县 · 建议停留」下增加 `开放 8:30–17:00 · 地图服务`；
  种子景点没有该字段，不显示。
- 提示词修正两处不实口径：
  1. MapKit 景点此前因 `requiresBooking=false` 被写成「无需预约」→ 改为
     「预约信息未获取，以官方为准」，并加规则 15 禁止编造预约方式/提前天数；
  2. MapKit 住宿区此前会把「0 分钟、空线路、空锚定站」喂给模型 → 改为
     「地图服务区县；住宿档、通勤与餐饮未校准，具体住宿以平台实时信息为准」。
- 提示词新增规则 14：有「开放」时段时排期必须落在时段内，没信息不要编造。
- `PromptContract.test.ets` 补地图口径用例（地图景点/住宿区的提示词断言）。

**真机取证（Pocket 2，sm，深色档，2026-10-31 03:20–03:24）**

| 路径 | 结果 |
|---|---|
| 西安屏4 | 首屏可见 `开放 7:30–14:00 · 地图服务`、`开放 8:00–22:00 · 地图服务`、`开放 6:00–22:30 · 地图服务`，与探针原始字段一致 |
| 来源提示 | `景点来自地图服务` / `停留时长为估算，预约与开放时间以官方为准` 仍在 |
| 提示词 | hypium 断言：地图景点行含「预约信息未获取，以官方为准」「开放:8:30–17:00」，不含「无需预约」；地图住宿区行含「地图服务区县」，不含「到机场 0 分钟」；system prompt 含规则 14/15 |
| 种子回归 | 未重新生成；本轮只改 MapKit 映射/提示词，种子 Spot 无 `openingHours`，屏4 行不增字 |

**构建 / 尺子 / hypium / 离线**

- 主 HAP 与 ohosTest HAP BUILD SUCCESSFUL；hypium **178/178**（177 + PromptContract 地图口径 1 例）。
- 静态十二把尺全 0 偏差。
- 离线：`MAP_CITY_OK 63`（+7 条开放时间断言）、`TRIP_INTENT_OK 76`、`TRIP_REVIEW_OK 57`。
- 本轮未改配色/材质/布局尺寸；对比度沿用上一轮结论。

**成本与数据副作用**

- 零 LLM；MapKit 只读请求未增加（仍为检索 + 最多 10 个区县酒店查询）。
- 没有新建/修改/删除行程、打卡、费用；MapKit 数据仍只在内存。

**边界**

1. 只展示各天一致的单时段；有午休、闭馆日、各天不同或没有 texts 的景点不显示开放时间，
   仍以官方为准。
2. 提示词规则 14/15 尚未用真实生成验证（会再花一次 LLM 额度）；本轮只有纯函数/hypium 证据。
3. 屏10 详情面板/分享文本尚未展示 MapKit 开放时间；本轮只上屏4。
4. 种子景点没有开放时间字段，行为不变。
5. md/浅色档未复测。

### §5ci 续 53：Stage 2.7 MapKit 区县酒店查询并发化（真机耗时对比）

**做了什么**

- `MapKitCityStore.fetch` 的 10 个区县 `nearbySearch('酒店')` 从顺序 `await` 改为
  `Promise.all` 并发；单区县仍由 `hotelCount` 内部 catch 成 0，不阻断整城。
- fetch 成功日志补 `costMs`，后续可直接观测取数耗时。

**真机取证（Pocket 2，sm，2026-10-31 10:49）**

| 项 | 结果 |
|---|---|
| 并发前 | 同一台机、同一查询（西安）：约 **4.7s**（03:15 日志：地址样本 01.914 → 完成 06.603） |
| 并发后 | `西安 raw=60 deduped=54 spots=54 areas=8 districts=10 costMs=2504` |
| 数据一致性 | 屏4 仍 `经典 · 8/45`，开放时间仍见 7:30–14:00 / 8:00–22:00 / 6:00–22:30 |
| 容错 | 仍有 1 个区县酒店查询 `1002603001`（零结果），按 0 处理，整城成功 |

**闸门 / 成本 / 副作用**

- 主 HAP BUILD SUCCESSFUL；hypium **178/178**；离线 `MAP_CITY_OK 63` /
  `TRIP_INTENT_OK 76` / `TRIP_REVIEW_OK 57`；十二把尺 0。
- 零 LLM；无行程/打卡/费用/spot 写入。
- 边界：并发数 = 区县数（最多 10）；本次只测西安一城；MapKit 配额与限流仍未确认，
  若并发导致更多零结果，后续可降到 3–4 并发分批。

### §5ci 续 54：城市别称识别 + MapKit 同名远距离不合并（纯逻辑轮）

**做了什么**

- `Cities.MAP_CITY_ALIASES` 增 10 个别称 → Map Kit 城市：蓉城/山城/金陵/江城/星城/
  鹭岛/春城/冰城/泉城/岛城；`TripIntentParser.matchUnsupported` 先认别称再扫城市表，
  一句话「去蓉城玩三天」现在能进 Map Kit 流程。
- `MapCityMapper.isDuplicate`：同名记录从「无条件合并」收紧为「同名且相距 ≤3km」，
  同名但更远视为不同地点（如两座「万达广场」）；包含/近距同前缀规则不变。

**验证**

- 离线：`MAP_CITY_OK 66`（+3 条：同名远距离、别称数量/归属）、
  `TRIP_INTENT_OK 80`（+4 条：蓉城/山城别称与字段保留）、`TRIP_REVIEW_OK 57`。
- 真机 hypium：`Tests run: 178, Failure: 0, Error: 0, Pass: 178`（别称/去重断言在既有用例内）。
- 双 HAP BUILD SUCCESSFUL；十二把静态尺 0 偏差。
- 零 LLM；无行程/打卡/费用/spot 写入。

**边界**

1. **没有真机 UI 走查别称句**：设备当前停在系统天气/锁屏页，按规矩不碰、不解锁；
   本轮只有纯逻辑 + hypium 证据。浅色档走查也因此挂起（临时 lightprobe 已撤回，未提交）。
2. 别称只收 10 个不易误伤的词；不是任意城市自由文本解析。
3. 同名远距离不合并可能让极少数重复 POI 出现在列表里；这是宁可见两个、不误删一个的取舍。

### §5ci 续 55：浅色档逐屏走查 + 三处修复（真机取证）

设备空出后，用临时 `lightprobe=1` 把 **App** 钉进浅色档（系统主题不动），逐屏走查；
临时探针已撤回、未提交。最终源码仍跟随系统，真机复验为深色。

**走查范围与对比度（audit_contrast）**

| 页面 | 结果 |
|---|---|
| 首页 | 22 节点 0 低 |
| 屏2 基础信息 | 25 节点 0 低 |
| 城市面板 | 面板自身 0 低；2 处低于阈值是遮罩下的底层表单（1.07:1），非面板元素 |
| 别称预览（去蓉城） | 42 节点 0 低；`蓉城 → 成都`、12 预选、青羊区、地图来源说明均正确 |
| 屏4 | 30 节点 0 低 |
| 屏5 | 23 节点 0 低 |
| 屏5b | 36 节点 0 低 |
| 屏8 | 27 节点 0 低 |
| 旅行回顾 | 修复前 2 处低：海报脚注 3.00:1、日主题 3.19:1；修复后 39 节点 0 低 |
| 我的勋章 | 22 节点 0 低 |
| 分享与导出 | 31 节点 0 低 |
| 费用 / 地图 | 24 / 20 节点 0 低 |
| 我的行程 | 55 节点，2 处 1.14:1 均来自第四张卡被浮动 dock 覆盖（可滚动让出，非文字色缺陷） |

**修复的三处**

1. **城市面板：系统关闭 ✕ 压住「使用」按钮**（浅色截图直接可见，深色同样存在）。
   「其他城市」输入行增加 `top: SpaceTokens.xl`，把「使用」移到 ✕ 下方；浅色/深色复拍均不再重叠。
2. **屏4：「开放 全天开放」重复**。全天时段改为只显示 `全天开放 · 地图服务`；
   普通时段仍是 `开放 8:00–22:00 · 地图服务`。深色/浅色复拍确认。
3. **旅行回顾：`faint` 文本在浅色下不可读**。海报脚注、日主题、空日行、页脚由 `faint` 改
   `muted`；浅色对比度从 3.00/3.19 归零，深色复拍仍为 39 节点 0 低。装饰性 highlight 圆点保留 faint。

**闸门 / 成本 / 副作用**

- 双 HAP BUILD SUCCESSFUL；hypium **178/178**；离线 `MAP_CITY_OK 66` /
  `TRIP_INTENT_OK 80` / `TRIP_REVIEW_OK 57`；十二把尺 0。
- 零 LLM；没有新建/修改/删除行程、打卡、费用、spot；MapKit 只读。
- 边界：浅色探针未提交；登录/隐私同意/生成失败页未在浅色下走查；md/宽屏仍未验；
  试走查时曾发现设备在系统天气/锁屏页，按规矩未解锁、未点击，等设备空出后才继续。

### §5ci 续 56：MapKit 开放时间回填到 sight 活动 note（端到端待复验）

**做了什么**

- `TripEnrich.backfillOpeningHours(trip, spots)`：只处理 `category=sight`，按现有
  `matchSpot`（精确同名/包含）找景点；景点有 `openingHours` 时把 `开放 8:30–17:00`
  追加到活动 `note`（已有同一时段不重复）。餐次/交通/酒店不写。
- `LlmClient.generateTrip` 在地址回填后调用，日志增加「开放时间 N 条」；屏10 详情面板
  本来就会显示活动 note，因此不需要新 UI/表结构。

**验证**

- hypium **179/179**（新增 `opening_hours_go_to_sight_note_once_only`：只写 sight、
  已有 note 用 `·` 追加、二次回填不重复、food 不写）；主/测试 HAP 成功；
  离线 `MAP_CITY_OK 66` / `TRIP_INTENT_OK 80` / `TRIP_REVIEW_OK 57` 保持；十二把尺 0。
- **端到端没拿到**：先试「西安 1 天」真实生成，两次均失败——
  第 1 次 `days[1].dayIndex=1 应为 2`（模型重复 dayIndex），第 2 次
  `JSON 解析失败: Unexpected Object in JSON`；两次都在解析阶段，`backfillOpeningHours` 未执行。
  随后改试 3 天，MapKit 检索返回 `1002600002 Failed to connect to the Map Kit server`，
  识别入口直接失败，未走到 LLM。
- **成本**：两次失败调用均为 Flash：
  `in=1584(缓存384) out=1303` 与 `in=1584(缓存1408) out=1624`，半价约 **¥0.0066**；
  没有成功生成、没有新建行程（trip 仍 11 条）。
- 因此本轮只有纯逻辑/hypium 证据；屏10 显示 note 的槽位是既有能力（此前已验），
  但「生成后 note 真的出现开放时间」没有真机画面。

**边界**

1. 1 天行程的 LLM 输出稳定性差（dayIndex 重复/JSON 非法），不是本轮 enrichment 引入；
   需要单独排查提示词或解析容错。
2. MapKit 连接 `1002600002` 是服务/网络层，恢复后可重跑 3 天路径补屏10 证据。
3. 只有「各天一致开放时段」的 MapKit 景点会被写入；闭馆/午休/不一致仍无。
4. 种子景点没有 openingHours，行为不变。

**后续补验（2026-10-31 14:36–14:38，端到端已闭合）**

- MapKit 恢复后重试 3 天西安：`attempt=1` 成功，`days=3 回填地址 12 条、开放时间 2 条`；
  落库 `xian-20261031-2`（2026-10-31–11-02）。
- DB 取证：11 条活动 note 带开放时间；其中 `曲江池遗址公园`/`杜邑遗址公园` 两条是
  `backfillOpeningHours` 追加的 `· 开放 全天开放`，其余为模型按提示词自己写入。
- 屏10 首站 note 显示 `预约信息未获取……开放时段8:00–22:00`；屏10 对比度 55 节点，
  仅浮层下的底层 Day 2/Day 3 标签 3.26/3.29 被标（非面板元素）。
- 顺手修：AI 已写「全开放」时不再追加「开放 全天开放」；hypium **179/179**。
- 成本：成功调用 `in=2003(缓存1152) out=2412`，半价约 **¥0.0053**；连同此前两次失败
  ¥0.0066，本轮开放时间链路共约 **¥0.0119**。
- 数据副作用：新增并保留 3 天西安测试行程 `xian-20261031-2`。

### §5ci 续 57：1 天行程 LLM 输出稳定化（真机复验待设备解锁）

**证据与根因**

- 2026-10-31「西安 1 天」两次失败：第 1 次 `days[1].dayIndex=1 应为 2`，第 2 次
  `JSON 解析失败: Unexpected Object in JSON`。
- 用户消息只写「日期：X 至 X」，没有数字天数；系统规则 1 也只说「等于用户给定的天数」。
  单日窗口下模型把行程拆成「抵达日 + 游玩日」，两天 `dayIndex` 都写 1；
  解析器按数组位置硬校验后整份打回。JSON 非法那次没有原文，无法归因——
  本轮补了失败原文片段日志，后续再出现时可直接看形态。

**修改**

- `PromptBuilder.userPrompt` 首行写 `计划天数：N 天`；规则 1 明确首日等于 `startDate`、
  末日等于 `endDate`；新增规则 16：计划 1 天时 `days` 恰好 1 个元素，禁止拆成
  「抵达日 + 游玩日」两天。
- `TripParser.parseTrip(text, expect?)` 新增可选窗口：多出的天按窗口截断，
  `dayIndex/date` 按数组位置重写；少于窗口仍抛 `SCHEMA_VALIDATION_FAILED` 重试。
  不传 `expect` 时保持原有严格 `dayIndex` 校验，既有守卫语义不变。
- `LlmClient.generateTrip` 用 `DateUtils.spanDays` 传入窗口；失败时打印模型原文前
  240 字（压缩空白），补上此前「解析失败却没有原文」的盲区。
- 真实调用补验时又抓到第二处契约冲突：提示词规则 9 允许 `location`
  「没有入口信息时留空串」，`TripSchema.str(true)` 也只约束 string，但
  `TripParser` 用 `reqStr` 要求非空。解析器改为 `reqStrAllowEmpty`（键仍必须存在），
  与提示词/Schema 对齐。

**验证（本轮已做）**

- 离线：DevEco 自带 tsc `--strict` 零诊断；断言 `PASS 8/8`（重复 `dayIndex` 归一、
  单日多吐一天截断、缺天失败、无窗口仍严格、缺 `dayIndex` 不可修复、
  1 天提示词天数与规则 16、空 `location` 可解析）。
- 主/测试 HAP 均 `BUILD SUCCESSFUL`（仓库根 hvigor CLI；15:36 重装版），
  `ets/modules.abc` 内已 grep 到「计划天数」「不得把行程拆成」「本次行程要求」
  `reqStrAllowEmpty`。
- hypium **185/185**（新增 6 例：重复 `dayIndex` 归一、单日多吐一天截断、缺天失败、
  空 `location` 可解析、1 天提示词天数与规则 16、LlmClient 窗口接线）。
- 十二把尺 0；离线 `MAP_CITY 66` / `TRIP_INTENT 80` / `TRIP_REVIEW 57`；
  `REPLAN 74+26` / `WEATHER 102` 全绿。
- **真实模型补验**（2026-10-31 15:30，周六非高峰；离线副本复用同一份
  `PromptBuilder`/`TripParser`，夹具为 2 个 MapKit 风格西安景点 + 碑林区）：
  - 第 1 次：`rawDays=1`，但解析在 `activities[0].location` 空串处失败——
    模型遵守规则 9 留空，解析器却要求非空，遂做上面的 `reqStrAllowEmpty` 修正。
  - 第 2 次：`rawDays=1`，`parseTrip` 成功得到 `days=1 dayIndex=1
    date=2026-11-01 start=end=2026-11-01`，11 个活动 / 3 餐。
  - 用量：第 1 次 `in=1555(cache 0) out=1193`；第 2 次
    `in=1555(cache 命中 1408) out=1407`。
- **真机 App 端到端**（2026-10-31 15:44）：一句话「西安 1 天」→ 直接生成；
  日志 `LLM 用量 in=1662(cache 命中 1152) out=1434 结束=stop`、
  `生成成功 attempt=1 days=1 回填地址 6 条、开放时间 0 条`；
  屏8 显示「西安 · 1天0晚 / Day 1 · 10月31日」；DB 新增
  `xian-20261031-daytrip`（start=end=2026-10-31），trip_day 恰好 1 行
  （day_index=1）、11 条活动。
- 成本：两次离线副本真实调用 + App 端一次，按 Flash 周六半价
  （命中 ¥0.01/M、未命中 ¥0.50/M、输出 ¥2.00/M）合计约 **¥0.0092**。
- 数据副作用：新增并保留 1 天西安测试行程 `xian-20261031-daytrip`。

**真机边界**

- 设备解锁后已安装主/测试 HAP、跑完全量 hypium，并完成真机 1 天生成闭环。
- 历史第 2 次失败（JSON 非法）没有复现；现在失败会打印模型原文前 240 字，
  再出现可直接定位是围栏、多对象还是未转义引号。
- 环境坑：DevEco MCP `build_project` 实际构建了 IDE 当前打开的 HarmonyProject1
  （其 ohosTest HAP 15:17 更新），不是本仓库；本轮改用仓库根 hvigor CLI 构建并
  用 abc 字符串核产物，避免把别的项目装到真机。
- 真机同步检测到锁屏（`10106102`）时按规矩未解锁、未绕过，等设备空出后才继续。

### §5ci 续 58：单日短途质量收口（预选按 10h 窗口 + 负载去重）

**问题**

- 续 57 的真机 1 天行程 `xian-20261031-daytrip` 仍是「标准 4 站」预选：
  07:00–21:40、4 个景点 + 2 餐 + 5 段交通，负载条 18.6h。用户点「直接生成」
  拿到的是需要手动减站的计划。
- 负载条把交通节点的「节点时段」和它自带的 `transport.duration` 都累加；
  模型常常两者相同（08:00–09:20 + duration 80），同一条腿被算两次。
  11-02 行程实际 07:30–17:30 正好 10 小时，旧口径却报 13.4h、超建议 3.4h。

**修改**

- `PlanAutoPick.pickSpotsForSingleDay`：单日先用节奏上限取候选，以住宿区为起点，
  按 `直线 × 1.2 道路系数 / 30km/h + 8min` 估每段通勤；「停留 + 往返通勤」
  超过 `600 − 120 = 480min` 就从低优先级端往回砍，至少留 1 站。首站仍是必去。
  屏2 一句话生成改调此方法；预览文案改为「按单日 10 小时窗口预选 N 个景点」。
- `PromptBuilder` 规则 17：单日停留 + 通勤 ≤10h、首站不早于 07:30、末站不晚于
  21:00，装不下删 want/optional；规则 2 补「交通节点不要再填 transport，避免重复计算」。
- `DayLoadCalc`：交通节点只取「节点时段」或「自带 duration」其一（没时段才用后者），
  非交通节点仍叠加到达该站的通勤。修正前一条 10h 的行程会被报成 13.4h。

**验证**

- 离线 `TRIP_INTENT 86/86`（新增单日预算 6 例）；hypium **186/186**（新增单日预算 1 例，
  `transport_node_counts_once` 改为断言只算一次 + 无时段兜底）；十二把尺 0；
  `MAP_CITY 66` / `TRIP_REVIEW 57` 保持。
- 真机 11-02 单日西安：预览「按单日 10 小时窗口预选 2 个景点 · 住宿区 灞桥区」；
  生成 `attempt=1 days=1`，DB `xian-2026-11-02-1d` 1 天 8 条活动；
  实际排期 07:30–17:30，负载条修正后 **10.1h · 超建议 0.1h**（同一行程旧口径 13.4h）。
- 花费：本轮新增一次真实生成 `in=1625(cache 命中 512) out=1073`，周六半价约 **¥0.0027**。
- 数据副作用：新增并保留测试行程 `xian-2026-11-02-1d`；10-31 的 4 站旧行程保留不动。

**边界**

- 10.1h 仍在 10h 窗口外 0.1h，所以「超建议 0.1h / 去减一站」照常显示；
  没有为边界值加宽容差，避免把真实超载藏起来。
- 通勤估算是直线距离启发式，不是真实路径规划；远郊景点会按 1.2/30km/h 粗算，
  与实际公交/专线时长可能有偏差。单日首站优先级最高，不会被预算砍掉。
- 10-31 的旧 4 站行程是修正前数据，仍会显示 18.6h；没有重新生成/改写用户行程。

### §5ci 续 59：浅色档补齐登录/隐私同意/生成失败三页（禁用按钮去 opacity）

**走查方式**

- 临时探针（只用于取证、已撤、未入库）：`lightprobe=1` 把本 App 钉进浅色档（系统主题不动）、
  `loginprobe=1` 强制出登录页、`consentprobe=1` 强制开隐私同意弹窗；
  失败页走既有深链 `--ps route GenerateFailed`。全程未退出华为账号、未清用户数据。
- 每页 `dumpLayout` + `snapshot_display`，过 `tools/audit_contrast.py`。

**发现并修复**

- 浅色登录页「华为账号一键登录」实测 **1.26:1**：`YoujingButton` 用
  `.opacity(disabled ? 0.4 : 1)` 表达禁用态，既违反 handoff §8 禁令 10
  （不许用 opacity 表达状态），也把白字连同淡蓝底一起压掉对比度。
  改为禁用态标签走 `muted` token、底色交回官方 Button 的 disabled 渲染。
  同一颗组件覆盖另外 4 处禁用主按钮（屏2 开始规划/识别、屏12 分享、启动页、登录页）。

**验证**

- 浅色：登录页 14 节点 **0 低**（修前 1 处 1.26:1）、隐私同意 28 节点 0 低、
  生成失败 24 节点 0 低。
- 深色同三页补拍（这两档此前都没走过查）：登录 15 节点 0 低、失败 24 节点 0 低；
  同意弹窗报 8 处低，逐条核对全是遮罩下的底层首页文字（开始规划新行程 / dock 四签 /
  最近行程 / TRACEABLE ROUTES 等），弹窗自身文字 0 低——按既有口径不计为缺陷。
- 撤探针后重建：主/测试 HAP `BUILD SUCCESSFUL`，产物 abc 内 grep 探针字符串 0；
  hypium **186/186**；十二把尺 0。
- 零 LLM、零行程/打卡/费用改动。

**边界**

- md/宽屏档这三页仍未验（模拟器通道未解决，见 [[harmonyos-emulator-cli]]）。
- 浅色档只能靠 App 级探针复现：本机没有 `settings` 命令切系统深浅色。

### §5ci 续 60：13 个提交推上 GitHub + 丽江住宿区预选取证

**推送**

- `main` 领先 13 个提交，已全部推送：`70fdf0c..d5433cd`，远端 `refs/heads/main = d5433cd`，
  本地与 `origin/main` 已同步。
- 通路：`~/.gitconfig` 的 `http(s).proxy=127.0.0.1:7890` 在，SSH 推送被该代理直接
  `Connection closed`；改用钥匙串凭据走 HTTPS 显式 URL 推送，**未改动任何 git 配置**。
- 推送前安全核对：提交版 `ApiConfig.ets` 的 `BASE_URL`/`LLM_CHAT_ENDPOINT`/`API_KEY` 均为空串；
  全历史按 `sk-[0-9a-f]{24,}` 扫描 0 命中（`-S 'sk-'` 的两次命中是 "task-" 误报）；
  `build-profile.json5` 与 `ApiConfig.ets` 都是 skip-worktree，签名口令不在库里；
  未跟踪的 `.merkle-snapshot.json` 按规矩不入库。

**丽江校准发现**

- 「丽江 2 天」一句话识别走 MapKit：`raw=60 deduped=48 spots=48 areas=4 districts=4 costMs=2489`，
  预选结果 `8 个景点 · 住宿区 玉龙纳西族自治县`。游客实际住的是**古城区**（大研/束河），
  这正是 `Docs/任意城市接入方案.md` 记的「远郊县仍可能出现在屏5b」那条未收口的账。
- 但现有日志只有汇总，判不出**古城区到底有没有进候选、被谁挤掉**：
  是 `buildAreas` 按酒店供给排序挤掉了它，还是 `PlanAutoPick.pickArea` 的
  「到已选景点平均距离最近」被玉龙雪山卫星簇拖走，两条修法完全不同。
- 因此本轮只补取证，不改规则：`MapKitCityStore` 增加一行
  `候选区县 名 景点数/酒店数 → 住宿区顺序`，下次设备空出跑一次丽江即可定位。
  在没有这条数据前把排序改成「景点多数投票」属于凭猜改口径。

**设备边界**

- 走查中途 `aa dump -l` 前台变为 `com.huawei.hmos.outerhome`、有径进程 PID 由 38938 换成 42448，
  注入点击不再改变界面——判定为真人接手，按规矩立即停手，未继续点击、未解锁。

**验证**

- 主 HAP `BUILD SUCCESSFUL`；离线 `MAP_CITY 66/66`；零 LLM、零数据改动。

### §5ci 续 61：丽江取证闭环——住宿区预选改「多数景点投票，平票按列表顺序」

**取证（17:20，装的是带诊断行的构建）**

- `丽江 候选区县 玉龙纳西族自治县 22景/139店、古城区 20景/467店、宁蒗彝族自治县 5景/70店、
  永胜县 1景/11店 → 住宿区顺序 古城区/玉龙纳西族自治县/宁蒗彝族自治县/永胜县`
- 结论：**屏5 列表是对的**（古城区按酒店供给排第一），错的是自动预选。
  用户那条 `lijiang-20261031-1` 的真实景点是古城区 2（束河古镇、丽江古城）
  / 玉龙县 2（蓝月谷、白沙古镇）——平票，而 `pickArea` 只看平均直线距离，
  被玉龙雪山那颗卫星点拉去县城，于是「屏2 预选」和「屏5 首屏推荐」自相矛盾。

**修法**

- `PlanAutoPick.nearestArea`：主键改为「多少个已选景点离这片最近」，
  平票按传入顺序——屏5 候选顺序本身就是酒店供给降序，所以平票等于让更适合住的一片赢。
  平均距离不再参与判定（它衡量的是几何中心，不是「适合住宿」）。
- 屏5「帮我选」与屏2 一句话共用这条规则，不出现两套口径；
  MapKit 区卡的 reason 从「按到所选景点的平均直线距离推荐」改为
  「按酒店供给多少排序」——旧文案与新规则不符，属于说假话。

**验证**

- 离线 `TRIP_INTENT 89/89`（+3：平票取古城区、多数在玉龙县时仍取玉龙县、
  并断言这组点位的平均距离确实偏向玉龙县——即旧口径必错的那条证据）。
- 主/测试 HAP 构建通过，产物已装机。

**边界**

- 真机复跑（丽江预览应显示「住宿区 古城区」）与全量 hypium **未跑**：
  设备再次锁屏（`10106102`），按规矩未解锁、未绕过，等设备空出补验。
- 北京/上海等种子城市走的是同一函数，理论上有回归风险；
  现有 hypium 用例（单目标取最近、档位过滤、空目标退回首位）仍应成立，但需真机确认。

### §5ci 续 62：住宿区排序收成一个函数——列表与预选不再各排一次

**上一版只修了一半**

- 续 61 把预选改成「投票 + 平票按列表顺序」，但复查发现 `StayPickPage.rankByDistance`
  对**所有**片区都按平均距离重排：丽江的屏5 首屏仍会是玉龙县，
  预选说古城区、列表第一名说玉龙县，矛盾照旧。
- 北京 3 天在投票口径下给出 `bja-008 中关村`（它在种子顺序里排第 8，是票数赢的），
  而屏5 列表按距离排的第一名不是它——同一类矛盾在种子城市也出现。

**修法**

- 排序收进一个纯函数 `PlanAutoPick.rankAreas(areas, targets)`，判据按数据源分：
  · **地图区县**＝入参顺序（`buildAreas` 已按酒店供给降序），不再按距离重排——
  住宿库存是我们手上最强的「适合住」信号，丽江实测 467 店 vs 139 店；
  · **种子片区**＝到所选景点的平均直线距离升序，缺坐标的排最后；
  · 没有景点坐标时原样返回，不把「算不出距离」当成「最近」。
- `nearestArea` 退化成 `rankAreas(...)[0]`；屏5 列表、屏5「帮我选」、屏2 预选
  三条路径全部同源，结构上不可能再给出两个第一名。删掉 `StayPickPage.rankByDistance`
  与 `AreaDistance`。
- `verify_trip_intent.sh` 多拷一个 `MapCityMapper.ets`（`PlanAutoPick` 现在 import `isMapArea`）。

**验证**

- 离线 `TRIP_INTENT 91/91`（新增：地图区县按供给不被距离重排、列表第二名仍是玉龙县、
  种子片区按平均距离升序、无景点坐标不重排；并保留「这组点位的平均距离确实偏向玉龙县」
  这条证明旧口径必错的断言）；`MAP_CITY 66/66`。主/测试 HAP 构建通过并已装机。
- 真机锁屏前已确认丽江：`17:37:20 一句话识别 丽江 2天 spots=8 area=mk-area:丽江:古城区`
  （上一版口径；新口径对丽江结果相同——供给第一名就是古城区）。

**待补（设备再次锁屏 `10106102`，未解锁未绕过）**

- 全量 hypium（预期 187 例）。
- 北京 3 天：新口径下预选应变回距离第一名，且与屏5 首卡一致；
  丽江：屏5 首卡应为古城区。

### §5ci 续 63：住宿区一致性真机闭环（丽江 / 北京两种数据源）

**顺手修的假话**

- 续 62 把排序收成一条规则后，屏5 的按钮仍写「帮我选（离景点最近）」，
  而地图城市的判据已经是住宿供给。文案按数据源分开：
  地图城市「帮我选（住得最方便）」、种子城市「帮我选（离景点最近）」，
  toast 前置一句判据（`StayPickPage.autoPickArea`）；`Geo.test.ets` 头注释同步。

**真机验证（Pocket 2，设备解锁后）**

- 丽江 2 天：屏2 预览「按每天 4 站预选 8 个景点 · 住宿区 古城区」；
  屏5 首卡＝古城区（徽标 精选 1、理由「按酒店供给多少排序；住宿档与通勤未校准」）、
  按钮「帮我选（住得最方便）」——**预选与列表同一个第一名**。
- 北京 3 天（种子城市）：预览「住宿区 南锣鼓巷-鼓楼」；屏5 首卡＝南锣鼓巷-鼓楼、
  第二卡 雍和宫-和平里、按钮「帮我选（离景点最近）」。
  上一版投票口径给的是 `bja-008` 中关村（与列表不一致），现已回到同源。
- hypium **187/187**（最终构建上复跑）；十二把尺 0（含 label_fit / a11y / type 复跑）。
- 零 LLM、零数据改动：只跑本机识别 + 路由直达屏5，没有生成行程。

**边界**

- 屏5 列表不按住宿档过滤，屏2 预选会先按 `stayTier` 收候选；
  两者只在「第一片档位不符」时不同——用户偏好优先于排序，不算矛盾。
- md/宽屏档仍未验（模拟器通道未解决）。

### §5ci 续 64：第三城取证抓到单日收口砍反了——改成「装不下就跳过这一站」

**取证（重庆，走城市别名「山城」）**

- 加了轨迹日志后第一次跑：`单日收口 候选4→1 留大足石刻 弃洪崖洞民俗风貌区/磁器口古镇/双江古镇景区
  停留+通勤490min/预算480min 起点渝中区`。
- 首候选大足石刻离渝中区约 120km，单站就吃掉整天预算；而 `pop()` 从尾部砍，
  把三个同城景点全砍光，只剩一个远郊站——**方向正好砍反**。
  一天的行程该是一个片区，不是「全国最出名的那个 POI 在哪就去哪」。

**修法**

- `pickSpotsForSingleDay`：由「超预算就从尾部砍」改成**按优先级逐个试装，
  装不下就跳过这一站继续看下一站**；只有全部装不下时才保留首站。
- `TripInputPage` 新增收口轨迹日志（候选→留/弃/停留+通勤/预算/起点），
  正是这一行把根因从「预算太紧」纠正成「砍错方向」。
  配套公开 `PlanAutoPick.singleDayCandidates` 与 `routeMinutesOf`（纯函数，可离线断言）。

**验证**

- 离线 `TRIP_INTENT 94/94`（+3：重庆形态跳过远郊首站、留 2 个同城站、大足石刻不占名额；
  西安/丽江原有用例结果不变）；hypium **187/187**；十二把尺 0。
- 真机 18:40:28 同一句「山城 1 天」：`候选4→2 留洪崖洞民俗风貌区/磁器口古镇
  弃大足石刻/双江古镇景区 停留+通勤265min/预算480min 起点渝中区`；
  预览「按单日 10 小时窗口预选 2 个景点 · 住宿区 渝中区」。
- 零 LLM、零数据改动（只识别，未生成行程）。

**边界**

- 通勤仍是直线启发式（×1.2 道路系数 / 30km/h + 8min），重庆这类山地城市的实际耗时可能更高；
  预算 480min 是「10h − 两餐」的估算，不是承诺。
- 候选上限仍是节奏档（标准 4），所以重庆是从 4 个里挑 2；用户想加大足石刻要在屏4 手动加，
  那时负载条会照常提醒。

### §5ci 续 65：单日候选池放宽到 2 倍上限（重庆 2 站 → 3 站）

**规则**

- `singleDayCandidates` 取 `max(8, 2×节奏上限)` 个候选（标准档 8、紧凑档 12），
  `pickSpotsForSingleDay` 按优先级逐个试装，**装够节奏上限就停**。
- 为什么不干脆放宽「装几个」：节奏档是用户在屏3b 选的（标准 4 站/天）。
  候选池决定「从哪几个里挑」，不决定「挑几个」——放宽池子是修「挑错人」，
  放宽结果是替用户改节奏。

**验证**

- 离线 `TRIP_INTENT 100/100`（+6：池子取到 8 个、重庆形态挑出 `p2/p3/p5`、
  两个远郊站与武隆都不进单日、标准档 4 站封顶、轻松档 3 站封顶）；
  hypium **187/187**；十二把尺 0。
- 真机 19:56:09 同一句「山城 1 天」：
  `候选8→3 留洪崖洞民俗风貌区/磁器口古镇/罗汉寺
  弃大足石刻/双江古镇景区/黑山谷风景区/重庆丰都鬼城名山景区-黄泉路/濯水古镇景区
  停留+通勤338min/预算480min 起点渝中区`；
  预览「按单日 10 小时窗口预选 3 个景点 · 住宿区 渝中区」。
- 零 LLM、零数据改动。

**边界**

- 338min 没用满 480min：剩下的候选全在远郊（重庆的热门榜混了丰都/武隆/黔江方向），
  不是预算算松了。要那些景点得用户在屏4 自己加，负载条会照常提醒。
- 通勤仍是直线启发式，山地城市的实际耗时可能更高。

### §5ci 续 66：MapKit 取不到数据的出口真机验完，顺手把「10 小时」收成一处

- 之前只验过成功路径（西安 / 丽江 / 北京 / 重庆），**失败出口一次没在真机上走过**。
  想造真失败，先试撤本应用的 `ohos.permission.INTERNET`：
  `atm perm -c -i 537227270 -p ohos.permission.INTERNET` 报
  `Permission 'ohos.permission.INTERNET' is not requested by the application` ——
  它是装期授权（`grantFlag 4` = SYSTEM_GRANT），`atm` 只管用户授权类 ACL，撤不动。
  飞行模式更不行：本机 hdc 就是走 WiFi（`192.168.31.38:46077`），断网等于断自己的手。
- 换**真实数据缺口**当扳机，零成本也不碰设备网络：在屏2「其他城市」输 `雷克雅未克`。
  华为地图国内节点没有这座岛的景点列表，走的是 `MapKitCityStore` 那条真链路。
  实测落点值得记一笔：**屏2 不做联网预检**，输完城市直接放行到下一步，
  失败一律在屏4「选景点」现形 ——
  「地图服务没取到雷克雅未克的景点」/「检查网络后重试，或换一座城市」+ 两个出口
  「重试」`[312,1743][412,1802]`、「换城市」`[700,1743][850,1802]`。
  不崩、不卡转圈、不拿空列表冒充成功。
- 「重试」单独量了一次行为边界而不只是看它存在：点下去 3s 后仍是同一空态（说明请求重新发起了），
  13s 后还是同一空态而不是停在加载壳 —— 按钮是活的，且失败后能落回可操作态。
- 顺带修掉一处会静默漂移的重复：`PlanAutoPick.SINGLE_DAY_WINDOW_MIN` 和
  `DayLoadCalc.WINDOW_MINUTES` 各写了一份 `600`，注释还互相指认「与对方同源」。
  现在 `PlanAutoPick` 直接 `import { DayLoadCalc }`，窗口取 `DayLoadCalc.WINDOW_MINUTES`，
  景点预算写成 `DAY_WINDOW_MIN - MEAL_MINUTES`（120 是两餐，不再手算成 480）。
  改一边不会让另一边失败，所以补了两条离线断言把等式钉住
  （`tools/trip_intent_check.ts` → 100 → **102**）。
  代价是离线取证脚本要多拷三个文件（`DayLoad` / `model/Trip` / `model/Expense`），已加。
- 两处工具与文档的账：`tools/verify_dock_tabs.sh` 里写死的 `DEV=192.168.3.2:46077`
  换成取 `hdc list targets` 首条 + 无设备时明确报错退出（IP 每次重连都变，实测已变成
  `192.168.31.38`，写死只会让脚本静默跑在错目标上）；README 的 186 例 / 离线 86 条
  按这次实跑值改成 187 / 102。
- 门禁（全部本轮实跑）：离线 66 / 102 / 57 / 74+26 / 102 全绿；十二把静态尺 0 偏差；
  `assembleHap` BUILD SUCCESSFUL；真机 hypium **187/187**。
- **仍未验**：屏6 → 屏7 带真错误码的降级链。`aa start --ps route GenerateFailed` 这条直入通道
  只带 `code=0`（`routeTo` 的 param 是行程 id，不是 `FailInfo`），渲染的是兜底文案；
  而屏2 既然不预检，MapKit 失败就到不了屏7，只能停在屏4。
  要拿到真错误码得让生成阶段真的失败一次 —— 那是花模型额度的事，留到下次顺路验。
  `FailureCopy` 两个映射函数本身有 hypium 覆盖（`FailureCopy.test.ets` 4 例全过）。

### §5ci 续 67：顺着「同源」二字扫了一遍，又抓到一处逐字重复的实现

- 续 66 修的那类缺陷（两处各写一个 `600`，注释互相指认「同源」，改一边不会让另一边失败）
  不是孤例，所以按「同源」二字全库 grep 了一遍。`TripSchema` / `TripParser` / `model/Trip`
  那几处是真的共用常量，没问题；**`PlanAutoPick.dailyCap` 和 `LlmClient` 里
  `MockLlmTransport.capOf` 是逐字相同的两份实现**，注释写着「与 LlmClient 的 capOf 同源口径」。
- 危害和 600 那条同型：屏2 按 A 个数预选景点、生成侧按 B 个数排每天，
  用户读到「预选 4 个景点」而实际每天排 3 站，两边都能自圆其说、没有一处会报错。
- 收法：唯一实现挪到 `model/PlanParams.ets` 的 `PaceRule.dailyCap(pace: string)`。
  不放 utils 也不放 ai 是有原因的——`ai/` 侧带 `@kit`，抽进离线取证脚本会直接判死；
  而 `PlanAutoPick` 反向 import `LlmClient` 会成环。`PlanParams` 是两边都已经依赖、
  且已在离线脚本拷贝清单里的唯一落点。`PlanAutoPick.dailyCap` 保留成转发（调用方和
  `TripIntent.test.ets` 4 条断言都不用改），`capOf` 删掉。
- 补 2 条离线断言（`PaceRule` 与 `dailyCap` 同值、空档/未知档按标准 4 兜底）：
  TRIP_INTENT 102 → **104**。

### §5ci 续 68：屏15「今日已打卡」的「进行中」态补上通路——它一直是死分支

- 底稿帧 `屏15_有径-旅行中模式_fc4e40cd` 在这一节排的是**三行两态**：
  `07:40 早餐 已打卡` / `08:30 渡月桥 已打卡` / `09:00 竹林 进行中`，
  后者有独立样式类 `.check-status-ongoing`（时间与标签都 `#0066CC`、不带对勾）。
  渲染侧 `checkRow()` 早就按帧写全了四个 `row.ongoing` 分支，**但数据侧 `buildRows()`
  把 `ongoing` 写死成 `false`**，而且循环开头 `if (marks[st.key] === undefined) continue`
  只放已打卡的行进来 —— 这一态在真机上永远不可能出现。属
  [[feedback-prove-consumption-path]] 说的「界面承诺了但没通路」。
- 修法不是删分支（那是把契约槽位删掉），是**补通路**：
  ① 循环条件放宽成「已打卡 **或** 就是当前这一站」；
  ② `ongoing = !checked && st.key === ongoingKey`；
  ③ 新字段 `ongoingKey` 在 `reload()` 里选好 `curStop` 之后赋，且**只在时刻已到时才记**——
  `cur` 原有一个兜底（`if (cur < 0) cur = 0`）会让"还没到首站"也把第一站当当前节点，
  对 hero 那是「今天先去哪儿」，对列表说「进行中」就是谎话。两件事分开判。
- 真机两档取证（21:14，两条今天有效的行程，都是零打卡）：
  丽江 19 站 → `19:30 返回住宿 进行中`；西安 11 站 → `21:00 返回新城区住宿 进行中`。
  dump 里该行只有三个文本节点（时间/名字/状态），**无金额、无对勾**，与帧一致；
  取「进行中」标签像素得 `(11,134,255)` ≈ 深色档 `primary #0A84FF`（帧的 `#0066CC` 是浅色档）。
  分组头仍写「今日已打卡」——**帧自己就这么标的**，不替帧改文案，
  但这行落在这一节里读起来是"已打卡一节里有一行没打卡"，属帧的措辞松，留给用户定。
- 空态文案没动：`rows.length === 0` 现在只剩「什么都还没开始且没打卡」才出现，
  「今天还没有走过任何节点，打卡后会出现在这里」在这个条件下依然成立。
- **顺带记一条本轮没动的不一致**：同一屏里 hero 的「当前节点」是 `21:00 返回新城区住宿`，
  而上方建议条说的是「秦始皇帝陵博物院还没打卡」——**两个不同节点**。
  前者取「时刻已到的最后一站」，后者取「第一个未打卡站」，各自都自洽，
  但同屏出现两个"当前"用户会读成矛盾。要不要统一（以及往哪边统一）属语义决定，没替用户拍。
- 闸门：十二把静态尺 0 偏差；真机 hypium **187/187**；`assembleHap` BUILD SUCCESSFUL；
  **零 LLM、未写入任何打卡/费用/行程数据**（取证全程只读，没点「完成打卡」）。

### §5ci 续 69：屏15 两个「当前」——先按「欠站赢」统一，被真机否掉，改成两条规则各自命名

- 续 68 记下那条没动的矛盾（hero 的「当前节点」与上方建议条说两个不同站）本轮要收。
  读代码才发现不是一处重复，是**三处两个规则**：
  `current`（时刻已到的最后一站）喂 hero / 进度条 / `next` / 「完成打卡」落点 / 到站订阅；
  `ongoingKey`（同规则）喂「进行中」行；
  `TripSignals.lagStop`（最后一个已打卡之后、第一个已开始且未打卡的站）喂建议条文案与
  「跳过这一站」的 `targetId`。**前两条一条、第三条另一条 —— 后果是同一屏两颗主按钮
  「完成打卡」与「跳过这一站」瞄着两个不同的站。**
- 第一条路（用户选的「欠的那一站赢」）实现完是真跑通的：新增 `utils/NodeOwe.indexOf`
  （欠站规则唯一实现）+ `SignalContext.currentKey` 把节点判定收进页面一处，`lagStop()` 删掉。
  离线 116 例、真机 hypium 188/188、十二把尺 0 偏差。
- **真机一开就否掉了它**（同一条丽江行程、同一时刻、零打卡）：

  | | 改之前 | 欠站赢 |
  |---|---|---|
  | hero | `返回住宿 19:30` | `入住办理与行李安放 10:00` |
  | 建议条 | `比计划晚 624 分钟` + `「丽江古城」还没打卡` | **整条消失** |
  | 进行中行 | `19:30 返回住宿` | `10:00 入住办理` |

  两个原因叠在一起：① **整天一次卡都没打过时，「欠着的那一站」恒等于今天第一站**，
  晚上九点半把 10:00 的入住办理当「当前节点」、还让「完成打卡」去落它，比钟点站没用得多；
  ② hero 落到住宿节点，而 `TripSignals.timeline()` 本来就排除交通与住宿
  （住宿既不能跳过也不是顺延目标），按 key 找不到节点 → 走到「宁可安静」那条分支，建议条整个哑掉。
  顺手还查出一个能力缺口：若为救建议条把住宿从口径里剔掉、hero 也跟着剔，
  **住宿节点就从 屏15 再也打不了卡**（hero 是唯一入口，打卡列表只列已打卡与进行中）。
- 最终形态：**不合并计算，合并命名。** 两个问题两条规则，各自只有一处实现：
  「按钟点我现在该在哪」留在页面那段循环里，喂 hero / 进度条 / `next` / 「完成打卡」/ 到站订阅；
  「哪一站该做而没做」是 `NodeOwe.indexOf`，喂「进行中」行与建议条
  （`SignalContext.currentKey` 传的是 `owedKey`，不是 hero 的键）。
  `oweItemsOf` 排除交通与住宿 —— **住宿不参与"欠"**，所以喂给信号的 key 一定在它自己的口径里，
  不会再触发"安静"分支；hero 仍能落在住宿上，打卡通路没丢。
  `NodeOwe.resolve`（欠站优先、退回钟点）随这条路线作废，已删。
- 真机复拍（21:47，同一条丽江行程）：hero `返回住宿 19:30`、
  建议条 `比计划晚 670 分钟` + `「丽江古城」还没打卡` + `跳过这一站`、
  进行中行 `10:50 丽江古城 进行中`。**建议条与「进行中」行落在同一个站，
  「跳过这一站」的动作也落在那一站**；hero 回到钟点站。
  矛盾消除的方式是"各说各的问题"，不是"强行说同一个答案"。
- 测试面：`NodeOwe` 9 条离线断言（含「已走过的漏站不回头追」「空列表不欠」「陌生 key 不影响」）；
  落后落点回归离线 5 条 + hypium 1 例 `signal_current_node_follows_the_owed_stop`；
  两处 `ctxOf` 改成用 `NodeOwe.indexOf` 反推欠站再喂信号，测试侧不再自己猜节点。
- 闸门：离线 `WEATHER_SIGNALS 116`（102→116）/ `TRIP_INTENT 104` / `MAP_CITY 66` /
  `TRIP_REVIEW 57`；十二把尺 0 偏差；双 HAP BUILD SUCCESSFUL；真机 hypium **188/188**。
  零 LLM。**本轮没写任何打卡/费用数据**（取证全程只读，没点过「完成打卡」）。
- **方法账**：这条弯路值得记 —— 用户选了「欠的那一站赢」之后我按选项实现完、测试全绿，
  但真机一开才发现它在「整天零打卡」这个最常见场景下退化。**只看 hypium 与离线断言就会
  当成已收口提交掉。语义类改动必须拿一帧真屏：绿测试证明的是"实现符合我当时的理解"，
  不是"理解本身对"。** 中途不提交、留在工作树里等复拍，是对的处置。

### §5ci 续 70：屏9 拖拽把手——「缺失」是我记错了，真缺陷是它浅色档只有 2.49:1

- 任务单上写的是「帧声明的六点把手代码里完全没有」。**这是错的**：
  `EditItineraryPage.handle()` 一直在每行最左渲染，`editRow()` 第一行就调它。
  我凭一条旧记忆（「屏9 交通段模式图标与 6 点把手未做」）+ 一次只命中 `dragIdx`
  没命中 `handle` 的 grep 就登记了缺陷，**没读那个行的 builder**。
  与 [[verify-the-scanner-before-trusting-a-zero]] 同族：报"没有"之前要先证明找得到。
- 读到的真缺陷是**颜色**：把手画在 `ColorTokens.faint` 上，而它坐在行卡
  `surface_elevated` 里 —— 浅色档 **#FF9E9EA3 on #FFF7F7F8 = 2.49:1**，
  非文本控件要求 3:1，也就是浅色档下这个把手基本是隐形的（深色档 4.86:1 尚可）。
  而帧 `ebe57eac` 给的 fill 是 `#69696E` —— **正好等于浅色档的 `muted`（5.10:1）**，
  所以这是实现抄错了 token，不是设计取舍。"可发现性为零"的真因是这条，不是缺件。
- 三点收口：
  ① 形状照帧改成 2 列 × 3 行六点（帧 viewBox 24 里 r=2 → 22vp 盒内 4vp 直径，
     行距 2 / 列距 4，行比列紧是帧自己的比例）；
  ② 颜色 `faint` → `muted`（同时修掉 2.49:1 与偏离帧）；
  ③ 整列加 `accessibilityText('长按拖动调整顺序')` —— 命中区收窄不到把手上
  （`onItemDragStart` 只能挂 List 级整行长按），所以它是「这一行可重排」的提示、
  不是「拖我」的靶子，手势本身靠读屏念出来。平台自己的命名空间里就有
  `gridobjectsortcomponent_accessibility_item_long_press_gesture` 这条约定。
- 官方符号表查过了（`ets-loader/sysResource.js`）：**没有六点把手**，
  最接近的 `dot_grid_2x2` 是四个点，所以这六点只能用图元画 —— 不违反「官方组件优先」，
  因为没有官方等价件。
- 真机取证（23:44，西安 8 节点 Day 1）：dump 里每行 6 个 `Circle` 节点，
  x `69–82` / `94–107`、y `719 / 738 / 756`。换算 **点 13px=4.16vp、列间 12px=3.84vp、
  行间 6px=1.92vp**，全部对上；点跨 38px 装在 75px(24vp) 列里两侧各 18.5px = 水平居中，
  把手中心 y=744 对行文字中心 743.5 = 垂直居中。取样点色 `(151,150,156)` ≈ 深色 `muted`，
  **实测点/底对比度 5.75:1，与离线预测 5.74:1 差 0.01**。
  行内其余列没被挤（时间 150–313、节点环 341–410、站名 438 起，与改前一致）——
  登记任务时担心的"加一列会截断"是多余的，那 24vp 本来就在。
- **本轮自己引入又自己抓到的缺陷**：`handle()` 上多了一个重复的 `@Builder`
  （原装饰器在替换范围之外），hvigor 报 `Duplicate '@Builder' decorators for method
  are not allowed` **但退出码仍是 BUILD SUCCESSFUL** —— 只看构建结论会漏掉。
- **未拍**：浅色档那一帧（设备在深色档，钉色档要再走一次临时探针）。
  浅色的 5.10:1 是 `color.json` 真值算的，不是估的。
- 进 屏9 的路本轮补记：深链不行（`asEditTarget` 要 `{tripId, dayIndex}` 对象，
  want 的 string 参数只会落到「没有带进行程」）；两条注入路是「去减一站」（要某天超载）
  与「去添加景点」（要某天空着），丽江三天 8h/7h/6.7h 都不满足，
  顶栏 ⋯ 溢出菜单注入点不开 —— **这次是用户真人点进去的**。
- 闸门：十二把尺 0 偏差（含 `audit_a11y_name` 通过）；双 HAP BUILD SUCCESSFUL；
  真机 hypium **188/188**；`modules.abc` 里 `grep -a` 到「长按拖动调整顺序」反证产物含改动。
  零 LLM、未写任何行程/打卡数据。

### §5ci 续 71：dock 四格 → 五格，导航真值表收成一处

- 用户提的分工：**地图**（地图 + 进行中的行程）· **行程**（历史/最近 + 编辑）·
  **规划**（主功能）· **费用** · **我的**（勋章卡 + 设置 + 个人信息）。
  现状对不上的地方比预想严重：`TripsPage`（历史列表）一直挂在**「我的」页签**上，
  用户要看自己的行程得点「我的」；「规划」在 dock 上根本没有位置；
  地图跟的是"最后打开的那条"而不是"进行中的那条"。
- **先纠正三条直觉**：
  ① **「有据」没有可同步的头像。** 它的头像来自自己后端的 COS URL（`user.avatar`，
  选图→压缩→直传→回写），全工程 `avatarUri|getAvatar` 零命中；而有径 Account Kit 走
  `authentication` 直取 `unionID`，`LoginWithHuaweiIDCredential` 的字段只有
  `authorizationCode/idToken/openID/unionID`，**响应体不含昵称与头像**。
  要拿必须换 `AuthorizationWithHuaweiIDRequest` + `scopes:['profile']`，那会弹系统授权框、
  破坏现在的静默登录。所以本轮放占位，但**留了接缝**（见下）。
  ② **设计契约从没钉格数。** `Docs/design-v1/DESIGN.md`（不是 `docs/`；
  【括注 2026-11-02】此处是**历史路径**：契约 v2 起该目录冻结为 v1 原文，
  现行镜像是 `Docs/design-v2/DESIGN.md`，见 §5ci 续 84 版本路标 —— 本轮"契约没钉格数"这条结论不动）只钉几何：
  `floating-dock-width 300px`(:234/363)、`tab_item_width 58`(:266)、`nav-label` 10/400(:169/916)、
  `300×64`(:1094)。13 帧底稿画的是 4 格，那是视觉参照不是数字约束 —— 加第 5 格不违反契约。
  ③ **300vp 装 5 格不用加宽 dock。** `Index` 的 builder 只钉 `.height(tabItemHeight=50)`，
  格宽是 bar 均分的结果。真机实测五格格心间距 **190px = 60.8vp**（预测 60vp），
  label 宽 63px = 20.2vp 两字 CJK，无截断；`floatingDockClearance=112` 由 dock 高度决定、
  **与格数无关**，17 个用它的屏一行不用动。
- **计划里有一步站不住，当场改了**：原计划 Step 1「加第 5 格」与 Step 2「重排编号」
  分不开 —— 加完第 5 格会有两格都叫「我的」，只改编号会把深链指错 tab，
  中间态必然是坏的。合并成一个原子步做完。
- **真值表收口**：`DOCK_TABS`（label + symbol）从 `Index:43-48` 搬进 `common/constants/AppNav.ets`，
  与 `TAB_*` 序号、`stackOfTab`、`tabOfRoute`、`stackOfRoute` 同处一文件。
  之前这四张表分写两处，四格改五格要同步改五处，漏一处不崩、只静默错位。
  `$r()` 在 `common/` 做模块级常量此前无先例（`HdsChrome` 的模式是"共享层声明 `Resource`
  类型、页面传 `$r`"），实测可编译，且 `AppNav` 本就引用 `NavPathStack` 这类 ArkUI 类型。
- **`MINE_NAV` 改名 `TRIPS_NAV`**：它以前挂「我的」页签，现在服务「行程」页签。
  留着会指反义 —— 这正是我否掉「只追加第 5 格、0-3 保号」那个方案的理由，
  不能自己犯自己批评过的错。只有 3 处代码引用 + 2 处注释。
- **深链这条是真改了机制，不是搬个号**：`EntryAbility.routeTo` 原来写
  `if (tab === TAB_ITINERARY) push` —— 那是四栈时代"只有 tab 0 的栈首帧就建好"的将就。
  重排后规划链在 2 号，照抄就会把页面 push 进**还没绑 Navigation 的栈**（§4k ④ 实测过：
  routerMap 收到空名）。改法是把初始页签**提前到 `applyWant` 写**：`onCreate` 早于
  `onWindowStageCreate` 的 `loadContent`，所以 `Index` 的 `@StorageLink wantTab` 初值
  就是目标页签，那个 TabContent 属于首帧就建的那一个。
  判据同时换成 `isTabRoot(name)`（是不是页签根页）而不是"属于哪个页签"。
  **真机三条冷启逐一验通**：`route=Itinerary` → 屏8「丽江 · 3天2晚」；
  `route=Badges` → 「我的勋章 / 已收集 3 枚」（这条最关键，它要 push 进「我的」那条懒建栈）；
  `route=TripInput` → 屏2「第 1 / 5 步 · 基础信息」。
- **新 `MinePage`（第五格）**：`rootMode` 双分支照 `TripsPage`；块序 = 个人信息区 →
  勋章卡 → 设置区（隐私政策/用户协议/关于，就地展开 `LegalDocReader`，不 push 路由）→
  退出登录。真机读到真数据：脱敏 ID `AABKND***`、「已收 3 枚勋章」、「走过 1 座城市」。
- **头像接缝（用户说"后续肯定要做，现在先放放"）**：`MinePage` 不写死 `SymbolGlyph`，
  改问 `data/ProfileStore.avatarOf(uid): AvatarSpec`（`kind: 'symbol' | 'image'`）。
  本轮恒返回 symbol 占位，但 `image` 分支的渲染代码这轮就在、只是永不命中；
  `displayName()` / `displayHint()` 同样收在这层。将来接真头像就是
  **改 `avatarOf()` 的返回值 + 加一个写入点**，页面结构与 UI 一行不动。
  两条实现路（profile scope 弹窗 vs 接服务端存 URL）都不是现在该拍的，只留出口不留决定。
- **三把尺各抓到一条我自己写进新文件的缺陷**（这就是它们存在的意义）：
  `audit_fontfamily` 抓到 ID 用了 serif 档 `title` 却没带 `.fontFamily` → 改成 sans 的
  `headline`（脱敏 ID 是操作型文本，契约里 serif 只给编辑性标题）；
  `audit_geometry` 抓到 `Column({ space: 2 })` 落在 4vp 基线网格外 → 换 `SpaceTokens.xs`；
  `audit_layout_patterns` R5 抓到「退出登录」同屏三份 → 弹窗标题改问句。
- **一条差点照方案加错的代码**：Plan agent 判「`SharePage` 缺 `onReady`，
  从行程/我的 push 会落回不可见的 APP_NAV」。读文件才发现 **`SharePage` 里没有任何
  `pushPath`/`pop`/`pathStack`**，返回全靠 `HdsNavDestination` 自带的系统返回 —— 没有东西可修。
  按 [[dont-register-a-defect-from-a-grep-miss]] 同一课：**转述的结论也要自己读到代码才算数。**
- **闸门**：十二把静态尺 0 偏差；双 HAP BUILD SUCCESSFUL；
  真机 hypium **191/191**（188 → 191，`NavStackRouting` 由 4 例扩到 7 例，
  新增「五个序号互不相同且铺满 0..4」与 `stackOfTab(tabOfRoute(n)) === stackOfRoute(n)`
  不变量断言 —— 后者是重编号错位的唯一程序化闸门）。零 LLM、未动任何行程数据。
- **本批未做（继续推进中）**：Step 3 规划 tab 瘦身（`YoujingStartPage:357-438` 的最近行程块
  与「行程」格现在重复展示）、Step 4 地图改吃"进行中行程"（`utils/TripWindow.isActiveOn`
  收掉 `YoujingStartPage:86` 与 `TripsPage:82` 两处内联谓词）、DESIGN.md 补格数、README 计数。

### §5ci 续 72：地图格改吃「在途行程」，`DESIGN.md` 一份都没动

- 新增 `utils/TripWindow.isActiveOn(start, end, today)`，把 `YoujingStartPage:93`
  与 `TripsPage:88` 两处内联的 `today >= start && today <= end` 收成一处 ——
  地图格要吃"进行中"就是第三份要出现的时候，先收再写。
  注释里搬过来一条重要口径：**不能用 `spanDays` 的差值判在途**，它含首尾且下限为 1，
  会把还没出发的未来行程算成旅行中（`TripsPage` 原注释记的）。
- `MapPage` 根页不再读 `activeTripId()`：那个键的语义是"最后打开的那条"，
  点开一条历史行程去编辑、切回地图就跟着变成那条历史行程 —— 而这一格承诺的是
  "看我现在走到哪"。`ACTIVE_TRIP_KEY` 现在**只服费用页**（记账跟着刚看的那条走才对）。
  改成 `resolveAndReload()`：`listSummaries` → 取首条 `isActiveOn` → 展示；
  一条都没有就出空态。push 形态（带 tripId）不受影响。
- 两个新状态位而不是复用 `loaded`：`noOnTrip`（今天没有在途）与 `onTripShown`
  （当前展示的就是在途那条，决定标题栏给不给「旅行中」入口）。
  "没有在途"和"还没加载完"不是一回事，共用一个标志位会让空态在加载瞬间闪出来。
- 自动停在**今天那一天**而不是「全程」：`applySel` 前先在 `trip.days` 里找 `date === today`。
  19 个落点缩在一张全程视图里反而看不清，而开地图的问题通常是"我现在在哪一段"。
- 空态用官方 `Button` 而不是 `Text.onClick` —— 后者会被第 8 把尺 R4 判成自绘按钮。
  落点 `enterPlanningFlow('TripInput')`（它会 `requestTab(TAB_PLAN)` 再 push，跨页签一条路）。
- **`DESIGN.md` 两份都没改**（计划里原写"补一句格数"）。核实过才发现
  `Docs/design-v1/DESIGN.md` 与 `~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md` 是
  **同一份文件的两个副本（md5 一致）**，而 `audit_colors.py` 读的是 `~/Pictures` 那份 ——
  后者是用户的设计定稿、不可为过闸而改。契约里 dock 只钉几何
  （`floating-dock-width 300px`、`300×64`、`tab_item_width 58`、`nav-label` 10/400），
  **从没钉格数**，而这次几何一个都没变。为一条契约本来不带的信息去改其中一份副本，
  只会让两份"权威契约"互相漂移 —— 正是本晚一直在消的那类缺陷（两处各写 600、两份 3/4/6）。
  计划里那条"同步 DESIGN.md 格数"因此作废。
  【括注 2026-11-02，只标路径不改这段记录】这里的 `Docs/design-v1/DESIGN.md` 现在是**历史路径**：
  契约 v2 起 `design-v1/` 冻结为 v1 原文、`~/Pictures` 那份跟着 v2，两者不再同 md5，
  现行镜像改由 `Docs/design-v2/DESIGN.md` 承担（见 §5ci 续 84 版本路标）。
  上面"两份副本 md5 一致、所以一份没改"是**当时的实测事实**，原文一字不回写。】
- 真机取证（11-01，丽江那条 10-31–11-02 仍在区间内）：进「地图」格标题
  `丽江 · 3天2晚`，站点条是 `束河古镇 09:00–10:30` / `白沙古镇与午餐 11:30–13:00`
  —— 不是 Day 1 的入住办理与丽江古城，说明自动选到了 Day 2。
- 闸门：十二把尺 0 偏差；双 HAP BUILD SUCCESSFUL；真机 hypium **191/191**。零 LLM、未动数据。
- **Step 3 刻意推后**：规划格摘「最近行程」等于重做 App 第一屏，
  和导航重构混在一起出问题时归不了因；单独一轮带前后对比拍再做。
  另外 `recent` 那个状态现在还兼着"本机有没有行程"的判据（`:296` 的预览卡分支），
  摘列表不能顺手删状态，得先想清楚空态判据换用什么。

### §5ci 续 73：Step 3 落地——规划格回到纯门面，顺手抓出一条 ¥0 死页

- `YoujingStartPage` 删掉「最近行程」整块（列表 + 「查看全部 N 条」）。它当初是为
  "行程 tab 看不到自己的行程"打的补丁，五格落地后补丁要拆掉，否则两格各有一份历史行程。
- **预览卡改成常驻，没有按计划换成 `tripTotal === 0`**。原收起理由写在注释里：
  "一张编出来的京都动线吃掉六成屏高，真数据只剩半屏"——那是**同一屏里两件事在抢高度**。
  列表搬走之后这个约束不存在了，再按"有没有行程"收起，老用户的规划格就只剩
  品牌 + 一颗按钮的空半屏。于是这一格**彻底不读行程数据**：`RecentRow` 接口、
  `recent`/`tripTotal` 状态、`reloadRecent()`、`dockTick` 的 `@Watch` 全部删除，
  规划格因此也没有"切回要重取"一说（另外四格照旧）。
- `TripsPage` 转「行程」格：标题 `我的行程`→`行程`（"我的"现在是另一格的名字），
  标题栏菜单去掉「我的勋章」「退出登录」，只留 ＋新建行程 —— 这两件在 `MinePage`
  已各有一份，`confirmLogout` 当时是**逐字两份**，删掉行程页那份而不是留两份互相漂移。
  连带三处文案改名：`LegalDocs` 的「在「我的行程」左滑即可删除」、
  `EditItineraryPage` 的「从「我的行程」里选一条」、`FlowSteps` 注释。
- 在途谓词的第三份收口：`TripsPage:88` 的内联比较改走 `TripWindow.isActiveOn`
  （`YoujingStartPage` 那份随列表一起没了）。现在全仓只有 `TripWindow` 一处写这条规则。
- **走查第 5 步抓到的真缺陷**：费用格显示 `预算 ¥0 · 0 人 · 0 天` 且**再等也不刷新**。
  根因不是 Step 3 —— 是 `ACTIVE_TRIP_KEY` 可以指向一条本机已不存在的行程：
  删行程时没人清这个键，桌面卡片也可能带着旧 id 深链进来。`loadTrip` 返回 null 后
  原代码只 `return []`，页面就停在初始 0 值上，没有任何出口。两处收口：
  ① 源头 `doDelete` 删的正是当前上下文就把键清空；② 消费方 null 分支丢掉 id 退回
  「无上下文」分支（它会自己找最近一条或给规划入口）。②带一次性标志 `contextRetried`：
  无上下文分支挑的是 `listSummaries` 第一条，那条要也取不到就是数据自身坏了，
  再退一次就是异步自循环。真机复验：`--ps route Expense --ps param trip-does-not-exist`
  现在落 `丽江 · 2026-10-31 – 2026-11-02 / 预算 ¥3,500`。
- **闸门脚本自己也是个坑**：step 3/5 深链硬编码 `trip-1792912362551`，这条行程早被删了，
  而 `grep "Day 1"` 在空壳页上照样命中 —— 一条一直"通过"的断言其实在测病态数据。
  改成不带 param（走 `ItineraryPage` 退最近那条真路），并加断言：出现
  「这一天还没有安排节点」就是上下文没退到真行程。
- 真机取证（11-01，五格走查全过、无 `!!`）：规划格 `有径 / 开始规划新行程 / Day 1 · 京都 东山步道 · 规划预览`；
  行程格 `行程 · 15 条` + 丽江(旅行中)/西安(未出发)/西安(已结束)；我的格身份区 + 勋章卡 + 设置三项；
  三条冷启深链落点正确；二次深链费用格有真金额。
- 对比度：`行程`/`费用`/`我的` 三格 0 处；`规划` 格 dock 选中标签 4.44、`地图` 格三个未选中标签
  4.34/4.43/4.49 —— 都是悬浮 dock 的玻璃材质压在**地图影像**上，`primary #0A84FF` 压在
  `canvas #121212` 精算是 **5.13:1**，偏差来自材质白叠加。这条先前就有、不在本轮口径内，
  记为观察项。
- 闸门：十二把尺退出码全 0；双 HAP BUILD SUCCESSFUL；真机 hypium **191/191**；
  离线五套 66/104/57/74+26/116 全绿。零 LLM、未动用户行程与打卡数据。

### §5ci 续 74：每屏上下两条黑边——是窗口背景，不是布局

用户报"所有界面屏幕上下都有黑边"。取证过程先否掉两个错判：

- **旧帧不能当对照**。手边最早的"无黑边"深色帧（`m1.jpeg` 等）其实是**有据**的界面
  （圈子/发布/消息那套五格），而有径存活的旧深色帧一份都没有——浅色帧的 255
  既可能是"画到 y=0"也可能是"白条压白条"，两种解释分不开。
  拿它当基线就会把一条一直存在的缺陷读成"今晚改坏的"。
- **探针要先按 bounds 校准**。第一版探针找"第一个非纯黑行"，结果状态栏图标
  （y≈40）就先命中，量到的是图标行不是带区；改成逐行**中位数**（图标只占几个像素，
  压不动中位数）才读出真值：顶部 0..105px = 纯 0，y≥110 = 18（`#121212` 画布）。

真值表（`uitest dumpLayout` 的 bounds，非像素推断）：

| 节点 | bounds | 含义 |
|---|---|---|
| `root` | `[0,106][1136,2690]` | 窗口内容顶到 y=106，**底部铺到物理屏 2690** |
| 页面 `Column` | `[0,106][1136,2603]` | 页面自己的容器止于 2603 |
| dock 层 `Stack` | `[0,2340][1136,2690]` | 悬浮 dock 那一层是满到屏底的 |

所以两条带区不是一回事：
**顶部 106px（33.9vp）在窗口之外**，由系统按 `statusBarColor` 画，没设过就是纯黑；
**底部 2603..2690（27.8vp）在窗口之内**，露的是**窗口背景色**，默认也是纯黑。
浅色档画布 `#FFFFFF` 与默认白条同色，所以这条缺陷只在深色档暴露——
不是回归，是从一开始就在，只是浅色档把它藏住了。

- 修法只改底色不改布局。契约 §4 明写「**状态栏不许玻璃化**，`.status-bar` 是设备 chrome」、
  §1000「status-bar inset is added here and nowhere else」——有径的设计意图就是内容让位、
  不铺进状态栏。所以不走同族工程那套 `setWindowLayoutFullScreen(true)`
  （那条路要每页自己让出状态栏高度，是一整轮改动），只把两条带区涂成画布色：
  `setWindowSystemBarProperties({ statusBarColor, navigationBarColor })` + `setWindowBackgroundColor`。
  后者是必需的：`navigationBarColor` 在手势导航下不生效（官方论坛确认，同族工程实测过），
  该区域透传窗口背景色。
- 色值不硬编码，走 `resourceManager.getColorSync($r('app.color.canvas').id)`
  按**当前生效配置**解 —— 与 `seedDarkMode` 同一手法，深浅两档一次实现覆盖，
  不新增一份"两处各写 121212"的同源缺陷。
- 三个调用点：`loadContent` 回调内（`getMainWindowSync` 在回调前会抛 1300002，
  同族工程踩过）、首帧后 3s 补设一次（HDS 标题栏挂载期会回写系统栏属性把首帧盖掉）、
  `onConfigurationUpdate` 与 `onForeground` 各重设一次。
- 真机复验（深色档，逐行中位数）：五格顶部 y=0/30/60/90/100 全部 = 18，
  与画布参照 y=200 完全一致；屏15 push 页同样到 18（y≥110 转 0 是满铺地图本身）。
  底部 2603 以下读到 7→10 的渐变而不是 18，那是 dock 的 **92px 渐隐遮罩**（契约 §1055
  "a 92px gradient mask fading content into the bar"）压在画布上，属设计内渲染，不是带区。
- **未验的边界**：浅色档没实拍复验——本机没有 `settings` 命令可切系统深浅，
  而把用户的手机翻成浅色是一次他设备上的可见改动（`darkprobe` 当初就是为此加的，
  且只有深色向）。这条走的是同一条资源解析路径，逻辑上两档对称，但**结论是推的、不是量的**。
- 闸门：十二把尺退出码全 0；双 HAP BUILD SUCCESSFUL；真机 hypium **191/191**。零 LLM、未动数据。

### §5ci 续 75：续 74 只治了色，用户要的是布局——窗口铺满物理屏 + 壳层让位

用户看完续 74 的答复：「直接修根源，从布局下手修，你观察真机也可以发现，每个页面的内容区
无法全部显示在屏幕上，上下会被截断。」这句是对的，续 74 把带区涂成画布色只是让缺陷**看不见**，
缺陷本身是**内容区比屏幕小**。

量出来的账（`uitest dumpLayout` bounds，密度 3.125）：

| 节点 | 改前 | 改后 |
|---|---|---|
| `root` | `[0,106][1136,2690]` | 同 |
| `TabContent`（页面容器） | `[0,106][1136,2603]` = **799.0vp** | `[0,106][1136,2690]` = **826.9vp** |
| `TabBar`（dock） | `2340..2515` | `2427..2602` |
| 物理屏 | 2690px = 860.8vp | 同 |

顶部 33.9vp 压根不在 App 窗口里（非全屏布局，窗口被系统按避让区裁掉），
底部 27.8vp 在窗口里但页面容器进不去。再减掉给悬浮 dock 让的 112vp，
一屏 860.8vp 实际能放内容 687vp —— 用户读到的就是"显示不全、上下截断"。

- **中间踩了一脚，而且只有眼睛能看见**：只加 `setWindowLayoutFullScreen(true)` 之后，
  每一屏顶部反而**被裁得更狠**——规划格「有径」的框从 `[50,118][250,262]`（144px）
  变成 `[50,106][250,156]`（50px）。机制：窗口一铺满，页面就从**窗口 y=0** 起排，
  而 `TabContent` 仍按安全区在 106px 处 `clip=true` 裁切，顶部 106px 直接切掉。
  这一步十二把尺全 0、hypium 191 全绿、离线五套全绿 —— **一条都没抓到**。
  是同机位复拍看见标题被削了一半才发现的。（同族工程注释里早写了这条，
  "否则全屏下标题会被状态栏区域盖住"，先读文档可以省掉这一轮。）
- 修法是把让位收在**壳层一处**：`Index` 的 `HdsTabs` 加 `.padding({ top: statusBarHeight })`。
  加在 `HdsTabs` 而不是壳层 `Column` 上——登录/同意闸门那两屏自己用
  `expandSafeArea([SYSTEM],[TOP,BOTTOM])` 铺到物理屏顶，被壳层垫一下就退回去了。
  这样 20 个页面一行不用改。
- 避让区高度由 `EntryAbility` 发布（`statusBarHeight` / `navIndicatorHeight` 两份 vp，
  px÷`display.getDefaultDisplaySync().densityPixels`，Ability 侧没有 `UIContext.px2vp`）。
  **顺序有讲究**：`getMainWindow()` 是异步的，所以 `publishAvoidArea` 必须在
  `setWindowLayoutFullScreen(true)` **之前**，并且 `loadContent` 回调里再用同步句柄补发布一次
  ——回调之前 `getMainWindowSync` 抛 1300002，而首次 build 可能早于 Promise 落地。
- dock 与页面的相对关系**没变**：改前 dock 顶到页面底 = 2603−2340 = 263px = 84.2vp，
  改后 = 2690−2427 = 263px = 84.2vp。所以 19 个文件里的 `floatingDockClearance: 112`
  仍然正好够用，不需要跟着改（这是"能不能只动壳层"的判据，不是猜的）。
- 真机复验（深色档，逐屏 bounds + 逐行中位数）：五格 `TabContent` 全部到 2690；
  规划「有径」回到 `[50,117][250,261]`（144px 完整）；屏15 标题 `进行中 · Day 2`、
  屏2 `有径` top=233、勋章墙 `我的勋章` top=233 —— 全部 ≥117，无一顶到 106 裁切线；
  y=0/60 亮度 = 18（画布），上下都不再有色带。
- 对比度顺带变好：规划格 dock 选中标签从 4.44 退场（dock 落到新背景上），
  规划/行程/我的/屏2 四屏各 0 处低于阈值。
- 闸门：十二把尺退出码全 0；离线五套全绿；双 HAP BUILD SUCCESSFUL；真机 hypium **191/191**；
  五格走查 + 三条冷启深链无 `!!`。零 LLM、未动行程/打卡数据。
- **未验边界**：① 浅色档没实拍（本机无 `settings` 可切系统深浅，翻用户手机是有改动作）；
  ② 折叠屏展开态（md/707vp）没量——壳层让位读的是实时避让区，理论上跟着走，但没量过；
  ③ `bindSheet` 类半模态在窗口铺满后的高度未逐张复核。

### §5ci 续 76：全路由诊断扫出 3 条，其中一条是我上一条留下的回归

诊断口径：`uitest dumpLayout` 的 bounds + 逐行中位数，19 个路由逐屏量；
另跑一遍"甩到真·底部再量"（判据 = 再甩 6 次几何不变）。跳过 `Generating`：
它 `aboutToAppear` 直接打真 LLM，几何探针不该花钱。**零 LLM。**

已当场修掉两条：

1. **上一条（`2c25ad7`）留下的回归**：`barBottomMargin` 是从**容器底**量的，
   窗口一铺满物理屏，容器底就变成物理屏底，dock 因此从契约钉的
   「28px above the system nav inset」掉到指示条上沿（实测掉 27.8vp）。
   改成 `floatingDockBottomMargin + navIndicatorHeight` 后 dock 回到
   `[55,2340][1081,2515]`，且 **dock 顶到容器底 = 112.0vp**，
   与 `floatingDockClearance: 112` 精确对上 —— 说明这个 token 本来就是按契约位算的。
2. **地图格空态药丸零净空**（`MapPage:351-376`，我 2eee85f 加的那颗
   「今天没有在途行程 · 去规划一趟」）：它和站点条同在 `Stack({alignContent: Bottom})` 里，
   站点条分支 `:343` 有 112 净空、这两个分支没有 → 整颗坐在 dock 带里。补同一 token。
   **这条状态今天量不到**（丽江在途），是按同函数兄弟分支的已验证形态对齐的。

扫出来但**没动**的，按严重度：

- **行程格滚到底，末张卡有 48.3vp 压在 dock 底下**（末卡底 797.1vp vs dock 顶 748.8vp，
  含「已结束·100%」「总花费 ¥1,540」和进度条）。`TripsPage:478` 写的是
  `List.padding({bottom: 112})`，**实测只生效 63.7vp**。同一个写法在
  Share（净空正好 112.0）/Itinerary（131.8）/SpotPick·StayPick·TripInput（124.5）
  都够，所以不是全局问题，是这一页的 `Refresh` + `.lanes()` 组合下的事，机制未定。
  修法待试 `List.contentEndOffset()`（SDK `list.d.ts:1090`，API 11+，专管末尾可滚延伸）。
  ⚠ **第 8 把尺 R1「钉底层未让位 dock」对这条报 0** —— 它只看代码里有没有那个 token，
  不看滚到底是否真让开。静态尺在这一类上给的是假安心。
- **规划格无 Scroll 兜底**：实测内容底到 1997px，离 dock 顶还有 110vp 余量，
  今天不溢出；但它是全仓唯一"根 Column + `height('100%')` + 零 `Scroll/List`"的屏，
  预览卡再加一行或 `meta` 折三行就会顶穿，而顶穿的正是主 CTA 那一段。
- **钉底条余量为零**：`PreferenceQAPage:198-230` 三颗按钮 96+80+120 实测右缘 348.2vp、
  内容盒右缘 347.5vp —— `Blank` 已塌到 0，**没有任何余量**。
  （子代理按"3 个间隙"算出 364>363.5 说主键被顶出屏幕，实测是 2 个间隙、352，
  结论错，但"余量 0"这件事是真的：`:221` 注释里那次 150→120 已经花光了全部富余。）
- **三个底部预留 token 里两个是僵尸**：`LayoutTokens.safeAreaFallback: 12`、
  `SpaceTokens.bottomReserve: 94` 全仓 0 消费（正主是 `bottomScrollReserve: 94`）；
  另外 `LayoutTokens` 有 28 个字段查不到 `LayoutTokens.<字段>` 形式的消费方，
  含 `floatingDockWidth`/`titleBarHeight`/`segmentedControlHeight` —— 契约钉的数
  在 token 里躺着没人用，页面用的是字面量（`Index` 的 dock 宽写死 300、三处 `barHeight: 64`）。

闸门：十二把尺退出码全 0；真机 hypium **191/191**；双 HAP BUILD SUCCESSFUL。

### §5ci 续 77：立了第 14 把尺（真机滚到底净空），它抓到的那条我没敢瞎修

补的就是续 76 点出的那个缺口 —— "padding 写了 ≠ 净空生效"，静态尺看不见这一类。
新尺 [tools/verify_scroll_clearance.py](../tools/verify_scroll_clearance.py)：
逐屏进屏 → 反复甩到"连续 3 次末边同值且至少甩 6 次" → 拿**本次 dump 实测的 dock 顶**
与末边比。不写死像素、点 dock 前重新 dump 取中心（dock 位置这轮改过两次，写死 y 会点到外面）。

**先按 [[verify-the-scanner-before-trusting-a-zero]] 自证它抓得到阳性**，过程里尺子自己错了两次：

1. 第一版把所有节点取 max，根容器/Column 这些铺满整屏的框先命中，
   每屏末边都读成 860.8vp、净空一律 −112.0vp —— **尺子自己造出 112vp 假遮挡**。
   限定"只取有文字的节点 + ListItem 这一级"后才对。
2. 稳定判据太松（只比两次），在行程格停在半路，把 797.1 读成 860.8。
   改成"连续 3 次同值 + 至少 6 次"。
3. 另外它要求"上一轮刚好停在有径上"才肯跑，装机后前台是 launcher 就误判成"人在用手机"。
   改成尺子自己 `aa start` 再断言，且断言前先删本地旧 dump —— 否则 recv 失败会拿
   上一轮的证据放行，那道保护就形同虚设。

校准结果：新尺对行程格读 **797.1vp / 净空 −48.3vp**，与手动量（30 次甩动 + 再甩 6 次不变）
完全一致。全量 17 屏基线：

| 净空 | 屏 |
|---|---|
| **−48.3vp（遮挡）** | 行程 |
| 0.0vp（贴平） | Itinerary、Share |
| 12.2–12.5vp | 地图、屏2、屏3、屏4、屏5、屏7 |
| 173–395vp | AreaMore、Badges、EditItinerary、OnTrip、Review、我的、费用、规划 |

**试修没成，撤了。** 换 `List.contentEndOffset(112)`（SDK `list.d.ts:1090`）后
读数**一点没动**，还是 797.1 —— 而产物自证 `contentEndOffset` 确实在 `modules.abc` 里
（不是 hvigor 复用旧产物的假象）。两种机制量出同一个 63.7vp 残差，
说明这段缺口不是 `padding.bottom` 也不是 `contentEndOffset` 给的，**机制未定**。
按 [[verify-batch-edits-by-measuring]] "数值没动就回退、别叠第三种猜测"，
把改动回退成原样，只在原处留一条写明"这条 padding 只生效 63.7vp、
换 contentEndOffset 同样是 63.7、机制未定"的注释，不留带错误结论的死代码。

肉眼可证的后果（`/tmp/now.jpeg`）：行程格滚到真底部后，末张卡的
「已结束 · 100%」「总花费 ¥1,540」和进度条整段在玻璃 dock 底下，滚不出来。

闸门：静态十二把尺退出码全 0；HAP BUILD SUCCESSFUL；零 LLM、未动行程/打卡数据。
README 质量闸门表加了这一行，状态如实写"1 屏遮挡、未修"。

### §5ci 续 78：顶边色差——三条路都试了，只有"同一个 token 涂两处"成立

用户报"布局问题还是没解决，屏幕顶部栏有色差"。先把色差量准：

| 屏 | 顶边逐行中位（px） | 读法 |
|---|---|---|
| 地图格（改前） | 0..340 = 18，390 起 62~75 | 顶部 **112vp 是一整块画布**（系统带 + 透明栏露出的壳层画布），不是安全区那条线 |
| 四格纯色页 | 全 18 | 本来就没缝 —— 它们的顶边就是画布 |

所以色差不是"带子涂错了"，是**画布块压在底图块上**。上一轮我把 `statusBarColor` 涂成画布，
对四格是对的，对地图格等于把缝从 y=106 挪到了 y=390。

**三条路逐个试，两条被否：**

1. **B2（我上一条提的"让栏的渐隐遮罩往上盖住带子"）机制不存在。** SDK 里
   `HdsNavigationBackgroundStyle` 只有 `backgroundColor` / `maskExtraHeight` / `blurRadius`
   三个字段，而 `maskExtraHeight` 的定义是"遮罩高 = 栏高 + 它"，**只往下长**
   （dump 印证：`Mask` 是 33.9..121.9vp，栏底之下）。栏之上那条带子是系统画的平色，没有渐变旋钮。
2. **`fullBleed: true` 能满铺，但会把栏内两行翻转。** 真机量：改后分段在
   `33.9..77.8vp`、标题在 `71.0..101.4vp` —— 分段跑到标题上面，违反契约 §1055
   「Line 1 品牌块 / Line 2 分段」。而且它没解决带子：底图仍从 106px 起，带子还是画布。
   撤。
3. **给栏体涂色（新加 `barBackground` 旋钮）不生效。** 栏是透明的，
   `backgroundColor` 给了也不画 —— 透过栏露出来的是**壳层 Column** 的底色。撤掉这个旋钮，
   不留没用的配置。

**成立的做法：一个 token 涂两处。** 新增颜色 `map_strip_base`（深色 `#2A3A53` ——
实测底图区众数，占 48.5%；浅色 `#FFFFFF` 与现状一致），由新 util
[utils/TopStrip.ets](../tools/../entry/src/main/ets/utils/TopStrip.ets) 单点决定"现在该用哪个色"：
AppStorage 里只存**资源名**，色值用 `getColorByNameSync` 按当前生效配置现解
（与 `seedDarkMode` 同一手法，不写死第二份 2A3A53）。同一个名字喂给两处：

- 系统带 → `setWindowBackgroundColor` + `statusBarColor`（`EntryAbility.applySystemBarSurface` 改走 TopStrip）；
- **壳层 Column 的 `backgroundColor`** → 这才是透过透明栏露出来的那一层，也是 112vp 画布块的真正来源。

切换点收在 `Index.syncTopStrip(index)`：地图格给 `map_strip_base`，其余四格给 `canvas`。

**结果（真机逐行中位）**：地图格 `0/60/104/110/200/340` 全是 56，一路连续到 390px 之后的
底图内容；四格仍全 18；地图→行程→回地图，带子跟着 56↔18 正确切换。栏内两行次序保持
标题在上、分段在下。

**屏15 没纳入，而且这是这套办法的边界**：它顶边实测是 **0（近黑）**，不是地图格那种 56。
一个静态 token 配不了两种顶边 —— 先按 `STRIP_MAP` 给它涂 56，色差从 `18→0`（Δ18）
变成 `56→0`（Δ56），**比不改更差**。所以撤掉屏15 的声明，只留注释写明原因。
上一轮我反对 B1 时说的那句"涂色只能涂静态值"，这次被自己的数据证实了。
屏15 要真修只能走底图铺进带子（即被否的 fullBleed 那条），得先解决栏内两行翻转。

**顺带补上了一条一直挂在"未验"清单上的洞**：跑完后设备自己切到了浅色档
（hilog `isDarkMode=false（config.colorMode=1）`），正好量到浅色五格：
顶边 `0/60/104/110/200/340px` 全是 255（浅色画布），最大跳变出现在 440px 之后，
那是蓝色主按钮（规划 83）与白昼底图（地图 234），不是缝。
所以**浅色档这条从"推的"变成"量的"** —— 前三轮一直只能声明"两档对称但没量过"。

**冷启直落地图格也补了**：`syncTopStrip` 原本只挂在 `onChange`/`onTabBarClick`，
而冷启用 `HdsTabs` 的 `index` 初值进 tab，`onChange` 不为初值触发 ——
那条路上带子会留在 `EntryAbility` 涂的画布色。补在 `aboutToAppear` 一处。

**尺子的一条自身缺陷**（不改代码，记着）：全量跑到第 9 屏之后，
`PreferenceQA`/`SpotPick`/`StayPick`/`AreaMore`/`GenerateFailed` 五条报"读不到正文节点"，
单独重跑三条全部正常（净空 12.5vp ok）。是 `force-stop → start → 5s` 这个节奏
在连续 17 屏后不够等界面稳定，**探针不重试**所以报成读不到。
读作探针的已知局限，不是页面回归。

### §5ci 续 79：末卡压 dock 的真因不在 dock——是 Refresh 抢了父容器的满高

续 77 留下一条"机制未定"。这次用**单变量实验**把它定了。

先把现象写成一条律。把 `padding.bottom` 从 112 改成 300（其余一律不动），重建装机、
甩 30 次到停：

| padding 写的 | List 框（实测） | 末卡底 | 残差 = 框底 − 末卡底 |
|---|---|---|---|
| 112 | 171.5..860.8vp | 797.1vp | 63.7vp |
| 300 | 171.5..860.8vp | 609.3vp | 251.5vp |

两行相减：padding 多写 188vp，末卡底就上移 188vp。**padding 一直在老老实实生效**，
只是每次都少 48.4vp —— 不是"没生效"，是有个恒定量在吃掉它。找那个 48.4 是谁。

**答案在 dump 的 `origBounds` 里，不在 `bounds`。** 逐节点打原始像素框：

```
Column（父）   bounds=[0,386][1136,2690]   → 高 2304px
Refresh/List   bounds=[0,536][1136,2690]   orig=[0,536][1136,2840]  ← 高也是 2304px
末 ListItem                                                 底 1904px
```

`bounds` 被窗口裁到 2690，`origBounds` 露出真相：这条列表**实际排到 2840px，比屏幕底还低
150px = 48vp**。父 Column 高 2304，上面那条 Search 已经占掉 150，Refresh 却仍然拿到整整
2304 —— `Refresh`/`List` 不写尺寸时按**父容器的 100% 高**解析，不是"剩下的高"。
于是 padding 从那个看不见的底（2840）量起：2840 − 300vp(937.5px) = 1902.5 ≈ 实测 1904，
误差 1.5px。**律对上了。**

这一条也回过头解释了续 77 那个"两种机制量出同一个 63.7"的怪事：`contentEndOffset` 和
`padding.bottom` 都从同一个出屏的底往回量，当然给出同一个数。当时据此判"两个都不是原因"，
把线索用错了地方——真正的第三个变量（框本身比窗口高 48vp）没被看。

**修法一行**：给 `Refresh` 加 `.layoutWeight(1)`，让它拿剩余空间而不是父容器的满高
（[pages/TripsPage.ets:485](../entry/src/main/ets/pages/TripsPage.ets#L485)）。
padding 那 112vp 保持契约值不动——它是 dock 顶到容器底的实测距离，本来就对。

**顺带把"机制未定"的注释撤了**，原地换成写明这条律的注释；注释里指向的尺子名字也错了
（写的 `audit_scroll_clearance.py`，实际是 `verify_scroll_clearance.py`），一并改对。
**给第 14 把尺加了判据 5（滚动区出屏）**，因为只量"末边 vs dock 顶"抓不全这一类：
行程格是靠三条长卡把内容顶到 dock 上才暴露的，而基线里净空 173–395vp 那批屏，
即使框同样钻出屏幕底，读数也照样是 pass。新判据直接比 `origBounds` 最底与容器底。

阳性自证（[[verify-the-scanner-before-trusting-a-zero]] 的规矩）：喂修前那份 dump
`/tmp/k3.json` → **spill = +150px = 48.0vp**，与缺陷量级一致；喂修后的行程格 dump → 0px。
口径上踩了一个坑：`scrollable` 属性在同一份 List 上有时 true 有时 false，
只按它筛会漏，所以改成"`scrollable=true` 或类型 ∈ List/Grid/Scroll/WaterFlow/Refresh"。

**全量 17 屏复跑（单实例、干净）**：退出码 0，**0 屏遮挡、0 屏出屏**。

| 屏 | 可滚 | 末边vp | 净空vp | | 屏 | 可滚 | 末边vp | 净空vp |
|---|---|---|---|---|---|---|---|---|
| 地图 | 否 | 736.6 | +12.2 | | Review | 否 | 575.0 | +173.8 |
| **行程** | **是** | **749.1** | **−0.3** | | EditItinerary | 否 | 519.4 | +229.4 |
| 规划 | 否 | 639.0 | +109.8 | | Share | 否 | 748.8 | 0.0 |
| 费用 | 否 | 562.6 | +186.2 | | Badges | 否 | 447.0 | +301.8 |
| 我的 | 否 | 555.5 | +193.3 | | TripInput | 否 | 736.3 | +12.5 |
| Itinerary | 是 | 748.8 | 0.0 | | PreferenceQA | 否 | 736.3 | +12.5 |
| OnTrip | 否 | 353.9 | +394.9 | | SpotPick | 否 | 736.3 | +12.5 |
| StayPick | 是 | 736.3 | +12.5 | | AreaMore | 否 | 575.0 | +173.8 |
| GenerateFailed | 否 | 736.3 | +12.5 | | | | | |

行程格从 −48.3 变成 −0.3（贴平，与 Itinerary/Share 的 0.0 同档）。
**诚实记两条边界**：① 表里 7 屏 dump 里一个滚动区节点都没筛到，它们的 0 只说明
"看得见的内容没被挡"，不证明框没出屏；② 续 77 记的"连续跑后 5 秒节奏不够、
探针不重试"这条局限本轮没复现（17 屏全部读到），但没修，仍按已知局限对待。

**这一轮自己犯的一次取证污染（记下来）**：先后起了两份全量跑，两个进程同时点同一台真机，
互相把对方甩离目标屏，证据文件（同名 `sc-*.json`）也被后写的盖掉——
第一份的尾表我当成结论引用过，实际不可信，所以作废重跑了一遍单实例。
尺子的用法里补了一句"一次只跑一份"。

闸门：静态十二把尺全 0；5 套纯逻辑离线断言全绿（MAP_CITY/TRIP_INTENT/TRIP_REVIEW/REPLAN/WEATHER OK）；
HAP BUILD SUCCESSFUL；真机 hypium **191/191**；`verify_dock_tabs.sh` 六项无 ⚠；
`verify_scroll_clearance.py` 全量 17 屏 pass。零 LLM、未动行程/打卡数据。

### §5ci 续 80：屏15 的"顶边色差"不是屏15 的事——17 个 push 页的栏带在深色档全是纯黑

续 78 把这条记成"一个静态 token 配不了两种顶边"，并因此**主动放弃**了屏15。
这轮先量准再动手，结论把那条前提推翻了：**屏15 的顶边不是它自己的天性，是框架默认值。**

`uitest dumpLayout` 直接读节点真值（深色档，`--ps darkprobe 1`）：

```
Column（壳层）      [0,106][1136,2690]  bg=#FF121212   ← 画布，对
Navigation          [0,106][1136,2690]  bg=#FF121212   ← 对
NavDestination      [0,106][1136,2690]  bg=#FF000000   ← 纯黑，HDS 深色默认
  TitleBar/HdsTitleBar  bg=#00000000                   ← 透明，于是露出上面那层黑
Column（页面正文）   [0,386][1136,2690]  bg=#FF121212
```

栏是透明的，露的就是 `NavDestination` 自己的底。所以每一屏 push 页都有三段：
系统带 18 → 栏带 0 → 正文 18，**Δ18 的缝在 y=106 和 y=386 各一道**。
同族一查就是 17 个 `HdsNavDestination`（Badges / Review / Share / OnTrip 全部 `#FF000000`）。
浅色档默认就是 `#FFFFFF`＝画布，所以这条缝**只有深色看得见** —— 这也是上一轮"屏15 顶边 0"
的来历：它量的不是屏15，是 HDS 的深色默认。

**先单点证因，再铺开。** 只在 OnTripPage 加一行 `.backgroundColor(ColorTokens.canvas)`，
装机复测：`NavDestination bg` 翻成 `#FF121212`，逐行中位 `0/60/106/200/340 = 18/18/18/18/18`
（改前是 `18/18/5/0/0`）。假设成立，才铺其余 16 页。
铺开用结构化定位（`HdsNavDestination() {` 配平括号找闭合行，且下一行必须以 `.` 开头），
**第一版脚本按"缩进相同的 } + 下一行是 ."匹配，命中了 Stack 的错缩进闭合括号，
把属性挂到了内层** —— 全部回退重做，17 处逐一核对下一行都是 `.titleBar(` 才写入。
（[[verify-batch-edits-by-measuring]]：批量改完必须逐屏量回来。）

**修完自己暴露下一条缝**：从地图格按栏上「旅行中」压进屏15 之后，屏幕顶上是那一页的栏带（18），
而系统带还留在地图的蓝灰 56 —— `Index.syncTopStrip` 原来**只按页签**决定带色。实测：
`push 后 0/60/100/106 = 56/56/56/14`，Δ38。

带色该跟"栈顶是谁"，而这件事只有地图自己的导航栈知道，所以收在 `MapPage.bindStripToStackTop()`：
`pathStack.setInterception({ willShow })`，`to === 'navBar'` 就是"这一跳回根视图"
（`NavBar` 是字面量类型 `declare type NavBar = 'navBar'`，比较是类型安全的，不用 `size()`——
回调那一刻栈可能还没更新）。壳层那侧同步补一条：`index === TAB_MAP && stackOfTab(TAB_MAP).size() === 0`，
否则"屏15 盖在地图上时切走再切回"会把蓝灰带留在别的页上。

**真机三态闭环（深色）**：

| 状态 | 逐行中位 0/60/100/106/200/340 |
|---|---|
| 地图格（栈顶=地图） | 56 56 56 56 56 56 |
| push 屏15 | 18 18 18 18 18 18 |
| 返回地图格 | 56 56 56 56 56 56 |

浅色档同一路径三态全 255（本轮改动在浅色是 no-op，因为画布与 HDS 默认同值）。
六个 push 页（OnTrip/Badges/Itinerary/TripInput/Share/EditItinerary）深色复测
`NavDestination bg` 全部 `#FF121212`、`0..340` 一路 18 连续。
离开底图页做了进程对照：`pidof` 前后同为 13028，hilog 里 `cppcrash` 0 条 ——
新加的 `willShow` 回调没有触发续 78 之前记的那条"离开含底图页面 App 被杀"。

**顺带量到一条与本轮无关的**：`audit_contrast.py` 在屏15 深色抓到 dock 选中标签「规划」
`4.39:1`（阈值 4.5）。那是 dock 玻璃上的蓝字，不在本轮改动面上，另立待办。

**闸门（本轮全量）**：静态十二把尺退出码全 0；5 套纯逻辑离线断言全绿；HAP BUILD SUCCESSFUL
且产物自证（解包 `modules.abc` 里 `bindStripToStackTop` 命中 2 次、`setInterception` 1 次，
不是 hvigor 复用旧产物）；真机 hypium **191/191**；`verify_dock_tabs.sh` 六项无 ⚠；
`verify_scroll_clearance.py` 全量 17 屏 pass（与续 79 那轮逐项同值，说明这批改动没动到布局）。
零 LLM、未动行程/打卡数据。

### §5ci 续 81：逐屏走查抓到的第一个缺陷是尺子自己——顺带把 dock 标签的蓝色选中态改掉

上一轮改完窗口全屏、顶部带色、17 页底色，闸门全绿。按 [[feedback-green-rulers-not-ui-quality]]
的规矩，这一轮不看尺子看屏幕：全 17 屏深色档成对采集（dump + 实拍），逐屏跑第四把尺，
再目视关键屏。

**先抓到的是尺子的两个假阳性。** 屏5 报「40分钟 2.32:1」「适合商务/购物… 3.92:1」两处，
准备照数改色之前先对了一眼图：dump 里是「适合商务/购物」，截图里已经是「适合购物/商务」——
**两帧不是同一时刻**（这一屏正文由 MapKit/LLM 回包异步填，会改文案与行高）。
等文本稳定后重采，两框还在，但位置落在钉底操作条（实底 `#FF121212`，顶边 2166px）以下 ——
**它们是被遮住的视口外节点，框内只剩 jpeg 噪声，压根没画字。**
滚到底复测：末行底边 611.2vp，操作条顶边 693.1vp，净空 +81.9vp —— 内容可达，**没有布局缺陷**。
差点照着假数去改配色，这就是"先看图再动手"挡下来的。

尺子的第四把因此补了**节点树遮挡判定**（`occluded()`）：不再靠像素启发式猜"这框有没有画字"。
过程里踩到三处，每一处都会造成误判：

1. **遮挡层不能只认得出实底色。** dock 走系统材质，dump 里 `backgroundColor=#00000000`、
   `blur=''` —— 材质根本不在字段里。浅色档行程格「总花费 ¥5,200」压在 dock 下量到 **1.12:1**，
   只认实底就漏了它。补的口径：类型为 `TabBar` 的节点本身就是"浮在内容之上的条"，算遮挡层。
2. **父容器永远不能算子的遮挡层。** dock 的 `TabBar` 自带 `zIndex=3`，里面五个标签是 `z=0`，
   按 `(zIndex, 树序)` 比大小会判成"父在子之后画"，于是**把五个标签整排当成被遮住**——
   规划格那一屏被吞掉之后尺子报 0 问题，正好把刚修好的 dock 变成假绿。
   修法：`collect` 一路带祖先 seq 集合，命中祖先直接跳过。
3. **阈值从 70% 降到 50%。** dock 是半透明材质，盖住半行字就读不出了
   （「总花费 ¥5,200」被盖 68%，量到 1.12:1）。

改完按 [[verify-the-scanner-before-trusting-a-zero]] 立**阳性对照**：拿改之前抓的那帧
`/tmp/walk-dark/规划` 喂回去，仍报 `4.39:1 规划`、遮挡 0 处 —— 尺子还抓得到，
"全绿"才是结论而不是吞掉了。

**真缺陷在 dock 标签上。** 逐格量五个标签（选中打星）：

| 深色档 改前 | 地图 | 行程 | 规划 | 费用 | 我的 |
|---|---|---|---|---|---|
| 行程格 | 7.03 | **4.67**\* | 6.49 | 6.75 | 6.82 |
| 规划格 | 7.03 | 7.06 | **4.39**\* | 6.49 | 6.82 |
| 费用格 | 7.03 | 7.06 | 6.49 | **4.75**\* | 6.82 |
| 我的格 | 7.03 | 7.06 | 6.49 | 6.75 | **4.63**\* |
| 地图格 | **3.05**\* | 4.58 | 4.33 | 4.24 | 4.77 |

两个独立成因：① 选中态是**品牌蓝 `#0A84FF`**，在画布玻璃上就只有 4.39–4.75；
② 地图格的玻璃透的是亮底图（实测底 lum 0.053–0.056，画布那侧 0.015–0.020），
**五个标签全体掉到 3.05–4.77**，连未选中档都不达标。
`nav-label` 是 10px（契约里唯一允许小于 11px 的串），走不了大字号 3:1 档。

**契约早就判过这件事。** `Docs/design-v1/DESIGN.md`（历史路径：v2 起该目录冻结为 v1 原文，
引文内容 v1/v2 一致；现行镜像 `Docs/design-v2/DESIGN.md`，见 §5ci 续 84）§9 原文：
「a tint fill carries an ink label plus a blue stroke, **never a blue label**」，
且"蓝字只允许出现在平画布或不透明 elevated/subtle 面上"（那里给的是 5.57/5.20:1）。
dock 是半透明材质，两头都不占。契约的 dock 段也只写 `iconColor: {colors.icon}` 与
`pressGlow: primary-tint` —— **选中态用蓝字本来就是我们自己加的**。
（同一条律上一轮已经管过站点条编号：`#0A84FF` 对面板 4.03:1，改成实底蓝 + `on_primary`。）

**我照契约改了一版，然后回退——因为这条撞在用户已经拍过的板上。**
改法（两处色，几何没动）：选中 = 图标 `icon` + 文字 `ink` + 字重 500；
未选中 = 图标 `muted` + 文字从 `muted` 抬到 `body`（地图格上 muted 只有 4.24，
而 lum 阶梯上 `body` 0.39 与 `ink` 0.87 之间没有中间档，抬一档是唯一不动几何的解）。
实测改后深色选中 10.38–15.91、未选中最低 5.19，浅色 7.82–19.82，
17 屏 × 深浅两档 0 处低于阈值，目视裁图也确认主次没被抹平。

**但这事 2026-10-26 用户已经拍过板**，而且拍了两次：轮 21「决定不改色（选中蓝是深色帧定的值）」、
轮 26「深色 dock 选中蓝 4.46:1（差 AA 0.04）用户明确决定维持 `#0A84FF` 不改，只留实测记录」。
我这一轮动手前没查这条（只查了 DESIGN.md 的 §9），等于把用户拍过的板悄悄改了 ——
**已回退成原样**（`primary` 选中 / `muted` 未选中），回退后深色复测逐格读数与本轮改前
**逐字相同**（3.05 / 4.39 / 4.67 / 4.75 / 4.63），浅色 6.00–8.41 全过。

**升级给用户重拍的那一条新事实**：当年那次决定量的是**画布那一侧的 4.46**（差 AA 0.04，
"维持"是合理的边际判断），而**地图格这一侧从没进过视野** —— dock 是半透明材质，
透的是底下那块屏，地图格的玻璃底 lum 0.056（画布侧 0.016，亮约三倍），
选中蓝在那里只剩 **3.05:1**，未选中 `muted` 也在 4.24–4.77 徘徊。
这不是"差 0.04"那一档问题了。三条走法代价不同，等用户选：
① 只治地图格（在地图页 dock 底下补契约 §5 那条 92px `glass-bar-gradient-mask`，
把透出来的底压回画布量级，选中蓝在五格上就都是同一个 4.4 档）；
② 全按 §9 改（即本轮已验过的那版，选中 `ink` + 未选中 `body`，深色 5.19–15.91）；
③ 维持现状、只把地图格这 3.05:1 记成已知限制。
工具侧的遮挡判定与 selftest **保留**（那是尺子的正确性，与配色决定无关）。

**闸门（本轮全量）**：静态十二把尺退出码全 0；真机 hypium **191/191**；
`verify_scroll_clearance.py` 全量 17 屏 pass（净空读数与续 79/80 两轮逐项同值 ——
本轮只动色不动几何，这正是该有的结果）；`audit_contrast.py` 改色期间 17 屏 × 深浅两档 0 处低于阈值（**回退后深色地图格恢复为 3.05/4.24/4.33/4.58/4.76，见上面待裁决三条**）；
HAP BUILD SUCCESSFUL 并装机复拍（规划格顶带一路连续、品牌块与主 CTA 正常）。
零 LLM、未动行程/打卡数据。

**两把真机尺都补了 `--selftest`（零设备复算）**。理由：本轮的阳性样本原本指向
`/tmp/k3.json` 这类一次性 dump，而 `/tmp` 重启即清空 —— "判 0 之前先自证抓得到"
这条规矩就没有可复算的依托了。现在内置成 fixture：
`audit_contrast --selftest` 断四条（祖先排除 / 悬浮条遮挡 / 未过半不误伤 / 可见行不吞），
`verify_scroll_clearance --selftest` 断阳性样本必须 `+150px = 48.0vp`、
且把 `scrollable` 全置 false 后仍要按类型抓到。
**这两条 selftest 第一次跑就双双失败**（fixture 括号不配平、样本里那根透明柱写成了实底
把 dock 标签整个盖住），正是它们该抓的东西 —— 也说明"遮挡层"的判定连自己的测试样本
都会踩到同一个坑。

### §5ci 续 82：地图格 dock 底下补一条遮罩——契约那条 alpha 是按画布调的，这里要重推

续 81 把 dock 配色升级重拍，用户选**第三条路：只治地图格**（保住 2026-10-26 拍的
"选中蓝 `#0A84FF` 不改"，只把地图格透出来的亮底压回去）。

契约 §1055 本来就给四处玻璃面配了这条遮罩（`glass-bar-gradient-mask`，约 92px 把内容
淡进栏里），全 App 从没画过 —— 压在画布上看不出来，只有地图格会露真效果。
**先按契约原值画一版**：深色 `#662A2F36`（40%）。装机量：地图格选中蓝 3.05 → **2.90**，
几乎没动。这不是画错了，是**那条 alpha 的适用前提不成立** —— 契约 §5 同一节自己写着
「Re-derive both if the canvas stops being white」，而地图格的底是 lum 0.056 的底图，
不是 lum 0.016 的画布。

**单变量找平台期**（每改一次装一次量一次，深色档地图格选中蓝）：

| 遮罩 alpha（对画布色） | 选中「地图」 | 未选中四档 |
|---|---|---|
| 0（改前） | 3.05 | 4.24–4.77 |
| 40%（契约原值） | 2.90 | 4.28–4.48 |
| 80% | 4.03 | 6.19–6.61 |
| **90%（取这档）** | **4.10** | **6.29–6.74** |

未选中那几档**全部抬过 AA**；选中蓝从 3.05 到 4.10，与其余四格本来就有的 4.39–4.75
已经是同一档（当年那次"维持"决定量的就是这一档）。90% 之后是平台期，再往上只是把底图
压得更死，换不来多少读数。浅色档不需要：地图格浅档实测 6.00–8.41 本来就全过，
所以 `map_dock_scrim` 的 base 档给**全透明**，分档交给资源系统，代码里不写 `if (isDark)`。

**中途差点盖掉地图 SDK 的归属水印**（这条是量出来才发现的，不在计划里）：
第一版遮罩一路铺到屏幕底，「花瓣地图」水印区对比度从 **4.59:1 掉到 1.23:1** —— 归属声明
不能这么压。水印顶边实测在 y≈826vp，就在 dock 底（804.8）下方 21.2vp。
所以遮罩改成三段：上 92vp 淡入、中间 56vp 实心（正好 dock 本体）、下 **21vp 就淡出收手**。
复测水印区回到 **3.92:1**（目视清楚），dock 读数没受影响（4.10 / 6.29–6.74）。

**验的三件事**（都是"说了要做就去拿证据"）：
① 遮罩不吃地图手势 —— 从遮罩区内起手势拖地图，地图内容区 8.7% 像素变化，穿透成立；
② 没动到布局 —— 地图格滚到底净空仍 12.2vp、行程格仍 −0.3vp，与前几轮逐项同值；
③ 闸门 —— 静态十二把尺全 0（`map_dock_scrim` 归入既有的"派生透明值，脚本不判"那一档，
与 `map_strip_base`/`on_dark_degraded` 同族）、真机 hypium **191/191**。零 LLM、未动数据。

**并行改动**：本轮期间用户用 CodeArts 在同仓库做商业化（`bff/`、`IapStore`/`EntitlementStore`/
`DeviceTokenStore`/`DeviceActivator`/`PricingPage`、`Index.bootstrap()`、`MapPage.resolveSeq`
竞态守卫等），**全部未提交**。`MapPage.ets` 因此是"他们的改动 + 我的遮罩"混在一个文件里，
提交时按"HEAD + 仅我的两段"构造索引内容单独提交，工作树里他们的改动原样保留，
不把我的提交信息盖到别人未完成的活上。

### §5ci 续 83：CodeArts 的商业化改动盘点（两条 P0），并把"skip-worktree 必须能编过"变成第 13 把尺

用户这轮用 CodeArts 在同仓库做商业化（IAP / 权益 / 设备激活 / 新增 `bff/` 后端），
21 个文件未提交。工作树被占着，我做任何 UI/逻辑改动都会撞，所以这轮做**只读盘点 + 一条不撞车的闸门**。

#### 两条 P0（都在代码层面证实，不是推测）

**P0-1 现在这份代码把 App 的主路径堵死了。** 链路是：
`GeneratingPage.ets:99` `if (!EntitlementStore.canGenerate()) throw CLOUD_QUOTA_EXHAUSTED`
→ `:126` `replacePath('Pricing')`。而 `EntitlementStore.canGenerate()`（`EntitlementStore.ets:102`）
第一句就是 `if (!isCacheValid()) return false`，`isCacheValid()` 要求 `cachedAt` 在 5 分钟内 ——
缓存只由 BFF 回包写入，而 `DeviceActivator.ets:39` 在 `BFF_BASE_URL.length === 0` 时
**直接 return false 跳过激活**。当前仓库版 `ApiConfig` 的 `BFF_BASE_URL` 就是空串（BFF 没部署），
所以：**生成行程必然被拦、必然跳付费页**。同样地 `canExport()`（:91）还额外要求
`!AccountStore.isGuest()`，日历写入（`ItineraryPage.ets:306`）、.ics 导出（`SharePage.ets:114`）、
分享（`TripReviewPage.ets:152`）三处也一律被拦。`IapStore.verifyWithBff`(:180) 在 BFF 空时
只返回 success 不调 `EntitlementStore.update`，所以开发期买了也不解锁。
> 修法方向（等他们定，我不改别人的在飞代码）：给"无 BFF"一个显式的开发态旁路
> （比如 `BFF_BASE_URL` 为空时整套权益门禁不生效），而不是让"没配置"等于"全拒绝"。

**P0-2 干净检出编不过。** `ApiConfig.ets` 是 skip-worktree（`git ls-files -v` 标 `S`）：
工作树版给接口加了 `BFF_BASE_URL: string;`，而 **HEAD 的仓库版没有这个字段**，
`LlmClient`/`DeviceActivator`/`IapStore` 共 6 处引用它。本地一切正常、`git status` 干净，
别人 clone 下来直接编译失败。这条坑 2026-10 已经踩过一次（记忆
[[skip-worktree-config-must-stay-compilable]]），**同一个坑第二次**，所以这次做成闸门。

#### 第 13 把尺 `tools/audit_skip_worktree.py`

- **R1 引用面**：全仓 `.ets` 里出现的 `<ConfigConst>.<field>`，字段必须在 **HEAD 版**配置里声明过。
- **R2 凭证面**：HEAD 版里名字像凭证的字段（`KEY|TOKEN|SECRET|PASSWORD|APP_ID|CLIENT_ID`）
  值必须为空；另外单判 URL 里内嵌凭证（`https://user:pass@host`）。
  **URL/ENDPOINT 本身不算凭证** —— 仓库版里 `WEATHER_URL` 是 Open-Meteo 免 Key 公共端点，
  把它清空只会让干净检出后的天气功能一起哑掉，是更坏不是更安全。这条是我第一版判错后改回来的。
- `--selftest` 四条：R1 缺字段可判 / R2 凭证入库可判 / 公共 URL 不误判 / 嵌套键不误收。
  **尺子自己也是先错两次才对**：写死"4 空格缩进"漏掉本仓的 2 空格配置（全字段被判成缺失、
  噪声 26 条），改成"缩进最浅一层"后又被 `^(\s*)` 坑了一次 —— `\s` 吃进换行，
  紧跟空行的键缩进多 1，被 `min()` 判成更深一层而整行漏掉（`BASE_URL` 就这么丢了）。
- 首跑就抓到真东西：**1 条 R1 命中，正是 P0-2**（`ApiConfig.BFF_BASE_URL`，6 处引用）。
  这把尺现在是红的，红得对 —— 修法是 CodeArts 把字段补进仓库版并留空。

#### 顺带记两条事实

- **数据库侧是安全的**：`DB_VERSION` 9 → 10，只 `ALTER TABLE trip ADD COLUMN pass_id TEXT NOT NULL
  DEFAULT ''`，由 `if (oldVersion < 10)` 守护、幂等；全文件无新增 `DROP/TRUNCATE/DELETE`。
  `CREATE TABLE` 里删掉的 `user_id`/`time`/`confidence` 三列由既有 v2/v5/v6 迁移在全新安装时补回。
  **我没有装这份包去动真机库** —— 迁移虽然是增列，但拿用户的行程/打卡去验别人在飞的代码不对等。
- **应用侧没新增权限、没新增运行时依赖**（`module.json5`、两个 `oh-package.json5` 无 diff）；
  新依赖都在未跟踪的 `bff/package.json`（express/dotenv/better-sqlite3/jsonwebtoken）。
  但 `bff/` 一旦被 `git add` 就会入库，里面有硬编码兜底 `JWT_SECRET`（值不在本文抄录，
  位置是 `bff/src/middleware/auth.js:3`、`bff/src/routes/iap.js:29`）与 DeepSeek 默认端点 ——
  提交前要把兜底改成"缺环境变量即启动失败"。
- **一轮里删掉的解释性注释**（不是功能改动，但都是踩过坑换来的）：`Index.ets` 四条
  （含"为什么必须等登录态恢复才能种 `ACTIVE_TRIP_KEY`"整段）、`MapPage.ets` 三条、
  `TripsPage.ets` 三条、`StayPickPage.ets` 两条、`LlmClient.ets` 多条
  （response_format 三层防线、max_tokens 截断账单翻倍等）。要不要留由用户定，我没擅自改回去。

闸门：新增的第 13 把尺 `--selftest` PASS、真实扫描 1 条真命中；其余十二把静态尺仍全 0。
本轮零设备写入、零 LLM、未动任何行程/打卡/费用数据。

### §5ci 续 84：契约修订口径改规矩（T8）+ design-v1/v2 版本路标（R17）+ 尺数校到 14 把

批次一（契约 v2 第一批）收尾的两件事：把"契约能不能改"这条规矩改成现在真正在执行的口径，
并给仓库里指向过期契约目录的旧引用立路标。**历史记录一律不回写**。

#### 规矩：契约由产品负责人修订，改后必须同批同步 token 与尺

§6「交接」末尾那条硬约束原文是「`~/Pictures/…/docs/DESIGN.md` 是权威契约，**不许为了让尺子过而改它**」。
本轮把它改写为：

> `~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md` 是家族契约文本，**由产品负责人修订**；
> 任何改动必须与 `design/*.ets` token 表、`tools/audit_*.py` 判据在**同一批提交**里同步
> （尺只遍历契约侧：加行可能红、删行只会绿）。

为什么旧那句话现在挡路：契约 v2 这一批的**内容本身**就是产品负责人改的（玻璃 24→50、
分段控件 20 升为成文例外、sheet/菜单改判材质面、动效落五档）。按旧句字面执行，
"改契约"就等于犯规，于是实际做法只能是"改完契约再把尺子的期望值抄着改一遍"——
那既不禁止为了让尺子过而改契约，也不禁止把尺子调松。新句禁的是**不同批**：
契约改了、token 与判据没同步，中间态必然有一条尺在骗人（本批 T1/T2 的红窗就是这条，
ledger R1 为此把两任务合成一次提交）。

括号里那句「加行可能红、删行只会绿」是这条规矩的**方向性**，不是修辞：
静态尺的判据形态是「遍历契约侧的每一项，去代码侧要一个对应物」，所以
**契约加一档 → 代码缺对应实现 → 报红（可信）**；**契约删一档 → 循环少一轮 → 只会变绿（不可信）**。
同理，把契约段落整块删掉不会让尺子变严，只会让它少看图 —— 所以本轮还要求
"读不到判据来源"必须自己响（见下面 `audit_fontfamily` 那条）。

**口径变化只写在这里，不回头改历史。** 本轮之前的旧口径记录按原文保留：
`:4711-4718` 那段（"两份副本 md5 一致、所以一份没改""后者是用户的设计定稿、
**不可为过闸而改**"，`:4710` 的 `design-v1` 引用也在其中）—— 本轮只在它**后面**
（`:4719-4723`）追加一段历史路径括注，正文一个字没动；`CHANGELOG.md` 里 2026-11-01
同一段记述（原 `:252-254`，因本批顶部新增条目已下移到 `:296-300`）同样一字未动。
那些是**当时真实的判断与实测**，回写就是把没做的事写成做过、把当时的证据涂掉；
本项目反复强调的正是这条。旧句所在行（§6「交接」末尾那条硬约束）属于**现行约束**，
所以只有它本身改写了 —— 现行规范要新，历史证据不动。
行号会随后续新增继续漂，认文案不认行号。

#### 版本路标（R17，评审 M-3）：`Docs/design-v1/` 冻结，现行镜像是 `Docs/design-v2/`

`Docs/design-v1/README.md:17` 自己写着「底稿升版（v2）后，请另建 `design-v2/` 快照目录并更新本
README，不覆盖 v1」，而 v1 冻结是硬约束（不许改它的正文）—— 于是仓库里以 `design-v1`
指称"现行契约"的旧句子会把读者带到过期版本。路标这么打：

| 路径 | 现在是什么 | 证据 |
|---|---|---|
| `~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md` | **契约原件，内容已升到 v2** | md5 `3fcc3a62edc7bc8ac3d782c9910d20aa` |
| `Docs/design-v2/DESIGN.md` | **现行契约镜像**（v2 起以「有据」为参考实现） | 同上 md5，逐字节一致 |
| `Docs/design-v1/DESIGN.md` | **v1 原文，冻结**（只作历史对表） | md5 `7c715d638b48268266b8267c1daaa1a2`，与 `~/Pictures/…v1.bak-2026-11-02/docs/DESIGN.md` 逐字节 |

仍以 `design-v1` 指称现行契约的三处旧引用已**逐条加括注标为历史路径**（只加路标，
正文结论一字未改）：`:4636`（dock 没钉格数）、`:4712`（两份副本 md5 一致）、
`:5203`（§9「never a blue label」引文 —— 该条 v1/v2 内容一致，引文照常有效）。

#### 尺数校正：现在是 **14 把静态尺**

`README.md` 原来在 `:23`/`:39` 写「十二把静态尺」、`:74` 闸门表写「十三把尺」，两头都落后于实际。
清点口径：`tools/audit_*.py` 共 15 个，其中 **14 把是静态尺**（不需要设备就能跑），
`audit_contrast.py` 要真机 `dumpLayout` + 截图，**不计入静态**。
14 把 = 原 13 把静态（colors / type / geometry / material / fontfamily / tnum / elevation /
button_width / scroll_actions / label_fit / a11y_name / layout_patterns / skip_worktree）
+ 本轮新增的 `motion`。README 的 `:23`、`:39`、`:74` 已按这个口径改写，闸门表补了 `audit_motion.py` 一行。

#### 本批第二条闸门修复：`audit_fontfamily` 的假绿

这条尺定义了契约路径常量（`DESIGN`/`FRAMES`）却**从没 open 过**，serif 档全部来自硬编码表
—— 契约 typography 段改了它永远 0 红，读数看着像"没问题"其实根本没看过契约。
现在改成真解析（`contract_serif_tiers()` 读 hierarchy 子树，凡带 `fontFamily: serif` 的档取
`fontSize`/`fontWeight`；`display-sans`/`title-sans` 这类没有 serif 键的档不进集合），
并钉了三条退路：**解析不到 serif 档 → 打印「尺子失明」；内置表只作兜底，走兜底必打
`[降级]` 且 rc 非 0；契约路径不存在 → 退 2（与 `audit_colors.py:81-83` 同惯例）**。
反证三条都跑过：改副本里 `title` 的 `fontWeight` 700→600 尺子报红；整段删掉 `typography`
打印尺子失明 rc=1；路径指向不存在的文件退 2 无 traceback。`--selftest` 24 条先证规则本身有效
（喂「serif 档未带 `.fontFamily`」的假源码必须命中 `[漏字族]`），再证解析。

#### 边界（本批**没有**的证据，别当已收口）

- **顶栏模糊 50 至今没有像素证据。** 判据由 note 升 fail 的那一轮（`8111777`）之后，
  `scrolled`/`scrollable` 只在 `design/HdsChrome.ets:55/57/76/83` 自己被声明和消费，
  **没有任何页面往 `ChromeSpec` 传过这两个键** —— 两态实际仍是 0 模糊。
  现在能说的只有"尺绿 + 构建过"，唯一取证点在 T4（属批次二，页面被另一会话占着）。
  另有一条未验证假设（N-4）：`scrollEffectStyle` 只带 `contentStyle` 不带 `backgroundStyle`，
  滚动终态栏下会不会重新长出默认底色/第二圈环，也要 T4 真机滚动态才能判。
- 本批只做了 **T1′/T3/T5/T7/T8**。**T4（16 页接线取证）、T6（间距契约名迁移）、
  T9（批次收尾）都没做**，起点条件是另一会话那 21 个在飞文件先提交。
- 闸门：**本轮（T7/T8）实跑**的是 14 把静态尺全 rc=0、`audit_fontfamily.py --selftest` 24 条 PASS、
  `audit_motion.py --selftest` 30 条 PASS。双 HAP `assembleHap BUILD SUCCESSFUL` 与真机 hypium 192/192
  是 **T3（`8111777`）/ T5（`23bf450`..`3d56074`）各轮实跑并经复审复算**的记录，本轮没有重跑构建与设备，
  别把它读成"T7/T8 又验了一遍真机"。本轮零设备写入、零 LLM、未动任何用户数据。

#### 续 85（2026-11-03）商业化链路真实验收：干净检出下主路径不可达 + 7 条支付守卫缺陷

探针 `bash tools/probe_bff_commercial.sh`（`tools/bff_commercial_probe.mjs`）。跑法见
`Docs/analysis/商业化链路真实验收-2026-11-03.md`。`bff/` 此前只被 `node --test` 用
`initDb(':memory:')` 装配成 in-process express，**`src/index.js` 从未作为真实进程启动过**，
`grep -rn iap bff/test/` **零命中** —— 付费路径一行测试都没有。本轮补齐。

**已证成立（13/14 必守行为）**：真实进程可启动；匿名设备激活拿票据并赠 3 次；
无票据读权益被 401 拦下（正对照，先证明鉴权链确实在）；`gift 3→2`；
同键重放带 `Idempotency-Replayed: true` 且**上游调用数 1→1、额度不双扣**；
三次用尽后第四次 **402 QUOTA_EXHAUSTED** —— 付费墙本身可诚实到达，扣费/幂等记账不用返工。

**P0 · 主路径在干净检出下不可达**（不是探针结论，是逐跳读消费方读出来的）：

| 跳 | 位置 | 行为 |
| --- | --- | --- |
| 1 | `common/config/ApiConfig.ets`（**仓库版** `git show HEAD:` 第 93/94 行） | `BFF_BASE_URL: ''` + `DEV_SKIP_BFF: false` |
| 2 | `data/DeviceActivator.ets:39-42` | URL 空 → 直接 return false，**永不激活** |
| 3 | `data/EntitlementStore.ets:117-131` | `devBypass()` 假 + `isCacheValid()` 假（缓存从没被填过）→ `canGenerate()` **恒 false** |
| 4 | `pages/GeneratingPage.ets:99-101 → 126-128` | 抛 `CLOUD_QUOTA_EXHAUSTED` → `replacePath('Pricing')` |
| 5 | `pages/PricingPage.ets` → `data/IapStore.ets` | 购买又要打同一个不存在的 BFF |

⇒ 任何干净检出/**提审构建**：点「生成行程」100% 跳付费页，且付费页也走不通。
商业化方案 §2 承诺的「免费 = 本机规则引擎生成」在 release 形态下**没有出口**——
本地合成挂在 `LlmClient.ets:326-328` 的 `DEV_SKIP_BFF` 之后，仓库版恒 false。
这条属产品决定（部署 BFF / 把本地规则引擎做成真免费档），**没替用户拍**。

**7 条支付守卫缺陷**（逐条证据见分析文档 §2）：D1 `services/iap.js:4` 的
`verifyPurchase()` 恒 `{verified:true}` ⇒ 假 `purchaseToken` 换来 active 订阅；
D2 该订阅**兑换成真额度**（赠送已 0 的账号 `POST /v1/trip/generate` → 200 `source=subscription`，利用链闭合）；
D3 假收据换来 trip pass ⇒ 端侧 `canExport()` 只看 passes 里有没有该 id，导出墙失效；
D4 伪造 pass 在**干净账号**上买到 `source=pass` 无限生成；
D5 换 `deviceId` 白拿 3 次（无 unionId 即建 `anon-<deviceId>`，端侧 deviceId 是本地随机 UUID）；
D6 `quota.js:1` `DAILY_CAP=20` 按**天**数，方案写 20 次/**月**，成本敞口约 30 倍；
D7 `/v1/iap/notify` 只 log 后回 `200 {}` ⇒ 到期/续费/退款永不改变权益；
另 D8 同一 `purchaseToken` 重复提交 → **500 SQLITE_CONSTRAINT_UNIQUE**（裸 INSERT，未处理约束）。
D9（**读码推断、非探针实测**）端侧对「订阅到期/退款」无感知：`routes/trip.js:105-110` 的 `quota`
不含 `subscription`，`ai/LlmClient.ets:279-288` 把 `subscription/dailyCap` 从本地缓存**原样结转**
（该处注释已写明 `remainingToday` 实为 `usedToday` ⇒ 形状差异是**刻意绕过**、不是漏字段），
而 `data/EntitlementStore.ets:23` 的 5 分钟 TTL 由每次 `update()` 刷新（`:134-135`）——
生成间隔小于 5 分钟就永不过期，叠加 D7 空转回调，到期与退款在端上没有生效路径。

**探针自己的一处假绿（已修，值得记）**：第一版把「伪造 pass 换生成额度」放在账号 1 上跑，读出 PASS。
根因是账号 1 此时已有（伪造来的）订阅，`determineQuotaSource` 优先返回 `subscription`，
`pass` 分支整个被盖掉。换干净账号 C（先烧光 3 次赠送、断言 402 当前提）后同一断言立刻变 DEFECT。
与 [[verify-the-scanner-before-trusting-a-zero]] 同族：**守卫类断言必须先证明它抓得到**。

**边界（本批没有的证据）**：端侧→BFF 那一段仍未在真机跑过一次（`BFF_BASE_URL` 空 +
skip-worktree），本探针只证明服务端一侧；契约 v2 的 T4/T6/T9 仍以另一会话 24 个在飞文件落地为前置，
顶栏模糊依旧零像素证据。本轮**零设备写入、零 LLM、未动 bff/data 与任何用户数据**
（探针跑在 `mktemp -d` 副本里，因 `bff/src/db.js:7` 的 `DB_PATH` 硬编码无 env 入口）。
静态尺 14 把全 rc=0、离线断言 7 套全 PASS（本轮实跑）。
**上段的「T4/T6/T9 以在飞文件落地为前置」已在续 86 解除**（用户确认对方会话结束、可动）。

#### 续 86（2026-11-03）P0-B 落地：干净检出主路径打通，单变量前后对拍

用户拍两件事：① **P0 走 B→A**（先把本机规则引擎升成真免费档，BFF 部署随后）；
② **另一会话已结束、那 24 个在飞文件可动**。

- **先承接再动手**：24 个在飞文件 + 未跟踪 `bff/`、6 个新 `.ets`、`Docs/商业化方案.md`、
  对方的全量分析文档，作为**独立一条标清归属的提交** `7beef96` 入库（不是我写的，
  消息里写明证据来源与未验项）。入库前证据：十四把静态尺 + 七套离线断言在含这批改动的树上全 rc=0；
  产物新鲜度用特征串反证（`modules.abc` 12:06:44 晚于最后源码改动 12:03:20，
  且 abc 里 strings 得到 `buildTripGeneratePayload`/`DeviceActivator`/`EntitlementStore`/`PricingPage`）——
  **hvigor 报 UP-TO-DATE 不等于产物含改动**，这条又应验一次。
  排除入库：`bff/.env`（含 DEEPSEEK_API_KEY/JWT_SECRET）、`node_modules`、`bff/data`、`.merkle-snapshot.json`。
- **改法**：新增 `utils/GenerationChannel.ets` 作为「这次走端侧合成还是走 BFF」的唯一判据，
  门禁（`GeneratingPage`）与传输选择（`LlmClient`）同读它；BFF 未配置即走端侧合成，
  不再要求 `DEV_SKIP_BFF` 参与传输选择。提交 `5d9526f`。
  判据收成一处是因为本项目已两次被「两份同源实现各改一边」咬到（`dailyCap`、`rankAreas`）。
- **单变量前后对拍**（同一台 Pocket 2、同一份发布形态配置 `DEV_SKIP_BFF:false`，只换那两个调用点）：
  改前 `git checkout 5d9526f^` 装产物 → 一句话「北京 3天2晚 2人」→ 识别 → 直接生成行程 → **落付费页**；
  改后同一条链 → **落屏8 真行程**（Day 1 · 11月03日 / 故宫博物院 09:00 需预约 / 理由件 /
  地铁 22分钟·2 站 / 八达岭长城 13:15 / Day 1-3）。帧存
  `~/Pictures/有径/走查帧-2026-11-03/P0改前-发布形态落付费页.jpeg` 与 `…改后…落屏8.jpeg`，**两张都人眼看过**。
  该次生成走端侧合成 ⇒ **零 LLM 花费**。验完还原本机 `ApiConfig` 为原值 `true`、重装与源码一致的产物。
- **闸门**：真机 hypium **198/198**（含新增 `GenerationChannel` 4 例）；十四把静态尺 + 七套离线断言全 rc=0；
  双 HAP BUILD SUCCESSFUL（CompileArkTS 实际重编，不是 UP-TO-DATE）。
- **文案随实现改口**：隐私政策原文写「景点名称会发给大模型接口」、用户协议写「行程依赖大模型输出」，
  在默认形态下都是不实陈述；两条改成按配置分述本机/云端，并写明配了云端时 UnionID 与设备标识**会**发
  （原文反而写「不包含华为账号标识」）。按 `ConsentStore.ets:9` 自定规矩 `CONSENT_VERSION` v2→v3，
  真机已见重新明示询问。**上架前仍需法务复核。**
- **新登记两条**（详见 `Docs/analysis/商业化链路真实验收-2026-11-03.md` §9）：
  **D10 免费档默认产出超载日**——改后那帧屏8 自己写着 `今日 13.7h · 超建议 3.7h` 且负载条满格变红；
  单日收口只作用于 1 天行程，多天按「每天 4 站」直排，而种子库停留是 4h/5h。
  B 落地后这条从"开发期噪声"变成**默认体验**，下一轮优先。
  **D11 云端落了行程骨架**——`routes/trip.js:32,43` 把整个请求体存进 `trip_request.params_json`
  （含城市/日期/人数/预算/选中景点名/片区），而方案 §1 承诺「行程内容永不上传，云端只看到随机 UUID 和时间戳」。
- **另一会话那份分析文档的 R1 已过期**：它写「BFF prompt 只有一句话、PromptBuilder 未被生产 import」。
  现读 `bff/src/prompt/index.js:180` 调 `PromptBuilder.userPrompt(...)`、`contract.js:18` require
  生成物 `TripSchema.js`，且 `bff/README.md` 的「Prompt / Schema 同源」是 12:17 才写进去的——
  即该文档写于 00:42、改动发生在其后。探针日志 `prompt=rich response_format=json_object` 也是正向证据。
  **R2 与我的 D1/D3/D5/D7 独立收敛到同一结论**，可信度因此更高。
- **验收脚本的一处假阳性（已修）**：断言"到屏8"用了 `完整行程`，付费页的「解锁完整行程」同样命中，
  改前那一跑差点被读成"改前也能生成"。换成 `Day 1 ·`/`去减一站`/`为什么排在这里` 后两跑读数才互斥。
- **数据副作用**：走查在设备库新增 2 条北京 3 天测试行程（改前那次被门禁拦下、未落库）。
  未删任何用户数据，清不清归用户。

#### 续 87（2026-11-03）契约 v2 批次二 T4：顶栏门控全仓接线，磨砂**首次出图**

用户确认另一会话已结束、24 个在飞文件可动 ⇒ T4 的前置解除。提交 `a7de94f`。

- **22 个 `HdsChrome.bar()` 调用点全部表态**（18 页 + Index + 两个 rootMode 双形态页）：
  有纵向正文的传 `scrolled`，没有的（地图格、生成页）传 `scrollable: false`。
  判据一律 `currentOffset().yOffset > 0` 的**绝对偏移**，不用每帧增量。
- 两种非标准形态各自单独处理：**规划格**的滚动容器在 `YoujingStartPage`、顶栏却在 `Index` 的
  `HdsNavigation` 上 ⇒ 新增 `AppNav.PLAN_SCROLL_KEY` 走 AppStorage 递状态（其余 17 页同页自产自销）；
  **屏8** 复用已有的 `listScroller`，不建第二枚实例（`ListScroller` 是 `Scroller` 子类，`currentOffset()` 可用）。
- **同批删掉 4 处深色归零分支**并把 `audit_elevation` 判据**反转**：出现深浅门控即违规、
  `radius: 0` 只允许由材质门控引出（`glassOn` 那条 v2 保留）。旧别名 `ShadowTokens.contact/card` 删除——
  `StyleConfig.test` 那条断言的注释自己写明"删别名时这条会编译失败，是预期的删除信号，不是回归"，
  信号兑现了，改成直接钉新档的四字段值。
- **新尺 `tools/audit_bar_scroll.py`**（静态尺计数 十四 → **十五**）：多行 spec 要按括号配平取整段。
  第一版把 depth 起点写成 0，**22 个调用点全被误判成未表态**——靠 `--selftest` 三条控制
  （单行已表态／单行未表态／多行已表态）才发现。修好后实跑 22 处、未表态 0。
  `audit_elevation --selftest` 从 14 条增至 **17 条**，新增 3 条阳性专测反转后的门控判据抓得到
  （判据改了却没人反证，正是本仓反复踩的「0 命中假绿」）。
- **真机像素证据（这条疑问自 2026-10-25 欠到今天，就此销案）**：
  行程格栏带 mean 静止 248.3 → 滚动 238.8；规划格 251.0 → 241.5（两页 Δ 同为 −9.5）。
  **图也看过**：静止态顶栏纯画布，滚动后顶栏出现灰调磨砂、搜索药丸下方透出被糊化的列表文字。
  结论修正：v1 的 `blurRadius=24` 从来没出过图，**根因不是半径值，而是全仓没人传 `scrolled`**——
  所以"24 在这台机器上到底出不出可见磨砂"这个自留疑问问错了问题。
- 闸门：真机 hypium **198/198**（双 HAP 全新构建后安装）、十五把静态尺 + 七套离线断言全 rc=0。
- **未验**：其余页面磨砂逐屏实拍（机制已在两页证通，含跨组件那条最难的路径）、深色档阴影可见性（见续 88）。

#### 续 88（2026-11-03）深色档阴影实拍：契约 v2 的推断成立，但翻出一张"没有边界的卡"

T4 反转后深色下这些投影会画出来，而我一帧没看过——这是我自己改动的风险，优先于 T6 的机械改名。
设备已有 `--ps darkprobe 1` 探针（App 级 `setColorMode`，不动用户系统主题），无需临时改码。

- **量的方法先错两次**：① 第一版拿文本节点的 bounds 当卡面，量到的是卡间画布，报出 Δ=−13 的假信号；
  ② 改竖直剖面时又选了 x=8..26 这条**在卡片左边距之外**的列，整屏读成 18.0。
  第三次改成"两张相邻卡之间的空隙，顶带减底带"才对（`cardAmbient` 是 offsetY 3 / blur 10，
  影只落在上卡下方）。**教训：探针的采样位置必须先用 dump 的 bounds 校准，否则读数会自证一个不存在的结论。**
- **结论一：契约 v2 的推断成立。** 深色下投影实测 Δ = −0.1（空隙顶 17.8 / 底 17.9），
  即黑 alpha 压在有径的 `#121212` 上**确实近乎不可见**——不是"脏"，是"没有"。
  所以不需要回方案 §7 作设计取舍，反转是安全的。
- **结论二（真缺陷，已修）**：正因为深色下投影不可见，卡片必须靠**底色台阶**分层。
  而 `TripsPage` / `StayPickPage` / `EditItineraryPage` 三处卡片填的是 `ColorTokens.canvas`
  ——**画布色画在画布上**。改前实拍：全屏 1950 行里 1767 行读数都是 canvas 的 L=18，
  卡面应有的 `surface_elevated` 档（L=30）**零命中** ⇒ 深色下行程列表就是一堆浮在黑底上的文字，
  没有卡、没有边界、没有层次。浅色下侥幸能看，因为白底上的 7% 黑影还测得出（247 vs 255 也帮了一点）。
  这同时是**契约偏差**：`components.card.backgroundColor` 契约写的是 `{colors.surface-elevated}`。
  三处改回 `surfaceElevated` 后复拍：深色卡面 L=30.0 / 隙中 18.0（台阶 12 级，肉眼已成卡）、
  浅色卡面 248 / 画布 256（契约本意的柔和台阶，不发闷）。两档都**看过图**。
- **v1 契约那句话的后半段从来没实现**：`In dark mode drop the shadow **and add a luminance step instead**`
  ——只做了 drop shadow，没做 luminance step。v2 删掉这句后，这个缺口才第一次暴露出来。
- 证据帧：`~/Pictures/有径/走查帧-2026-11-03/深色-行程卡改后有边界.jpeg`、`…/浅色-行程卡改后.jpeg`。
  （改前那帧被复拍覆盖，没留下；改前的读数在上面，是逐行中位亮度分布而非目测。）
- 闸门：十五把静态尺 + 七套离线断言全 rc=0；真机 hypium 198/198；双 HAP BUILD SUCCESSFUL。
- **未验**：屏5 片区卡与屏9 拖动预览只改了底色、没实拍（进入通路受限，§5ci 早前已记：
  屏9 深链带不进 `{tripId,dayIndex}` 对象、注入路要造超载或空白天、顶栏 ⋯ 注入点不开，
  上一次是用户真人点进去的）。
- **同族已回扫干净**：全仓「`.backgroundColor(ColorTokens.canvas)` 与 `.shadow(` 挂在同一条属性链」
  改后命中 **0** 处。这个 0 是先做过正对照才算数的——同一把扫描器喂 `HEAD~2` 的三份改前文件，
  精确抓出 `TripsPage:326 / StayPickPage:362 / EditItineraryPage:327` 三处（= 我改的那三处），
  证明它抓得到；否则"0 命中"多半只是漏判。

#### 续 89（2026-11-03）D10 收口：生成器按当日负载窗口排站，超载日不再出现

免费档成为默认出口后，屏8 那行 `今日 13.7h · 超建议 3.7h` 就是新用户看到的第一屏。

- **根因不是"选太多"，是生成器只挡开始时刻**：`MockLlmTransport.synthesize` 的内层循环
  只有 `slot > 20:00 → break`，**从不检查这一天累计负载**。种子库的真实停留是 4h/5h，
  12 站摊 3 天（每天上限 4 站）就排出 820~895 分钟，而 `DayLoadCalc.WINDOW_MINUTES` 是 600。
- **测试为什么一直没抓到**：`LlmPipeline.test` 全部 fixture 的 `suggestedDuration` 是 60/90/120 分钟
  —— 负载永远够不到窗口。**fixture 的量级必须与真数据同量级，否则用例是空的。**
- **新用例先跑红再修**（`offline_day_load_stays_inside_window`，12 站 / 3 天 / STANDARD）：
  改前真机读数 `D1=820min(780停留+40通勤) D2=880 D3=895`，全部 >600 ⇒ 用例红。
  第一版我只喂 6 站，quota 摊成 2/天、负载 540min 刚好不超 ⇒ **用例绿了却什么都没证**，
  补到与真实预选同量级才暴露。这条也记进方法账：**新断言必须先证明它会失败**。
- **改法**：当日负载预算直接取 `DayLoadCalc.WINDOW_MINUTES`（与屏8 负载条同一把尺，不新增第三种数字），
  装不下就**跳过这一站继续看下一站、留给后面还有余量的天**（沿用重庆单日收口学到的"不能从尾部砍"），
  但**一天还空着时宁可超窗也要装首站**——空白天比超载天更糟。
- **真机复测（同一条输入「北京 3天2晚 2人」，端侧合成、零 LLM 花费）**：
  改前 `今日 13.7h · 超建议 3.7h` + 「去减一站」+ 满格红条；
  改后 Day1 `9.4h · 建议 ≤10h`、Day2/Day3 各 `9.2h · 建议 ≤10h`，
  **「去减一站」出口自然消失**（无超载可减）。
- 闸门：真机 hypium **199/199**（新增 1 例）、双 HAP BUILD SUCCESSFUL。
- **新登记的遗留（D10b，未修）**：预选数量仍与承载能力不一致——屏2 写「按每天 4 站预选 12 个景点」，
  实测三天各只排下 2 站 ⇒ **6 站被静默丢弃**。正解是把同一套负载预算前移到
  `PlanAutoPick.pickSpots`（现在它是纯 `days × dailyCap` 计数），并让屏2 那句数量文案跟着改口。
  这条会动 屏2 文案与离线 `TRIP_INTENT` 断言，且涉及"节奏档上限 vs 时间可行性"的取舍
  （用户勾了每天 4 站，但 5 小时的景点物理上排不下 4 个），**属产品口径，留给用户定**，
  我没有替拍。当前行为（排出能装下的、丢掉装不下的）至少不再报超载。
- **两条自纠（写下来免得下次再犯）**：
  ① 我**在尺红的状态下就提交了** `cd2d7f0`——命令串里 `FAIL=1` 只置了变量、没拦住后面的 `git add && git commit`，
  输出明明印了「闸门：有红」我还是往下走了。之后补了 `LlmClient` 的改写并复跑全绿，
  但历史上留了一条红闸门的提交，这是流程失误不是技术取舍。
  规矩：闸门脚本一发现红就**退出**，不要靠人肉看输出。
  ② `audit_motion` 报我 `[裸时长] const add = spot.suggestedDuration + (leg !== undefined ? leg.duration : 0)`
  ——**是扫描器的歧义，不是真违规**：`duration\s*:\s*\d` 这条键位正则把三元表达式的冒号
  当成了对象键。`ai/` 在 W3 下"硬写数字照样报"，所以躲不掉。
  我选择**改写代码**（拆成 `let legMinutes = 0; if (leg !== undefined) { legMinutes = leg.duration; }`）
  而**不动这把尺**：它有 30 条 selftest 断言、五张白名单，为绕一条误报去收紧正则，
  风险大于收益；且拆开的写法本身更直白。尺的这条歧义留在此处备查，
  下次谁再撞上不用重新推一遍。

#### 续 90（2026-11-03）T9 深色逐屏走查：没再翻出"没有边界的卡"，但逼出一条漂了的文案

用工程里**已有**的 `--ps darkprobe 1` 探针（App 级 setColorMode，不动用户系统主题），
16 个深链路由逐屏抓帧 + 量逐行中位亮度台阶。色阶参照：canvas=18 / elevated=30 / subtle=35 / panel=40。

- **没有再发现续 88 那类缺陷。** 两处读数接近单层黑，**是看了图才没误报的**：
  - `SpotPick` 90% 单层 ⇒ 这一屏本来就是**列表不是卡片**（吸顶条有面、行是文字 + 圆环指示器），
    平是对的，不该"修"成卡片；
  - `AreaMore` 95% 单层 ⇒ 深链进来是**空态**（没有城市上下文），居中图标 + 衬线标题 + 正文 + 返回钮，正常。
  与 [[visual-diff-name-the-effect-before-measuring]] 同族：**先问这是不是设计意图，再决定要不要量它。**
- **两条本轮确实没量到**（别当已覆盖）：`EditItinerary` 深链落"没有带进行程"兜底
  （要 `{tripId,dayIndex}` 对象，want 的 string 传不进去）、`Review` 落空态
  （要"已结束 + 有活动打卡"的行程）⇒ 这两屏的深色分层未测。
- 占位串（`!!` / `undefined` / `NaN`）16 屏全 0。
- **逼出一条真缺陷并修掉**：屏4 与屏5b 的空态文案是**同一句话手抄两份、已经漂了**
  ——`SpotPickPage` 写「首批支持北京、上海、广州、深圳」、`AreaMorePage` 多了「杨凌」；
  而且 Stage 2 之后任意地图可查城市都能实时取数，「首批支持这五城」**把产品能力说小了**。
  收成 `Cities.seedCityListText()` 从 `SUPPORTED_CITIES` 生成（加一座城就自动进文案），
  两份都改成「内置精选…；其他城市走地图服务实时取数」。
  真机复拍 `AreaMore`：新文案两行完整渲染、底边 y=1661（屏高 2690）未溢出。
  **屏4 那处同函数同写法，未单独实拍**（要造一座"内置但无景点"的城市才有画面）。
- 闸门：真机 hypium **199/199**、十五把静态尺 + 七套离线断言全 rc=0、双 HAP BUILD SUCCESSFUL。
- **续 88 那次改色的对比度回算（我自己引入的风险，必须自己量）**：把卡片从 `canvas`(#121212)
  改成 `surface_elevated`(#1E1E1E) 等于**把卡内所有文字垫到更亮的底上**，对比度必然下降。
  按 `color.json` 真值精算（带 alpha 的先合成）六组配对，对画布 → 对卡面：
  `ink 16.76→14.91`、`body 7.92→7.05`、`muted 6.46→5.74`、`faint 5.46→4.86`、
  `primary 5.14→4.57`、`danger 5.50→4.89` ⇒ **全部仍过 AA 正文 4.5**。
  再用设备侧对比度尺做像素复核（dump + jpeg 配同一帧）：深色行程页 **57 个文本节点、低于阈值 0 处**
  （另有 2 框判为未画字/背景边界、8 框被实底遮住，按尺的规矩不计）。
  **余量最薄的是 `primary` 4.57**（AA 线只高 0.07）——以后 `primary` 或 `surface_elevated`
  任何一方被调暗，第一个破线的就是它，改这两枚色值前必须先复算这一组。

#### 续 91（2026-11-03）D10b 收口：预选数量与承载能力对齐，通勤不再编造

续 89 把当日负载预算放进**生成器**（装不下就跳过），这修好了超载日，却换来一个更隐蔽的问题：
**用户亲手选的站会被静默丢掉**。手工在屏4 勾 12 站时，用户要的是"这些我都要"，
少排了就得说出来，而不是让选择人间蒸发。所以本轮把收口挪回**预选**这一层：

- **生成器恢复"全排"**：选中的站一个不丢，装不下就照实超窗——屏8 的负载条与「去减一站」
  本来就是为这个状态设计的。只在 GeneratingPage 加一条**兜底告知**：实排少于选中时，
  toast 写清「这几天排不下 N 个景点」（排得下就完全不出现）。
- **`PlanAutoPick.pickSpotsForDays`**：按「生成器同一套分天规则」反算最大可容纳量 N，再取前 N 个。
  三条中间设计被真机否掉，记录如下（都不要再走一遍）：
  ① 只按热度排 + 预算跳过 ⇒ 预选被吃到 4 个（八达岭 60km 排在第 2 位，第 1 天直接爆）；
  ② 每天内部"就近贪心" ⇒ 预选的**分组**与生成器的 quota 切法错位，同一批站被拆进不同天，
     Day2/Day3 各 15.4h（超建议 5.4h）；
  ③ 先把**候选池整体按就近成串重排**、再套同一套 chunk 规则 ⇒ 两边分组一致（采用）。
- **通勤估算收成一处**（新 `utils/Transit.ets`）：此前离线合成为**每一段**都写死
  「地铁 22 分钟 · 2 站」——中关村→八达岭 60km 与故宫→景山 1km 报同一句话，属于凭空编造。
  现在预选与合成同读 `Transit.minutes`（直线 × 1.2 ÷ 30km/h + 8min 接驳），
  文案改成「约 X km」，不再编站数（站数是查出来的，不是算出来的）。
- **真机复测**（同一条输入「北京 3天2晚 2人」、端侧合成、零 LLM 花费）：
  日志 `多日收口 3天 预选10站` → `spots=10` → 落库，**没有「排不下」那一行**（= 10 站全排进）；
  三天负载 `8.0h / 8.4h / 8.4h` 全部 ≤10h；Day1 前两站南锣鼓巷→什刹海，
  通勤 `步行 9分钟 · 约 0.6km`、`步行 10分钟 · 约 0.9km`（改前是「地铁 22分钟 · 2 站」）。
  对照改前：预选 12、实排 6、6 站静默丢弃、`今日 13.7h · 超建议 3.7h`。
- **测试改成成对的两条**（先前那条"单日负载在窗口内"被更准的契约取代）：
  `offline_places_every_selected_spot`（12 站长停留 → 实排 9：9:00 起排、20:00 后不再起新站
  是物理上限，且**不许时间回卷**）与 `offline_preselected_plan_fits_window`
  （预选 N 必须 N 全排进且每天 ≤ 窗口）。**一条防丢、一条防虚报**，缺哪条都能被另一面糊弄过去。
- **一处测量教训**：我第一次用 `dumpLayout` 数每屏站点，读到 6（预选 10），差点判成"还在丢站"。
  dump 只含**已渲染**节点，列表虚拟化下的屏外项不在树里——真判据是日志里的 `spots=10`
  与「排不下」缺省。与 [[hdc-dump-only-contains-rendered-nodes]] 同一条。
- 闸门：真机 hypium **200/200**（新增 2 例）、十五把静态尺 + 七套离线断言全 rc=0
  （`verify_trip_intent.sh` 的离线拷贝清单补了 `utils/Transit.ets`，否则 TS2307）。

#### 续 92（2026-11-03）T9 顶栏磨砂逐页复核：8 页里 4 页出图、4 页内容根本不从栏下过

方法：每页深链进入 → 抓静止帧 → fling 两次 → 抓滚动帧，比**栏带（y 120–300）**的平均亮度差。
判据在行程格标定过：出磨砂约 −9.5，且必须同时确认内容真的位移了（否则"没变"可能只是没滚动）。

| 页 | 静止 | 滚动 | Δ | 结论 |
| --- | --- | --- | --- | --- |
| TripInput（屏2） | 250.7 | 241.0 | **−9.6** | 出磨砂 |
| StayPick（屏5） | 249.9 | 240.2 | **−9.7** | 出磨砂 |
| Itinerary（屏8） | 248.0 | 238.2 | **−9.8** | 出磨砂 |
| Trips（行程格） | 248.3 | 238.8 | **−9.5** | 出磨砂 |
| Expense（费用） | 250.7 | 250.7 | 0.0 | 内容位移了，但栏带**逐像素不变** |
| Share（屏16） | 249.5 | 249.5 | 0.0 | 同上 |
| Badges（勋章） | 246.3 | 246.3 | 0.0 | 同上 |
| Mine（我的） | 249.5 | 249.5 | 0.0 | 同上 |

- 后四页逐帧看过（Badges 那张）：**标题区是固定的页面头、列表从页头之下才开始**
  ——内容从不经过栏下，磨砂自然没有可糊的东西。Δ 恰好 0.0（逐像素相同）也印证"栏带里什么都没动"。
- **因此这四页无法区分"接线没生效"与"布局本来就不过栏"**：两种情况的视觉结果完全一样。
  记录为**未验**，不要当成"已验通过"。若以后把这四页改成沉浸式（内容从栏下过），
  必须重新量这四页——那时 Δ 才会真正检验 `scrollable`/`scrolled` 有没有接上。
- **要不要让这四页也沉浸**属设计取舍（会不会把列表顶进状态栏、页头要不要变成滚动内容），
  **没有替用户拍**；本轮只把现状与人眼证据记下来。
- 复查工具留在 `/tmp/blur_pages.py`（本机重启即丢）：每页都要判"内容是否位移"，
  只看栏带会把手滑当成"没生效"。

#### 续 93（2026-11-03）D6 收口：订阅档上限真的按月了

`bff/src/services/quota.js` 原先是 `DAILY_CAP=20` + `started_at >= date('now','start of day')`，
而商业化方案 §2 与**付费页自己的文案**都写「20 次/**月**」——一个月最多可跑 600 次，
成本敞口差约 30 倍，且与自家文案自相矛盾。

- 改：`MONTHLY_CAP=20` + `started_at >= date('now','start of month')`。
  **响应字段名 `usedToday` / `dailyCap` 保持不变**——端侧 `EntitlementStore.canGenerate()` 直接读这两个键，
  改名要连端侧一起动，而 BFF 还没部署、改名收益为零；口径已按月，名字留作历史兼容（文件头写明了）。
- 新增 `bff/test/quota-window.test.js` 两例：本月成功 3 次 + 上月 3 次 + 本月失败 1 次 ⇒ `usedToday=3`；
  本月满 20 次 ⇒ 订阅档不再放行、退到赠送档（**第一次写这条时我把断言写成 `null`，跑红才发现
  「用满后退到 gift」才是既有设计**——测试先跑红也拦住了我按想象改产品行为）。
- 探针 `tools/bff_commercial_probe.sh` 的 D6 判据同步改口径：窗口在 HTTP 上看不出来，
  由单测断言；探针只钉 `dailyCap===20`。复跑：**必守行为 14/15**（较上轮 +1），
  支付守卫缺陷从 7 条降到 **6 条**（D1/D2/D3/D4/D5/D7），D8 的重复收据 500 仍在。
- `bff: npm test` **44/44**。BFF 仍未部署（属用户的基建决定），端侧不受影响。

#### 续 94（2026-11-03）D8 收口：收据重放改成幂等，不再把约束异常抛成 500

`subscription.purchase_token` 有 UNIQUE 约束，而 `/v1/iap/verify` 是裸 INSERT：
客户端网络抖动后重试同一张收据，会看到 `500 SQLITE_CONSTRAINT_UNIQUE`——
明明已经买成功了，却被报成服务端错误。

- 改：订阅与通行证两条路径都先查收据是否已记账，已有就不再写、照常返回当前权益。
  收据是唯一凭据，重放的正确语义是「告诉你现在有什么」，不是再记一单。
- 新增 `bff/test/iap-idempotency.test.js` 两例（订阅、通行证各一）：两次都 200，
  且 `subscription` / `order` 各只有一行。
- 探针复跑：**必守行为 15/15**（较上轮 +1，`同一收据重复提交不把服务打成 500` 转绿），
  支付守卫缺陷仍 **6 条**（D1/D2/D3/D4/D5/D7）——这六条全部依赖真实 IAP 凭证或产品口径，
  不是本轮能自行闭环的。`bff: npm test` **46/46**。

#### 续 95（2026-11-03）契约 v2 T6：间距档改用契约名，**逐坐标与逐像素都验过零变化**

此前实现名与契约名**整体错一档**（契约 xxs 在实现里叫 xs、契约 xs 叫 sm……），
跨 App 复制一段组件时同一个 `md` 在有据是 20、在有径是 12，肉眼看不出、只在排版上错位。

- **改法**：两趟占位符替换（`__A..__F` 中转，避开 xs→xxs 与 sm→xs 这种环形撞名），
  映射按**值**一一对应：`xs(4)→xxs`、`sm(8)→xs`、`md(12)→sm`、`lg(16)→base`、
  `xl(24)→lg`、`fiveXl(48)→xxl`；`twoXl`/`fourXl`/`lgLoose`/`threeXl`/`bottomReserve` 零消费方，直接删。
  共改 **645 个调用点 / 36 个文件**（`entry/src/main/ets` 与 `entry/src/ohosTest` 两棵树都改）。
- **三条工具坑（都当场纠正）**：① zsh 不对未加引号的变量做分词，`perl ... $FILES` 把整串当成一个文件名
  （`File name too long`），**所以第一次跑其实什么都没改**——看到报错必须回读计数确认；
  ② macOS 的 BSD `grep` 不认 `-Z`，`grep -rlZ | xargs -0` 同样失效，最后用 `find -exec perl` 才成；
  ③ 只改 `entry/src/main` 会漏掉 `entry/src/ohosTest`（FamilyProbePage 里有一处 `SpaceTokens.md`），
  漏了它就会在测试页里把 `md` 从 12 变成 20。
- **零变化的证据（不是"看着没变"）**：
  - `audit_geometry` 的 `SPACE_ALIAS` 改成恒等后实跑 **偏差 0 项**（契约八档 ⇄ `SpaceTokens` 逐值相等）；
  - **真机 A/B**：`git stash` 出改名前产物与改名后产物，同一屏（行程格、同一份真数据）各抓一帧 + 一份 dump。
    结果：**61 个节点对 61 个节点，全部内容节点坐标完全一致**，唯一差异是状态栏时钟/电量（19:07↔19:08、81%↔82%）；
    裁掉状态栏后**像素差均值 0.000、非零像素占比 0.0%**（最大差 4 属 JPEG 噪声）。
  - `ALLOWED_SPACINGS` 收成契约八档 + 0（删 18/28/94）；新增 hypium `SpaceTokensContract`
    钉住八档值并断言 18/28/94 不在封闭集里。
- 闸门：真机 hypium **201/201**、十五把静态尺 + 七套离线断言全 rc=0、双 HAP BUILD SUCCESSFUL。
- 未做：契约里的**语义别名**（itemGap/blockGap/sectionGap/pagePadding…）本轮没有新增——
  它们必须有 ≥1 个真消费方才值得存在，而逐处判定"这处 16 是页面内缩还是卡片内边距"属于逐屏审美判断，
  不是机械改名。留作后续在具体页面动工时随用随加，避免又造一批零消费的字段。

#### 续 96（2026-11-03）屏4 的「建议上限」终于跟着节奏档走

屏4 的计数行、进度环、无障碍名、超量劝告**各自写了一遍 `天数 × 4`**，完全忽略用户选的节奏：
轻松档（每天 3 站）被劝到 4、紧凑档（每天 6 站）反而被当成超量。四处口径不一，且都与
`PaceRule.dailyCap`（预选与生成器都在用）对不上——又是「同一件事的第二份实现」。

- 新增 `PlanAutoPick.capacityOf(days, paces)`：天 × 每日上限；**多选节奏取最大档**
  （提示不该比用户自己选的更严）；未选节奏时按标准档 4。
- 屏4 四处统一改读 `this.capacity`（在 `load()` 里按草稿的 paces 算一次）。
- 回归：`TripIntent.test` 里补 6 条断言（relaxed 3 天=9、standard=12、packed=18、
  多选取最大=18、空列表=12、天数 0 时不小于 1）。这组能区分新旧实现（旧代码一律 12）。
- 真机：深链进屏4 读数「已选 0 / 可用 1 天 · 建议上限 4 个」——**值确实在渲染**，
  但这一例是标准档（新旧算法同值），**节奏档差异只有单测证据，没有真机画面**；
  要在真机上看到 9/18 需要走屏3 勾轻松或紧凑，本轮没走。
- 闸门：真机 hypium **201/201**（新断言并入既有用例，条数不变）、
  十五把静态尺 + 七套离线断言全 rc=0、双 HAP BUILD SUCCESSFUL。

#### 续 97（2026-11-03）地图城市的「无需预约」是编的——本地合成与 ICS 都改口

`Spot.booking.requiresBooking` 对地图来源的城市恒为 `false`，但那个 `false` 的含义是**没查过**
（MapKit 不返回预约字段），不是「查过、不需要预约」。而本地合成把它当成了后者：
`note` 留空、`status=NO_NEED`，于是屏8/屏10 与导出的 `.ics` 一路说「无需预约」。
提示词规则 15 早就要求真模型写「以官方为准」，**本地合成是唯一的漏网**。

- 改：本地合成对 `isMapCity(destination)` 的城市，给活动 `note` 写「预约信息未获取，以官方为准」；
  `IcsBuilder.statusLabel` 在 `NO_NEED` 且 note 含该句时照实返回它，不再替景点下结论。
  种子城市（预约信息随种子库给出）不受影响。
- 回归：`LlmPipeline.test` 新增 `map_city_never_claims_no_booking_needed`——
  西安（地图城）的活动 note 含该句、`statusLabel` 返回它；北京（种子城）note 仍为空、仍说「无需预约」。
- **真机侧证**（西安 1 天，端侧合成零 LLM）：同一次生成里通勤已变成
  「打车 89分钟 · 约 33.7km」「打车 91分钟 · 约 34.8km」——距 34km 的两站之间，
  旧代码报的是「地铁 22分钟 · 2 站」。
- **顺带暴露一条单日质量问题（查过断言后判定：不改，属产品口径）**：1 天预选仍按**热度**取点、
  不做就近成串，于是西安 1 天排成 秦始皇帝陵(临潼)→城墙(新城)→大雁塔(雁塔)，一天里有 3 小时在车上。
  但离线断言（`TripIntent.test` 的 `single_day_pick_trims_for_commute_and_meals`）**刻意钉住了
  "热度优先"**：`far[0].spotId === 'f1'` 要求那个高热度远站在列、且排在首位的语义不能变。
  也就是说「1 天要不要为了少坐车而放弃最热的那一站」是产品取舍，不是缺陷修复；
  多日路径（续 91）用 `clusterOrder` 是因为那边本来就没有"首站必须是最高热度"的约定。
  **没有替用户拍**，只在文档里留下这条判据与代价。
- 闸门：真机 hypium **202/202**、十五把静态尺 + 七套离线断言全 rc=0、双 HAP BUILD SUCCESSFUL。

#### 续 98（2026-11-03）设备 RDB 取证：库在 v10、证据列齐、孤儿为 0

上一会话把 `DB_VERSION` 推到 10 后一直没在真机上核过（§4f/续 83 都把它列为未验）。本轮把库拉下来查：

- **路径**（以前几次没找到是因为找错了地方）：`/data/app/el2/100/database/com.youjing.app/entry/rdb/youjing.db`，
  同目录还有 `-wal`（1.2MB）与 `-shm`，**只拉 `.db` 会漏掉 WAL 里的新行**这一条再次成立。
- 读数：`PRAGMA user_version = 10`；`checkin` 的六个打卡证据列
  （`uuid/latitude/longitude/accuracy_m/distance_m/source`）**全部在位**；
  `trip=24`、`checkin=4`、`expense=0`；
  **checkin / expense 的孤儿行各 0**（v9 那次一次性清理确实生效，之后删行程也级联了）。
- **能说到哪一步**：库目录是 2026-10-23 建的、里面装着本轮生成的行程，说明 v10 是**在已有数据的库上升级**上去的，
  不是全新装出来的；但**升级前的版本号我没有留证**（没有在迁移前抓一次 `user_version`），
  所以"v9→v10 的升级过程"是从终态反推的，不是过程观测。实验级的迁移回归仍缺一次
  「拿一份旧版本库 → 升级 → 逐表比对」。
- 顺带确认：`expense=0` 是因为历史费用都挂在已被删除的行程上，随级联清掉了，不是本轮代码问题。

#### 续 99（2026-11-03）补齐深色「旅行回顾」+ 五个 dock 页回归（T9 收尾证据）

- **深色「旅行回顾」拍到了**（此前是 T9 两处未覆盖之一，另一处 `EditItinerary` 仍未覆盖）：
  先用 RDB 找出"已结束且有打卡"的两条杨凌行程，从行程格滚到第 7 屏点进「可回顾」卡片。
  屏上读到 `2 / 9`、`本次收下 2 枚章`、两条 `排定 · 打卡` 行，**占位串 0**；
  帧看过后确认深色分层正常（卡面亮于画布、勾选态与文字层级清楚），无需改动。
  进入路径本身也值得记：行程列表按 `updated_at desc` 排，老行程要**滚动**才找得到，
  直接 dump 首屏会误判"没有可回顾的行程"。
- **五个 dock 页浅色回归**（规划 / 费用 / 我的 / 地图 / 行程）：
  全部**占位串 0**。三条读数的解释（免得下次当缺陷）：
  ① 费用页是**合法空态**（"今天还没有记录"/"最近记账"为空）——历史费用都挂在已删行程上，
     随 v9 的级联清理一起没了；
  ② 地图页停在**西安那条 1 天行程**，符合 `ACTIVE_TRIP_KEY` 跟随"最后打开"的口径；
  ③ 行程页 dump 里的 `33.000000` 是 **`Progress` 节点的值被 dumpLayout 报成 text**，
     不是数字漏进界面（§5ci 第十四轮已定案，这次又遇到一次）。
- 仍未覆盖：`EditItinerary`（要 `{tripId,dayIndex}` 对象，且「去减一站」入口在负载收口后
  只在真超载时出现）；顶栏磨砂除已测的 8 页外未逐页复测。

#### 续 100（2026-11-03）手选超载这条路还活着 + 屏9 首次进画面

续 91 把预选收口后，有一条必须确认的反面：**用户手选的站被排不下时，超载提示与出口还在不在**。
本轮把整条手选链走了一遍（屏2 → 屏3 四问选「紧凑」→ 屏4 手点 5 个圆环 → 屏5 就住这里 → 生成）：

- **屏4 的 `capacityOf` 在真机上第一次显出非标准档**：`已选 5 / 可用 3 天 · 建议上限 **18** 个`
  ——紧凑档 6/天 × 3 天。旧代码这里恒为 12（续 96 修的正是它），**这条补上了续 96 缺的真机画面**。
- **超载与出口都在**：Day 1 排出 天坛 09:00(2.5h) + 环球 11:45(8h) ⇒
  `今日 11.6h · 超建议 1.6h` + `去减一站` 出现。即「自动预选不虚报、手选超了如实报」两条同时成立。
- **屏9「编辑行程」首次进画面**（此前 T9 两处未覆盖之一，从「去减一站」进来）：
  `Day 1 · 11月03日`、`2 个节点`、两行带六点把手与时间轴节点、行间 `打车 65分钟 · 约 23.6km`、
  钉底 `撤销 / 保存修改`，**占位串 0**，版式正常（帧已存）。
- **屏9 的深色形态也拍到了**（同一条超载行程：`route Itinerary` 落最近一条 → `去减一站` → 屏9）：
  行卡面在近黑底上呈亮面板（续 88 把卡片改回 `surfaceElevated` 的效果在这里同样成立）、
  时间轴节点/六点把手/替换与删除图标都清晰可辨、钉底动作条与 dock 正常。
  至此**上一会话列的"两处深色未覆盖"（回顾、屏9）全部补上**。
- 仍未覆盖：顶栏磨砂除已测 8 页外未逐页复测；对比度尺只跑了行程页一屏。
- 顺带一条设备操作经验：屏4 的圆环菜单**用坐标点行右侧（x≈1048）**比按文本找更稳，
  菜单项在 dump 里成对出现，要用「设为必去」这种独有词定位。

#### 续 101（2026-11-03）对比度尺跨路由复跑：浅色 8 屏 0 低；深色 3 处是已裁决的 dock 蓝

- **浅色 8 条路由**（TripInput / SpotPick / StayPick / Itinerary / Expense / Trips / Badges / Mine）：
  **全部 0 处低于阈值**（节点数 23–56）。这条同时覆盖了续 88 换卡面后的浅色影响——
  按 token 精算最紧的是 `muted` on `surfaceElevated` = 5.10（`faint` 2.49 本来就在线上方，
  且它的用途是装饰性文字，契约如此）。
- **深色 5 条路由**：Expense / Mine 0 低；TripInput / StayPick / Itinerary 各 1 低，
  读数 **4.39–4.40:1、框高 12vp、文本「规划」**——这是 **dock 选中态标签**，
  即用户 2026-10-26 已明确"维持 `#0A84FF` 不改"的那一条（§4i / 轮 90 记录 4.34–4.49）。
  **不是新缺陷，也没再翻旧账。**
- **方法账（这一轮我自己踩的）**：第一版扫的时候没做前台断言，`Trips` 那一屏拍到的是
  **系统通知栏**（抖音通知「刚刚」），于是报出"1 处 4.20:1"——那是抖音的时间戳，不是我们的界面。
  加上"dump 里必须出现 规划/费用/我的/地图 这四个 dock 词"的前台守卫后重跑，8 屏全 0。
  与 [[assert-current-screen-before-each-action]] 同族：**量之前先证明自己在量对的东西**。

#### 续 102（2026-11-03）BFF 上线自检：把两条阻断项做成会自己红的闸门

BFF 能不能上线，此前只散落在分析文档的缺陷表里，没有可执行入口。新增 `bff/scripts/preflight.mjs`
（`cd bff && npm run preflight`），只回答一个问题：**现在暴露到公网会不会漏钱/泄密**。

- 六项检查：JWT_SECRET 非缺省/非示例、DEEPSEEK_API_KEY 已配、IAP 校验非恒真桩、
  `/v1/iap` 有统一鉴权且 notify 验签、DB 路径可配置、Prompt/Schema 生成物在位；本地有实例时顺带探一次 `/health`。
- **当前结果：通过 3 · 警告 1 · 阻断 2**（IAP 恒真桩、`/v1/iap` 未挂鉴权）。
  退出码 1 是**真话不是坏闸**，README 里写明了"不要为了让它变绿去改它"。
- **闸门自己做过反证**（照本项目规矩）：
  喂示例密钥 → 报 `FAIL JWT_SECRET 仍是示例值`；喂空 API Key → 报 `FAIL DEEPSEEK_API_KEY 未配置`；
  还原真实配置 → 两项转 PASS、阻断仍为 2。**它抓得到，读数才算数。**
- 自检覆盖不到、须人工确认的三件：TLS 终止、按 IP/账号限流、日志脱敏
  （请求体里有行程参数，原样落盘等于把用户行程写进日志）。
- 闸门：`bff: npm test` 46/46 不受影响；端侧无改动。

#### 续 103（2026-11-03）端侧→BFF 第一次真机跑通，并当场抓到一个会删数据的缺陷

到这一轮为止，「端侧→BFF」这一段**一次都没在真机上跑过**（BFF 未部署）。这轮用本机把这条缝补上：
Mac 的局域网地址是 `192.168.2.1`、手机是 `192.168.2.3`，同一网段，够得着。

- **做法**：把 `bff/` 拷到 `/tmp/bff-live`（不碰开发库），旁边起一个桩上游（返回夹具 Trip，
  按请求里出现的日期回填当天，**零 LLM 花费**）；临时把本机 skip-worktree 的
  `ApiConfig` 指到 `http://192.168.2.1:3001` 且 `DEV_SKIP_BFF:false`，重编装机跑一句话生成。
- **跑通了什么（日志逐条）**：`DeviceActivator: 设备激活成功 token=213字符`（真实跨设备 HTTP + JWT）；
  BFF `[trip] account=1 prompt=rich response_format=json_object`（rich 请求体按契约到达）；
  桩 `[stub] hit day=2026-11-03`（日期真的从用户消息传过来）；端侧 `生成成功 attempt=1 days=1`
  ⇒ **激活 / 票据 / rich 载荷 / Schema 校验 / 额度扣减 全链路成立**，此前只有本机 curl 和单测证据。
- **当场抓到的真缺陷（会删数据）**：模型返回的 `id` 被 `TripParser` 原样接受，而
  `TripDao.saveTrip` 是**按 id 先删后插**。桩两次都返回夹具的固定 id `trip-test` ——
  也就是说**第二次生成会把第一次那条行程连同它的天/活动整片删掉**，用户看到的是
  "新行程把旧的顶掉了"，且没有任何提示。真模型同样可能复用 id（`trip-001`、日期式 id 等）。
- **修法**：解析器对输入保持忠实（`TripParser.test` 仍断言 `trip-mock-kyoto`），
  只在**落库前的唯一漏斗** `LlmClient.generateTrip` 里换成本地主键
  `trip-${Date.now()}-${random6}`。活动 id 只在行程内唯一，保持模型给的不动。
- **真机复验**：修前两次都落 `trip-test`；修后连续两次生成落
  `trip-1793706219020-1d5lwm` 与 `trip-1793706261201-lzbt5s`，**拉库确认两条都在**（trip 总数 28）。
  新增 hypium `generated_trip_id_is_minted_locally`（固定 id 传输连生两次 ⇒ 两个 id 不同）。
- 收尾：`ApiConfig` 还原（skip-worktree 未破）、按源码重编重装、本机 BFF/桩进程已停、`/tmp/bff-live` 已删。
- 闸门：真机 hypium **203/203**、十五把静态尺 + 七套离线断言全 rc=0、bff 46/46。

#### 续 104（2026-11-03）同一套联调抓到 P0：权益缓存过期后持票用户被永久挡在付费页

续 103 把端侧→BFF 跑通之后，接着用同一套环境验错误路径，结果第一步就撞上一条真缺陷：

- **症状**：配好 BFF 后连续 4 次生成**全部直接落付费页**，而 **BFF 日志是空的、桩一次都没被调用**
  ——说明请求根本没发出去，是端侧门禁自己挡的。
- **根因是两处「各自合理」的组合**：① `EntitlementStore` 的缓存 TTL 只有 **5 分钟**；
  ② 门禁 `canGenerate()` 在缓存过期时直接 `return false`；
  ③ `DeviceActivator.activate()` 看到**票据还在就 return true**，从不刷新权益。
  于是冷启一次、过 5 分钟再点生成 ⇒ 永远进付费页，**而用户的票据与额度其实都好好的**。
  这条在 B 档（无 BFF）看不出来，一旦部署就会在第一天全体用户身上发作。
- **修法（两端各一处）**：
  1. `DeviceActivator.activate()` 在「已激活」分支改为调用新的 `refreshEntitlement()`
     —— 用现有票据 `GET /v1/entitlement` 刷新缓存；回 401 说明票据真失效，清票据让下次走完整激活。
  2. `EntitlementStore.canGenerate()` 在**缓存过期但票据还在**时返回 true，把判断交给服务端
     （真用尽会回 402，端侧照样跳付费页）——过期不等于没额度。
- **真机五连跑（同一套 BFF+桩，桩零花费）**：
  run1 旧票据刷新遇 401 → 清票据 → 落付费页（预期的一步恢复）；
  run2 重新激活 `token=213字符` → 生成成功，`gift 3→2`；
  run3 `权益已刷新 gift=2 used=1/20` → 成功；
  run4 `gift=1 used=2/20` → 成功；
  run5 `gift=0 used=3/20` → **`生成失败 code=6002: 生成额度已用完` → 落付费页**。
  ⇒ **401 恢复、冷启刷新、402 跳付费页三条路径第一次在真机 UI 上验通**（此前只有探针的 HTTP 层证据）。
- 收尾：`ApiConfig` 还原（skip-worktree 未破）、按源码重编重装、BFF/桩进程已停、临时副本已删。
- 闸门：真机 hypium **203/203**、十五把静态尺 + 七套离线断言全 rc=0。
- **仍未验**：401 之后「同一次会话内自动重试成功」没有画面（run1 是清票据后退到付费页，靠下次冷启恢复）；
  若希望不重启就恢复，得在生成失败分支里接一次 `reactivate` 重试，属行为增强、需产品确认。
