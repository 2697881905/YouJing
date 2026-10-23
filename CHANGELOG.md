# Changelog

本文件记录工程级显著变更，格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased]

### Fixed

- 屏14 三个开关与屏2 人数胶囊读屏时不知道是哪个（2026-10-24，对照底稿 aria-label）：
  帧 d04983a4 给的是「日历同步开关 / 行程卡片开关 / 提醒开关」，实现里 `Toggle` 只画了状态、
  标题在旁边的 Text 上，读屏念出来是孤零零一个「开关」；屏2 的人数钮帧给「1人/2人/4人」，
  而 `Button(count.toString())` 只念「1」。补 `accessibilityText`：开关用 `${title}开关`
  （拼出来与帧逐字一致），人数钮用 `${count}人`。两处都是官方控件的原生属性，没有加自绘层。
- 屏10 的「换一个时间」是个空承诺（2026-10-24，真机验收）：底稿帧把它和「加入日历提醒」
  并列成节点级动作，实现里只写了 `showDetail = false`——按钮收下面板、什么都不改。
  现接官方 `showTextPickerDialog`：列当日其它站（`13:15 · 天坛公园`），选中即把本站挪到那个位置，
  当日时间槽集合不变、中间各站按槽顺延，与屏9 拖动排序同一套语义（不新造时间、不编通勤腿），
  然后整份聚合根 `TripDao.saveTrip` 落库 + 刷新万能卡片。真机验过往返两次（09:00→13:15→09:00），
  杀进程重进仍是改后的顺序。
  附带一条实测：`bindSheet` 的自定义内容不随父组件 `@State` 重赋值重绘——时间线已经换槽，
  面板还停在打开那一刻的 09:00。所以应用后收起面板，再进就是真值。
- 离线生成器把景点堆在第一天（2026-10-24，真机 + 真机 hypium 验收）：`MockLlmTransport.synthesize`
  按节奏档的 `perDay`（标准 4 个/天）贪心装满再进下一天，于是「3 天 2 晚只选了 2 个景点」
  排出来是第 1 天两个、第 2/3 天全空——用户看到的就是「三天两晚只有头一天有东西」。
  每天名额改成 `min(perDay, ceil(选中数 / 天数))`：2 站 3 天摊成 1/1/0，8 站 3 天摊成 3/3/2，
  上限仍是节奏档，不放松强度。屏6 复测北京 3 天 4 站 = Day1 两站 / Day2 两站 / Day3 空档日
  （空档日文案走上一轮补的空态）。新增 `offline_spreads_spots_across_days` 用例锁住这个契约，
  真机全量回归 41/41 通过（原 40/40）。
- 屏11 费用页可能悄悄显示另一趟行程（2026-10-24，真机验收）：从 dock「费用」进来没有行程上下文，
  页面退到「最近一条」，但整页不写是哪趟——从北京那趟点过去，看到的却是北京 07-01 那趟的
  ¥16,000/3 天。hero 第一行补 `${目的地} · ${起} – ${止}`。
  先试过挂到顶栏 `subTitle`，真机量下来异步到达后顶栏不跟着重建（同一份状态，正文变了、栏没变），
  所以写进正文而不是留一个不生效的口子。
- 屏16 分享页的「行程纸」在浅色档看不见边界（2026-10-24，真机浅色）：
  `route_bg_top/bottom` 浅色档是白→#F1F2F5，压在浅灰卡上等于一块空白。补一条
  `borderSubtle` hairline，两档都读得出这是一块纸。
- 浅色模式下整条 HDS 顶栏标题看不见（2026-10-24，真机浅色复现）：HDS 的标题文字与菜单图标
  一样默认白色（透明栏压在 hero 媒体上的假设），`HdsChrome` 只显式给了 `iconColor`、
  没给 `titleStyle`。真机量过：浅色画布上标题区整块 255,255,255，屏15/屏6/地图页/行程列表
  四页只剩一个返回箭头。补 `titleStyle.mainTitleColor = ink`、`subTitleColor = muted`，
  四页复测标题字色 min 0（真画上去了）。
- 屏8 小面板首站图钉被上边缘裁掉（2026-10-24，真机浅色）：为把视角拉近试过把
  `newLatLngBounds` 的顶部留白从 260px 压到 120px，当场复现裁切——真机上一枚编号图钉
  从锚点往上伸约 260px。回到 280/150 档并把这个取舍写进常量注释：
  625px 高的小面板扣掉留白只剩 ~195px 视带，当日两点相距 7km 时镜头必然退到街区以上，
  要更近只能改小图钉或加高面板（地图页满屏底图不受此限）。
