#!/usr/bin/env python3
"""每个 HdsChrome.bar() 调用点必须表态 scrolled 或 scrollable（契约 v2 T4 Step 5 的机检）。

多行 spec 要按括号配平取整段，所以先跑自证：喂一条已知带 scrolled 的样本必须判"已表态"、
喂一条已知没表态的样本必须判"未表态"——否则这把尺的读数没有意义
（第一版把 depth 起点写成 0，22 个调用点全被误判成未表态）。
"""
import glob
import re
import sys


def spec_of(lines, i):
    """从第 i 行（含 HdsChrome.bar( ）起，按括号配平取到该调用的完整实参文本"""
    text = '\n'.join(lines[i:])
    m = re.search(r'HdsChrome\.bar\(', text)
    if not m:
        return ''
    rest = text[m.end():]
    depth = 1
    out = []
    for ch in rest:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                break
        out.append(ch)
    return ''.join(out)


def declared(spec):
    return 'scrolled' in spec or 'scrollable' in spec


SELF = [
    ('  .titleBar(HdsChrome.bar({ mainTitle: ' + "'旅行回顾'" + ', scrolled: this.barScrolled }))', True),
    ('  .titleBar(HdsChrome.bar({ mainTitle: ' + "'费用'" + ' }))', False),
    ('  return HdsChrome.bar({', True),
]
# 第三条是多行形态：靠后续行补齐
SELF_MULTI = [
    '  return HdsChrome.bar({',
    "    mainTitle: '行程',",
    '    scrolled: this.barScrolled,',
    '  });',
]
ok1 = declared(spec_of([SELF[0][0]], 0)) == SELF[0][1]
ok2 = declared(spec_of([SELF[1][0]], 0)) == SELF[1][1]
ok3 = declared(spec_of(SELF_MULTI, 0)) == SELF[2][1]
if '--selftest' in sys.argv:
    print(f'[selftest] 单行已表态={ok1} 单行未表态={ok2} 多行已表态={ok3}')
    sys.exit(0 if (ok1 and ok2 and ok3) else 1)
if not (ok1 and ok2 and ok3):
    print('[selftest] 判据本身失效，拒绝出数（别把这把尺的读数当结论）')
    sys.exit(1)

bad = []
total = 0
for path in sorted(glob.glob('entry/src/main/ets/pages/*.ets')
                   + glob.glob('entry/src/main/ets/components/*.ets')):
    lines = open(path, encoding='utf-8').read().split('\n')
    for i, ln in enumerate(lines):
        if 'HdsChrome.bar(' not in ln or ln.strip().startswith('*'):
            continue
        total += 1
        if not declared(spec_of(lines, i)):
            bad.append(f'{path}:{i + 1}')

print(f'bar 调用点 {total} 处，未表态 {len(bad)} 处')
for b in bad:
    print('  未表态:', b)
sys.exit(1 if bad else 0)
