#!/usr/bin/env python3
"""第 15 把尺：skip-worktree 配置必须"干净检出也编得过、也不带密钥"。

为什么要有这一把：`entry/src/main/ets/common/config/ApiConfig.ets` 是 skip-worktree
（`git ls-files -v` 里标 `S`）—— 工作树里那份带真密钥/真地址，**仓库里那份必须字段齐全
但值为空**。这个约定已经第二次被破：2026-11-01 那轮有人给接口加了 `BFF_BASE_URL` 并让
`LlmClient`/`DeviceActivator`/`IapStore` 去引用它，而 HEAD 里的仓库版没这个字段 ——
本地一切正常（因为本地那份是带字段的），**别人 clone 下来直接编译失败**，
而且 `git status` 干干净净，看不出任何异常。这条坑的隐蔽之处就在于它不留痕迹。

判两条：
  R1 引用面：所有 `.ets` 里出现的 `<ConfigConst>.<field>`，字段必须在 **HEAD 版**的
      配置对象里声明过。缺 = 干净检出编不过。
  R2 密钥面：HEAD 版里凡是名字像密钥/令牌/地址的字段（KEY/TOKEN/SECRET/URL/ENDPOINT），
      值必须为空串。非空 = 密钥入库。

用法：
  python3 tools/audit_skip_worktree.py            # 扫全仓
  python3 tools/audit_skip_worktree.py --selftest # 零依赖复算：注入阳性样本

退出码 0 = 两条都过；1 = 有违规；2 = 仓库状态读不到（不是判定失败）。
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = 'entry/src/main/ets/common/config'
# 名字像这些的字段，仓库版里必须留空 —— 这是"凭证"面。
# **URL / ENDPOINT 不在列**：本仓仓库版里 `WEATHER_URL` 存的是 Open-Meteo 公共端点
# （免 Key、无凭证），把它清空只会让干净检出后的天气功能一起哑掉，不是更安全而是更坏。
# 地址类真正要防的是"把凭证嵌在 URL 里"，那条单独判（CRED_IN_URL）。
SECRETISH = re.compile(r'(KEY|TOKEN|SECRET|PASSWORD|APP_ID|CLIENT_ID)$')
CRED_IN_URL = re.compile(r'://[^/\s]*:[^/\s]*@')   # https://user:pass@host —— 内嵌凭证


def sh(*args):
    return subprocess.run(['git', '-C', REPO] + list(args),
                          capture_output=True, text=True).stdout


def skip_worktree_files():
    out = sh('ls-files', '-v', CONFIG_DIR)
    return [l.split(' ', 1)[1].strip() for l in out.splitlines()
            if l.startswith('S ') or l.startswith('h ')]


def const_names(text):
    """`export const ApiConfig: ApiConfigType = {` → ['ApiConfig']"""
    return re.findall(r'export\s+const\s+([A-Za-z_][A-Za-z0-9_]*)\s*:', text)


def fields_of(text, const):
    """从 `export const <const> ... = {` 往后收到配平的 `}`，取顶层 `key: value`。"""
    m = re.search(r'export\s+const\s+%s\b[^\n]*\{\s*$' % re.escape(const), text, re.M)
    if not m:
        return {}
    body = text[m.end():]
    depth = 1
    out = {}
    line = []
    for ch in body:
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                break
        line.append(ch)
    src = ''.join(line)
    # 顶层键 = 缩进最浅的那一层。写死"4 空格"会漏：本仓配置用 2 空格缩进，
    # 而嵌套对象里的键缩进更深，不能当顶层字段收（selftest 里钉住这条）。
    # 缩进只能吃水平空白：`(\s*)` 会把换行也算进缩进，于是"紧跟在空行之后的键"
    # 缩进多 1，被 min() 判成更深一层而漏掉（selftest 里 BASE_URL 就是这么丢的）。
    rows = [(len(mm.group(1)), mm.group(2), mm.group(3))
            for mm in re.finditer(r'^([ \t]*)([A-Za-z_][A-Za-z0-9_]*)[ \t]*:[ \t]*(.*)$', src, re.M)]
    if not rows:
        return out
    top = min(r[0] for r in rows)
    for indent, key, raw in rows:
        if indent == top:
            out[key] = raw.strip().rstrip(',')
    return out


def scan_references():
    """返回 [(引用到的字段, 文件, 行号)]，只看在配置目录之外引用这些常量的地方。"""
    hits = []
    for root, dirs, files in os.walk(os.path.join(REPO, 'entry/src')):
        dirs[:] = [d for d in dirs if d not in ('build', '.preview', 'node_modules')]
        for f in files:
            if not f.endswith('.ets'):
                continue
            p = os.path.join(root, f)
            try:
                lines = open(p, encoding='utf-8').read().split('\n')
            except Exception:
                continue
            rel = os.path.relpath(p, REPO)
            for i, l in enumerate(lines, 1):
                for mm in re.finditer(r'\b([A-Z][A-Za-z0-9_]*(?:Config))\.([A-Za-z_][A-Za-z0-9_]*)', l):
                    hits.append((mm.group(1), mm.group(2), rel, i))
    return hits


def value_is_empty(raw):
    v = raw.strip()
    return v in ("''", '""', "'''", '""""')


