#!/usr/bin/env python3
"""每个 HdsChrome.bar() 调用点必须表态 scrolled 或 scrollable（契约 v2 T4 Step 5 的机检）。

多行 spec 要按括号配平取整段，所以先跑自证：喂一条已知带 scrolled 的样本必须判"已表态"、
喂一条已知没表态的样本必须判"未表态"、注释里的那条必须**不**数成调用点——
否则这把尺的读数没有意义
（第一版把 depth 起点写成 0，22 个调用点全被误判成未表态；2026-11-05 又数过一条注释）。
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


def is_call_site(ln):
    """注释里出现的 `HdsChrome.bar(` 不是调用点。

    2026-11-05 假红：把「带子色为什么不能交给栏体」写进 `pages/Index` 的注释，
    这把尺把那条注释数成一个未表态的调用点（22→23 处、报 Index:303）。
    讲机制的注释是这仓库的常规写法，尺必须跳过 `//` 与 `*` 开头的行。
    """
    s = ln.strip()
    return 'HdsChrome.bar(' in ln and not s.startswith(('*', '//'))


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
# 第四条：注释里的 HdsChrome.bar( 不算调用点（阳性=真调用，阴性=注释行）
ok4 = (is_call_site('  .titleBar(HdsChrome.bar({ mainTitle: x }))')
       and not is_call_site('    // 试过 `HdsChrome.bar({ barBackground })` 也不成立'))
if '--selftest' in sys.argv:
    print(f'[selftest] 单行已表态={ok1} 单行未表态={ok2} 多行已表态={ok3} 注释不算调用点={ok4}')
    sys.exit(0 if (ok1 and ok2 and ok3 and ok4) else 1)
if not (ok1 and ok2 and ok3 and ok4):
    print('[selftest] 判据本身失效，拒绝出数（别把这把尺的读数当结论）')
    sys.exit(1)

bad = []
total = 0
for path in sorted(glob.glob('entry/src/main/ets/pages/*.ets')
                   + glob.glob('entry/src/main/ets/components/*.ets')):
    lines = open(path, encoding='utf-8').read().split('\n')
    for i, ln in enumerate(lines):
        if not is_call_site(ln):
            continue
        total += 1
        if not declared(spec_of(lines, i)):
            bad.append(f'{path}:{i + 1}')

print(f'bar 调用点 {total} 处，未表态 {len(bad)} 处')
for b in bad:
    print('  未表态:', b)
sys.exit(1 if bad else 0)
