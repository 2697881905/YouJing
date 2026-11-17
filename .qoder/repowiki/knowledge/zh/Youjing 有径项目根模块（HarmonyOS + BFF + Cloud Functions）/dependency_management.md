## 1. 使用的系统/工具

本项目采用**双栈依赖管理**：

- HarmonyOS ArkTS 应用与模块：使用 **oh-package / hvigor** 体系，根目录 `oh-package.json5`、`oh-package-lock.json5` 以及每个 module 下的 `oh-package.json5`（如 `entry/oh-package.json5`）声明依赖，由 `hvigorfile.ts` 统一编排构建。
- Node.js 服务与脚本：使用 **npm**，根 `package.json` + `package-lock.json`，并在子模块 `bff/package.json`、`cloud/pickSpots/package.json`、`cloud/replanDay/package.json`、`cloud/pickSpots/prompt/package.json` 各自独立声明依赖。

项目未使用 Go、Rust、Cargo、Pip、Yarn/PNPM 等其它包管理器。ArkTS 第三方库全部通过 `@kit.*` 命名空间（如 `@kit.AbilityKit`、`@kit.BasicServicesKit`）以 HarmonyOS SDK kit 的形式引入，而非 npm 包。

## 2. 关键文件

| 路径 | 角色 |
|---|---|
| `oh-package.json5` | 根 oh-package 清单，仅声明 devDependencies（`@ohos/hypium`、`@ohos/hamock`），无运行时依赖 |
| `oh-package-lock.json5` | oh-package 的锁文件，用于冻结 ArkTS 依赖版本 |
| `entry/oh-package.json5` | entry 模块清单，当前 `dependencies` 为空，业务逻辑通过内部 ETS 模块引用 |
| `package.json` | 根 npm 清单，唯一依赖为 `@qodercn-ai/qodercn-agent-sdk ^1.0.58`，服务于 `.codeartsdoer/` Agent 配置 |
| `bff/package.json` | BFF 服务清单，依赖 express、better-sqlite3、jsonwebtoken、uuid、dotenv |
| `cloud/*/package.json` | AGC 云函数清单，标记 `"private": true`，仅声明测试脚本与 `engines.node >= 18` |
| `cloud/pickSpots/prompt/package.json` | prompt contract 生成器子包，随 BFF 部署 |
| `hvigorfile.ts`、`hvigor/hvigor-config.json5` | hvigor 构建入口与配置 |

## 3. 架构与约定

- **按模块拆分 manifest**：每个独立的 Node.js 子系统（BFF、两个 cloud 函数、prompt 生成器）都有自己 `package.json`，避免共享依赖膨胀；HarmonyOS 侧 entry 模块的 `oh-package.json5` 保持空 dependencies，所有业务代码通过同仓内 ETS 模块引用。
- **SDK 依赖走 oh-package**：ArkTS 端只依赖 HarmonyOS SDK (`@kit.*`) 和测试框架 (`@ohos/hypium`、`@ohos/hamock`)，没有把 UI 组件库或业务库发布到 ohpm。
- **Node 依赖按子系统隔离**：BFF 是唯一的完整 Node 应用；cloud 云函数仅声明运行所需的最小依赖，且通过 `engines.node = ">=18"` 约束运行时。
- **无 vendoring**：未发现 `vendor/`、`node_modules/` 被提交；Lockfile 存在，实际安装发生在 CI/开发环境。
- **私有 registry / mirror**：未见 `.npmrc`、`.ohpmrc`、`GOPRIVATE` 等配置；依赖来源依赖默认源与 ohpm 默认源。

## 4. 约定与约束

- ArkTS 第三方依赖通过 `oh-package.json5` 的 `dependencies` / `devDependencies` 字段声明，并由 `oh-package-lock.json5` 锁定版本（根清单已体现）。规则来源：oh-package 规范与仓库中存在的 lock 文件。
- Node.js 依赖通过各子目录 `package.json` 的 `dependencies` 声明，并由对应 `package-lock.json` 锁定；BFF 与 cloud 函数各自独立安装，互不共享 `node_modules`。规则来源：多 `package.json` 的布局与各自独立的 lock 文件。
- Cloud 函数子包标记 `"private": true`，表明它们不作为公共包发布。规则来源：`cloud/pickSpots/package.json`、`cloud/replanDay/package.json`。
- Cloud 函数要求 Node ≥ 18，通过 `engines.node` 声明。规则来源：两个 cloud 包的 `engines` 字段。
- ArkTS 端不使用外部 npm 包，仅依赖 HarmonyOS SDK (`@kit.*`)；业务代码通过相对路径的 ETS 模块组织（如 `PlanTripSkill.ets` import `../../../src/main/ets/data/SkillPrefill`）。规则来源：`entry/oh-package.json5` 的 empty dependencies 及源码中的 import 路径模式。
- 根级 `package.json` 仅承载 `.codeartsdoer/` Agent 工具的依赖，不对应用构建产生直接作用。规则来源：其内容仅为 `@qodercn-ai/qodercn-agent-sdk` 一个依赖项。

当前仓库在依赖管理上较为轻量：没有私有 registry、没有 monorepo 工具（pnpm workspace / lerna）、没有自动升级机器人配置，主要靠开发者手动维护 lockfile。