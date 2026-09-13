#!/usr/bin/env python3
"""Dump a class body by name (brace-balanced) for readability."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, sys

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")


def classbody(name):
    m = re.search(r'var\s+' + re.escape(name) + r'\s*=\s*function', d)
    if not m:
        return None
    # include the enclosing statement up to the __reflect for that class
    r = re.search(r'__reflect\(\s*' + re.escape(name) + r'\.prototype', d[m.start():])
    end = m.start() + r.end() if r else m.start() + 4000
    return d[m.start():end]


def wrap(s):
    out, depth = [], 0
    for ch in s:
        if ch == "{":
            depth += 1; out.append(ch + "\n" + "  " * depth)
        elif ch == "}":
            depth = max(0, depth - 1); out.append("\n" + "  " * depth + ch)
        elif ch == ";":
            out.append(ch + "\n" + "  " * depth)
        else:
            out.append(ch)
    return "".join(out)


if __name__ == "__main__":
    name = sys.argv[1]
    out = sys.argv[2]
    b = classbody(name)
    if not b:
        print("not found:", name); sys.exit(1)
    open(out, "w", encoding="utf8").write(wrap(b))
    print(f"{name}: {len(b)} chars -> {out}")
