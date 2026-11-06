#!/usr/bin/env python3
"""第 21 把静态尺：吸顶组头必须有不透明底板。

来历（§5ci 续 218）：`sticky(StickyStyle.Header)` 的组头压在滚动内容上，
裸 `Text` 没有底板时，下面滚过来的行文字会从组头底下透出来叠成两行。
真例：`SpotPickPage.groupHeader` / `AreaMorePage.groupHeader` 当时都没有底板，
另外三处（OnTripPage / BadgePage / ItineraryPage）都有。
有据同位是定高 36 + 实底板（`PublishTagPanel.ets:83-86`）。

判据（有意保守，只查能静态判定的形状）：
1. 找到 `.sticky(StickyStyle.Header)`；
2. 在同一属性链上下 60 行内找 `ListItemGroup({ header: this.X })`；
3. 回到 `@Builder` 定义里取 `X(...)` 的正文（到下一个 `@Builder` 或 30 行为止）；
4. 正文里必须出现 `backgroundColor(`；否则判偏差。

用法：python3 tools/audit_sticky_header.py [--selftest]
退出码 0 = 全部有底板；1 = 有裸组头（或 selftest 不过）。
"""
import glob
import re
import sys

STICKY = re.compile(r'\.sticky\(StickyStyle\.Header\)')
GROUP = re.compile(r'ListItemGroup\(\{\s*header:\s*this\.(\w+)')
BUILDER = re.compile(r'@Builder\s*\n\s*(\w+)\s*\(', re.M)
LOOKBACK = 60
BUILDER_LEN = 40

SELFTEST = [
    ('  ListItemGroup({ header: this.groupHeader }) { }\n'
     '  .sticky(StickyStyle.Header)\n'
     '  @Builder\n  groupHeader(g: G) {\n    Text(g.label)\n  }\n', True, '裸组头（真缺陷形状，分组在 sticky 之前）'),
    ('  ListItemGroup({ header: this.groupHeader }) { }\n'
     '  .sticky(StickyStyle.Header)\n'
     '  @Builder\n  groupHeader(g: G) {\n    Text(g.label)\n      .backgroundColor(ColorTokens.canvas)\n  }\n',
     False, '有 canvas 底板'),
    ('  Text(x)\n  .sticky(StickyStyle.Header)\n', False, '只有 sticky 没有分组，不判'),
    ('  // .sticky(StickyStyle.Header)\n  Text(x)\n', False, '注释里的不算'),
    ('  ListItemGroup({ header: this.h }) { }\n  .sticky(StickyStyle.None)\n'
     '  @Builder\n  h() {\n    Text(x)\n  }\n', False, '非吸顶不判'),
]


def header_bodies(text):
    """{builder 名: 正文}"""
    out = {}
    for m in BUILDER.finditer(text):
        start = m.end()
        nxt = text.find('@Builder', start)
        end = nxt if nxt > 0 else len(text)
        out[m.group(1)] = text[start:end][:BUILDER_LEN * 80]
    return out


def scan(name, text):
    hits = []
    if not STICKY.search(text):
        return hits
    bodies = header_bodies(text)
    for m in STICKY.finditer(text):
        # `.sticky()` 在 List 的属性链里，位于分组块的**后面**，所以要往回找。
        # （第一版往后面找，5 处全部"未配对"、于是假报 0 命中——这正是"检测器报 0 先反证"那条。）
        head = text[:m.start()]
        win = head[-LOOKBACK * 80:]
        matches = list(GROUP.finditer(win))
        if not matches:
            continue
        g = matches[-1]
        builder = g.group(1)
        body = bodies.get(builder, '')
        ln = text[:m.start()].count('\n') + 1
        if 'backgroundColor(' not in body:
            hits.append((name, ln, builder))
    return hits


def selftest():
    bad = 0
    for text, expect_hit, note in SELFTEST:
        got = bool(scan('demo.ets', text))
        if got != expect_hit:
            print('  SELFTEST FAIL %s -> got=%s want=%s' % (note, got, expect_hit))
            bad += 1
    if bad:
        print('自测 %d 条不过：控制样本没立住时，真跑的 0 命中不算证据' % bad)
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
    for path in sorted(glob.glob('entry/src/main/ets/**/*.ets', recursive=True)):
        text = open(path, encoding='utf-8').read()
        hits += scan(path, text)
    for path, ln, builder in hits:
        print('  %-46s L%-5s 吸顶组头 %s() 没有 backgroundColor' % (path, ln, builder))
    print('吸顶组头底板：偏差 %d 项' % len(hits))
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
