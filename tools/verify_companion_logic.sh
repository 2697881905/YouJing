#!/usr/bin/env bash
# 伴随助手核心逻辑（偏好降级 + 规划外到访请示引擎）纯逻辑离线验收：
# 把不依赖 @kit 的 .ets 拷成 .ts，bundled tsc --strict 后再用 bundled node 跑断言。
# 用法：zsh tools/verify_companion_logic.sh
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
copy entry/src/main/ets/model/Expense.ets model/Expense.ts
copy entry/src/main/ets/model/Spot.ets model/Spot.ts
copy entry/src/main/ets/utils/DateUtils.ets utils/DateUtils.ts
copy entry/src/main/ets/utils/Geo.ets utils/Geo.ts
copy entry/src/main/ets/companion/CompanionTypes.ets companion/CompanionTypes.ts
copy entry/src/main/ets/companion/CompanionPrefs.ets companion/CompanionPrefs.ts
copy entry/src/main/ets/companion/CompanionEngine.ets companion/CompanionEngine.ts
copy tools/companion_check.ts tools/companion_check.ts

"$TSC" --strict --noEmitOnError --target ES2020 --module commonjs --moduleResolution node \
  --lib ES2020,DOM --rootDir "$TMP" --outDir "$TMP/out" \
  "$TMP/tools/companion_check.ts"

"$NODE" "$TMP/out/tools/companion_check.js"
echo "COMPANION_LOGIC_OK"