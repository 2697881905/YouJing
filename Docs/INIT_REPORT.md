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

1. **bundleName 已定稿** `com.youjing.app`（2026-10-15，参考有据 com.youju.app 命名）；AGC 应用已注册（2026-10-23，应用名「有径」，APP ID `6917619826312400726`，项目「有径」/ projectId `101653523865420226`），上架前需核对应用市场重名。
2. **调试签名已就绪**（2026-10-20 生成，2026-10-23 换 Profile）：证书与 p12 由 DevEco 自动签名生成（有效期 2026-10-20 → 2027-10-20）；Profile 含 4 台设备；Profile 改用 AGC 手动创建的 `youjing-debug-20261023` —— 自动签名生成的 Profile 带随机 `app-identifier`（`6918745435470575450`），Account Kit 报 `1001502003`；手动 Profile 的 `app-identifier` 才是 APP ID。Profile 内嵌证书与本机 `.cer` 同一张，`hdc install -r` 签名一致，登录态与行程数据跨重启保留。签名材料仅存本机 `~/.ohos/config/`，signingConfigs 不入 git（build-profile.json5 已 skip-worktree）。Profile 有效期至 2027-10-20，到期需重签；release 签名上架前仍需单独申请。
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
    - **足迹地图**：Map Kit 需 AGC 项目凭据；当前无凭据。另有一条**比凭据更硬的数据缺口**：
      `DataSeeder.toArea` 给同城所有片区填同一个 `DistrictCoords.lookup(city, city)` 城市质心，
      所以即便接了 Map Kit，片区在图上也会叠成一个点——要先给区域库补逐区域经纬度。
      今日已把三处「像有地图其实没有」的呈现收口：屏5 地图卡改候选片区图例（不暗示方位）、
      屏8 地图区只显真统计芯片、dock「地图」落点改说人话（见 §4b-6/8）。
10c. **玻璃点位①③按色彩模式分流（2026-10-23 双模式实测定案）**：
   顶栏与浮动 dock 接 `uiMaterial.ImmersiveMaterial`（顶部 ULTRA_THIN、底部 THIN，均带投影）。
   真机同页两模式对比：
   - **浅色**：dock 标签清晰，滚动内容被虚化成柔和色块，玻璃观感成立 → **采纳材质**；
   - **深色**：近黑底上模糊≈透明，「建议停留…」「步行 15分钟…」直接穿透压到
     「行程/地图/费用/我的」标签上，可读性明显变差，且 ULTRA_THIN/THIN/THICK 三档截图无可辨差异
     → **回退实色** `surfaceElevated` + 1px 描边（深色零阴影契约不变）。
   实现条件为 `glassOn && !isDark`；点位②分段控件与两处 Sheet 材质不受模式影响，一直走系统材质。
   点位④（吸顶日标题）底稿本就是无底文字行，未擅自加胶囊材质，待设计定。
11. **Account Kit 已接入**（2026-10-23 完成）：AGC 侧 APP ID / Client ID 均为 `6917619826312400726`，调试证书 SHA256 指纹 `86:6F:…:CF:70` 已登记，Client ID 与 APP ID 相同（无需 `client_id` metadata）；`AccountConfig.ACCOUNT_KIT_ENABLED=true`。真机验收：屏1 点击后 `LoginWithHuaweiID error_code=0`、`YouJing.Data.AccountStore: 静默登录成功 uid=AABKND***`，落到屏2；冷重启日志「恢复登录态 kind=huawei uid=AABKND***」。游客期行程归户走 `TripDao.adoptGuestTrips`。换签名时必须用 AGC 手动 Profile（见 #2）。
12. **`AceSheet: radius is not correct type` 是框架噪声，非本工程配置问题**（2026-10-23 归因实验）：
    真机每次开半模态都在 E 级日志打这一行，怀疑过是 `SheetOptions.systemMaterial` 传错。
    对照实验：屏2 城市面板是**不带** `systemMaterial` 的裸 `bindSheet`（只有 height/backgroundColor/showClose），
    `hilog -r` 清缓冲后单独打开它，同样报这一行（还伴随 I 级 `Bottom offset invalid`）。
    全工程没有任何一处给 bindSheet 传 `radius`，SDK `@ohos.arkui.uiMaterial.d.ts` 里也没有 radius 字段。
    结论：API 26 下 bindSheet 应用自身默认圆角时的框架内部报错，视觉结果（圆角与材质）真机截图均正常，
    后续走查**不要**再把它当缺陷查。

