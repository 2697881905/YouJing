#!/usr/bin/env python3
"""沉浸光感核对：玻璃点位必须"四处都有、四处之外都没有"，且材质生效时撤掉自绘层。

为什么要有这一支：色/字/几何/对比度四把尺量的都是"画出来对不对"，
而 DESIGN §1055/§1149/§1150 管的是另一件事——深度装置只有 blur 一种，且只许出现在
顶栏、浮动 dock、吸顶日标题、sheet/菜单四处；材质可用时自绘背景/描边/投影必须归零，
否则栏外多一圈环、栏下多一条灰缝。这四条此前只靠人眼，而 ItineraryPage:807 那条
"glassOn 时把底置透明，结果既无材质也无底色"的事故正是人眼漏掉的形态。

用法：python3 tools/audit_material.py
退出码 0 = 四处齐备且无越界；1 = 缺点位 / 玻璃画到四处之外 / 材质上叠了自绘层。

口径：
- 点位是否落实，按"该点位的宿主是否出现材质载体调用"判；有意不做写
  `// 材质豁免：<理由>` 一行，豁免要带理由，否则视同漏做；
- 顶栏走 HdsNavigation 的 IMMERSIVE_GRADIENT_BLUR（官方栏自己接管材质），
  dock/吸顶走 attributeModifier(barMaterial(...))，sheet/菜单走 options 里的 systemMaterial。
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'entry/src/main/ets')
DESIGN = os.path.expanduser('~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md')

EXEMPT = re.compile(r'材质豁免[:：]\s*(\S.*)')
MATERIAL_CARRIERS = ('barMaterial(', 'systemMaterial', 'IMMERSIVE_GRADIENT_BLUR', 'backgroundBlurStyle(')
# 材质生效时必须归零的自绘层
SELF_DRAWN = ('backgroundColor', 'border(', 'shadow(')
GATE_TOKENS = ('glassOn', 'isSystemMaterialActive', 'Color.Transparent', 'radius: 0', 'width: 0',
               'undefined')


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def sources():
    out = {}
    for p in glob.glob(os.path.join(ETS, '**/*.ets'), recursive=True):
        out[os.path.relpath(p, ROOT)] = read(p)
    return out


def find_exempt(lines):
    """返回本文件里写了豁免的调用行号（豁免写在被检语句的同一行或上一行）"""
    hits = set()
    for i, ln in enumerate(lines):
        if EXEMPT.search(ln):
            hits.add(i)
            hits.add(i + 1)
    return hits


def stmt_blocks(text):
    """把 @Builder/方法体切成"从宿主关键字到下一个空行或同级右括号"的粗块，用于成对检查"""
    return re.split(r'\n\s*\n', text)


def check_points(srcs, fails):
    """R1 四处点位齐备"""
    chrome = srcs.get('entry/src/main/ets/design/HdsChrome.ets', '')
    if 'IMMERSIVE_GRADIENT_BLUR' not in chrome:
        fails.append('[点位①顶栏] HdsChrome 未挂 IMMERSIVE_GRADIENT_BLUR 沉浸渐变模糊')

    dock = srcs.get('entry/src/main/ets/components/FloatingDock.ets', '')
    if 'barMaterial(' not in dock:
        fails.append('[点位②dock] FloatingDock 未挂 barMaterial')

    for rel, text in srcs.items():
        for m in re.finditer(r'\.sticky\(StickyStyle\.Header\)', text):
            # 找到这条 List 的 ListItemGroup header 传入的是哪个 builder
            heads = re.findall(r'ListItemGroup\(\{\s*header:\s*this\.(\w+)\(\)', text)
            for builder in heads:
                body = builder_body(text, builder)
                if body is None:
                    fails.append(f'[点位③吸顶] {rel} 找不到 @Builder {builder}() 的函数体')
                    continue
                if any(c in body for c in MATERIAL_CARRIERS):
                    continue
                lines = text.split('\n')
                head_line = None
                for i, ln in enumerate(lines):
                    if re.search(r'\.sticky\(StickyStyle\.Header\)', ln):
                        head_line = i
                exempt = find_exempt(lines)
                if body_exempt(body, lines, text) or (head_line is not None and head_line in exempt):
                    continue
                fails.append(f'[点位③吸顶] {rel} 的 @Builder {builder}() 既无材质也无豁免——'
                             f'契约 §1024 要求 sticky 变体用 glass-bar-surface + blur 24')

    for rel, text in srcs.items():
        lines = text.split('\n')
        exempt = find_exempt(lines)
        for i, ln in enumerate(lines):
            if '.bindSheet(' in ln:
                window = '\n'.join(lines[i:i + 12])
                if 'systemMaterial' in window or i in exempt or (i - 1) in exempt:
                    continue
                fails.append(f'[点位④sheet] {rel}:{i + 1} bindSheet 未走 options.systemMaterial，'
                             f'也未写豁免')
            if '.bindMenu(' in ln or 'MenuOptions' in ln and 'bindMenu' in ln:
                window = '\n'.join(lines[i:i + 12])
                if 'systemMaterial' in window or i in exempt:
                    continue
                fails.append(f'[点位④菜单] {rel}:{i + 1} 菜单未走 options.systemMaterial，也未写豁免')


def builder_body(text, name):
    m = re.search(r'@Builder\s*\n\s*' + re.escape(name) + r'\(\)\s*\{', text)
    if not m:
        return None
    i = m.end() - 1
    depth = 0
    while i < len(text):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[m.end() - 1:i + 1]
        i += 1
    return None


def body_exempt(body, lines, text):
    return EXEMPT.search(body) is not None


def check_selfdrawn(srcs, fails):
    """R2 材质生效处不得再叠未归零的自绘层"""
    for rel, text in srcs.items():
        if 'attributeModifier(barMaterial(' not in text:
            continue
        lines = text.split('\n')
        for i, ln in enumerate(lines):
            if 'attributeModifier(barMaterial(' not in ln:
                continue
            chain = '\n'.join(lines[i + 1:i + 14])
            end = re.match(r'\s*(\)|\})', lines[i + 1] if i + 1 < len(lines) else '')
            cut = chain.split('\n')
            for k, cl in enumerate(cut):
                if re.match(r'^\s{0,12}\.', cl) or k == 0:
                    continue
                cut = cut[:k]
                break
            chain = '\n'.join(cut)
            for prop in SELF_DRAWN:
                for m in re.finditer(re.escape(prop), chain):
                    seg = chain[m.start():m.start() + 160].split('\n)')[0]
                    if any(g in seg for g in GATE_TOKENS):
                        continue
                    fails.append(f'[自绘叠加] {rel}:{i + 1 + chain[:m.start()].count(chr(10)) + 1} '
                                 f'材质上又叠了未门控的 .{prop}（契约 §1150：双环 + 灰缝）')


def check_widget(srcs, fails):
    """R3 桌面卡片永不透明/模糊"""
    for rel, text in srcs.items():
        if '/widget/' not in rel:
            continue
        for bad in ('backgroundBlurStyle', 'BlurStyle.', 'systemMaterial', 'ImmersiveMaterial'):
            if bad in text:
                fails.append(f'[卡片禁玻璃] {rel} 出现 {bad}（契约 §1161：卡片要在任意壁纸上可读）')


def check_single_gate(srcs, fails):
    """R4 材质构造与 API 门禁只许住在 immersiveMaterial.ets"""
    for rel, text in srcs.items():
        if rel.endswith('utils/immersiveMaterial.ets'):
            continue
        for bad in ('new uiMaterial.ImmersiveMaterial(', 'deviceInfo.apiAvailable(',
                    'deviceInfo.sdkApiVersion'):
            if bad in text:
                fails.append(f'[门禁外溢] {rel} 直接写了 {bad}——兼容性门禁只准在 immersiveMaterial.ets 内')


def check_blur_value(srcs, notes):
    """R5 栏体磨砂半径 vs 契约 glass-blur（数值不等时要求写明理由）"""
    design = read(DESIGN)
    m = re.search(r'glass-blur:\s*"?(\d+)"?', design)
    if not m:
        notes.append('[半径] DESIGN.md 未找到 glass-blur token，跳过')
        return
    contract = int(m.group(1))
    chrome = srcs.get('entry/src/main/ets/design/HdsChrome.ets', '')
    for vm in re.finditer(r'BAR_BLUR_RADIUS:\s*number\s*=\s*(\d+)', chrome):
        got = int(vm.group(1))
        if got == contract:
            continue
        line = chrome[:vm.start()].count('\n') + 1
        nearby = '\n'.join(chrome.split('\n')[max(0, line - 6):line + 1])
        if '契约' in nearby and str(contract) in nearby:
            notes.append(f'[半径·已释明] 顶栏 blurRadius={got} 而契约 glass-blur={contract}，'
                         f'HdsChrome:{line} 已写明取舍')
        else:
            notes.append(f'[半径·待释明] 顶栏 blurRadius={got} 而契约 glass-blur={contract}，'
                         f'HdsChrome:{line} 未写明为何偏离')


def main():
    srcs = sources()
    fails = []
    notes = []
    check_points(srcs, fails)
    check_selfdrawn(srcs, fails)
    check_widget(srcs, fails)
    check_single_gate(srcs, fails)
    check_blur_value(srcs, notes)
    print(f'扫描 {len(srcs)} 个 .ets，玻璃点位四处 + 自绘叠加 + 卡片 + 门禁外溢')
    for n in notes:
        print('  · ' + n)
    if not fails:
        print('材质偏差 0 处')
        return 0
    for f in fails:
        print('  ✗ ' + f)
    print(f'材质偏差 {len(fails)} 处')
    return 1


if __name__ == '__main__':
    sys.exit(main())
