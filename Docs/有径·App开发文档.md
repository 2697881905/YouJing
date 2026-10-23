# 有径 · App 开发文档

## 一、项目概述

### 1.1 产品定位

**有径** 是一款 AI 驱动的旅游行程规划 App。用户选择目的地城市与出行日期后，AI 以选项形式追问偏好，最终生成结构化、可执行、可视化的逐日行程。

核心理念：**AI 是分析引擎，不是数据源。** 景点与住宿区域数据由开发者收集整理为内置资产，AI 只负责筛选、排序、路线规划与推荐理由生成。

“有径”二字取自“有迹可循，有径可行”——既延续了“有据”的品牌基因，又暗含“为你规划一条路径”的产品功能。

### 1.2 目标用户

需要快速规划自由行的用户，尤其是对目的地不熟悉、不想花大量时间查攻略、希望获得“拿来就能用”的行程方案的人群。

### 1.3 核心差异化

- **结构化输出**：不是大段文字，而是逐日时间线、活动节点、预约状态、交通耗时
- **选项式追问**：AI 以按钮形式提问，用户点选即可，不需要打字
- **系统级触达**：万能卡片展示“今日行程”，日历服务自动提醒预约节点
- **纯 ArkTS 技术栈**：不依赖 Java 后端，全链路鸿蒙原生


## 二、技术选型

### 2.1 开发工具链

| 工具 | 角色 | 说明 |
|---|---|---|
| **DevEco Studio** | 主 IDE | 工程创建、签名配置、模拟器管理、UI 预览。签名和模拟器管理必须在此完成 |
| **DevEco CLI** | 命令行工具链 | 将 hvigor、ohpm、hdc、hilog 等封装为统一 CLI，原生面向 AI Agent 设计 |
| **TraeWork / Trae** | AI 原生 IDE | 通过 MCP 配置调用 DevEco CLI，完成代码生成、静态检查、构建、日志排查 |
| **WorkBuddy** | 桌面 Agent | 辅助代码生成、报错排查、文档撰写 |
| **CodeX** | AI 编程助手 | 安装鸿蒙 Skill 包后，获得 ArkTS 检查、构建、日志排查能力 |

### 2.2 AI IDE 与鸿蒙工程集成方案

**推荐方案：TraeWork + DevEco CLI（MCP 模式）**

配置方式：在 Trae 的 MCP 配置中添加 DevEco MCP Server：

```json
{
  "mcpServers": {
    "deveco-mcp": {
      "command": "npx",
      "args": ["-y", "@deveco-codegenie/mcp@beta"],
      "env": {
        "PROJECT_PATH": "${workspaceFolder}",
        "DEVECO_PATH": "path/to/your/deveco"
      }
    }
  }
}
```

配置完成后，TraeWork 可调用以下核心能力：

| 工具 | 功能 |
|---|---|
| `harmonyos_knowledge_search` | 查询鸿蒙云端知识库 |
| `check_ets_files` | ArkTS 静态语法检查 |
| `build_project` | 项目构建 |
| `start_app` | 模拟器/真机启动应用 |
| `get_hilog_or_faultlog_recent` | 获取设备日志 |
| `get_app_ui_tree` | 获取 UI 树（用于 UI 还原度校验） |
| `perform_ui_action` | 在已启动的 App 中执行点击/输入 |

**开发流**：在 TraeWork 中对话式完成代码生成 → AI 自动调用 `check_ets_files` 检查 → `build_project` 构建 → `start_app` 部署到设备 → `get_hilog` 排查日志。签名和模拟器管理仍在 DevEco Studio 中完成。

**CodeX 补充配置**：安装 `harmonyos6-0exp-guide-codex` Skill，让 CodeX 在处理 ArkTS、ArkUI、UIAbility、路由、权限、ohpm、Hvigor 和 HAP 打包时优先使用官方工具链。

**WorkBuddy 使用场景**：适合辅助场景，如 API 查询、报错排查、文档草稿整理。但编译和 SDK 环境隔离，无法直接自动安装到设备，需配合 DevEco Studio 使用。

