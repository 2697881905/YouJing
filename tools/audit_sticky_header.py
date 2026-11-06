#!/usr/bin/env python3
"""第 21 把静态尺：吸顶组头必须有不透明底板，且带高钉在条高 token 上。

来历（§5ci 续 218）：`sticky(StickyStyle.Header)` 的组头压在滚动内容上，
裸 `Text` 没有底板时，下面滚过来的行文字会从组头底下透出来叠成两行。
真例：`SpotPickPage.groupHeader` / `AreaMorePage.groupHeader` 当时都没有底板，
另外三处（OnTripPage / BadgePage / ItineraryPage）都有。
有据同位是定高 36 + 实底板（`PublishTagPanel.ets:83-86`）。

判据（有意保守，只查能静态判定的形状）：
1. 找到 `.sticky(StickyStyle.Header)`；
2. 在同一属性链上下 60 行内找 `ListItemGroup({ header: this.X })`；
3. 回到 `@Builder` 定义里取 `X(...)` 正文（到下一个 `@Builder` 或 30 行为止）；
4. 正文里必须出现 `backgroundColor(`，否则判偏差（否则滚过来的行字压在组头字上）；
5. 正文里还必须出现吸顶带高 token（`stickyHeaderHeight` / `dayDividerHeight`），否则判偏差
   ——组头带的**高度**也得有单源。续 218 只补了底板、带高仍靠 `padding({top,bottom})` 凑，
   四处单行/复合头的 padding 合计分别是 8+4 与 12+4 两种（SpotPick/OnTrip 与 AreaMore/Badge），
   加上 11 号字后各自落到不同档；有据同一形状是 `height(segmentedHeight)` 钉一条 36
   （`PublishTagPanel.ets:83-86`）。本仓为此新立 `LayoutTokens.stickyHeaderHeight = 36`，
   而**不**复用 `segmentedControlHeight`：契约只写了分段控件的 36（DESIGN.md:232、:356），
   单行组头无档；两个 36 绑一起后，任何组头里塞进一条分段控件都会让这把尺误判为已钉高。

用法：python3 tools/audit_sticky_header.py [--selftest] [--pairs]
退出码 0 = 全部合格；1 = 有裸组头或带高没钉（或 selftest 不过）。
"""
import glob
import re
import sys

STICKY = re.compile(r'\.sticky\(StickyStyle\.Header\)')
GROUP = re.compile(r'ListItemGroup\(\{\s*header:\s*this\.(\w+)')
BUILDER = re.compile(r'@Builder\s*\n\s*(\w+)\s*\(', re.M)
BAND = re.compile(r'LayoutTokens\.(stickyHeaderHeight|dayDividerHeight)')
LOOKBACK = 60
BUILDER_LEN = 40

SELFTEST = [
    ('  ListItemGroup({ header: this.groupHeader }) { }\n'
     '  .sticky(StickyStyle.Header)\n'
     '  @Builder\n  groupHeader(g: G) {\n    Text(g.label)\n  }\n', True, '裸组头（真缺陷形状，分组在 sticky 之前）'),
    ('  ListItemGroup({ header: this.groupHeader }) { }\n'
     '  .sticky(StickyStyle.Header)\n'
     '  @Builder\n  groupHeader(g: G) {\n    Text(g.label)\n      .backgroundColor(ColorTokens.canvas)\n  }\n',
     True, '有底板但带高靠 padding 凑（续 218 的状态，第 5 条要拦的就是这个）'),
    ('  ListItemGroup({ header: this.groupHeader }) { }\n'
     '  .sticky(StickyStyle.Header)\n'
     '  @Builder\n  groupHeader(g: G) {\n    Text(g.label)\n'
     '      .backgroundColor(ColorTokens.canvas)\n'
     '      .height(LayoutTokens.stickyHeaderHeight)\n  }\n',
     False, '底板 + 吸顶带高 token'),
    ('  ListItemGroup({ header: this.groupHeader }) { }\n'
     '  .sticky(StickyStyle.Header)\n'
     '  @Builder\n  groupHeader(g: G) {\n    Row(){ Text(g.label) SegmentedBar() }\n'
     '      .backgroundColor(ColorTokens.canvas)\n'
     '      .height(LayoutTokens.segmentedControlHeight)\n  }\n',
     True, '钉的是分段控件的 36，不算组头带高（这个洞就是不复用 segmentedControlHeight 的理由）'),
    ('  ListItemGroup({ header: this.groupHeader }) { }\n'
     '  .sticky(StickyStyle.Header)\n'
     '  @Builder\n  groupHeader(g: G) {\n    Column()\n'
     '      .backgroundColor(ColorTokens.canvas)\n'
     '      .constraintSize({ minHeight: LayoutTokens.dayDividerHeight })\n  }\n',
     False, '复合头用 minHeight 也算钉住'),
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


def scan(name, text, pairs=None):
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
        if pairs is not None:
            pairs.append((name, ln, builder,
                          'backgroundColor(' in body, bool(BAND.search(body))))
        reasons = []
        if 'backgroundColor(' not in body:
            reasons.append('没有 backgroundColor 底板')
        if not BAND.search(body):
            reasons.append('带高没钉条高 token（padding 凑）')
        if reasons:
            hits.append((name, ln, builder, '；'.join(reasons)))
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
    pairs = []
    for path in sorted(glob.glob('entry/src/main/ets/**/*.ets', recursive=True)):
        text = open(path, encoding='utf-8').read()
        hits += scan(path, text, pairs)
    if '--pairs' in sys.argv:
        for name, ln, builder, has_bg, has_band in pairs:
            print('  配对 %-30s L%-5s %s() 底板=%s 条高=%s'
                  % (name.split('/')[-1], ln, builder, 'Y' if has_bg else 'N',
                     'Y' if has_band else 'N'))
    for path, ln, builder, reason in hits:
        print('  %-46s L%-5s 吸顶组头 %s() %s' % (path, ln, builder, reason))
    print('吸顶组头（底板 + 条高单源）：偏差 %d 项 / 配对 %d 处' % (len(hits), len(pairs)))
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
