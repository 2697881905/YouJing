#!/usr/bin/env python3
"""沉浸光感核对：书面 blur 只许在三处栏面、材质面必须挂系统材质，且材质生效时撤掉自绘层。

为什么要有这一支：色/字/几何/对比度四把尺量的都是"画出来对不对"，
而 DESIGN §1062/§1156/§1157 管的是另一件事——深度装置只有 blur 一种，且书面 blur 只许出现在
顶栏、浮动 dock、吸顶日标题这三处栏面；④sheet/菜单是**材质面**而不是 blur 面：有系统材质时由
材质接管面板，自绘兜底就是 `components.sheet-modal` 那套实色（surface-elevated + floating 影 + scrim），
不新造 blur 值；分段控件也不是第四块玻璃面，它只带组件内的 blur 20。材质可用时自绘背景/描边/投影
必须归零，否则栏外多一圈环、栏下多一条灰缝。这几条此前只靠人眼，而 ItineraryPage:807 那条
"glassOn 时把底置透明，结果既无材质也无底色"的事故正是人眼漏掉的形态。

用法：
  python3 tools/audit_material.py                  # 读默认契约（DEFAULT_DESIGN）+ 仓库源码
  python3 tools/audit_material.py --design PATH    # 契约路径可传（与 audit_colors.py:81 同惯例）
  python3 tools/audit_material.py --chrome PATH    # 用该文件内容替代仓库 HdsChrome 参与判据（反证用，
                                                   # 不改仓库文件；不传判据参数时尺子只能审仓库）
  python3 tools/audit_material.py --selftest       # 反证判据本身有效
退出码 0 = 三处栏面 blur 与④材质面齐备、无越界、半径与门控都在；
        1 = 缺点位 / 书面 blur 画到三处栏面之外 / 材质上叠了自绘层 / 半径不符 / 缺两态 / 缺门控 /
          契约门控声明被删（尺子失明）/ selftest 有断言不成立；
        2 = 用法错（未知参数、参数缺值、多余位置参数）或 --design / --chrome 指向的文件不存在
          （对齐 audit_colors.py:83、audit_fontfamily.py 的"路径不存在退 2"，不退 0、不打 traceback）。
**本尺以前根本不解析参数**：任何参数都被无视、照常跑仓库扫描退 0，于是"audit_material --selftest 通过"
这类话在工作树里是零证据的假绿（批次一全批评审 Important-1）。现在未知参数退 2，--selftest 是真自检。

口径：
- 点位是否落实，按"该点位的宿主是否出现材质载体调用"判；有意不做写
  `// 材质豁免：<理由>` 一行，豁免要带理由，否则视同漏做；
- 顶栏走 HdsNavigation 的 IMMERSIVE_GRADIENT_BLUR（官方栏自己接管材质），
  dock 走官方 HdsTabs 的 barFloatingStyle.systemMaterialEffect，吸顶走 barMaterial/背景模糊，
  sheet/菜单走 options 里的 systemMaterial；
- [半径]（R5a）：契约 layout.glass-blur 是唯一天平，`BAR_BLUR_RADIUS` 不等即 fail（Task 3 已从 note 升档）；
- [两态缺失]（R5b）：挂 IMMERSIVE_GRADIENT_BLUR 却不写 scrollEffectStyle，滚动到位后没有终态可切；
- [门控]（R5c，本轮新增）：契约 `layout.glass-bar-scroll-gated: "true"`（DESIGN.md:240）+ §1062 那句
  "The bar surface is gated by the **absolute** scroll offset (`scrolled ? 50 : 0`), never by per-frame
  delta"。声明为 true 时，HdsChrome 里**每一个** blurRadius 值位（对象属性式与 `.blurRadius(` 方法式都算）
  必须写成带 `scrolled` 条件的三元式；缺三元式（无条件 50）、条件不是 `scrolled`（每帧增量
  `this.scrollDelta > 0 ?` 与 `scrolledDelta` 这类假门控名）、整个挂载点被删、或契约把声明那一行删掉，
  全部 fail。R5a/R5b 管的是"半径是多少、有没有终态"，管不到"什么时候给"——把三元式改成无条件 50
  那两条照绿，全站唯一防"无条件糊"的机制就只剩人眼；这条判据就是把那个空格子补上（评审 Important-1）。
  已知边界（不是漏判，堵它要先有新裁定）：本判据认"值位里有 `scrolled` 三元式"这个**形态**，
  不验 `scrolled` 这一路是不是真由绝对偏移喂进来的（`ChromeSpec.scrolled` 的 21 个调用点属批次二 T4，
  今天还没有可量的接线）；也不验 true 分支具体等于哪个半径（那是 R5a 的活）。
- selftest 的数字：**阳性 8 类 / 阴性 6 类 / 断言共 30 条**，由下面 DOC_* 三个常量与断言锁死，
  改判据或加样本必须同批改文案（同 audit_motion.py 的 M-2 防漂移闸门）；内嵌契约样本 + 内嵌代码样本
  让自检不依赖 ~/Pictures 在不在（真契约那两条是额外钉，不是唯一证据）。
"""

