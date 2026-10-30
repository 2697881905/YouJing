#!/usr/bin/env bash
# 切片 5（行后回顾 / 城市套章 / 周年）纯逻辑离线验收：
# 把不依赖 @kit 的 .ets 拷成 .ts，bundled tsc --strict 后再用 bundled node 跑断言。
# 用法：zsh tools/verify_trip_review.sh
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

copy entry/src/main/ets/model/Trip.ets entry/src/main/ets/model/Trip.ts
copy entry/src/main/ets/model/Expense.ets entry/src/main/ets/model/Expense.ts
copy entry/src/main/ets/utils/BadgeBoard.ets entry/src/main/ets/utils/BadgeBoard.ts
copy entry/src/main/ets/utils/DateUtils.ets entry/src/main/ets/utils/DateUtils.ts
copy entry/src/main/ets/utils/TripReview.ets entry/src/main/ets/utils/TripReview.ts
copy entry/src/main/ets/utils/CityStamps.ets entry/src/main/ets/utils/CityStamps.ts
copy tools/trip_review_check.ts tools/trip_review_check.ts

"$TSC" --strict --noEmitOnError --target ES2020 --module commonjs --moduleResolution node \
  --lib ES2020,DOM --rootDir "$TMP" --outDir "$TMP/out" \
  "$TMP/tools/trip_review_check.ts"

"$NODE" "$TMP/out/tools/trip_review_check.js"
echo "TRIP_REVIEW_OK"
