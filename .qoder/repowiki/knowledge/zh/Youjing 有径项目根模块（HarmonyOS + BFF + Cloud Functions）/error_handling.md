## 1. 整体方案

项目采用「两端各自定义错误类型 + 通过 ErrorCode 数值码桥接」的分层策略：

- **ArkTS 端（entry）**：所有跨层上抛的错误统一包装为 `AppError`，携带三位段前缀的 `ErrorCode` 数字码。
- **BFF（Node.js/Express）**：自定义 `HttpError(status, code, message)` 作为业务异常；中间件直接 `res.status().json({ error, message })` 返回标准 JSON 体。
- **端侧映射**：`BffErrorMap.bffErrorCode` 把 BFF 的 HTTP 状态码和 body 中的 `error` 字符串还原为 ArkTS 端的 `ErrorCode`，是前后端错误协议的唯一翻译点。
- **用户文案分离**：`FailureCopy.failureHeadline / failureDetail` 根据 `ErrorCode` 返回面向用户的标题与详情，页面层只做排版，不内联文案。

## 2. 关键文件

| 层级 | 文件 | 职责 |
|---|---|---|
| ArkTS 公共层 | `entry/src/main/ets/common/error/AppError.ets` | 统一错误类，封装 `code`、`cause` |
| ArkTS 公共层 | `entry/src/main/ets/common/error/ErrorCode.ets` | 全工程唯一错误码常量表，按 1xxx–6xxx 分区 |
| ArkTS 公共层 | `entry/src/main/ets/common/error/FailureCopy.ets` | 错误码 → 用户可读标题/详情的纯映射 |
| ArkTS 工具层 | `entry/src/main/ets/utils/BffErrorMap.ets` | BFF HTTP 错误 → ArkTS `ErrorCode` 映射 |
| BFF 公共层 | `bff/src/lib/http-error.js` | Node 侧 `HttpError` 基类 |
| BFF 中间件 | `bff/src/middleware/auth.js` | 401 TOKEN_INVALID |
| BFF 中间件 | `bff/src/middleware/rateLimit.js` | 429 RATE_LIMITED |
| 展示页 | `entry/src/main/ets/pages/GenerateFailedPage.ets` | 使用 `failureHeadline/failureDetail` 渲染失败态 |

被广泛引用 `AppError`/`ErrorCode` 的业务文件（16 个）包括：`LlmClient`、`ReplanClient`、`TripParser`、`ReplanParser`、`AccountStore`、`TripDao`、`DatabaseHelper`、`DataSeeder`、`MapKitCityStore`、`WeatherParser`、`DirectChat`、`GeneratingPage`、`GenerateFailedPage`。

## 3. 架构约定

### 3.1 ArkTS 端错误分类（ErrorCode 区段）

`ErrorCode` 用千位段划分错误域，注释明确禁止重复、新增只能在本区段顺延追加：

- `1xxx` — 网络（HTTP 请求、LLM 直连、Map Kit 城市数据）
- `2xxx` — JSON/解析（response_format、Schema 校验、ArkTS 类型守卫）
- `3xxx` — RDB 存储（初始化、迁移、事务、查询）
- `4xxx` — 业务规则（行程生成前置校验、重试耗尽）
- `5xxx` — 账号（UnionID 静默登录、登录态持久化）
- `6xxx` — 云端（BFF / 权益 / IAP：令牌失效、额度耗尽、限流、幂等冲突、通行证不存在、IAP 校验失败）

### 3.2 AppError 包装模式

`AppError.fromError(code, error)` 是唯一的入站包装入口，保留原始 `Error` 为 `cause`。调用方在 catch 中把具体异常转为 `AppError`，再向 UI 层抛出，避免上层拿到框架原生错误。

### 3.3 错误码到用户文案的双函数映射

`FailureCopy` 提供两个独立函数：`failureHeadline`（标题）和 `failureDetail`（原因说明）。设计文档强调“主副标题两版必须一致”，原始诊断只进日志或“明确标注的调试行”。未命中分支回退到通用文案（如 `'生成没能完成'`、`'原因已记进本机日志…'`），保证每个 `ErrorCode` 都有兜底。

### 3.4 BFF ↔ 端侧错误协议

BFF 中间件直接返回 `{ error: 'TOKEN_INVALID', message: '…' }` 这类结构体；`BffErrorMap.bffErrorCode` 根据 status + body.error 反推 `ErrorCode`。对 `>=500` 还区分上游问题（`LLM_UPSTREAM_ERROR` → `LLM_UNAVAILABLE`）与模型内容问题（`LLM_INVALID_TRIP` / `LLM_INVALID_JSON` → `TRIP_GENERATE_RETRY_EXHAUSTED`），避免把模型输出缺陷误报成网络故障。

### 3.5 BFF 中间件错误策略

- `authMiddleware`：缺少 Authorization 头或 JWT 验证失败 → 401 `TOKEN_INVALID`。
- `rateLimitMiddleware`：固定窗口内存计数超限 → 429 `RATE_LIMITED`；文档明确声明该实现是进程内单实例限流，多实例部署需 Redis。
- `idempotency`（同名中间件）：配合客户端幂等键，冲突时返回 409，端侧映射为 `CLOUD_IDEMPOTENCY_CONFLICT`。

## 4. 观察到的约定与约束

- **错误码集中定义**：`ErrorCode.ets` 是全工程唯一定义点，注释写明“码值全局唯一不得重复；新增错误码只能在所属区段内顺延追加”。
- **跨层错误一律包装**：`AppError` 注释要求“所有跨层上抛的错误一律包装为 AppError，携带 ErrorCode 码值”。
- **用户文案与业务逻辑分离**：`FailureCopy` 单独成文件以便进入 hypium 回归测试；页面只负责排版，不调用 `err.message`。
- **BFF 错误结构稳定**：中间件统一返回 `{ error, message }` 的 JSON，供 `BffErrorMap` 消费。
- **未覆盖错误有兜底**：`FailureCopy` 和 `bffErrorCode` 都保留了 fallback 分支，确保新增错误码不会导致空标题或未定义行为。
- **可测试性**：`FailureCopy.test.ets`、`BffErrorMap.test.ets` 以及 BFF 的 `test/*` 目录覆盖了错误映射路径；`rateLimitMiddleware` 暴露 `resetRateLimit()` 供测试清空状态。
- **无 panic/recover**：ArkTS 侧未见 `try/catch` 之外的全局崩溃捕获；Node 侧 BFF 也未见顶层 `process.on('uncaughtException')` 处理器，依赖 Express 默认错误处理或宿主环境。
- **日志与显示分离**：FailureCopy 注释指出“原始诊断只该进日志和明确标注的调试行”，业务代码应记录详细堆栈，UI 只展示 `failureHeadline/failureDetail`。