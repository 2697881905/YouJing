# design-v2 · 契约 v2 镜像快照（2026-11-02）

> 本目录是家族契约文档 **契约 v2** 的**镜像快照**（以「有据」为参考实现的对齐口径），防仓库外单点丢失。
> 按 `Docs/design-v1/README.md` 的规矩「底稿升版（v2）后另建 `design-v2/` 快照目录，不覆盖 v1」新建，
> `Docs/design-v1/` 已还原为 2026-10-26 的 v1 原文并冻结不再更新。
> 原件与后续更新仍在：`~/Pictures/有径/有径-设计底稿-v1/docs/`（底稿目录共约 9 MB，
> 含帧截图等资产，不在本快照范围内）。

| 文件 | 角色 |
|---|---|
| `DESIGN.md` | 色板 / 字阶 / 几何 / 材质等设计契约本体（v2），`tools/audit_*.py` 的对表基准 |
| `youjing-engineering-handoff.md` | 工程交接稿：§7 逐帧必改表、§12 路由表、帧清单（文档中「handoff §N」均指此文件） |
| `youjing-stitch-prompts.md` | 39 帧的生成底稿（帧哈希 7fc1cb85、1ab099b1 等的出处） |

## 本版（v2）相对 v1 的差异

- `layout.glass-blur`：`"24"` → `"50"`，正文四处规范性表述（`components.top-bar-immersive.material`、
  §5 材质表 blur 行、§Layout 吸顶日分隔、§Components Floating dock）同步为 50。
- **分段控件按成文例外钉死**：`components.segmented-control.blur` 由引用 `{layout.glass-blur}` 改为显式
  `"20"`，§5 材质表那行不再自称 "the app's only blur radius"，并明写分段控件不是第五块玻璃面、20 只是组件内数值
  （与有据 `GlassTokens.ets:11 SEGMENT_BLUR=20` 同口径）。
- **§Elevation & Depth 的封闭名单按 R11 重写**：书面 blur 半径只属于**三个栏面**（①顶栏 / ②浮动 dock /
  ③吸顶日分隔，一律 50 + 1px `glass-bar-border` + 92px 渐变遮罩）；**④sheet 与菜单是「材质面」而非
  「blur 面」**——有系统材质时由材质接管，自绘兜底就是 `components.sheet-modal` 那套实色
  （`surface-elevated` + `floating` 影 + scrim），不新造 blur 值（与 `components.sheet-modal` 无 blur 键、
  §Components「Sheet (half-modal) … `surface-elevated` … floating elevation, scrim behind」自洽）。
- prompts 屏 11 / 11b 的分段控件行文（第 200、216 行）按 R12 由 `blur(50px)` 改 `blur(20px)`（组件内例外）；
  第 148 行是顶栏，保持 `blur(50px)`。
- handoff §10 缺陷表「屏 8 / 11 / 11b 分段控件模糊离档」行的**实现时应为**列按 R13 改写为
  「v2 作废：20 已升为 `components.segmented-control` 的组件内成文例外；三处栏面统一 50（ArkTS 走材质档位）」
  ——该缺陷在 v2 口径下不再成立；同行「渲染实测 `segmented-control: blur(20px)`，其余三处 24」是实测列，
  与 v1 原文逐字节相同，保持原值。
- 新增 `layout.glass-bar-scroll-gated: "true"` 与 §Translucency 的门控口径：玻璃面由**绝对**滚动偏移
  （`scrolled ? 50 : 0`）驱动，禁止按帧增量驱动。
- 新增 `transitions:` 五键（page-enter / page-fade / feed-stagger-step / long-take / snapshot-handover），
  本批次只写进契约、尚无实现消费方。
- **历史记录与实测取证不跟随数值**：`DESIGN.md` 屏 4 状态栏 `blur(24px)` 那条违规实测记录、
  handoff §5「稿件屏 4 违规带了 `blur(24px)`」/ §9「稿件里的 `blur(24px)` 是 CSS 近似」/
  §10 缺陷表同样条目 + 「渲染实测 blur(20px)，其余三处 24」的实测列，以及 prompts 的 9 行既往
  实测 / 违规 / 缺陷记录（1081、1088、1090、1109、1252、1350、1548、1556、1661）均保持 24 ——
  帧未重切（39 帧 `code.html` 今日实测仍为 `blur(24px)`），改了就成篡改证据；1350 那条是逐字引用帧文件原文。

## 使用口径

- **审计脚本不指向本目录**：`tools/audit_colors.py` 等默认仍读原件路径
  `~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md`（底稿搬家后传参即可）。
  快照落后于原件时不影响任何审计行为；如需比对，`diff Docs/design-v2/DESIGN.md <原件路径>`。
- 验收 grep 口径（固定）：`grep -n 'blur 24\|blur(24px)\|: 24\|统一 24'` 的命中里**只允许历史 / 实测类残留，
  规范性必须 0**。当前三份命中：`DESIGN.md:1197`（屏 4 状态栏实测违规记录）、handoff `237/627/634`
  （既往取证与实测列）、prompts 的 9 行记录，以及 prompts `973/988/999/1073/1288` 五条与模糊半径无关的
  `: 24`（节点 24px、`line-height: 24px`）——按模式属于过宽匹配，非玻璃数值。`统一 24` 命中 0。
  不以「出现次数 ≥ N」为门槛。
- 快照时间：2026-11-02（R11/R12/R13 最后一轮文档修正后），原件 md5 见下。

  | 原件 | md5 |
  |---|---|
  | `docs/DESIGN.md` | `d2f74a2ca99e499d8bc1ac3d40525c02` |
  | `docs/youjing-stitch-prompts.md` | `117c6a27642174e34bdb6be0d252bf0b` |
  | `docs/youjing-engineering-handoff.md` | `be248e2b5c2fdaad2f0fd38eb148fa94` |
