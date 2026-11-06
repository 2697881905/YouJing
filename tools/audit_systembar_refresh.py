#!/usr/bin/env python3
"""第 22 把静态尺：顶栏两态宿主必须在回顶时补设系统栏（HDS 会回写图标明暗）。

来历（§5ci 续 236）：`utils/systemBar.ets` 的补设通道与有据同构（四连发
400/1000/1800/3000ms，EntryAbility 注册刷新器），但**宿主只接了一个**
（`YoujingStartPage`）。其余 15 个同样用绝对偏移驱动顶栏磨砂的页面，滚回顶部时
HDS 把 `isStatusBarLightIcon` 回写成按系统深浅渲染——系统深＋应用浅的组合态下
状态栏图标渲成白色、浅色画布上直接看不见。这条在有据是 2026-10-25 真机实证过两次的，
我们只搬了通道没搬接线，等于把同一个缺陷留在 15 屏上。

判据：
R1 含 `syncBarScroll` 且函数体读 `currentOffset()…yOffset` 的文件，必须
   (a) 在体内调用 `requestSystemBarRefresh();`
   (b) 且该调用被回顶条件（`if (!on)` 或 `y <= 0` / `offset <= 0`）包住——
       无条件挂在每帧上会不停重排四发定时器；
   (c) 且恰好一条 `import { requestSystemBarRefresh } from '../utils/systemBar'`。
R2 `entryability` 必须注册刷新器（`setSystemBarRefresher(`）——没注册时四连发是空响。
R3 `utils/systemBar.ets` 的连发档必须 ≥3 发且最后一发 ≥2500ms：单发 400ms 与
   HDS 回写构成竞速（有据两次复现分别在 <0.6s 与 ~2.9s），已被证伪。

注释里的调用不算（先剥注释再判）。

用法：python3 tools/audit_systembar_refresh.py [--selftest] [--hosts]
退出码 0 = 全部接线；1 = 有漏接（或 selftest 不过）。
"""
import glob
import re
import sys

SYNC_FN = re.compile(r'private syncBarScroll\(\): void \{(.*?)\n  \}\n', re.S)
OFFSET = re.compile(r'currentOffset\(\)\??\.yOffset')
CALL = re.compile(r'requestSystemBarRefresh\(\);')
GUARD = re.compile(r'if \(!on\) \{[^}]*requestSystemBarRefresh\(\);|'
                   r'if \(y <= 0\) \{[^}]*requestSystemBarRefresh\(\);|'
                   r'if \(offset <= 0\) \{[^}]*requestSystemBarRefresh\(\);', re.S)
IMPORT = re.compile(r"import \{[^}]*requestSystemBarRefresh[^}]*\} from '\.\./utils/systemBar';")
BURST = re.compile(r'REFRESH_SHOTS_MS[^=]*=\s*\[([^\]]*)\]')

BLOCK = re.compile(r'/\*.*?\*/', re.S)
LINE = re.compile(r'//[^\n]*')


def strip_comments(text):
    return LINE.sub('', BLOCK.sub('', text))


def shots(text):
    m = BURST.search(strip_comments(text))
    if not m:
        return []
    return [s.strip() for s in m.group(1).split(',') if s.strip().isdigit()]


def check_global(files):
    """R2 / R3，返回偏差列表"""
    hits = []
    reg = [p for p, t in files
           if re.search(r'setSystemBarRefresher\(', strip_comments(t))
           and 'entryability' in p]
    if not reg:
        hits.append(('entryability', 0, 'R2 没注册补设器：四连发是空响'))
    burst = [(p, t) for p, t in files if p.endswith('utils/systemBar.ets')]
    if not burst:
        hits.append(('utils/systemBar.ets', 0, 'R3 补设通道不存在'))
    for p, t in burst:
        s = shots(t)
        last = int(s[-1]) if s else 0
        if len(s) < 3 or last < 2500:
            hits.append((p, 0, 'R3 连发不足（%s 发，末发 %sms）：单发会被 HDS 回写吃掉'
                         % (len(s), last)))
    return hits