### 2.3 应用技术栈

| 层面 | 技术 | 说明 |
|---|---|---|
| 开发语言 | **ArkTS** | 声明式 UI，Stage 模型 |
| UI 框架 | **ArkUI** | RowSplit 分栏布局、List、ForEach、@State 状态管理 |
| 本地数据库 | **relationalStore (RDB)** | 基于 SQLite，支持事务、索引、版本迁移、加密 |
| 轻量存储 | **Preferences** | 用户偏好、UnionID、默认参数 |
| 密钥管理 | **HUKS** | 加密存储敏感信息 |
| 网络请求 | **@kit.NetworkKit (http)** | LLM API 调用（备选方案时使用） |
| 地图服务 | **Map Kit (@kit.MapKit)** | POI 检索、地理编码、路径规划 |
| 账号登录 | **Account Kit** | 华为账号静默登录，UnionID 关联 |
| 日历服务 | **Calendar Kit** | 活动节点写入系统日历，提前提醒 |
| 万能卡片 | **ArkUI 卡片能力** | 桌面“今日行程”卡片 |
| AI 智能体 | **小艺开放平台 LLM 模式** | 语音唤起，平台承担算力成本 |

### 2.4 AI 能力方案

**方案：小艺开放平台 LLM 模式（推荐）**

| 维度 | 说明 |
|---|---|
| 算力成本 | 平台承担，开发者免费 |
| 开发方式 | 在小艺开放平台创建 Skill，选择“LLM 模式”Agent |
| 能力 | 意图识别、对话上下文、工具调用、工作流编排 |
| 端侧集成 | Skill 业务代码跑在 HAP 内，通过 `onNewWant` 接收参数，复用 App 登录态和存储 |
| 兜底方案 | App 内纯 ArkTS 状态机 + 直连 LLM API（需自管 Key，成本自担） |

**创建流程**：登录小艺开放平台 → 进入 Skill → 新建 Skill → 填写名称、描述、触发意图 → 选择 Agent → 添加 LLM 模式 Agent。


## 三、数据架构

### 3.1 核心业务模型

```
Trip（行程）
  ├── id, destination, startDate, endDate, people, budget, style
  ├── overview: { totalCost, highlights[], summary }
  ├── days: TripDay[]
  └── tips: string[]

TripDay（单日行程）
  ├── dayIndex, date, theme, intensity（低/中/高）, risk, dailyCost
  ├── activities: Activity[]
  ├── meals: Meal[]
  └── accommodation

Activity（活动节点）
  ├── time, endTime, title, location, address
  ├── longitude, latitude
  ├── status（已约/未约/约满/待定/无需预约）
  ├── category（交通/景点/餐饮/购物/休息/住宿/其他）
  ├── note
  └── transport: { mode, duration, detail }

Meal（餐饮）
  ├── type（早餐/午餐/晚餐）
  ├── name, location, note, estimatedCost

SelectedSpot（用户选中的景点）
  ├── spotId, priority（必去/想去/可选）
  └── userNote

SelectedArea（用户选中的住宿区域）
  └── areaId
```

### 3.2 内置数据资产

**景点库**

| 字段组 | 字段 | 说明 |
|---|---|---|
| 基础 | 名称、城市、标签（必去/经典/小众/亲子）、一句话简介 | 展示用 |
| 规划 | 建议游玩时长、热度指数、周边景点 | 排序与串联 |
| 位置 | 经纬度、所在区、最近地铁站、入口提示 | 地理分析 |
| 预约 | 是否需要预约、预约方式、提前几天、放票时间、闭馆日、预约难度 | **标注“以官方为准”** |
| 溯源 | 数据来源、更新时间、可信度 | 数据管理 |

**住宿区域库**

