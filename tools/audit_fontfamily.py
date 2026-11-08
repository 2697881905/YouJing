#!/usr/bin/env python3
"""字族契约核对：serif 只许出现在契约/帧点名的槽位，且这些槽位必须真的带上衬线。

为什么要有这一支：前四把尺量的都是"数值对不对"（色/字号/几何/对比度），
但「中文衬线做编辑体标题、可操作的一律 HarmonyOS Sans」是这份契约的**设计语言本体**
（DESIGN.md 描述段原话：Chinese serif for editorial titles over HarmonyOS Sans for everything
operable）。而 ArkUI 的 `fontFamily` 不随字号档位自动带上——只写
`.fontSize(TypeTokens.title.size).fontWeight(700)` 编译通过、截图看着也"差不多"，
实际渲染是 sans。这条轴漏了不会报错，只会让整个 App 的编辑感静悄悄消失。

用法：
  python3 tools/audit_fontfamily.py                    # 读默认契约（DEFAULT_DESIGN）
  python3 tools/audit_fontfamily.py --design PATH      # 契约路径可传（与 audit_colors.py 同惯例）
  python3 tools/audit_fontfamily.py PATH               # 同上，位置参数
  python3 tools/audit_fontfamily.py --selftest         # 反证判据本身有效
退出码 0 = 字族表与契约一致且衬线槽位全部带上 fontFamily；
        1 = 有偏差 / 契约 serif 档没解析出来（降级兜底，见下）/ selftest 失效；
        2 = 用法错或契约文件不存在（对齐 audit_colors.py:83）。

口径（serif 档**每轮从契约现读**，不是写死的表）：
- `contract_serif_tiers()` 真解析 DESIGN.md frontmatter 的 `typography.hierarchy` 子树，
  凡带 `fontFamily: serif` 的档取其 `fontSize`/`fontWeight`。当前契约解出四档：
  display 32/700、title 21/700、day-label 21/700、body-serif 16/400；
  `display-sans`/`title-sans` 这类**没有** serif 键的档一律不进集合（否则 sans 档会被
  当 serif 档要求带衬线，是反向的假红）。其余档位必须 sans；
- 帧侧实测的 serif 槽只有三种：21/700（17 处，跨屏 1/2/3/10/12/13/14/15/16）、
  32/700（屏1 品牌字标）、16/700（屏2 一处，契约无此档，见 SERIF_SLOTS 备注）；
- 同值不同义由人判：`display` 档在屏11 是**金额 hero**，契约明写该槽换 sans，
  所以走白名单而不是改代码。

为什么这一轮非改不可（旧版是一条永远 0 红的假绿）：旧版定义了 `DESIGN`/`FRAMES` 路径常量
却**从未 open**，serif 档全部来自硬编码的 `CONTRACT_SERIF_TIERS` —— 契约 typography 段
改了、加了档、换了字族，这把尺一个都不会响，读数看着像"0 偏差"其实根本没看过契约。
现在：解析不到 serif 档就打印「尺子失明」并退 1；内置表只作兜底，走兜底必打 `[降级]`
且 **rc 非 0**，不许静默放行。selftest 里含真契约断言，改判据必须同步文案。
"""

import glob
import os
import re
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DESIGN = os.path.expanduser('~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md')
# 帧目录：SERIF_SLOTS 那张表是逐帧 CSS 解析后人工抄录进来的，本尺不 open 它
# （判据要复现的是"槽位↔代码文件"这张表，不是重新解析 45 帧）。
FRAMES = os.path.expanduser('~/Pictures/有径/有径-设计底稿-v1/frames')

# 兜底表：**只在契约解析不出 serif 档时用**，用时必打 `[降级]` 且 rc 非 0（见 main）。
# 它不是"契约的副本"，是"契约读不到时尺子还能不能自证"的最后一段路；契约 typography
# 段一改，真值走 contract_serif_tiers()，这张表跟着旧了也不影响判据。
FALLBACK_SERIF_TIERS = {'display': (32, 700), 'title': (21, 700),
                        'day-label': (21, 700), 'body-serif': (16, 400)}
