#!/usr/bin/env bash
# 切片 4（一句话解析 + 自动选点/住宿区）纯逻辑离线验收：
# 把不依赖 @kit 的 .ets 拷成 .ts，bundled tsc --strict 后再用 bundled node 跑断言。
# 用法：zsh tools/verify_trip_intent.sh
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

copy entry/src/main/ets/model/Spot.ets model/Spot.ts
copy entry/src/main/ets/model/Area.ets model/Area.ts
copy entry/src/main/ets/model/PlanParams.ets model/PlanParams.ts
copy entry/src/main/ets/utils/Geo.ets utils/Geo.ts
copy entry/src/main/ets/utils/DateUtils.ets utils/DateUtils.ts
copy entry/src/main/ets/utils/TripIntentParser.ets utils/TripIntentParser.ts
copy entry/src/main/ets/utils/PlanAutoPick.ets utils/PlanAutoPick.ts
copy entry/src/main/ets/common/constants/BudgetConfig.ets common/constants/BudgetConfig.ts
copy entry/src/main/ets/common/constants/Cities.ets common/constants/Cities.ts
copy tools/trip_intent_check.ts tools/trip_intent_check.ts

"$TSC" --strict --noEmitOnError --target ES2020 --module commonjs --moduleResolution node \
  --lib ES2020,DOM --rootDir "$TMP" --outDir "$TMP/out" \
  "$TMP/tools/trip_intent_check.ts"

"$NODE" "$TMP/out/tools/trip_intent_check.js"
echo "TRIP_INTENT_OK"
