#!/usr/bin/env python3
"""色值契约核对：resources 的两份 color.json ↔ 设计契约 DESIGN.md。

为什么要有这个脚本：色表是 48 件 × 两档的手抄结果，抄错一位（比如把
rgba(196,196,202,.4) 写成 #66C4C6CA，绿通道 196→198）肉眼和截图都看不出来，
但它是契约偏差。DESIGN.md 的 Translucency ledger 同时给了 rgba() 与 8 位十六进制
两列，所以能逐件机器比对。

用法：
    python3 tools/audit_colors.py [DESIGN.md 路径]
默认路径指向设计底稿 v1；底稿搬家后把新路径传进来即可。

退出码 0 = 全部对得上；1 = 有偏差（每条打印出来）。
"""

import json
import os
import re
import sys

LIGHT_FILE = 'entry/src/main/resources/base/element/color.json'
DARK_FILE = 'entry/src/main/resources/dark/element/color.json'
DEFAULT_DESIGN = os.path.expanduser(
    '~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md')

# 少数件与契约名不成规则，单独标出来
NAME_MAP = {
    'border_subtle': ('glass-bar-border', 'dark-glass-bar-border'),
    'modal_scrim': ('modal-scrim', 'modal-scrim'),
}


def load_colors(path):
    with open(path, encoding='utf-8') as f:
        return {e['name']: e['value'].upper() for e in json.load(f)['color']}


def norm8(h):
    h = h.upper()
    return '#FF' + h[1:] if len(h) == 7 else h


def contract_names(name):
    """推出契约里的浅/深件名。规则：route_* ↔ route-paper/route-night，
    star_* ↔ star-paper/star-night，其余 ↔ 原名与 dark- 前缀。"""
    if name in NAME_MAP:
        return NAME_MAP[name]
    kebab = name.replace('_', '-')
    for prefix, light, night in (('route_', 'route-paper-', 'route-night-'),
                                 ('star_', 'star-paper-', 'star-night-')):
        if name.startswith(prefix):
            return (light + name[len(prefix):], night + name[len(prefix):])
    return (kebab, 'dark-' + kebab)


def parse_design(md):
    """返回 {契约名(下划线大写): 8 位色值}，含 YAML 段与 rgba 台账两段。

    台账同时给了 rgba() 与十六进制两列：0.3 换算成 alpha 是 76.5，四舍五入会得 4C，
    而台账的十六进制列写的是 4D。所以有十六进制列时以它为准，rgba 只兜底。
    """
    out = {}
    for m in re.finditer(r'^\s*([a-z0-9][a-z0-9-]*):\s*"(#[0-9A-Fa-f]{6,8})"', md, re.M):
        out[m.group(1).replace('-', '_').upper()] = norm8(m.group(2))
    for m in re.finditer(r'\|\s*`([a-z0-9-]+)`\s*\|\s*`rgba\(([^)]*)\)`\s*(?:\|\s*`([0-9A-Fa-f ]+)`)?', md):
        name = m.group(1).replace('-', '_').upper()
        hexes = re.findall(r'[0-9A-Fa-f]{2}', m.group(3) or '')
        if len(hexes) == 4:
            out.setdefault(name, '#' + ''.join(h.upper() for h in hexes))
            continue
        parts = [p.strip() for p in m.group(2).split(',')]
        if len(parts) == 4:
            r, g, b, a = parts
            alpha = int(round(float(a) * 255))
            out.setdefault(name, '#{:02X}{:02X}{:02X}{:02X}'.format(alpha, int(r), int(g), int(b)))
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    design_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DESIGN
    if not os.path.exists(design_path):
        print('找不到契约文件：' + design_path)
        return 2
    with open(design_path, encoding='utf-8') as f:
        contract = parse_design(f.read())
    base = load_colors(os.path.join(root, LIGHT_FILE))
    dark = load_colors(os.path.join(root, DARK_FILE))
    bad = 0
    unchecked = []
    for name in sorted(base):
        light_key, dark_key = contract_names(name)
        want_l = contract.get(light_key.replace('-', '_').upper())
        want_d = contract.get(dark_key.replace('-', '_').upper())
        if want_l is None and want_d is None:
            unchecked.append(name)
            continue
        got_l, got_d = base[name], dark.get(name, '')
        if want_l is not None and got_l != want_l:
            print('浅色偏差 {:22} 实为 {} 契约 {}'.format(name, got_l, want_l))
            bad += 1
        if want_d is not None and got_d != want_d:
            print('深色偏差 {:22} 实为 {} 契约 {}'.format(name, got_d, want_d))
            bad += 1
    print('核对 {} 件：偏差 {} 件，契约未直接命名 {} 件'.format(
        len(base), bad, len(unchecked)))
    if unchecked:
        print('未直接命名（派生透明值或系统件，脚本不判）：' + ', '.join(unchecked))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
