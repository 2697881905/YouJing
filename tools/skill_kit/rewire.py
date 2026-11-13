#!/usr/bin/env python3
"""
把 Skill 源码里的 @kit.* 引用换成 tools/skill_kit/ 下的替身，并把仓内相对路径
换成离线 tmp 目录里的相对路径。

为什么要这一步：离线跑真脚本时，脚本本体必须**一字不改**地参与编译
（改了就变成测副本而不是测真行为）。所以只动 import 行，不动逻辑。

用法：rewire.py <src.ets> <dst.ts>
"""
import sys

MAP = {
    # @kit.* → 离线替身
    "from '@kit.AbilityKit'": "from './kit/AbilityKit'",
    "from '@kit.BasicServicesKit'": "from './kit/BasicServicesKit'",
    "from '@kit.ArkData'": "from './kit/ArkData'",
    "from '@kit.PerformanceAnalysisKit'": "from './kit/PerformanceAnalysisKit'",
    # 仓内相对路径 → tmp 内相对路径（脚本在 entry/skills/ 下，层级不同）
    "from '../../../src/main/ets/common/logger/Logger'": "from './Logger'",
    "from '../../../src/main/ets/data/SkillPrefill'": "from './SkillPrefill'",
    "from '../../../src/main/ets/utils/DateUtils'": "from './DateUtils'",
    "from '../../../src/main/ets/utils/TripLimits'": "from './TripLimits'",
    "from '../common/logger/Logger'": "from './Logger'",
    "from '../common/constants/BuildConfig'": "from './BuildConfig'",
    "from '../constants/BuildConfig'": "from './BuildConfig'",
    "from '../utils/DateUtils'": "from './DateUtils'",
}


def main() -> int:
    if len(sys.argv) != 3:
        print('usage: rewire.py <src> <dst>', file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding='utf-8') as fh:
        text = fh.read()
    for old, new in MAP.items():
        text = text.replace(old, new)
    with open(sys.argv[2], 'w', encoding='utf-8') as fh:
        fh.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
