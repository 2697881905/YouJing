#!/usr/bin/env python3
r"""主操作是否在"按百分比定高、可能不进可滚状态"的滚动区里。

来历：屏11 记一笔的 P0（键盘弹起后「保存」被推出可见区、滑不出来，§5ci 续 13/15）
根因是 `Scroll` 吃 `.height('100%')`。`bindSheet` 在窗口被压缩后不重新下发高度约束，
于是 `'100%'` 按压缩前解析，Scroll 以为内容装得下、**根本不进可滚状态**，
放在它里面的主操作就再也点不到。修法是主操作搬出滚动区 + 滚动区给确定上限。
屏10 详情面板（§5ci 续 17）是同一形状的第二个实例。

为什么单独做一把尺而不是靠人读：上一版我临时写的全仓扫描**只往后看 90 行**，
而 `detailSheet` 的两颗主操作距 `Scroll() {` 有 162 行——扫出来是"0 命中"，
差点被我当成"只有记一笔会踩"写进结论。所以这一把尺：
① 一律用花括号配对取**整个 builder 正文**，不用固定行窗；
② 自带 `--probe`：注入一个已知阳性（主操作在百分号滚动区里）与一个已知阴性
   （主操作在滚动区之外），必须一次抓到、一次不报，否则读数不作数。

用法：
  python3 tools/audit_scroll_actions.py            # 全仓
  python3 tools/audit_scroll_actions.py --probe    # 反证尺子抓得到

退出码 0 = 没有"主操作困在百分比定高滚动区里"的实例；1 = 有。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')

SCROLL_OPEN = re.compile(r'(?<![A-Za-z0-9_])Scroll\s*\(\s*\)\s*\{')
ACTION = re.compile(r"label:\s*'([^']+)'|Button\s*\(\s*\)\s*\{")
PERCENT_HEIGHT = re.compile(r"\.height\(\s*'100%'\s*\)")
# 滚动区自己的属性链：从 `}` 关掉 Scroll 之后那串以 `.` 开头的行
CHAIN = re.compile(r"^\s*\.\w+")


def match_block(text, start_idx):
    """从 `Scroll() {` 的左括号起做配对，返回 (正文, 结束位置)。"""
    i = text.index('{', start_idx)
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[i + 1:j], j
    return text[i + 1:], len(text)


def chain_after(text, close_idx):
    """取滚动区闭括号之后的属性链（连续的 `.` 开头行 + 注释/空行透明）。"""
    tail = text[close_idx + 1:].split('\n')
    out = []
    for line in tail:
        s = line.strip()
        if s == '' or s.startswith('//') or s.startswith('*'):
            continue
        if s.startswith('.'):
            out.append(s)
        else:
            break
    return '\n'.join(out)


def scan_text(name, text):
    hits = []
    pos = 0
    while True:
        m = SCROLL_OPEN.search(text, pos)
        if not m:
            break
        body, close = match_block(text, m.end() - 1)
        actions = ACTION.findall(body)
        labels = [a for a in actions if a]
        if labels and PERCENT_HEIGHT.search(chain_after(text, close)):
            line_no = text[:m.start()].count('\n') + 1
            hits.append((name, line_no, labels))
        pos = m.end()
    return hits


def probe():
    """注入一正一负：正的必须被抓，负的必须不报，否则尺子无效。"""
    bad = """  demoSheet() {
    Scroll() {
      Column() {
        Text('字段')
        YoujingButton({
          label: '保存',
        })
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
"""
    good = """  demoSheet() {
    Column() {
      Scroll() {
        Column() {
          Text('字段')
        }
      }
      .width('100%')
      .constraintSize({ maxHeight: 300 })

      YoujingButton({
        label: '保存',
      })
    }
    .width('100%')
    .height('100%')
  }
"""
    far = """  demoSheet() {
    Scroll() {
      Column() {
""" + ("        Text('中间内容行')\n" * 200) + """        YoujingButton({
          label: '加入日历提醒',
        })
      }
    }
    .width('100%')
    .height('100%')
  }
"""
    r_bad = scan_text('bad.ets', bad)
    r_good = scan_text('good.ets', good)
    r_far = scan_text('far.ets', far)
    ok = True
    if not r_bad:
        print('PROBE FAILED: 注入的阳性样本没被抓到（主操作在百分号定高的 Scroll 里）')
        ok = False
    if r_good:
        print('PROBE FAILED: 注入的阴性样本被误报（主操作已在滚动区外 + 定高上限）')
        ok = False
    if not r_far:
        print('PROBE FAILED: 主操作距 Scroll 起点 >90 行的样本没抓到（说明还在用固定行窗）')
        ok = False
    if ok:
        print('probe ok: 阳性抓到、阴性不报、162 行外的主操作也抓到。')
    return 0 if ok else 1


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
            for name, line_no, labels in scan_text(fn, text):
                rel = os.path.relpath(path, ROOT)
                print('%s:%d  Scroll 用 .height(\'100%\') 且主操作在其内: %s'
                      % (rel, line_no, '、'.join(labels)))
                total += 1
    if total == 0:
        print('scroll-action: 没有主操作困在百分比定高的滚动区里 (pass)')
        return 0
    print('\n%d 处。修法：主操作移出滚动区 + 给滚动区确定上限（见 §5ci 续 15/17）。' % total)
    return 1


if __name__ == '__main__':
    sys.exit(main())