- 离开地图页会杀掉整个 App（2026-10-24，真机复现并验证修复）：`TripMapView.aboutToDisappear`
  里 `events.off('markerClick', cb)` 被 Map Kit 反手用 `undefined` 调了一次回调，
  `marker.getTag()` 抛 `TypeError` 逃出生命周期 → JS 崩溃、进程被系统回收。
  真机栈：`TripMapView.ets:64 ← MapEventManager.ts:204 ← aboutToDisappear`，
  现象是从屏8/dock 地图页返回桌面后 App 直接消失（hilog `Reason:TypeError` + JS_ERROR）。
  修法三条：回调首行判空、注销与覆盖物清理各包 try/catch、异步 `addMarker` 回来先确认组件未拆。
- 屏6 Day 分段栏停在 3 个占位（2026-10-24，真机验收）：`ImmersiveSegmentBar.items` 是数组 @Prop
  但没有 @Watch，`options` 只在 `aboutToAppear` 建一次，异步加载后条目从占位 3 个变成真值 2 个
  时界面不跟——北京 2天1晚 的行程顶栏写着「2天1晚」，下面却挂着 Day 1/2/3。
  items 补 @Watch 重建，并在条目变少时把越界的 `selectedIndex` 收回 0。
- dock 地图页全览把首末站藏进浮层（2026-10-24，真机验收）：`newLatLngBounds` 的留白单位是 px
  且原为组件内常量（260/150，按屏8 那块 625px 高的小面板量的）。满屏底图的地图页沿用这档，
  落点 1 压在分段栏下、落点 2 压在站点条下。留白改成宿主按真机浮层边界传参
  （地图页上下各 600px：分段栏底 487、站点条顶 2101），小面板保持原档。
- 屏6 空档日一片空白（2026-10-24，真机验收）：只选 2 个景点时引擎把两天都排不满，
  Day 2 时间线零行且无任何说明，地图兜底文案还错报「当日仅一站」（该句只讲通勤段数）。
  现在空档日给「这一天还没有安排节点」，摘要按 `activities.length === 0` 先判成「当日暂无安排」。

### Added

- 屏5「帮我选」从取第一篇改成真算距离（2026-10-24，真机验收）：底稿帧 1cd06e03 的按钮写的是
  「帮我选（按通勤最短）」，实现里是 `selectedId = picks[0].area.id`，等于按推荐顺序白拿第一个，
  承诺比行为大。新增 `utils/Geo`（haversine 纯函数，5 条用例走教科书量：1° 纬度 ≈ 111.19km、
  60°N 的 1° 经度是赤道的一半），把屏4 已选景点的坐标取平均直线距离，取最小的一篇。
  按钮文案跟着实际算的东西写「帮我选（离景点最近）」——本项目没有路径规划，
  把直线距离标成「通勤最短」就是谎报导航里程，这处改名请用户过目。
  坐标缺失有兜底（toast + 退回推荐顺序并打 warn）。真机跑北京「故宫 + 天坛」：
  日志 `所选景点可用坐标 2/2` → `帮我选 前门-大栅栏 平均 2.18km targets=2`，
  选出的是**前门-大栅栏**而不是列表第一篇王府井-东城核心，证明是按距离算的、不是顺位。
  真机全量回归 47/47（原 42/42）。
- 屏10 补上底稿顶栏声明的「分享」（2026-10-24，真机验收）：帧 471fcea9 的 title-bar 有
  两个 44 热区——返回与分享，实现里只有官方面板的关闭钮，节点级分享整条缺失。
  现在内容区右上角一枚官方 `Button(Circle, TEXTUAL)` + `sys.symbol.share`，带无障碍名「分享此节点」，
  走 `ShareExporter.shareNode` → `IcsBuilder.nodeSummary`（纯函数）出本站的时间/地址/到达/预约/提醒，
  交系统分享面板。真机拉起验过：标题 `故宫博物院 09:00`，落到华为分享/微信/QQ/钉钉/复制/打印/中转站
  一排目标（只验证拉起面板，未向任何目标发送）。新增 `node_summary_is_one_node_only` 用例，
  真机全量回归 42/42（原 41/41）。面板自带官方关闭钮，所以分享没再伪造一层顶栏。
- 沉浸光感流光第一次真正上屏（2026-10-24，真机验收）：`components/ImmersiveSurface`
  是 2026-10-24 从有据移植的 HDS 双边流光容器（`HdsVisualComponent` +
  `DUAL_EDGE_FLOW_LIGHT_WITH_BACKGROUND_MASK`），但**建完一直没被任何页面挂载**，
  等于 App 里其实没有沉浸光感。现包在屏15 hero 面板外层，真机截图量到卡片下缘
  出现左暖右蓝两道流光弧（三帧哈希不同，确实在动），不支持的设备按既有门禁退回实色。
  其余表面（屏11 预算面板、屏6 地图面板等）要不要同样上流光属视觉取舍，留给用户点单：
  地图面板叠背景蒙层会给瓦片染色，不建议无脑铺。
