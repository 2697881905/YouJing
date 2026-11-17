## 1. 总体方案

本项目采用**两端分离的日志策略**：
- **HarmonyOS ArkTS 客户端（entry 模块）**：通过自研 `Logger` 类对系统 `@kit.PerformanceAnalysisKit.hilog` 做统一封装，作为全工程唯一日志出口。
- **BFF Node.js 后端（bff 模块）**：直接使用 `console.log / console.warn / console.error`，没有引入 pino、winston、bunyan 等第三方日志框架。
- **Cloud Functions（cloud/）**：未见显式日志调用。

## 2. 关键文件

| 文件 | 作用 |
|---|---|
| `entry/src/main/ets/common/logger/Logger.ets` | 唯一日志门面，封装 hilog.debug/info/warn/error |
| `entry/src/main/ets/common/constants/BuildConfig.ets` | 集中定义 `IS_DEBUG` / `BUILD_MODE_NAME`，控制 debug 输出开关 |
| `bff/src/index.js` | BFF 全局错误处理中间件，使用 `console.error('[error]', ...)` |
| `bff/src/services/*.js`、`bff/src/routes/*.js` | BFF 各路由与服务的 console 日志点 |

## 3. 架构与约定

### ArkTS 端 Logger
- 基于 `hilog`，自定义 `DOMAIN = 0x0100`，所有日志前缀为 `YouJing.`，便于在设备端通过 hilog 按 tag 过滤抓取全部应用日志。
- 四个静态方法：`debug(tag, message)`、`info(tag, message)`、`warn(tag, message)`、`error(tag, message)`，均接收业务 tag 与字符串消息。
- **debug 级别受 `BuildConfig.IS_DEBUG` 保护**：当其为 false 时直接 return，不进入 hilog。
- tag 命名约定为「模块名.子域」，如 `Ui.Itinerary`、`Data.TripDao`、`ItineraryLongTake`、`Ai.LlmClient` 等，调用方自行传入。

文档中明确声明纪律：「禁止直接调用 console.log / console.error（P6 由 lint 规则固化）」，即 ArkTS 侧应只通过 `Logger` 写日志。

### BuildConfig 联动
`BuildConfig.IS_DEBUG` 是构建环境开关的唯一来源（文件注释强调「全工程唯一定义点」），默认值为 `true`，发布 release 前需手动翻转为 `false`。Logger 依赖该常量决定是否输出 debug 级日志。

### BFF 端
BFF 未抽象日志层，所有日志直接以带方括号标签的 `console.log/warn/error` 输出，例如 `[bff]`、`[health]`、`[error]`、`[llm]`、`[pick]`、`[iap]`、`[device]`、`[trip]`、`[db]`。全局异常处理中间件用 `console.error('[error]', err.message)` 捕获未处理异常并返回 JSON 错误体。

## 4. 约定与约束

- **ArkTS 侧日志出口唯一化**：`Logger.ets` 头注释声明禁止直接 `console.log / console.error`，且 P6 lint 规则将其固化为强制项；所有业务代码通过 `Logger.<level>('Tag', msg)` 调用。
- **tag 命名规范**：tag 由调用方提供，约定形式为「模块.子模块」（如 `Ui.*`、`Data.*`、`Ai.*`），便于按模块过滤。
- **debug 输出受构建开关控制**：`Logger.debug` 仅在 `BuildConfig.IS_DEBUG === true` 时写入 hilog；release 包中 debug 日志被静默丢弃。
- **日志前缀**：ArkTS 端所有 hilog 输出自动加 `YouJing.` 前缀，方便外部采集。
- **BFF 无结构化日志框架**：Node 侧未引入任何日志库，日志为裸 `console` 输出，不存在统一的 level、sink、traceId 等机制。
- **BuildConfig 维护纪律**：`IS_DEBUG` 不得在其他位置重复定义；发布 release 前必须手动翻转该常量并通过 Docs/INIT_REPORT.md 的 checklist 核对。