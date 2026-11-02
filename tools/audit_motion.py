#!/usr/bin/env python3
r"""动效尺：时长/曲线只准走 MotionTokens/MotionCurves；.animation() 必须紧贴 .stateStyles() 之前。

为什么要有这一支：全站今天**零动画**（`.animation(` / `animateTo(` / `.transition(` 各 0 处），
所以这把尺不抓现行、只防回归——契约 v2 C4 已把 motion 五档钉成
press140 / control220 / container320 / shimmer1200 / pressScale0.97，曲线钉成 MotionCurves 三条
自定义贝塞尔。P2 建 BaseCard/Pressable、P3 建转场工厂之后，任何页面里自己写死的毫秒数或
Curve 枚举都是「页面各自调参」，正是 §0 口径要消灭的形态；而它一旦进了页面，肉眼极难发现
（数值不改变静态像素，只在动的那 200ms 里对或错）。

三条判据：
- [裸时长] `duration:` / `delay:` 后面跟的不是 `MotionTokens.*` → 报。**默认全报**，只有下面
  三张写明原因的豁免名单（命中数会随结果打印出来，不做无声豁免）：
    W1 提示停留时长：`showToast(` / `getPromptAction(` / `show*Dialog(` 调用的括号区间内
       （`duration` 在这里是「toast 显示几秒」，全站现存 16 处，不是动效时长）；
    W2 类型声明位：冒号右边是**类型名**（`duration: number;` / `delay?: number` /
       `const duration: number = ...`）——接口成员与带标注的声明，不是毫秒值；
    W3 数据层分钟数：`data/` `ai/` `mock/` `model/` 下的 `duration` 是 `Transport.duration`
       （model/Trip.ets 注释原文「耗时，分钟」），且值取自别的字段/变量时才豁免；
       这些目录里**硬写数字**（`duration: 400`）或**落在动效算子括号区间内**照样报。
  上一版的豁免是「不在四个动效算子花括号内就免」——那是无边界豁免：三元
  `duration: this.on ? 320 : 220`、变量 `duration: pressMs`、helper 预定义
  `AnimateParam = { duration: 400 }`（P3 的 buildPageTransition 工厂正是这形状）、
  `keyframeAnimateTo` 帧内时长、`marquee`/`ImageAnimator` 五类真裸毫秒全部静默通过。
- [枚举曲线] `curve : Curve.xxx`（冒号前后空格都认）→ 必须写 MotionCurves.*（契约 curve-* 全是
  自定义贝塞尔，ArkUI 的 Curve 枚举里根本没有 cubic-bezier(0.2, 0.8, 0.2, 1) 这一档，
  写枚举就是静默换曲线）；
- [顺序] `.stateStyles(` 的**上一条属性**不是 `.animation(` → 顺序倒置（或有状态样式却没挂动画）。
  这条来自有据实测的 ArkUI 坑：`.animation()` 声明在它作用属性之后不生效，
  写成 `.stateStyles().animation()` 等于「按下没反馈而代码看着没错」。
  判据按「上一条属性」而不是「上一行字面」——跨行 `.animation({ … })` 块的后继闭括号、
  夹在中间的空行与注释行都算透明，`.animation().stateStyles()` 同行链也算相邻；
  注释文本里提到 `.stateStyles(` 不触发判据（注释与字符串先抹成空格）。

结构判据一律在 **mask 之后的文本**上算：`mask()` 与 tools/audit_button_width.py:54 同一套
（字符串字面量与注释抹成空格、长度不变，R20：同目录两把尺早就把这两个坑写成规矩，复用而不是重造），
只多修一处——反引号模板串**跨行**也要抹，否则 ``Text('{ label: \'{' }')`` 与多行 SQL 模板里的
`{` 会污染括号/花括号深度跟踪（M-3），让块「永不闭合」。

selftest 共 21 条断言 = 阳性 9 类 + 阴性 9 类 + 3 条「本 docstring 写的数字与真数一致」防漂移
（M-2 的成因就是数字靠手数）。阳性证明抓得到、阴性证明**契约正确写法不误抓**——上一版
三条阴性样本全是单行紧邻形态，恰好绕开 I-1，等于没测。

未覆盖（刻意留给后续任务，不是漏判）：
- 「转场只能来自 buildPageTransition/buildFadePageTransition」是 §5 给这把尺的第二条判据，
  但工厂属 P3（`utils/styles.ets`）尚未存在，现在写死会把 P3 的第一步堵在尺下——P3 落地时补；
- 缩放（pressScale）与 `.duration()` 组件setter 同理，等 P2/P3 出现消费方再上判据；
- `const duration: number = 220` 这类「先声明带类型的裸毫秒、再 `duration: duration` 挂进
  `.animation({})`」：声明位按 W2 不报，但**用进去那一行在动效块内必报**，绕不过去；
- 反向的刻意从严：UI 目录（pages/components/design/common/utils）里 `duration: 非 token 值`
  一律报，包括 `duration: 变量`。页面要动效时长就引 token；真需要豁免时来改顶部 W 名单，
  而不是让尺子闭嘴。

用法：python3 tools/audit_motion.py [--selftest]
退出码 0 = 无违规（或 selftest 21 条断言全成立）；1 = 有违规 / selftest 失效；2 = 用法错。
"""