## 4b. 需要产品/设计确认的文案改动（agent 已按「能力对齐文案」原则改口）

1. 屏14「行程卡片」副文案：`每 15 分钟刷新` → `随系统周期刷新（最小 30 分钟）`。
   原因：`form_config.json` 的 `updateDuration` 最小粒度是 30 分钟，15 分钟做不到。
2. 屏16 主按钮与说明：`复制链接 / 链接 7 天内有效` → `分享行程文本 / 内容在本机生成，不上传服务器、不含账号信息`。
   原因：本项目纯 ArkTS 无后端，生成不了带有效期的分享链接；改为走系统分享面板发行程文本 + `.ics` 文件。
3. 屏15 底部说明：`打卡会同步到日历和卡片` → `打卡与记账只存本机，不上传服务器`。
   原因：打卡目前不回写日历事件、也不触发卡片即时刷新（卡片按系统周期刷新），原句是兑现不了的承诺。
4. 屏10 详情面板删掉底稿里的 mock 事实（山脚入口 / 开放时间全天 / 建议时段 06:30–08:00 / 红叶季拥挤 /
   上一站「一条」下一站「东福寺」/ 门票 ¥0），改为只显示模型里真有的字段，无数据即显示 `—`。
   若这些字段要保留，需要 Spot 库补营业时间、票价、拥挤提示三类数据，并在 Activity 上带 spotId。
5. 屏14「写入内容预览」第四行：`备注 行程第 N 天 · 步行到达` → `备注 <地点>[ · <排期理由>]`。
   原因：日历事件的 description 实际写的是 `location`（有 `reason` 时附在后面），原句既多写了没落库的
   「行程第 N 天」，又在当日首站（`transport` 为空）时把不存在的通勤说成「步行到达」。
   预览与真写入对齐后，同时修掉屏10 动线条首/末站的越界序号（前一格显 `0`、后一格显 `N+1`）。
6. dock「地图」落点页：`骨架占位 / 路由「Map」将在后续批次按设计底稿落地` →
   标题「地图视图」+ 一句说明（要接 Map Kit、需 AGC 开通并重新签名、动线现按时间线呈现）+「返回行程」按钮。
   原因：原句是工程内部话术（批次、路由名），却已经出现在装机可点到的路径上。
   **待设计**：底稿 39 帧里 dock 的四项含「地图」，但没有对应的地图屏（屏13 是万能卡片）；
   这一格目前只有说明页，要真做地图视图需要先出帧。
7. 屏5 区域卡三列：`步行 12分钟｜到首个景点` `34分钟｜日均通勤` `9 家｜舒适型房源` →
   `45分钟｜到机场` `12分钟｜到火车站` `高｜餐饮密度`。
   原因：底稿那三项要的是路径规划与住宿库存，本项目两者都没有（§7 明确不接第三方住宿服务），
   而代码里此前是按卡片序号现算的 `8 + i * 4` / `30 + i * 6` / `9 + i * 7`——用户看到的却是真数。
   新三列全部取 `Area` 真字段（`airportMinutes` / `trainStationMinutes` / `diningDensity`），版式不变。
8. 屏5 顶部地图卡：`动线地图 · Map Kit 批次接入` → 候选片区图例（三枚芯片 +「按推荐顺序排列」）。
   原因有二：原句把「批次」这种工程话术露到用户界面；更根本的是**画不出真位置**——
   `DataSeeder.toArea` 给所有片区填的是 `DistrictCoords.lookup(city, city)`，即同城 36 个片区共用
   同一个城市质心坐标，按经纬度布点等于编位置。所以这格只留 route-paper 底色 + 芯片，不暗示相对方位。
   同屏底部按钮 `帮我选（按通勤最短）` → `帮我选（推荐第一片）`：处理函数就是选 `picks[0]`，
   「通勤最短」是它没做的事。
   **要做真地图/真通勤，前置条件是区域库补逐区域经纬度 + Map Kit 凭证**，二者缺一都只能保持现在的图例形态。
9. 屏5 区域卡副信息行 `maxLines` 1 → 2：加进「锚定 X站」后最长串实测 30 字
   （深圳 大鹏-较场尾「舒适档 · 地铁 E11接驳 · 锚定 大鹏中心(公交接驳)」），单行必截。
   当前四城首屏 12 张卡最长 26 字，两行内可完整放下，真机已无省略号。
