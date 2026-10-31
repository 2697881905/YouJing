#!/usr/bin/env python3
"""第 14 把尺（真机）：滚到底，末行到底躲没躲开悬浮 dock。

不叫 audit_*：`for f in tools/audit_*.py` 是"静态十二把尺"的跑法，
这一把要动设备，混进去会让静态闸门悄悄点起真机。

为什么要有这一把（2026-11-01 实测）：行程格 `TripsPage:478` 写着
`List.padding({bottom: LayoutTokens.floatingDockClearance})`，第 8 把尺
`audit_layout_patterns.py` 的 R1「钉底层未让位 dock」因此判它合规、报 0 偏差；
而真机甩到列表**真·底部**后，末张卡的底边在 797.1vp、dock 顶在 748.8vp
—— 48.3vp 压在玻璃 dock 底下，被挡的是「总花费」那一行和进度条。
**padding 写了不等于净空生效**：静态尺只看代码里有没有那个 token，
量不到"滚到底之后还剩多少"。这一把补的就是这个缺口。

判据（对每一屏）：
  1. 进屏（冷启深链或点 dock），断言前台确实是有径，不跟真人抢手机；
  2. 反复甩到底，直到连续两次"最末内容底边"不变 —— 这才叫到底，
     不然量到的是中途滚动位置，会把正常页读成缺陷；
  3. 取 dock 顶（本次 dump 实测，不写死像素）与最末内容底边比：
     末边 > dock 顶 ⇒ 遮挡，报失败；
  4. 顺带报"有效净空"，让 112 这个 token 与实际值漂移可见。

用法：
  python3 tools/verify_scroll_clearance.py            # 全跑
  python3 tools/verify_scroll_clearance.py 行程 费用  # 只跑指定标签
  python3 tools/verify_scroll_clearance.py --evidence /tmp/scrollclear

退出码 0 = 无遮挡；1 = 有遮挡；2 = 设备/前台问题（不算判定失败）。
只读设备状态 + 启动自己的 App；不点删除类控件、不动任何行程数据。
"""
import json
import os
import re
import subprocess
import sys
import time

HDC = os.environ.get('HDC', '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc')
BUNDLE = 'com.youjing.app'
DENSITY = 3.125          # 实测：真机像素 ÷ vp 一律按 3.125
CLIP = 106               # 状态栏避让区（px），实测 33.9vp；窗口铺满物理屏后这是内容起排点
TOL_PX = 3               # 3px 以内的压线算量测噪声（bounds 取整）
MAX_FLINGS = 26

# 进入方式与 AppNav 的 TAB_* / routerMap 对齐；改名或加路由时要同步这张表。
# 不带 param：硬编码 trip id 会随用户删除而过期，届时测的是病态数据不是这一屏。
TARGETS = [
    ('地图', 'tab'), ('行程', 'tab'), ('规划', 'tab'), ('费用', 'tab'), ('我的', 'tab'),
    ('Itinerary', 'route'), ('OnTrip', 'route'), ('Review', 'route'),
    ('EditItinerary', 'route'), ('Share', 'route'), ('Badges', 'route'),
    ('TripInput', 'route'), ('PreferenceQA', 'route'), ('SpotPick', 'route'),
    ('StayPick', 'route'), ('AreaMore', 'route'), ('GenerateFailed', 'route'),
    # Generating 不在名单里：它 aboutToAppear 直接打真 LLM，量几何不该花钱。
]


def sh(*args):
    return subprocess.run(list(args), capture_output=True, text=True).stdout


def device():
    t = sh(HDC, 'list', 'targets').strip().splitlines()
    return t[0].strip() if t and t[0] != '[Empty]' else ''


def attrs(n):
    a = n.get('attributes')
    return a if isinstance(a, dict) else n


def nums(b):
    v = [int(x) for x in re.findall(r'-?\d+', b or '')]
    return v if len(v) == 4 else None


def inside(b, r):
    return bool(r) and b[0] >= r[0] - 2 and b[1] >= r[1] - 2 and b[2] <= r[2] + 2 and b[3] <= r[3] + 2


def grab(tag, out):
    """dump 一次，返回 (最末内容底边 px, dock 顶 px, 容器底 px, 落盘路径)"""
    remote = f'/data/local/tmp/{tag}.json'
    sh(HDC, 'shell', f'uitest dumpLayout -p {remote}')
    local = os.path.join(out, f'{tag}.json')
    sh(HDC, 'file', 'recv', remote, local)
    if not os.path.exists(local):
        return None, None, None, None
    d = json.load(open(local))
    nodes, bar, tab = [], [None], [None]

    def w(n):
        a = attrs(n)
        b = nums(a.get('bounds'))
        ty = str(a.get('type'))
        if b:
            if ty == 'TabBar' and bar[0] is None:
                bar[0] = b
            if ty == 'TabContent' and tab[0] is None:
                tab[0] = b
            nodes.append(((a.get('text') or '').strip(), ty, b))
        for c in n.get('children', []):
            w(c)
    w(d)
    if bar[0] is None:
        return None, bar[0], None, local
    # 只看"内容边"：有文字的节点 + ListItem 这一级。
    # 不加这个限定的话，根容器/Column 这些铺满整屏的框会先命中 max，
    # 末边永远等于屏底 —— 尺子自己造出 112vp 假遮挡（第一版就踩了）。
    body = [b for t, ty, b in nodes
            if (t or ty == 'ListItem') and not inside(b, bar[0]) and b[3] > CLIP and b[2] < 1138]
    if not body:
        return None, bar[0][1], tab[0][3] if tab[0] else 2690, local
    return max(b[3] for b in body), bar[0][1], tab[0][3] if tab[0] else 2690, local


