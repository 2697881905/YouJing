#!/usr/bin/env python3
"""第 23 把静态尺：每个页面壳必须设 titleBar 且档位钉 MINI。

来历（§5ci 续 242）：组件选档普查发现两仓的子页壳走的是两条路线——
有据 `NavDestination` 里嵌 `HdsNavigation().titleBar(...)`（`HdsNavigationTitleMode.MINI` 11 处），
有径 `HdsNavDestination().titleBar({...})`（`HdsNavDestinationTitleMode.MINI` 18 处 + 五格容器 5 处）。
**档位两边一模一样，都是 MINI（固定 56vp 栏）**，差的只是 API 路线，所以不改动代码；
但这类"同值不同写法"最容易被后来者漏设，漏掉的那页会掉回组件默认档。

判据：
R1 每处 `HdsNavDestination()` 必须在其属性链**或** `titleBar({ titleBarStyle… })` 对象里
   设到 titleBar，且档位必须是 MINI；
R2 每处 `HdsNavigation()`（容器/分格）同理；
R3 两仓口径都数得出来：有径 23 处（18 子页 + 5 格），少一处即偏差。

对象形与链式形都要认——先前一版只认链式 `.titleMode(...)`，于是 4 页被误报成"没设档"，
实际它们写在 `titleBar({ titleBarStyle: { titleMode: … } })` 里（这正是"检测器报 0/报 N 先反证"）。

用法：python3 tools/audit_page_chrome.py [--selftest] [--list]
退出码 0 = 全部设齐；1 = 有漏设或档位不是 MINI。
"""
import glob
import re
import sys

# 带参形式也要认：五格容器写的是 `HdsNavigation(this.pathStack)`，
# 只匹配 `HdsNavigation()` 会漏掉 5 个容器（壳数会从 23 少到 18）。
NAVDEST = re.compile(r'(?<![\w.])HdsNavDestination\s*\(')
NAV = re.compile(r'(?<![\w.])HdsNavigation\s*\(')
MINI = re.compile(r'TitleMode\.MINI')
TITLE_BAR = re.compile(r'titleBar\(|\.titleBar\(')

BLOCK_OPEN = re.compile(r'\{')


def block_close(text, brace_idx):
    depth = 0
    for j in range(brace_idx, len(text)):
        if text[j] == '{':
            depth += 1
        elif text[j] == '}':
            depth -= 1
            if depth == 0:
                return j
    return len(text) - 1


def call_close(text, open_idx):
    """从调用左括号做配对，返回右括号位置（参数里可能带对象，不能直接找 '{'）"""
    depth = 0
    for j in range(open_idx, len(text)):
        if text[j] == '(':
            depth += 1
        elif text[j] == ')':
            depth -= 1
            if depth == 0:
                return j
    return open_idx


def scope_of(text, m):
    """返回 (属性链, 组件正文)。链从闭括号后开始，
    **必须跟着括号平衡走**：`titleBar({ ... })` 常常跨多行，
    早先只收 `.` 开头的行，第二行的 `style: { titleMode: … }` 就掉了，
    于是把已经设齐的页误报成"档位看不见"（自测先抓到这一点）。"""
    brace = text.index('{', call_close(text, text.index('(', m.start())) + 1)
    end = block_close(text, brace)
    body = text[brace + 1:end]
    chain = []
    open_paren = 0
    open_brace = 0
    for line in text[end + 1:].split('\n')[1:]:
        s = line.strip()
        balanced = open_paren == 0 and open_brace == 0
        if not s:
            # 空行不能终止链：`}` 之后那一行的残余就是空串，属性常写在它下面几行
            continue
        if s.startswith('//') or s.startswith('*'):
            continue
        if s.startswith('.') or not balanced:
            chain.append(s)
            open_paren += s.count('(') - s.count(')')
            open_brace += s.count('{') - s.count('}')
            if open_paren < 0:
                open_paren = 0
            if open_brace < 0:
                open_brace = 0
        else:
            break
    return '\n'.join(chain), body


def strip_keep_lines(text):
    """剥注释但保留换行——直接删会让后面的行号整体前移，报出来的行号就是假的
    （这一版先踩了两次：一次误报 4 页"没设档"，一次把注释里的 HdsNavigation 当壳数）。"""
    out = []
    i = 0
    n = len(text)
    in_block = False
    while i < n:
        c = text[i]
        if in_block:
            if c == '*' and i + 1 < n and text[i + 1] == '/':
                in_block = False
                out.append('  ')
                i += 2
                continue
            out.append('\n' if c == '\n' else ' ')
            i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            in_block = True
            out.append('  ')
            i += 2
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def check(name, text):
    text = strip_keep_lines(text)
    hits = []
    for pat, label in ((NAVDEST, 'HdsNavDestination'), (NAV, 'HdsNavigation')):
        for m in pat.finditer(text):
            if text[:m.start()].split('\n')[-1].strip().startswith('//'):
                continue
            chain, body = scope_of(text, m)
            ln = text[:m.start()].count('\n') + 1
            has_bar = bool(TITLE_BAR.search(chain)) or bool(TITLE_BAR.search(body))
            has_mini = bool(MINI.search(chain)) or bool(MINI.search(body))
            if not has_bar:
                hits.append((name, ln, label, '没设 titleBar（该页会掉回组件默认档）'))
            elif not has_mini:
                hits.append((name, ln, label, 'titleBar 档位不是 MINI（有据全仓 11 处都是 MINI）'))
    return hits


