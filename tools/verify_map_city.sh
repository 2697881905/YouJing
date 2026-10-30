#!/usr/bin/env bash
# Stage 2（Map Kit 任意城市映射）纯逻辑离线验收：
# 把不依赖 @kit 的 .ets 拷成 .ts，bundled tsc --strict 后再用 bundled node 跑断言。
# 用法：zsh tools/verify_map_city.sh
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

copy entry/src/main/ets/model/Spot.ets entry/src/main/ets/model/Spot.ts
copy entry/src/main/ets/model/Area.ets entry/src/main/ets/model/Area.ts
copy entry/src/main/ets/utils/Geo.ets entry/src/main/ets/utils/Geo.ts
copy entry/src/main/ets/utils/MapCityMapper.ets entry/src/main/ets/utils/MapCityMapper.ts
copy entry/src/main/ets/common/constants/Cities.ets entry/src/main/ets/common/constants/Cities.ts
copy tools/map_city_check.ts tools/map_city_check.ts

"$TSC" --strict --noEmitOnError --target ES2020 --module commonjs --moduleResolution node \
  --lib ES2020,DOM --rootDir "$TMP" --outDir "$TMP/out" \
  "$TMP/tools/map_city_check.ts"

"$NODE" "$TMP/out/tools/map_city_check.js"
echo "MAP_CITY_OK"
