#!/usr/bin/env bash
# 构建并装机，且**只有本轮构建成功才允许装机**。
#
# 为什么要脚本化：2026-11-05 真机走查时，一次 `assembleHap` 是 FAIL 的，
# 但紧随其后的 `hdc install -r` 照样回 `AppMod finish`——它装的是上一轮留在
# entry/build 里的产物。之后那次"真机复拍"读到的还是旧文案，看起来像验证通过。
# `install` 的成功字样不证明产物含改动（见记忆 hvigor-up-to-date-stale-artifact），
# 所以把"构建成功 → 才装机"这条判据固化成脚本，而不是靠人记得看那行字。
#
# 用法：
#   tools/build_install.sh                 # default 模块（App 本体，debug）
#   tools/build_install.sh ohosTest        # ohosTest 模块（hypium 包）
set -euo pipefail

SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
HVIGOR="/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js"
HDC="$SDK_HOME/default/openharmony/toolchains/hdc"
MODULE="${1:-default}"
cd "$(dirname "$0")/.."

LOG="$(mktemp)"
INSTALL_LOG="$(mktemp)"
trap 'rm -f "$LOG" "$INSTALL_LOG"' EXIT

echo "==> 构建 entry@${MODULE}（debug）"
DEVECO_SDK_HOME="$SDK_HOME" node "$HVIGOR" \
  --mode module -p "module=entry@${MODULE}" -p product=default -p buildMode=debug \
  assembleHap --no-daemon >"$LOG" 2>&1 || true

if ! grep -q "BUILD SUCCESSFUL" "$LOG"; then
  echo "!! 本轮构建未成功，**不装机**。产物保持上一轮，装上去会读到旧代码。"
  grep -E "ERROR" "$LOG" | head -20
  exit 1
fi
grep -E "BUILD SUCCESSFUL" "$LOG" | tail -1

HAP="entry/build/default/outputs/${MODULE}/entry-${MODULE}-signed.hap"
if [[ ! -f "$HAP" ]]; then
  echo "!! 找不到签名产物 $HAP"
  exit 1
fi
# 产物必须比本轮构建开始时刻新：UP-TO-DATE 复用旧产物时时间戳不更新，
# 这条把"构建成功"和"产物真的含改动"分开判。
if [[ "$(stat -f %m "$HAP")" -lt "$(date -v-5M +%s 2>/dev/null || echo 0)" ]]; then
  echo "!! 产物修改时间超过 5 分钟，疑似复用了旧包；请确认改动是否真的进了编译"
  exit 1
fi

echo "==> 装机 $HAP"
# 多设备时（真机 + 模拟器同时在）不带 -t 的 install 会回 "[Fail]...need connect-key"，
# 而管道尾部照样是 hdc 的正常收尾字样——只看退出码或最后一行会把失败读成成功。
INSTALL_LOG="$(mktemp)"
if [[ -n "${HDC_TARGET:-}" ]]; then
  "$HDC" -t "$HDC_TARGET" install -r "$HAP" >"$INSTALL_LOG" 2>&1
else
  "$HDC" install -r "$HAP" >"$INSTALL_LOG" 2>&1
fi
if grep -q "install bundle successfully" "$INSTALL_LOG" && ! grep -q "\[Fail\]" "$INSTALL_LOG"; then
  tail -1 "$INSTALL_LOG"
  if [[ -n "${HDC_TARGET:-}" ]]; then
    echo "==> 完成：本轮构建成功且产物已装机（目标 $HDC_TARGET）"
  else
    echo "==> 完成：本轮构建成功且产物已装机"
  fi
else
  echo "!! 装机未成功，屏幕跑的还是上一轮产物。hdc 原文："
  cat "$INSTALL_LOG"
  exit 1
fi
