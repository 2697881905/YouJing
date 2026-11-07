#!/usr/bin/env python3
"""逐屏结构巡检：用 App 自带的 `--ps route` 深链把每个页面直接拉起来，
dumpLayout 读真树，检查三件确定性的事——页面起得来、顶栏是 56vp 的 MINI 档、
底部悬浮 dock 板在位。

为什么要它（§5ci 续 247）：本仓有一整类改动只有"跑起来"才暴露
（16 页系统栏接线、13 页 edgeEffect 挂载、4 处吸顶带高），
而"承接外部改动要真机逐屏跑"这条纪律此前只能靠手工点屏，成本高到没人肯每轮做。
深链把路径压成一条命令，所以这一轮把它做成闸门。

用法：
  python3 tools/verify_route_sweep.py                 # 全部路由
  python3 tools/verify_route_sweep.py --target 127.0.0.1:5555
  python3 tools/verify_route_sweep.py --only SpotPick,AreaMore

退出码 0 = 每一屏都过；1 = 有屏没起来 / 顶栏档不对 / dock 板不在。
读的是 bounds 像素，vp 换算用屏宽实测密度（不硬编 3.0/3.125）。

**这把尺证明什么、不证明什么（做过对照实验才敢这样写）**：
 · 证明：每个 `--ps route` 落点都真起了一棵树、带 56vp 的 MINI 顶栏带、底部有悬浮板
   （板宽按屏宽派生：sm 档 250–340vp 对应 300vp，md/lg 档 460–620vp 对应 560vp）。
   "某页白屏 / 壳没挂上 / dock 掉了"这类会被抓到。
 · 不证明：**页面身份**。传不存在的路由时它确实 FAIL（落回没有 MINI 顶栏的宿主页），
   但那是副作用不是校验。要断言"落点就是费用页"得比文案，本尺故意不做——
   否则任何一次正常的文案改动都会被当成结构失败来红。
 · 不证明：观感。回弹手感、模糊、液态胶囊、材质折射都不在 bounds 里，仍需真人。
"""
import argparse
import json
import re
import subprocess
import sys
import time

BUNDLE = 'com.youjing.app'
ROUTES = ['TripInput', 'PreferenceQA', 'SpotPick', 'StayPick', 'Generating', 'Itinerary',
          'GenerateFailed', 'EditItinerary', 'Expense', 'Trips', 'OnTrip', 'Share',
          'AreaMore', 'Map', 'Badges', 'Review', 'Pricing']
TITLE_BAR_VP = 56.0          # HdsNavDestinationTitleMode.MINI 的档高（SDK 注释）
def dock_range_vp(screen_vp):
    """dock 板宽的**按档**预期：手机档 300vp，md/lg 档 LayoutTokens 给的是 560vp。
    写死 250–340 会在宽屏上误报 FAIL（这一版我自己刚踩到，改成按屏宽派生）。"""
    if screen_vp >= 600.0:
        return 460.0, 620.0
    return 250.0, 340.0
NEAR_BOTTOM_PX = 460          # dock 板下沿离物理底不远


def hdc(target, args, timeout=90):
    return subprocess.run(['hdc', '-t', target] + args,
                          capture_output=True, text=True, timeout=timeout)


def layout(target):
    hdc(target, ['shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/sweep.json'])
    out = hdc(target, ['shell', 'cat', '/data/local/tmp/sweep.json']).stdout
    i = out.find('{')
    if i < 0:
        return []
    items = []

    def walk(n):
        a = n.get('attributes', {})
        m = re.match(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]', a.get('bounds', ''))
        if m:
            x1, y1, x2, y2 = [int(v) for v in m.groups()]
            items.append((a.get('type', ''), x1, y1, x2, y2))
        for c in n.get('children', []):
            walk(c)

    try:
        walk(json.loads(out[i:]))
    except json.JSONDecodeError:
        return []
    return items


# 已知设备档：屏宽 px → 密度。用实测过的读数，不做二次猜测。
# 1320/3.376＝Mate 90 Pro Max 模拟器（sm）；2210/3.125＝Mate X7 模拟器（md，本次实测：
# 节点最大 x2＝2210px，÷ 既有窗口宽 707.2vp ＝ 3.125，与 dock 板 1750px＝560vp 同密度）；
# 1260/3.125＝Pocket 2 真机竖屏。
PROFILES = ((1320, 3.376), (2210, 3.125), (1260, 3.125))


def pick_density(width_px, override):
    if override > 0:
        return override
    for px, d in PROFILES:
        if abs(width_px - px) <= 8:
            return d
    return 0.0


