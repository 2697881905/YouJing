# INIT_REPORT.md · 有径工程初始化报告（P1–P7）

> 生成日期：2026-10-15。初始化流程 P0–P7 全部完成，验收清单见第 2 节，遗留事项见第 4 节。

## 1. 完成清单

**目录骨架**（P1，`entry/src/main/ets/`）：pages / components / model / data / ai / mock / utils / design / common/{config, constants, error, logger}，职责与依赖方向见 `Docs/ARCHITECTURE.md`。

**文档**（Docs/）：
- `ARCHITECTURE.md`：目录职责表、依赖方向规则、与开发文档 §5.4 差异、命名与标识规范、UI 约定（P1/P4/P5）
- `TECH_STACK.md`：版本锁定表、依赖管理策略、变更记录区（P2）
- `CONTRIBUTING.md`：提交规范、分支策略、本地验收清单、hook 启用步骤（P6）
- 根 `CHANGELOG.md`：Keep a Changelog 结构，首条目「工程基线初始化」（P6）

**源码**：
- `common/constants/BuildConfig.ets`：IS_DEBUG / BUILD_MODE_NAME 单点定义（P3）
- `common/config/ApiConfig.ets`：BASE_URL / LLM_CHAT_ENDPOINT 占位（P3）
- `common/config/MockConfig.ets`：USE_MOCK_DATA 开关（P3）
- `common/logger/Logger.ets`：hilog 封装，YouJing. 前缀，debug 受 IS_DEBUG 门控（P4）
- `common/error/AppError.ets`、`common/error/ErrorCode.ets`：1xxx–4xxx 区段 14 码（P4）
- `entryability/EntryAbility.ets`：onError 接入 Logger.error（P4）
- `design/ColorTokens|SpaceTokens|FontTokens|MotionTokens.ets`：视觉常量单一事实源，数值为占位基线（P5）