# token 字段 → 契约档名（day-label 与 title 同值，工程上合成一个 token；body-serif 见 MISSING）
TOKEN_TIER = {'display': 'display', 'title': 'title'}
TOKENS_PATH = 'entry/src/main/ets/design/TypeTokens.ets'

# display/title 档挂在链上却没带 fontFamily 的白名单（必须写理由）
FAMILY_SKIP = {
    ('entry/src/main/ets/widget/pages/TodayTripCard.ets', 'title'):
        "帧 7fc1cb85 的卡片日标签是 .serif-title 21/700，档位已对齐；字族拿不到——"
        "卡片里 getUIContext/getFont/registerFont 被编译器 11706006 判 "
        "can't support form application（实测三连报错，TodayTripCard.ets:39），"
        "应用字体通道在卡片里是关的。唯一未试通道是通用字族 'serif'（不需注册），"
        "但它落到哪个字面没实拍验证过，不写没验过的属性 → 任务 #37",

    ('entry/src/main/ets/pages/ExpensePage.ets', 'display'):
        '契约 §typography 备注：金额 hero 与 display 同档但 family 换 sans（DESIGN hierarchy '
        '另有 display-sans 一档），此处是 ¥ 金额，不是编辑体标题',
}

# 帧声明的 serif 槽位 → 落在哪个代码文件（槽位来自逐帧 CSS 解析，非估计）
SERIF_SLOTS = [
    ('屏1', '有径（品牌字标 32/700）', 'entry/src/main/ets/pages/YoujingStartPage.ets'),
    ('屏1', 'Day 1 · 京都 东山步道（预览卡 21/700）', 'entry/src/main/ets/pages/YoujingStartPage.ets'),
    ('屏2', '开启一次有迹可循的旅程（21/700）', 'entry/src/main/ets/pages/TripInputPage.ets'),
    ('屏3', '这趟想怎么过？（question-card 21/700）', 'entry/src/main/ets/pages/PreferenceQAPage.ets'),
    ('屏3b', '每天想排多满？（21/700）', 'entry/src/main/ets/pages/PreferenceQAPage.ets'),
    ('屏6', '正在为你规划 5 天行程（21/700）', 'entry/src/main/ets/pages/GeneratingPage.ets'),
    # 屏7 / 屏12b / 屏5 三个「标题槽」2026-11-07 起按有据 EmptyState/错误态规格改为
    # headline 18/600 serif（帧的 21/700 是历史取证），移入 SLOT_PENDING 说明，不再用
    # 「文件里有没有 title/display 档的衬线 Text」这个旧判据卡它们。

    ('屏8', 'Day 1 · 6月10日 周二（day-label 21/700）', 'entry/src/main/ets/pages/ItineraryPage.ets'),
    ('屏9', 'Day 1 · 6月10日 周二（编辑态 21/700）', 'entry/src/main/ets/pages/EditItineraryPage.ets'),
    ('屏10', '伏见稻荷大社（节点名 21/700）', 'entry/src/main/ets/pages/ItineraryPage.ets'),
    ('屏12', '京都 / 东京 / 镰仓与箱根（目的地 21/700）', 'entry/src/main/ets/pages/TripsPage.ets'),
    ('屏14', '让行程走到系统里（21/700）', 'entry/src/main/ets/pages/ItineraryPage.ets'),
    ('屏15', '岚山竹林（当前节点 21/700）', 'entry/src/main/ets/pages/OnTripPage.ets'),
    ('屏16', '分享这份行程（21/700）', 'entry/src/main/ets/pages/SharePage.ets'),
]
# 帧声明但按新契约改档的槽：报告不卡构建，理由写死在下面
# 帧声明但工程上暂缺的槽：报告不卡构建，理由写死在这里
SLOT_PENDING = {
    ('屏7', '第 3 天没排通（21/700）'):
        '2026-11-07 全量对齐：错误态主句按有据规格改为 headline 18/600 serif，'
        '帧里 21/700 是历史取证；新档位仍是衬线，只是不再走 title 档，故旧判据不适用',
    ('屏12b', '还没有行程（空态 21/700）'):
        '2026-11-07 全量对齐：空态主句按有据 EmptyState 改为 headline 18/600 serif，'
        '图形档 48→44；帧里 21/700 是历史取证，旧判据不适用',
    ('屏5', '片区名（SpotPick/AreaMore 标题 21/700）'):
        '2026-11-07 全量对齐：AreaMore 空态主句按有据 EmptyState 改为 headline 18/600 serif，'
        '帧里 21/700 是历史取证，旧判据不适用',
    ('屏13', 'Day 2 · 6月11日（卡片日标签 21/700 serif）'):
        '档位已对齐 21/700；衬线拿不到：卡片里 getUIContext/getFont/registerFont '
        "被编译器 11706006 判 can't support form application（实测三连报错），"
        '应用字体通道关着；通用字族 serif 也实测判死——能编译但真机解析成黑体'
        '（对照实验：屏15 已知衬线标题换成 serif 后裁图无衬脚、行盒 94px→77px）。'
        '两条通道都关，卡片只对齐 21/700 档位。#37 已结案（实测限制，不是待办）',
}