import glob
import os
import re
import sys
import tempfile
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'entry/src/main/ets')
DEFAULT_DESIGN = os.path.expanduser('~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md')
CHROME_REL = 'entry/src/main/ets/design/HdsChrome.ets'

# 本 docstring 声称的数字；selftest 逐条比对，漂移当场 FAIL（audit_motion.py:143-145 同一闸门）
DOC_POSITIVE = 8
DOC_NEGATIVE = 6
DOC_ASSERTIONS = 30

BLUR_SITE = re.compile(r'blurRadius\s*[:\(]')
# 门控条件：`scrolled` 词边界 + 其后紧跟 `?`；`scrollDelta`/`scrolledDelta` 这类名字过不了 \b
GATE_TERNARY = re.compile(r'(?<![A-Za-z0-9_])scrolled\b[^?]{0,120}\?')
OPEN_BRACKET = {'(': ')', '[': ']', '{': '}'}
CLOSE_BRACKET = {')': '(', ']': '[', '}': '{'}

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
    """R1 三处栏面（①顶栏 ②dock ③吸顶）+ ④材质面（sheet/菜单）点位齐备"""
    chrome = srcs.get('entry/src/main/ets/design/HdsChrome.ets', '')
    if 'IMMERSIVE_GRADIENT_BLUR' not in chrome:
        fails.append('[点位①顶栏] HdsChrome 未挂 IMMERSIVE_GRADIENT_BLUR 沉浸渐变模糊')

    # 点位②：浮动 dock。2026-10-26 起载体换成官方 HdsTabs（自绘 FloatingDock 已删），
    # 材质走 barFloatingStyle 的 systemMaterialEffect——载体变了，尺跟着改定义，不是放宽。
    dock = srcs.get('entry/src/main/ets/pages/Index.ets', '')
    if 'barFloatingStyle(' not in dock or 'systemMaterialEffect' not in dock:
        fails.append('[点位②dock] 官方 HdsTabs 的 barFloatingStyle 没挂 systemMaterialEffect')

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
                             f'契约 §1031 要求 sticky 变体用 glass-bar-surface + blur 50')

    for rel, text in srcs.items():
        lines = text.split('\n')
        exempt = find_exempt(lines)
        for i, ln in enumerate(lines):
            if '.bindSheet(' in ln:
                window = '\n'.join(lines[i:i + 12])
                if 'systemMaterial' in window or i in exempt or (i - 1) in exempt:
                    continue
                fails.append(f'[④材质面·sheet] {rel}:{i + 1} bindSheet 未走 options.systemMaterial，'
                             f'也未写豁免')
            if '.bindMenu(' in ln or 'MenuOptions' in ln and 'bindMenu' in ln:
                window = '\n'.join(lines[i:i + 12])
                if 'systemMaterial' in window or i in exempt:
                    continue
                fails.append(f'[④材质面·菜单] {rel}:{i + 1} 菜单未走 options.systemMaterial，也未写豁免')


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


