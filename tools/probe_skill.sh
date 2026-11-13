#!/usr/bin/env bash
# 小艺 Skill 真机链路探针（黑盒）。
#
# 为什么要有它：离线断言（tools/verify_skill_logic.sh）钉的是脚本契约，
# 但**脚本 → 预填 → 草稿 → 屏2** 这一段只有真机能验。而这正是最容易静默出错的一段：
# 预填落对了、屏2 却显示别的（2026-11-13 真机实测：过去日期被丢弃、天数被改写）。
#
# 探针做什么：用 Skill 下发的**同一组 Want 参数**（§D 本地自验口径）打真机，
# 抓入口日志 + dumpLayout 实测屏2 的目的地/日期/天数/人数，逐条对表。
#
# 注意：设备 /system/bin 下**没有** ohos-arkTSScript，hdc 无法直接调 Skill 函数
# （这是《Docs/小艺Skill接入清单.md》§D 记录的已知限制）。所以这里验的是
# **下游链路**；「小艺说一句话 → 调 Skill」必须在小艺开放平台真机测试里完成。
#
# 日期全部相对**设备当天**生成：写死日期的话，脚本过了那天就集体过期，
# 期望值会从「应显示该日期」变成「应被拒绝」，两套用例会一起误报。
#
# 用法：bash tools/probe_skill.sh
# 退出码：0 = 全部用例符合预期；1 = 有偏差（打印实际值）；2 = 没有设备。
set -uo pipefail

HDC="${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}"
BUNDLE="com.youjing.app"
OUT="/tmp/youjing_skill_probe.json"
SHOT="/tmp/youjing_skill_toast.jpeg"

if ! $HDC list targets 2>/dev/null | grep -qE '^[0-9a-zA-Z.:_-]+$'; then
  echo "!! 没有可用设备 —— 退出" >&2
  exit 2
fi

fail=0

# 设备当天（真机时区；探针按设备时间算「今天出发」）
TODAY_ISO=$($HDC shell 'date +%Y-%m-%d' 2>/dev/null | tr -d '\r\n ')
if [ -z "$TODAY_ISO" ]; then
  echo "!! 读不到设备日期 —— 退出" >&2
  exit 2
fi

# iso_add <基准日> <天数> → ISO 日期
iso_add() {
  python3 -c "import datetime,sys;print((datetime.date.fromisoformat(sys.argv[1])+datetime.timedelta(days=int(sys.argv[2]))).isoformat())" "$1" "$2"
}

# expect_range <出发日> <天数> → "M月D日 – M月D日|行程长度文案"
# 长度文案与屏2 的 TripSpan.text 同口径：1 天就是「1天」，不写「1天0晚」
expect_range() {
  python3 -c "
import datetime,sys
s=datetime.date.fromisoformat(sys.argv[1]); d=int(sys.argv[2]); e=s+datetime.timedelta(days=d-1)
span='1天' if d<=1 else f'{d}天{d-1}晚'
print(f'{s.month}月{s.day}日 – {e.month}月{e.day}日|{span}')" "$1" "$2"
}

extract() {
  python3 - "$1" <<'PY'
import json,sys,re
try:
    d=json.load(open(sys.argv[1]))
except Exception as e:
    print('DUMP_FAIL:'+str(e)); raise SystemExit
out=[]; st=[d]
while st:
    n=st.pop(0)
    if isinstance(n,dict):
        a=n.get('attributes',{}) or {}
        t=(a.get('text') or '').strip()
        if t: out.append(t)
        st.extend(n.get('children') or [])
    elif isinstance(n,list): st.extend(n)
def after(label):
    for i,x in enumerate(out):
        if x==label and i+1<len(out): return out[i+1]
    return '?'
dates=[x for x in out if re.match(r'^\d+月\d+日',x)]
people=[x for x in out if '成人' in x]
span=[x for x in out if re.match(r'^(\d+天\d+晚|1天)$',x)]
dest=after('目的地')
print('%s|%s|%s|%s' % (dest, dates[0] if dates else '?', span[0] if span else '?', people[0] if people else '?'))
PY
}