def chain_has(lines, idx):
    """只在这条属性链内找 fontFamily：链上的修饰行与 .fontSize 同行缩进，
    缩进一变（下一个组件/块收尾）就停。窗口式往下扫 6~7 行会吃到**兄弟组件**的
    fontFamily，把真漏判成通过——种子实测踩过一次，规则②和③同时失明。"""
    base = len(lines[idx]) - len(lines[idx].lstrip())
    for j in range(idx + 1, len(lines)):
        ln = lines[j]
        st = ln.strip()
        if not st or st.startswith('//') or st.startswith('*'):
            continue
        indent = len(ln) - len(ln.lstrip())
        if indent != base or not ln.lstrip().startswith('.'):
            return False
        if 'fontFamily' in ln:
            return True
    return False


def hierarchy_block(txt):
    """切出 `typography: → hierarchy:` 子树的原文（含 4 空格档名行）。

    只在这段里匹配，不拿整篇 YAML 硬扫：4 空格键在别的段同样合法出现，那里只要
    沾上 "serif" 字样（如 `serif-family` 的值、组件备注）就会被收进衬线档集合，
    那是**假红**的一侧。契约里 hierarchy 只有一个，切法按缩进深浅一层即可。"""
    lines = txt.split('\n')
    for i, ln in enumerate(lines):
        if re.match(r'^\s*hierarchy:\s*$', ln):
            depth = len(ln) - len(ln.lstrip())
            block = []
            for j in range(i + 1, len(lines)):
                s = lines[j]
                if s.strip() and len(s) - len(s.lstrip()) <= depth:
                    break
                block.append(s)
            return '\n'.join(block) + '\n'
    return ''


def contract_serif_tiers(txt):
    """真读契约：hierarchy 子树里凡带 `fontFamily: serif` 的档 → 档名: (size, weight)。

    简报给的片段里写的是 `weight.group(2)`，那是笔误（只有一个捕获组），这里按
    `group(1)` 取；其余逐字照用（四空格档名 / 六空格子行，对着契约 110-199 行的真实缩进）。
    解析结果实测：display 32/700、title 21/700、body-serif 16/400、day-label 21/700 四档，
    `display-sans`/`title-sans`/`body` 等无 serif 键的档一律不进集合。"""
    out = {}
    for m in re.finditer(r'^    ([a-z][a-z0-9-]*):\n((?:      .*\n)+)',
                         hierarchy_block(txt), re.M):
        body = m.group(2)
        if 'serif' not in body:
            continue
        size = re.search(r'fontSize: "(\d+)px"', body)
        weight = re.search(r'fontWeight: (\d+)', body)
        if size and weight:
            out[m.group(1)] = (int(size.group(1)), int(weight.group(1)))
    return out


def tiers_text(tiers):
    return '、'.join('%s %d/%d' % (k, v[0], v[1]) for k, v in sorted(tiers.items()))


