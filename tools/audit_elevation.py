#!/usr/bin/env python3
r"""投影（elevation）契约核对：阴影档与 ShadowTokens 逐档对表、必须走 ShadowTokens、hero 永不带影。

T2′（契约 v2）改尺记录：契约 elevation 从三档（contact/card/floating）升六档
（none/cardContact/cardAmbient/floating/pillFloat/segmented/popover）。本尺的档名映射同步为
cardContact(1,0,3) / cardAmbient(10,3,7) / floating(16,6,9) / pillFloat(8,3,15)，
兼容期旧名 contact/card 已随 T4 从 ShadowTokens 删除（散文正则仍收旧名并归一，防有人回抄）。
**深色判据已按契约 v2 反转**：出现深浅门控即违规，`radius: 0` 只允许由材质门控引出
（v1 的「深色必须归零」口径作废；材质门控那条 v2 保留，它管的是系统材质接管时表面自归零）。
selftest 共 17 条断言 = 阳性 10 类 + 阴性 6 类 + 1 条文档数字锁（三个数自锁）。
阳性样本钉死「改 blur 必报 / 删档与缺 `Npx y` 退化必报 [契约漂移] 或失明 / pillFloat 新映射面必报」，
阴性样本钉死「当前真实代码 + 新契约 0 偏差、解析恰等于 CONTRACT 四档、字面跑 7 处挂载不误红」。

为什么要有这一支：DESIGN §Elevation 把深度装置排成严格优先级
「表面色阶 → 留白 → 阴影」，阴影是最后手段、且只有具面值的档；
决议 4「hero 永不带影，elevation 只给卡片与浮层」。
决议 8「深色侧零阴影」在契约 v2 已被 §Elevation 那句「Shadow is black-with-alpha,
which is theme-neutral」反转，但**判据反转与门控删除属 T4 原子批**，本轮尺仍按 v1 口径要求门控。
这几条全是"多写一处不明显、攒起来就毁掉层级"的规则，且纯静态可判——
色/字/几何/对比度/材质/字族/tnum 之后，这是最后一条还能机判的风格轴。

用法：python3 tools/audit_elevation.py [--selftest]
退出码 0 = 各档值与契约一致、所有阴影走 token 且深色带门控、hero 无影（selftest 为 14 条断言全成立）；
        1 = 有偏差 / selftest 失效；
        2 = 用法错（未知参数）。

口径：
- 契约值用 §Elevation bullet 行（blur / y / 黑不透明度），**本尺不解析 YAML `elevation:` 段**——
  R27③ 实测：YAML 键带点号而 token 侧正则只认 `\w+`；且旧散文正则不强制括号里的 `Npx y` 时，
  改名后 `` `contact` `` 会去匹配 `` `cardAmbient` (10px blur… `` 行、两档互相覆盖静默出错档。
  ⇒ 现在档名组显式列出六名（含兼容期旧名），且 blur/y/% 三件缺一即不解析、由 [缺档]/失明分支兜住；
- token 侧的 color 是 #AARRGGBB，alpha 换算成百分比比对（0x08=3.1%≈3%、0x12=7.1%≈7%、
  0x18=9.4%≈9%、0x26=14.9%≈15%），容差 ±1 个百分点（hex alpha 粒度 ~0.4%）；
- 「cardContact 从不单独出现」这条 v2 口径（契约散文：layered under `cardContact` by two nested
  containers）：一个节点只有一层阴影，ambient 与 contact 由两个嵌套容器分层——见 TOKEN_NOTE，
  属实现口径不是漏做；
- 深色归零的**当前**判据仍是链上出现 isDark / ColorMode / glassOn 三元，或直接不调用 .shadow()
  （v1 口径，反转随 T4）。
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.expanduser('~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md')

# 契约 §Elevation：档名 → (blur, offsetY, 黑不透明度%)。
# 这份 dict 是 selftest 阴性的数字源——与顶部 docstring 的三件数字互锁，漂移即 FAIL。
CONTRACT = {
    'cardContact': (1, 0, 3),
    'cardAmbient': (10, 3, 7),
    'floating': (16, 6, 9),
    'pillFloat': (8, 3, 15),
}
# 兼容期旧档名（4 个页面调用点在用）：散文正则收进来后归一到新名；T4 随别名一起删。
LEGACY_MAP = {'contact': 'cardContact', 'card': 'cardAmbient'}
# 契约允许的两档"环境影"（无偏移）：分段栏与弹层，见 §Elevation 末行
AMBIENT = {'segmented': 8, 'popover': 8}
# 具名 token 之外允许出现的零值形态
ZERO_OK = re.compile(r'\{\s*radius:\s*0[^}]*\}')
# 契约 v2 的投影口径：**黑 alpha 主题中性，深色不再归零**（家族契约 §Elevation，2026-11-02 拍板）。
# 所以这里反过来判：出现深浅门控 = 违规；出现零值只允许由**材质**门控引出（材质接管时表面自己归零，
# 与深浅无关，那条规则 v2 保留）。T4 已删掉现存 4 处 `this.isDark ? {radius:0} : …`
# （TripsPage/StayPickPage/MapPage/EditItineraryPage），别名 contact/card 同批停用。
THEME_GATE = re.compile(r'isDark|ColorMode|colorMode')
MATERIAL_GATE = re.compile(r'glassOn|isSystemMaterialActive')


def gate_problems(window: str) -> list:
    """投影门控判据（v2 反转后）。单独成函数是为了让 --selftest 能直接喂样本反证它抓得到，
    而不是只反证契约解析——判据改了却没人测过改动，就是本仓反复踩过的「0 命中假绿」。"""
    out = []
    if THEME_GATE.search(window):
        out.append('[深色仍归零]')
    elif 'radius: 0' in window and not MATERIAL_GATE.search(window):
        out.append('[无门控归零]')
    return out

TOKEN_NOTE = {
    'contact': '契约要求 cardContact 从不单独出现（与 cardAmbient 由两个嵌套容器分层）；'
               'ArkUI 一个节点只画一层阴影，所以这条"卡片下沿实边"由 hairline 描边'
               '（LayoutTokens.hairlineWidth + border_subtle）承担，不额外建第二层节点——'
               '实测 4 处 .shadow( 全部同时带 hairline 或材质描边',
    'segmented': '分段栏的投影由 HDS 材质给（immersiveMaterial.getSegmentImmersiveMaterial 的 '
                 'applyShadow:true），自绘档只在材质不可用时才该被引用；当前无消费方',
    'popover': '弹层走官方 bindMenu/MenuOptions.systemMaterial，自绘档同样无消费方',
}

# §Elevation 的六档散文 bullet（与契约逐字同文）。真实扫描直接读 DESIGN；
# selftest 以这四行为基线做单变量变异，跑 run-on-sample 而不是拿字面量比 contract_from_design()。
BULLETS = [
    '- `cardContact` (1px blur, 0px y, 3% black): the crisp edge under a card; never alone.',
    '- `cardAmbient` (10px blur, 3px y, 7% black): itinerary cards, summary card, sheets — '
    'layered under `cardContact` by two nested containers, since ArkUI renders one shadow '
    'layer per node.',
    '- `floating` (16px blur, 6px y, 9% black): sheets, popovers, the dock.',
    '- `pillFloat` (8px blur, 3px y, 15% black): floating pills and drag-elevated rows.',
]


def sources():
    return sorted(glob.glob(os.path.join(ROOT, 'entry/src/main/ets/pages/*.ets')) +
                  glob.glob(os.path.join(ROOT, 'entry/src/main/ets/components/*.ets')))


def elevation_section_text():
    txt = open(DESIGN, encoding='utf-8').read()
    start = txt.find('# Elevation & Depth')
    if start < 0:
        return ''
    body = txt[start:]
    nxt = body.find('\n# ')
    return body if nxt < 0 else body[:nxt]


def parse_bullets(section_text):
    """抓 §Elevation bullet：`档名` (Npx blur, Npx y, N% black)。

    R27③：`Npx y` **强制必填**。改名后若不强制，旧式 `` `contact` (1px blur, 3% black) ``
    （无 y 件）会静默解析成 cardContact=(1,0,0)，或让档名组吃掉别的档的行——
    缺件时该条**不进** out，由主扫描的 [缺档]/[契约解析] 分支兜住并报红，绝不静默绿。
    """
    out = {}
    for m in re.finditer(
            r'`(cardContact|cardAmbient|contact|card|floating|pillFloat)` \(([^)]*)\)',
            section_text):
        name = LEGACY_MAP.get(m.group(1), m.group(1))
        body = m.group(2)
        blur = re.search(r'(\d+)px blur', body)
        off = re.search(r'(\d+)px y', body)
        pct = re.search(r'(\d+)% black', body)
        if blur and off and pct:
            out[name] = (int(blur.group(1)), int(off.group(1)), int(pct.group(1)))
    return out


def contract_from_design():
    return parse_bullets(elevation_section_text())


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


def usage():
    print('用法：python3 tools/audit_elevation.py [--selftest]'
          '（--selftest 自 T2′ 起真跑 14 条断言，不再是退 2 占位）')


def scan(bullet_src=None):
    """一次投影核对。bullet_src=None 读真实契约；selftest 传入变异样本复用全部判据。

    返回 (rc, .shadow( 挂载点数)。挂载点计数进返回值是为了让 selftest 钉住
    「阴性不是判据没跑到」——照 audit_motion 的口径。
    """
    fails = []
    notes = []
    want = contract_from_design() if bullet_src is None else parse_bullets(bullet_src)
    if not want:
        fails.append('[契约解析] 没从 DESIGN.md §Elevation 抓到任何一档三件齐全（blur/y/%）的'
                     ' bullet（cardContact/cardAmbient/floating/pillFloat），尺子失明')
        print('\n'.join(fails))
        return 1, 0
    got = tokens()
    # 交叉对表两向都要咬：want 来自散文契约、CONTRACT 来自本尺头部（与 YAML §2(a) 同源）。
    # 只比 want→tokens 会留 fail-open 面：契约行被删/缺 y 退化成少一档时 want 里根本没有那档，
    # [缺档] 永不触发，尺子对着残缺契约"0 偏差"（selftest 阳性 5/6 第一跑就是靠这个漏洞抓到本修）。
    for name, spec in want.items():
        if name not in got:
            fails.append(f'[缺档] ShadowTokens 没有 {name} 档，契约 §Elevation 有')
            continue
        g = got[name]
        # 偏移与模糊半径严格比，百分比容差 1 个点（hex alpha 只能表达到 ~0.4% 粒度）
        if g[0] != spec[0] or g[1] != spec[1] or abs(g[2] - spec[2]) > 1:
            fails.append(f'[值不符] {name} 实测 blur/offset/alpha = {g[0]}/{g[1]}px/{g[2]}%，'
                         f'契约是 {spec[0]}/{spec[1]}px/{spec[2]}%')
    # 反向：want 必须恰好是 CONTRACT 四档——契约多一档（尺未同步）或少一档（被删/缺 y 解析退化）都报。
    # selftest 阳性 5（删整行）与 6（单条缺 y）都落在这里，不再依赖 tokens 侧的 [缺档]。
    extra = sorted(set(want) - set(CONTRACT))
    missing = sorted(set(CONTRACT) - set(want))
    if want and (extra or missing):
        fails.append(f'[契约漂移] §Elevation 解析出 {sorted(want)}，与本尺 CONTRACT 四档不符：'
                     f'多出={extra or []} 缺失={missing or []}'
                     '（改契约档位必须同批改本尺 CONTRACT，T8 规矩；缺 y 退化也走这条）')
    for name in AMBIENT:
        if name in got and got[name][1] != 0:
            fails.append(f'[环境影] {name} 档带偏移 {got[name][1]}px，'
                         f'契约 §Elevation 末行要求分段栏与弹层用无偏移环境影')
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
            window = '\n'.join(lines[max(0, i - 2):i + 3])
            for tag in gate_problems(window):
                if tag == '[深色仍归零]':
                    fails.append(f'{tag} {rel}:{i + 1} .shadow( 带深浅门控'
                                 f'（契约 v2：黑 alpha 阴影主题中性，深色保留）')
                else:
                    fails.append(f'{tag} {rel}:{i + 1} .shadow( 出现 radius:0 却无材质门控'
                                 f'（只有系统材质接管时表面才该自归零）')
            if re.search(r'hero', cur_builder, re.I) and 'floating' not in seg:
                notes.append(f'[hero 复查] {rel}:{i + 1} builder {cur_builder}() 上带影，'
                             f'决议 4 要求 hero 永不带影（若该 builder 只是名字含 hero 的容器，忽略此条）')
    print(f'扫描 {len(sources())} 个界面文件，.shadow( 挂载点 {n_shadow} 处；'
          f'契约四档值 {want}')
    for n in notes:
        print('  · ' + n)
    if not fails:
        print('投影偏差 0 处')
        return 0, n_shadow
    for f in fails:
        print('  ✗ ' + f)
    print(f'投影偏差 {len(fails)} 处')
    return 1, n_shadow


def main():
    argv = sys.argv[1:]
    # 批次一全批评审 Important-1 附项 + T2′：`--selftest` 以前是退 2 占位
    # （"给了这个参数就报错退出"，绝不让"elevation --selftest 通过"成为没发生过的事）。
    # T2′ 档名映射落地后自检**真跑**（阳性 7 + 阴性 6 + 文档锁 1），不再退 2。
    if argv[:1] == ['--selftest']:
        return selftest()
    if argv:
        print('未知参数：' + ' '.join(argv))
        usage()
        return 2
    rc, _ = scan()
    return rc


# ---------------------------------------------------------------- selftest 样本
# 单变量变异：每条只动一处，报不出来就是判据失效而不是"样本没造对"。

# 真实扫描的期望读数（selftest 断言锁死；漂移即 FAIL，改代码/改契约时必须两处同批动）
# 2026-11-07 全量对齐收尾：实际生产 `.shadow(` 挂载点 = 3 个自绘玻璃件（GlassPanel /
# DesignButton / BottomTabBar）+ 4 个页面（TripsPage / StayPickPage / MapPage /
# EditItineraryPage）= 7。SpringPanel / BaseCard / GlassPillButton 经复核在 YJ 无载体已删除。
RUN_RC, RUN_SHADOW = 0, 7


def edited(old, new):
    """对 BULLETS 基线做一处 str.replace 变异（找不到旧串 = 样本失配，直接判 FAIL）。"""
    text = '\n'.join(BULLETS)
    if old not in text:
        raise AssertionError('selftest 样本失配（基线 bullet 里没有）：' + old[:60])
    return text.replace(old, new, 1)


def selftest():
    checks = []  # (名称, 是否成立, 读数说明)

    def expect(name, ok, detail):
        checks.append((name, ok, detail))

    # ---- 阳性 1-4：四档三件逐项单变量篡改必须报（容差外才算抓到）
    positives = [
        ('blur+1', lambda: edited('`cardContact` (1px blur', '`cardContact` (2px blur'),
         '[值不符] cardContact'),
        ('offsetY+1', lambda: edited('`floating` (16px blur, 6px y', '`floating` (16px blur, 7px y'),
         '[值不符] floating'),
        ('alpha+2pp(容差外)', lambda: edited('`cardAmbient` (10px blur, 3px y, 7%',
                                             '`cardAmbient` (10px blur, 3px y, 9%'),
         '[值不符] cardAmbient'),
        ('pillFloat blur 篡改(新映射面)', lambda: edited('`pillFloat` (8px blur', '`pillFloat` (6px blur'),
         '[值不符] pillFloat'),
    ]
    for tag, mk, needle in positives:
        rc, n = scan(mk())
        expect(f'阳性 {tag}', rc == 1, f'rc={rc} 应报 {needle!r}')

    # ---- 阳性 5：删掉一档整行 → want 少一档，[契约漂移] 报（不靠 tokens 侧 [缺档]）
    rc, n = scan('\n'.join(BULLETS[:3]))
    expect('阳性 删 pillFloat 整行', rc == 1 and n == RUN_SHADOW,
           f'rc={rc} 挂载点={n}，应落 [契约漂移] 缺失=[\'pillFloat\']')

    # ---- 阳性 6-7：散文缺 `Npx y` 造成解析退化——必须报 [契约漂移] 或报失明，不许静默绿（R27③）
    rc, _ = scan(edited('- `cardContact` (1px blur, 0px y, 3% black)',
                        '- `contact` (1px blur, 3% black)'))
    expect('阳性 单条缺 y(旧式 contact)', rc == 1, f'rc={rc}，应落 [契约漂移] 缺失=[\'cardContact\']')
    rc, _ = scan('\n'.join([
        '- `contact` (1px blur, 3% black): x',
        '- `card` (10px blur, 7% black): x',
        '- `floating` (16px blur, 9% black): x',
        '- `pillFloat` (8px blur, 15% black): x',
    ]))
    expect('阳性 四条全缺 y(尺子失明)', rc == 1, f'rc={rc}，应落 [契约解析] 失明分支')

    # ---- 阴性 1：当前真实代码 + 新契约必须 0 偏差
    rc, n = scan()
    expect('阴性 真跑 0 偏差', rc == 0 and n == RUN_SHADOW, f'rc={rc} 挂载点={n}')
    # ---- 阴性 2：真实契约解析恰等于 CONTRACT 四档（档名与三件全对）
    want = contract_from_design()
    expect('阴性 解析==CONTRACT', want == CONTRACT, f'解析出 {want}')
    # ---- 阴性 3：字面跑（BULLETS 逐字，不读 DESIGN）——契约行本身解析得 4 档，
    #       真实代码对其 0 偏差、挂载点恰 RUN_SHADOW（「阴性不是判据没跑到」）
    rc3, n3 = scan('\n'.join(BULLETS))
    expect('阴性 字面跑 0 偏差且挂载点钉死', rc3 == RUN_RC and n3 == RUN_SHADOW,
           f'rc={rc3} 挂载点={n3}（钉死 {RUN_RC}/{RUN_SHADOW}）')
    # ---- 阴性 4：tokens() 必须命中全部新档名且 blur/offset 与 CONTRACT 严格一致
    got = tokens()
    ok4 = all(name in got and got[name][0] == spec[0] and got[name][1] == spec[1]
              and abs(got[name][2] - spec[2]) <= 1 for name, spec in CONTRACT.items())
    expect('阴性 tokens 覆盖新四档', ok4,
           f'tokens={ {k: got[k] for k in CONTRACT if k in got} }')
    # ---- 阴性 5：旧别名 contact/card 已随 T4 删除（这条原本是"删除信号"，信号已兑现）
    ok5 = 'contact' not in got and 'card' not in got
    expect('阴性 旧别名已删(T4)', ok5, f"残留={[k for k in ('contact', 'card') if k in got]}")
    # ---- 阳性 8-10：v2 反转后的门控判据本身要能被抓到（判据改了没人反证 = 假绿）
    p8 = gate_problems('  .shadow(this.isDark ? { radius: 0 } : ShadowTokens.cardAmbient)')
    expect('阳性 深色门控(反转判据)', p8 == ['[深色仍归零]'], f'判到 {p8}')
    p9 = gate_problems('  .shadow(this.glassOn ? ShadowTokens.none : ShadowTokens.cardContact)')
    expect('阳性 材质门控不误报', p9 == [], f'判到 {p9}')
    p10 = gate_problems('  const z = { radius: 0 }\n  .shadow(ShadowTokens.floating)')
    expect('阳性 radius:0 无材质门控', p10 == ['[无门控归零]'], f'判到 {p10}')
    # ---- 阴性 6：旧名三件齐全时归一到新名（兼容期不误红）
    legacy = parse_bullets('- `contact` (1px blur, 0px y, 3% black): x\n'
                           '- `card` (10px blur, 3px y, 7% black): x')
    expect('阴性 旧名归一不误红', legacy == {'cardContact': (1, 0, 3), 'cardAmbient': (10, 3, 7)},
           f'解析出 {legacy}')

    doc = re.search(r'selftest 共 (\d+) 条断言 = 阳性 (\d+) 类 \+ 阴性 (\d+) 类', __doc__)
    n_pos = sum(1 for name, _, _ in checks if name.startswith('阳性'))
    n_neg = sum(1 for name, _, _ in checks if name.startswith('阴性'))
    doc_ok = bool(doc) and int(doc.group(1)) == len(checks) + 1 \
        and int(doc.group(2)) == n_pos and int(doc.group(3)) == n_neg
    expect('文档数字锁', doc_ok,
           f'docstring={doc.groups() if doc else None} 实跑=阳性{n_pos}/阴性{n_neg}/共{len(checks)}+1锁')

    bad = [c for c in checks if not c[1]]
    n_pos = sum(1 for name, _, _ in checks if name.startswith('阳性'))
    n_neg = sum(1 for name, _, _ in checks if name.startswith('阴性'))
    for name, ok, detail in checks:
        print(('  OK ' if ok else '  FAIL ') + name + '：' + detail)
    if bad:
        print(f'selftest FAIL：{len(bad)} 条不成立 → 尺子读数不可信，先修尺再谈过闸')
        return 1
    print(f'selftest PASS：{len(checks)} 条成立（阳性 {n_pos} 类抓到 / 阴性 {n_neg} 类不误抓 / 文档锁 1 条）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
