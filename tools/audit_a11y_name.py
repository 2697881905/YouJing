#!/usr/bin/env python3
r"""控件可及名核对（accessibilityText / placeholder）：底稿帧把每个可点控件都写了
`aria-label`，帧的 aria-label 就是这一屏的交互契约；落地时 ArkUI 要逐控件显式写
`.accessibilityText(...)`，漏一处读屏软件就只念出「滑块」「开关」这种没信息量的角色名。

为什么要有这一支：前九把尺量的是"画得对不对上帧"，这一把量的是**控件叫什么**。
漏写不影响视觉、编译也不报错，实拍永远查不出来——只有把帧的 aria-label 和代码的属性
链对表才会现形。本轮实测（屏2 预算 Slider）就是这么抓到的。

用法：
  python3 tools/audit_a11y_name.py            # 全仓核对
  python3 tools/audit_a11y_name.py --probe    # 反证尺子抓得到（注入一个已知阳性）

退出码 0 = 语义控件全部有可及名；1 = 有漏写。

口径（可机判，不猜数据流）：
- 只查**官方语义控件** Slider/Toggle/Checkbox/TextInput/TextArea/Search/Select/Rating/Progress/Gauge——
  它们自带角色名，没有可及名就等于读屏念「开关，关」。
- Button / Text / 自定义组件不算：Button 的 label、Text 的内容本身就是可及名。
- 算"有名字"的属性：accessibilityText / placeholder / label / title / value 里的具名参数。
- 匹配用 `(?<![A-Za-z0-9_])`：`TextInput(` 前面是字母的行（如 `isTextInput(`）不算控件本体。
- 属性链取法与 audit_layout_patterns 同口径：从控件行往后吃 `.` 开头的链，
  遇到缩进回到控件行之前、且不以 `.` 开头的行就停——不吃子组件的链。
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')

# Progress/Gauge 一起纳管：屏4 容量条在 dumpLayout 里就是 `Progress 100.000000`——
# 不给可及名时读屏念的是框架的原始比例（OnTripPage 那条注释也记过「真机实测 1.000000」）。
# LoadingProgress 不会被误抓：`(?<![A-Za-z0-9_])` 把 "Loading" 结尾的 g 挡在外面。
CONTROLS = ('Slider', 'Toggle', 'Checkbox', 'TextInput', 'TextArea', 'Search', 'Select', 'Rating',
            'Progress', 'Gauge')
CONTROL_RE = re.compile(r'(?<![A-Za-z0-9_])(' + '|'.join(CONTROLS) + r')\s*\(')
NAMED = ('accessibilityText', 'placeholder', 'label', 'title')

# 有理由不带可及名的位置：file -> 行号集合（改代码后行号会漂，所以每条都要写清是什么控件）
SKIP = {}


def attribute_chain(lines, start):
    """从控件行 start（0 基）往后取参数闭包 + `.属性` 链，返回这段源码文本。

    注释行与空行算「透明」，链继续吃——实测的预算 Slider 在 `.trackColor()` 与
    `.accessibilityText()` 之间夹了 3 行注释，早先按「非 `.` 开头即停」判，
    给已经补上可及名的 Slider 报了一处假漏写。
    """
    depth = lines[start].count('(') - lines[start].count(')')
    collected = [lines[start]]
    i = start + 1
    while i < len(lines) and depth > 0:
        collected.append(lines[i])
        depth += lines[i].count('(') - lines[i].count(')')
        i += 1

    def is_filler(text):
        s = text.strip()
        return s == '' or s.startswith('//') or s.startswith('/*') or s.startswith('*')

    while i < len(lines):
        stripped = lines[i].lstrip()
        # 只吃「`.` 开头的属性行」和「注释/空行」；第一条真语句（同级兄弟控件）即停，
        # 否则会把兄弟控件的 title/label 算进本控件的链上，造出假通过。
        if stripped.startswith('.') or is_filler(lines[i]):
            collected.append(lines[i])
            i += 1
        else:
            break
        if i - start > 80:
            break
    return '\n'.join(collected)


def scan(path):
    with open(path, encoding='utf-8') as fh:
        lines = fh.read().split('\n')
    skipped = SKIP.get(os.path.basename(path), set())
    hits = []
    for idx, line in enumerate(lines):
        m = CONTROL_RE.search(line)
        if not m:
            continue
        if (idx + 1) in skipped:
            continue
        if not any(n in attribute_chain(lines, idx) for n in NAMED):
            hits.append((idx + 1, m.group(1)))
    return hits


def probe():
    """反证：喂已知样本，尺子必须①抓到裸控件 ②不被注释截断 ③不借用兄弟控件的名字。"""
    cases = [
        ('Slider 缺可及名', [
            '  Slider({',
            '    value: this.budget,',
            '    min: 3000,',
            '    max: 12000',
            '  })',
            "    .width('100%')",
            '    .onChange((v: number) => {',
            '      this.budget = v;',
            '    })',
        ], ['Slider']),
        ('链中夹注释仍算有名字', [
            '  Slider({ value: 1 })',
            '    .trackColor(x)',
            '    // 这里解释把手颜色',
            "    .accessibilityText('调整预算档位')",
        ], []),
        ('Progress 缺可及名（读屏会念 100.000000）', [
            '  Progress({',
            '    value: 100,',
            '    total: 100,',
            '    type: ProgressType.Linear',
            '  })',
            "    .width('100%')",
        ], ['Progress']),
        ('Progress 有可及名不报', [
            "  Progress({ value: 100, total: 100 })",
            "    .accessibilityText(`已选 ${n} 个景点`)",
        ], []),
        ('LoadingProgress 不算进度条', [
            '  LoadingProgress()',
            "    .width(24)",
        ], []),
        ('不借兄弟控件的名字', [
            '  Checkbox()',
            '    .select(this.agreed)',
            '',
            '  // 下一句是同级兄弟，它自带的名字不能算到 Checkbox 头上',
            "  Slider({ value: 1 }).accessibilityText('调整预算档位')",
        ], ['Checkbox']),
    ]
    for desc, sample, expected in cases:
        hits = []
        for idx, line in enumerate(sample):
            m = CONTROL_RE.search(line)
            if m and not any(n in attribute_chain(sample, idx) for n in NAMED):
                hits.append(m.group(1))
        if hits != expected:
            print('PROBE FAILED [%s]: 期望 %s，实得 %s——尺子读数不可信。' % (desc, expected, hits))
            return 1
        print('probe ok: %s' % desc)
    return 0


def main():
    if '--probe' in sys.argv:
        return probe()
    total = 0
    for path in sorted(glob.glob(os.path.join(SRC, '**', '*.ets'), recursive=True)):
        for line_no, control in scan(path):
            print('%s:%d  %s 没有可及名（缺 accessibilityText/placeholder）'
                  % (os.path.relpath(path, ROOT), line_no, control))
            total += 1
    if total == 0:
        print('a11y name: 全部语义控件都有可及名 (pass)')
        return 0
    print('\n%d 处漏写。' % total)
    return 1


if __name__ == '__main__':
    sys.exit(main())
