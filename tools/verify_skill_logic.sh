#!/usr/bin/env bash
# 小艺 Skill 契约离线验收：把 Skill 脚本与 SkillPrefill 拷成 .ts，bundled tsc --strict
# 后用 bundled node 跑断言，不依赖 @kit / 设备。
#
# 与其它 verify_*.sh 的差别：Skill 脚本本身**依赖 @kit**（AbilityKit 的
# scriptManager 回调、ArkData 的 preferences），所以这里给四个 kit 喂最小替身
# （tools/skill_kit/）。**脚本本体一字不改地参与编译**——断言钉的是真行为，
# 不是复制逻辑重写。
#
# 覆盖：四城白名单 / 四参映射 / 非四城拒绝 / 非法日期 / 过去日期拒绝 / 越界天数人数 /
#       默认值 / message 文案 / 预填取后即删 / 2 小时过期 / 非法字段预填 / clear。
# 日期用例全部相对「今天」生成：写死日期会在某天开始集体变成过去日期而误报。
#
# 用法：bash tools/verify_skill_logic.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TSC="${TSC:-/Applications/DevEco-Studio.app/Contents/tools/ohpm/node_modules/typescript/bin/tsc}"
NODE="${NODE:-/Applications/DevEco-Studio.app/Contents/tools/node/bin/node}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 拷 + 改 import 行（逻辑不动）
copy() {
  mkdir -p "$TMP/$(dirname "$2")"
  python3 "$ROOT/tools/skill_kit/rewire.py" "$ROOT/$1" "$TMP/$2"
}

copy entry/src/main/ets/utils/DateUtils.ets "skill/DateUtils.ts"
copy entry/src/main/ets/utils/TripLimits.ets "skill/TripLimits.ts"
copy entry/src/main/ets/common/constants/BuildConfig.ets "skill/BuildConfig.ts"
copy entry/src/main/ets/common/logger/Logger.ets "skill/Logger.ts"
copy entry/src/main/ets/data/SkillPrefill.ets "skill/SkillPrefill.ts"
copy entry/skills/youjing-plan-trip/scripts/PlanTripSkill.ets "skill/PlanTripSkill.ts"

mkdir -p "$TMP/skill/kit"
cp "$ROOT/tools/skill_kit/AbilityKit.ts" "$TMP/skill/kit/AbilityKit.ts"
cp "$ROOT/tools/skill_kit/BasicServicesKit.ts" "$TMP/skill/kit/BasicServicesKit.ts"
cp "$ROOT/tools/skill_kit/ArkData.ts" "$TMP/skill/kit/ArkData.ts"
cp "$ROOT/tools/skill_kit/PerformanceAnalysisKit.ts" "$TMP/skill/kit/PerformanceAnalysisKit.ts"

cp "$ROOT/tools/skill_check.ts" "$TMP/skill/skill_check.ts"

"$TSC" --strict --noEmitOnError --target ES2020 --module commonjs --moduleResolution node \
  --lib ES2020,DOM --rootDir "$TMP" --outDir "$TMP/out" \
  "$TMP/skill/skill_check.ts"

cat > "$TMP/run.js" <<'RUNJS'
const { runAll } = require('./out/skill/skill_check.js');
runAll().then(() => process.exit(0)).catch((e) => { console.error(e.message); process.exit(1); });
RUNJS

"$NODE" "$TMP/run.js"
echo "SKILL_LOGIC_OK"
