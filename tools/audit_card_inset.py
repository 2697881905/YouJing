#!/usr/bin/env python3
"""第 20 把静态尺：同一种卡（`RadiusTokens.card`）只能有一种内容内缩。

来历（§5ci 续 212）：有径 同一个 `RadiusTokens.card`(20) 圆角配了两种内缩——
`SpaceTokens.sm`(12) 26 处 vs `SpaceTokens.base`(16) 18 处。
`TripsPage.ets:486` 用 12、`MinePage.ets:207` 用 16 ⇒ 同一种卡在两屏之间
内容离卡边跳 4vp。有据侧通用卡钉 16（`BaseCard.ets:12`）。

判据：凡属性链里出现 `.borderRadius(RadiusTokens.card)`，往上找**最近的一个** `.padding(...)`，
它必须用规范档（默认 `base`）。理由是同一条链上相邻的两个属性描述的是同一个容器，
不需要精确配对就能判"这张卡用了哪一档内缩"。

用法：
  python3 tools/audit_card_inset.py                 # 全仓
  python3 tools/audit_card_inset.py --selftest      # 控制样本必须先立住
  python3 tools/audit_card_inset.py --canonical sm  # 临时换规范档（收口过程中用）

退出码 0 = 没有混用；1 = 有。
"""
import glob
import re
import sys

PADDING = re.compile(r'\.padding\(\s*(?:\{[^)]*\})?')
CARD_RADIUS = re.compile(r'\.borderRadius\(\s*RadiusTokens\.card\s*\)')
TOKEN_IN = re.compile(r'SpaceTokens\.(\w+)')
LOOKBACK = 8

SELFTEST = [
    ('  .padding(SpaceTokens.sm)\n  .borderRadius(RadiusTokens.card)\n', 'base', True,
     '卡面用 sm=12（今晚的真混用）'),
    ('  .padding(SpaceTokens.base)\n  .borderRadius(RadiusTokens.card)\n', 'base', False,
     '卡面用 base=16（规范）'),
    ('  .padding({ left: SpaceTokens.base, right: SpaceTokens.base, bottom: SpaceTokens.sm })\n'
     '  .borderRadius(RadiusTokens.card)\n', 'base', False, '对象式 padding，主内缩是 base'),
    ('  .padding(SpaceTokens.sm)\n  .borderRadius(RadiusTokens.reason)\n', 'base', False,
     '非卡面（reason 档）不判'),
    ('  .padding(SpaceTokens.base)\n  .borderRadius(RadiusTokens.card)\n', 'sm', True,
     '规范档换成 sm 时 base 就成了偏差'),
    ('  .padding(0)\n  .borderRadius(RadiusTokens.card)\n', 'base', False,
     '整宽按钮披卡圆角：padding(0) 是满铺，不是混用'),
    ('      .padding(SpaceTokens.sm)\n      }\n      .width(\'100%\')\n'
     '      .height(200)\n      .borderRadius(RadiusTokens.card)\n', 'base', False,
     'padding 属于上一个兄弟节点（跨出链）——地图卡那行覆盖钮的真形状'),
    ('  .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })\n'
     '  .borderRadius(RadiusTokens.card)\n', 'base', False,
     '只有上下节奏、横向在父级：拖动态行'),
    ('  .height(\'100%\')\n  .borderRadius(RadiusTokens.card)\n  .clip(true)\n', 'base', False,
     '媒体铺满卡（clip 容器）本来就没有内容内缩：地图卡/分组容器'),
    ('  .padding(SpaceTokens.base)\n  .borderRadius(RadiusTokens.card)\n  .clip(true)\n', 'base', False,
     'clip 不影响判定：规范档仍是规范档'),
]


FLUSH = re.compile(r'\.padding\(\s*0\s*\)')


BLOCK_CLOSE = re.compile(r'^\s*}\s*(?:,\s*)?$')


