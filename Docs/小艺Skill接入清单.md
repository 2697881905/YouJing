# 小艺 Skill 接入清单（有径）

> 分工：**平台侧你在控制台做（§A）**，**应用侧我做（§B）**。参数契约在 §C，两边都按它对齐。
> 现状：应用侧接收通道已实现并真机验证（commit `28fced4`），平台侧还没有 Skill，所以语音还唤不起。

## A. 你在小艺开放平台要做的事

开发文档 §3 已定方案：**小艺开放平台 LLM 模式**（平台承担算力成本，纯 ArkTS 集成）。控制台路径：

1. 登录 [小艺开放平台](https://developer.huawei.com/consumer/cn/harmonyos/51-IntentsKit/) → **Skill** → **新建 Skill**
   - 名称：`有径行程规划`
   - 描述：面向「帮我规划一次旅行」这类说法，说明能给出行程
   - 触发意图：填用户会说的话，例：`帮我规划去北京的行程`、`安排一次三天两晚的旅游`
2. 选择 **Agent** → **添加 LLM 模式 Agent**
3. 在 Agent 的**出参 / 拉起应用**配置里，按 §C 的键名把槽位传给我们（这一步最关键，键名错了应用收到空值）
4. 关联到本应用：bundleName `com.youjing.app`（AGC 侧应用需已注册，与调试签名同一账号体系）
5. 提交审核（开发文档 §8 风险表：**Skill 上架有延迟**，所以 App 内闭环已先做完，Skill 只当增量入口）

你需要准备/确认的信息：AGC 应用是否已注册、签名指纹是否已登记、这个 Skill 用哪个 AGC 项目。这三项和 §D 的 Account Kit 是同一套配置，一次问清比较省事。

## B. 应用侧我已完成 / 待做

已完成（真机验证）：

- `EntryAbility.applyWant()`：解析外部拉起的 `want.parameters`
  - `route` → 落到哪一屏（`TripInput` / `Trips` / `Itinerary` …，路由表见 `Docs/ARCHITECTURE.md`）
  - `destination` / `start` / `end` / `days` / `people` → 预填屏2 基础参数（非法日期直接忽略，不会覆盖已有草稿）
  - `param` → 路由参数（如屏8 需要的 tripId）
- `onNewWant()`：App 已在前台时同样生效（单例复用页面栈，不重建窗口）
- 屏2 `aboutToAppear` 回显草稿真值 —— 预填不是只写进内存，用户看得见

待我做（拿到平台侧结论后）：

- 意图声明落进 HAP：`@kit.IntentsKit` 在本机 SDK 里确认可用（`insightIntent` + `InsightIntentUIExtensionAbility`），
  但**意图注册的具体声明文件与 JSON 格式我还没核实**，明天我按 SDK 声明文件和官方样例确认后补，不凭记忆写。
- 若平台侧只能拉起 Ability 不能带自定义参数，退路是：Skill 只传 `route`，参数由屏2 让用户确认（不硬编数字）。

## C. 参数契约（贴进 Skill 出参配置的就是这张表）

| 键 | 类型 | 含义 | 例 |
|---|---|---|---|
| `route` | string | 落点屏名，缺省则不跳转只预填 | `TripInput` |
| `destination` | string | 目的地城市，屏2 城市表内的值才生效 | `上海` |
| `start` | string | 出发日 ISO `YYYY-MM-DD` | `2026-08-01` |
| `end` | string | 返程日 ISO，与 `days` 二选一，`days` 优先 | `2026-08-04` |
| `days` | number | 天数（含首尾），会反算 `end` | `4` |
| `people` | number | 同行人数 | `3` |
| `param` | string | 路由参数；`route=Itinerary` 时传 tripId | `trip-1792689610437` |

## D. 顺手一起问的：Account Kit（阶段 8 的遗留开关）

屏1「华为账号一键登录」现在走本机游客分区，因为 `AccountConfig.ACCOUNT_KIT_ENABLED=false`。
你在 AGC 配好 Client ID + 登记签名证书指纹后告诉我，我把它翻成 `true` 就接上真 UnionID，
游客期行程会自动归户到该账号（`TripDao.adoptGuestTrips`，已实现并留了日志）。

## E. 不等平台就能验的（我明天继续跑，你也可以自己试）

```bash
# 冷启动预填
hdc shell aa start -a EntryAbility -b com.youjing.app \
  --ps route TripInput --ps destination 上海 --ps start 2026-08-01 --ps days 4 --ps people 3

# App 已在前台时改参（走 onNewWant）
hdc shell aa start -a EntryAbility -b com.youjing.app \
  --ps route TripInput --ps destination 北京 --ps start 2026-09-10 --ps days 6 --ps people 1

# 直达某屏 / 带路由参数
hdc shell aa start -a EntryAbility -b com.youjing.app --ps route Trips
```

真机实测结论：第一条屏2 显示「上海 / 8月1日–8月4日 / 4天3晚 / 3 位成人」；第二条同一进程内改成
「北京 / 9月10日–9月15日 / 6天5晚 / 1 位成人」，日志见 `YouJing.EntryAbility: 外部预填 route=…`。
