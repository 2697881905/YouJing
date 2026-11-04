#!/usr/bin/env python3
"""第 18 把静态尺：行程长度只能有一个来源。

2026-11-05 真机拍到两类同根问题——同一个事实由多处各自推导：
  R1 `DateUtils.spanDays(<草稿日期对>)` 直接算天数。草稿日期默认是空串（占位语义有
     hypium 用例钉着），`spanDays('', '')` 取到 1，而屏2 显示的是「今天起算 3 天」，
     于是屏2 写 3天2晚、屏5 只给 4 个名额。唯一口径是 `PlanDraft.days(basic)`。
  R2 手写 `${days}天${days - 1}晚`。单日行程被端成「1天0晚」——那是减法的结果。
     唯一口径是 `TripSpan.text(days)`。

两条都只判"从草稿/数组长度各自推导"的写法，不判纯函数内部实现
（`PlanDraft.days` 里那次 `spanDays`、`TripSpan.text` 里那次减法正是它们自己）。

用法：
  python3 tools/audit_span_source.py            # 扫 entry/src/main/ets
  python3 tools/audit_span_source.py --selftest # 阳性/阴性控制样本，任一不过即退出码 1
"""

import re
import sys
from pathlib import Path

SRC_ROOT = Path('entry/src/main/ets')

# R1：spanDays 的实参看起来来自草稿日期对（而不是页面 state 或字面量日期）
R1_RE = re.compile(r'spanDays\(\s*(?:b|basic|draft\.basic|params\.basic)\.startDate')
# R2：手写「N天N-1晚」
R2_RE = re.compile(r'\}\s*天\s*\$\{[^{}]*- 1\}晚')

# 承载"唯一口径"的两个函数自身，允许出现推导式写法
OWNERS = ('data/PlanDraft.ets', 'utils/TripSpan.ets', 'utils/TripLength.ets')

SELFTEST = [
    # (归属文件, 片段, 期望命中规则, 说明)
    ('pages/SpotPickPage.ets', "this.days = DateUtils.spanDays(b.startDate, b.endDate);", 'R1', '屏5 从草稿直接算天数'),
    ('pages/GeneratingPage.ets', "const days = DateUtils.spanDays(basic.startDate, basic.endDate);", 'R1', '屏7 从草稿直接算天数'),
    ('pages/TripInputPage.ets', "Text(`${this.dayCount()}天${this.dayCount() - 1}晚`)", 'R2', '手写天数晚数'),
    ('pages/SharePage.ets', "`行程 ${trip.days.length}天${trip.days.length - 1}晚`", 'R2', '分享页手写'),
    ('pages/SpotPickPage.ets', "this.days = PlanDraft.days(b);", None, '走唯一口径'),
    ('pages/TripInputPage.ets', "return DateUtils.spanDays(this.startDate, this.endDate);", None, '页面 state 自己的日期对'),
    ('test/X.test.ets', 'expect(DateUtils.spanDays("2026-06-11", "2026-06-15")).assertEqual(5);', None, '字面量日期对（测试）'),
    ('utils/TripSpan.ets', "return d > 1 ? `${d}天${d - 1}晚` : '1天';", None, '唯一口径自身（按文件排除）'),
    ('data/PlanDraft.ets', "return DateUtils.spanDays(b.startDate, b.endDate);", None, '唯一口径自身（按文件排除）'),
]


def classify(path: str, line: str):
    """与 scan 同一条判定链：先按文件排除唯一口径自身，再判两条规则。"""
    if any(path.endswith(o) for o in OWNERS):
        return None
    if R1_RE.search(line):
        return 'R1'
    if R2_RE.search(line):
        return 'R2'
    return None


def scan(root: Path):
    hits = []
    for path in sorted(root.rglob('*.ets')):
        rel = str(path)
        if any(rel.endswith(o) for o in OWNERS):
            continue
        text = path.read_text(encoding='utf-8')
        for i, line in enumerate(text.split('\n'), 1):
            stripped = line.strip()
            if stripped.startswith('//') or stripped.startswith('*'):
                continue
            rule = classify(rel, line)
            if rule and not stripped.startswith('//'):
                hits.append((rel, i, rule, stripped))
    return hits


def selftest() -> int:
    failed = 0
    for owner, frag, want, note in SELFTEST:
        got = classify(owner, frag)
        if got != want:
            print('  SELFTEST FAIL %s → got=%s want=%s' % (note, got, want))
            failed += 1
    if failed:
        print('自测 %d 条不过（阳性 %d / 阴性 %d 的控制样本必须先立住，否则真跑的 0 命中不算证据）'
              % (failed, sum(1 for x in SELFTEST if x[2]), sum(1 for x in SELFTEST if not x[2])))
        return 1
    print('自测通过：阳性 %d / 阴性 %d' % (
        sum(1 for x in SELFTEST if x[2]), sum(1 for x in SELFTEST if not x[2])))
    return 0


def main() -> int:
    if '--selftest' in sys.argv:
        return selftest()
    if selftest() != 0:
        return 1
    hits = scan(SRC_ROOT)
    for rel, line, rule, text in hits:
        print('  %-4s %s:%d  %s' % (rule, rel, line, text[:96]))
    print('行程长度来源：偏差 %d 项（R1 天数唯一口径 PlanDraft.days / R2 文案唯一口径 TripSpan.text）' % len(hits))
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
