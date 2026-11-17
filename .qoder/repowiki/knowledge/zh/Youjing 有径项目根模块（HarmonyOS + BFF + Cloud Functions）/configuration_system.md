## 1. 架构概览

### 端侧配置分层

| 层次 | 文件 | 用途 | 是否可发布 |
|---|---|---|---|
| 网络/外部服务 | `ApiConfig.ets` | BFF 地址、LLM 端点、重排云函数、天气 API、超时、模型参数 | 是（不含 Key） |
| 直连 LLM 兜底 | `DirectConfig.ets` | OpenAI 兼容 URL + KEY + MODEL（开发期旁路） | **否**，注释明确“不上架” |
| 精选云函数 | `PickConfig.ets` | AGC 云函数触发器 URL + TOKEN | 是（TOKEN 非密钥级机密） |
| Mock 路由 | `MockConfig.ets` | `USE_MOCK_DATA` 开关 | 是，但 release 前必须置 false |
| 账号 | `AccountConfig.ets` | Account Kit 开关、Preferences key、游客 UID | 是 |
| 构建模式 | `BuildConfig.ets` | `IS_DEBUG` / `BUILD_MODE_NAME` | 是，release 前需翻转 |

所有端侧配置都遵循同一模板：先声明 `XxxConfigType` interface，再导出同名 const 对象。类型定义同时充当契约文档，任何新增字段都必须先在 interface 中声明。

### 后端配置

BFF 使用 `dotenv.config()` 加载 `.env`，只暴露 `PORT` 一个变量给业务代码；其余凭据（LLM Key、数据库连接、华为 IAP 证书等）通过各 service 模块直接读取 `process.env.*`，没有统一的环境加载器。

## 2. 关键约定

### 2.1 单点定义纪律

- `ApiConfig.ets` 头部注释强制“全工程所有 URL / 端点常量只能定义在此文件”，并警告修改后需全量重编重装 HAP（hvigor 增量构建可能不重编引用方）。
- `BuildConfig.ets` 注释写明“全工程唯一定义点（IS_DEBUG / BUILD_MODE_NAME 不得在他处重复定义）”。
- `AccountConfig.ets` 同样以“单点定义”自述，变更只需改一处。

### 2.2 开发/发布双轨

- `DirectConfig.ets`：URL/KEY 为空时不启用直连，回退 BFF 或本地合成；要求开发者用 `git update-index --skip-worktree` 标记该文件防误提交，且上架前必须迁云。
- `ApiConfig.DEV_SKIP_BFF`：开发态旁路开关，注释详述其语义——BFF 未配置时让行程生成走 `MockLlmTransport`，而非抛 `LLM_UNAVAILABLE`。
- `MockConfig.USE_MOCK_DATA`：注释明确要求“发布 release 前必须置为 false（列入 Docs/INIT_REPORT.md 发布 checklist）”。
- `BuildConfig.IS_DEBUG`：注释要求“发布 release 前必须手动翻转 IS_DEBUG 为 false，并逐项核对 Docs/INIT_REPORT.md 的发布前 checklist”。

### 2.3 空值即禁用

多个配置以空字符串作为“禁用/回退”信号：
- `ApiConfig.BFF_BASE_URL: ''` → LlmClient 走 Mock 或报 `LLM_UNAVAILABLE`。
- `ApiConfig.REPLAN_URL: ''` → 不请求云端，直接走本地兜底。
- `PickConfig.URL: ''` → `PickClient` 回退到 `ApiConfig.BFF_BASE_URL + /v1/pick/spots`。
- `DirectConfig.URL/KEY` 任一为空 → 不启用直连。

### 2.4 权限与配置分离

`module.json5` 中的 `requestPermissions` 是 HarmonyOS 系统权限声明，不是应用配置；真正的运行时开关集中在上述 `config/` 目录。例如 `ACCOUNT_KIT_ENABLED` 控制是否发起真实 UnionID 登录，而不是通过系统权限开关。

## 3. 约束与规则

- **禁止 hvigor 构建参数透传运行时开关**：`BuildConfig.ets` 注释明确指出“已验证不可靠（有据项目 BUILD_MODE_NAME 教训），环境开关一律以本文件源码常量为准”。这是唯一被显式记录的硬性规则。
- **AkTS 配置变更需全量重编**：`ApiConfig.ets` 头注强制要求全量重编并重装 HAP，因为 hvigor 增量构建可能不重编引用方。
- **Key 不出包**：`DirectConfig.ets` 明确要求“发布包不能带 Key”，直连 LLM 是 P0 兜底、不上架的方案。
- **Release 检查清单**：`MockConfig` 与 `BuildConfig` 均指向 `Docs/INIT_REPORT.md` 的发布 checklist，作为人工校验入口。
- **BFF 环境变量来源单一**：仅通过 `dotenv.config()`，未做 schema 校验；`PORT` 有默认值 3000，其他环境变量在 service 层直接使用 `process.env.X`，无集中校验。

## 4. 缺失项

仓库没有以下常见机制：
- 没有 `.env` 模板文件或 `.env.example`。
- 没有运行时配置热重载。
- 没有远程配置中心（Feature Flag）、A/B 测试开关或动态下发配置。
- 没有统一的配置 schema 校验（如 Zod/Yup），BFF 端 `dotenv` 也不做字段存在性校验。
- 没有用户级偏好设置持久化（除 AccountKit 登录态写入 Preferences 外），当前配置全部是部署/构建期常量。