| 字段组 | 字段 | 说明 |
|---|---|---|
| 基础 | 区域名称、城市、经纬度、一句话描述 | 展示用 |
| 交通 | 锚定地铁站（1-3个）、地铁线路、到机场/火车站时间 | 通勤计算 |
| 配套 | 商圈标签、餐饮密度、适合人群 | 推荐依据 |
| 价格 | 价格档位（经济/舒适/豪华）、参考价位段 | 预留，后期预算协同 |
| 分组 | 核心区/商圈/地铁站 | 浏览分组 |
| 溯源 | 数据来源、更新时间 | 数据管理 |

**首批城市**：北上广深，每城景点 30-50 个、住宿区域 35-50 个。数据来源：购买 + 爬虫。经纬度通过 Map Kit 地理编码获取。

### 3.3 数据分层策略

```
用户选择城市 + 日期
    │
    ▼
第一层：App 端规则筛选（不消耗 Token）
    │  按标签分组，每组取热度最高的 N 个
    │  输出：精简列表（名称 + 标签 + 一句话简介 + 预约提示）
    │
    ▼
第二层：AI 精选（Prompt 仅放精简列表）
    │  AI 帮用户勾选/排序，用户确认后得到 SelectedSpot[]
    │
    ▼
第三层：AI 规划（Prompt 放 SelectedSpot[] 完整信息）
    │  经纬度、建议时长、周边景点、预约规则全部传入
    │  AI 做路线规划、通勤计算、住宿区域推荐
    │
    ▼
输出：Trip
```

住宿区域同理：App 端先用经纬度算直线距离筛掉明显太远的，输出 8-12 个候选区域给 AI，AI 精选 2-3 个。


## 四、业务流程

### 4.1 用户主流程

```
1. 进入 App → 华为账号静默登录（UnionID）
2. 基础输入 → 城市 + 出发日期 + 返程日期 + 人数 + 预算
3. AI 追问第一轮 → 景点选择
   ├── App 从内置景点库读取该城市景点
   ├── AI 判断时间是否紧张（可用天数 × 4 vs 景点总数）
   ├── 紧张 → 提示标注优先级（必去/想去/可选）
   ├── 按标签分组展示，每个景点标注预约状态
   ├── 用户勾选 + 标注优先级
   └── 用户可点“推荐更多”→ AI 从内置库挖掘符合偏好的景点
4. AI 追问第二轮 → 住宿区域选择
   ├── App 端算距离，筛出候选区域（8-12 个）
   ├── AI 从候选中精选 2-3 个，给出具体通勤分析
   ├── 用户选择一个 / 点“帮我选”
   └── 用户可“查看更多区域”→ 展开完整列表（核心区/商圈/地铁站分组）
5. 生成行程
   ├── 输入：城市 + 日期 + SelectedSpot[] + SelectedArea
   ├── 组装 Prompt（含 JSON Schema 约束）
   ├── 调 LLM → 结构化 JSON
   ├── 类型守卫校验 → Trip 对象
   └── 不通过 → 重试一次 / 降级 / 提示用户
6. 展示与编辑 → 统一模板渲染（时间线 + 地图 + 费用），可拖动调整
7. 持久化与系统触达 → RDB 存储 + 日历写入 + 万能卡片
8. 旅行中 → 卡片展示当前节点，打卡、记费用
9. 分享 → 导出链接/日历文件
```

### 4.2 AI 追问交互设计

追问以 **App 内状态机** 实现，不依赖对话式交互：

```
问题1：旅行风格？
  [休闲] [暴走] [亲子] [美食] [文化]

问题2：住宿偏好？
  [经济型] [舒适型] [豪华型]

问题3：交通方式？
  [公共交通] [打车为主] [包车]

问题4：节奏偏好？
  [每天3个活动（轻松）] [每天4-5个（标准）] [每天6+个（紧凑）]
```

用户每题点一下按钮，状态机推进，所有问题答完后触发行程生成。默认值兜底，用户不操作也能生成。

### 4.3 JSON Schema 约束体系

三层防线：

**第一层**：Prompt 系统指令中嵌入完整 JSON Schema，要求 AI 只返回 JSON，不返回其他文字。