def scan(name, text):
    hits = []
    clean = strip_comments(text)
    for m in SYNC_FN.finditer(clean):
        body = m.group(1)
        if not OFFSET.search(body):
            continue
        ln = clean[:m.start()].count('\n') + 1
        if not CALL.search(body):
            hits.append((name, ln, 'R1 回顶没补设（缺 requestSystemBarRefresh 调用）'))
        elif not GUARD.search(body):
            hits.append((name, ln, 'R1 调用没被回顶条件包住（每帧重排定时器）'))
        elif len(IMPORT.findall(clean)) != 1:
            hits.append((name, ln, 'R1 import 不为恰好一条（实得 %d）'
                         % len(IMPORT.findall(clean))))
    return hits


HOST = (
    "import { requestSystemBarRefresh } from '../utils/systemBar';\n"
    '  private syncBarScroll(): void {\n'
    '    const y: number = this.barScroller.currentOffset().yOffset;\n'
    '    const on: boolean = y > 0;\n'
    '    if (on !== this.barScrolled) {\n'
    '      this.barScrolled = on;\n'
    '      if (!on) {\n'
    '        requestSystemBarRefresh();\n'
    '      }\n'
    '    }\n'
    '  }\n')

SELFTEST = [
    (HOST.replace('      if (!on) {\n        requestSystemBarRefresh();\n      }\n', ''),
     True, '回顶没补设（正是改前 15 个宿主的形状）'),
    (HOST.replace('    if (on !== this.barScrolled) {\n      this.barScrolled = on;\n'
                  '      if (!on) {\n        requestSystemBarRefresh();\n      }\n    }\n',
                  '    this.barScrolled = on;\n    requestSystemBarRefresh();\n'),
     True, '调用挂在每帧上、没被回顶条件包住'),
    (HOST.replace("import { requestSystemBarRefresh } from '../utils/systemBar';\n", ''),
     True, '调用了但没 import'),
    ('  // requestSystemBarRefresh();\n' + HOST.replace('        requestSystemBarRefresh();', ''),
     True, '只有注释里提到，不算接线'),
    (HOST, False, '已按形状接好'),
    ('  private syncBarScroll(): void {\n    const y: number = 0;\n  }\n',
     False, '不读真实偏移的 syncBarScroll 不判'),
    ('  build() { Text(x) }\n', False, '非宿主文件不判'),
]

BURST_SELFTEST = [
    ('const REFRESH_SHOTS_MS: number[] = [400];', 1, '单发（已被真机证伪的形状）'),
    ('const REFRESH_SHOTS_MS: number[] = [400, 1000, 1800, 3000];', 4, '有据同构四发'),
    ('const REFRESH_SHOTS_MS: number[] = [300, 900, 2600];', 3, '三发但末发够晚'),
]


def selftest():
    bad = 0
    for text, expect_hit, note in SELFTEST:
        got = bool(scan('demo.ets', text))
        if got != expect_hit:
            print('  SELFTEST FAIL %s -> got=%s want=%s' % (note, got, expect_hit))
            bad += 1
    for text, expect_shots, note in BURST_SELFTEST:
        got = len(shots(text))
        if got != expect_shots:
            print('  SELFTEST FAIL 连发%s -> 解析到 %d 发，应为 %d' % (note, got, expect_shots))
            bad += 1
    if bad:
        print('自测 %d 条不过：控制样本没立住时，真跑的 0 命中不算证据' % bad)
        return 1
    print('自测通过：宿主阳性 %d / 阴性 %d，连发样本 %d'
          % (sum(1 for x in SELFTEST if x[1]), sum(1 for x in SELFTEST if not x[1]),
             len(BURST_SELFTEST)))
    return 0


def main():
    if '--selftest' in sys.argv:
        return selftest()
    if selftest() != 0:
        return 1
    files = []
    for path in sorted(glob.glob('entry/src/main/ets/**/*.ets', recursive=True)):
        files.append((path, open(path, encoding='utf-8').read()))
    hits = []
    hosts = 0
    for path, text in files:
        found = scan(path, text)
        hosts += len([1 for m in SYNC_FN.finditer(strip_comments(text))
                      if OFFSET.search(m.group(1))])
        hits += found
    if '--hosts' in sys.argv:
        for path, text in files:
            for m in SYNC_FN.finditer(strip_comments(text)):
                if OFFSET.search(m.group(1)):
                    print('  宿主 %-40s %s' % (path.split('/')[-1],
                                              'OK' if not scan(path, text) else '偏差'))
    hits += check_global(files)
    for path, ln, reason in hits:
        print('  %-46s L%-5s %s' % (path, ln, reason))
    print('回顶补设：宿主 %d 处，偏差 %d 项' % (hosts, len(hits)))
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