def value_expr(text, start):
    """从 blurRadius 的值位（`:` 或 `(` 之后）按括号配平读到顶层结束符，返回表达式原文。

    认三种结束：顶层 `,`（对象属性下一项）、顶层 `}`/`)`/`]`（字面量或调用结束）、`;`、文本尾。
    跨行三元式（条件在上、两分支各一行）读得到——不然合规写法会被假红逼人手关闸门。
    """
    out = []
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if depth == 0 and c in (',', ';', '}', ')', ']'):
            break
        if c in OPEN_BRACKET:
            depth += 1
        elif c in CLOSE_BRACKET:
            if depth == 0:
                break
            depth -= 1
        out.append(c)
        i += 1
    return ''.join(out)


def one_line(text):
    return ' '.join(text.split())


def contract_glass_blur(design_txt):
    m = re.search(r'glass-blur:\s*"?(\d+)"?', design_txt)
    return int(m.group(1)) if m else None


def contract_scroll_gated(design_txt):
    """layout.glass-bar-scroll-gated 的声明值；键不存在返回 None（区别于 "false"）"""
    m = re.search(r'glass-bar-scroll-gated:\s*"?([A-Za-z]+)"?', design_txt)
    return m.group(1) if m else None


def check_gate(chrome, design_txt, fails, notes):
    """R5c [门控]：契约声明门控为 true 时，blurRadius 值位必须是 scrolled 三元式。

    契约侧三种状态各有各的响法，没有一种可以静默跳过（ Important-1 的靶心就是"零校验"）：
    - 键不存在 → 只要栏面还挂着 IMMERSIVE_GRADIENT_BLUR 就报「声明被删＝尺子失明」；
    - 键存在但不是 "true" → 打 note 说明本轮不要求三元式（降级是有意动作，得留痕）；
    - 键为 "true" → 逐个 blurRadius 值位验三元式；一个挂载点都没有也报（栏面模糊整个没了）。
    同一条记录不重复打印（audit_motion.py 的"同一条不许重复打印"闸门）。
    """
    gated = contract_scroll_gated(design_txt)
    if gated is None:
        if 'IMMERSIVE_GRADIENT_BLUR' in chrome:
            fails.append('[门控] 契约里找不到 glass-bar-scroll-gated 声明，而 HdsChrome 仍挂着 '
                         'IMMERSIVE_GRADIENT_BLUR——门控声明被删等于这把判据失明，不许静默变绿'
                         '（契约 §1062 与 layout 段是同一段话的两半）')
        else:
            notes.append('[门控] 契约无 glass-bar-scroll-gated 键，且栏面未挂 IMMERSIVE_GRADIENT_BLUR'
                         '——没有书面 blur 门可验，跳过')
        return
    if gated.lower() != 'true':
        notes.append('[门控] 契约 glass-bar-scroll-gated="%s" 非 true ⇒ 本轮不要求 scrolled 三元式；'
                     '若是有意取消门控，§1062 那句"never by per-frame delta"也得同批改' % gated)
        return
    sites = list(BLUR_SITE.finditer(chrome))
    if not sites:
        fails.append('[门控] 契约声明门控为 true，HdsChrome 里却没有一个 blurRadius 挂载点——'
                     '三处栏面的书面 blur 50（§1031/§1062/§1156）不靠 blurRadius 出不了图')
        return
    records = []
    for m in sites:
        expr = value_expr(chrome, m.end())
        if GATE_TERNARY.search(expr):
            continue
        if '?' not in expr:
            why = '值位是写死的无条件半径（%s）——静止态也会糊，正是 §1062 要拦的形态' % (one_line(expr) or '空')
        else:
            why = '三元式的条件不是 scrolled（%s）——每帧增量/别的偏移都算这条，' \
                  '松手回弹的负增量会把模糊打灭' % (one_line(expr) or '空')
        line = chrome[:m.start()].count('\n') + 1
        records.append('[门控] HdsChrome:%d %s —— %s（契约 layout.glass-bar-scroll-gated: "true" + '
                       '§1062：由绝对滚动偏移驱动 `scrolled ? 50 : 0`，不得用每帧增量）'
                       % (line, m.group(0).strip(), why))
    seen = set()
    for r in records:
        if r in seen:
            continue
        seen.add(r)
        fails.append(r)