- 屏1 首启预览卡同档上流光（2026-10-24，真机验收）：有据把 `ImmersiveSurface` 用在引导卡
  （`CircleOnboarding`）上，有径的首启预览卡是同一种表面，跟着同一档语言。
  真机深色一帧：卡片下缘左暖右蓝两道弧，卡内三站一屏放得下、登录按钮未被挤压。

### Fixed

- 屏2 返程日期藏在长按里（2026-10-24，真机验收）：出行日期那格原来 `onClick` 开出发、
  另挂一个**没有任何提示的 `LongPressGesture`** 开返程。底稿这一格只有一个
  `chevron-action`「选择出行日期」入口，长按既不在帧上、用户也不可能发现，
  等于大多数人改不了返程。改成一次点按串两档官方日期弹窗（出发 → 返程，
  第二档的 `start` 直接以下一档为界，返程不可能早于出发），隐藏手势删掉。
  真机走通：点行 → 出发弹窗 2026-07-01 → 确定 → 返程弹窗落在 07-03 → 确定 →
  行内回显 `7月1日 – 7月3日 · 3天2晚`。
- 屏4 景点行整行可点会误触（2026-10-24，真机验收）：底稿这格是
  `<button class="priority-action" aria-label="设为必去">` —— 一个带无障碍动作名的按钮，
  不是「整行可点」。实现里 `cycle()` 挂在整行 `Row.onClick` 上，点景点名字就把优先级改了，
  且指示器只是个裸 Column（不可聚焦、读屏念不出动作）。现在热区收回指示器、
  外面包官方 `Button`（Circle + TEXTUAL 档，不出额外表面），触点放大到 `minTouchTarget`，
  并按当前档如实给无障碍名（未选「设为必去」/ 必「改为想去」/ 想「改为可去」/ 可「标为普通」）。
  真机复测：点行名 `已选` 保持 0（不再误触），点指示器 `已选 1` 且角标变「必」。
- 屏15 流光滑色档结成一坨品红（2026-10-24，真机浅色复现并修）：`ImmersiveSurface` 的
  默认配色是从有据带过来的深色值（白 77% 边光 + 紫蓝 56% 二束），压在白卡上
  两个上角变成蓝紫色块。改成按 `isDarkMode` 分档：浅色走品牌蓝（边光 50%/40%、
  蒙层 4%→8%），深色保持有据原值；场景参数从 `aboutToAppear` 一次性设置改成
  `applyScene()`，深浅档切换（`@Watch`）会重设，不留旧配色。
  真机两档各拍一帧复测：浅色边缘最饱和像素从品红变成 (108,182,231) 蓝，
  深色左缘仍有 (86,96,132) 冷光、画布 18,18,18 未被蒙层染色。

### Added

- 屏9 编辑页补齐底稿声明的两个动作（2026-10-24，真机验收）：帧 ebe57eac 的交互清单是
  `完成编辑 / 替换景点 / 移除景点 / 补选景点 / 撤销修改 / 保存修改`，实现里只有前四个——
  行程进了编辑态**只能减不能加**，删错也没有回退。
  - 补选景点：复用同一张候选面板（`replaceIdx = -1` 走追加分支），接在当日末尾、
    开始时间取上一站结束 + 15 分钟缓冲，再 `reflowTimes()` 重排时间槽；
    不编通勤腿（新站点没有真实距离，`transport` 留空，时间线本就不画这一段）。
  - 撤销修改：每次移动/删除/替换/补选前压一份 `Activity[]` 快照，弹栈回退。
    菜单项**常驻**而不是按有无历史显隐——顶栏不随异步状态重建（屏11 副标题踩过这个坑），
    动态增减会留下点不出来的死项，所以空历史时如实 toast「还没有可撤销的改动」。
  - 顶栏 `content.menu` 从 1 项变 3 项（完成 / 补选景点 / 撤销修改，官方 maxCount=3）。
  真机：北京 Day1 两站 → 补选颐和园 → `rows=3` → 撤销 → `rows=2`；全程没点「完成」，库未改动。

### Changed

- 屏3 与屏15 的正文迁到官方 `List`（2026-10-24，真机验收）：屏3 题干一个 ListItem、
  每个选项一个 ListItem；屏15 hero / 下一段 / 今日已打卡各成一个 ListItem，
  打卡区改 `ListItemGroup` + 吸顶分组头 + 官方 `.divider()`，不再手排间距。
  顺带删掉屏15 进度条上一处重复的 `.margin({ top: md })`。
- 屏6 行程正文迁到官方 `List`（2026-10-24，真机验收）：原来是 `Scroll > Column` 里手排
  地图面板 + 日标题 + 节点/通勤腿。现在地图面板一个 ListItem，节点与通勤腿各成一个 ListItem，
  日标题挂 `ListItemGroup.header` 并开 `.sticky(StickyStyle.Header)`——底稿写的「吸顶日标题」
  到这里才真的吸顶。面板右下角「全图」从裸 `Text + onClick` 换成官方 `Button`
  （NORMAL 档在瓦片上不出表面色，量到胶囊区与底图同色，改 EMPHASIZED 实底胶囊后读得清）。
  真机复测：北京 3 天 Day1 两站 + 一段通勤渲染与滚动正常，点节点仍能开屏10 详情面板。