**工程配置**：
- `.gitignore`：增补 .preview、签名/密钥文件（*.p7b/*.cer/*.p12/*.csr/*.jks/*.keystore）、.workbuddy/（P3）
- `code-linter.json5`：启用 no-explicit-any / no-unused-vars / explicit-function-return-type / no-console（P6）
- `.gitmessage.txt` 提交模板 + `.git/hooks/pre-commit` 零依赖门禁（console/any 扫描 + hvigor 编译检查），拦截演示通过（P6）
- git 仓库初始化（main 分支），P1–P7 共 9 笔提交全部符合 `type(scope): 中文摘要` 规范

**标准重建流程（固化）**：`pkill -f hvigor` → 删除 `.preview/` → `hvigorw clean` → `assembleHap`。后续凡增删页面或遇到诡异的 `@Entry decorator` 报错（hvigor daemon 缓存假错），先执行此流程再排查代码。构建命令需带 `DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk`。

## 2. 终验结果（P7 验收清单）

| 验收项 | 结果 |
|---|---|
| 全量构建（clean 后 assembleHap debug） | ✅ BUILD SUCCESSFUL，32/33 任务实跑，产物 `entry/build/default/outputs/default/entry-default-unsigned.hap` |
| 目录结构与 ARCHITECTURE.md 一致 | ✅ 11 个目录逐一对应 |
| 配置单点扫描（P3 复跑） | ✅ 业务目录 URL/IP 零命中；IS_DEBUG 全工程仅 BuildConfig.ets 一处定义 |
| token 裸值扫描（P5 复跑） | ✅ pages/components 裸色值零命中、fontSize/padding/margin/gap 裸数值零命中 |
| ErrorCode 码值无重复 | ✅ 14 码，重复 0 |
| TECH_STACK.md 与实际配置一致 | ✅ 逐项核对通过；`ohpm install --all` 后 lock 零 diff；运行时依赖为空 |
| git log 符合提交规范 | ✅ 不合规提交数 0 |

## 3. 工具链版本快照

见 `Docs/TECH_STACK.md` 版本锁定表（不在此重复罗列）。关键项：API 26 / DevEco Studio 26.0.0.851 / hvigor 6.26.8 / 内置 Node v24.14.1 / ohpm 26.0.0.630。

## 4. 已知限制与待办

1. **bundleName 已定稿** `com.youjing.app`（2026-10-15，参考有据 com.youju.app 命名）；AGC 应用注册在自动签名时一并完成，上架前需核对应用市场重名。
2. **调试签名已就绪**（2026-10-20）：DevEco Studio 自动签名生成，Profile 绑定 `com.youjing.app`、debug 类型、有效期 2026-10-20 → 2027-10-20、含 4 台设备；签名 HAP 已安装到本地模拟器验证通过。签名材料仅存本机 `~/.ohos/config/`，signingConfigs 不入 git（build-profile.json5 已 skip-worktree）。release 签名上架前仍需单独申请。
3. **应用名称未定**：AppScope label 当前为 "YouJing"，中文名「有径」待品牌资源定稿后替换。
4. **API 26 最低兼容范围未评审**：compatibleSdkVersion=26.0.0 意味着不兼容更低版本设备，上架前需评审覆盖面。
5. **小艺 Skill 接入协议待调研**：ApiConfig 端点为占位空串，待小艺开放平台 Skill 创建后回填。
6. **日志输出已真机补验通过**（2026-10-20，本地模拟器）：四级 Logger 临时调用注入 → 签名 HAP 安装启动 → hilog 按 `YouJing.` 过滤抓到 D/I/W/E 全部四条（domain A00100），验毕临时代码已删除、还原版已重装。
7. **deveco_mcp 的 PROJECT_PATH 指向 HarmonyProject1**（旧工程）：MCP 的 build/check 工具对本工程无效，初始化期间一律以本地 hvigor 直跑替代；需在 MCP 配置中改指向本工程后方可使用。
8. **LSP 静态检查（check_ets_files）不可用**：20s 超时无诊断返回，静态检查以 hvigor CompileArkTS 为准。
9. **设计 tokens 数值为占位基线**：色值/间距/字号待用户 UI 设计定稿后替换（单点改 token 文件即可全工程生效）。
10. **ohosTest 进程拿不到合法模块 context**（2026-10-22 探针用例实测）：测试进程只挂 ApplicationContext，`relationalStore.getRdbStore` 报「Parameter error.Illegal context.」、`preferences.getPreferences` 报「The context is invalid.」，`application.createModuleContext()` 亦直接报「must be a context of stageMode」。因此 RDB 读写、迁移、账号分片持久化**不能**写成 hypium 用例，只能在真机 App 内以启动日志 + 界面走查验收；纯逻辑（Schema 守卫、Prompt、种子映射、登录态兜底）仍走 hypium。若后续要补 DB 单测，需在 ohosTest 侧加 TestAbility 并由 runner 启动后取 context。
10b. **阶段 10 两项按数据/凭据缺口暂缓（不编数）**：
    - **预算协同分析**：需要各住宿区域「价位段/晚」真值。种子库 `area` 只有 `priceTier`（经济/舒适/豪华）
      与 `price_range` 字段位，**未采集到价格数据**，故不生成任何金额结论；
      已把 `priceTier` 落到消费方（屏5 区域卡元信息行 + PromptBuilder 住宿区域行），
      等真实价位数据到位后只需补 `price_range` 灌入与一段换算。
    - **足迹地图**：Map Kit 需 AGC 项目凭据；当前无凭据，屏8/16 地图区仍为渐变占位、
      区域经纬度为区级近似值（`DataSeeder.DistrictCoords`，注释已标待地理编码替换）。
11. **Account Kit 未配置**：AGC 侧无 Client ID / 证书指纹未登记，`AccountConfig.ACCOUNT_KIT_ENABLED=false`，屏1「华为账号一键登录」实际走本机游客分区（uid=`local-guest`，行程数据仍只留本机，与屏1 法务行承诺一致）。真机验收证据：启动日志「恢复登录态 kind=guest uid=local-（掩码）」「迁移完成 1 → 2」。AGC 配置就绪后只改该开关，静默登录与游客数据归户（`TripDao.adoptGuestTrips`）即生效。

## 4b. 需要产品/设计确认的文案改动（agent 已按「能力对齐文案」原则改口）

1. 屏14「行程卡片」副文案：`每 15 分钟刷新` → `随系统周期刷新（最小 30 分钟）`。
   原因：`form_config.json` 的 `updateDuration` 最小粒度是 30 分钟，15 分钟做不到。
2. 屏16 主按钮与说明：`复制链接 / 链接 7 天内有效` → `分享行程文本 / 内容在本机生成，不上传服务器、不含账号信息`。
   原因：本项目纯 ArkTS 无后端，生成不了带有效期的分享链接；改为走系统分享面板发行程文本 + `.ics` 文件。
3. 屏10 详情面板删掉底稿里的 mock 事实（山脚入口 / 开放时间全天 / 建议时段 06:30–08:00 / 红叶季拥挤 /
   上一站「一条」下一站「东福寺」/ 门票 ¥0），改为只显示模型里真有的字段，无数据即显示 `—`。
   若这些字段要保留，需要 Spot 库补营业时间、票价、拥挤提示三类数据，并在 Activity 上带 spotId。

## 5. 发布前 checklist

- [ ] `BuildConfig.IS_DEBUG` 翻转为 false（手动，禁止 hvigor -p 透传）
- [ ] `MockConfig.USE_MOCK_DATA` 置为 false
- [ ] 网络配置（ApiConfig）变更后执行全量重编并重装 HAP
- [ ] 签名配置就绪（release 证书 + Profile）

## 6. 当前进度（开发文档 §6 十阶段）

阶段 1–8 已完成并真机验收（屏1–16 骨架 + 种子库 + Schema 守卫 + RDB + LLM 离线闭环 + 多轮交互全流程 + 账号分区）。
剩余：阶段 9（小艺 Skill 接收端 / 万能卡片真数据 / 日历真写入）、阶段 10（费用落库 / 分享导出 .ics / 预算协同）。
