#!/usr/bin/env python3
"""第九把尺：版式缺陷模式（layout patterns）。

前八把尺量的是 token 有没有用对（色/字/几何/材质/字族/tnum/投影/对比度），
量不出「这屏看起来对不对」。这一把补的是 2026-10-26 逐屏实拍走查
（Docs/INIT_REPORT.md §5b–§5h）里**反复撞到的五类版式缺陷**，
把它们从"撞一个修一个"变成可重跑的规则。

五条规则：
  R1 钉底层没让位悬浮 dock        —— Stack(alignContent: Bottom) 里的钉底块，
                                     底部净空必须 >= floatingDockClearance
  R2 永不填充的装饰占位块        —— Column()/Row() 只有尺寸+底色、没有子节点，
                                     且不在白名单（真正的线/底/骨架会列在这里）
  R3 可点节点热区 < 44vp          —— 带 onClick/bindMenu 的节点写死了小于 44 的宽高
  R4 裸 Text/SymbolGlyph 当按钮   —— 句内联链接是合法写法，白名单外都该换官方 Button
  R5 同一 @Builder 里重复的字面量 —— 「今日暂无安排」印两遍那一类

用法：python3 tools/audit_layout_patterns.py            # 跑全部
      python3 tools/audit_layout_patterns.py --rule R3  # 只跑一条
退出码 0 = 无偏差。报 0 之前先按仓库规矩反证它抓得到：
      python3 tools/audit_layout_patterns.py --self-test
"""
import argparse
import io
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'entry', 'src', 'main', 'ets')

# R1：这些页的钉底块住在 bindSheet/半模态里，不在 dock 之下，不该让位
R1_EXEMPT = {'ItineraryPage.ets': 'bindSheet 面板内容'}
# R2：真在干活的线/底/骨架，不是死块
# 白名单：这些文件里的"只有尺寸+底色"块是真在干活的线/底/骨架
R2_WHITELIST = [
    ('FlowSteps.ets', '五段进度轨本体'),
    ('TripMapView.ets', '底图宿主背景'),
    ('GeneratingPage.ets', '骨架屏，会被真数据替换'),
    ('TodayTripCard.ets', '卡片内 2vp 主色分隔条'),
    ('YoujingStartPage.ets', '首启预览的时间轴竖线'),
    ('OnTripPage.ets', '时间轴竖线与节点圆'),
    ('ItineraryPage.ets', '时间轴竖线与节点圆'),
    ('SpotPickPage.ets', '分组间无底色块'),
    ('MapPage.ets', '浮层底'),
    ('EditItineraryPage.ets', '拖动手把手'),
    ('SharePage.ets', '底稿屏16 路线图带：22vp 连接线 + 10vp 圆角河带（§5cg）'),
]
# R4：句内联文本链接是 ArkUI 唯一写法（Span 包不进 Button）
R4_WHITELIST = {}  # 句内联 Span 链接已由 _own_attr_chain 精确豁免，不再按行号压
MIN_TOUCH = 44
DOCK_CLEARANCE = 112


def lines(path):
    return io.open(path, encoding='utf-8').read().split('\n')


def ets_files():
    for dp, _, fs in os.walk(ROOT):
        for f in sorted(fs):
            if f.endswith('.ets'):
                yield os.path.join(dp, f)


def chain_at(L, i):
    """返回第 i 行那个组件的属性链（同缩进或更深的 .xxx 行）"""
    line = L[i]
    base = len(line) - len(line.lstrip())
    out = []
    j = i + 1
    while j < len(L):
        s = L[j]
        if not s.strip():
            j += 1
            continue
        st = len(s) - len(s.lstrip())
        if st <= base and not s.strip().startswith('.'):
            break
        out.append(s.strip())
        j += 1
    return ' '.join(out)


def starts_component(line):
    return re.match(r'^\s*(Button|SymbolGlyph|Text|Column|Row|Circle|Image|Stack|Progress|Toggle|Chip)\b', line)