# run_case <名称> <期望dest> <期望日期> <期望天数文案> <期望人数> <start> <days> <people> [日志标记]
run_case() {
  local name="$1" exp_dest="$2" exp_dates="$3" exp_span="$4" exp_people="$5"
  local start="$6" days="$7" people="$8" marker="${9:-}"
  $HDC shell "aa force-stop $BUNDLE" >/dev/null 2>&1
  sleep 1
  local cmd="aa start -a EntryAbility -b $BUNDLE --ps route TripInput --ps destination 上海 --ps start $start"
  [ -n "$days" ] && cmd="$cmd --ps days $days"
  [ -n "$people" ] && cmd="$cmd --ps people $people"
  $HDC shell "$cmd" >/dev/null 2>&1
  sleep 4
  $HDC shell 'uitest dumpLayout -p /data/local/tmp/youjing_skill_probe.json' >/dev/null 2>&1
  $HDC shell 'cat /data/local/tmp/youjing_skill_probe.json' > "$OUT" 2>/dev/null
  local got
  got=$(extract "$OUT")
  local gd gdates gspan gpeople
  IFS='|' read -r gd gdates gspan gpeople <<< "$got"
  # 用 python 做定宽对齐：bash printf 的 %-22s 按字节补位，中文会被截坏
  if [ "$gd" = "$exp_dest" ] && [ "$gdates" = "$exp_dates" ] &&
     [ "$gspan" = "$exp_span" ] && [ "$gpeople" = "$exp_people" ]; then
    python3 -c "import sys; print('  PASS  %-26s %s' % (sys.argv[1], sys.argv[2]))" "$name" "$got"
  else
    python3 -c "import sys; print('  FAIL  %-26s 期望 %s|%s|%s|%s 实得 %s' % (sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]))" \
      "$name" "$exp_dest" "$exp_dates" "$exp_span" "$exp_people" "$got"
    fail=$((fail + 1))
  fi
  if [ -n "$marker" ]; then
    if $HDC shell 'hilog -x' 2>/dev/null | grep -q "$marker"; then
      python3 -c "import sys; print('  PASS  %-26s 日志命中「%s」' % (sys.argv[1], sys.argv[2]))" "$name" "$marker"
    else
      python3 -c "import sys; print('  FAIL  %-26s 日志未见「%s」' % (sys.argv[1], sys.argv[2]))" "$name" "$marker"
      fail=$((fail + 1))
    fi
  fi
}

echo "=== 小艺 Skill 真机链路探针 ==="
echo "设备当天：${TODAY_ISO}（日期用例相对它生成）"

echo
echo "[1] Skill 注册（system skillManager）"
$HDC shell "aa start -a EntryAbility -b $BUNDLE" >/dev/null 2>&1
sleep 3
reg=$($HDC shell 'hilog -x' 2>/dev/null | grep -oE 'Skill 注册 [0-9]+ 个: [a-z-]+' | tail -1)
if [ -n "$reg" ]; then
  echo "  PASS  注册日志：$reg"
else
  echo "  FAIL  未见 Skill 注册日志"
  fail=$((fail + 1))
fi

echo
echo "[2] 下游链路：Want → 草稿 → 屏2"
echo "    口径（2026-11-13 修缺陷 A/B 后）：Want 与 Skill 两条路径的 endDate 同口径——"
echo "    days=1 就是 1 天；过去日期照写草稿、屏2 明示纠正为今天起算且**长度不变**。"

D30=$(iso_add "$TODAY_ISO" 30)
D60=$(iso_add "$TODAY_ISO" 60)
PAST=$(iso_add "$TODAY_ISO" -60)

r4=$(expect_range "$D30" 4); IFS='|' read -r e4d e4s <<< "$r4"
rt=$(expect_range "$TODAY_ISO" 4); IFS='|' read -r etd ets <<< "$rt"
r3=$(expect_range "$D60" 3); IFS='|' read -r e3d e3s <<< "$r3"
r1=$(expect_range "$D60" 1); IFS='|' read -r e1d e1s <<< "$r1"
rp=$(expect_range "$TODAY_ISO" 4); IFS='|' read -r epd eps <<< "$rp"

run_case "未来日期 4天3人"       "上海" "$e4d" "$e4s" "3 位成人" "$D30" "4" "3"
run_case "今天出发 4天3人"       "上海" "$etd" "$ets" "3 位成人" "$TODAY_ISO" "4" "3"
run_case "省略天数人数(默认3天)" "上海" "$e3d" "$e3s" "2 位成人" "$D60" "" ""
run_case "days=1 就是 1 天"      "上海" "$e1d" "$e1s" "2 位成人" "$D60" "1" "2"
run_case "天数越界被忽略"         "上海" "$e3d" "$e3s" "2 位成人" "$D60" "31" "2"
run_case "非法日期被忽略"         "上海" "$(expect_range "$TODAY_ISO" 3 | cut -d'|' -f1)" "3天2晚" "2 位成人" "2027-02-30" "3" "2"
run_case "过去日期→今天起算且明示" "上海" "$epd" "$eps" "3 位成人" "$PAST" "4" "3" "已过期"

echo
echo "[3] 过期日期的用户侧明示（截图取证）"
$HDC shell "aa force-stop $BUNDLE" >/dev/null 2>&1
sleep 1
$HDC shell "aa start -a EntryAbility -b $BUNDLE --ps route TripInput --ps destination 上海 --ps start $PAST --ps days 4 --ps people 3" >/dev/null 2>&1
sleep 2
if $HDC shell 'snapshot_display -f /data/local/tmp/youjing_skill_toast.jpeg' >/dev/null 2>&1 &&
   $HDC file recv /data/local/tmp/youjing_skill_toast.jpeg "$SHOT" >/dev/null 2>&1 && [ -s "$SHOT" ]; then
  python3 -c "import sys; print('  PASS  截图已取：%s（屏2 应能看到过期提示 toast）' % sys.argv[1])" "$SHOT"
else
  echo "  WARN  截图未取到（设备不支持 snapshot_display 则忽略此项）"
fi

echo
if [ "$fail" -gt 0 ]; then
  echo "SKILL_PROBE_FAIL 偏差 $fail 条"
  exit 1
fi
echo "SKILL_PROBE_OK"