def check_token_table(tokens, tiers):
    """判据①：TypeTokens 的档位数值/字族必须等于契约**本轮解析出来的** serif 档。"""
    fails, notes = [], []
    rows = re.findall(r'(\w+):\s*\{\s*family:\s*(FAMILY_\w+),\s*size:\s*(\d+),'
                      r'\s*weight:\s*(\d+)', tokens)
    fams = {r[0]: (r[1], int(r[2]), int(r[3])) for r in rows}
    got_serif = {k for k, v in fams.items() if v[0] == 'FAMILY_SERIF'}
    for tier, cname in TOKEN_TIER.items():
        if cname not in tiers:
            continue
        if tier not in got_serif:
            fails.append(f'[token] 契约档 {cname} 是 serif，TypeTokens.{tier} 却不是')
        elif fams[tier][1:] != tiers[cname]:
            fails.append(f'[token] TypeTokens.{tier} = {fams[tier][1]}/{fams[tier][2]}，'
                         f'契约 {cname} 是 {tiers[cname][0]}/{tiers[cname][1]}')
    for t in sorted(got_serif):
        if t not in tiers:
            fails.append(f'[token] TypeTokens.{t} 设成 serif，但契约 hierarchy 里没有 {t} '
                         f'这个 serif 档（该档是 sans）')
    bs = tiers.get('body-serif')
    if bs and not any(v[0] == 'FAMILY_SERIF' and v[1:] == bs for v in fams.values()):
        notes.append(f'[token] 契约有 body-serif（{bs[0]}/{bs[1]} serif）一档，token 表没有——'
                     '13 帧浅色档实测 serif 只出现在 21/700 与 32/700 两种，16/400 一处没有，'
                     '所以这档暂无消费方（与 geometry 尺的 LAYOUT_SKIP 同一口径）')
    return fails, notes


def scan_source(lines, tiers):
    """判据②的源码侧：serif 档的 .fontSize 链上有没有真的 .fontFamily。

    返回 (带字族的 [(行号, 档名)], 漏字族的 [(行号, 档名)])；白名单判定留给调用方，
    这样 selftest 喂假源码时能直接看到"漏"本身，不被 FAMILY_SKIP 吞掉。"""
    hits, misses = [], []
    for i, ln in enumerate(lines):
        m = re.search(r'\.fontSize\((?:TypeTokens|tokens)\.(\w+)\.size\)', ln)
        if not m or m.group(1) not in TOKEN_TIER:
            continue
        tier = m.group(1)
        if TOKEN_TIER[tier] not in tiers:
            continue  # 契约本轮不认它是 serif 档 → 不要求带衬线
        # 同一行写完链式（`.fontSize(x).fontFamily(y)`）也算带上了：仓里确有这种写法
        # （SpotPickPage.ets:294 同行三连接），chain_has 只看后续行，不补这一下就是一条假红。
        has = 'fontFamily' in ln or chain_has(lines, i)
        (hits if has else misses).append((i + 1, tier))
    return hits, misses


# ---------------------------------------------------------------- selftest 样本
# 契约样本是 DESIGN.md hierarchy 段的**逐字删节**（110-199 行那套 2/4/6 空格缩进）。
# 内嵌一份是故意的：selftest 不许依赖 ~/Pictures 在不在。
ST_CONTRACT = '''colors:
  ink: "#1B1B1F"
typography:
  font-family: "'HarmonyOS Sans', ui-sans-serif, system-ui, sans-serif"
  serif-family: "'Noto Serif SC', 'Songti SC', serif"
  hierarchy:
    display:
      fontFamily: "serif"
      fontSize: "32px"
      fontWeight: 700
      lineHeight: "44px"
      letterSpacing: "0"
    display-sans:
      fontSize: "32px"
      fontWeight: 700
      lineHeight: "40px"
      letterSpacing: "0"
    title:
      fontFamily: "serif"
      fontSize: "21px"
      fontWeight: 700
      lineHeight: "32px"
      letterSpacing: "0"
    title-sans:
      fontSize: "21px"
      fontWeight: 650
      lineHeight: "28px"
      letterSpacing: "0"
    headline:
      fontSize: "18px"
      fontWeight: 600
      lineHeight: "24px"
      letterSpacing: "0"
    body:
      fontSize: "16px"
      fontWeight: 400
      lineHeight: "24px"
      letterSpacing: "0"
    body-serif:
      fontFamily: "serif"
      fontSize: "16px"
      fontWeight: 400
      lineHeight: "26px"
      letterSpacing: "0"
    day-label:
      fontFamily: "serif"
      fontSize: "21px"
      fontWeight: 700
      lineHeight: "28px"
      letterSpacing: "0"
      note: "Day 3 · 6月12日 周四"
rounded:
  card: "20px"
'''

