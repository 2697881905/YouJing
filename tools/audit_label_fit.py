#!/usr/bin/env python3
r"""定宽按钮的文案装不装得下（可算出来的截断，不用等真机）。

来历：这一整轮反复出现的「排版交错」里有一类是**文字被容器截断**
（屏5b 三行 meta、屏16 半屏空洞旁的空占位、屏11b 那一排圆钮被切 8vp）。
之前都是实拍一屏一屏查，其实**按钮宽度是写死的、文案是固定的**，
两者一比就知道会不会截断——不需要设备。

口径（两条都要成立才算违规，宁缺勿滥）：
- ① 容器给了**确定宽度**：`buttonWidth: N`（vp）紧跟一个 `label: '…'`；
  或 `YoujingButton({ variant: …, label: '…' })` 之外没有 `fullWidth: true`。
  `fullWidth` 的按钮不吃定宽，跳过。
- ② 需求宽度按字形估：CJK 一字 ≈ 1×字号、拉丁 ≈ 0.55×字号，再加容器左右内边距 32vp
  （契约 pill 内边距档）。字号按按钮档位取 16fp。
  这是**下界估计**：真机中文更宽一点、还可能有图标，所以命中即真有问题，未命中不保证没事。

用法：
  python3 tools/audit_label_fit.py            # 全仓
  python3 tools/audit_label_fit.py --probe    # 反证尺子抓得到已知阳性

退出码 0 = 没有"定宽容器放不下自身文案"的实例；1 = 有。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')

FONT_VP = 16.0
PADDING_VP = 32.0
PAIR = re.compile(r"buttonWidth:\s*(\d+)[\s\S]{0,220}?label:\s*'([^']+)'")
CALL = re.compile(r"YoujingButton\(\{")
FULLWIDTH_NEAR = re.compile(r"fullWidth:\s*true")


def block_after(text, open_idx):
    """取 `YoujingButton({ … })` 这一整段实参文本（括号配对，不猜字段顺序）。"""
    depth = 0
    for j in range(open_idx, len(text)):
        c = text[j]
        if c in '({':
            depth += 1
        elif c in ')}':
            depth -= 1
            if depth == 0:
                return text[open_idx:j + 1], j
    return text[open_idx:], len(text)


def scan_text(name, text):
    """按实参块解析：同一块里同时拿到 label 与 buttonWidth 才判，字段顺序无关。

    第一版按 `buttonWidth: N … label: '…'` 的**固定顺序**配对，结果 17 个定宽按钮
    只配上 4 个——因为仓库里多数写法是 `label` 在 `buttonWidth` 之前。
    那次的 "pass" 其实是覆盖面漏洞，不是干净。
    """
    hits = []
    pos = 0
    while True:
        m = CALL.search(text, pos)
        if not m:
            break
        blk, end = block_after(text, m.end() - 1)
        pos = end + 1
        lm = re.search(r"label:\s*'([^']+)'", blk)
        wm = re.search(r"buttonWidth:\s*(\d+)", blk)
        if not lm or not wm:
            continue                                  # 没定宽（fullWidth/自适应）不判
        if FULLWIDTH_NEAR.search(blk):
            continue
        # TEXT 档按钮（ButtonStyleMode.TEXT / variant: TEXT）不画胶囊底、不吃那 32vp 内边距，
        # 按胶囊模型估会造出假阳性——真机实测「不去下一站」文本 80vp、按钮给 108vp，
        #  orig == bounds 完全没截断，我却照尺子把宽度改到 124。这类按钮一律不判。
        if re.search(r"variant:\s*YoujingButtonVariant\.TEXT", blk) or \
           re.search(r"buttonStyle:\s*ButtonStyleMode\.TEXT", blk):
            continue
        label = lm.group(1)
        if len(label) <= 2:
            continue
        allotted = int(wm.group(1))
        need = needed_vp(label)
        if need > allotted:
            hits.append((name, text[:m.start()].count('\n') + 1, label, allotted, need))
    return hits


def cjk_count(text):
    return sum(1 for c in text if '\u4e00' <= c <= '\u9fff')


def needed_vp(label, font=FONT_VP, pad=PADDING_VP):
    cjk = cjk_count(label)
    latin = len(label) - cjk
    return round(cjk * font + latin * font * 0.55 + pad, 1)


def probe():
    """两种字段顺序都要抓到；放得下的不误报。

    第二例是仓库里的常见写法（`label` 在 `buttonWidth` 之前）——
    第一版尺子正因为只认前一种顺序，17 个定宽按钮只判了 4 个就报 pass。
    """
    cases = [
        ('width-then-label 阳性',
         "YoujingButton({ buttonWidth: 72, label: '继续未完成的规划' })", True),
        ('label-then-width 阳性',
         "YoujingButton({ label: '继续未完成的规划', buttonWidth: 72 })", True),
        ('放得下的阴性',
         "YoujingButton({ label: '换一个时间', buttonWidth: 160 })", False),
        ('fullWidth 不判',
         "YoujingButton({ label: '继续未完成的规划', fullWidth: true })", False),
    ]
    for desc, src, should_hit in cases:
        hits = scan_text('probe.ets', src)
        if bool(hits) != should_hit:
            print('PROBE FAILED [%s]: 期望 %s，实得 %s — 读数不可信' % (desc, should_hit, hits))
            return 1
        print('probe ok: %s %s' % (desc, ('抓到' if hits else '不报')))
    return 0


def main():
    if '--probe' in sys.argv:
        return probe()
    total = 0
    for dirpath, _dirs, files in os.walk(SRC):
        for fn in sorted(files):
            if not fn.endswith('.ets'):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, encoding='utf-8') as fh:
                text = fh.read()
            for _name, line_no, label, allotted, need in scan_text(fn, text):
                print('%s:%d  定宽 %dvp 放不下 label「%s」（约需 %svp）'
                      % (os.path.relpath(path, ROOT), line_no, allotted, label, need))
                total += 1
    if total == 0:
        print('label-fit: 没有定宽容器放不下自身文案的实例 (pass)')
        return 0
    print('\n%d 处。宽度是写死的、文案是固定的，这条不需要真机就该修。' % total)
    return 1


if __name__ == '__main__':
    sys.exit(main())
