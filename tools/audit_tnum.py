#!/usr/bin/env python3
r"""数字等宽核对（tnum）：契约 §typography 写「tnum for every numeral:
times, durations, distances, step counts」——时刻、时长、距离、步数一律走等宽数字。

为什么要有这一支：前五把尺量的都是"有没有对上帧"，这一把量的是**同一屏内数字对不对得齐**。
tnum 漏写不会报错、不会改变字号，只会让「09:30 / 13:15 / 18:30」三行的冒号错开半格，
两列金额对不齐。而 ArkUI 里它必须逐条属性链显式写 `.fontFeature("'tnum' on")`，
所以漏一处就少一处。

用法：python3 tools/audit_tnum.py
退出码 0 = 数字表面全部等宽；1 = 有漏写或字面量漂移。

口径（两条都可机判，不猜数据流）：
- ① 内联模板：`Text(\`... 小时/分钟/km/¥/天/人/站/段/步/晚 ...\`)` 这类**参数里就带数字单位**的
  可见 Text，链上必须有 fontFeature；纯单位标签（'站'、'天'）与无数字的散文走 SKIP 并写理由。
- ② 数字 helper：自动收集"返回模板里含数字单位"的 `private xxx(): string`，
  再看它的**调用点** `Text(this.xxx())` 有没有带 tnum——数字串在 helper 里拼好时，
  只看 Text 参数是查不出来的（这条正是本轮实测出来的盲区）。
- 匹配用 `(?<![A-Za-z0-9_])Text\\(`：`accessibilityText(...)` 不是可见文本，
  早先一版把它算成了 Text，凭空造出两处"漏写"。
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NUM_UNIT = re.compile(r'(小时|分钟|km|¥|:\d|\d+晚|天\d*晚|步|段|密度|\{\w+\}\s*(人|站|个|天|晚|分钟|小时|km))')
TNUM = "'tnum' on"

# 参数含数字单位、但**不该**等宽的可见 Text（必须写理由）
SKIP = {
    ('entry/src/main/ets/pages/SharePage.ets', '站'):
        '这是 hero 数字右侧的**单位标签**（"16 / 站"里的"站"），本身不含数字；'
        '数字在兄弟 Text 上，那条已带 tnum',
    ('entry/src/main/ets/pages/YoujingStartPage.ets', '基于本地精选数据库'):
        '散文句里的"站点"是词不是计数，等宽无意义',
}


def chain_of(lines, idx):
    """取该 Text 的属性链：链上修饰行缩进一致，缩进变浅即链结束（窗口式会吃到兄弟组件）"""
    ti = len(lines[idx]) - len(lines[idx].lstrip())
    base = None
    out = []
    for j in range(idx + 1, len(lines)):
        st = lines[j].strip()
        if not st or st.startswith('//') or st.startswith('*'):
            continue
        ind = len(lines[j]) - len(lines[j].lstrip())
        if ind <= ti:
            break
        if base is None:
            base = ind
        if ind == base and st.startswith('.'):
            out.append(st)
    return '\n'.join(out)


def sources():
    return sorted(glob.glob(os.path.join(ROOT, 'entry/src/main/ets/pages/*.ets')) +
                  glob.glob(os.path.join(ROOT, 'entry/src/main/ets/components/*.ets')) +
                  glob.glob(os.path.join(ROOT, 'entry/src/main/ets/widget/**/*.ets'), recursive=True))


def numeric_helpers(text):
    """返回模板里带数字单位的 private 方法名"""
    out = set()
    for m in re.finditer(r'(?:private |static )?(\w+)\([^)]*\)\s*:\s*string\s*\{', text):
        name = m.group(1)
        i = m.end() - 1
        depth = 0
        while i < len(text):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = text[m.end():i]
        if re.search(r'return\s+`', body) and NUM_UNIT.search(body):
            out.add(name)
    return out


def main():
    fails = []
    notes = []
    total_inline = 0
    total_helper = 0
    for path in sources():
        rel = os.path.relpath(path, ROOT)
        text = open(path, encoding='utf-8').read()
        lines = text.split('\n')
        helpers = numeric_helpers(text)
        for i, ln in enumerate(lines):
            m = re.search(r'(?<![A-Za-z0-9_])Text\((.{2,120}?)\)', ln)
            if not m:
                continue
            arg = m.group(1)
            has_num = bool(NUM_UNIT.search(arg))
            is_helper = re.search(r'this\.(\w+)\(', arg) and re.search(r'this\.(\w+)\(', arg).group(1) in helpers
            if not (has_num or is_helper):
                continue
            # 参数里只出现 helper 名而不含单位时，交给 helper 分支；纯变量名（无数字单位）不算
            if is_helper or (has_num and '$' in arg):
                if has_num:
                    total_inline += 1
                if is_helper:
                    total_helper += 1
                chain = chain_of(lines, i)
                if TNUM in chain or TNUM in arg:
                    continue
                hit = [k for k in SKIP if k[0] == rel and k[1] in arg]
                if hit:
                    notes.append(f'[已释明] {rel}:{i + 1} {arg[:34]}：{SKIP[hit[0]]}')
                    continue
                tag = '数字 helper' if is_helper and not has_num else '内联数字'
                fails.append(f'[漏 tnum] {rel}:{i + 1} {tag} Text({arg[:44]}) '
                             f'所在链上没有 .fontFeature("\'tnum\' on")')
        # 字面量漂移
        for i, ln in enumerate(lines):
            for fm in re.finditer(r"\.fontFeature\((.{1,40})\)", ln):
                if fm.group(1).replace(' ', '') != f'"{TNUM}"'.replace(' ', ''):
                    fails.append(f'[字面量漂移] {rel}:{i + 1} fontFeature({fm.group(1)})，'
                                 f'契约只有一种取值 "{TNUM}"')
    print(f'扫描 {len(sources())} 个界面文件；内联数字 Text {total_inline} 处、'
          f'数字 helper 调用点 {total_helper} 处')
    for n in notes:
        print('  · ' + n)
    if not fails:
        print('tnum 偏差 0 处')
        return 0
    for f in fails:
        print('  ✗ ' + f)
    print(f'tnum 偏差 {len(fails)} 处')
    return 1


if __name__ == '__main__':
    sys.exit(main())