- 屏16 分享页迁到官方 `List`（2026-10-24，真机验收）：抬头与行程卡成一个 ListItem，
  两条动作成一个 `ListItemGroup`，行间手画的 `Divider` 换成官方 `.divider()`，
  `optionRow` 去掉 `last` 形参。点击热区从内层 `Column` 抬到 `ListItem` 本体
  （真机 dumpLayout 里两行现在是 `ListItem [87,1431][1049,1626]` 这样的可点节点）。
  顺带补 `options.length >= 2` 的门槛——原来异步到达前就直接索引 `options[0]`。
- 屏5 住哪一片迁到官方 `List`（2026-10-24，真机验收）：地图面板一个 ListItem，三张候选片区卡
  各成一个 ListItem（卡间距留在卡片自己身上）。真机复测北京 11-02 两天：三片落点全在面板内、
  首片选中态蓝描边与勾选正常、第三片可滚出。至此屏3/4/5/6/11/12/15/16 的纵向正文全部走官方
  `List`；还在用 `Scroll` 的只剩横向 chip 轨道（屏8 两行、屏11 分类行）、屏2 表单与屏10 详情面板内部。

### Added

- 真实地图三处落地（2026-10-24，真机验收）：AGC 开通地图服务并重出调试 Profile，
  `module.json5` 补 `ohos.permission.INTERNET`，新增 `components/TripMapView`（Map Kit 底图 +
  落点 + 分天动线 + 深色 `setDayNightMode` + 带错误码的兜底文案）与 `utils/MapStops`
  （行程/景点/片区三类数据收敛成同一份落点，含中国大陆范围粗筛，AI 回写的 0/0 或跑偏坐标直接丢弃）。
  dock「地图」从说明页换成 `pages/MapPage`（全程 / Day N 切换、站点条点选飞镜头、全览）；
  屏8 顶部地图面板与屏5 候选片区卡同时换成真底图（屏5 三片互斥故 `route: false` 不连线）。
  真机实测：花瓣底图出瓦片、无 1002600003，北京行程三站落点与延庆—城区连线正确，
  屏5 西单/前门/王府井三片相对方位正确。

### Added

- 屏5b 全部区域页（2026-10-24，真机验收）：屏5 那行「查看更多区域」原本是不可点的纯文字，
  现在落到 `pages/AreaMorePage`——按 `Area.group` 真字段分组（核心地段/商圈便利/交通枢纽）
  浏览本城 36 片，官方 `Search` 支持区域名/站点/地铁线过滤，官方 `List + ListItemGroup`
  吸顶分组头，行内「选这片」带 Area 出栈；屏5 收到后把它插成首位候选并重排角标与地图落点。
  三列数字与屏5 同口径（到机场/到火车站/餐饮密度），不编路径规划与住宿库存类数据。
  真机走查：北京 36 片 → 选「亮马桥-燕莎」→ 回屏5 首位变它、角标重排、地图三点重铺。
  顺带修一处 `@Builder` 值快照不刷新：picks 的 ForEach key 原来只有 area.id，
  重排名次后第二张卡仍显示「精选 1」，key 补上 `aiRank` 与选中态后正确。

### Added

- 地图落点编号可见（2026-10-24，真机验收）：Map Kit 默认图钉没有序号，一屏多站看不出先后。
  新增 `utils/NumberedPin`，用官方 `OffscreenCanvas` 画「序号 + 白盘 + 品牌色水滴」，
  产出 PixelMap 交给官方 `MarkerOptions.icon` 槽位（不是自绘 UI 组件，只是给官方槽位供素材），
  按「序号 + 颜色」缓存，生成失败退回默认图钉。
  同时纠正 `newLatLngBounds` 留白：单位是 px 不是 vp，且图钉锚点在针尖、圆头往点上方伸一截，
  改为上 260 / 下 150 / 左右 120 px 的非对称留白——此前屏5 首末两片的图钉头被面板上边缘裁掉。
  真机实测：屏5 三片 1 王府井 / 2 前门 / 3 西单 与下方卡片顺序一致且完整入框。

### Changed

