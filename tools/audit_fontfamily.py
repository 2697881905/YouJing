#!/usr/bin/env python3
"""字族契约核对：serif 只许出现在契约/帧点名的槽位，且这些槽位必须真的带上衬线。

为什么要有这一支：前四把尺量的都是"数值对不对"（色/字号/几何/对比度），
但「中文衬线做编辑体标题、可操作的一律 HarmonyOS Sans」是这份契约的**设计语言本体**
（DESIGN.md 描述段原话：Chinese serif for editorial titles over HarmonyOS Sans for everything
operable）。而 ArkUI 的 `fontFamily` 不随字号档位自动带上——只写
`.fontSize(TypeTokens.title.size).fontWeight(700)` 编译通过、截图看着也"差不多"，
实际渲染是 sans。这条轴漏了不会报错，只会让整个 App 的编辑感静悄悄消失。

用法：python3 tools/audit_fontfamily.py
退出码 0 = 字族表与契约一致且衬线槽位全部带上 fontFamily；1 = 有偏差。

口径：
- 契约 serif 档（hierarchy 里 fontFamily: serif）：display 32/700、title 21/700、
  day-label 21/700、body-serif 16/400；其余档位必须 sans；
- 帧侧实测的 serif 槽只有三种：21/700（17 处，跨屏 1/2/3/10/12/13/14/15/16）、
  32/700（屏1 品牌字标）、16/700（屏2 一处，契约无此档，见 SERIF_SLOTS 备注）；
- 同值不同义由人判：`display` 档在屏11 是**金额 hero**，契约明写该槽换 sans，
  所以走白名单而不是改代码。
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.expanduser('~/Pictures/有径/有径-设计底稿-v1/docs/DESIGN.md')
FRAMES = os.path.expanduser('~/Pictures/有径/有径-设计底稿-v1/frames')

# 契约 hierarchy：档名 → (family, size, weight)
CONTRACT_SERIF_TIERS = {'display': (32, 700), 'title': (21, 700),
                        'day-label': (21, 700), 'body-serif': (16, 400)}
# token 字段 → 契约档名（day-label 与 title 同值，工程上合成一个 token；body-serif 见 MISSING）
TOKEN_TIER = {'display': 'display', 'title': 'title'}

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
    ('屏7', '第 3 天没排通（21/700）', 'entry/src/main/ets/pages/GenerateFailedPage.ets'),
    ('屏8', 'Day 1 · 6月10日 周二（day-label 21/700）', 'entry/src/main/ets/pages/ItineraryPage.ets'),
    ('屏9', 'Day 1 · 6月10日 周二（编辑态 21/700）', 'entry/src/main/ets/pages/EditItineraryPage.ets'),
    ('屏10', '伏见稻荷大社（节点名 21/700）', 'entry/src/main/ets/pages/ItineraryPage.ets'),
    ('屏12', '京都 / 东京 / 镰仓与箱根（目的地 21/700）', 'entry/src/main/ets/pages/TripsPage.ets'),
    ('屏12b', '还没有行程（空态 21/700）', 'entry/src/main/ets/pages/TripsPage.ets'),
    ('屏14', '让行程走到系统里（21/700）', 'entry/src/main/ets/pages/ItineraryPage.ets'),
    ('屏15', '岚山竹林（当前节点 21/700）', 'entry/src/main/ets/pages/OnTripPage.ets'),
    ('屏16', '分享这份行程（21/700）', 'entry/src/main/ets/pages/SharePage.ets'),
    ('屏5', '片区名（SpotPick/AreaMore 标题 21/700）', 'entry/src/main/ets/pages/AreaMorePage.ets'),
]
# 帧声明但工程上暂缺的槽：报告不卡构建，理由写死在这里
SLOT_PENDING = {
    ('屏13', 'Day 2 · 6月11日（卡片日标签 21/700 serif）'):
        '档位已对齐 21/700；衬线拿不到：卡片里 getUIContext/getFont/registerFont '
        "被编译器 11706006 判 can't support form application（实测三连报错），"
        '应用字体通道在卡片里是关的；通用字族 serif 未实拍，不写没验过的属性（任务 #37）',
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


def main():
    fails = []
    notes = []
    tokens_path = 'entry/src/main/ets/design/TypeTokens.ets'
    tokens = open(os.path.join(ROOT, tokens_path), encoding='utf-8').read()
    # ① token 表 vs 契约 hierarchy
    rows = re.findall(r'(\w+):\s*\{\s*family:\s*(FAMILY_\w+),\s*size:\s*(\d+),'
                      r'\s*weight:\s*(\d+)', tokens)
    fams = {r[0]: (r[1], int(r[2]), int(r[3])) for r in rows}
    got_serif = {k for k, v in fams.items() if v[0] == 'FAMILY_SERIF'}
    for tier, cname in TOKEN_TIER.items():
        if cname not in CONTRACT_SERIF_TIERS:
            continue
        if tier not in got_serif:
            fails.append(f'[token] 契约档 {cname} 是 serif，TypeTokens.{tier} 却不是')
        elif fams[tier][1:] != CONTRACT_SERIF_TIERS[cname]:
            fails.append(f'[token] TypeTokens.{tier} = {fams[tier][1]}/{fams[tier][2]}，'
                         f'契约 {cname} 是 {CONTRACT_SERIF_TIERS[cname][0]}/{CONTRACT_SERIF_TIERS[cname][1]}')
    for t in got_serif:
        if t not in TOKEN_TIER.values() and t not in ('display', 'title'):
            fails.append(f'[token] TypeTokens.{t} 设成 serif，但契约该档是 sans')
    if not any(v[0] == 'FAMILY_SERIF' and v[1] == 16 for v in fams.values()):
        notes.append('[token] 契约有 body-serif（16/400 serif）一档，token 表没有——'
                     '13 帧浅色档实测 serif 只出现在 21/700 与 32/700 两种，16/400 一处没有，'
                     '所以这档暂无消费方（与 geometry 尺的 LAYOUT_SKIP 同一口径）')

    files = sorted(glob.glob(os.path.join(ROOT, 'entry/src/main/ets/pages/*.ets')) +
                   glob.glob(os.path.join(ROOT, 'entry/src/main/ets/components/*.ets')) +
                   glob.glob(os.path.join(ROOT, 'entry/src/main/ets/widget/**/*.ets'), recursive=True))
    serif_sites = {}
    # ② serif 档必须显式带上 fontFamily
    for path in files:
        rel = os.path.relpath(path, ROOT)
        lines = open(path, encoding='utf-8').read().split('\n')
        for i, ln in enumerate(lines):
            m = re.search(r'\.fontSize\((?:TypeTokens|tokens)\.(\w+)\.size\)', ln)
            if not m or m.group(1) not in TOKEN_TIER:
                continue
            tier = m.group(1)
            if chain_has(lines, i):
                serif_sites.setdefault(rel, []).append((i + 1, tier))
            elif (rel, tier) not in FAMILY_SKIP:
                fails.append(f'[漏字族] {rel}:{i + 1} 用了 serif 档 {tier} 却没写 .fontFamily——'
                             f'ArkUI 不会随档位带上衬线，这里实际渲染是 sans')
            else:
                notes.append(f'[已释明] {rel}:{i + 1} {tier} 档不带上衬线：'
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
    if not fails:
        print('字族偏差 0 处')
        return 0
    for f in fails:
        print('  ✗ ' + f)
    print(f'字族偏差 {len(fails)} 处')
    return 1


if __name__ == '__main__':
    sys.exit(main())