import glob
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')

# token 定义本体里写的是契约数值本身，不属「页面调参」
SKIP = ('design/MotionTokens.ets',)
# W3 数据层目录（这几个目录里 duration 的单位是分钟，见 model/Trip.ets:51）
DATA_DIRS = ('/data/', '/ai/', '/mock/', '/model/')
# selftest 样本默认按 UI 层文件判（W3 不适用），W1/W2 仍适用
UI_REL = 'entry/src/main/ets/pages/_SelfTest.ets'

# 动效算子：其括号区间内的时长**一定**是动效时长，任何豁免在此让路（MOTION 优先于 W1/W3）
MOTION_OPEN = re.compile(
    r'\.animation\s*\(|\banimateTo(?:Immediately|AfterSwitch)?\s*\(|\.transition\s*\('
    r'|\bkeyframeAnimateTo\s*\(|[Mm]arquee\s*\(|\.marqueeOptions\s*\(|\bImageAnimator\s*\('
    r'|\bSpriteAnimation\s*\(|\.pageTransition\s*\(|\bscrollTo(?:Index)?\s*\('
    r'|\.sharedTransition\s*\(')
# W1 非动效 API（提示/弹窗停留时长）
NOTICE_CALL = re.compile(
    r'\bshow(?:Toast|Dialog|CustomDialog|LoadingDialog)\s*\(|\bgetPromptAction\s*\(')
# 时长键：? 是可选成员语法（delay?: number），(?<![A-Za-z0-9_]) 挡住 suggested_duration / transport_duration
TIME_KEY = re.compile(r'(?<![A-Za-z0-9_])(?:duration|delay)\s*\??\s*:\s*')
TOKEN_VALUE = re.compile(r'MotionTokens\s*\.\s*[A-Za-z_]\w*')
TYPE_VALUE = re.compile(
    r'(?:number|string|boolean|any|void|Object|ResourceStr|Length|ICurve|Curve|AnimateParam|'
    r'AnimatorParam|number\[\]|string\[\])\s*(?:=|;|,|\)|$)')
DIGIT_FIRST = re.compile(r'[+-]?\d')
BARE_CURVE = re.compile(r'(?<![A-Za-z0-9_])curve\s*:\s*Curve\s*\.')
STATE_RE = re.compile(r'\.stateStyles\s*\(')

# 本 docstring 声称的数字；selftest 逐条比对，漂移当场 FAIL（M-2 的防复发闸门）
DOC_POSITIVE = 9
DOC_NEGATIVE = 9
DOC_ASSERTIONS = 21