**第二层**：API 层设置 `response_format: { type: 'json_schema', strict: true }`，模型被强制遵循 Schema。

**第三层**：ArkTS 端类型守卫。`JSON.parse()` 返回 `Object | null`，不可直接断言。逐字段校验类型、枚举值、数组结构，构造业务对象。Schema、接口、守卫三者同源。


## 五、技术架构

### 5.1 分层架构

```
┌─────────────────────────────────────────────────┐
│  入口层                                          │
│  ├─ App 内直接交互（城市/日期 → 选项追问 → 生成）│
│  └─ 小艺 Skill（onNewWant 接收参数 → 预填）      │
├─────────────────────────────────────────────────┤
│  交互层                                          │
│  ├─ 多轮选项状态机（Question[] → answers）       │
│  └─ 行程编辑（拖动调整 / 手动增删）              │
├─────────────────────────────────────────────────┤
│  AI 层（ArkTS）                                  │
│  ├─ 数据分层筛选（规则 → 精简列表 → AI 精选）    │
│  ├─ Prompt 构造（含 JSON Schema）                │
│  ├─ LLM 调用（小艺 Agent / http）                │
│  └─ parseTrip() 类型守卫 → Trip                  │
├─────────────────────────────────────────────────┤
│  数据层（ArkTS）                                 │
│  ├─ RDB：Trip / TripDay / Activity / 景点库 / 区域库 │
│  ├─ Preferences：UnionID、用户偏好               │
│  └─ HUKS：密钥管理                               │
├─────────────────────────────────────────────────┤
│  渲染层（ArkUI）                                 │
│  ├─ 统一模板：时间线 / 地图 / 费用               │
│  ├─ RowSplit 分栏布局                            │
│  └─ 万能卡片“今日行程”                           │
├─────────────────────────────────────────────────┤
│  系统能力层                                      │
│  ├─ Map Kit：POI 检索 / 地理编码 / 路径规划      │
│  ├─ Calendar Kit：日程写入 + 提前提醒            │
│  └─ Account Kit：华为账号登录                    │
└─────────────────────────────────────────────────┘
```

### 5.2 RDB 数据层要点

基于鸿蒙 RDB 的生产级实践，有径的数据层需遵循以下原则：

- **RdbStore 是单例的**：一个数据库一个 store，不要每处新建。页面普通查询可保持独立，但写事务应收敛为单写通道。
- **增删改走 SQL，查询走 ResultSet**：ArkTS 严格类型下，查询结果要逐列收口成模型对象，不可直接断言。
- **版本号驱动迁移**：`onUpgrade` 按 oldVersion → newVersion 依次执行 ALTER/CREATE，多条迁移建议放入事务，成功后再写入新版本号。
- **索引优化**：在经常用于过滤条件的列上创建索引，避免全表扫描。
- **数据记录大小限制**：单条数据记录不超过 2 MB。

### 5.3 Map Kit 能力集成

使用 Map Kit 的以下能力时，需先通过 DevEco Studio 或 AppGallery Connect 开通地图服务并完成签名：

| 能力 | 用途 |
|---|---|
| `site`（地点搜索） | POI 搜索、正/逆地理编码，用于景点经纬度获取 |
| `navi`（路径规划） | 出行路径规划、批量算路，用于通勤时间计算 |
| `map`（地图显示） | 行程页地图展示 |

**必需权限**：`ohos.permission.APPROXIMATELY_LOCATION`、`ohos.permission.LOCATION`。

**常见错误**：1002600003（应用身份校验失败）通常是因为未开通地图服务，或开通后未重新生成 Profile 文件进行重新签名。

**2026-10-24 落地实测（`map` 地图显示这一档）**：
- 只画落点、不显示「我的位置」时，实际只需 `ohos.permission.INTERNET`（瓦片走网络）；
  上面两条定位权限留给后续 `setMyLocationEnabled` 再声明，不提前申请。
