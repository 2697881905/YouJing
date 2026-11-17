## 1. 采用的体系与工具

- **平台**：HarmonyOS ArkTS（ArkUI），无 CSS/Tailwind，样式全部以 ArkTS 组件属性 + `resources/base` / `resources/dark` 资源表承载。
- **设计系统位置**：`entry/src/main/ets/design/` 集中暴露色彩、字号、圆角、图标、布局等 token；运行时值来自 ArkUI 的 `$r('app.color.xxx')` 引用。
- **深色模式**：通过两套 `color.json`（`base/element/color.json` 浅色、`dark/element/color.json` 深色）实现，由系统 `ColorMode` 自动切换，页面零分支。`ColorTokens.ets` 仅导出 `$r` 引用，不硬编码色值。
- **契约来源**：`Docs/design-v1/DESIGN.md`（手稿 v1）与 `Docs/superpowers/specs/2026-11-07-表现层全量对齐-差异表.md` 作为权威依据；代码注释多处引用 DESIGN.md 行号。
- **审计工具**：`tools/audit_*.py`（Python）在开发期扫描 `pages/`、`components/`、`widget/**`，强制字体大小、颜色、材质等约定不走 token 即报错。

## 2. 关键文件

| 路径 | 职责 |
|---|---|
| `entry/src/main/ets/design/ColorTokens.ets` | 色彩 token 类型声明 + `$r` 映射，含「有据同名别名」兼容层 |
| `entry/src/main/ets/design/LayoutTokens.ets` | 间距、内缩、dock/导航栏高、滚动预留等具名尺寸 |
| `entry/src/main/ets/design/TypeTokens.ets` | 九档字阶 + 字族（NotoSerifSC / HarmonyOS Sans）+ tabular 特性 |
| `entry/src/main/ets/design/RadiusTokens.ets` | 八值圆角封闭集（0/6/10/14/20/28/30/999） |
| `entry/src/main/ets/design/IconTokens.ets` | 图标尺寸（compact=16, standard=24），与旧 `IconSizes` 并存 |
| `entry/src/main/ets/design/HdsChrome.ets` | HDS 沉浸光感材质 chrome 封装 |
| `entry/src/main/resources/base/element/color.json` | 浅色色板（48+ 项，`#AARRGGBB`） |
| `entry/src/main/resources/dark/element/color.json` | 深色色板（同名键值对） |
| `entry/src/main/ets/utils/responsive.ets` | 断点 → List.lanes 映射（sm/md/lg = 1/2/3 列）+ 单栏最大宽 |`breakpointCenter.ets`（同 utils）提供唯一断点源 |
| `tools/audit_type.py` | 扫描 Text/SymbolGlyph 字号是否走 token |
| `tools/audit_colors.py` | 校验两份 color.json ↔ DESIGN.md 契约 |
| `tools/audit_radius.py`（存在但本摘要未展开） | 校验圆角值是否在 ALLOWED_RADII 内 |

## 3. 架构与约定

### 色彩
- 所有语义色集中在 `ColorTokens` 接口中按域分组：画布/表面、文字/图标、品牌与语义、线与遮罩、玻璃栏面族、路线图、星图、历史别名。
- 新增 token 必须在 `resources/{base,dark}/element/color.json` 成对登记，并在 `ColorTokens` 中添加字段；注释中常附契约来源与设计验收比（如 `brandSolid` 白字 7.91:1、`chipSolid` 白字 9.1:1）。
- 为兼容从「有据」搬运的组件，保留同名别名（`secondary/body`、`tertiary/muted`、`sunken/surfaceSunken`、`brand/primary`、`barSurface/glassBarSurface` 等），改色需两仓同步。
- 玻璃材质相关色（`glassBarSurface` / `glassBarBorder` / `glassBarBg` / `glassCardBg` / `glassSegmentBg` / `glassSegmentBorder` / `glassPillFill` / `glassPillRim`）是 2026-11-07 全量对齐新增的兜底族。

### 字号与字体
- 封闭九档：display(32)/title(21)/headline(18)/body(16)/small(14)/caption(12)/overline(11)/navLabel(10)/time(12)，外加 `callout`/`titleSans` 两个语义别名。
- 字族：正文用 `HarmonyOS Sans`，标题/金额 hero 用 `NotoSerifSC`（已打包 `rawfile/fonts` 并在 `EntryAbility` 注册）。数字统一开启 tabular (`'tnum' on`)。
- `ALLOWED_FONT_SIZES = [10,11,12,14,16,18,21,32]` 被 `audit_type.py` 用于拒绝非契约字号。