def nearest_padding_token(lines, idx):
    """从 borderRadius 那行往上找最近的 .padding(...)，返回它用的 SpaceTokens 档名。

    `.padding(0)` 豁免并单列：那三处是**整宽按钮披着卡圆角**（`ButtonStyleMode.TEXTUAL` +
    `width('100%')` + `padding(0)`，如 `TripsPage.ets:497`、`TripInputPage.ets:839/877`），
    内缩由里面的内容自己给，不是卡面内缩——算进偏差就是把一种有意的满铺件当成混用。
    """
    for j in range(idx, max(-1, idx - LOOKBACK), -1):
        if j != idx and BLOCK_CLOSE.match(lines[j]):
            # 已经跨出当前节点的属性链：这个 padding 属于**上一个兄弟节点**，
            # 不是这张卡的内缩。真例：`ItineraryPage.ets:1297` 是地图卡里那行覆盖钮的
            # padding，`1303` 的 `borderRadius(card)` 属于父卡——配对起来就是假偏差。
            return None, None
        if PADDING.search(lines[j]):
            if FLUSH.search(lines[j]):
                return '满铺豁免', j + 1
            if 'LayoutTokens.sheetPanelPadding' in lines[j]:
                # 对话框/半模态披着卡圆角：契约钉的是面板内缩 20（`sheetPanelPadding`），
                # 不是卡面 16，判成混用就是把弹窗当卡（`PrivacyConsentDialog.ets:101`、
                # `BadgeEarnedDialog.ets:78` 两例）。
                return '面板豁免', j + 1
            if 'left' not in lines[j] and 'right' not in lines[j] and '{' in lines[j]:
                # `.padding({ top: xs, bottom: xs })`：只给上下节奏，横向内缩在父级，
                # 不是卡内容内缩。真例：`EditItineraryPage.ets:424` 的拖动态行。
                return '无横向内缩', j + 1
            m = TOKEN_IN.search(lines[j])
            return (m.group(1) if m else '字面量'), j + 1
    return None, None


def scan(path, canonical):
    out = []
    lines = open(path, encoding='utf-8').read().split('\n')
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith('//') or s.startswith('*'):
            continue
        if not CARD_RADIUS.search(line):
            continue
        # 披着卡圆角的**按钮**不是卡：它的左右内缩是控件内边距（如 `TripInputPage.ets:557-561`
        # 那排城市胶囊），按卡面规范档判就是误报。窗口取半径行上下 4 行，够覆盖 Button 的属性链。
        window = '\n'.join(lines[max(0, i - 4):i + 5])
        if '.buttonStyle(' in window or '.type(ButtonType' in window:
            continue
        tok, ln = nearest_padding_token(lines, i)
        if tok is None:
            # 链里没有 padding **不算偏差**：媒体铺满的卡（地图卡、分组容器）本来就没有内容内缩，
            # 内缩由里面的行自己给（真例 `TripMapView.ets:319`、`SpotPickPage.ets:547`、
            # `StayPickPage.ets:513`）。这条与自测同口径，免得"放宽尺子"和"归零"混为一谈。
            pass
        elif tok in ('满铺豁免', '面板豁免', '无横向内缩'):
            pass
        elif tok != canonical:
            out.append((path, i + 1, tok, ln, '与规范档 %s 不一致' % canonical))
    return out


def selftest(canonical):
    bad = 0
    for text, canon, expect_hit, note in SELFTEST:
        lines = text.split('\n')
        hit = False
        for i, line in enumerate(lines):
            if CARD_RADIUS.search(line):
                tok, _ = nearest_padding_token(lines, i)
                hit = (tok is not None and tok not in (canon, '满铺豁免', '面板豁免', '无横向内缩'))
        if hit != expect_hit:
            print('  SELFTEST FAIL %s -> got=%s want=%s' % (note, hit, expect_hit))
            bad += 1
    if bad:
        print('自测 %d 条不过：控制样本没立住时，真跑的 0 命中不算证据' % bad)
        return 1
    print('自测通过：阳性 %d / 阴性 %d' % (sum(1 for x in SELFTEST if x[2]),
                                     sum(1 for x in SELFTEST if not x[2])))
    return 0


def main():
    argv = sys.argv[1:]
    canon = 'base'
    if '--canonical' in argv:
        canon = argv[argv.index('--canonical') + 1]
    if '--selftest' in argv:
        return selftest(canon)
    if selftest(canon) != 0:
        return 1
    hits = []
    for path in sorted(glob.glob('entry/src/main/ets/**/*.ets', recursive=True)):
        hits += scan(path, canon)
    for path, ln, tok, pln, why in hits:
        print('  %-46s L%-5s padding=%s（第 %s 行）%s' % (path, ln, tok, pln, why))
    print('卡面内缩：规范档 %s，混用 %d 处' % (canon, len(hits)))
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