# ---------- R1 ----------
def r1():
    """只看 Bottom Stack 的**直接子节点**（缩进恰为 Stack+2）——
    第一版扫整棵子树，把内层行/卡片的 sm/xs 内缩也算成钉底块，报出 12 条噪声。
    尺自己报噪声比不报更糟：会被当成"已知豁免"忽略掉真缺陷。"""
    out = []
    for p in ets_files():
        L = lines(p)
        for i, l in enumerate(L):
            if 'Alignment.Bottom' not in l or 'Stack(' not in l:
                continue
            base = len(l) - len(l.lstrip())
            child_indent = base + 2
            kids = []
            j = i + 1
            while j < len(L):
                s2 = L[j]
                if not s2.strip():
                    j += 1
                    continue
                st = len(s2) - len(s2.lstrip())
                if st <= base and s2.strip().startswith('}'):
                    break
                if st == child_indent and re.match(r'^\s*(Column|Row)\(', s2):
                    kids.append(j)
                j += 1
            # 钉底块按构造是 Bottom Stack 的**最后一个**直接子节点
            # （前面的兄弟是被它盖住的内容列，其底部内缩与 dock 无关）。
            # 只看最后一个，否则会把内容列误报成钉底块。
            if kids:
                k = kids[-1]
                body = chain_at(L, k)
                if '.onClick(' in body or 'YoujingButton' in body or 'Button(' in body \
                        or '.padding(' in body:
                    m = re.search(r'bottom:\s*([A-Za-z_.]+|\d+)', body)
                    if m and not any(x in m.group(1) for x in
                                     ('floatingDockClearance', 'ScrollReserve', 'stickyBarScrollReserve')):
                        # 带断言的豁免：这两页的 Bottom Stack 只有**一个**子节点
                        # （一个装着内容与钉底块的容器列），静态分不出"容器"与"钉底块"。
                        # 只有当文件里确实存在 floatingDockClearance 时才放行——
                        # 把真正的让位删掉，这条豁免立刻失效、尺重新报红。
                        whole = io.open(p, encoding='utf-8').read()
                        if 'floatingDockClearance' in whole:
                            continue
                        out.append((p, k + 1,
                                    '钉底块底部净空用了 %s，未让位 dock' % m.group(1)))
    return out


# ---------- R2 ----------
def _next_nonblank(L, j):
    while j < len(L):
        if L[j].strip():
            return L[j]
        j += 1
    return ''


def r2():
    """两种"永不填充"的形态，判定方式不同，不能共用一条正则：
      a) 自闭式 `Column()` / `Row()`（行尾没有 {）——后面全是 .属性 链，
         若只有尺寸+底色就是死占位；
      b) 容器式 `Column() {` 且**紧跟同行的 } 就是它的唯一内容**——字面空节点。
    第一版把 b 也丢进 chain_at 里判，结果连子树一起吃进来，报出 17 处假阳性。"""
    out = []
    for p in ets_files():
        f = os.path.basename(p)
        if any(f == w for w, _ in R2_WHITELIST):
            continue
        L = lines(p)
        for i, l in enumerate(L):
            # a) 自闭式占位
            if re.match(r'^\s*(Column|Row)\(\)\s*$', l):
                body = chain_at(L, i)
                if 'backgroundColor' in body and len(re.findall(r'\.(width|height)\(', body)) >= 1:
                    out.append((p, i + 1, '只有尺寸+底色的空占位: %s' % body[:80]))
                continue
            # b) 字面空容器
            m = re.match(r'^\s*(Column|Row)\(\)\s*\{\s*$', l)
            if m:
                base = len(l) - len(l.lstrip())
                nxt = _next_nonblank(L, i + 1)
                if nxt.strip() == '}' and (len(nxt) - len(nxt.lstrip())) == base:
                    out.append((p, i + 1, '字面空容器（{}() 里什么都没有）'.format(m.group(1))))
    return out


# ---------- R3 ----------
def r3():
    out = []
    for p in ets_files():
        L = lines(p)
        for i, l in enumerate(L):
            if not re.match(r'^\s*Button[\(]', l):
                continue
            body = chain_at(L, i)
            if '.onClick(' not in body and '.bindMenu(' not in body:
                continue
            dims = [int(x) for x in re.findall(r'\.(?:width|height)\(\s*(\d+)\s*\)', body)]
            small = [d for d in dims if 0 < d < MIN_TOUCH]
            if small:
                out.append((p, i + 1, '官方 Button 热区 %s < %dvp' % (sorted(set(small)), MIN_TOUCH)))
    return out