### 圆角
- 封闭八值：`none/media/capsule/reason/card/hero/dock/pill/floatingBar/lg`，`ALLOWED_RADII` 由 audit 脚本校验。

### 布局与间距
- 所有尺寸以 vp 为单位，通过 `LayoutTokens` 具名导出（`pagePadding=16`、`itemGap=12`、`blockGap=16`、`sectionGap=24`、`contentMaxWidth=720`、`minTouchTarget=44`、`floatingDockClearance=112` 等）。
- 浮动 dock 尺寸链（300/420/560 宽、56 高、28 下边距、92 渐变遮罩、112 钉底净空）全部集中在此，避免散落魔法数。

### 响应式策略
- 断点监听只注册在 `breakpointCenter.ets` 一处；`utils/responsive.ets` 只做纯映射：`listLanesForBreakpoint` 返回 sm→1、md→2、lg→3 列。
- 长文单栏使用 `longFormMaxWidth(bp, capVp)`：sm 档 `'100%'`，md 档固定到 `BP_MD_MIN_VP`（600vp），lg 档取传入上限（默认 `LayoutTokens.contentMaxWidth=720`）。
- 对称居中用 `symmetricInsetForCap(windowWidthVp, capVp, baseVp)`，避免 `constraintSize.maxWidth` 导致的子级测量溢出问题。

### 组件库与自绘
- 未引入第三方 UI 组件库（无 oh-package 中的 UI kit 依赖）。业务组件位于 `entry/src/main/ets/components/`（`DesignButton`、`YoujingButton`、`GlassPanel`、`CompanionOrb`、`CompanionOverlay`、`SoftChip`、`TimelineNode` 等）均为自绘 ArkUI 组件。
- 官方 HDS 材质仅在 Chrome 容器中使用（`HdsChrome.ets`），其余玻璃效果通过自绘组件覆盖，遵循「材质生效时自绘 border/shadow/blur 归零」的避让规则。

## 4. 约定与约束（观察到的行为 + 可验证的规则）

- **颜色必须经资源表**：`ColorTokens.ets` 中每个 token 都通过 `$r('app.color.xxx')` 取值，禁止在组件中硬写十六进制色值。
- **深色自动切换**：两套 `color.json` 同名键对应浅/深主题，页面零分支——这是 `ColorTokens.ets` 顶部注释明确的设计机制 A。
- **字号仅限八档**：`tools/audit_type.py` 将 `ALLOWED_TEXT_SIZES` 硬编码为 `{10,11,12,14,16,18,21,32}`，对 `pages/`、`components/`、`widget/**` 下的 `.fontSize(n)` 做正则扫描，不在集合内即报告「字号不在契约八档里」。
- **Text 字号应走 TypeTokens.size**：即使字号合法，audit 也提示「应写 TypeTokens.<档>.size」，鼓励消费方引用 token 而非字面量。
- **图标尺寸走 IconTokens/IconSizes**：`SymbolGlyph` 上的字号同样受 `ICON_TOKEN_SIZES` 约束。
- **`.lineHeight(0)` 禁止**：`TypeTokens.overline` 与 `time` 的 lineHeight 为 0 表示「不设行高」，audit 脚本把显式 `.lineHeight(0)` 视为违规，防止把「没设」误译成「行高 0」。
- **圆角仅限八值**：`RadiusTokens.ALLOWED_RADII = [0,6,10,14,20,28,30,999]` 由 audit 脚本校验。
- **色表契约逐像素核对**：`tools/audit_colors.py` 读取 `entry/src/main/resources/base/element/color.json` 与 `dark/element/color.json`，对照 DESIGN.md 中的 rgba/十六进制台账，逐件比对并输出偏差。
- **响应式断点唯一源**：`responsive.ets` 注释要求「窗口尺寸监听只在 breakpointCenter.ets 注册一处，不允许各自挂 windowSizeChange」。
- **List.lanes 不是 Grid**：`responsive.ets` 明确说明项目卡片全是单列 List，`listLanesForBreakpoint` 返回的是 List 的列数，不是 Grid 的列数。
- **长文宽度必须挂 `.width()`**：`longFormMaxWidth` 注释指出不能挂 `constraintSize({maxWidth})`，否则折叠屏上子级仍按原约束测量导致溢出。
- **底部滚动预留必须叠加 dockNavInset**：`LayoutTokens.bottomScrollReserve=94` 只是手势档基础值，三键档需额外加 dock 位移，消费方必须写成 `bottomScrollReserve + dockNavInset`。
- **历史别名不得删改**：`ColorTokens` 中 `secondary`/`tertiary`/`sunken`/`brand` 等别名是为兼容搬运组件而保留，注释明确要求「改色需两仓同步」。