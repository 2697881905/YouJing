#!/usr/bin/env bash
# #21 dock→HdsTabs 六项真机验收：一条命令跑完，证据落盘。
# 用法：bash tools/verify_dock_tabs.sh [输出目录]
# 只读设备状态 + 启动自己的 App；不点删除类控件。
set -uo pipefail

HDC=${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}
# 设备地址不写死：IP 每次重连都会变（实测 192.168.3.2 → 192.168.31.38），
# 写死的地址只会让脚本静默跑在错误目标上。取 `hdc list targets` 第一条，
# 需要指定时用 DEV=... 覆盖。
if [ -z "${DEV:-}" ]; then
  DEV="$("$HDC" list targets 2>/dev/null | sed -n '1p')"
fi
if [ -z "$DEV" ] || [ "$DEV" = "[Empty]" ]; then
  echo "没有可用设备：hdc list targets 为空。接上真机或用 DEV=<ip:port> 指定。" >&2
  exit 2
fi
BUNDLE=com.youjing.app
OUT=${1:-/tmp/docktabs-$(date +%Y%m%d-%H%M%S)}
DENSITY=3.125   # 实测：真机像素 ÷ vp 一律按 3.125

mkdir -p "$OUT"
say() { printf '\n== %s ==\n' "$*"; }

# 设备被真人占用时立刻停手：屏幕不是本 App 就退出，不试图抢。
# 口径用 dumpLayout 文字（已验证可读），不用 hidumper/aa dump：
# 前者这一版只给窗口名与 pid、没有包名，后者把所有存活 mission 都列出来，都判不出前台。
assert_front() {  # assert_front <已落盘的 json>：不像有径的前台就整跑中止
  local hits
  hits=$(python3 - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
def attrs(n):
    a = n.get('attributes')
    return a if isinstance(a, dict) else n
seen = set()
def walk(n):
    seen.add((attrs(n).get('text') or '').strip())
    for c in n.get('children', []):
        walk(c)
walk(d)
# 三个一起才算有径的前台：有据的 dock 也有「我的」
print(len({x for x in ('行程', '地图', '费用') if x in seen}))
PY
)
  if [ "${hits:-0}" -lt 3 ]; then
    echo "  !! 前台不像 $BUNDLE（dock 标签命中 $hits/3），整跑中止——不跟真人抢手机" >&2
    exit 3
  fi
}

guard_foreground() {
  local tag=$1
  $HDC shell "uitest dumpLayout -p /data/local/tmp/$tag.json" >/dev/null 2>&1
  $HDC file recv "/data/local/tmp/$tag.json" "$OUT/$tag.json" >/dev/null 2>&1
  assert_front "$OUT/$tag.json"
}

dump() {  # dump <名字> → 打印文本节点，落 json
  local tag=$1
  $HDC shell "uitest dumpLayout -p /data/local/tmp/$tag.json" >/dev/null 2>&1
  $HDC file recv "/data/local/tmp/$tag.json" "$OUT/$tag.json" >/dev/null 2>&1
  python3 - "$OUT/$tag.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = []
def attrs(n):
    # dumpLayout 把 text/bounds 装在 attributes 里，不是节点顶层（真机实测）
    a = n.get('attributes')
    return a if isinstance(a, dict) else n
def walk(n):
    t = (attrs(n).get('text') or '').strip()
    if t:
        out.append(t)
    for c in n.get('children', []):
        walk(c)
walk(d)
print(' | '.join(out[:24]))
PY
}

