#!/usr/bin/env python3
"""深色档文字对比度逐屏量化（第四把尺）。

为什么只能量像素：`uitest dumpLayout` 的节点里没有 fontColor / fontSize
（只有 backgroundColor / bounds / text / opacity …），本机也没有 `settings`
命令可以切深色档。所以做法是：给深色档探针下的界面截图，按每个 Text 节点的
bounds 取框，框内取亮度 p95 当字色、p5 当底色，算 WCAG 相对亮度比。

阈值按 WCAG：普通文字 4.5:1，大字号（框高 ≥24css px，本机密度 3.125）3:1。
p95/p5 这类分位数对**稀疏字形**会失效：大字号标题的笔画覆盖率常常不到 5%，
两端都落在背景上，算出来永远是 1:1。所以取法改成：
底色 = 框内亮度中位数（背景必然占多数），字色 = 对侧最极端 2% 的均值
（比背景亮就取最亮 2%，比背景暗就取最暗 2%——浅色档同样适用）。

用法：python3 tools/audit_contrast.py <dump.json> <screenshot.png> [屏名]
退出码 0 = 无低于阈值项；1 = 有。
"""

import json
import sys

from PIL import Image

DENSITY = 3.125          # 测试机 px/vp（见记忆 harmonyos-device-density-3125）
LARGE_CSS_PX = 24.0      # WCAG 大字号门槛（css px）
NORMAL_MIN = 4.5
LARGE_MIN = 3.0


def rel_lum(r, g, b):
    def ch(c):
        s = c / 255.0
        return s / 12.92 if s <= 0.03928 else pow((s + 0.055) / 1.055, 2.4)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def ratio(l1, l2):
    hi = max(l1, l2)
    lo = min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def percentile(sorted_vals, q):
    if not sorted_vals:
        return 0.0
    i = int(round(q * (len(sorted_vals) - 1)))
    return sorted_vals[i]


def tail_mean(sorted_vals, from_top):
    """最极端 2% 的均值（至少 1 个像素）"""
    n = len(sorted_vals)
    if n == 0:
        return 0.0
    # 尾窗只取 0.5%：11px 细字在一个几万样本的大框里，笔画核心常常不足 2%，
    # 取 2% 会连抗锯齿边缘一起平均，把对比度算低（实测「分类支出」2.88 vs 真值 5.4）
    k = max(1, int(n * 0.005))
    seg = sorted_vals[n - k:] if from_top else sorted_vals[:k]
    return sum(seg) / len(seg)


def collect(node, out, layers, seq, anc=()):
    """一次遍历收两样东西：可量的 Text，和所有"遮挡层"（供遮挡判定）。

    seq 是树序（≈绘制序），anc 是这个节点的**祖先 seq 集合**。
    zIndex 非零时 paint 序会偏离树序，所以比较键是 (zIndex, seq) —— 但祖先必须
    无条件排除：dock 的 TabBar 自带 zIndex=3、里面五个标签是 z=0，光比键会判成
    "父在子之后画"，于是把标签整排当成被自己父容器遮住（实测：五个全被吞，
    尺子对刚修好的 dock 直接报 0 问题——假绿）。
    """
    a = node.get('attributes', {})
    txt = (a.get('text', '') or '').strip()
    b = a.get('bounds', '')
    typ = node.get('type', '') or a.get('type', '')
    parts = None
    if b.startswith('['):
        p = [int(x) for x in b.replace('[', ' ').replace(']', ' ').replace(',', ' ').split()]
        parts = p if len(p) == 4 else None
    zraw = a.get('zIndex', '')
    z = int(zraw) if zraw.lstrip('-').isdigit() else 0
    bg = a.get('backgroundColor', '') or ''
    # 遮挡层两类：① 报得出实底的；② **报不出底色的悬浮条** —— dock 走系统材质，
    # dump 里 backgroundColor 是 #00000000、blur 是空，材质根本不在字段里，
    # 只认①就会漏：浅色档行程格「总花费 ¥5,200」压在 dock 下量到 1.12:1，
    # 差点被当成配色 bug。TabBar 这个类型本身就是"浮在内容之上的条"。
    floating = typ == 'TabBar'
    if parts and ((bg.startswith('#FF') and (parts[2] - parts[0]) * (parts[3] - parts[1]) > 0)
                  or floating):
        layers.append((z, seq, parts))
    if txt and typ == 'Text' and parts:
        # 只量真正的 Text 节点：Progress 之类会把自身数值当 text 报上来（如 100.000000），
        # 那不是屏幕上的字，量它没有意义
        out.append((txt, parts, z, seq, anc))
    child_anc = anc + (seq,)
    n = seq + 1
    for c in node.get('children', []) or []:
        n = collect(c, out, layers, n, child_anc)
    return n


