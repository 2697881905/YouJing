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
  python3 tools/audit_scroll_actions.py            # 全仓（两条硬检查 + 未表态计数）
  python3 tools/audit_scroll_actions.py --probe    # 反证尺子抓得到
  python3 tools/audit_scroll_actions.py --edges    # 第三条：未表态 edgeEffect 的宿主清单 + 反证

退出码 0 = 没有"主操作困在百分比定高滚动区里"、没有裸 Spring 的实例；1 = 有。
第三条（续 238 加的"字段整个没写"）默认只报数：那 12 处要逐处把属性挂到**宿主自己**的链上，
挂错到子级 Column 一样编译通过、只是回弹不生效，必须配装机复拍才能收，见任务 #39。
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
# 第二条检查（2026-11-06 续 206）：回弹必须常开。
# 有据 43 处 `EdgeEffect.Spring` 里 40 处带 `{ alwaysEnabled: true }`，
# 有径此前 14 处只 1 处带——后果是内容不满一屏时有据有橡皮筋、有径拉不动（读起来像卡死）。
SPRING_BARE = re.compile(r'\.edgeEffect\(\s*EdgeEffect\.Spring\s*\)')


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


def scan_spring(name, text):
    """裸 `.edgeEffect(EdgeEffect.Spring)`（缺 alwaysEnabled）逐行抓；注释行不算。"""
    hits = []
    for i, line in enumerate(text.split('\n'), 1):
        s = line.strip()
        if s.startswith('//') or s.startswith('*') or s.startswith('/*'):
            continue
        if SPRING_BARE.search(line):
            hits.append((name, i))
    return hits


# 第三条检查（2026-11-06 续 238）：**根本没表态** edgeEffect 的滚动宿主。
# 前两条抓的都是"值写错了"（百分号定高困住主操作、裸 Spring 缺 alwaysEnabled），
# 这一条抓"字段整个没写"——同一段思路用在第 4 行时才暴露出这类盲区（对表单位应该是调用点）。
# 真值（续 239 用括号配对逐宿主重数，替代此前"文件内声明数减表态数"的粗数）：
# 有据 48 处宿主里 42 处表态（纵向 43 里 38、横向 5 里 4），有径此前 26 处里只有 14 处。
# 续 239 已把缺的 13 处挂满并升成硬闸：属性必须挂在**该宿主自己的属性链**上（挂到子级 Column 上
# 编译照过、行为却是子级没有回弹），所以插入前后都要双向核链；手感复拍仍在任务 #39/#30。
SCROLLABLE = re.compile(r'(?<![A-Za-z0-9_.])(Scroll|List|Grid|WaterFlow)\s*\(')


def call_close_paren(text, open_idx):
    depth = 0
    for j in range(open_idx, len(text)):
        if text[j] == '(':
            depth += 1
        elif text[j] == ')':
            depth -= 1
            if depth == 0:
                return j
    return -1


def scan_missing_edge(name, text):
    hits = []
    for m in SCROLLABLE.finditer(text):
        line = text[:m.start()].split('\n')[-1].strip()
        if line.startswith('//') or line.startswith('*'):
            continue
        op = text.index('(', m.start())
        close = call_close_paren(text, op)
        if close < 0:
            continue
        brace = text.find('{', close)
        if brace < 0:
            continue
        body, end = match_block(text, brace)
        if '.edgeEffect(' not in chain_after(text, end):
            hits.append((name, text[:m.start()].count('\n') + 1, m.group(1)))
    return hits


def probe_missing_edge():
    """一正一负：没表态的必须报，表态挂在宿主自己链上的必须不报。"""
    missing = "  demo() {\n    List() {\n      ListItem() { Text('a') }\n    }\n    .width('100%')\n  }\n"
    present = "  demo() {\n    List() {\n      ListItem() { Text('a') }\n    }\n    .width('100%')\n" \
              "    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })\n  }\n"
    wrong_host = "  demo() {\n    Column() {\n      List() {\n        ListItem() { Text('a') }\n      }\n" \
                 "      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })\n    }\n  }\n"
    a = bool(scan_missing_edge('m.ets', missing))
    b = bool(scan_missing_edge('p.ets', present))
    c = len(scan_missing_edge('w.ets', wrong_host))
    ok = a and not b and c == 0
    print('  反证：未表态抓到=%s 已表态不报=%s 挂对宿主不误报=%s' % (a, not b, c == 0))
    return 0 if ok else 1


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
    spring_bad = scan_spring('sb.ets', "    List()\n    .edgeEffect(EdgeEffect.Spring)\n")
    spring_ok = scan_spring('sg.ets',
                            "    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })\n")
    spring_doc = scan_spring('sd.ets', "  // 这里以前写 .edgeEffect(EdgeEffect.Spring) 裸形\n")
    if not spring_bad:
        print('PROBE FAILED: 注入的裸 EdgeEffect.Spring 没被抓到')
        ok = False
    if spring_ok or spring_doc:
        print('PROBE FAILED: 已带 alwaysEnabled 的或注释里的 Spring 被误报')
        ok = False
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
        print('probe ok: 阳性抓到、阴性不报、162 行外的主操作也抓到、裸 Spring 抓到而带 alwaysEnabled/注释不报。')
    return 0 if ok else 1


def main():
    if '--probe' in sys.argv:
        return probe()
    if '--edges' in sys.argv:
        if probe_missing_edge() != 0:
            return 1
        n = 0
        for dirpath, _dirs, files in os.walk(SRC):
            for fn in sorted(files):
                if not fn.endswith('.ets'):
                    continue
                path = os.path.join(dirpath, fn)
                with open(path, encoding='utf-8') as fh:
                    text = fh.read()
                for _n, line_no, tag in scan_missing_edge(fn, text):
                    print('%s:%d  %s 没表态 edgeEffect（有据同宿主 1:1 带 Spring）'
                          % (os.path.relpath(path, ROOT), line_no, tag))
                    n += 1
        print('未表态滚动宿主 %d 处（0 处为合格；本条自续 239 起已进硬闸，跑全仓时计入 total）' % n)
        return 0
    total = 0
    missing_edges = 0
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
            for name, line_no in scan_spring(fn, text):
                rel = os.path.relpath(path, ROOT)
                print('%s:%d  EdgeEffect.Spring 裸形（缺 alwaysEnabled，内容不满一屏时拉不动）'
                      % (rel, line_no))
                total += 1
            missing_edges += len(scan_missing_edge(fn, text))
    total += missing_edges
    if missing_edges:
        print('\n%d 处滚动宿主没表态 edgeEffect（`--edges` 出清单）：有据 48 处宿主里 42 处带'
              '（含横向 5 里带 4），没表态就是内容不满一屏时拉不动、读起来像卡死。' % missing_edges)
    if total == 0:
        print('scroll-action: 没有主操作困在百分比定高的滚动区里，回弹全部常开，'
              '且 26 处滚动宿主全部表态 edgeEffect (pass)')
        return 0
    print('\n%d 处。主操作困住→移出滚动区 + 确定上限（§5ci 续 15/17）；'
          '裸 Spring→补 { alwaysEnabled: true }（§5ci 续 206）。' % total)
    return 1


if __name__ == '__main__':
    sys.exit(main())
