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
  材质表那行末尾「segmented control uses 20」是契约明文例外，**保留 20 不跟 50**。
- 新增 `layout.glass-bar-scroll-gated: "true"` 与 §Translucency 的门控口径：玻璃面由**绝对**滚动偏移
  （`scrolled ? 50 : 0`）驱动，禁止按帧增量驱动。
- 新增 `transitions:` 五键（page-enter / page-fade / feed-stagger-step / long-take / snapshot-handover），
  本批次只写进契约、尚无实现消费方。
- **历史记录与实测取证不跟随数值**：`DESIGN.md` 屏 4 状态栏 `blur(24px)` 那条违规实测记录、
  handoff §5「稿件屏 4 违规带了 `blur(24px)`」/ §9「稿件里的 `blur(24px)` 是 CSS 近似」/
  §10 缺陷表同样条目，均保持 v1 原文的 24 —— 帧未重切，实测值仍是 24，改了就成篡改证据。

## 使用口径

- **审计脚本不指向本目录**：`tools/audit_colors.py` 等默认仍读原件路径
  `~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md`（底稿搬家后传参即可）。
  快照落后于原件时不影响任何审计行为；如需比对，`diff Docs/design-v2/DESIGN.md <原件路径>`。
- 验收 grep 口径：`grep -n 'blur 24\|blur(24px)' Docs/design-v2/DESIGN.md` 只允许命中历史记录
  （当前为 1197 行屏 4 实测那条）；规范性表述一律 50，不以「出现次数 ≥ N」为门槛。
- 快照时间：2026-11-02，原件 md5 见下。

  | 原件 | md5 |
  |---|---|
  | `docs/DESIGN.md` | `4ba324d72411f4ee5bce2d51d17c5597` |
  | `docs/youjing-stitch-prompts.md` | `336869d24f45579b1488d23559db878a` |
  | `docs/youjing-engineering-handoff.md` | `4695e6383dd902f894a219d1b4b68c5a` |