def occluded(box, layers, z, seq, anc):
    """有没有**后画的遮挡层**盖住这个框 ≥50%（祖先层不算，见 collect 的注释）。

    为什么必须有这一道：2026-11-01 走查屏5 时，钉底操作条（实底 #FF121212，
    顶边 2166px）把视口外的「适合商务/购物…」「40分钟」两框整块盖住，框内只剩
    jpeg 噪声 —— 明暗差跨过了 0.02、覆盖率也跨过了 1%，于是报出 3.92:1 / 2.32:1
    两个**假**低对比。像素侧的启发式挡不住噪声，遮挡要用节点树判。

    阈值取 50% 而不是 70%：dock 是半透明材质，压住半行字就已经读不出
    （浅色档行程格「总花费 ¥5,200」被 dock 盖住 68%，量到 1.12:1）。
    """
    x1, y1, x2, y2 = box
    area = float((x2 - x1) * (y2 - y1))
    for lz, lseq, lb in layers:
        if lseq in anc:
            continue                      # 祖先：子节点本来就画在它上面
        if (lz, lseq) <= (z, seq):
            continue                      # 先画的在底下，不算遮挡
        w = min(x2, lb[2]) - max(x1, lb[0])
        h = min(y2, lb[3]) - max(y1, lb[1])
        if w > 0 and h > 0 and (w * h) / area >= 0.5:
            return True
    return False


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    dump_path, shot_path = sys.argv[1], sys.argv[2]
    label = sys.argv[3] if len(sys.argv) > 3 else dump_path
    tree = json.load(open(dump_path, encoding='utf-8'))
    img = Image.open(shot_path).convert('RGB')
    W, H = img.size
    px = img.load()
    texts = []
    layers = []
    collect(tree, texts, layers, 0)
    bad = []
    best = {}
    skipped = 0
    covered = 0
    for txt, (x1, y1, x2, y2), z, seq, anc in texts:
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(W, x2), min(H, y2)
        if x2 - x1 < 6 or y2 - y1 < 6:
            continue
        # 先用节点树判遮挡，再动像素：被后画的实底盖住的框里根本没有字形，
        # 采到的只有 jpeg 噪声（屏5 那两个 3.92:1 / 2.32:1 假低对比就是这么来的）
        if occluded((x1, y1, x2, y2), layers, z, seq, anc):
            covered += 1
            continue
        lum = []
        row_diffs = []
        for y in range(y1, y2, 2):
            row = []
            for x in range(x1, x2, 2):
                r, g, b = px[x, y]
                v = rel_lum(r, g, b)
                lum.append(v)
                row.append(v)
            row_diffs.append(row)
        lum.sort()
        l_bg = percentile(lum, 0.5)
        hi = tail_mean(lum, True)
        lo = tail_mean(lum, False)
        # 框内两个方向都没有笔画 → 这个节点没被绘制（被悬浮 dock/弹层盖住，
        # 或列表项在回收区）。属于遮挡，不是配色失败，判为不可判而不是报成低对比
        if max(hi - l_bg, l_bg - lo) < 0.02:
            continue
        # 再加一道**笔画覆盖率**：只靠"有没有明暗差"判不出"那差是不是字形"。
        # 真字形的差异像素占比在 1%~60% 之间；屏5 深色档那次，列表视口外的
        # 「40分钟」框采到的是 dock 圆角边——差异存在，但它是一条边、不是字，
        # 于是报出 2.48:1 的假低对比。覆盖率低于 1% 判"没画字"，高于 60% 判
        # "整块背景边界穿过框"，两者都归不可判而不是配色失败。
        coverage = sum(1 for v in lum if abs(v - l_bg) > 0.06) / float(len(lum))
        # 只按覆盖率还不够：dock 的圆角边横穿一个 140×51 的框，覆盖率也有 ~3%，
        # 但它只占两三行。真字形在竖直方向是**连续铺开**的（一行行都有笔画），
        # 所以再看"有差异的行数占比"——低于 20% 判为一条边/一根线，不是字。
        rows_hit = sum(1 for row in row_diffs
                       if any(abs(v - l_bg) > 0.06 for v in row))
        row_ratio = rows_hit / float(max(1, len(row_diffs)))
        if coverage < 0.01 or coverage > 0.60 or row_ratio < 0.20:
            skipped += 1
            continue
        # 字色取离背景更远的那一侧：深色档是亮侧，浅色档是暗侧
        l_text = hi if (hi - l_bg) >= (l_bg - lo) else lo
        c = ratio(l_text, l_bg)
        large = (y2 - y1) / DENSITY >= LARGE_CSS_PX
        floor = LARGE_MIN if large else NORMAL_MIN
        # 同名节点取「最优实例」：被 dock/弹层压住的框会采到遮挡物，
        # 那是遮挡不是配色失败；只要有一个可见实例读得出，色对就算成立
        key = (txt, floor)
        prev = best.get(key)
        if prev is None or c > prev[0]:
            best[key] = (c, floor, 'large' if large else 'normal', (y2 - y1) / DENSITY, txt)
    for (txt, floor), (c, floor2, kind, hvp, t) in best.items():
        if c < floor:
            bad.append((c, floor, kind, hvp, t))
    bad.sort()
    print('### %-14s 文本节点 %d，低于阈值 %d 处（另有 %d 个框判为未画字/背景边界、%d 个被实底层遮住，均不计）'
          % (label, len(texts), len(bad), skipped, covered))
    for c, floor, kind, hvp, txt in bad[:14]:
        print('    %5.2f:1 (<%.1f, %s, 框高%.0fvp)  %s' % (c, floor, kind, hvp, txt))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
