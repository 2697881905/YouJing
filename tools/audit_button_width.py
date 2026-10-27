#!/usr/bin/env python3
r"""钉底条/动作条里的「宽度算术」错法——三种已被真机各抓到一次的写法。

来历：同一轮里连着出三个表现不同、根因同族的缺陷（§5ci 续 22–29）：

| 屏 | 写法 | 真机后果 |
|----|------|----------|
| 屏3 | 定宽主键 + `Blank()` 挤在一条 Row 里 | 主键被顶出右缘 15.5vp（1136px 屏，bounds 右缘正压屏边） |
| 屏5 | `.layoutWeight(1)` 挂在自定义组件 `YoujingButton` 上 | 权重被框架**静默忽略**，主键一直是死宽，同排控件被挤出屏 |
| 屏9 | `fullWidth: true` 放在有兄弟件的 Row 里 | `fullWidth` 解成**父级 100%**（331.5vp）+ 兄弟 120vp + 间距 → 出屏约 136vp |

统一修法（三处都已按这个改并真机复测）：**剩余宽交给原生 `Column().layoutWeight(1)`，主键再 `fullWidth: true` 填满它**；
自定义组件身上不写通用布局属性。

这三条全是**语法层面就能判死**的（不依赖像素、不依赖文案长度），所以做成常驻尺。
第 ④ 类「定宽 + Blank 的算术够不够」需要真机宽度才判得准，故意**不进这把尺**——
静态估算是 `audit_label_fit.py` 踩过坑的那类假阳性来源。

用法：
  python3 tools/audit_button_width.py            # 全仓
  python3 tools/audit_button_width.py --probe    # 反证尺子三类都抓得到

退出码 0 = 没有这三类写法；1 = 有。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')

CALL = re.compile(r'\b([A-Z]\w*)\s*\(')
FULLWIDTH = re.compile(r'fullWidth:\s*true')
LAYOUT_WEIGHT = re.compile(r'\.layoutWeight\s*\(')
WIDTH_100 = re.compile(r"\.width\(\s*'100%'\s*\)")
HORIZONTAL_KEYS = re.compile(r'\b(left|right)\s*:')

# Row 里这些原生件算「兄弟件」；Blank 单独一条规则，不算进 fullWidth 的兄弟计数
INLINE_ONLY = ('Blank',)


class Stmt(object):
    def __init__(self, name, start, arg_open, arg_close, body, chain):
        self.name = name
        self.start = start
        self.arg_open = arg_open            # '(' 的下标
        self.arg_close = arg_close          # 匹配的 ')' 下标
        self.body = body                    # (open_idx+1, close_idx) 或 None
        self.chain = chain                  # 属性链原文（含点号）
        self.line = 0


def mask(text):
    """字符串字面量与注释一律抹成空格，长度不变——括号配对和正则只吃结构。"""
    out = list(text)
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                out[k] = ' ' if out[k] != '\n' else '\n'
            i = j
        elif c in '"\'`':
            quote = c
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    out[j] = ' '
                    j += 2
                    continue
                if text[j] == quote:
                    break
                if text[j] == '\n':
                    break
                out[j] = ' '
                j += 1
            i = min(j + 1, n)
        else:
            i += 1
    return ''.join(out)


def match_pair(text, i, o, cl):
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c == o:
            depth += 1
        elif c == cl:
            depth -= 1
            if depth == 0:
                return j
    return len(text) - 1


def chain_after(masked, text, i):
    """从下标 i 起吃掉连续的 `.name(...)` / `.name` 段，返回 (链原文, 结束下标)。"""
    parts = []
    j = i
    n = len(masked)
    while True:
        k = j
        while k < n and masked[k] in ' \t\r\n':
            k += 1
        if k >= n or masked[k] != '.':
            return ''.join(parts), j
        m = re.match(r'\.\w+', masked[k:])
        if not m:
            return ''.join(parts), j
        seg = text[k:k + len(m.group(0))]                       # 链原文取**未抹掉**的那份
        p = k + len(m.group(0))
        q = p
        while q < n and masked[q] in ' \t\r\n':
            q += 1
        if q < n and masked[q] == '(':
            close = match_pair(masked, q, '(', ')')
            seg += text[q:close + 1]
            j = close + 1
        else:
            j = k + len(m.group(0))
        parts.append(seg)


def parse(text):
    m = mask(text)
    stmts = []
    for match in CALL.finditer(m):
        name = match.group(1)
        open_idx = m.index('(', match.start())
        close_idx = match_pair(m, open_idx, '(', ')')
        body = None
        tail = close_idx + 1
        while tail < len(m) and m[tail] in ' \t\r\n':
            tail += 1
        owner_end = close_idx
        if tail < len(m) and m[tail] == '{':
            bclose = match_pair(m, tail, '{', '}')
            body = (tail + 1, bclose)
            owner_end = bclose
        chain, _end = chain_after(m, text, owner_end + 1)
        stmt = Stmt(name, match.start(1), open_idx, close_idx, body, chain)
        stmt.line = text[:match.start(1)].count('\n') + 1
        stmts.append(stmt)
    return m, stmts


def children_of(parent, stmts):
    """parent 花括号正文里的**直属**子件。

    两道排除：① 落在别的件**正文**里（那是那件的子件，不是 parent 的）；
    ② 落在别的件**实参括号**里（`Foo(bar(Baz()))` 里的 Baz 不算一行）。
    只排 ② 的第一版把「Row 里包一层 Column 再放主键」这个**修法写法**误报成了
    「主键直挂 Row」——正好把修好的形状又判成缺陷，所以必须两道都排。
    """
    if not parent.body:
        return []
    lo, hi = parent.body
    out = []
    for s in stmts:
        if s is parent or not (lo < s.start < hi):
            continue
        deeper = None
        inside_arg = False
        for u in stmts:
            if u is s:
                continue
            if u.body and u.body[0] < s.start < u.body[1] and lo < u.start < hi:
                if deeper is None or u.body[0] > deeper:
                    deeper = u.body[0]
            if u.arg_open < s.start < u.arg_close and lo <= u.start < hi:
                inside_arg = True
        if deeper is None and not inside_arg:
            out.append(s)
    return out


def custom_component_names(stmts_by_file):
    """仓库里声明过的 struct = 自定义组件；只有它们才吃「通用属性被忽略」这条。"""
    names = set()
    for text in stmts_by_file.values():
        for m in re.finditer(r'\bstruct\s+(\w+)', text):
            names.add(m.group(1))
    return names


def scan_text(name, text, customs):
    _m, stmts = parse(text)
    hits = []
    for s in stmts:
        if s.name != 'Row':
            continue
        kids = children_of(s, stmts)
        fixed_siblings = [k for k in kids if k.name not in INLINE_ONLY]
        for k in kids:
            if k.name == 'YoujingButton' and FULLWIDTH.search(text[k.arg_open:k.arg_close]):
                if len(fixed_siblings) >= 2:
                    hits.append(('A', name, k.line,
                                 'fullWidth 主键直挂 Row，同排还有 %d 个非 Blank 兄弟件'
                                 % (len(fixed_siblings) - 1)))
    for s in stmts:
        if s.name in customs and LAYOUT_WEIGHT.search(s.chain):
            hits.append(('B', name, s.line,
                         '.layoutWeight 挂在自定义组件 %s 上——框架静默忽略' % s.name))
    for s in stmts:
        if not WIDTH_100.search(s.chain):
            continue
        mm = re.search(r'\.margin\(\s*\{[^}]*\}', s.chain)
        bad = False
        if mm and HORIZONTAL_KEYS.search(mm.group(0)):
            bad = True
        m2 = re.search(r'\.margin\(\s*[^{)]', s.chain)   # 单值/常量 margin = 四边，含横向
        if m2:
            bad = True
        if bad:
            hits.append(('C', name, s.line,
                         "%s 身上 .width('100%%') 又加横向 margin = 100%%+边距，必然外溢" % s.name))
    return hits


def probe():
    pos = """
  struct Probe {
    @Builder
    bar() {
      Row({ space: SpaceTokens.md }) {
        YoujingButton({
          variant: YoujingButtonVariant.SECONDARY,
          label: '撤销',
          buttonWidth: 120,
        })
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: '保存修改',
          fullWidth: true,
        })
      }
      Column() {
        ProbeCard({
          label: 'x'
        })
        .layoutWeight(1)
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        Text('a')
      }
      .width('100%')
      .margin({ left: SpaceTokens.md, right: SpaceTokens.md })
      Text('b')
        .width('100%')
        .margin({ top: SpaceTokens.md })
      Row() {
        Text('c')
      }
      .width('100%')
      .margin(SpaceTokens.md)
    }
  }