def is_youjing():
    # 先删本地旧证据：recv 失败时不能拿上一轮的 dump 判"前台是有径"，
    # 那样这道保护就形同虚设
    for p in ('/tmp/sc-front.json',):
        if os.path.exists(p):
            os.unlink(p)
    _, dock, _, _ = grab('sc-front', '/tmp')
    return dock is not None


def enter(name, how):
    sh(HDC, 'shell', f'aa force-stop {BUNDLE}')
    time.sleep(1.2)
    if how == 'route':
        sh(HDC, 'shell', f'aa start -b {BUNDLE} -a EntryAbility --ps route {name}')
        time.sleep(5.0)
        return True
    sh(HDC, 'shell', f'aa start -b {BUNDLE} -a EntryAbility')
    time.sleep(4.5)
    # 点 dock 之前先 dump 拿实测中心：dock 位置会随窗口布局改动，写死 y 会点到 dock 外面
    remote = '/data/local/tmp/sc-tap.json'
    if os.path.exists('/tmp/sc-tap.json'):
        os.unlink('/tmp/sc-tap.json')
    sh(HDC, 'shell', f'uitest dumpLayout -p {remote}')
    sh(HDC, 'file', 'recv', remote, '/tmp/sc-tap.json')
    try:
        d = json.load(open('/tmp/sc-tap.json'))
    except Exception:
        return False
    hit = []

    def w(n):
        a = attrs(n)
        b = nums(a.get('bounds'))
        if b and (a.get('text') or '').strip() == name and b[1] > 2200:
            hit.append(b)
        for c in n.get('children', []):
            w(c)
    w(d)
    if not hit:
        return False
    b = hit[0]
    sh(HDC, 'shell', f'uitest uiInput click {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}')
    time.sleep(2.0)
    return True


def fling_to_end(name, out):
    """甩到几何不再变化为止；返回 (末边, dock顶, 容器底, 是否真的还能再滚)

    稳定判据要"连续 3 次同值 + 至少甩 6 次"。只比两次会在惯性滚动中途
    恰好抓到同一帧时提前收手 —— 第一版就在行程格停在半路，把 797.1 读成 860.8。
    """
    last_bottom, dock, cont, _ = grab(f'sc-{name}', out)
    if last_bottom is None:
        return None, None, None, False
    moved = False
    same = 0
    for i in range(MAX_FLINGS):
        prev = last_bottom
        sh(HDC, 'shell', 'uitest uiInput swipe 568 2100 568 400 1400')
        time.sleep(0.7)
        nb, dock, cont, _ = grab(f'sc-{name}', out)
        if nb is None:
            return None, None, None, False
        if abs(nb - prev) <= TOL_PX:
            same += 1
            if same >= 3 and i + 1 >= 6:
                return nb, dock, cont, moved
        else:
            same = 0
            moved = abs(nb - prev) > TOL_PX
            last_bottom = nb
    return last_bottom, dock, cont, moved


def main():
    args = [a for a in sys.argv[1:]]
    out = '/tmp/sc-evidence'
    if args and args[0] == '--evidence':
        out = args[1]
        args = args[2:]
    os.makedirs(out, exist_ok=True)
    only = set(args)

    if not device():
        print('没有可用设备：hdc list targets 为空。接上真机或用 HDC=/DEV= 指定。', file=sys.stderr)
        return 2
    # 先把 App 拉到前台再断言：闸门自己该负责进入被测态，
    # 不能要求"上一轮刚好停在有径上"（装机后前台是 launcher，就会被下面这条误判成人在用手机）
    sh(HDC, 'shell', f'aa start -b {BUNDLE} -a EntryAbility')
    time.sleep(4.5)
    if not is_youjing():
        print('前台不像有径（dock 标签读不到）——不跟真人抢手机，退出。', file=sys.stderr)
        return 2

    print(f"{'屏':16s} {'可滚':4s} {'末边vp':>7s} {'dock顶vp':>8s} {'净空vp':>7s} 判定")
    fails = []
    for name, how in TARGETS:
        if only and name not in only:
            continue
        if not enter(name, how):
            print(f"{name:16s} 进不去（前台丢了或标签没找到）")
            continue
        bottom, dock, cont, moved = fling_to_end(name, out)
        if bottom is None:
            print(f"{name:16s} 读不到正文节点")
            continue
        gap = (dock - bottom) / DENSITY
        verdict = 'ok' if gap >= -TOL_PX / DENSITY else '⚠ 被 dock 挡'
        if gap < -TOL_PX / DENSITY:
            fails.append((name, gap))
        print(f"{name:16s} {'是' if moved else '否':4s} {bottom / DENSITY:7.1f} {dock / DENSITY:8.1f} {gap:7.1f} {verdict}")

    print()
    if fails:
        print(f"== 滚到底被 dock 挡住：{len(fails)} 屏 ==")
        for n, g in fails:
            print(f"   {n}: 末边超出 dock 顶 {-g:.1f}vp")
        print('   注：可滚=否 的屏是"内容超出但没有滚动区"，同样算遮挡——滚不动就永远看不见。')
        return 1
    print('== 滚到底无遮挡（pass）==')
    return 0


if __name__ == '__main__':
    sys.exit(main())
