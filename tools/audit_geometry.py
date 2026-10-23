#!/usr/bin/env python3
"""几何契约核对：圆角/间距/尺寸必须走 RadiusTokens · SpaceTokens · LayoutTokens，
且这三张表本身要和 DESIGN.md 的 rounded/spacing/layout 三块一一对得上。

为什么要有这一支：色值（audit_colors.py）和字号（audit_type.py）都已经各抓到一处
真缺陷，几何是同一把尺子上唯一还没量的轴。帧里 52/24/10 这类「契约有名字、代码写死数」
的写法一旦散开，改一次主轴宽度就要跨 6 个文件找。

用法：python3 tools/audit_geometry.py
退出码 0 = 无偏差；1 = 契约与 token 对不上，或代码里有绕过 token 的几何字面量。

口径：
- 间距阶梯只管 padding / margin / gap（space），不管 height/width——高度归 layout 具名值；
- width/height 只核对「唯一对应一个 layout token」的字面值，避免把 24 这类
  同时是头像小档 / 拖拽把手宽 / 主轴节点值的碰撞当成违规。
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.expanduser('~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md')
ETS_FILES = (sorted(glob.glob(os.path.join(ROOT, 'entry/src/main/ets/pages/*.ets')) +
                    glob.glob(os.path.join(ROOT, 'entry/src/main/ets/components/*.ets')) +
                    glob.glob(os.path.join(ROOT, 'entry/src/main/ets/widget/**/*.ets'), recursive=True)))

# 契约名 → 本项目 token 字段名（命名不同是有意为之：token 用语义名，不用尺度名）
RADIUS_ALIAS = {'none': 'none', 'xs': 'media', 'sm': 'capsule', 'md': 'reason',
                'lg': 'card', 'xl': 'hero', 'floating-bar': 'dock', 'pill': 'pill'}
SPACE_ALIAS = {'xxs': 'xs', 'xs': 'sm', 'sm': 'md', 'base': 'lg', 'md': 'twoXl',
               'lg': 'xl', 'xl': 'fourXl', 'xxl': 'fiveXl'}
# layout 里不进 LayoutTokens 的键：断点/比例/列数不是尺寸；圆角和字号各有自己的表
LAYOUT_SKIP = {'media-aspect-ratio': '比例，不是尺寸',
               'breakpoint-compact': '断点：当前只做 compact 竖屏，宽屏未立项',
               'breakpoint-expanded': '断点：同上',
               'feed_columns_phone': '列数',
               'grid-baseline': '基线网格说明项',
               'widget-min-text': '字号，归 TypeTokens.overline',
               'post_card_radius': '圆角，归 RadiusTokens.card',
               'grid-gutter': '与 itemGap 同值（12），当前无独立栅格消费',
               'question-progress-dot': '帧的进度是 4px 通栏轨道（屏3 .progress-track），无 6px 圆点消费；'
                                        '换型与否待用户裁决（任务 #28 第 ⑤ 条）',
               'tab_glow_size': '帧写 180 环境光晕，实现按单格 68×56，尺寸取舍待用户裁决（任务 #28 第 ⑨ 条）'}


def camel(kebab):
    parts = re.split(r'[-_]', kebab)
    return parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])


def parse_contract_block(text, header):
    """DESIGN.md 的 `rounded:` / `spacing:` / `layout:` 顶层块 → {key: 'NNpx'}"""
    lines = text.split('\n')
    out = {}
    start = None
    for i, line in enumerate(lines):
        if line.rstrip() == header:
            start = i
            break
    if start is None:
        return out
    for line in lines[start + 1:]:
        if line and not line.startswith(' '):
            break
        m = re.match(r"\s+([A-Za-z0-9_-]+):\s*\"([^\"]*)\"", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def parse_token_object(path, obj_name):
    """design/*.ets 里 `export const X: T = { a: 1, b: 2 }` → {field: number}"""
    src = open(path, encoding='utf-8').read()
    m = re.search(r'export const %s(?::[^=]*)?=\s*\{(.*?)\n\}' % obj_name, src, re.S)
    if not m:
        return {}
    out = {}
    for line in m.group(1).split('\n'):
        code = re.sub(r'//.*', '', line)
        km = re.match(r"\s*([A-Za-z0-9_]+):\s*([0-9.]+),?\s*$", code)
        if km:
            out[km.group(1)] = float(km.group(2))
    return out


def px(value):
    m = re.match(r'^([0-9.]+)px$', value)
    return float(m.group(1)) if m else None


def check_contract():
    """token 表 vs DESIGN.md：缺字段、值不符一律算偏差"""
    text = open(DESIGN, encoding='utf-8').read()
    dev = os.path.join(ROOT, 'entry/src/main/ets/design')
    radius = parse_token_object(os.path.join(dev, 'RadiusTokens.ets'), 'RadiusTokens')
    space = parse_token_object(os.path.join(dev, 'SpaceTokens.ets'), 'SpaceTokens')
    layout = parse_token_object(os.path.join(dev, 'LayoutTokens.ets'), 'LayoutTokens')
    tables = {'rounded': (parse_contract_block(text, 'rounded:'), RADIUS_ALIAS, radius, 'RadiusTokens'),
              'spacing': (parse_contract_block(text, 'spacing:'), SPACE_ALIAS, space, 'SpaceTokens'),
              'layout': (parse_contract_block(text, 'layout:'), {}, layout, 'LayoutTokens')}
    gaps, mismatch, skipped = [], [], []
    for block, (contract, alias, tokens, tname) in tables.items():
        for key, raw in contract.items():
            if key in LAYOUT_SKIP:
                continue
            want = px(raw)
            if want is None:
                skipped.append('{}: {}（非 px）'.format(key, raw))
                continue
            field = alias.get(key, camel(key))
            if block == 'layout':
                field = camel(key)
            if field not in tokens:
                gaps.append('{} {}={} → {} 缺字段 {}'.format(block, key, raw, tname, field))
            elif abs(tokens[field] - want) > 1e-6:
                mismatch.append('{} {}={} ≠ {}.{}={}'.format(block, key, raw, tname, field, tokens[field]))
    print('== 契约缺 token 字段（必须补）==', len(gaps))
    for g in gaps:
        print('  ', g)
    print('== 契约值与 token 不符（必须修）==', len(mismatch))
    for m in mismatch:
        print('  ', m)
    if skipped:
        print('== 非 px 尺寸键 ==', ', '.join(skipped))
    print('== 契约中显式不进 token 的键 ==')
    for k, why in LAYOUT_SKIP.items():
        print('   {:24} {}'.format(k, why))
    return gaps, mismatch, radius, space, layout


def check_code(radius, space, layout):
    """确定项：圆角封闭八档 + 间距阶梯（padding/margin/gap）；
    参考项：width/height 的字面值恰好等于某个具名尺寸——同值不同义很常见
    （24 既可以是主轴节点，也可以是拖拽把手宽），所以只列出来人工判定，
    不让启发式把构建卡住。"""
    allowed_radius = {v: k for k, v in radius.items()}
    allowed_space = {v: k for k, v in space.items()}
    ladder = '/'.join(str(int(x)) for x in sorted(space.values()))
    named_size = {}
    for name, value in layout.items():
        named_size.setdefault(value, []).append(name)
    hard, review = [], []
    spacing_key = re.compile(r'\b(left|right|top|bottom)\s*:\s*(\d+(?:\.\d+)?)')
    gap_key = re.compile(r'\bspace\s*:\s*(\d+(?:\.\d+)?)')
    for path in ETS_FILES:
        rel = os.path.relpath(path, ROOT)
        for i, line in enumerate(open(path, encoding='utf-8').read().split('\n')):
            code = re.sub(r'//.*', '', line)
            if not code.strip():
                continue
            rm = re.search(r'\.borderRadius\(\s*(\d+(?:\.\d+)?)\s*\)', code)
            if rm:
                v = float(rm.group(1))
                if v in allowed_radius:
                    hard.append((rel, i + 1, '圆角 {} 应写 RadiusTokens.{}'.format(v, allowed_radius[v])))
                else:
                    hard.append((rel, i + 1, '圆角 {} 不在封闭八档（{}）'.format(v, ladder)))
            pm = re.match(r'\s*\.padding\(\s*(\d+(?:\.\d+)?)\s*\)', code)
            if pm and float(pm.group(1)) > 0:
                v = float(pm.group(1))
                if v not in allowed_space:
                    hard.append((rel, i + 1, 'padding {} 离表（阶梯 {}）'.format(v, ladder)))
                else:
                    review.append((rel, i + 1, 'padding {} 可写 SpaceTokens.{}'.format(v, allowed_space[v])))
            if '.padding({' in code or '.margin({' in code:
                for km in spacing_key.finditer(code):
                    v = float(km.group(2))
                    if v == 0:
                        continue
                    if v not in allowed_space:
                        hard.append((rel, i + 1, '{} {} 离表（阶梯 {}）'.format(km.group(1), v, ladder)))
                    else:
                        review.append((rel, i + 1, '{} {} 可写 SpaceTokens.{}'.format(km.group(1), v, allowed_space[v])))
            for gm in gap_key.finditer(code):
                v = float(gm.group(1))
                if v == 0:
                    continue
                if v not in allowed_space:
                    hard.append((rel, i + 1, 'gap/space {} 离表（阶梯 {}）'.format(v, ladder)))
                else:
                    review.append((rel, i + 1, 'gap/space {} 可写 SpaceTokens.{}'.format(v, allowed_space[v])))
            for wm in re.finditer(r'\.(width|height)\(\s*(\d+(?:\.\d+)?)\s*\)', code):
                v = float(wm.group(2))
                if v in named_size and v >= 6:
                    review.append((rel, i + 1, '{} {} 与具名尺寸同值：{}（同值不同义则忽略）'.format(
                        wm.group(1), v, '/'.join(named_size[v]))))
    print('== 几何必须修 ==', len(hard))
    for rel, ln, why in hard:
        print('  {:44} L{:<5} {}'.format(rel, ln, why))
    print('== 参考项（不卡构建，人工判定）==', len(review))
    for rel, ln, why in review:
        print('  {:44} L{:<5} {}'.format(rel, ln, why))
    return hard


def main():
    if not os.path.exists(DESIGN):
        print('契约文件不在：' + DESIGN)
        return 1
    gaps, mismatch, radius, space, layout = check_contract()
    hard = check_code(radius, space, layout)
    total = len(gaps) + len(mismatch) + len(hard)
    print('核对结果：偏差 {} 项'.format(total))
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
