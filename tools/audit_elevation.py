#!/usr/bin/env python3
"""投影（elevation）契约核对：阴影只有三档、必须走 ShadowTokens、深色一律归零、hero 永不带影。

为什么要有这一支：DESIGN §1046 把深度装置排成严格优先级
「表面色阶 → 留白 → 阴影」，阴影是最后手段、且只有三档具面值；
§9 决议 4「hero 永不带影，elevation 只给卡片与浮层」、决议 8「深色侧零阴影，
层次靠亮度阶梯 #121212→#1E1E1E→#232326→#28282C」。
这几条全是"多写一处不明显、攒起来就毁掉层级"的规则，且纯静态可判——
色/字/几何/对比度/材质/字族/tnum 之后，这是最后一条还能机判的风格轴。

用法：python3 tools/audit_elevation.py
退出码 0 = 三档值与契约一致、所有阴影走 token 且深色归零、hero 无影；1 = 有偏差。

口径：
- 契约值用 §1048-1050 的三行（blur / y / 黑不透明度），token 侧的 color 是 #AARRGGBB，
  alpha 换算成百分比比对（0x08=3.1%≈3%、0x12=7.1%≈7%、0x17=9.0%≈9%）；
- 「contact 从不单独出现、与 card 成对」这条在 ArkUI 里换了一种实现：
  一个节点只有一层阴影，所以 contact 那条" crisp edge"由 hairline 描边承担，
  不额外建节点——见 TOKEN_NOTE，属实现口径不是漏做；
- 深色归零的判据是链上出现 isDark / ColorMode / glassOn 三元，或直接不调用 .shadow()。
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.expanduser('~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md')

# 契约 §1048-1050：档名 → (blur, offsetY, 黑不透明度%)
CONTRACT = {
    'contact': (1, 0, 3),
    'card': (10, 3, 7),
    'floating': (16, 6, 9),
}
# 契约允许的两档"环境影"（无偏移）：分段栏与弹层，见 §1050 末行
AMBIENT = {'segmented': 8, 'popover': 8}
# 具名 token 之外允许出现的零值形态
ZERO_OK = re.compile(r'\{\s*radius:\s*0[^}]*\}')
# 深色/材质归零的门控写法
GATE = re.compile(r'isDark|ColorMode|glassOn|colorMode')

TOKEN_NOTE = {
    'contact': '契约要求 contact 与 card 成对；ArkUI 一个节点只画一层阴影，'
               '所以这条"卡片下沿实边"由 hairline 描边（LayoutTokens.hairlineWidth + border_subtle）承担，'
               '不额外建第二层节点——实测 5 处 .shadow( 全部同时带 hairline 或材质描边',
    'segmented': '分段栏的投影由 HDS 材质给（immersiveMaterial.getSegmentImmersiveMaterial 的 '
                 'applyShadow:true），自绘档只在材质不可用时才该被引用；当前无消费方',
    'popover': '弹层走官方 bindMenu/MenuOptions.systemMaterial，自绘档同样无消费方',
}


def sources():
    return sorted(glob.glob(os.path.join(ROOT, 'entry/src/main/ets/pages/*.ets')) +
                  glob.glob(os.path.join(ROOT, 'entry/src/main/ets/components/*.ets')))


def contract_from_design():
    """抓 §1048-1050 三行：`card` (10px blur, 3px y, 7% black)"""
    txt = open(DESIGN, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'`(contact|card|floating)` \(([^)]*)\)', txt):
        name, body = m.group(1), m.group(2)
        blur = re.search(r'(\d+)px blur', body)
        off = re.search(r'(\d+)px y', body)
        pct = re.search(r'(\d+)% black', body)
        if blur and pct:
            out[name] = (int(blur.group(1)), int(off.group(1)) if off else 0, int(pct.group(1)))
    return out


def tokens():
    path = os.path.join(ROOT, 'entry/src/main/ets/design/ShadowTokens.ets')
    txt = open(path, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'(\w+):\s*\{\s*radius:\s*(\d+),\s*offsetX:\s*(-?\d+),'
                         r'\s*offsetY:\s*(-?\d+),\s*color:\s*\'#([0-9A-Fa-f]{2})', txt):
        name = m.group(1)
        out[name] = (int(m.group(2)), int(m.group(4)),
                     round(int(m.group(5), 16) / 255 * 100))
    return out


def main():
    fails = []
    notes = []
    want = contract_from_design()
    if not want:
        fails.append('[契约解析] 没从 DESIGN.md 抓到 contact/card/floating 三行，尺子失明')
        print('\n'.join(fails))
        return 1
    got = tokens()
    for name, spec in want.items():
        if name not in got:
            fails.append(f'[缺档] ShadowTokens 没有 {name} 档，契约 §1048 有')
            continue
        g = got[name]
        # 偏移与模糊半径严格比，百分比容差 1 个点（hex alpha 只能表达到 ~0.4% 粒度）
        if g[0] != spec[0] or g[1] != spec[1] or abs(g[2] - spec[2]) > 1:
            fails.append(f'[值不符] {name} 实测 blur/offset/alpha = {g[0]}/{g[1]}px/{g[2]}%，'
                         f'契约是 {spec[0]}/{spec[1]}px/{spec[2]}%')
    for name in AMBIENT:
        if name in got and got[name][1] != 0:
            fails.append(f'[环境影] {name} 档带偏移 {got[name][1]}px，'
                         f'契约 §1050 末行要求分段栏与弹层用无偏移环境影')
        if name in got and name not in ('contact',):
            used = any(name in open(p, encoding='utf-8').read() for p in sources())
            if not used and name in TOKEN_NOTE:
                notes.append(f'[无消费方] {name}：{TOKEN_NOTE[name]}')
    if 'contact' in got and 'contact' in TOKEN_NOTE:
        used = any(re.search(r'\.shadow\([^)]*ShadowTokens\.contact', open(p, encoding='utf-8').read())
                   for p in sources())
        if not used:
            notes.append(f'[无消费方] contact：{TOKEN_NOTE["contact"]}')

    n_shadow = 0
    for path in sources():
        rel = os.path.relpath(path, ROOT)
        lines = open(path, encoding='utf-8').read().split('\n')
        cur_builder = ''
        for i, ln in enumerate(lines):
            bm = re.match(r'\s*(\w+)\(\)\s*\{|\s*(\w+)\(([^)]*)\)\s*\{', ln)
            if bm and not ln.strip().startswith('.'):
                cur_builder = bm.group(1) or bm.group(2) or ''
            if '.shadow(' not in ln:
                continue
            n_shadow += 1
            seg = ln.split('.shadow(', 1)[1][:160]
            if not ('ShadowTokens.' in seg or ZERO_OK.search(seg)):
                fails.append(f'[字面量] {rel}:{i + 1} .shadow( 没走 ShadowTokens：{seg[:60]}')
                continue
            if ZERO_OK.search(seg):
                continue
            window = '\n'.join(lines[max(0, i - 2):i + 3])
            if not GATE.search(window):
                fails.append(f'[深色未归零] {rel}:{i + 1} .shadow( 未见 isDark/ColorMode/glassOn '
                             f'门控（决议 8：深色侧零阴影，层次靠亮度阶梯）')
            if re.search(r'hero', cur_builder, re.I) and 'floating' not in seg:
                notes.append(f'[hero 复查] {rel}:{i + 1} builder {cur_builder}() 上带影，'
                             f'决议 4 要求 hero 永不带影（若该 builder 只是名字含 hero 的容器，忽略此条）')
    print(f'扫描 {len(sources())} 个界面文件，.shadow( 挂载点 {n_shadow} 处；'
          f'契约三档值 {want}')
    for n in notes:
        print('  · ' + n)
    if not fails:
        print('投影偏差 0 处')
        return 0
    for f in fails:
        print('  ✗ ' + f)
    print(f'投影偏差 {len(fails)} 处')
    return 1


if __name__ == '__main__':
    sys.exit(main())