def check_blur_value(srcs, notes, fails, design_txt):
    """R5 栏体磨砂半径 vs 契约 glass-blur + 两态样式齐备 + 滚动门控在位。

    判据升档（Task 3）：契约 v2 把 glass-blur 钉成 50 且 T1′ 已落地，半径不再走"写明理由即可"
    的 note 通道——不等即 fail。两态判据同批加：只挂 IMMERSIVE_GRADIENT_BLUR 却不写
    scrollEffectStyle，等于滚动后没有终态样式可切，同属缺件。

    N-5（round 2）：两态判据必须在读 DESIGN.md 之前就跑完。它只依赖 HdsChrome 的源码，与
    glass-blur 数值判据是两回事；旧写法把它放在 `if not m: return` 之后，DESIGN 抓不到
    glass-blur 键时两条判据同批静默跳过、rc 照样 0——尺子失效得毫无声音。

    Important-1（本轮）：半径对不等于门控在。[门控] 与半径、两态并列跑，且**契约抓不到
    glass-blur 时也要跑**——所以下面先跑两态与门控，再谈半径。
    """
    chrome = srcs.get(CHROME_REL, '')
    if 'IMMERSIVE_GRADIENT_BLUR' in chrome and 'scrollEffectStyle:' not in chrome:
        fails.append('[两态缺失] HdsChrome 用 IMMERSIVE_GRADIENT_BLUR 却没写 scrollEffectStyle')
    check_gate(chrome, design_txt, fails, notes)
    contract = contract_glass_blur(design_txt)
    if contract is None:
        notes.append('[半径] DESIGN.md 未找到 glass-blur token，跳过（两态与门控判据已照跑）')
        return
    for vm in re.finditer(r'BAR_BLUR_RADIUS:\s*number\s*=\s*(\d+)', chrome):
        got = int(vm.group(1))
        if got == contract:
            continue
        line = chrome[:vm.start()].count('\n') + 1
        fails.append(f'[半径] HdsChrome:{line} BAR_BLUR_RADIUS={got} 而契约 glass-blur={contract}'
                     f'（三处栏面同一把尺，不再接受注释释明）')


def judge_blur(chrome, design_txt):
    """selftest 用的窄入口：只跑 R5 三条（两态 / 门控 / 半径），不碰点位与自绘叠加"""
    fails, notes = [], []
    check_blur_value({CHROME_REL: chrome}, notes, fails, design_txt)
    return fails


TAG_RE = re.compile(r'^(\[[^\]]+\])')


def tag_of(hit):
    m = TAG_RE.match(hit)
    return m.group(1) if m else hit


# ---------------------------------------------------------------- selftest 样本
# 内嵌契约样本 + 内嵌代码样本是故意的：selftest 不许依赖 ~/Pictures 在不在
# （audit_fontfamily.py:212 同一口径）；真契约那两条是额外钉，不是唯一证据。
ST_DESIGN = 'layout:\n  glass-blur: "50"\n  glass-bar-scroll-gated: "true"\n'
ST_DESIGN_NOGATE = 'layout:\n  glass-blur: "50"\n'
ST_DESIGN_GATE_FALSE = 'layout:\n  glass-blur: "50"\n  glass-bar-scroll-gated: "false"\n'
ST_DESIGN_BARE = 'layout:\n  hairline-width: "0.5px"\n'