- AGC 开通「地图服务」后必须重出 Profile：新 p7b 解出的
  `app-services-capabilities = { "com.huawei.service.mapkit": {} }`，旧 p7b 该字段为 null——
  这就是重出的判据。证书与设备列表不变（同一张调试证书 SHA-256 `86:6F:C3:64…CF:70`），
  只把 `build-profile.json5` 的 profile 路径换新文件重签即可。
- 中国大陆底图按 **GCJ02** 绘制，种子坐标必须先由 WGS84 转换（本工程在灌数据阶段离线转好，
  落 `seed/*.jsonl` 的 `la/lo`），否则整条动线会偏几百米。
- `MapComponent` 的 `mapCallback` 只由组件挂载后才可能回调，所以「等 ready 再挂 MapComponent」
  会自锁成一张永久空图（首版真机踩过）；底图先挂，加载态与错误态做成覆盖层。
- **组件拆除期会反手调你的事件回调**：`MapEventManager.off('markerClick', cb)` 在
  `aboutToDisappear` 里用 `undefined` 把 `cb` 又调了一次，回调里 `marker.getTag()` 抛
  `TypeError: Cannot read property getTag of undefined`，异常逃出 `aboutToDisappear`
  就是 JS 崩溃、整个 App 被系统杀掉（真机实测：离开任一含底图的页面必死）。
  口径：回调第一行判空 + 注销与覆盖物清理各包一层 try/catch；异步 `addMarker` 的
  `.then` 回来时先确认组件还在（`controller !== null`），别碰已回收的底图对象。
- `newLatLngBounds` 的留白单位是 px，且**按宿主量、不给全局常量**：底图是满屏的、浮层不是。
  dock 地图页真机 1136×2690 上，分段栏底 487px、站点条顶 2101px → 上下各留 600px 才不压图钉；
  屏8 那块 625px 高的小面板另有一档（260/150）。留白小了，首末站图钉会藏进浮层底下。

### 5.4 工程结构

```
YouJing/
├── entry/
│   └── src/main/ets/
│       ├── entryability/EntryAbility.ets
│       ├── pages/
│       │   ├── Index.ets                    # 首页（城市+日期选择）
│       │   ├── SpotSelectPage.ets           # 景点选择
│       │   ├── AreaSelectPage.ets           # 住宿区域选择
│       │   ├── TripDetailPage.ets           # 行程详情（时间线）
│       │   └── QuestionFlowPage.ets         # 选项追问状态机
│       ├── components/
│       │   ├── DayCard.ets                  # 单日卡片
│       │   ├── ActivityItem.ets             # 活动节点
│       │   ├── SpotCard.ets                 # 景点卡片
│       │   ├── AreaCard.ets                 # 区域卡片
│       │   └── OptionButton.ets             # 选项按钮
│       ├── model/
│       │   ├── Trip.ets                     # Trip / TripDay / Activity
│       │   ├── Spot.ets                     # 景点数据模型
│       │   ├── Area.ets                     # 住宿区域数据模型
│       │   └── PlanParams.ets               # 规划参数
│       ├── data/
│       │   ├── TripDao.ets                  # 行程 RDB 操作
│       │   ├── SpotDao.ets                  # 景点 RDB 操作
│       │   ├── AreaDao.ets                  # 区域 RDB 操作
│       │   └── DatabaseHelper.ets           # 建库建表 + 版本迁移
│       ├── ai/
│       │   ├── PromptBuilder.ets            # Prompt 构造
│       │   ├── TripSchema.ets               # JSON Schema 常量
│       │   ├── TripParser.ets               # 类型守卫 + 解析
│       │   └── LlmClient.ets                # LLM API 调用（备选）
│       ├── mock/
│       │   └── MockTrip.ets                 # Mock 数据
│       └── utils/
│           ├── Geo.ets                       # 大圆距离（屏5「帮我选」按距离取片区）
│           ├── CategoryStyle.ets             # 活动类别 → 色名（屏8/屏13 同一口径）
│           ├── IcsBuilder.ets                # .ics 与分享文本（RFC 5545 口径）
│           ├── MapStops.ets                  # 底图落点与视野盒
│           ├── NumberedPin.ets               # 编号图钉
│           ├── immersiveMaterial.ets         # 系统材质档位与能力门控
│           └── DateUtils.ets                 # 日期工具
├── tools/
│   └── audit_colors.py                       # 色值 ↔ 设计契约核对（见 §5.5）
├── AppScope/
└── build-profile.json5
```