10. 屏5 角标：`AI 精选 1` → `精选 1`；第二/三名的 `交通枢纽` 改成按 `Area.group` 取
    （core=核心地段 / commercial=商圈便利 / metro=交通枢纽）。
    原因有二：片区顺序来自种子库的编排顺序，模型没有参与区域排序（它只排景点），「AI 精选」是替模型认领了
    人做的事；旧写法是 `i === 0 ? … : (commercial ? 商圈便利 : 交通枢纽)`，于是北京「前门-大栅栏」、
    上海「外滩-十六铺」、深圳「香蜜湖-农园」这三片 `group=core` 全被贴成「交通枢纽」。
    真机复验：北京三片角标现为 精选 1 / 核心地段 / 商圈便利。
11. 桌面卡片 2×2 的标题与 footer 在真机上被系统省略号截断（`Day 1 · 10月…`、`还有 1 个需预约节点 · …`）。
    原因：底稿屏13 的 Widget A 在 360vp 机身框里画满了容器宽（328px），真机 2×2 格的文本区
    dumpLayout 实测只有 134vp（`[87,1152]–[507,1451]`）；实现已把标题降到 18（底稿 21），仍放不下
    `Day 1 · 10月23日`，footer 11 号也放不下 16 字。**已定（2026-10-23，用户选 a）**：
    接受系统省略号，完整信息回 App（点卡片直达屏8），不另做 2×2 收口文案。
    2×4 的 16 内缩已补上真尺寸通路（见 §6 卡片验收）。

## 4c. 阶段 2 验收：空 / 部分 / 异常 三态走查（2026-10-23 真机）

| 态 | 屏 | 结论 | 证据 |
|---|---|---|---|
| 空 | 屏11 费用 | 通过 | 无 tripId 直达：`预算 ¥0 · 0 人 · 0 天`，分类区与流水区各自显示引导文案 |
| 空 | 屏15 旅行中 | 通过 | 无 tripId 直达：`今日暂无安排` + `还没有打卡节点`，按钮不崩 |
| 空 | 屏16 分享 | 通过 | 无 tripId 直达：`行程未就绪`，统计三格为 0 |
| 空 | 屏12 行程列表 | 通过 | 临时把列表读取短路成 `[]`（不删任何用户数据）后真机见 `还没有行程` + 引导语 + `创建新行程`，验毕还原 |
| 部分数据 | 屏8 / 屏10 | 通过 | 活动缺 `transport` → 不画通勤腿、详情显 `—` 与「当日首站，无通勤」；缺 `note`/`reason` → 对应块整体不渲染 |
| 异常 | 屏7 生成受阻 | 通过 | 临时置 `USE_MOCK_DATA=false` 走 HTTP 分支真跑：日志 `生成失败 code=4004: 两次生成均失败: LLM 端点未配置（ApiConfig 占位）`，屏7 显示「试了两次都没排通」+ 该诊断，两条修法可跳转；验毕开关还原 true |
| 异常 | 生成前校验 | 通过 | hypium `guard_*` 系列 + `retry_exhausted` + `guard_end_time_not_later`（40/40） |

原始诊断文本只在 `BuildConfig.IS_DEBUG` 为真时露出，release 显示引导语，不把 `ApiConfig 占位` 这类技术文本甩给用户。

## 5. 发布前 checklist

- [ ] `BuildConfig.IS_DEBUG` 翻转为 false（手动，禁止 hvigor -p 透传）
- [ ] `MockConfig.USE_MOCK_DATA` 置为 false
- [ ] 网络配置（ApiConfig）变更后执行全量重编并重装 HAP
- [ ] 签名配置就绪（release 证书 + Profile）

## 6. 当前进度（开发文档 §6 十阶段）

阶段 1–10 全部落地并真机验收（屏1–16 + 种子库 + Schema 守卫 + RDB v1→v4 + LLM 离线闭环 +
多轮交互全流程 + 账号分区 + 日历真写入 + 卡片真数据 + 外部拉起参数通道 + 费用落库 + `.ics` 导出）。
hypium 40/40；RDB/账号/日历路径按已知限制 #10 走真机验收。

**十阶段里没做的只剩三项，都不是代码缺口而是数据/凭证缺口：**

| 项 | 缺什么 | 需要谁动 |
|---|---|---|
| 预算协同（阶段10） | 种子库没有「区域真实价位区间」字段，任何分档差异都会是编造数字 | 产品定数据来源，或砍掉该功能 |
| 足迹地图（阶段10） | Map Kit 凭证与 Client ID 未申请；底稿也没有地图屏的帧。dock「地图」现在落到一句实话说明页 | 提供 AGC 地图凭证 + 出一帧地图设计 |
| 小艺 Skill 平台侧（阶段9） | 应用侧接收端已就绪并真机验证；平台侧建 Skill 需在 AGC 操作 | 见 `Docs/小艺Skill接入清单.md`，用户执行 |

