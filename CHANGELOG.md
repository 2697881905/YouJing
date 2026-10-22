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
  - 阶段10 费用与导出：`expense` 表 v2→v3 迁移 + `ExpenseDao` 按 uid 分区，屏11 hero/分类/最近记账
    取记账真值并补底稿遗漏的「记一笔」Pill；`utils/IcsBuilder` 生成 RFC 5545 `.ics`（VALARM 提前提醒、
    字节折行、CRLF）+ `data/ShareExporter` 走系统分享面板；屏10 详情面板 mock 事实全部换成真值或 `—`
  - 回归：hypium 31/31（含 TodayPlan 10 条纯逻辑断言）；RDB/账号/日历分片路径改真机验收
    （原因见 `Docs/INIT_REPORT.md` 已知限制 #10）

- 工程基线初始化（P1–P5，2026-10-15）：
  - 目录骨架（pages/components/model/data/ai/mock/utils/design/common）与架构契约 `Docs/ARCHITECTURE.md`（目录职责/依赖方向/§5.4 差异/命名规范/UI 约定）
  - 技术栈版本锁定 `Docs/TECH_STACK.md`（API 26 / DevEco 26.0.0.851 / hvigor 6.26.8，运行时零依赖基线）
  - 配置层与环境隔离：`common/constants/BuildConfig.ets`、`common/config/ApiConfig.ets`、`common/config/MockConfig.ets`，`.gitignore` 增补签名/密钥防线
  - 日志与错误基线：`common/logger/Logger.ets`（YouJing. 前缀、IS_DEBUG 门控）、`common/error/AppError.ets`、`common/error/ErrorCode.ets`（1xxx–4xxx 区段 14 码），EntryAbility.onError 接入
  - 设计 tokens：`design/ColorTokens|SpaceTokens|FontTokens|MotionTokens.ets`（占位基线值，待 UI 设计定稿替换）