GATE_PROP = 'blurRadius: spec.scrolled === true ? BAR_BLUR_RADIUS : 0,'
GATE_METHOD_BODY = '.blurRadius(this.scrolled ? BAR_BLUR_RADIUS : 0)'


def st_chrome(blur_line=GATE_PROP, radius=50, scroll_effect_style=True, immersive=True):
    """拼一段与现 HdsChrome.ets:38/77/83/107 同形的最小骨架，selftest 逐条替换其中一项"""
    lines = ['const BAR_BLUR_RADIUS: number = %d;' % radius,
             '  static bar(spec: ChromeSpec): HdsNavigationTitleBarOptions {',
             '    const scrollEffect: ScrollEffectOptions = {']
    if immersive:
        lines.append('      scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,')
    lines.append('      blurEffectiveStartOffset: LengthMetrics.vp(0)')
    lines.append('    };')
    lines.append('    const backgroundStyle: HdsNavigationBackgroundStyle = {')
    lines.append('      backgroundColor: Color.Transparent,')
    if blur_line:
        lines.append('      ' + blur_line)
    lines.append('      maskExtraHeight: 0')
    lines.append('    };')
    lines.append('    const style: TitleBarStyleOptions = {')
    lines.append('      scrollEffectOpts: scrollEffect,')
    lines.append('      originalStyle: originalStyle,')
    if scroll_effect_style:
        lines.append('      scrollEffectStyle: { contentStyle: contentStyle }')
    lines.append('    };')
    lines.append('  }')
    return '\n'.join(lines)


ST_MULTI_LINE = ('blurRadius: spec.scrolled === true\n'
                 '          ? BAR_BLUR_RADIUS\n'
                 '          : 0,')
ST_UNCOND = 'blurRadius: BAR_BLUR_RADIUS,'
ST_UNCOND_LITERAL = 'blurRadius: 50,'
ST_DELTA = 'blurRadius: this.scrollDelta > 0 ? BAR_BLUR_RADIUS : 0,'
ST_FAKE_GATE = 'blurRadius: this.scrolledDelta !== 0 ? BAR_BLUR_RADIUS : 0,'

# 判据（阳性=契约禁止的写法，必须抓到；阴性=契约正确写法，一条不许误抓）
# 每条 (类别, 名称, chrome 文本, 契约文本, 期望命中标签及最少条数)
CASES = [
    ('阳性', '半径不符：BAR_BLUR_RADIUS 写 24 而契约 glass-blur=50',
     st_chrome(radius=24), ST_DESIGN, {'[半径]': 1}),
    ('阳性', '两态缺失：挂 IMMERSIVE_GRADIENT_BLUR 却不写 scrollEffectStyle',
     st_chrome(scroll_effect_style=False), ST_DESIGN, {'[两态缺失]': 1}),
    ('阳性', '门控缺失·无条件：blurRadius 直接给常量（评审 Important-1 的靶子）',
     st_chrome(blur_line=ST_UNCOND), ST_DESIGN, {'[门控]': 1}),
    ('阳性', '门控缺失·无条件字面量：blurRadius: 50（把三元式手改成无条件也照样被抓）',
     st_chrome(blur_line=ST_UNCOND_LITERAL), ST_DESIGN, {'[门控]': 1}),
    ('阳性', '门控缺失·每帧增量：条件是 scrollDelta（§1062 明令禁止的驱动源）',
     st_chrome(blur_line=ST_DELTA), ST_DESIGN, {'[门控]': 1}),
    ('阳性', '门控缺失·假门控名：scrolledDelta 里确实含 scrolled 字样，但不是 scrolled',
     st_chrome(blur_line=ST_FAKE_GATE), ST_DESIGN, {'[门控]': 1}),
    ('阳性', '门控缺失·挂载点被删：originalStyle 里整行 blurRadius 没了',
     st_chrome(blur_line=''), ST_DESIGN, {'[门控]': 1}),
    ('阳性', '门控声明被删：契约找不到 glass-bar-scroll-gated 键（尺子失明必须响）',
     st_chrome(), ST_DESIGN_NOGATE, {'[门控]': 1}),
    ('阴性', '当前真实代码形态：三元门控 + 两态 + 半径 50',
     st_chrome(), ST_DESIGN, {}),
    ('阴性', '仓库真实 HdsChrome 全文对契约样本', None, ST_DESIGN, {}),
    ('阴性', '跨行三元式（条件在上、两分支各一行）不误抓',
     st_chrome(blur_line=ST_MULTI_LINE), ST_DESIGN, {}),
    ('阴性', '方法式 .blurRadius(this.scrolled ? R : 0) 不误抓',
     'const BAR_BLUR_RADIUS: number = 50;\n'
     '        Column()\n'
     '          .backgroundColor(Color.Transparent)\n'
     '          ' + GATE_METHOD_BODY + '\n'
     '          .expandSafeArea([SafeAreaType.SYSTEM])\n', ST_DESIGN, {}),
    ('阴性', '契约明确 gated=false 时不要求三元式（走 note，不走 fail）',
     st_chrome(blur_line=ST_UNCOND), ST_DESIGN_GATE_FALSE, {}),
    ('阴性', '契约既无 glass-blur 也无门控键、栏面也没挂 IMMERSIVE_GRADIENT_BLUR：'
             '三条判据都不适用，不许瞎报',
     st_chrome(blur_line=ST_UNCOND, immersive=False), ST_DESIGN_BARE, {}),
]


