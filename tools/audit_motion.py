#!/usr/bin/env python3
"""动效尺：时长/曲线只准走 MotionTokens/MotionCurves；.animation() 必须挂在 .stateStyles() 之前。

为什么要有这一支：全站今天**零动画**（`.animation(` / `animateTo(` / `.transition(` 各 0 处），
所以这把尺不抓现行、只防回归——契约 v2 C4 已把 motion 五档钉成
press140 / control220 / container320 / shimmer1200 / pressScale0.97，曲线钉成 MotionCurves 三条
自定义贝塞尔。P2 建 BaseCard/Pressable、P3 建转场工厂之后，任何页面里自己写死的毫秒数或
Curve 枚举都是「页面各自调参」，正是 §0 口径要消灭的形态；而它一旦进了页面，肉眼极难发现
（数值不改变静态像素，只在动的那 200ms 里对或错）。

三条判据：
- [裸时长] 动效上下文里 `duration:` / `delay:` 跟数字字面量 → 必须写 MotionTokens.*；
- [枚举曲线] `curve: Curve.xxx` → 必须写 MotionCurves.*（契约 curve-* 全是自定义贝塞尔，
  ArkUI 的 Curve 枚举里根本没有 cubic-bezier(0.2, 0.8, 0.2, 1) 这一档，写枚举就是静默换曲线）；
- [顺序] `.stateStyles(` 的上一行不是 `.animation(` → 顺序倒置（或有状态样式却没挂动画）。
  这条来自有据实测的 ArkUI 坑：`.animation()` 声明在它作用属性之后不生效，
  写成 `.stateStyles().animation()` 等于「按下没反馈而代码看着没错」。

「动效上下文」按动效算子（`.animation(` / `animateTo(` / `animateToImmediately(` /
`.transition(`）的花括号范围算，不是全文裸扫。原因：`showToast({ duration: 1800 })` 的
duration 是**提示停留时长**，不是动效时长，全站现存 16 处；第一版按裸正则写，一扫就 16 条假违规。
所以 selftest 除了「阳性样本必须被抓到」，还多两条对照：跨行动效块必须抓到、toast 必须不抓。

未覆盖（刻意留给后续任务，不是漏判）：
- 「转场只能来自 buildPageTransition/buildFadePageTransition」是 §5 给这把尺的第二条判据，
  但工厂属 P3（`utils/styles.ets`）尚未存在，现在写死会把 P3 的第一步堵在尺下——P3 落地时补；
- 缩放（pressScale）与 `.duration()` 组件setter 同理，等 P2/P3 出现消费方再上判据。

用法：python3 tools/audit_motion.py [--selftest]
退出码 0 = 无违规（或 selftest 四条全成立）；1 = 有违规 / selftest 失效；2 = 用法错。
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')

# 阳性样本：契约禁止的三个形态一次写全——顺序倒置 + 裸时长 + 枚举曲线。
SELF_BAD = ('  .stateStyles({ normal: { .opacity(1) } })\n'
            '  .animation({ duration: 180, curve: Curve.EaseInOut })\n')
# 阴性样本：同一处动效改成契约写法，顺序也摆正。
SELF_OK = ('  .animation({ duration: MotionTokens.press, curve: MotionCurves.standard })\n'
           '  .stateStyles({ normal: { .opacity(1) } })\n')
# 跨行的动效块：裸时长写在 .animation({ 的下一行——花括号跟踪不生效就会漏判。
SELF_BAD_BLOCK = ('  .animation({\n'
                  '    duration: 220,\n'
                  '    curve: Curve.EaseInOut\n'
                  '  })\n')
SELF_OK_BLOCK = ('  .animation({\n'
                 '    duration: MotionTokens.control,\n'
                 '    curve: MotionCurves.decelerate\n'
                 '  })\n')
# 对照样本：toast 的 duration 不属动效，必须 0 命中（否则全站 16 处误伤）。
SELF_TOAST = ("  this.getUIContext().getPromptAction().showToast({ message: '已保存', duration: 1800 });\n")

# token 定义本体里写的是契约数值本身，不属"页面调参"
SKIP = ('design/MotionTokens.ets',)

MOTION_OPEN = re.compile(r'\.animation\s*\(|\banimateTo(?:Immediately)?\s*\(|\.transition\s*\(')
BARE_TIME = re.compile(r'\b(?:duration|delay):\s*\d')
BARE_CURVE = re.compile(r'\bcurve:\s*Curve\.')


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def sources():
    out = {}
    for p in glob.glob(os.path.join(ETS, '**/*.ets'), recursive=True):
        rel = os.path.relpath(p, ROOT)
        if any(rel.endswith(s) for s in SKIP):
            continue
        out[rel] = read(p)
    return out


def motion_marks(lines):
    """返回"落在某个动效调用的字面量里"的行号集合：算子所在行 + 其花括号未闭合期间跨到的行。"""
    marked = set()
    depth = 0
    for i, ln in enumerate(lines):
        opener = MOTION_OPEN.search(ln)
        if depth > 0 or opener:
            marked.add(i)
        if depth > 0 or opener:
            seg = ln[opener.start():] if depth == 0 and opener else ln
            depth += seg.count('{') - seg.count('}')
            if depth < 0:
                depth = 0
    return marked


def scan(text):
    hits = []
    lines = text.split('\n')
    marks = motion_marks(lines)
    for i, ln in enumerate(lines):
        if i in marks and BARE_TIME.search(ln):
            hits.append(f'[裸时长] L{i+1}: {ln.strip()}')
        if BARE_CURVE.search(ln):
            hits.append(f'[枚举曲线] L{i+1}: {ln.strip()}')
        if '.stateStyles(' in ln:
            prev = lines[i - 1].strip() if i > 0 and lines[i - 1].lstrip().startswith('.') else ''
            if not prev.startswith('.animation('):
                hits.append(f'[顺序] L{i+1}: .stateStyles 前一行不是 .animation')
    return hits


def selftest():
    checks = []
    bad = scan(SELF_BAD)
    ok = scan(SELF_OK)
    block_bad = scan(SELF_BAD_BLOCK)
    block_ok = scan(SELF_OK_BLOCK)
    toast = scan(SELF_TOAST)

    print('阳性样本 SELF_BAD（.stateStyles 在 .animation 之前 + duration: 180 + Curve.EaseInOut）'
          f'命中 {len(bad)} 条：')
    for h in bad:
        print('    ✗ ' + h)
    checks.append(('裸时长被抓到', any(h.startswith('[裸时长]') for h in bad)))
    checks.append(('枚举曲线被抓到', any(h.startswith('[枚举曲线]') for h in bad)))
    checks.append(('顺序倒置被抓到', any(h.startswith('[顺序]') for h in bad)))
    checks.append(('阳性样本命中 >=3', len(bad) >= 3))

    print('阳性样本 SELF_BAD_BLOCK（跨行 .animation({ 里写 duration: 220）'
          f'命中 {len(block_bad)} 条：')
    for h in block_bad:
        print('    ✗ ' + h)
    checks.append(('跨行裸时长被抓到（花括号跟踪生效）', len(block_bad) >= 2))

    print(f'阴性样本 SELF_OK / SELF_OK_BLOCK / SELF_TOAST 命中 {len(ok)}/{len(block_ok)}/{len(toast)} 条')
    for h in ok + block_ok + toast:
        print('    ? ' + h)
    checks.append(('契约写法 0 命中', len(ok) == 0))
    checks.append(('跨行契约写法 0 命中', len(block_ok) == 0))
    checks.append(('toast 的 duration 不算动效违规', len(toast) == 0))

    failed = [name for name, passed in checks if not passed]
    for name, passed in checks:
        print(f"  {'OK  ' if passed else 'FAIL'} {name}")
    if failed:
        print(f'selftest FAIL：{len(failed)} 条不成立 → {failed}（尺子失效得毫无声音，先修尺再谈过闸）')
        return 1
    print(f'selftest PASS：{len(checks)} 条成立（3 类违规各抓到 / 跨行抓到 / 契约写法与 toast 不误伤）')
    return 0


def main():
    if sys.argv[1:2] == ['--selftest']:
        return selftest()
    if len(sys.argv) > 1:
        print(__doc__)
        return 2
    srcs = sources()
    fails = []
    for rel, text in sorted(srcs.items()):
        for h in scan(text):
            fails.append(f'{rel} {h}')
    print(f'扫描 {len(srcs)} 个 .ets（跳过 {"/".join(SKIP)}），'
          f'判据：动效上下文裸时长 / Curve 枚举曲线 / .animation 与 .stateStyles 顺序')
    if not fails:
        print('动效违规 0 处')
        return 0
    for f in fails:
        print('  ✗ ' + f)
    print(f'动效违规 {len(fails)} 处')
    return 1


if __name__ == '__main__':
    sys.exit(main())