另有两项待用户决策：§4b 前十处改口文案确认、点位④吸顶日标题是否给胶囊材质
（§4b-11 卡片 2×2 截断已定 (a) 接受省略号）。Account Kit 的 AGC 凭证已于 2026-10-23 配齐并真机验收。

**2026-10-23 今日改动后的全链路复跑**（真机，逐步截图 `f1_屏1`…`f7_屏8`）：
屏1 静默登录 → 屏2 开始规划 → 屏3 四步追问（末题 CTA 是「生成行程」，不是「下一题」）→
屏4 选点（`已选 0 / 可用 3.0 天 · 建议上限 12 个` 为真派生）→ 屏5 三片角标 精选 1/核心地段/商圈便利 →
屏6 生成 → 屏8 渲染 `北京 · 3天2晚` + Day 1 故宫/八达岭/颐和园 + dock 四标签。七段全 OK。
屏8/10/11/12/14/15 的 dock 与面板链见 §4b-6 与提交记录；hypium 40/40。

**2026-10-23 14:25–14:33 「有径 · 今日」卡片真机验收**（用户在桌面自行放置，formId `996982405`）：

| 项 | 证据 | 结论 |
|---|---|---|
| 真值渲染 | 桌面截图 + dumpLayout 文本节点：`有径 · 今日` / `Day 1 · 10月23日` / `09:00 故宫博物院` / `13:15 八达岭长城` / `18:30 颐和园` / `还有 1 个需预约节点 · 18:30 前` | 与屏8 北京行程 Day 1 三站一致 |
| 数据来源 | hilog `YouJing.Data.DatabaseHelper: RdbStore 就绪 v4` → `YouJing.Data.TripDao: 今日卡片 trip-1792723833719 Day 1 · 10月23日 还剩 1 站 · 共 3 站` → `YouJing.Widget.TodayTrip: 回灌卡片 996982405 2*2` | 卡片进程直读 RDB，不是缓存的占位数据 |
| 点击通路 | 点卡片 → `com.youjing.app/EntryAbility` FOREGROUND，落屏8 `Day 1 · 10月23日`；Back 回屏2，Home 回桌面 | `postCardAction` router + `tripId` 参数生效 |
| 重装自愈 | `hdc install -r` 后系统重拉 provider：`onAddForm 996982405 2*2` + 回灌，卡片内容不变 | 改版本不丢桌面卡片 |
| 尺寸通路 | 新增 `dimensionOf(want)` 读 `ohos.extra.param.key.form_dimension`，落 preferences `widget_form_dims`，每次回灌带 `dimension` | 2×4 的 16 内缩此前恒走 2×2 默认值（死分支）；2×2 已实测 `2*2`，2×4 桌面形态未实机放置，只有代码通路 |

`extension_running_timeout_monitor` 的 `duration: 14s, limit: 10s` 不是崩溃：provider 在 1s 内完成
`onAddForm` + `updateForm`（14:25:51），监控触发后走 `onStop`、进程 `exit with code:0`，
属系统对 form 扩展的空闲回收；下次刷新由新进程处理，与 `AceSheet radius` 一样归为框架噪声。

2×2 真机格宽 134vp 与底稿 328px 画布的差异导致标题/footer 截断；2026-10-23 用户定为 (a)
接受省略号、完整信息回 App（点卡片直达屏8）。

**2026-10-23 14:46–14:55 Account Kit 真机接通**：此前 `1001502003 Invalid clientId or profile`
的根因不是 Client ID，而是 DevEco 自动签名 Profile 的 `app-identifier` 为随机值
（`6918745435470575450`，≠ AGC APP ID）。在 AGC 新建调试 Profile `youjing-debug-20261023`
（应用「有径」/ 证书 `auto_debug_10086000824313557.cer` / 4 台设备），把下载的 `.p7b`
换入 `build-profile.json5` 后重建安装：`LoginWithHuaweiID error_code=0`，App 日志
「静默登录成功 uid=AABKND***」，屏1 → 屏2；冷重启后「恢复登录态 kind=huawei」。
新旧 Profile 内嵌的 development-certificate 完全相同（本机 `.cer` 指纹 `86:6F:…:CF:70`），
因此 `hdc install -r` 签名一致，无需卸载。下载的 Profile 存于 `~/.ohos/config/`
（用户指定位置），`~/Downloads` 的重复件已删。
