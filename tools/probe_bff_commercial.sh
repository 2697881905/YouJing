#!/usr/bin/env bash
# 商业化链路验收探针的启动器：把 bff/ 拷成隔离副本再跑，仓库与 bff/data 零写入。
#
# 为什么拷出去跑：src/db.js 的 DB_PATH 是硬编码的 ../data/youjing.db，没有环境变量入口，
# 直接在仓库里起服务会往另一会话正在用的开发库写测试账号。
#
# 用法：bash tools/probe_bff_commercial.sh
# 退出码：0 = 行为全绿且无支付守卫缺陷；1 = 有缺陷或有回归。
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/bff"
WORK="$(mktemp -d)"
PROBE="$WORK/bff"
PORT="${PROBE_PORT:-47811}"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

if [ ! -d "$SRC/src" ]; then
  echo "找不到 $SRC/src —— bff/ 还没落地，探针无从起跑" >&2
  exit 2
fi

mkdir -p "$PROBE/data"
# src/test/scripts/package.json 带上；node_modules 用符号链接；.env 不带（探针自带环境变量，
# 且 dotenv 默认不覆盖已有 env，但少一份密钥文件更保险）
cp -R "$SRC/src" "$SRC/test" "$SRC/package.json" "$PROBE/" 2>/dev/null
[ -d "$SRC/scripts" ] && cp -R "$SRC/scripts" "$PROBE/scripts"
ln -s "$SRC/node_modules" "$PROBE/node_modules"
cp "$REPO/tools/bff_commercial_probe.mjs" "$PROBE/__commercial_probe.mjs"

echo "隔离副本：$PROBE（仓库零写入）· 端口 $PORT"
echo

PROBE_PORT="$PORT" node "$PROBE/__commercial_probe.mjs"
RC=$?

echo
if [ "$RC" = "0" ]; then
  echo "PROBE_OK 商业化链路无缺陷"
else
  echo "PROBE_RC=$RC 见上方 DEFECT 清单（副本已随进程退出删除，未留下测试数据）"
fi
exit "$RC"
