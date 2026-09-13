#!/usr/bin/env python3
"""Print every occurrence of a literal in the client JS with surrounding context.

Needed because many protocol commands have NO `prototype.<cmd>` handler (they are
callback-style: the client sends the request and handles the reply in a closure).
For those, dump_handlers.py finds nothing and the reply shape has to be read off
the send site instead.

Usage: ctx_literal.py <literal> [window] [max_hits]
"""
import re
import sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"

lit = sys.argv[1]
win = int(sys.argv[2]) if len(sys.argv) > 2 else 320
maxhits = int(sys.argv[3]) if len(sys.argv) > 3 else 8

src = open(JS, encoding="utf8", errors="replace").read()


def out(*parts):
    """Print without dying on non-console-encodable characters (GBK terminal)."""
    enc = getattr(sys.stdout, "encoding", None) or "utf-8"
    text = " ".join(str(p) for p in parts)
    sys.stdout.write(text.encode(enc, "replace").decode(enc, "replace") + "\n")


out(f"searching {lit!r}  (file {len(src)} chars)")
hits = [m.start() for m in re.finditer(re.escape(lit), src)]
out(f"{len(hits)} occurrence(s)\n")

for i, at in enumerate(hits[:maxhits]):
    lo = max(0, at - win)
    hi = min(len(src), at + win)
    out(f"===== hit {i + 1}/{len(hits)} at offset {at} =====")
    out(src[lo:at] + ">>>" + lit + "<<<" + src[at + len(lit):hi])
    out()