# 反证「尺子失明」这条路的样本：整段 typography 删掉（契约副本上删，真契约一个字不动）
ST_CONTRACT_NO_TYPO = '''colors:
  ink: "#1B1B1F"
rounded:
  card: "20px"
'''

# 另一条失明路：hierarchy 还在，但档名缩进被改成 3 空格 —— 判据认的是 4/6 空格这套
ST_CONTRACT_BAD_INDENT = ST_CONTRACT.replace('    display:\n      fontFamily',
                                             '   display:\n      fontFamily')

SRC_LEAK = '''  Column() {
    Text('Day 1 · 6月10日 周二')
      .fontSize(TypeTokens.title.size)
      .fontWeight(700)
      .fontColor(ColorTokens.ink)
  }
'''

# 兄弟组件带 fontFamily，绝不能替上一条链"顶上"（旧注释里的窗口式扫法就栽在这）
SIBLING_TRAP = '''  Column() {
    Text('Day 1 · 6月10日 周二')
      .fontSize(TypeTokens.title.size)
      .fontWeight(700)
    Text('伏见稻荷大社')
      .fontSize(TypeTokens.headline.size)
      .fontFamily(TypeTokens.headline.family)
  }
'''

SRC_CHAIN_OK = '''  Column() {
    Text('Day 1 · 6月10日 周二')
      .fontSize(TypeTokens.title.size)
      .fontWeight(TypeTokens.title.weight)
      .fontFamily(TypeTokens.title.family)
      .fontColor(ColorTokens.ink)
  }
'''

SRC_COMMENT_OK = '''  Column() {
    Text('京都 / 东京 / 镰仓与箱根')
      .fontSize(TypeTokens.title.size)

      // 注释与空行在链内是透明的（与 audit_a11y_name.py 同一口径）
      .fontFamily(TypeTokens.title.family)
      .fontColor(ColorTokens.ink)
  }
'''

# sans 档不要求衬线：抓它就是假红
SRC_SANS = '''  Column() {
    Text('09:30')
      .fontSize(TypeTokens.headline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.ink)
  }
'''

SRC_INLINE = '''  Column() {
    Text('伏见稻荷大社')
      .fontSize(TypeTokens.title.size).fontFamily(TypeTokens.title.family)
      .fontWeight(700)
  }
'''

SRC_CASES = [
    ('假源码「serif 档未带 .fontFamily」必须命中 [漏字族]', SRC_LEAK, 1, 0),
    ('兄弟组件的 fontFamily 不算上一条链的（链内扫描未退化）', SIBLING_TRAP, 1, 0),
    ('契约正确写法（链内下一行带字族）不误抓', SRC_CHAIN_OK, 0, 1),
    ('链中夹注释/空行仍认得到字族（不误抓）', SRC_COMMENT_OK, 0, 1),
    ('同行链式一次写完 .fontSize().fontFamily()（仓里确有此写法）不误抓', SRC_INLINE, 0, 1),
    ('sans 档不要求带衬线（不误抓）', SRC_SANS, 0, 0),
]

TOKENS_OK = '''export const TypeTokens: TypeTokensType = {
  display: { family: FAMILY_SERIF, size: 32, weight: 700, lineHeight: 44 },
  title: { family: FAMILY_SERIF, size: 21, weight: 700, lineHeight: 32 },
  headline: { family: FAMILY_SANS, size: 18, weight: 600, lineHeight: 24 }
};
'''