### 5.5 设计与契约核对脚本

`resources/base/element/color.json` 与 `resources/dark/element/color.json` 是把设计契约
（底稿 v1 `docs/DESIGN.md` 的 §1 色板 + Translucency ledger）手抄成 48 件 × 两档，
抄错一位肉眼看不出来——2026-10-24 就抓到过一处：`border_subtle` 浅色写成
`#66C4C6CA`（绿通道 198），契约 `glass-bar-border` 是 `rgba(196, 196, 202, 0.4)` =
`66 C4 C4 CA`（绿通道 196），33 处帧内联值也都是 196,196,202。

`python3 tools/audit_colors.py [DESIGN.md 路径]` 逐件比对两份 color.json 与契约，
退出码非 0 即有偏差；契约未直接命名的三件（`on_dark_degraded`、`primary_glow_edge`、
`start_window_background`）是派生透明值或系统必需件，脚本按规则跳过并打印出来。
台账同时给 rgba 与十六进制两列时以十六进制列为准（0.3 换算成 alpha 会四舍五入成 4C，
而台账写的是 4D）。当前状态：48 件核对，0 偏差。

`python3 tools/audit_type.py` 是第二把尺：`Text` 的字号必须来自 `TypeTokens`、
`SymbolGlyph` 的必须来自 `IconSizes`（契约字号只有 10/11/12/14/16/18/21/32）。
它一跑就指出屏13 桌面卡片是唯一绕过字阶 token 的界面，且对着帧的 widget CSS
（`widget-time 12/600`、`widget-content-text 14/400`）核出时间和站名各小了一档。
当前 Text 违规 0 件；剩 7 处图标字面量（12/14/18）属"帧在用、禁令 7 未承认"的待裁决档位。

两把尺子的共同理由：色表和字阶都是把契约手抄成几十件，抄错一位（绿通道 196→198、
字号差一档）肉眼和截图都发现不了。hooks 不随仓库分发，所以这两条不进 pre-commit，
改过 token 或界面后手动各跑一次。


## 六、开发路线

### 阶段 1：数据契约冻结

**产出**：Trip / TripDay / Activity / Spot / Area 接口定义

**验收**：覆盖行程页所有展示字段，字段类型与 JSON Schema 一一对应

### 阶段 2：UI 占位 + Mock 数据

**产出**：用 Mock 数据渲染完整行程详情页（时间线 + 地图占位 + 费用）

**验收**：空状态 / 部分数据 / 异常数据三种边界都能正常展示

**工具**：DevEco Studio 预览器 + TraeWork MCP `get_app_ui_tree` 校验 UI

### 阶段 3：JSON Schema + 类型守卫

**产出**：TripSchema 常量 + parseTrip() 校验函数

**验收**：Mock JSON 通过，非法数据被拦截

### 阶段 4：本地存储

**产出**：RDB 建表（Trip / TripDay / Activity / Spot / Area）+ DAO

**关键点**：RdbStore 单例，不要每处新建；版本号驱动迁移，onUpgrade 按版本迭代

### 阶段 5：内置数据收集

**产出**：北上广深四城景点库 + 住宿区域库

**数据来源**：购买 + 爬虫，经纬度通过 Map Kit 地理编码获取

**验收**：每城 30-50 个景点、35-50 个区域，字段完整

### 阶段 6：LLM 接入

**产出**：PromptBuilder + LlmClient + 解析闭环

**验收**：AI 返回的 JSON 能通过守卫变成 Trip 对象

### 阶段 7：多轮选项交互

**产出**：QuestionFlow 状态机，景点选择 + 住宿区域选择页面

