# 权益管理 API

<cite>
**本文引用的文件**   
- [bff/src/routes/entitlement.js](file://bff/src/routes/entitlement.js)
- [bff/src/services/quota.js](file://bff/src/services/quota.js)
- [bff/src/middleware/auth.js](file://bff/src/middleware/auth.js)
- [bff/src/services/admin.js](file://bff/src/services/admin.js)
- [bff/src/db.js](file://bff/src/db.js)
- [Docs/商业化方案.md](file://Docs/商业化方案.md)
- [entry/src/main/ets/data/EntitlementStore.ets](file://entry/src/main/ets/data/EntitlementStore.ets)
- [entry/src/main/ets/utils/BffErrorMap.ets](file://entry/src/main/ets/utils/BffErrorMap.ets)
- [entry/src/main/ets/common/config/ApiConfig.ets](file://entry/src/main/ets/common/config/ApiConfig.ets)
</cite>

## 目录
1. [引言](#引言)
2. [项目结构与职责边界](#项目结构与职责边界)
3. [核心组件](#核心组件)
4. [架构总览](#架构总览)
5. [接口规范](#接口规范)
6. [详细组件分析](#详细组件分析)
7. [依赖关系分析](#依赖关系分析)
8. [性能与并发一致性](#性能与并发一致性)
9. [错误处理指南](#错误处理指南)
10. [结论](#结论)

## 引言
本文件面向“权益管理”相关能力，覆盖以下目标：
- 明确 `GET /v1/entitlement` 的语义、鉴权方式、响应结构及客户端缓存策略。
- 明确额度检查与扣减逻辑，包括免费用户、付费订阅、行程通行证、赠送额度的优先级与剩余量计算。
- 说明权限验证流程（JWT）、会员状态判定、管理员白名单行为。
- 给出并发访问时的预占—提交—释放机制和数据一致性保证。
- 提供常见错误的识别与处理方式，包括余额不足、票据失效、幂等冲突等。

需要特别说明的是：当前仓库中并未实现独立的 `POST /v1/entitlement/check` 端点；额度检查与扣减由生成接口 `POST /v1/trip/generate` 内部调用配额服务完成。因此本文在“额度检查”部分以该实际实现为准进行说明。

## 项目结构与职责边界
- BFF（Node/Express）负责账号鉴权、权益查询、配额预占/提交/释放、IAP 校验与通知、LLM 代理。
- 数据库为 SQLite，DDL 定义于 BFF 启动路径，包含账户、订阅、通行证、额度账本、行程请求、订单等表。
- 端侧（ArkTS）维护权益本地缓存、权限判断入口、购买流程与错误映射。

```mermaid
graph TB
  Client["客户端<br/>ArkTS 应用"] --> BFF["BFF Express 服务"]
  BFF --> Auth["鉴权中间件<br/>JWT 验证"]
  BFF --> EntRoute["权益路由<br/>GET /v1/entitlement"]
  BFF --> TripRoute["行程生成路由<br/>POST /v1/trip/generate"]
  BFF --> QuotaSvc["配额服务<br/>getEntitlement / determineQuotaSource"]
  BFF --> DB["SQLite 数据库<br/>订阅 / 通行证 / 额度账本 / 行程请求"]
  Client --> EntStore["端侧权益缓存<br/>EntitlementStore"]
```

**图表来源**
- [bff/src/routes/entitlement.js:1-15](file://bff/src/routes/entitlement.js#L1-L15)
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)
- [bff/src/middleware/auth.js:1-25](file://bff/src/middleware/auth.js#L1-L25)
- [bff/src/db.js:1-136](file://bff/src/db.js#L1-L136)
- [entry/src/main/ets/data/EntitlementStore.ets:1-200](file://entry/src/main/ets/data/EntitlementStore.ets#L1-L200)

**章节来源**
- [Docs/商业化方案.md:1-200](file://Docs/商业化方案.md#L1-L200)
- [bff/src/db.js:1-136](file://bff/src/db.js#L1-L136)

## 核心组件
- 权益路由：暴露 `GET /v1/entitlement`，返回订阅、通行证、赠送额度、用量与上限。
- 配额服务：提供权益快照、额度来源判定、预占/提交/释放、管理员白名单判断。
- 鉴权中间件：校验 `Authorization: Bearer <JWT>`，解析出 `accountId` 与 `deviceId`。
- 端侧权益缓存：按 5 分钟 TTL 缓存服务端快照，并提供导出与生成门禁判定。
- 错误映射：将 BFF HTTP 状态码映射为端侧业务错误码。

**章节来源**
- [bff/src/routes/entitlement.js:1-15](file://bff/src/routes/entitlement.js#L1-L15)
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)
- [bff/src/middleware/auth.js:1-25](file://bff/src/middleware/auth.js#L1-L25)
- [entry/src/main/ets/data/EntitlementStore.ets:1-200](file://entry/src/main/ets/data/EntitlementStore.ets#L1-L200)
- [entry/src/main/ets/utils/BffErrorMap.ets:1-41](file://entry/src/main/ets/utils/BffErrorMap.ets#L1-L41)

## 架构总览
权益查询与额度控制的整体链路如下：

```mermaid
sequenceDiagram
  participant App as "客户端"
  participant BFF as "BFF"
  participant Auth as "鉴权中间件"
  participant Route as "权益路由"
  participant Quota as "配额服务"
  participant DB as "数据库"

  App->>BFF: "GET /v1/entitlement"
  BFF->>Auth: "校验 Authorization"
  Auth-->>BFF: "解析 accountId/deviceId"
  BFF->>Route: "转发到 /v1/entitlement"
  Route->>Quota: "getEntitlement(accountId)"
  Quota->>DB: "读取订阅 / 通行证 / 赠送 / 用量"
  DB-->>Quota: "权益数据"
  Quota-->>Route: "权益快照"
  Route-->>App: "JSON 响应"
```

**图表来源**
- [bff/src/routes/entitlement.js:1-15](file://bff/src/routes/entitlement.js#L1-L15)
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)
- [bff/src/middleware/auth.js:1-25](file://bff/src/middleware/auth.js#L1-L25)

## 接口规范

### GET /v1/entitlement
用于查询当前账号的权益快照，供端侧展示和做本地门禁判断。

- 方法：`GET`
- 路径：`/v1/entitlement`
- 鉴权：必须携带 `Authorization: Bearer <JWT>`。
- 成功响应体字段：
  - `subscription`：`null` 或对象，含 `status`、`periodEnd`。
  - `passes`：数组，元素含 `localTripId`、`status`、`expiresAt`。
  - `giftRemaining`：赠送额度剩余次数。
  - `usedToday`：当月已使用次数（字段名保留历史兼容）。
  - `dailyCap`：月度防滥用上限，当前固定为 20。
  - `unlimited`：仅管理员白名单命中时为 `true`。
- 失败响应：
  - `401`：缺少或无效的 JWT，返回 `TOKEN_INVALID`。

#### 请求示例
```text
GET /v1/entitlement
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### 成功响应示例
```json
{
  "subscription": {
    "status": "active",
    "periodEnd": "2026-12-01T00:00:00Z"
  },
  "passes": [
    {
      "localTripId": "a1b2c3d4",
      "status": "active",
      "expiresAt": null
    }
  ],
  "giftRemaining": 3,
  "usedToday": 5,
  "dailyCap": 20,
  "unlimited": false
}
```

#### 不同用户类型的差异
| 用户类型 | subscription | passes | giftRemaining | usedToday | dailyCap | unlimited |
|---|---|---|---:|---:|---:|---|
| 免费新用户 | `null` | `[]` | 3 | 0 | 20 | `false` |
| 付费订阅用户 | `active` | 可能为空 | 3 | 小于等于 20 | 20 | `false` |
| 有通行证用户 | `null` 或任意 | 至少一个 `active` | 3 | 小于等于 20 | 20 | `false` |
| 管理员测试账号 | 同上 | 同上 | 同上 | 同上 | 20 | `true` |

**章节来源**
- [bff/src/routes/entitlement.js:1-15](file://bff/src/routes/entitlement.js#L1-L15)
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)
- [bff/src/middleware/auth.js:1-25](file://bff/src/middleware/auth.js#L1-L25)
- [bff/src/services/admin.js:1-24](file://bff/src/services/admin.js#L1-L24)
- [Docs/商业化方案.md:120-160](file://Docs/商业化方案.md#L120-L160)

## 详细组件分析

### 权益查询逻辑
`getEntitlement` 根据 `accountId` 查询四类数据：
1. 有效订阅：状态为 `active` 且未过期的最近一条订阅记录。
2. 通行证：状态为 `active` 的所有通行证。
3. 赠送额度累计：来源于 `quota_ledger` 中 `source='gift'` 且 `state='committed'` 的累计值，并与基础赠送额度合并。
4. 当月用量：统计当月 `trip_request.status='succeeded'` 的行数。

返回值中的 `usedToday` 实际上是当月用量，但字段名保留以兼容端侧消费逻辑；`dailyCap` 固定为 20，表示月度防滥用上限。

```mermaid
flowchart TD
  Start(["进入 getEntitlement"]) --> ReadSub["查询有效订阅"]
  ReadSub --> ReadPass["查询通行证列表"]
  ReadPass --> ReadGift["查询赠送额度累计"]
  ReadGift --> CountMonth["统计当月成功用量"]
  CountMonth --> Build["组装 subscription / passes / giftRemaining / usedToday / dailyCap / unlimited"]
  Build --> End(["返回权益快照"])
```

**图表来源**
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)

**章节来源**
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)

### 额度检查与扣减逻辑
虽然不存在独立的 `POST /v1/entitlement/check` 端点，但额度检查的核心实现在 `determineQuotaSource` 与 `reserveQuota/commitQuota/releaseQuota` 中。

额度来源判定优先级：
1. 管理员白名单：直接返回 `admin`，不触发 402。
2. 订阅未满额：存在有效订阅且当月用量小于 20，返回 `subscription`。
3. 通行证：若请求附带 `passId` 且属于该账号的活跃通行证，返回 `pass`。
4. 赠送额度：若 `giftRemaining > 0`，返回 `gift`。
5. 否则返回 `null`，生成接口返回 402。

```mermaid
flowchart TD
  Enter(["进入 determineQuotaSource"]) --> AdminCheck{"是否管理员?"}
  AdminCheck -->|是| ReturnAdmin["返回 admin"]
  AdminCheck -->|否| SubCheck{"是否有有效订阅且用量小于上限?"}
  SubCheck -->|是| ReturnSub["返回 subscription"]
  SubCheck -->|否| PassCheck{"是否存在匹配的通行证?"}
  PassCheck -->|是| ReturnPass["返回 pass"]
  PassCheck -->|否| GiftCheck{"是否还有赠送额度?"}
  GiftCheck -->|是| ReturnGift["返回 gift"]
  GiftCheck -->|否| ReturnNull["返回 null → 402"]
```

**图表来源**
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)

**章节来源**
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)

### 权限验证流程
- 所有受保护路由通过 `authMiddleware` 校验 JWT。
- JWT 负载中包含 `accountId` 与 `deviceId`。
- 缺失 `Authorization` 头或 Token 无效时返回 `401 TOKEN_INVALID`。
- 管理员白名单由环境变量配置，仅在生成额度场景生效，不影响 IAP 与限流。

```mermaid
sequenceDiagram
  participant Client as "客户端"
  participant Middleware as "鉴权中间件"
  participant Service as "下游路由或服务"

  Client->>Middleware: "携带 Authorization 头"
  Middleware->>Middleware: "提取并验签 JWT"
  alt Token 有效
    Middleware-->>Service: "注入 accountId/deviceId"
    Service-->>Client: "正常响应"
  else Token 无效或缺失
    Middleware-->>Client: "401 TOKEN_INVALID"
  end
```

**图表来源**
- [bff/src/middleware/auth.js:1-25](file://bff/src/middleware/auth.js#L1-L25)

**章节来源**
- [bff/src/middleware/auth.js:1-25](file://bff/src/middleware/auth.js#L1-L25)
- [bff/src/services/admin.js:1-24](file://bff/src/services/admin.js#L1-L24)

### 端侧权益缓存与门禁
端侧 `EntitlementStore` 的职责包括：
- 从 `/v1/entitlement` 拉取权益快照，缓存到本地偏好存储，TTL 为 5 分钟。
- 合并旧值与新值：服务端明确返回 `null` 时必须清除本地订阅；字段缺省才沿用旧值。
- 导出门禁：仅对非游客且拥有有效订阅或通行证放行。
- 生成门禁：订阅未满额、持有通行证、或仍有赠送额度时放行；管理员 `unlimited=true` 时直接放行。

```mermaid
classDiagram
  class EntitlementStore {
    +init(context)
    +get()
    +isCacheValid()
    +hasSubscription()
    +hasPass(tripId)
    +canExport(tripId)
    +hasGiftQuota()
    +canGenerate(tripId)
  }

  class QuotaSnapshot {
    +subscription
    +passes
    +giftRemaining
    +remainingToday
    +dailyCap
    +unlimited
  }

  class SubscriptionInfo {
    +status
    +periodEnd
  }

  class PassInfo {
    +localTripId
    +status
    +expiresAt
  }

  EntitlementStore --> QuotaSnapshot : "合并与缓存"
  QuotaSnapshot --> SubscriptionInfo : "引用"
  QuotaSnapshot --> PassInfo : "引用"
```

**图表来源**
- [entry/src/main/ets/data/EntitlementStore.ets:1-200](file://entry/src/main/ets/data/EntitlementStore.ets#L1-L200)

**章节来源**
- [entry/src/main/ets/data/EntitlementStore.ets:1-200](file://entry/src/main/ets/data/EntitlementStore.ets#L1-L200)

## 依赖关系分析
- 权益路由依赖配额服务，不直接操作数据库。
- 配额服务依赖数据库与管理员白名单工具。
- 鉴权中间件独立于业务路由，但为所有受保护路由提供账号上下文。
- 端侧权益缓存依赖 BFF 返回的稳定字段形状，并通过 `ApiConfig` 决定网络层行为。

```mermaid
graph LR
  Auth["auth.js"] --> Routes["routes/*"]
  Entitlement["routes/entitlement.js"] --> Quota["services/quota.js"]
  Trip["routes/trip.js"] --> Quota
  Quota --> DB["db.js"]
  Quota --> Admin["services/admin.js"]
  EntitlementStore["EntitlementStore.ets"] --> ApiConfig["ApiConfig.ets"]
```

**图表来源**
- [bff/src/routes/entitlement.js:1-15](file://bff/src/routes/entitlement.js#L1-L15)
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)
- [bff/src/middleware/auth.js:1-25](file://bff/src/middleware/auth.js#L1-L25)
- [bff/src/services/admin.js:1-24](file://bff/src/services/admin.js#L1-L24)
- [bff/src/db.js:1-136](file://bff/src/db.js#L1-L136)
- [entry/src/main/ets/data/EntitlementStore.ets:1-200](file://entry/src/main/ets/data/EntitlementStore.ets#L1-L200)
- [entry/src/main/ets/common/config/ApiConfig.ets:1-66](file://entry/src/main/ets/common/config/ApiConfig.ets#L1-L66)

**章节来源**
- [bff/src/routes/entitlement.js:1-15](file://bff/src/routes/entitlement.js#L1-L15)
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)
- [bff/src/middleware/auth.js:1-25](file://bff/src/middleware/auth.js#L1-L25)
- [entry/src/main/ets/data/EntitlementStore.ets:1-200](file://entry/src/main/ets/data/EntitlementStore.ets#L1-L200)
- [entry/src/main/ets/common/config/ApiConfig.ets:1-66](file://entry/src/main/ets/common/config/ApiConfig.ets#L1-L66)

## 性能与并发一致性

### 配额预占—提交—释放模型
额度扣减采用三阶段模型：
1. **预占**：`reserveQuota` 插入 `delta=-1`、`state=reserved` 的记录，并支持同键重试时将已释放行重新预占。
2. **提交**：`commitQuota` 将状态改为 `committed`，并写入结算时间。
3. **释放**：`releaseQuota` 将状态改为 `released`，用于失败分支回滚。

```mermaid
flowchart TD
  Reserve["reserveQuota<br/>插入 reserved 行"] --> Success{"上游处理成功?"}
  Success -->|是| Commit["commitQuota<br/>提交为 committed"]
  Success -->|否| Release["releaseQuota<br/>释放为 released"]
  Commit --> Done(["完成"])
  Release --> Done
```

**图表来源**
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)

### 并发保护与幂等
- 行程生成使用 `idempotency_key` 防止重复扣费。
- 同一幂等键同时只有一个请求能抢占到 `pending` 状态；其余请求收到 409。
- 预占失败时立即释放额度，避免泄漏。
- 提交与状态更新在同一事务内执行，保证“提交成功则状态成功”。

### 数据一致性要点
- 订阅有效性同时检查状态与过期时间，避免过期订阅继续送额度。
- 用量统计只计入 `status='succeeded'` 的请求，失败请求不计入月度限额。
- 赠送额度基于 `source='gift'` 且 `state='committed'` 的账本累计，避免未结算行干扰。

**章节来源**
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)
- [bff/src/db.js:1-136](file://bff/src/db.js#L1-L136)

## 错误处理指南

### 常见错误与处理建议
| 场景 | BFF 表现 | 端侧处理建议 |
|---|---|---|
| 缺少或无效 JWT | `401 TOKEN_INVALID` | 提示重新激活设备或重新登录，必要时重新获取令牌。 |
| 额度用尽 | `402 QUOTA_EXHAUSTED` | 跳转定价页或提示购买订阅/通行证。 |
| 频率限制 | `429 RATE_LIMITED` | 提示稍后重试，不要频繁刷新。 |
| 幂等冲突 | `409 IDEMPOTENCY_CONFLICT` | 直接使用上次结果，不应重试。 |
| 模型输出异常 | `502 LLM_INVALID_JSON` 或 `LLM_INVALID_TRIP` | 端侧视为生成重试耗尽，展示对应失败文案。 |

端侧错误映射把 `401`、`402`、`429`、`409` 分别映射到明确的业务错误码，并将 5xx 中的模型内容问题与普通网络问题区分开。

```mermaid
flowchart TD
  Resp["BFF 响应"] --> Status{"HTTP 状态码"}
  Status -->|401| TokenErr["TOKEN_INVALID"]
  Status -->|402| QuotaErr["QUOTA_EXHAUSTED"]
  Status -->|429| RateErr["RATE_LIMITED"]
  Status -->|409| IdemErr["IDEMPOTENCY_CONFLICT"]
  Status -->|5xx| ModelErr["模型内容或网络错误"]
  TokenErr --> HandleToken["提示重新鉴权"]
  QuotaErr --> HandleQuota["跳转付费页"]
  RateErr --> HandleRate["提示重试"]
  IdemErr --> HandleIdem["复用上次结果"]
  ModelErr --> HandleModel["展示生成失败或不可用"]
```

**图表来源**
- [entry/src/main/ets/utils/BffErrorMap.ets:1-41](file://entry/src/main/ets/utils/BffErrorMap.ets#L1-L41)

**章节来源**
- [bff/src/middleware/auth.js:1-25](file://bff/src/middleware/auth.js#L1-L25)
- [bff/src/services/quota.js:1-113](file://bff/src/services/quota.js#L1-L113)
- [entry/src/main/ets/utils/BffErrorMap.ets:1-41](file://entry/src/main/ets/utils/BffErrorMap.ets#L1-L41)

## 结论
- `GET /v1/entitlement` 是当前权益查询的唯一官方端点，返回订阅、通行证、赠送额度、用量与上限。
- 额度检查并非独立端点，而是嵌入生成流程；其核心由 `determineQuotaSource` 与预占/提交/释放三段式账本保障一致性。
- 免费用户默认获得 3 次赠送额度；订阅用户每月最多 20 次；单个行程可购买通行证；管理员白名单仅影响额度门禁。
- 并发安全依赖幂等键、预占行状态与事务提交；失败路径需正确释放额度。
- 客户端应重视 JWT 有效性、权益缓存新鲜度与错误映射，避免因缓存陈旧或错误分类不当导致主路径失败。