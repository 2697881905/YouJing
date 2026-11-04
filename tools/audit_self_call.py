#!/usr/bin/env python3
"""
静态尺：抓「方法体只调用自己」的无守卫递归——编译与类型检查完全不报，运行即栈溢出。

为什么要这一把：2026-11-04 承接外部改动时发现，`MinePage.refreshMembership()` 的方法体
只有 `this.refreshMembership();` 一行（提交 4116bf4）。ArkTS 编译通过、hypium 237 例全绿、
16 把尺全绿，因为它不是类型错误也不是契约违规——真机上一进「我的」标签页就崩。
这类缺陷只能靠结构判据拦：方法体没有任何分支却调用自己。

判据（宁可漏报不误报）：
- 方法体去掉空白后只有一条语句；
- 该语句是调用自身（`this.x()` / `x()` / `MinePage.x()`，可带 return）；
- 体内没有 if/for/while/do/switch/try/?:/&&/|| ——有守卫的递归是合法写法，不报。

用法：
  python3 tools/audit_self_call.py [根目录]     # 默认 entry/src
  python3 tools/audit_self_call.py --selftest   # 先过阳性/阴性对照再出数
退出码：0=无命中；1=有命中；2=selftest 未过。
"""
import re
import sys
from pathlib import Path

GUARDS = re.compile(r"\b(if|for|while|do|switch|try|case)\b|[?:&|]|\bawait\b")
DECL = re.compile(r"(?:(?:private|public|protected|static|async|readonly)\s+)*([A-Za-z_]\w*)\s*\([^()]*\)\s*(?::[^{]+)?\{")


def strip_body_braces(text, open_idx):
    """从 '{' 处按配平取出方法体（跳过字符串里的括号与花括号）。"""
    depth = 0
    i = open_idx
    quote = None
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "'\"`":
            quote = ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[open_idx + 1:i], i
        i += 1
    return None, -1


def find_self_calls(path, text):
    hits = []
    types = [(m.start(), m.group(1)) for m in
             re.finditer(r"\b(?:class|struct|interface)\s+([A-Z]\w*)", text)]
    for m in DECL.finditer(text):
        name = m.group(1)
        body, _end = strip_body_braces(text, m.end() - 1)
        if body is None:
            continue
        stmt = body.strip()
        if stmt.endswith(";"):
            stmt = stmt[:-1].strip()
        if not stmt or GUARDS.search(stmt):
            continue
        # 只有一条语句且它在叫自己
        if ";" in stmt or "\n" in _collapse(stmt):
            continue
        # 自身写法：this.x() / x() / 宿主类名.x()。别的类上的同名方法不算（PaceRule.dailyCap 那种是委托）
        owner = [t for pos, t in types if pos < m.start()]
        receivers = ["this"] + (owner[-1:] if owner else [])
        qualified = re.match(
            r"^(?:return\s+)?(" + "|".join(re.escape(r) for r in receivers) + r")\." +
            re.escape(name) + r"\s*\(", stmt)
        bare = re.match(r"^(?:return\s+)?" + re.escape(name) + r"\s*\(", stmt)
        if qualified or bare:
            line = text[:m.start()].count("\n") + 1
            hits.append((line, name, " ".join(stmt.split())))
    return hits


def _collapse(s):
    return re.sub(r"\s+", " ", s)


def scan(root):
    findings = []
    for f in sorted(Path(root).rglob("*.ets")):
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for line, name, stmt in find_self_calls(str(f), text):
            findings.append(f"{f}:{line} {name}() → {stmt}")
    return findings


SELFTEST_POS = [
    ("bare this-call", "struct A {\n  private f(): void {\n    this.f();\n  }\n}"),
    ("with return", "struct A {\n  private f(): string {\n    return this.f();\n  }\n}"),
    ("qualified static", "class A {\n  static f(): void {\n    A.f();\n  }\n}"),
    ("blank lines inside", "struct A {\n  private f(): void {\n\n    this.f();\n\n  }\n}"),
]
SELFTEST_NEG = [
    ("guarded recursion", "struct A {\n  private f(n: number): void {\n    if (n > 0) {\n      this.f(n - 1);\n    }\n  }\n}"),
    ("delegates to another method", "struct A {\n  private f(): void {\n    this.g();\n  }\n}"),
    ("two statements", "struct A {\n  private f(): void {\n    const n: number = 1;\n    this.f();\n  }\n}"),
    ("not a call", "struct A {\n  private f(): void {\n    this.x = 1;\n  }\n}"),
    ("string that mentions itself", "struct A {\n  private f(): void {\n    Logger.info('t', 'this.f()');\n  }\n}"),
    ("delegates to sibling class same name", "class B {\n  static f(): string {\n    return '';\n  }\n}\nclass A {\n  private f(): string {\n    return B.f();\n  }\n}"),
]


def selftest():
    ok = True
    for label, src in SELFTEST_POS:
        hits = find_self_calls("mem", src)
        if not hits:
            print(f"  !! 阳性对照未命中：{label}")
            ok = False
    for label, src in SELFTEST_NEG:
        hits = find_self_calls("mem", src)
        if hits:
            print(f"  !! 阴性对照误报：{label} → {hits}")
            ok = False
    print(f"selftest {'PASS' if ok else 'FAIL'}（阳性 {len(SELFTEST_POS)} · 阴性 {len(SELFTEST_NEG)}）")
    return ok


def main():
    args = [a for a in sys.argv[1:]]
    if "--selftest" in args:
        if not selftest():
            return 2
        args.remove("--selftest")
    root = args[0] if args else "entry/src"
    findings = scan(root)
    if findings:
        print(f"无守卫自递归 {len(findings)} 处（运行即栈溢出）：")
        for f in findings:
            print(f"  {f}")
        return 1
    print(f"自递归尺：0 命中（扫 {root} 的 .ets）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