**验收**：用户从输入到生成全流程无阻断

### 阶段 8：华为账号登录

**产出**：UnionID 登录态 + 数据按用户分区

### 阶段 9：系统能力集成

**产出**：小艺 Skill + 万能卡片 + 日历写入

**验收**：语音唤起 App 并预填参数；卡片显示今日行程；日历有预约提醒

### 阶段 10：增强功能

**产出**：费用记录 / 足迹地图 / 分享导出 / 预算协同分析


## 七、关键技术决策记录

| 决策 | 选择 | 理由 |
|---|---|---|
| App 命名 | **有径** | 延续“有据”品牌感，暗含“为你规划路径”，查重风险可控 |
| AI 能力接入 | 小艺开放平台 LLM 模式 | 平台承担算力成本，纯 ArkTS 集成 |
| 数据来源 | 自建景点库 + 区域库 | AI 不负责找景点，只做筛选和规划 |
| 住宿服务 | 只推荐位置，不接第三方 | 避免合规复杂度 |
| 预算协同 | 预留 priceLevel 字段，后期启用 | 数据结构先行 |
| 预约信息 | 标注“以官方为准” | 硬信息无法保证实时准确 |
| 筛选策略 | App 端规则筛选 → AI 精选 → AI 规划 | Token 可控，质量可控，可降级 |
| 开发工具 | DevEco Studio + TraeWork + CodeX + WorkBuddy | AI IDE 负责代码生成与检查，DevEco Studio 负责签名和最终调试 |
| 城市范围 | 首批北上广深 | 覆盖主要旅游需求，数据收集可控 |
| 屏10 节点改期 | 官方 TextPicker 选当日其它槽位，整份聚合根落库 | 当日时间槽是既定集合：另填一个新时间会撞预约窗口，也会让后续站的通勤腿失真；选槽等于重排当日，与屏9 拖动同一套语义 |
| 屏5「帮我选」度量 | 与所选景点的平均直线距离（utils/Geo），按钮写「离景点最近」 | 无路径规划接口，「通勤最短」算不出来；直线距离是能给的最近似，按它命名就不谎报导航里程 |
| 屏3b 多选节奏 | 所选档位切成等长天段，固定按 轻松→标准→紧凑 铺 | helper 承诺「按天段分别排布」；若跟点选先后走，同一组勾选会因点击顺序排出不同行程，不可复现 |


## 八、风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| LLM 输出不稳定 | 解析失败 | 三层 Schema 约束 + 重试 + Mock 降级 |
| 景点数据过期 | 预约信息误导 | 标注“以官方为准”，定期更新 |
| 住宿区域推荐不准 | 用户选错位置 | App 端先算距离筛候选，AI 只做精选 |
| 地图服务配额 | POI 检索受限 | 核心数据内置，Map Kit 仅用于地理编码和路径计算 |
| 小艺平台审核 | Skill 上架延迟 | 先做 App 内闭环，Skill 作为增量入口 |
| ArkTS 严格类型 | JSON 解析报错 | 类型守卫逐字段校验，不用 any |
| RDB 写并发 | busy 错误 | 全应用复用同一 RdbStore，写事务收敛为单写通道 |
| bindSheet 内容不随父组件 @State 重绘 | 面板显示过期真值（真机实测：时间线已换槽，屏10 仍停在打开那一刻的时间） | 改完数据即收起面板，重开读真值；不在面板里留一个不生效的刷新口子 |


## 九、命名决策记录

| 阶段 | 候选名 | 结果 |
|---|---|---|
| 初版 | 旅典 | 偏静态，像攻略合集 |
| 迭代 | 旅π、路书、取道、司南、拿主意、别问走、走呗、老马、一口袋、指北 | 多数已被占用或调性不符 |
| 收敛 | 有迹 | 第9类商标已被“有迹 TV”注册，多个 App 同名 |
| 定稿 | **有径** | 第9/42类暂未发现有效商标障碍，应用市场未发现同名旅游 App |