SELFTEST = [
    ('  HdsNavDestination() {\n    Text(x)\n  }\n  .width(\'100%\')\n',
     True, '子页壳没设 titleBar'),
    ('  HdsNavDestination() {\n    Text(x)\n  }\n  .titleBar(this.bar)\n',
     True, '设了栏但档位看不见（不是 MINI）'),
    ('  HdsNavDestination() {\n    Text(x)\n  }\n  .titleBar({\n'
     '    style: { titleMode: HdsNavDestinationTitleMode.MINI }\n  })\n',
     False, '链式 + 对象形都齐（有径 4 页的真实写法）'),
    ('  HdsNavDestination() {\n    Text(x)\n  }\n  .titleBar({ titleBarStyle: { '
     'titleMode: HdsNavDestinationTitleMode.MINI } })\n',
     False, 'titleBarStyle 形状'),
    ('  // HdsNavDestination() {\n  // }\n', False, '行注释里的壳不算'),
    ('  /**\n   * 文件头说这页被 push 时走 HdsNavDestination\n   */\n'
     '  HdsNavDestination() {\n    Text(x)\n  }\n  .titleBar({ style: {\n'
     '    titleMode: HdsNavDestinationTitleMode.MINI } })\n',
     False, '块注释里的名字不算壳（真有 1 个壳时读数是 1 不是 2）'),
    ('  HdsNavDestination() {\n    Text(x)\n  }\n\n'
     '  .titleBar(this.bar)\n  .titleMode(HdsNavDestinationTitleMode.MINI)\n',
     False, '闭括号与属性链之间有空行（这一版曾经在这里终止扫描、误报 18 处）'),
    ('  HdsNavigation() {\n    Text(x)\n  }\n  .titleBar({ style: {\n'
     '    titleMode: HdsNavigationTitleMode.MINI } })\n',
     False, '容器形（有据路线）齐'),
    ('  HdsNavigation(this.stack) {\n    TabContent() { Text(x) }\n  }\n'
     '  .titleBar({ style: { titleMode: HdsNavigationTitleMode.MINI } })\n',
     False, '带参容器形（有径五格真实写法，早前漏匹配的那一类）'),
    ('  HdsNavigation(this.stack) {\n    TabContent() { Text(x) }\n  }\n  .barMode(BarMode.Scrollable)\n',
     True, '带参容器但没设 titleBar'),
]


def selftest():
    bad = 0
    for text, expect_hit, note in SELFTEST:
        got = bool(check('demo.ets', text))
        if got != expect_hit:
            print('  SELFTEST FAIL %s -> got=%s want=%s' % (note, got, expect_hit))
            bad += 1
    if bad:
        print('自测 %d 条不过：控制样本没立住时，真跑的读数不算证据' % bad)
        return 1
    print('自测通过：阳性 %d / 阴性 %d'
          % (sum(1 for x in SELFTEST if x[1]), sum(1 for x in SELFTEST if not x[1])))
    return 0


def main():
    if '--selftest' in sys.argv:
        return selftest()
    if selftest() != 0:
        return 1
    hits = []
    shells = 0
    for path in sorted(glob.glob('entry/src/main/ets/**/*.ets', recursive=True)):
        text = strip_keep_lines(open(path, encoding='utf-8').read())
        found = check(path, text)
        shells += len(list(NAVDEST.finditer(text))) + len(list(NAV.finditer(text)))
        hits += found
    if '--list' in sys.argv:
        for path in sorted(glob.glob('entry/src/main/ets/**/*.ets', recursive=True)):
            text = strip_keep_lines(open(path, encoding='utf-8').read())
            n = len(list(NAVDEST.finditer(text))) + len(list(NAV.finditer(text)))
            if n:
                print('  %-46s 壳 %d 处' % (path.replace('entry/src/main/ets/', ''), n))
    for name, ln, label, reason in hits:
        print('  %-46s L%-5s %s %s' % (name, ln, label, reason))
    print('页面壳档位一致性：壳 %d 处，偏差 %d 项' % (shells, len(hits)))
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