"""
    neg = """
  struct Probe {
    @Builder
    bar() {
      Row({ space: SpaceTokens.md }) {
        YoujingButton({
          variant: YoujingButtonVariant.SECONDARY,
          label: '帮我选（离景点最近）',
          buttonWidth: 200,
        })
        Column() {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '就住这里',
            fullWidth: true,
          })
        }
        .layoutWeight(1)
      }
      Column() {
        ProbeCard({
          label: 'x'
        })
      }
      .width('100%')
      .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
      Text('b')
        .width('100%')
        .margin({ top: SpaceTokens.md })
    }
  }
"""
    customs = {'ProbeCard'}
    r_pos = scan_text('pos.ets', pos, customs)
    r_neg = scan_text('neg.ets', neg, customs)
    ok = True
    want = {'A': 1, 'B': 1, 'C': 2}          # C 两类写法：对象式 left/right 与单值四边
    for need, count in want.items():
        got = len([h for h in r_pos if h[0] == need])
        if got < count:
            print('PROBE FAILED: 规则 %s 阳性样本抓到 %d 个，应 %d 个' % (need, got, count))
            ok = False
    if r_neg:
        print('PROBE FAILED: 修法样本（原生 Column().layoutWeight(1) 包主键）被误报: %s' % r_neg)
        ok = False
    if ok:
        print('probe ok: A/B/C 四类阳性（C 两种 margin 写法）全抓到，统一修法的写法不报。')
    return 0 if ok else 1


def main():
    texts = {}
    for dirpath, _dirs, files in os.walk(SRC):
        for fn in sorted(files):
            if fn.endswith('.ets'):
                path = os.path.join(dirpath, fn)
                with open(path, encoding='utf-8') as fh:
                    texts[path] = fh.read()
    if '--probe' in sys.argv:
        return probe()
    customs = custom_component_names(texts)
    total = 0
    for path, text in sorted(texts.items()):
        rel = os.path.relpath(path, ROOT)
        for kind, _fn, line_no, why in scan_text(os.path.basename(path), text, customs):
            print('%s:%d  [%s] %s' % (rel, line_no, kind, why))
            total += 1
    if total == 0:
        print('button-width: 没有 fullWidth 挂兄弟 Row / layoutWeight 挂自定义件 / '
              '100% 宽 + 横向 margin 的实例 (pass)')
        return 0
    print('\n%d 处。修法：剩余宽交给原生 Column().layoutWeight(1)，主键再 fullWidth 填满它；'
          "横向让位用 .padding 而不是 margin（见 §5ci 续 22–29）。" % total)
    return 1


if __name__ == '__main__':
    sys.exit(main())