- 内置资产补逐条经纬度（2026-10-24）：128 景点 + 144 片区由 Photon(OpenStreetMap) 按名称
  （片区取首个锚定站名）地理编码，WGS84→GCJ02 后写进 `seed/*.jsonl` 新增的 `la/lo` 字段，
  271/272 成功（深圳「宝安青少年宫-滨海文化公园」未编出，该行不落点）。
  `DataSeeder` 景点优先用种子坐标、缺字段才退回区中心，片区不再用 `lookup(city, city)`
  （表里无该键，四城 144 片此前全部落到兜底点）；坐标来源写进 `provenance.source`
  （`seed-v2-geo` / 退回区中心的仍为 `seed-v1`，可信度降为「低」）。
  新增种子版本闸门 `v2-geo-2`：已装机不必清数据，冷启动按 id upsert 回填，真机日志
  「北京 灌入 spots=32 areas=36 …」四城重跑。GCJ02 位移自检：中位 573m、区间 457–633m。

- 屏4 景点列表迁官方 List（2026-10-24，真机验收）：`Scroll + Column + 手排 Divider` 换成
  `List + ListItemGroup`，分组头 `sticky(Header)` 吸顶、行间用官方 `.divider()`、
  组卡背景与圆角挂在 ListItemGroup 上；行 key 补优先级，避免点选后 必/想/可 角标不刷新。
- dock 四项与屏11「记一笔」改官方 Button（2026-10-24，真机验收）：dock 项原来是裸
  `Column + onClick`（无按压态、不可聚焦），现套官方 `Button` TEXTUAL 档，选中色仍走 token；
  「记一笔」44 高 + 1px 描边的自绘 Pill 换官方 Capsule Button。

- 屏3 追问选项卡改官方 Button 档位（2026-10-24，真机验收）：`OptionCard` 原来是
  「surfaceSubtle / primaryTint 底 + 条件 1px primary 描边」的手抄选中态，
  改官方 `Button` + `ButtonStyleMode.EMPHASIZED / NORMAL` 两档，文字色跟档位翻
  （实底蓝上换 onPrimary）。真机实测第 1/4 步五选项，选中「休闲」为官方实底档。

- 屏12 我的行程补真交互并迁官方列表（2026-10-24，真机验收）：右上角放大镜原来是个没有动作的
  死控件，改官方 `Search`（目的地/日期关键词过滤，实测 9 条 → 输入「北京」剩 2 条）；
  列表由 `Scroll + Column + ForEach` 迁到官方 `Refresh + List/ListItem`（下拉重读 RDB、
  `space` 统一卡距、`edgeEffect.Spring`、`cachedCount`）；标题栏副标题给真条数「N 条」。

- 弹层材质一致性与费用分类 chip（2026-10-24）：屏2 城市选择 `bindSheet` 补
  `systemMaterial: getSheetImmersiveMaterial()`，与屏8 两处、屏9、屏11 同档（此前只有它漏掉，
  同一 App 里两种弹层质感）；屏11 费用分类筛选 chip 由自绘胶囊（手挑 primaryTint/描边）
  改官方 `Button` Capsule，选中 EMPHASIZED / 未选 TEXTUAL。

- 选择类 chip 交回官方 Button（2026-10-24，真机验收）：屏2 同行人数（自绘 24vp 圆 +
  primaryTint 底 + 条件描边）→ 官方 `ButtonType.Circle` + `ButtonStyleMode` 选中档；
  地图页 Day 筛选 chip 与底部站点条（自绘胶囊 + 手挑背景色）→ 官方 `ButtonType.Capsule`
  /`Normal` + `buttonStyle`，选中态不再手抄色板，深色模式由系统色板接管。

- 按钮与进度条交回官方控件（2026-10-24，真机验收）：`YoujingButton` 内部由「Row + 自绘
  背景/圆角/描边 + onTouch 手抄按压态」改成官方 `Button`（`ButtonType.Capsule/Normal` +
  `ButtonStyleMode` 三档，按压态与深色色板归系统），14 处调用点签名不变；
  屏3/屏5/屏11/屏12/屏15 六处「两条 Row + layoutWeight 拼的假进度条」换成官方
  `Progress({type: ProgressType.Linear})`。真机实测屏12 进度条与屏5 主/次按钮均为官方样式。

- 全 App 顶栏改官方 HDS 标题栏（2026-10-24，真机验收）：根 `Navigation` → `HdsNavigation`，
  13 个路由页 `NavDestination` → `HdsNavDestination` + `.titleBar(HdsChrome.bar(...))`，
  撤掉全部自绘标题 Row 与自绘返回钮（官方自带）；页内动作（分享 / 编辑 / 完成 / 推荐更多 / 全览）
  改走官方 `content.menu` 圆钮。新增 `design/HdsChrome`（单点构造，带三条有据真机结论：
  menu 图标默认白色必须显式给 token、`maskExtraHeight` 默认 32vp 会糊到内容须压 0、
  blurRadius 只在 GRADIENT_BLUR/IMMERSIVE_GRADIENT_BLUR 下出图）与
  `components/ImmersiveSurface`（HDS 双边流光容器，API≥23 门禁降级）。
  真机实测：屏2/屏8 官方标题栏 + 圆钮菜单出图，深色模式图标色随 token 翻转。