def mask(text):
    """字符串字面量与注释一律抹成空格，长度不变——括号配对和正则只吃结构。

    与 tools/audit_button_width.py:54 同一套语义（R20），差别只在反引号模板串跨行也抹：
    原版遇换行就 break，多行模板里的 `{` 会漏进深度跟踪。
    """
    out = list(text)
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                out[k] = ' ' if out[k] != '\n' else '\n'
            i = j
        elif c == '`':
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    out[j] = ' '
                    j += 2
                    continue
                if text[j] == '`':
                    break
                out[j] = ' ' if text[j] != '\n' else '\n'
                j += 1
            i = min(j + 1, n)
        elif c in '"\'':
            quote = c
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    out[j] = ' '
                    j += 2
                    continue
                if text[j] == quote or text[j] == '\n':
                    break
                out[j] = ' '
                j += 1
            i = min(j + 1, n)
        else:
            i += 1
    return ''.join(out)


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def sources():
    out = {}
    for p in glob.glob(os.path.join(ETS, '**/*.ets'), recursive=True):
        rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
        if any(rel.endswith(s) for s in SKIP):
            continue
        out[rel] = read(p)
    return out


def call_spans(masked, regex):
    """regex 命中的每一处调用（正则须以左括号收尾），返回它从左括号到配平右括号所跨的行号集合（0 基）。

    注释与字符串已在 mask 里抹掉，所以这里的深度跟踪只吃结构：夹注释/空行不截断，
    字符串里的 `{` 也不会把块撑成永不闭合（M-3）。
    """
    covered = set()
    n = len(masked)
    for m in regex.finditer(masked):
        k = m.end() - 1
        if k >= n or masked[k] != '(':
            continue
        depth = 0
        j = k
        while j < n:
            if masked[j] == '(':
                depth += 1
            elif masked[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        first = masked.count('\n', 0, k)
        last = masked.count('\n', 0, j + 1)
        covered.update(range(first, last + 1))
    return covered


def prev_attribute(masked, pos):
    """`.stateStyles(` 之前的**上一条属性调用**名（0 基行号）。I-1 的正解。

    与 audit_a11y_name.py:46 attribute_chain 同一套「空行/注释行透明」语义：从 pos 往回跳过
    空白（mask 后注释就是空白），吃一个配平的 `(...)`，再读它前面的 `.名字`。所以
    跨行 `.animation({ … })` 块（回跳先落在后继闭括号 `)` 上）、同行链
    `.animation({ … }).stateStyles(…)`、中间夹注释/空行，三种写法都判成「上一条是 animation」。
    """
    i = pos - 1
    while i >= 0 and masked[i].isspace():
        i -= 1
    if i < 0 or masked[i] != ')':
        return None, 0
    depth = 0
    while i >= 0:
        if masked[i] == ')':
            depth += 1
        elif masked[i] == '(':
            depth -= 1
            if depth == 0:
                break
        i -= 1
    if i <= 0:
        return None, 0
    j = i - 1
    while j >= 0 and masked[j].isspace():
        j -= 1
    k = j
    while k >= 0 and (masked[k].isalnum() or masked[k] == '_'):
        k -= 1
    name = masked[k + 1:j + 1]
    h = k
    while h >= 0 and masked[h].isspace():
        h -= 1
    if not name or h < 0 or masked[h] != '.':
        return None, masked.count('\n', 0, j + 1)
    return name, masked.count('\n', 0, j + 1)


def judge(text, rel=UI_REL):
    """返回 (违规列表, 豁免计数)。豁免计数只在真实扫描时打印，selftest 只取违规。"""
    masked = mask(text)
    lines = masked.split('\n')
    raw = text.split('\n')
    motion = call_spans(masked, MOTION_OPEN)
    notice = call_spans(masked, NOTICE_CALL)
    slash = rel.replace(os.sep, '/')
    is_data_layer = any(d in slash for d in DATA_DIRS)
    hits = []
    exempt = Counter()

    for i, ln in enumerate(lines):
        for m in TIME_KEY.finditer(ln):
            value = ln[m.end():].lstrip()
            src = (raw[i].strip() if i < len(raw) else ln.strip())
            if TOKEN_VALUE.match(value):
                continue
            if i in motion:                      # 动效区间内：任何豁免让路
                hits.append('[裸时长] L%d: %s' % (i + 1, src))
            elif TYPE_VALUE.match(value):
                exempt['W2 类型声明位'] += 1
            elif i in notice:
                exempt['W1 提示停留时长'] += 1
            elif is_data_layer and not DIGIT_FIRST.match(value):
                exempt['W3 数据层分钟数'] += 1
            else:
                hits.append('[裸时长] L%d: %s' % (i + 1, src))
        for m in BARE_CURVE.finditer(ln):
            hits.append('[枚举曲线] L%d: %s' % (i + 1, raw[i].strip()))

    for m in STATE_RE.finditer(masked):
        line_no = masked.count('\n', 0, m.start())
        name, prev_line = prev_attribute(masked, m.start())
        if name == 'animation':
            continue
        if name:
            why = '上一条属性是 .%s()（L%d），不是紧跟 .animation()' % (name, prev_line + 1)
        else:
            why = '往前找不到属性调用——整条链没挂 .animation，或中间被别的语句截断'
        hits.append('[顺序] L%d: .stateStyles %s' % (line_no + 1, why))
    hits.sort(key=lambda h: int(re.search(r'L(\d+)', h).group(1)))
    return hits, exempt


def scan(text, rel=UI_REL):
    return judge(text, rel)[0]


# ---------------------------------------------------------------- selftest 样本
# 阳性 9 类：契约禁止的写法，必须被抓到。
P_REVERSED = (
    '  .stateStyles({ normal: { .opacity(1) } })\n'
    '  .animation({ duration: 180, curve: Curve.EaseInOut })\n')
P_BLOCK = (
    '  .animation({\n'
    '    duration: 220,\n'
    '    curve: Curve.EaseInOut\n'
    '  })\n')
P_TERNARY = ('  .animation({\n'
             '    duration: this.on ? 320 : 220,\n'
             '    curve: MotionCurves.standard\n'
             '  })\n')
P_VARIABLE = ('  .animation({\n'
              '    duration: pressMs,          // 变量不是 token\n'
              '    curve: MotionCurves.standard\n'
              '  })\n')
P_HELPER = (
    '  private buildPressParam(): AnimateParam {\n'
    '    const p: AnimateParam = { duration: 400, curve: Curve.Sharp };\n'
    '    return p;\n'
    '  }\n')
P_KEYFRAME = (
    '  this.getUIContext().keyframeAnimateTo({ iterations: 2 }, [\n'
    '    { duration: 100, curve: MotionCurves.standard, event: (): void => { this.step = 1; } },\n'
    '    { duration: MotionTokens.control, curve: MotionCurves.decelerate, event: (): void => {} },\n'
    '  ]);\n')
P_MARQUEE = (
    '  Marquee({ start: true, step: 6, loop: -1, src: tips })\n'
    '    .margin({ top: SpaceTokens.sm })\n'
    '  ImageAnimator({ images: frames, duration: 300 })\n')
P_NO_ANIMATION = (
    '  .padding(SpaceTokens.md)\n'
    '  .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.8) } })\n')
P_DATA_FILE_MS = (
    '  const legacy = { duration: 999 };\n'
    '  Column() {\n'
    '    Text(label)\n'
    '  }\n'
    '  .animation({ duration: 400, curve: MotionCurves.standard })\n'
    '  .stateStyles({ pressed: { .scale({ x: MotionTokens.pressScale }) } })\n')

# 阴性 9 类：契约正确写法 / 非动效 duration，一条都不许误抓。
N_SAME_LINE = (
    '  .animation({ duration: MotionTokens.press, curve: MotionCurves.standard })\n'
    '  .stateStyles({ normal: { .opacity(1) } })\n')
N_BLOCK_CLOSE = (
    '  .animation({\n'
    '    duration: MotionTokens.control,\n'
    '    curve: MotionCurves.decelerate\n'
    '  })\n'
    '  .stateStyles({ pressed: { .scale({ x: MotionTokens.pressScale }) } })\n')
N_COMMENT_AND_BLANK = (
    '  .animation({\n'
    '    duration: MotionTokens.press,\n'
    '    curve: MotionCurves.standard\n'
    '  })\n'
    '  // 中间夹注释：ArkUI 里 .animation 必须在 .stateStyles 之前\n'
    '\n'
    '  .stateStyles({ normal: { .opacity(1) } })\n')
N_SAME_LINE_CHAIN = ('  Text(label).animation({ duration: MotionTokens.press }).stateStyles({ normal: { .opacity(1) } })\n')
N_COMMENT_MENTIONS = (
    '  // 别写成 .stateStyles({}) 在前、.animation({ duration: 220 }) 在后\n'
    '  /* 同样合法：块注释里提到 duration: 1800 与 .stateStyles( */\n'
    '  .animation({ duration: MotionTokens.control, curve: MotionCurves.standard })\n'
    '  .stateStyles({ normal: { .opacity(1) } })\n')
N_TOAST = (
    "  this.getUIContext().getPromptAction().showToast({ message: '已保存', duration: 1800 });\n"
    "  this.getUIContext().getPromptAction().showToast({\n"
    "    message: '库里的景点都已推荐过了', duration: 1800\n"
    "  });\n")
N_TYPE_DECL = (
    '  export interface MotionSpec {\n'
    '    duration: number;\n'
    '    delay?: number;\n'
    '  }\n'
    '  const duration: number = 220;\n')
N_DATA_MODEL = (
    '  const t: ReplanTransport = { duration: a.transport.duration };\n'
    '  const info: TransportInfo = { mode: mode, duration: minutes, detail: detail };\n'
    '  return { id: id, duration: rs.getLong(rs.getColumnIndex(\'transport_duration\')) };\n')
N_STRING_BRACES = (
    "  Text('{ label: \'{\' }')\n"
    '    .animation({ duration: MotionTokens.shimmer, curve: MotionCurves.linear })\n'
    '    .stateStyles({ normal: { .opacity(1) } })\n')

CASES = [
    # (类别, 名字, 判据文件路径, 样本, 阳性期望 {标签: 至少几条})
    ('阳性', '顺序倒置（stateStyles 在前）', UI_REL, P_REVERSED, {'[顺序]': 1, '[裸时长]': 1, '[枚举曲线]': 1}),
    ('阳性', '跨行 .animation 块内裸时长+枚举曲线', UI_REL, P_BLOCK, {'[裸时长]': 1, '[枚举曲线]': 1}),
    ('阳性', '三元 duration: this.on ? 320 : 220', UI_REL, P_TERNARY, {'[裸时长]': 1}),
    ('阳性', '变量 duration: pressMs', UI_REL, P_VARIABLE, {'[裸时长]': 1}),
    ('阳性', 'helper 预定义 AnimateParam={duration:400}', 'entry/src/main/ets/utils/styles.ets', P_HELPER,
     {'[裸时长]': 1, '[枚举曲线]': 1}),
    ('阳性', 'keyframeAnimateTo 帧内裸时长', UI_REL, P_KEYFRAME, {'[裸时长]': 1}),
    ('阳性', 'marquee/ImageAnimator 裸时长', UI_REL, P_MARQUEE, {'[裸时长]': 1}),
    ('阳性', '有 stateStyles 却没挂 animation', UI_REL, P_NO_ANIMATION, {'[顺序]': 1}),
    ('阳性', '数据层文件里硬写毫秒（W3 只放行取自字段的分钟数）', 'entry/src/main/ets/data/Probe.ets',
     P_DATA_FILE_MS, {'[裸时长]': 2}),
    ('阴性', '单行紧邻契约写法（上一版唯一测过的形态）', UI_REL, N_SAME_LINE, {}),
    ('阴性', '跨行 .animation({…}) 块 + 后继闭括号接 stateStyles', UI_REL, N_BLOCK_CLOSE, {}),
    ('阴性', '块与 stateStyles 之间夹注释行与空行', UI_REL, N_COMMENT_AND_BLANK, {}),
    ('阴性', '.animation().stateStyles() 同行链', UI_REL, N_SAME_LINE_CHAIN, {}),
    ('阴性', '注释文本里提到 .stateStyles( 与裸毫秒', UI_REL, N_COMMENT_MENTIONS, {}),
    ('阴性', 'showToast 停留时长（单行 + 跨行调用）', UI_REL, N_TOAST, {}),
    ('阴性', '接口成员与带类型的变量声明', 'entry/src/main/ets/model/Trip.ets', N_TYPE_DECL, {}),
    ('阴性', '数据层 Transport.duration（分钟，取自字段/变量）', 'entry/src/main/ets/data/SkipPlanner.ets', N_DATA_MODEL, {}),
    ('阴性', '字符串里的花括号不污染深度跟踪', UI_REL, N_STRING_BRACES, {}),
]

TAG_RE = re.compile(r'^(\[[^\]]+\])')


def tag_of(hit):
    m = TAG_RE.match(hit)
    return m.group(1) if m else hit


def selftest():
    checks = []
    pos = [c for c in CASES if c[0] == '阳性']
    neg = [c for c in CASES if c[0] == '阴性']

    print('=' * 78)
    print('阳性样本 %d 类——契约禁止的写法，必须抓到' % len(pos))
    print('=' * 78)
    for _kind, name, rel, text, want in pos:
        hits = scan(text, rel)
        got = Counter(tag_of(h) for h in hits)
        bad = [t for t, n in want.items() if got.get(t, 0) < n]
        print('\n[阳性] %s  (%s)' % (name, rel))
        for h in hits:
            print('       抓到 ✗ ' + h)
        for t, n in want.items():
            print('       判据 %s 期望 >=%d 实得 %d' % (t, n, got.get(t, 0)))
        checks.append(('阳性｜' + name, not bad and len(hits) > 0))

    print('')
    print('=' * 78)
    print('阴性样本 %d 类——契约正确写法与非动效 duration，必须一条不报' % len(neg))
    print('=' * 78)
    for _kind, name, rel, text, _want in neg:
        hits = scan(text, rel)
        print('\n[阴性] %s  (%s)' % (name, rel))
        if hits:
            for h in hits:
                print('       误抓 !! ' + h)
        else:
            print('       确认不误抓 ✓ 0 命中')
        checks.append(('阴性｜' + name, len(hits) == 0))

    checks.append(('docstring 阳性类数与真数一致（M-2 防漂移）', len(pos) == DOC_POSITIVE))
    checks.append(('docstring 阴性类数与真数一致（M-2 防漂移）', len(neg) == DOC_NEGATIVE))
    checks.append(('docstring 断言总数与真数一致（M-2 防漂移）', len(checks) + 1 == DOC_ASSERTIONS))

    print('')
    failed = [name for name, passed in checks if not passed]
    for name, passed in checks:
        print("  %s %s" % ('OK  ' if passed else 'FAIL', name))
    if failed:
        print('selftest FAIL：%d 条不成立 → %s（尺子读数不可信，先修尺再谈过闸）'
              % (len(failed), '；'.join(failed)))
        return 1
    print('selftest PASS：%d 条成立（阳性 %d 类抓到 / 阴性 %d 类不误抓 / 文档数字 3 条对表）'
          % (len(checks), len(pos), len(neg)))
    return 0


def main():
    if sys.argv[1:2] == ['--selftest']:
        return selftest()
    if len(sys.argv) > 1:
        print(__doc__)
        return 2
    srcs = sources()
    fails = []
    total_exempt = Counter()
    for rel, text in sorted(srcs.items()):
        hits, exempt = judge(text, rel)
        total_exempt.update(exempt)
        for h in hits:
            fails.append('%s %s' % (rel, h))
    print('扫描 %d 个 .ets（跳过 %s），判据：裸时长 / Curve 枚举曲线 / .animation 与 .stateStyles 顺序'
          % (len(srcs), '/'.join(SKIP)))
    if total_exempt:
        detail = '、'.join('%s %d 处' % (k, v) for k, v in sorted(total_exempt.items()))
        print('豁免非动效 duration（W1/W2/W3 白名单，逐条可查）：%s' % detail)
    if not fails:
        print('动效违规 0 处')
        return 0
    for f in fails:
        print('  ✗ ' + f)
    print('动效违规 %d 处' % len(fails))
    return 1


if __name__ == '__main__':
    sys.exit(main())
