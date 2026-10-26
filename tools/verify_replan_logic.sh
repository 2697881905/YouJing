#!/usr/bin/env bash
# 纯逻辑离线验收：把不依赖 @kit 的 .ets 拷成 .ts，bundled tsc --strict 后再用 bundled node 跑断言。
# 用法：zsh tools/verify_replan_logic.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TSC="${TSC:-/Applications/DevEco-Studio.app/Contents/tools/ohpm/node_modules/typescript/bin/tsc}"
NODE="${NODE:-/Applications/DevEco-Studio.app/Contents/tools/node/bin/node}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

copy() {
  mkdir -p "$TMP/$(dirname "$2")"
  cp "$ROOT/$1" "$TMP/$2"
}

copy entry/src/main/ets/model/Trip.ets model/Trip.ts
copy entry/src/main/ets/model/Replan.ets model/Replan.ts
copy entry/src/main/ets/utils/DateUtils.ets utils/DateUtils.ts
copy entry/src/main/ets/common/error/AppError.ets common/error/AppError.ts
copy entry/src/main/ets/common/error/ErrorCode.ets common/error/ErrorCode.ts
copy entry/src/main/ets/ai/TripSchema.ets ai/TripSchema.ts
copy entry/src/main/ets/ai/TripParser.ets ai/TripParser.ts
copy entry/src/main/ets/data/SkipPlanner.ets data/SkipPlanner.ts
copy entry/src/main/ets/ai/ReplanParser.ets ai/ReplanParser.ts
copy tools/skip_planner_check.ts tools/skip_planner_check.ts
copy tools/replan_parser_check.ts tools/replan_parser_check.ts

"$TSC" --strict --noEmitOnError --target ES2020 --module commonjs --moduleResolution node \
  --lib ES2020,DOM --rootDir "$TMP" --outDir "$TMP/out" \
  "$TMP/tools/skip_planner_check.ts" "$TMP/tools/replan_parser_check.ts"

"$NODE" "$TMP/out/tools/skip_planner_check.js"
"$NODE" "$TMP/out/tools/replan_parser_check.js"
echo "REPLAN_LOGIC_OK"