- 小艺预填屏2 补齐人数与预算（2026-10-23，真机验收）：小艺开的是新行程，预算不再沿用上一段
  草稿，统一回到默认 `¥8,000/人`（新增 `common/constants/BudgetConfig` 收敛 3000/12000/500/8000
  四个散落常量）；人数 chip 原固定 1/2/4，现把预填带来的 3、5 等值补进选项并高亮。
  差分实测：暖草稿 `¥5,000` → Skill 预填 `西安/3人` → 屏2 显示 `¥8,000`，chip 为 1/2/3/4。
  仅 App 侧改动，`SKILL.md` 契约未变，无需重新上架 Skill。

- 屏11 费用页迁官方 List 并补记账删除通路（2026-10-24，真机端到端验收）：整页由
  `Scroll + Column + 手排 Divider` 换成 `List` + 两个 `ListItemGroup`（吸顶分组头、
  官方 `.divider()` 行间线、组卡背景圆角挂在组上）；hero 里最后一条「两条 Row 拼的假进度条」
  补成官方 `Progress`（此前漏在六处之外）。`ExpenseDao.delete` 原本同样没有调用方，
  现记账行左滑出删除钮 + `showAlertDialog` 二次确认。
  真机端到端：记一笔 ¥1「验证删除」→ 已花 ¥1、分类「门票 ¥1」→ 左滑 → 确认删除 →
  回到 ¥0 / 今天还没有记录（测试数据已清，用户原数据未动）。

- 行程删除通路补全（2026-10-24，真机验收）：`TripDao.deleteTrip` 自阶段 4 起就没有任何调用方，
  用户删不掉行程。屏12 卡片加官方 `ListItem.swipeAction` 左滑出删除钮，删除前走官方
  `showAlertDialog` 二次确认（文案如实说明「只删本机记录、日历已写入的事件不会自动删除」），
  删后重载列表并 `WidgetSync.refreshAll` 回灌桌面卡片。
  真机实测：左滑出红色 trash、对话框标题「删除这条行程」与「取消/删除」两钮，点取消不删数据。

### Fixed

- 小艺 Skill 真机拉起失败（2026-10-23）：平台日志显示参数正确解析，但 `startAbility` 返回
  `201 The application does not have permission to call the interface.`——手机后台应用无权拉起
  UIAbility（`START_ABILITIES_FROM_BACKGROUND` 仅系统应用；`startSelf()` 仅 PC/2in1）。
  改为 `data/SkillPrefill` 落盘（Preferences `youjing_skill_prefill`，取后即删、2 小时过期），
  `EntryAbility` 在 `contentReady && visible` 时消费并推屏2；Skill 返回 `launched=false` +
  如实 `message`（「已记下…打开有径会自动进入行程规划页并填好这些信息」）。
  `startAbility` 保留为 PC/2in1 的尽力尝试。杭州等四城之外的拒绝行为不变。
  **2026-10-23 16:31 小艺真机复测通过**：回复「已记下：上海，10月24日出发，3天，2人…」；
  16:32 打开有径即落屏2，实测 `上海 / 10月24日–10月26日 / 3天2晚 / 2 位成人`。

### Added

- 小艺 Skill 上架（2026-10-23 16:42，范围「仅自己使用」）：上架记录 `1.0.0`（渠道：资源库），
  控制台 Skill 列表状态「已上架」，即时生效、无需等待审核。发布表单随后自动预置下一版 `1.0.1`；
  后续改动按 `Docs/小艺Skill接入清单.md` §B4 提版重审。
- 小艺 Skill 应用内接入（2026-10-23，真机验收）：API 26 `skillProfiles` 注册 `youjing-plan-trip`；
  `entry/skills/youjing-plan-trip/SKILL.md` 按官方样例给完整 `exec-cli` 命令对象 Schema 与
  `oneOf` 返回值 Schema；`PlanTripSkill.ets` 校验四参后拉起 `EntryAbility`
  （Want 参数 `route/destination/start/days/people`）。HAP 内含 SKILL.md，启动日志
  「Skill 注册 1 个: youjing-plan-trip」；下游屏2 预填真机通过。
  平台侧新建 / 导入步骤见 `Docs/小艺Skill接入清单.md`（需用户操作，真机测试要求 HarmonyOS 7.0 + Beta 小艺）
- 游客数据归户补全：`TripDao.adoptGuestData` 同一事务迁移 `trip` / `expense` / `checkin` 三表
  （此前只迁 `trip`，登录前记的费用与打卡会从屏15 / 旅行中页消失）；真机日志
  `trip=6 expense=1 checkin=1`，费用页「故宫门票 ¥320」与旅行中「故宫博物院 已打卡」均可见