def selftest():
    """先证明**规则本身有效**（阳性抓到 / 阴性不误抓），再证明**参数拒收有效**——顺序与
    audit_motion.py / audit_fontfamily.py 同：判据坏在样本上就当场 FAIL，不留给真实代码去发现。"""
    checks = []

    def note(tag, name, detail):
        print('\n[%s] %s' % (tag, name))
        for d in detail:
            print('       ' + d)

    pos = [c for c in CASES if c[0] == '阳性']
    neg = [c for c in CASES if c[0] == '阴性']

    print('=' * 78)
    print('阳性样本 %d 类——契约禁止的写法，必须抓到' % len(pos))
    print('=' * 78)
    dup_seen = []
    for _kind, name, chrome, design, want in pos:
        hits = judge_blur(chrome, design)
        got = Counter(tag_of(h) for h in hits)
        bad = [t for t, n in want.items() if got.get(t, 0) < n]
        dup_seen.append(len(set(hits)) == len(hits))
        note('阳性', name, ['抓到 ✗ ' + h for h in hits] or ['0 命中（判据没响＝样本失效）'])
        for t, n in want.items():
            print('       判据 %s 期望 >=%d 实得 %d' % (t, n, got.get(t, 0)))
        checks.append(('阳性｜' + name, not bad and len(hits) > 0))

    print('')
    print('=' * 78)
    print('阴性样本 %d 类——契约正确写法与不适用场景，必须一条不报' % len(neg))
    print('=' * 78)
    for _kind, name, chrome, design, _want in neg:
        text = chrome if chrome is not None else read(os.path.join(ROOT, CHROME_REL))
        hits = judge_blur(text, design)
        note('阴性', name + ('（仓库真实文件）' if chrome is None else ''),
             ['误抓 !! ' + h for h in hits] or ['确认不误抓 ✓ 0 命中'])
        checks.append(('阴性｜' + name, not hits))

    # 两类同时坏时各报各的，不互相吞（半径与门控是同一段契约的两半）
    both = judge_blur(st_chrome(blur_line=ST_UNCOND, radius=24), ST_DESIGN)
    note('交叉', '半径 24 + 无条件门控（期望 [半径] 与 [门控] 各至少一条）',
         ['抓到 ✗ ' + h for h in both])
    checks.append(('阳性｜半径与门控同时坏时两类各报各的（不互相吞）',
                   any(tag_of(h) == '[半径]' for h in both)
                   and any(tag_of(h) == '[门控]' for h in both)))
    checks.append(('阳性样本内不出现两条一模一样的记录（同一条不许重复打印）', all(dup_seen)))
    twice = judge_blur(st_chrome(blur_line=ST_UNCOND + ST_UNCOND), ST_DESIGN)
    note('去重', '同一行两处无条件站点（期望 [门控] 只打一条）', ['抓到 ✗ ' + h for h in twice])
    checks.append(('阳性｜同行两处同类偏差只打一条记录', len(twice) == 1))

    # —— 真契约解析：不依赖内嵌样本，钉住「契约改成 50 + 声明门控」这两件事真的读到了 ——
    real_txt = read(DEFAULT_DESIGN) if os.path.exists(DEFAULT_DESIGN) else ''
    note('契约', '真契约 %s 解析结果' % DEFAULT_DESIGN,
         ['glass-blur=%s ｜glass-bar-scroll-gated=%s'
          % (contract_glass_blur(real_txt), contract_scroll_gated(real_txt))])
    checks.append(('阳性｜真契约解出 glass-blur=50 且 glass-bar-scroll-gated=true',
                   contract_glass_blur(real_txt) == 50
                   and contract_scroll_gated(real_txt) == 'true'))
    checks.append(('阳性｜真契约对仓库真实 HdsChrome 0 偏差',
                   not judge_blur(read(os.path.join(ROOT, CHROME_REL)), real_txt)))

    # —— 端到端与用法：参数必须真被解析，否则"某条尺 --selftest 通过"是假绿（Important-1 附项）——
    rc, out = run_tool([])
    note('运行', '真实代码 + 默认契约全尺跑', ['rc=%d ｜%s' % (rc, out.strip() or '(空)')])
    checks.append(('阴性｜仓库真实代码全尺跑 rc==0（含真契约，无参数）', rc == 0))

    fd, tmp_design = tempfile.mkstemp(suffix='.md', prefix='material-selftest-design-')
    with os.fdopen(fd, 'w', encoding='utf-8') as fh:
        fh.write(ST_DESIGN)
    fd2, tmp_uncond = tempfile.mkstemp(suffix='.ets', prefix='material-selftest-chrome-')
    with os.fdopen(fd2, 'w', encoding='utf-8') as fh:
        fh.write(st_chrome(blur_line=ST_UNCOND))
    fd3, tmp_ok = tempfile.mkstemp(suffix='.ets', prefix='material-selftest-chrome-ok-')
    with os.fdopen(fd3, 'w', encoding='utf-8') as fh:
        fh.write(st_chrome())
    try:
        rc, out = run_tool(['--design', tmp_design, '--chrome', tmp_uncond])
        note('反证', '--chrome 喂「无条件 50」的副本（仓库文件未改动）', out.strip().split('\n'))
        checks.append(('阳性｜--chrome + --design 把无条件副本喂进判据：rc==1 且报 [门控]',
                       rc == 1 and '[门控]' in out))
        rc, out = run_tool(['--design', tmp_design, '--chrome', tmp_ok])
        note('反证', '--chrome 喂「当前真实代码形态」的副本', ['rc=%d ｜%s' % (rc, out.strip()[-200:])])
        checks.append(('阴性｜--chrome 喂合规副本不报 [门控]（rc==0）',
                       rc == 0 and '[门控]' not in out))
    finally:
        for p in (tmp_design, tmp_uncond, tmp_ok):
            if os.path.exists(p):
                os.remove(p)

    missing_design = os.path.join(tempfile.gettempdir(), 'material-no-such-design.md')
    rc, out = run_tool(['--design', missing_design])
    note('用法', '契约路径指向不存在的文件', ['rc=%d ｜%s' % (rc, out.strip() or '(空)')])
    checks.append(('用法｜契约路径不存在退 2 并明确报错，无 traceback（对齐 audit_colors.py:83）',
                   rc == 2 and '找不到契约文件' in out and 'Traceback' not in out))
    rc, out = run_tool(['--chrome', os.path.join(tempfile.gettempdir(), 'material-no-such.ets')])
    checks.append(('用法｜--chrome 路径不存在退 2 并明确报错', rc == 2 and '找不到' in out))
    rc, out = run_tool(['--design'])
    checks.append(('用法｜--design 缺参数值退 2 且不崩', rc == 2 and 'Traceback' not in out))
    rc, out = run_tool(['--nope'])
    note('用法', '未知参数 --nope', ['rc=%d ｜%s' % (rc, out.strip() or '(空)')])
    checks.append(('用法｜未知参数退 2 并打用法（不再静默跑正常扫描退 0）',
                   rc == 2 and '未知参数' in out and '用法' in out))
    rc, out = run_tool(['entry/src/main/ets/design/HdsChrome.ets'])
    checks.append(('用法｜多余位置参数退 2（本尺只认 --design/--chrome/--selftest）', rc == 2))

    checks.append(('docstring 阳性类数与真数一致（防漂移）', len(pos) == DOC_POSITIVE))
    checks.append(('docstring 阴性类数与真数一致（防漂移）', len(neg) == DOC_NEGATIVE))
    checks.append(('docstring 断言总数与真数一致（防漂移）', len(checks) + 1 == DOC_ASSERTIONS))

    print('')
    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print('  %s %s' % ('OK  ' if ok else 'FAIL', name))
    if failed:
        print('selftest FAIL：%d 条不成立 → %s（尺子读数不可信，先修尺再谈过闸）'
              % (len(failed), '；'.join(failed)))
        return 1
    print('selftest PASS：%d 条成立（阳性 %d 类抓到 / 阴性 %d 类不误抓 / 交叉与去重 / 真契约解析 / '
          '端到端与用法 / 文档数字对表）' % (len(checks), len(pos), len(neg)))
    return 0