# 按可见文字找中心点（bounds 是设备像素，uitest 也吃像素）
tap_text() {  # tap_text <文字> <dump 前缀>
  local want=$1 tag=$2 coords
  $HDC shell "uitest dumpLayout -p /data/local/tmp/$tag.json" >/dev/null 2>&1
  $HDC file recv "/data/local/tmp/$tag.json" "$OUT/$tag.json" >/dev/null 2>&1
  coords=$(python3 - "$OUT/$tag.json" "$want" <<'PY'
import json, re, sys
d, want = json.load(open(sys.argv[1])), sys.argv[2]
exact, loose = [], []
def attrs(n):
    a = n.get('attributes')
    return a if isinstance(a, dict) else n
def center(a):
    nums = [int(x) for x in re.findall(r'-?\d+', a.get('bounds') or '')]
    return ((nums[0] + nums[2]) // 2, (nums[1] + nums[3]) // 2) if len(nums) == 4 else None
def walk(n):
    a = attrs(n)
    t = (a.get('text') or '').strip()
    if t == want:
        p = center(a)
        if p:
            exact.append(p)
    elif want in t:
        p = center(a)
        if p:
            loose.append(p)
    for child in n.get('children', []):
        walk(child)
walk(d)
# 先取全等：页面上「费用」既是 dock 页签也是「记一笔费用」按钮，子串匹配会点错
print('%d %d' % exact[0] if exact else ('%d %d' % loose[0] if loose else ''))
PY
)
  assert_front "$OUT/$tag.json"
  if [ -z "$coords" ]; then
    echo "  !! 找不到文字「$want」——记为未验，别猜坐标" >&2
    return 1
  fi
  echo "  tap 「$want」 @ $coords (vp $(echo "$coords" | awk -v d=$DENSITY '{printf "%.0f %.0f", $1/d, $2/d}'))"
  $HDC shell "uitest uiInput click $coords" >/dev/null 2>&1
}

shot() {  # shot <名字>
  $HDC shell "snapshot_display -f /data/local/tmp/$1.jpeg" >/dev/null 2>&1
  $HDC file recv "/data/local/tmp/$1.jpeg" "$OUT/$1.jpeg" >/dev/null 2>&1
}

start_route() {  # start_route <route> [param]
  $HDC shell "aa force-stop $BUNDLE" >/dev/null 2>&1
  sleep 1.2
  if [ -n "${2:-}" ]; then
    $HDC shell "aa start -a EntryAbility -b $BUNDLE --ps route $1 --ps param $2" >/dev/null 2>&1
  else
    $HDC shell "aa start -a EntryAbility -b $BUNDLE --ps route $1" >/dev/null 2>&1
  fi
  sleep 2.5
}

say "0 前置：设备与产物"
$HDC list targets | grep -q "$DEV" || { echo "设备不在线：先 $HDC tconn $DEV" >&2; exit 2; }
$HDC shell "bm dump -n $BUNDLE" 2>/dev/null | grep -m1 "versionName" | tee "$OUT/version.txt"
echo "  源码 HEAD：$(git rev-parse --short HEAD) 分支 $(git rev-parse --abbrev-ref HEAD)"
echo "  注意：验收前必须装与当前分支一致的产物（hvigor 产物 md5 见下）"
md5 -q entry/build/default/outputs/default/entry-default-signed.hap | tee "$OUT/hap.md5"
read -r -p "  确认手机空闲、产物已装机？回车继续（Ctrl-C 中止）" _

say "1 五页签点切（地图 → 行程 → 规划 → 费用 → 我的，每步 dump）"
$HDC shell "aa start -a EntryAbility -b $BUNDLE" >/dev/null 2>&1
sleep 2.5
dump 1-home
for t in 行程 规划 费用 我的 地图; do
  tap_text "$t" "1-tap-$t" && sleep 1.6 && dump "1-after-$t" && shot "1-after-$t"
done
# 五格重排后最容易静默坏掉的是「切回来数据没刷新」：序号错位不崩、只是不重取。
# 所以每格都要 dump 正文并人工核对是当前数据，不能只看有没有切过去。
echo "  ↑ 逐格核对 dump 正文是当前数据而不是第一次进入那份（isTabShownTick 错位的唯一肉眼判据）"

say "1b 新「我的」格要有身份区与勋章卡（不能还是行程列表）"
tap_text 我的 "1b-goto" && sleep 1.6 && dump 1b-mine && shot 1b-mine
grep -q "勋章" "$OUT/1b-mine.json" || echo "  !! 1b 「我的」格里没有勋章卡" >&2
grep -qE "游客空间|\*\*\*" "$OUT/1b-mine.json" \
  || echo "  !! 1b 「我的」格缺少身份区（脱敏 ID 或游客态）" >&2

say "2 费用 tab 根页内容（要有金额，不是占位）"
tap_text 费用 "2-goto" && sleep 1.6 && dump 2-expense && shot 2-expense

say "3 冷启深链 route=Itinerary"
# 不带 param：硬编码的 trip id 会随用户删除而失效，届时这一条测的是「深链到一条不存在的行程」，
# 照样 grep 得到 Day 1 就成了假绿。不带 param 走的是 ItineraryPage 退最近一条那条真路。
start_route Itinerary
dump 3-itinerary && shot 3-itinerary
grep -q "Day 1" "$OUT/3-itinerary.json" || echo "  !! 3 未落到行程页" >&2
if grep -q "这一天还没有安排节点" "$OUT/3-itinerary.json"; then
  echo "  !! 3 落到了一条没有节点的行程（深链上下文没退到真行程）" >&2
fi

say "4 冷启深链 route=TripInput"
start_route TripInput
dump 4-tripinput && shot 4-tripinput
grep -qE "目的地|出发|人数" "$OUT/4-tripinput.json" || echo "  !! 4 未落到屏2" >&2

say "4b 冷启深链 route=Badges（要 push 进「我的」那条懒建的栈——重排后最容易丢的一条）"
start_route Badges
dump 4b-badges && shot 4b-badges
grep -q "勋章" "$OUT/4b-badges.json" \
  || echo "  !! 4b 深链没落到勋章墙（push 落进了还没绑 Navigation 的栈）" >&2

say "5 二次深链同一个 tab（8c5d0a5 修的那条：第一次建 tab 之后的深链）"
# 不带 param：EntryAbility 只在 param 非空时写 ACTIVE_TRIP_KEY，硬编码的旧 trip id
# 会让费用页拿一条本机不存在的行程去 loadTrip——测的是病态数据不是深链本身。
# 不带 param 时 ItineraryPage 退到最近一条并把它回写成上下文，才是真用户走的那条路。
start_route Itinerary
tap_text 费用 "5-goto" && sleep 1.6
start_route Expense
dump 5-expense-again && shot 5-expense-again
grep -qE "预算|¥" "$OUT/5-expense-again.json" || echo "  !! 5 二次深链没落到费用页" >&2
if grep -q "0 人 · 0 天" "$OUT/5-expense-again.json"; then
  echo "  !! 5 费用格落在死数据（0 人 · 0 天）：上下文行程不存在且没退回最近一条" >&2
fi

say "6 弹栈边界：tab 根页的返回钮/返回手势会弹到空占位（§4j 结构性缺口）"
tap_text 我的 "6-goto" && sleep 1.6
$HDC shell "uitest uiInput keyEvent Back" >/dev/null 2>&1
sleep 1.2
dump 6-after-back && shot 6-after-back
echo "  ↑ 若 6 只剩 dock、正文空，就是 §4j 记的那条：根页不该走栈"

say "7 hypium 81 例"
$HDC shell "aa test -b $BUNDLE -m entry_test -s unittest OpenHarmonyTestRunner" 2>&1 | tee "$OUT/aa-test.txt" | tail -12

say "完成"
echo "证据目录：$OUT"
echo "把 §4j 六项逐条对完再决定合入/回退；任何一项未验，分支不算可合入。"
