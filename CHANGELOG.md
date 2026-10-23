# Changelog

本文件记录工程级显著变更，格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased]

### Added

- 业务阶段 1–8 落地（2026-10-20 → 2026-10-22，真机验收）：
  - 阶段1/3 数据契约与防线：`model/`（Trip/Spot/Area/PlanParams 接口与枚举）、`ai/TripSchema`（枚举白名单单一事实源）+ `ai/TripParser` 逐字段守卫（错误路径定位到 `days[i].activities[j].field`）
  - 阶段2/4 UI 与存储：设计底稿 39 帧全量落 `pages/`+`components/`+`design/`（46 色 light/dark 双值、衬线字体注册、深色零阴影门控、系统材质沉浸栏）；`data/DatabaseHelper` RdbStore 单例 + 单写通道事务 + 版本驱动迁移
  - 阶段5 内置资产：北上广深种子库（每城 32 景点 / 36 区域，rawfile JSONL）+ `DataSeeder` 首启幂等灌入
  - 阶段6/7 AI 与交互：`ai/PromptBuilder`（Schema 内嵌）+ `ai/LlmClient`（Mock 离线闭环 / HTTP 备选 / 失败重试一次）；屏2–6 多轮选项状态机 `data/PlanDraft` + `data/PlanRepository` 打通到落库
  - 阶段8 账号与分区：`common/config/AccountConfig` + `data/AccountStore`（UnionID 静默登录、失败退本机游客分区、登录态 Preferences 持久化）；DB v1→v2 加 `trip.user_id` 分区列与索引，`TripDao` 列表/详情读按 uid 收口、`adoptGuestTrips` 游客数据归户
  - 阶段9 系统触达：屏14 Calendar Kit 真写入（预约节点 + 每日全天、按 tripId 幂等清理）；
    今日行程卡片读真 RDB 数据（`data/TodayPlan` 纯函数 + FormExtensionAbility 直读回灌）；
    外部拉起参数通道（`onNewWant` + 屏2 预填回显）为小艺 Skill 接收端就绪
  - 阶段10 屏7 接真错误：`FailInfo{code,detail}` 随路由传入，`common/error/FailureCopy` 做错误码→人话标题
    （纯函数，hypium 覆盖），两条修法改成真能跳的「回选点页/调松节奏」，原始诊断仅 debug 版露出；
    底稿编造的「伏见稻荷与宇治步行超 90 分钟」「打车 ¥3,200」不再对用户说
  - 阶段10 屏5 去假数：区域卡三列原样是卡片序号算出来的（`8 + i * 4` 分钟 / `30 + i * 6` / `9 + i * 7` 家），
    换成 `Area` 真字段「到机场 / 到火车站 / 餐饮密度」；顶部地图卡改成候选片区图例（同城 36 片区
    共用一个城市质心坐标，按经纬度布点就是编位置）；`帮我选（按通勤最短）` → `帮我选（推荐第一片）`
    （处理函数就是取 `picks[0]`）；副信息行 `maxLines` 1→2，最长 30 字的种子行不再被省略号截断
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
  - 回归：hypium 40/40（含 TodayPlan 10 条纯逻辑断言）；RDB/账号/日历分片路径改真机验收
    （原因见 `Docs/INIT_REPORT.md` 已知限制 #10）

- 工程基线初始化（P1–P5，2026-10-15）：
  - 目录骨架（pages/components/model/data/ai/mock/utils/design/common）与架构契约 `Docs/ARCHITECTURE.md`（目录职责/依赖方向/§5.4 差异/命名规范/UI 约定）
  - 技术栈版本锁定 `Docs/TECH_STACK.md`（API 26 / DevEco 26.0.0.851 / hvigor 6.26.8，运行时零依赖基线）
  - 配置层与环境隔离：`common/constants/BuildConfig.ets`、`common/config/ApiConfig.ets`、`common/config/MockConfig.ets`，`.gitignore` 增补签名/密钥防线
  - 日志与错误基线：`common/logger/Logger.ets`（YouJing. 前缀、IS_DEBUG 门控）、`common/error/AppError.ets`、`common/error/ErrorCode.ets`（1xxx–4xxx 区段 14 码），EntryAbility.onError 接入
  - 设计 tokens：`design/ColorTokens|SpaceTokens|FontTokens|MotionTokens.ets`（占位基线值，待 UI 设计定稿替换）
