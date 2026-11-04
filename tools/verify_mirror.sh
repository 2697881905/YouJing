#!/bin/sh
# 契约镜像一致性闸（离线断言类，不占「十四把静态尺」计数）
#
# 为什么需要它（批次一全批评审 Important-2）：
#   1. 五把读契约的尺（colors / type / geometry / material / fontfamily / elevation 里读 DESIGN 的那些）
#      默认路径**全指仓库外原件** `~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md`，
#      而 `Docs/design-v2/README.md:67-69` 明写「审计脚本不指向本目录……快照落后于原件时
#      不影响任何审计行为」——**镜像失同步今天是合法状态**，没有任何一把尺看着它。
#   2. 新规矩（T8 改写）把「产品负责人可改契约」常态化，批次二 T2 起会反复发生
#      「改原件、仓库镜像与出稿提示词掉队」。
#   3. 掉队不是文档洁癖：`youjing-stitch-prompts.md` 引 DESIGN 72 处、是**出稿产线**，
#      它落后就批量产出 v1 视觉（spec §7 决议 3 同步改的那条理由）；
#      `youjing-engineering-handoff.md` 抄了 §5 逐帧表的具体值，落后就按旧值接线。
#   4. `~/Pictures` 不在 git 下，改错没有回滚，只能靠**冻结哈希**证明 v1 那一版没被动过。
#
# 干两件事，任一失配退非 0：
#   ① 原件三份（DESIGN.md / youjing-stitch-prompts.md / youjing-engineering-handoff.md）
#      与 Docs/design-v2/ 逐字节 `cmp`；
#   ② Docs/design-v1/ 四份对**钉死的冻结哈希**只读校验（基线取 c7671d9 那一版，
#      现算方式：`git show c7671d9:Docs/design-v1/<文件> | md5 -q`）。
#
# 冻结哈希的现算记录（2026-11-02 本轮，逐条真跑，非抄写）：
#   git show c7671d9:Docs/design-v1/DESIGN.md                    | md5 -q → 7c715d638b48268266b8267c1daaa1a2
#   git show c7671d9:Docs/design-v1/README.md                    | md5 -q → 9711ace3d2aa34fe889f72967bb0d166
#   git show c7671d9:Docs/design-v1/youjing-engineering-handoff.md | md5 -q → d56df31aca4bc37f6bbba34c3fc8a6c4
#   git show c7671d9:Docs/design-v1/youjing-stitch-prompts.md     | md5 -q → 3970d4943c1d38e61a712c109183b157
#   同四条在工作树里现算 md5 -q Docs/design-v1/<文件> 与上面逐字符相同（v1 冻结，本闸就是钉住这条）。
#
# 零依赖：POSIX sh + cmp + md5 -q（macOS 自带），不引入任何三方工具、不联网、不改文件。
# 用法：bash tools/verify_mirror.sh
# 退出码 0 = 两份都过；1 = 内容失配（镜像落后 / v1 被改）；2 = 前置缺失或用法错
#        （原件目录不在、文件缺失、无 md5、未知参数）——**前置缺失绝不退 0**，
#        否则「闸没跑」会被读成「闸过了」，正是本轮要消灭的形态。

set -u

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "verify_mirror：不在 git 仓库里，无法定位 Docs/" >&2
  exit 2
}
cd "$ROOT" || exit 2

SRC_DIR="$HOME/Pictures/有径/有径-设计底稿-v1/docs"
V2_DIR="Docs/design-v2"
V1_DIR="Docs/design-v1"

if [ "$#" -gt 0 ]; then
  echo "用法：bash tools/verify_mirror.sh（无参数；不接受任何开关）" >&2
  exit 2
fi

MD5="$(command -v md5 2>/dev/null || true)"
if [ -z "$MD5" ]; then
  echo "verify_mirror：本机没有 md5 命令，无法校验冻结哈希（不许退 0 蒙过）" >&2
  exit 2
fi

fail=0

echo "① 原件 docs ↔ Docs/design-v2 逐字节比对（${SRC_DIR}）"
if [ ! -d "$SRC_DIR" ]; then
  echo "  !! 前置缺失：契约原件目录不存在 $SRC_DIR —— 镜像无从比对，判为不通过" >&2
  fail=1
fi
for f in DESIGN.md youjing-stitch-prompts.md youjing-engineering-handoff.md; do
  if [ ! -d "$SRC_DIR" ]; then
    break
  fi
  if [ ! -f "$SRC_DIR/$f" ] || [ ! -f "$V2_DIR/$f" ]; then
    echo "  !! ${f}：一侧文件缺失（原件 $SRC_DIR/$f ｜镜像 $V2_DIR/${f}）" >&2
    fail=1
    continue
  fi
  if cmp -s "$SRC_DIR/$f" "$V2_DIR/$f"; then
    n=$(wc -c < "$V2_DIR/$f" | tr -d ' ')
    echo "  OK ${f}：逐字节相同（$n 字节）"
  else
    diff_line=$(cmp "${SRC_DIR}/$f" "${V2_DIR}/$f" 2>&1 | head -1)
    echo "  ✗ ${f}：镜像与原件不一致（${diff_line:-cmp 未给出分叉位置}）" >&2
    echo "     修法：cp \"$SRC_DIR/$f\" \"$V2_DIR/$f\" 后复跑本闸；" >&2
    echo "     若这次改动是契约修订，按 T8 规矩同一批同步 token 与尺。" >&2
    fail=1
  fi
done

echo ""
echo "② Docs/design-v1 冻结哈希只读校验（基线 c7671d9）"
check_frozen() {
  name=$1
  want=$2
  path="$V1_DIR/$name"
  if [ ! -f "$path" ]; then
    echo "  !! ${name}：文件缺失 $path" >&2
    fail=1
    return
  fi
  got=$(md5 -q "$path")
  if [ "$got" = "$want" ]; then
    echo "  OK ${name}：md5 $got 与冻结值一致"
  else
    echo "  ✗ ${name}：md5 $got ≠ 冻结值 $want" >&2
    echo "     v1 是已发布历史快照（design-v1/README 明写不许覆盖、只作差异对照），" >&2
    echo "     要动它先按规矩升版建新目录，不要在 v1 上就地改。" >&2
    fail=1
  fi
}
check_frozen DESIGN.md 7c715d638b48268266b8267c1daaa1a2
check_frozen README.md 9711ace3d2aa34fe889f72967bb0d166
check_frozen youjing-engineering-handoff.md d56df31aca4bc37f6bbba34c3fc8a6c4
check_frozen youjing-stitch-prompts.md 3970d4943c1d38e61a712c109183b157

echo ""
if [ "$fail" -eq 0 ]; then
  echo "verify_mirror PASS：三镜像逐字节同步 + 四份 v1 冻结哈希未动"
  exit 0
fi
echo "verify_mirror FAIL：镜像同步或 v1 冻结至少有一处不成立（详见上面 ✗/!! 行）"
exit 1