- 桌面卡片账号分区修复：FormExtensionAbility 是独立进程，此前只按游客分区读 RDB，归户后卡片显示空态。
  provider 刷新前先 `AccountStore.init` 恢复 UnionID；新增 `widget/TodayCard.ets` 共享卡片数据映射 +
  `WidgetSync.refreshAll`，主应用在归户 / 生成 / 编辑 / 冷启动后主动回灌，不必等 30 分钟定时。
  真机日志 `Widget.TodayCard: 已刷新卡片 996982405 2*2`，桌面恢复今日三站

- 业务阶段 1–8 落地（2026-10-20 → 2026-10-22，真机验收）：
  - 阶段1/3 数据契约与防线：`model/`（Trip/Spot/Area/PlanParams 接口与枚举）、`ai/TripSchema`（枚举白名单单一事实源）+ `ai/TripParser` 逐字段守卫（错误路径定位到 `days[i].activities[j].field`）
  - 阶段2/4 UI 与存储：设计底稿 39 帧全量落 `pages/`+`components/`+`design/`（46 色 light/dark 双值、衬线字体注册、深色零阴影门控、系统材质沉浸栏）；`data/DatabaseHelper` RdbStore 单例 + 单写通道事务 + 版本驱动迁移
  - 阶段5 内置资产：北上广深种子库（每城 32 景点 / 36 区域，rawfile JSONL）+ `DataSeeder` 首启幂等灌入
  - 阶段6/7 AI 与交互：`ai/PromptBuilder`（Schema 内嵌）+ `ai/LlmClient`（Mock 离线闭环 / HTTP 备选 / 失败重试一次）；屏2–6 多轮选项状态机 `data/PlanDraft` + `data/PlanRepository` 打通到落库
  - 阶段8 账号与分区：`common/config/AccountConfig` + `data/AccountStore`（UnionID 静默登录、失败退本机游客分区、登录态 Preferences 持久化）；DB v1→v2 加 `trip.user_id` 分区列与索引，`TripDao` 列表/详情读按 uid 收口、`adoptGuestData` 游客数据归户
  - 阶段9 系统触达：屏14 Calendar Kit 真写入（预约节点 + 每日全天、按 tripId 幂等清理）；
    今日行程卡片读真 RDB 数据（`data/TodayPlan` 纯函数 + FormExtensionAbility 直读回灌）；
    外部拉起参数通道（`onNewWant` + 屏2 预填回显）为小艺 Skill 接收端就绪
  - 阶段10 屏7 接真错误：`FailInfo{code,detail}` 随路由传入，`common/error/FailureCopy` 做错误码→人话标题
    （纯函数，hypium 覆盖），两条修法改成真能跳的「回选点页/调松节奏」，原始诊断仅 debug 版露出；
    底稿编造的「伏见稻荷与宇治步行超 90 分钟」「打车 ¥3,200」不再对用户说
  - 阶段10 屏5 去假数：区域卡三列原样是卡片序号算出来的（`8 + i * 4` 分钟 / `30 + i * 6` / `9 + i * 7` 家），
    换成 `Area` 真字段「到机场 / 到火车站 / 餐饮密度」；顶部地图卡改成候选片区图例（同城 36 片区
    共用一个城市质心坐标，按经纬度布点就是编位置）；`帮我选（按通勤最短）` → `帮我选（推荐第一片）`
    （处理函数就是取 `picks[0]`）；副信息行 `maxLines` 1→2，最长 30 字的种子行不再被省略号截断；
    角标 `AI 精选 1` → `精选 1`（区域排序是种子库编排，模型只排景点），第二/三名的「交通枢纽」
    改为按 `Area.group` 实取，修掉北京前门、上海外滩、深圳香蜜湖三片 core 被贴错标签
  - 阶段10 补两处功能空洞：屏2「预算档位」原是画死的 55/45 轨道 + 硬编码 ¥8,000（点了没反应），
    改用官方 `Slider`（3,000–12,000/人，默认 8,000 恰落在底稿的 55% 处），值进草稿、
    经 PromptBuilder 带给模型、并决定屏11 预算总额；`PlanDraft.reset()` 从未被调用导致
    连着规划第二程时上一段的选点/住宿区/节奏静默残留，改为静态 `fresh()` 并在
    屏1 首启 CTA 与屏12「创建新行程」两个新建入口调用
  - 阶段10 旅行中：DB v3→v4 加 `checkin` 表（(trip_id,activity_id) 唯一）与 `expense.activity_id`；
    屏15 整页由底稿 mock 改为真数据——当前节点/进度/下一段通勤/行内金额/打卡态全部取真值，
    打卡写库并跨重启保留（刻意不入 Trip 契约：行程是 LLM 生成物，打卡是本机用户态）
  - 阶段10 费用与导出：`expense` 表 v2→v3 迁移 + `ExpenseDao` 按 uid 分区，屏11 hero/分类/最近记账
    取记账真值并补底稿遗漏的「记一笔」Pill；`utils/IcsBuilder` 生成 RFC 5545 `.ics`（VALARM 提前提醒、
    字节折行、CRLF）+ `data/ShareExporter` 走系统分享面板；屏10 详情面板 mock 事实全部换成真值或 `—`
  - 阶段10 浮动 dock 收口：屏8 的内联 dock 提为 `components/FloatingDock`（底稿 39 帧扫描确认
    只有屏8/11/12/15 声明 `dock-item`，屏2–7 规划流与屏16 分享不挂），屏11/12/15 按帧补挂，
    activeIndex 逐屏对表（屏8/15=行程、屏11=费用、屏12=我的）；
    屏8 的 dock 壳同时承接屏14 触达面板的 `bindSheet`（一个节点只能挂一个，Stack 已被屏10 详情占用）；
    屏11 无 tripId 直达时回落到最近一趟行程，不再显示空预算
  - dock「地图」落点页改口：`ComingSoonPage` 不再对用户说「骨架占位 / 路由「Map」将在后续批次落地」，
    改成标题「地图视图」+ 一句实话（要接 Map Kit、需 AGC 开通重签）+「返回行程」；
    底稿只有 dock 里的「地图」一格、没有对应地图屏，已列为待设计（`Docs/INIT_REPORT.md` §4b-6）
  - 桌面卡片真机验收（2026-10-23，用户放置 formId `996982405`）：卡片进程直读 RDB 渲染
    `Day 1 · 10月23日` + 三站 + `还有 1 个需预约节点 · 18:30 前`；点卡片拉起 EntryAbility 落屏8；
    `hdc install -r` 后系统重拉 provider 并回灌，卡片内容不变。顺带补尺寸通路：`onAddForm` 读
    `ohos.extra.param.key.form_dimension`、按 formId 落 preferences、每次回灌带 `dimension`，
    修掉 2×4 的 16 内缩恒走 2×2 默认值的死分支（2×4 未实机放置，仅代码通路）。
    2×2 真机文本区 134vp vs 底稿 328px 画布，标题/footer 被系统省略号截断，列为 §4b-11 待设计决策
  - 回归：hypium 40/40（含 TodayPlan 10 条纯逻辑断言）；RDB/账号/日历分片路径改真机验收
    （原因见 `Docs/INIT_REPORT.md` 已知限制 #10）

