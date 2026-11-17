#!/usr/bin/env bash
# 手表线协议 + 路由决策表纯逻辑离线验收：
# 把不依赖 @kit 的 .ets 拷成 .ts，用 tsconfig paths 把 `watchcontract` 映射到同一份源码，
# bundled tsc --strict 后再用 bundled node 跑断言。
# 用法：zsh tools/verify_watch_contract.sh
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

# 线协议真源（与 entry / wearable 编译时用的同一份文件）
copy watchcontract/src/main/ets/WatchProtocol.ets watchcontract/WatchProtocol.ts
copy watchcontract/src/main/ets/WatchProjection.ets watchcontract/WatchProjection.ts

# 纯逻辑依赖（CompanionTypes 只依赖 model/Trip）
copy entry/src/main/ets/model/Trip.ets entry/src/main/ets/model/Trip.ts
copy entry/src/main/ets/model/Expense.ets entry/src/main/ets/model/Expense.ts
copy entry/src/main/ets/model/Spot.ets entry/src/main/ets/model/Spot.ts
copy entry/src/main/ets/companion/CompanionTypes.ets entry/src/main/ets/companion/CompanionTypes.ts
copy entry/src/main/ets/watch/WatchRoute.ets entry/src/main/ets/watch/WatchRoute.ts

copy tools/watch_contract_check.ts tools/watch_contract_check.ts

cat > "$TMP/watchcontract/index.ts" <<'EOF'
export * from './WatchProtocol';
export * from './WatchProjection';
EOF

cat > "$TMP/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "strict": true,
    "noEmitOnError": true,
    "target": "ES2020",
    "module": "commonjs",
    "moduleResolution": "node",
    "lib": ["ES2020", "DOM"],
    "rootDir": ".",
    "outDir": "out",
    "baseUrl": ".",
    "paths": {
      "watchcontract": ["watchcontract/index.ts"]
    }
  },
  "include": ["tools/watch_contract_check.ts"]
}
EOF

"$TSC" -p "$TMP/tsconfig.json"

# tsc 只做类型期 paths 映射；运行期补一个 node_modules 软入口，指向同一份编译产物
mkdir -p "$TMP/out/node_modules/watchcontract"
cat > "$TMP/out/node_modules/watchcontract/package.json" <<'EOF'
{
  "name": "watchcontract",
  "version": "1.0.0",
  "main": "index.js"
}
EOF
cat > "$TMP/out/node_modules/watchcontract/index.js" <<'EOF'
module.exports = require('../../watchcontract/index.js');
EOF

"$NODE" "$TMP/out/tools/watch_contract_check.js"
echo "WATCH_CONTRACT_LOGIC_OK"