TOKENS_BAD_SIZE = '''export const TypeTokens: TypeTokensType = {
  display: { family: FAMILY_SERIF, size: 32, weight: 700, lineHeight: 44 },
  title: { family: FAMILY_SERIF, size: 24, weight: 700, lineHeight: 32 }
};
'''

TOKENS_BAD_FAMILY = '''export const TypeTokens: TypeTokensType = {
  display: { family: FAMILY_SERIF, size: 32, weight: 700, lineHeight: 44 },
  title: { family: FAMILY_SANS, size: 21, weight: 700, lineHeight: 32 }
};
'''

TOKENS_EXTRA_SERIF = '''export const TypeTokens: TypeTokensType = {
  display: { family: FAMILY_SERIF, size: 32, weight: 700, lineHeight: 44 },
  title: { family: FAMILY_SERIF, size: 21, weight: 700, lineHeight: 32 },
  headline: { family: FAMILY_SERIF, size: 18, weight: 600, lineHeight: 24 }
};
'''

TOKEN_CASES = [
    ('契约正确 token 表不误抓', TOKENS_OK, 0),
    ('token 字号偏离契约（21→24）必报', TOKENS_BAD_SIZE, 1),
    ('契约 serif 档在 token 表里掉成 sans 必报', TOKENS_BAD_FAMILY, 1),
    ('token 把契约的 sans 档设成 serif 必报', TOKENS_EXTRA_SERIF, 1),
]