- 工程基线初始化（P1–P5，2026-10-15）：
  - 目录骨架（pages/components/model/data/ai/mock/utils/design/common）与架构契约 `Docs/ARCHITECTURE.md`（目录职责/依赖方向/§5.4 差异/命名规范/UI 约定）
  - 技术栈版本锁定 `Docs/TECH_STACK.md`（API 26 / DevEco 26.0.0.851 / hvigor 6.26.8，运行时零依赖基线）
  - 配置层与环境隔离：`common/constants/BuildConfig.ets`、`common/config/ApiConfig.ets`、`common/config/MockConfig.ets`，`.gitignore` 增补签名/密钥防线
  - 日志与错误基线：`common/logger/Logger.ets`（YouJing. 前缀、IS_DEBUG 门控）、`common/error/AppError.ets`、`common/error/ErrorCode.ets`（1xxx–4xxx 区段 14 码），EntryAbility.onError 接入
  - 设计 tokens：`design/ColorTokens|SpaceTokens|FontTokens|MotionTokens.ets`（占位基线值，待 UI 设计定稿替换）

### Changed

- `Docs/小艺Skill接入清单.md` 重写为 API 26 应用内 Skill 指南：旧版指向已下线的 IntentsKit 控制台路径，
  且把「意图声明格式待调研」留在待办里；现记录 `skillProfiles` / SKILL.md / 脚本入口契约、平台侧
  新建 → 真机测试 → 发布流程、已验证据与本地不可直调 Skill 的边界
- 华为账号静默登录接通真 UnionID（2026-10-23，真机验收）：AGC 侧注册应用「有径」
  （APP ID / Client ID `6917619826312400726`、projectId `101653523865420226`），登记调试证书
  SHA256 指纹 `86:6F:…:CF:70`；`AccountConfig.ACCOUNT_KIT_ENABLED` 翻为 `true`。
  首次接通仍报 `1001502003 Invalid clientId or profile`，根因是 DevEco 自动签名 Profile 的
  `app-identifier` 为随机值（`6918745435470575450`）；在 AGC 新建调试 Profile
  `youjing-debug-20261023`（同一张 `auto_debug_10086000824313557.cer`、4 台设备）替换后
  `app-identifier` 变为 APP ID，`LoginWithHuaweiID error_code=0`、日志「静默登录成功」，
  冷重启「恢复登录态 kind=huawei」。新旧 Profile 内嵌证书相同，`hdc install -r` 签名一致。
  Profile 有效期至 2027-10-20；签名配置仍仅存本机、不入库。