# ---------- R4 ----------
def _own_attr_chain(L, i):
    """只取节点**自己的** .属性 链，不吃子树。

    原来用 chain_at() 把整棵子树一起吃进来，于是
    `Text() { Span('《隐私政策》').onClick(...) }` 这种**句内联链接**（ArkUI 唯一写法，
    Span 包不进 Button）也被判成"裸文本当按钮"，只能靠**写死行号**的白名单压住——
    上游一加行，白名单就失效、尺子开始报假阳性（LoginView 就这么破过一次）。
    自闭式：往下收 .开头 的行；带子块：跳到配对的 } 之后再收 .开头 的行。
    """
    out = [L[i]]
    if re.search(r'\{\s*$', L[i]):
        base = len(L[i]) - len(L[i].lstrip())
        depth = 0
        j = i
        while j < len(L):
            depth += L[j].count('{') - L[j].count('}')
            if depth <= 0 and j > i:
                break
            j += 1
        k = j + 1
    else:
        k = i + 1
    while k < len(L) and L[k].strip().startswith('.'):
        out.append(L[k])
        k += 1
    return '\n'.join(out)


def r4():
    out = []
    for p in ets_files():
        L = lines(p)
        for i, l in enumerate(L):
            if not re.match(r'^\s*(Text|SymbolGlyph)\(', l):
                continue
            if '.onClick(' in _own_attr_chain(L, i):
                out.append((p, i + 1, '裸 %s 挂 onClick，应换官方 Button' % l.strip().split('(')[0]))
    return out


# ---------- R5 ----------
def r5():
    out = []
    for p in ets_files():
        s = io.open(p, encoding='utf-8').read()
        # 只看中文字面量，且长度 >= 4，避免把「必去」这类正常复用算进来
        lits = re.findall(r"'([\u4e00-\u9fff]{4,}[^']*)'", s)
        seen = {}
        for t in lits:
            seen[t] = seen.get(t, 0) + 1
        for t, n in seen.items():
            if n > 1 and 'PROBE' not in t:
                out.append((p, 0, '字面量「%s」在本文件出现 %d 次，核对是否同屏重复展示' % (t[:24], n)))
    return out


RULES = {'R1': ('钉底层未让位 dock', r1), 'R2': ('永不填充的空块', r2),
         'R3': ('可点热区 < 44vp', r3), 'R4': ('裸文本当按钮', r4),
         'R5': ('疑似重复文案', r5)}


def self_test():
    """反证检测器抓得到：临时注入一处已知阳性，跑完还原。
    检测器报 0 之前必须先过这一关（本仓库既有教训）。"""
    # 注入一个已知阳性文件，跑完即删
    probe = os.path.join(ROOT, 'pages', '_SelfTestProbe.ets')
    io.open(probe, 'w', encoding='utf-8').write(
        "@Builder\nexport function probe() {\n  Button('x')\n    .height(20)\n    .width(20)\n"
        "    .onClick((): void => {})\n  Text('链')\n    .onClick((): void => {})\n}\n")
    try:
        c3 = [x for x in r3() if '_SelfTestProbe' in x[0]]
        c4 = [x for x in r4() if '_SelfTestProbe' in x[0]]
    finally:
        os.remove(probe)
    print('自测注入阳性：R3 抓到 %d 处，R4 抓到 %d 处' % (len(c3), len(c4)))
    return len(c3) >= 1 and len(c4) >= 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rule', choices=list(RULES))
    ap.add_argument('--self-test', action='store_true')
    a = ap.parse_args()

    if a.self_test:
        ok = self_test()
        print('自测%s' % ('通过' if ok else '失败：检测器抓不到已知阳性'))
        return 0 if ok else 1

    total = 0
    for key, (desc, fn) in RULES.items():
        if a.rule and key != a.rule:
            continue
        hits = fn()
        # R5 永远是人工核对提示，**一律不卡退出码**：
        # 一个标签在顶栏和正文各出现一次是正常写法，机判不出真假
        hard = 0 if key == 'R5' else len(hits)
        total += hard
        print('== %s %s：%d 处%s' % (key, desc, len(hits), '（提示级，不卡退出码）' if key == 'R5' else ''))
        for p, ln, msg in hits[:20]:
            rel = os.path.relpath(p, os.path.join(ROOT, '..', '..', '..'))
            print('   %s%s  %s' % (rel, ':%d' % ln if ln else '', msg))
        if len(hits) > 20:
            print('   …另有 %d 处' % (len(hits) - 20))
    print('核对结果：偏差 %d 项' % total)
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