def check():
    """返回违规清单 [(规则, 说明, 出处)]。"""
    bad = []
    files = skip_worktree_files()
    if not files:
        return bad
    declared = {}      # const -> {field: raw value}
    for rel in files:
        head = sh('show', 'HEAD:' + rel)
        if not head:
            bad.append(('R0', f'读不到 HEAD 版 {rel}', 'git show'))
            continue
        consts = const_names(head)
        if not consts:
            continue
        for c in consts:
            fields = fields_of(head, c)
            declared.setdefault(c, {}).update(fields)
            # R2：仓库版里像密钥的字段必须留空
            for fname, raw in fields.items():
                if SECRETISH.search(fname) and not value_is_empty(raw):
                    bad.append(('R2', f'{rel} 的仓库版字段 {c}.{fname} 非空：{raw[:48]}',
                                'skip-worktree 仓库版必须字段齐全、凭证留空'))
                elif CRED_IN_URL.search(raw):
                    bad.append(('R2', f'{rel} 的仓库版字段 {c}.{fname} 把凭证嵌进了 URL：{raw[:48]}',
                                '改成独立的空字段，别把 user:pass 写进地址'))
    seen = {}
    for const, field, path, line in scan_references():
        if const not in declared or field in declared[const]:
            continue
        seen.setdefault((const, field), (path, line))
    for (const, field), (path, line) in sorted(seen.items()):
        total = sum(1 for c, f, _, _ in scan_references() if (c, f) == (const, field))
        more = f'（全仓共 {total} 处引用）' if total > 1 else ''
        bad.append(('R1', f'{path}:{line} 引用 {const}.{field}，但 HEAD 版 {const} 没这个字段{more}',
                    '干净检出会编译失败；把字段补进仓库版并留空'))
    return bad


def selftest():
    """零设备、零仓库状态依赖地自证这把尺抓得到东西（报 0 之前先反证）。"""
    head = """export interface ApiConfigType {
  BASE_URL: string;
  API_KEY: string;
}
export const ApiConfig: ApiConfigType = {
  BASE_URL: '',
  API_KEY: '',
};
"""
    assert fields_of(head, 'ApiConfig') == {'BASE_URL': "''", 'API_KEY': "''"}, fields_of(head, 'ApiConfig')
    leaky = head.replace("  API_KEY: '',", "  API_KEY: 'sk-1234567890abcdef';")
    f = fields_of(leaky, 'ApiConfig')
    assert SECRETISH.search('API_KEY') and not value_is_empty(f['API_KEY']), 'R2 没能识别入库的密钥'
    # 公共端点不该被当成密钥（清空它只会让功能一起哑掉）
    assert not SECRETISH.search('WEATHER_URL'), 'URL 类字段被误判成凭证'
    assert CRED_IN_URL.search("'https://u:pw@host/x'"), '内嵌凭证的 URL 没被抓到'
    # R1：引用了仓库版没有声明的字段
    assert 'BFF_BASE_URL' not in fields_of(head, 'ApiConfig'), '样本本身就该缺这个字段'
    # 配平：嵌套对象里的键不该被当成顶层字段
    nested = """export const X: T = {
  A: '',
  deep: {
    B: 'zzz',
  },
};
"""
    assert set(fields_of(nested, 'X')) == {'A', 'deep'}, fields_of(nested, 'X')
    print('selftest PASS：R1 缺字段可判 / R2 凭证入库可判 / 公共 URL 不误判 / 嵌套键不误收')
    return 0


def main():
    if sys.argv[1:2] == ['--selftest']:
        return selftest()
    if not os.path.isdir(os.path.join(REPO, '.git')):
        print('不是 git 仓库，跳过', file=sys.stderr)
        return 2
    files = skip_worktree_files()
    bad = check()
    print(f"skip-worktree 配置 {len(files)} 份：{', '.join(os.path.basename(f) for f in files)}")
    if not bad:
        print('skip-worktree: 干净检出可编译、仓库版无密钥 (pass)')
        return 0
    for rule, why, fix in bad:
        print(f'  ⚠ [{rule}] {why}')
        print(f'        → {fix}')
    return 1


if __name__ == '__main__':
    sys.exit(main())