def selftest():
    """先证明**规则本身有效**，再谈契约解析——顺序不能倒，否则分不清"规则坏"还是"解析坏"。"""
    checks = []

    def note(tag, name, detail):
        print('\n[%s] %s' % (tag, name))
        for d in detail:
            print('       ' + d)

    # —— 契约解析：真文件 + 内嵌样本 + 「删掉 typography 段」三路 ——
    real_txt = ''
    if os.path.exists(DEFAULT_DESIGN):
        real_txt = open(DEFAULT_DESIGN, encoding='utf-8').read()
    real = contract_serif_tiers(real_txt) if real_txt else {}
    checks.append(('阳性｜真契约解出四档 serif 且数值逐档对上',
                   all(real.get(k) == v for k, v in FALLBACK_SERIF_TIERS.items())))
    note('契约', '真契约 %s 解析结果' % DEFAULT_DESIGN, [tiers_text(real) or '（文件不存在）'])
    checks.append(('阴性｜display-sans / title-sans / body 这类无 serif 键的档不进集合',
                   not ({'display-sans', 'title-sans', 'body', 'headline'} & set(real))))
    st = contract_serif_tiers(ST_CONTRACT)
    checks.append(('阳性｜内嵌 hierarchy 样本解出同样四档（不依赖 ~/Pictures）',
                   st == {'display': (32, 700), 'title': (21, 700),
                          'day-label': (21, 700), 'body-serif': (16, 400)}))
    note('样本', '内嵌契约样本解析结果', [tiers_text(st)])
    checks.append(('阳性｜整段删掉 typography 后解析为空集（尺子失明的触发条件）',
                   contract_serif_tiers(ST_CONTRACT_NO_TYPO) == {}))
    bad = contract_serif_tiers(ST_CONTRACT_BAD_INDENT)
    note('契约', '把 display 档名缩进 4→3 空格后的解析结果', [tiers_text(bad) or '（空集）'])
    checks.append(('阳性｜档名缩进 4→3 空格后**那一档**从集合里掉出去（判据认 4/6 空格）',
                   'display' not in bad and bad.get('title') == (21, 700)))
    checks.append(('阴性｜typography 之上的 serif-family 行不产生档（子树切得干净）',
                   'serif-family' not in st and 'font-family' not in st))

    # —— 判据②：serif 档未带 .fontFamily 必须命中 [漏字族] ——
    for name, text, want_miss, want_hit in SRC_CASES:
        hits, misses = scan_source(text.split('\n'), real or FALLBACK_SERIF_TIERS)
        detail = ['漏字族 ✗ L%d %s' % (ln, tier) for ln, tier in misses]
        detail += ['带字族 ✓ L%d %s' % (ln, tier) for ln, tier in hits]
        note('源码', '%s（期望漏 %d / 带 %d）' % (name, want_miss, want_hit),
             detail or ['两条都 0（该样本不含 serif 档链）'])
        checks.append(('判据②｜' + name, len(misses) == want_miss and len(hits) == want_hit))
    # 逐条硬断言（上面的条数之外，再钉住"抓到的是哪一档、第几行"）
    h, m = scan_source(SRC_LEAK.split('\n'), real or FALLBACK_SERIF_TIERS)
    checks.append(('阳性｜喂「serif 档未带 .fontFamily」的假源码必须命中 title 档',
                   m == [(3, 'title')] and not h))
    h, m = scan_source(SIBLING_TRAP.split('\n'), real or FALLBACK_SERIF_TIERS)
    checks.append(('阳性｜兄弟组件的 fontFamily 不算数（链内扫描未退化回窗口式）',
                   m == [(3, 'title')] and not h))
    h, m = scan_source(SRC_LEAK.split('\n'), {})
    checks.append(('阴性｜契约本轮没有 serif 档时不要求带衬线（判据跟着契约走，不写死）',
                   not m and not h))

    # —— 判据①：token 表 vs 契约 ——
    for name, text, want in TOKEN_CASES:
        fails, _ = check_token_table(text, real or FALLBACK_SERIF_TIERS)
        note('token', '%s（期望 %d 条）' % (name, want),
             ['抓到 ✗ ' + f for f in fails] or ['0 命中（契约正确写法不误抓）'])
        checks.append(('判据①｜' + name, len(fails) == want))
    real_tokens = open(os.path.join(ROOT, TOKENS_PATH), encoding='utf-8').read()
    fails, _notes = check_token_table(real_tokens, real)
    checks.append(('阴性｜仓库真实 TypeTokens 对真契约 0 偏差', not fails))

    # —— 降级与用法：非静默，且与 audit_colors.py:83 惯例一致 ——
    fd, tmp = tempfile.mkstemp(suffix='.md', prefix='fontfamily-selftest-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as fh:
            fh.write(ST_CONTRACT_NO_TYPO)
        rc, out = run_tool(['--design', tmp])
        note('降级', '契约副本删掉 typography 段后的运行结果', out.strip().split('\n'))
        checks.append(('阳性｜契约无 serif 档时打印「尺子失明」+ [降级] 且 rc==1',
                       '尺子失明' in out and '[降级]' in out and rc == 1))
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    rc, out = run_tool(['--design', os.path.join(tempfile.gettempdir(),
                                                 'fontfamily-no-such-file.md')])
    note('用法', '契约路径指向不存在的文件', ['rc=%d ｜%s' % (rc, out.strip() or '(空)')])
    checks.append(('用法｜路径不存在时退 2 并明确报错，无 traceback（对齐 audit_colors.py:83）',
                   rc == 2 and '找不到契约文件' in out and 'Traceback' not in out))
    rc, out = run_tool(['--design'])
    checks.append(('用法｜--design 缺参数退 2 且不崩', rc == 2 and 'Traceback' not in out))
    rc, out = run_tool(['a', 'b'])
    checks.append(('用法｜多余参数退 2 并打用法', rc == 2))

    print('')
    failed = [n for n, ok in checks if not ok]
    for n, ok in checks:
        print('  %s %s' % ('OK  ' if ok else 'FAIL', n))
    if failed:
        print('selftest FAIL：%d 条不成立 → %s（尺子读数不可信，先修尺再谈过闸）'
              % (len(failed), '；'.join(failed)))
        return 1
    print('selftest PASS：%d 条成立（判据有效性 + 契约真解析 + 降级与用法三条路径，逐条见上）'
          % len(checks))
    return 0


def run_tool(args):
    import subprocess
    p = subprocess.run([sys.executable, os.path.abspath(__file__)] + args,
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def usage():
    print('用法：python3 tools/audit_fontfamily.py [--selftest | --design PATH | PATH]')


def main():
    argv = sys.argv[1:]
    if argv[:1] == ['--selftest']:
        return selftest()
    if argv[:1] == ['--design']:
        if len(argv) != 2:
            usage()
            return 2
        design_path = argv[1]
    elif len(argv) == 1:
        design_path = argv[0]
    elif len(argv) > 1:
        usage()
        return 2
    else:
        design_path = DEFAULT_DESIGN

    if not os.path.exists(design_path):
        print('找不到契约文件：' + design_path)
        return 2
    tiers = contract_serif_tiers(open(design_path, encoding='utf-8').read())
    degraded = False
    if not tiers:
        print(f'[契约解析] 没从 {design_path} 抓到 serif 档，尺子失明'
              '（typography.hierarchy 段缺失、改名或缩进不是 4/6 空格）')
        print('[降级] 使用内置 serif 档兜底——内置表不是契约，本轮退出码非 0，不静默放行')
        tiers = dict(FALLBACK_SERIF_TIERS)
        degraded = True
    print(f'[{"契约" if not degraded else "兜底"}] {design_path} '
          f'{"解出" if not degraded else "没读进来，本轮按内置表判"} serif 档 {len(tiers)} 个：'
          f'{tiers_text(tiers)}')

    fails = []
    notes = []
    tokens = open(os.path.join(ROOT, TOKENS_PATH), encoding='utf-8').read()
    f1, n1 = check_token_table(tokens, tiers)
    fails += f1
    notes += n1

    files = sorted(glob.glob(os.path.join(ROOT, 'entry/src/main/ets/pages/*.ets')) +
                   glob.glob(os.path.join(ROOT, 'entry/src/main/ets/components/*.ets')) +
                   glob.glob(os.path.join(ROOT, 'entry/src/main/ets/widget/**/*.ets'), recursive=True))
    serif_sites = {}
    for path in files:
        rel = os.path.relpath(path, ROOT)
        lines = open(path, encoding='utf-8').read().split('\n')
        hits, misses = scan_source(lines, tiers)
        for ln, tier in hits:
            serif_sites.setdefault(rel, []).append((ln, tier))
        for ln, tier in misses:
            if (rel, tier) not in FAMILY_SKIP:
                fails.append(f'[漏字族] {rel}:{ln} 用了 serif 档 {tier} 却没写 .fontFamily——'
                             f'ArkUI 不会随档位带上衬线，这里实际渲染是 sans')
            else:
                notes.append(f'[已释明] {rel}:{ln} {tier} 档不带上衬线：'
                             f'{FAMILY_SKIP[(rel, tier)]}')
    # ③ 帧声明的每个 serif 槽，映射的代码文件里要真有一处衬线
    for screen, slot, rel in SERIF_SLOTS:
        if rel not in serif_sites:
            fails.append(f'[槽位漏做] {screen} 帧声明 serif 槽「{slot}」，'
                         f'{rel} 里却没有任何带衬线的 Text')
    for (screen, slot), reason in SLOT_PENDING.items():
        notes.append(f'[槽位待补] {screen}「{slot}」：{reason}')

    print(f'扫描 {len(files)} 个界面文件；带衬线的 Text {sum(len(v) for v in serif_sites.values())} 处，'
          f'帧声明 serif 槽 {len(SERIF_SLOTS)} 处已对表')
    for n in notes:
        print('  · ' + n)
    for f in fails:
        print('  ✗ ' + f)
    if degraded:
        if fails:
            print(f'字族偏差 {len(fails)} 处（且本轮契约没读进来，判据按内置兜底表跑，读数不可信）')
        else:
            print('字族偏差 0 处（**不可信**：契约没读进来，本轮按内置兜底表判）')
        print('降级运行：rc 非 0——兜底表不等于契约，静默放行就是这条尺原来的病')
        return 1
    if not fails:
        print('字族偏差 0 处')
        return 0
    print(f'字族偏差 {len(fails)} 处')
    return 1


if __name__ == '__main__':
    sys.exit(main())
