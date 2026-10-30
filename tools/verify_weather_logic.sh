#!/usr/bin/env bash
# 切片 3（天气 + 建议信号 + 顺延）纯逻辑离线验收：
# 把不依赖 @kit 的 .ets 拷成 .ts，bundled tsc --strict 后再用 bundled node 跑断言。
# 用法：zsh tools/verify_weather_logic.sh
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
copy entry/src/main/ets/model/Replan.ets model/Replan.ts
copy entry/src/main/ets/model/Weather.ets model/Weather.ts
copy entry/src/main/ets/utils/DateUtils.ets utils/DateUtils.ts
copy entry/src/main/ets/utils/Geo.ets utils/Geo.ts
copy entry/src/main/ets/common/error/AppError.ets common/error/AppError.ts
copy entry/src/main/ets/common/error/ErrorCode.ets common/error/ErrorCode.ts
copy entry/src/main/ets/common/weather/WeatherParser.ets common/weather/WeatherParser.ts
copy entry/src/main/ets/data/WeatherAdvisor.ets data/WeatherAdvisor.ts
copy entry/src/main/ets/data/SkipPlanner.ets data/SkipPlanner.ts
copy entry/src/main/ets/data/TripSignals.ets data/TripSignals.ts
copy tools/weather_signals_check.ts tools/weather_signals_check.ts

"$TSC" --strict --noEmitOnError --target ES2020 --module commonjs --moduleResolution node \
  --lib ES2020,DOM --rootDir "$TMP" --outDir "$TMP/out" \
  "$TMP/tools/weather_signals_check.ts"

"$NODE" "$TMP/out/tools/weather_signals_check.js"
echo "WEATHER_LOGIC_OK"