def check(items, density_override=0.0):
    """返回 (是否通过, 读数说明)。元组是 (type, x1, y1, x2, y2)，索引别搞混。"""
    if len(items) < 40:
        return False, '节点只有 %d 个——页面没起来' % len(items)

    def w(it):
        return it[3] - it[1]

    def h(it):
        return it[4] - it[2]

    H = max(it[4] for it in items)
    W = max(it[3] for it in items)
    density = pick_density(W, density_override)
    if density <= 0:
        return False, ('屏宽 %dpx 不在已知档表 %s 内——请带 --density <值>，'
                       '不要靠猜（上一版这里用 W/363.5 兜底，等于把未知设备硬塞进 sm 档）'
                       % (W, ', '.join(str(px) for px, _d in PROFILES)))
    dmin, dmax = dock_range_vp(W / density)
    # 栏带高度不再恒 56：带 bottomBuilder 行的页（行程详情/区域页）静止态是 56+48/56vp。
    # 判据改成「顶部有一条 50–140vp 的高栏」——MINI 掉了会变成 0 或很矮，仍会被抓住；
    # 上界 140 是 56 + 最厚的栏内行（84vp）留的余量。
    band = [it for it in items
            if 50 * density <= h(it) <= 140 * density
            and w(it) > 0.7 * W and it[2] < 0.12 * H]
    dock = [it for it in items
            if it[2] > H - NEAR_BOTTOM_PX
            and dmin * density < w(it) < dmax * density
            and h(it) > 40 * density]
    problems = []
    if not band:
        problems.append('没认出 %.0fvp 顶栏带（MINI 档掉了？）' % TITLE_BAR_VP)
    if not dock:
        problems.append('底部没找到 dock 板（宽 250–340vp 的悬浮条）')
    ok = not problems
    detail = '节点 %d ｜ 屏 %dx%d ｜ 密度≈%.3f ｜ 顶栏带 %d 处 ｜ dock 候选 %d 个%s' % (
        len(items), W, H, density, len(band), len(dock),
        '' if ok else ' → ' + '；'.join(problems))
    return ok, detail


def selfcheck():
    """不连设备也能验的部分：按档预期区间与判定阈值。"""
    cases = [(391.0, 250.0, 340.0), (363.5, 250.0, 340.0), (707.2, 460.0, 620.0),
             (839.0, 460.0, 620.0)]
    bad = 0
    for vp, lo, hi in cases:
        got = dock_range_vp(vp)
        if got != (lo, hi):
            print('  SELFCHECK FAIL %.1fvp -> %s 应为 (%.0f, %.0f)' % (vp, got, lo, hi))
            bad += 1
    for px, d in ((1320, 3.376), (2210, 3.125), (1260, 3.125), (1920, 0.0)):
        got = pick_density(px, 0.0)
        want = d
        if abs(got - want) > 1e-6:
            print('  SELFCHECK FAIL 屏宽 %dpx -> 密度 %.3f（应 %.3f；0 表示应要求 --density）'
                  % (px, got, want))
            bad += 1
    if pick_density(1920, 2.5) != 2.5:
        print('  SELFCHECK FAIL --density 覆盖没生效')
        bad += 1
    if bad:
        print('自检 %d 条不过：按档区间/密度档表没立住时，17 屏全绿不算证据' % bad)
        return 1
    print('自检通过：dock 板宽按档 4 例 + 密度档表 4 例 + --density 覆盖 1 例')
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--target', default='127.0.0.1:5555')
    ap.add_argument('--only', default='')
    ap.add_argument('--settle', type=float, default=5.0)
    ap.add_argument('--density', type=float, default=0.0,
                    help='屏宽不在已知档表内时显式给密度（px/vp）')
    ap.add_argument('--selfcheck', action='store_true',
                    help='不连设备，只验按档区间')
    args = ap.parse_args()
    if args.selfcheck:
        return selfcheck()
    routes = [r.strip() for r in args.only.split(',') if r.strip()] or ROUTES

    alive = subprocess.run(['hdc', '-t', args.target, 'shell', 'echo', 'ok'],
                           capture_output=True, text=True, timeout=30).stdout
    if 'ok' not in alive:
        print('目标 %s 不在线：先起模拟器（Emulator -hvd "Mate 90 Pro Max" '
              '-path ~/.Huawei/Emulator/deployed）或接真机' % args.target)
        return 1

    bad = 0
    for name in routes:
        hdc(args.target, ['shell', 'aa', 'force-stop', BUNDLE])
        time.sleep(1.2)
        hdc(args.target, ['shell', 'aa', 'start', '-a', 'EntryAbility', '-b', BUNDLE,
                          '--ps', 'route', name])
        time.sleep(args.settle)
        items = layout(args.target)
        ok, detail = check(items, args.density)
        if not ok:
            # 首次启动/慢设备上 4.5s 可能只抓到半棵树（真机实测：Mate X7 首次深链 StayPick 报
            # 节点 102、无顶栏带，重跑同一条就正常 217/有栏）。失败时重采一次再判，
            # 避免把加载慢当成布局回归；仍失败才算真失败。
            time.sleep(2.5)
            items = layout(args.target)
            ok2, detail2 = check(items, args.density)
            detail = detail2 + ('' if ok2 else '（重采后仍失败）')
            ok = ok2
        print('  %-16s %s  %s' % (name, 'OK ' if ok else 'FAIL', detail))
        bad += 0 if ok else 1
    print('逐屏结构巡检：%d 屏，失败 %d 屏。' % (len(routes), bad))
    print('读数口径＝dumpLayout 的 bounds 像素；观感（回弹/模糊/胶囊）不在本尺能力内，仍需真人。')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
