#!/usr/bin/env python3
"""第 19 把静态尺：顶部/底部避让量只能有一个来源。

R1 禁止把 `statusBarHeight` / `navIndicatorHeight` / `navBarHeight` 直接写进
   padding / margin / height 表达式——必须走 navMode 发布的键。
   阳性对照是 2026-11-05 真机抓到的那条 `pages/Index` `.padding({ top: this.statusBarHeight })`：
   壳层避让 + 栏体避让 = 同一件事写两遍，后果是状态栏带子拿不到栏体的沉浸遮罩，
   滚动时出现「带子 L=18 / 栏体 L=11」的硬台阶。
R2 dock 边距必须读 `bottomNavInsetVp`，禁止再写 `+ this.navIndicatorHeight` 这类只看高度的自算
   （手势条 27.9vp 与三键栏 27.8vp 只看高度判不开）。

用法：python3 tools/audit_inset_source.py [--selftest]
"""
import glob
import re
import sys

EXEMPT = ('utils/navMode.ets', 'utils/navInset.ets', 'entryability/EntryAbility.ets')
R1 = re.compile(r'\.(padding|margin|height)\s*\([^)]*\b(statusBarHeight|navIndicatorHeight|navBarHeight)\b')
R2 = re.compile(r'navIndicatorHeight')
KEY_READ = 'dockNavInset'

SELFTEST = [
    ('pages/Index.ets', ".padding({ top: this.statusBarHeight })", 'R1', '壳层重复避让（今晚的真缺陷）'),
    ('pages/Index.ets', "barBottomMargin: LayoutTokens.floatingDockBottomMargin + this.navIndicatorHeight,", 'R2', 'dock 只看高度自算'),
    ('pages/Index.ets', "@StorageLink(BOTTOM_NAV_INSET_KEY) dockNavInset: number = 0;", None, '走单源键'),
    ('pages/Index.ets', "barBottomMargin: LayoutTokens.floatingDockBottomMargin + this.dockNavInset,", None, '派生自单源键'),
    ('utils/navMode.ets', "AppStorage.setOrCreate('navBarHeight', heightVp);", None, '发布点豁免'),
    ('pages/MapPage.ets', ".height(this.statusBarHeight)", 'R1', '任意页面自算顶部避让'),
]


def classify(path, line):
    if any(path.endswith(e) for e in EXEMPT):
        return None
    if line.strip().startswith('//') or line.strip().startswith('*'):
        return None
    if R1.search(line):
        return 'R1'
    if R2.search(line) and KEY_READ not in line:
        return 'R2'
    return None


def selftest():
    bad = 0
    for path, frag, want, note in SELFTEST:
        got = classify(path, frag)
        if got != want:
            print('  SELFTEST FAIL %s -> got=%s want=%s' % (note, got, want))
            bad += 1
    pos = sum(1 for x in SELFTEST if x[2])
    neg = len(SELFTEST) - pos
    if bad:
        print('自测 %d 条不过：控制样本没立住时，真跑的 0 命中不算证据' % bad)
        return 1
    print('自测通过：阳性 %d / 阴性 %d' % (pos, neg))
    return 0


def main():
    if '--selftest' in sys.argv:
        return selftest()
    if selftest() != 0:
        return 1
    hits = []
    for path in sorted(glob.glob('entry/src/main/ets/**/*.ets', recursive=True)):
        for i, line in enumerate(open(path, encoding='utf-8').read().split('\n'), 1):
            rule = classify(path, line)
            if rule:
                hits.append((rule, path, i, line.strip()))
    for rule, path, i, text in hits:
        print('  %-3s %s:%d  %s' % (rule, path, i, text[:96]))
    print('避让量来源：偏差 %d 项（R1 顶部/底部不得自算，R2 dock 必须读单源键）' % len(hits))
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