def run_tool(args):
    import subprocess
    p = subprocess.run([sys.executable, os.path.abspath(__file__)] + args,
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def usage():
    print('用法：python3 tools/audit_material.py [--selftest | --design PATH | --chrome PATH]')


def main():
    argv = sys.argv[1:]
    if argv[:1] == ['--selftest']:
        return selftest()
    design_path = DEFAULT_DESIGN
    chrome_path = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a not in ('--design', '--chrome'):
            print('未知参数：' + a)
            usage()
            return 2
        if i + 1 >= len(argv) or argv[i + 1].startswith('--'):
            print(a + ' 后面要跟一个路径（不能空着）')
            usage()
            return 2
        if a == '--design':
            design_path = argv[i + 1]
        else:
            chrome_path = argv[i + 1]
        i += 2
    if not os.path.exists(design_path):
        print('找不到契约文件：' + design_path)
        return 2
    if chrome_path and not os.path.exists(chrome_path):
        print('找不到 HdsChrome 副本：' + chrome_path)
        return 2

    design_txt = read(design_path)
    srcs = sources()
    if chrome_path:
        srcs[CHROME_REL] = read(chrome_path)
    fails = []
    notes = []
    if chrome_path:
        notes.append('[覆盖] HdsChrome 取 --chrome 指定的副本 %s（仓库文件没被改动）' % chrome_path)
    check_points(srcs, fails)
    check_selfdrawn(srcs, fails)
    check_widget(srcs, fails)
    check_single_gate(srcs, fails)
    check_blur_value(srcs, notes, fails, design_txt)
    print('扫描 %d 个 .ets，三处栏面 blur + ④材质面 + 自绘叠加 + 卡片 + 门禁外溢 + 半径/两态/门控；'
          '契约 %s（glass-blur=%s，glass-bar-scroll-gated=%s）'
          % (len(srcs), design_path, contract_glass_blur(design_txt),
             contract_scroll_gated(design_txt)))
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
