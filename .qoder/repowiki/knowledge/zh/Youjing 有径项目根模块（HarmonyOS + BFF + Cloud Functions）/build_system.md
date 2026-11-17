## 1. 构建系统总览

本项目是 HarmonyOS NEXT 应用（ArkTS）+ Express BFF + AGC 云函数的聚合仓库，构建编排围绕 **Hvigor**（HarmonyOS 官方构建引擎）与 **oh-package**（DevEco Studio / hvigor-ohos-plugin）展开。Node.js 侧的 BFF 和云函数各自使用 `npm`/`node --test` 独立管理依赖。

仓库根目录没有 Makefile、Dockerfile 或 GitHub Actions 等 CI 配置；发布/部署流程未在本仓库内固化，仅保留开发期辅助脚本。

## 2. 关键文件

| 文件 | 作用 |
|---|---|
| `hvigorfile.ts` | 根级 Hvigor 入口，加载 `@ohos/hvigor-ohos-plugin` 的 `appTasks` |
| `entry/hvigorfile.ts` | entry 模块级 Hvigor 入口，加载 `hapTasks` |
| `build-profile.json5` | 根构建配置：签名、product、targetSdkVersion=26、debug/release 双 buildMode、modules 列表 |
| `entry/build-profile.json5` | entry 模块配置：`stageMode` API、release 下 ArkTS 混淆开关、`default` 与 `ohosTest` 两个 target |
| `tools/build_install.sh` | 封装 `assembleHap` + `hdc install` 的开发机一键装机脚本 |
| `entry/obfuscation-rules.txt` | release 模式下 ArkTS 代码混淆规则白名单 |
| `bff/package.json` | BFF Node 服务依赖与脚本（start/dev/test/migrate/sync:prompt/preflight） |
| `cloud/pickSpots/package.json`、`cloud/replanDay/package.json` | AGC 云函数各自的 Node 依赖与 `node --test` 测试入口 |
| `hvigor/hvigor-config.json5` | Hvigor 全局配置（路径存在，内容未在证据中展开） |

## 3. 架构与约定

### 3.1 ArkTS 应用（entry 模块）

- 通过 `hvigor assembleHap` 生成 HAP 包，产物路径固定为 `entry/build/default/outputs/${MODULE}/entry-${MODULE}-signed.hap`。
- 只维护一个 product `default`，对应 `runtimeOS: "HarmonyOS"`、`targetSdkVersion: "26.0.0"`、`compatibleSdkVersion: "26.0.0"`。
- 构建模式分 debug 与 release 两种；release 开启 ArkTS 混淆（但默认 `enable: false`，需显式打开），混淆规则位于 `entry/obfuscation-rules.txt`。
- 模块划分：根 `build-profile.json5` 声明 modules 数组，目前仅包含 `entry`，srcPath 指向 `./entry`。
- entry 模块暴露两个 target：`default`（主 App）和 `ohosTest`（hypium 测试包）。
- 签名配置硬编码在根 `build-profile.json5` 的 signingConfigs 中（含 certpath、storePassword 等），是本地调试签名。
- 根 `hvigorfile.ts` 使用内置插件 `appTasks`，`entry/hvigorfile.ts` 使用 `hapTasks`，两者都声明 `plugins: []`，即无自定义 Hvigor 插件扩展。

### 3.2 BFF 后端（bff/）

- 标准 Node ESM 项目（`"type": "module"`），Express + better-sqlite3 + jsonwebtoken + dotenv。
- 通过 `package.json.scripts` 暴露 `start`、`dev`（`node --watch`）、`migrate`、`test`（`node --test test/*.test.js`）、`preflight`、`sync:prompt` 等命令。
- 测试统一使用 Node 原生 `--test` runner，无需额外测试框架。

### 3.3 云函数（cloud/）

- `pickSpots` 与 `replanDay` 是两个独立的 AGC Node 运行时云函数，各自有独立 `package.json` 与 `index.js` 入口。
- 共享子目录 `prompt/` 下的 AI prompt 构建逻辑被同时引用到 BFF 与 cloud 两侧。

### 3.4 开发期工具（tools/）

- `tools/build_install.sh` 是核心开发脚本：先执行 `hvigorw.js assembleHap`，检查日志中是否出现 `BUILD SUCCESSFUL`，再校验 HAP 产物时间戳是否在最近 5 分钟内（防止 UP-TO-DATE 复用旧包），最后调用 `hdc install -r` 安装。
- 脚本强制要求 `DEVECO_SDK_HOME` 环境变量（默认 `/Applications/DevEco-Studio.app/Contents/sdk`），并直接引用 DevEco Studio 安装路径中的 `hvigorw.js` 与 `hdc`。
- 支持可选参数 `$1` 选择模块：缺省为 `default`（App 本体），传 `ohosTest` 则构建 hypium 测试包。
- 通过 `HDC_TARGET` 环境变量指定 hdc 目标设备，避免多设备时 `install` 报错。

## 4. 约定与约束

- **构建入口**：ArkTS 应用通过 Hvigor 构建，BFF 与云函数通过 Node `package.json` scripts 运行，二者不混用。
- **产品形态单一**：根构建 profile 仅定义一个 product `default`，未见多 flavor / 多渠道构建。
- **SDK 版本锁定**：`targetSdkVersion` 与 `compatibleSdkVersion` 均固定为 `26.0.0`（见 `build-profile.json5`）。
- **ArkTS 混淆策略**：release 模式下混淆规则启用项 `enable` 默认为 `false`，且规则文件路径固定为 `./obfuscation-rules.txt`（见 `entry/build-profile.json5`）。
- **构建产物位置固定**：HAP 产物必须落在 `entry/build/default/outputs/${MODULE}/entry-${MODULE}-signed.hap`，否则 `tools/build_install.sh` 会拒绝装机（脚本内硬编码该路径）。
- **UP-TO-DATE 防护**：`tools/build_install.sh` 明确拒绝“构建成功但产物时间戳超过 5 分钟”的情况，因为 hvigor 缓存可能返回旧包（脚本注释写明原因）。
- **装机成功判据**：不仅检查 `hdc install` 退出码，还要求输出中包含 `install bundle successfully` 且不含 `[Fail]` 字符串（脚本内双重 grep）。
- **无 CI 流水线**：仓库未包含 `.github/workflows`、`.codeartsdoer` 外的 CI 配置；CodeArtsDoer 目录用于 AI Agent 协作配置，不是传统 CI。
- **测试命令规范**：BFF 使用 `node --test`，cloud 函数同样使用 `node --test`，ArkTS 端通过 ohosTest target + hvigor 构建 Hypium 测试包。
- **Node 版本要求**：云函数 `cloud/pickSpots/package.json` 通过 `engines.node >= 18` 声明最低 Node 版本。
- **依赖锁定**：BFF 使用 `package-lock.json`，ArkTS 工程使用 `oh-package-lock.json5`，确保可重复安装。
