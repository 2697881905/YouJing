#!/usr/bin/env python3
"""字号契约核对：Text 的字号必须走 TypeTokens，SymbolGlyph 的必须走 IconSizes。

契约（DESIGN.md §2）允许的字号只有 10/11/12/14/16/18/21/32，
图标只有 22（控制档）/48（展示档）——底稿帧里另有 12/14/20 的内容图标，
那几档还没获设计方裁决（见任务 #28 第 ⑧ 条），所以本脚本把它们列成
「待裁决」而不是「违规」，避免把未定的事写成已定。

用法：python3 tools/audit_type.py
退出码 0 = 无违规；1 = 有 Text 字号绕过 token。
"""

import glob
import os
import re
import sys

ALLOWED_TEXT_SIZES = {10, 11, 12, 14, 16, 18, 21, 32}
ICON_TOKEN_SIZES = {12, 14, 18, 20, 22, 48}


def owner_of(lines, idx):
    """往上找这个 .fontSize 挂在哪个组件上"""
    for j in range(idx, max(-1, idx - 6), -1):
        s = lines[j]
        if 'SymbolGlyph(' in s:
            return 'SymbolGlyph'
        m = re.search(r'\bText\(', s)
        if m:
            return 'Text'
        if re.match(r'^\s{0,6}(?:@Builder|private |export |\}\s*$|\s*$)', s):
            continue
    return '?'


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = sorted(glob.glob(os.path.join(root, 'entry/src/main/ets/pages/*.ets')) +
                   glob.glob(os.path.join(root, 'entry/src/main/ets/components/*.ets')) +
                   glob.glob(os.path.join(root, 'entry/src/main/ets/widget/**/*.ets'), recursive=True))
    bad = []
    icon_literals = []
    for path in files:
        rel = os.path.relpath(path, root)
        lines = open(path, encoding='utf-8').read().split('\n')
        for i, line in enumerate(lines):
            code = re.sub(r'//.*', '', line)
            m = re.search(r'\.fontSize\(\s*(\d+)\s*\)', code)
            if not m:
                continue
            size = int(m.group(1))
            owner = owner_of(lines, i)
            if owner == 'Text':
                if size not in ALLOWED_TEXT_SIZES:
                    bad.append((rel, i + 1, size, owner, '字号不在契约八档里'))
                else:
                    bad.append((rel, i + 1, size, owner, 'Text 字号应写 TypeTokens.<档>.size'))
            elif owner == 'SymbolGlyph':
                if size not in ICON_TOKEN_SIZES:
                    icon_literals.append((rel, i + 1, size, '图标档位外'))
                else:
                    icon_literals.append((rel, i + 1, size, '应写 IconSizes.<档>'))
            else:
                icon_literals.append((rel, i + 1, size, '归属未识别：' + owner))
    print('== Text 绕过字阶 token（必须修）==', len(bad))
    for rel, ln, size, owner, why in bad:
        print('  {:44} L{:<5} {}px {} {}'.format(rel, ln, size, owner, why))
    print('== 图标/未识别（含待裁决档位）==', len(icon_literals))
    for rel, ln, size, why in icon_literals:
        print('  {:44} L{:<5} {}px {}'.format(rel, ln, size, why))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
