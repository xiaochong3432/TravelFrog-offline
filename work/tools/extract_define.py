#!/usr/bin/env python3
"""Extract the game's tuning-constant table out of the client's `Define` object.

Several agents independently noticed that keys like FRIEND_VISIT_COOL,
FRIEND_GIFTPER_NORMAL and PrizeBalls appear in the minified client EXACTLY ONCE --
at their definition -- and are never read by any client code. That means the
original *server's* tuning values were shipped inside the client, which turns a
lot of previously-guessed gameplay numbers (visitor cadence, gift odds, lottery
weights) into documented values.

The block is a single large object literal, mostly written with the minifier's
"(p={},p[Enum.X]=v,p[Enum.Y]=w,p)" idiom. This walks the braces and rewrites that
idiom into plain "X: v" lines.

Usage: python extract_define.py
"""
import re
import sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
OUT = r"H:\AI\frog\work\build\define_block.txt"

raw = open(JS, "rb").read().decode("utf-8", "replace")

# anchor: a constant we know lives inside the block
anchor = raw.find("PrizeBalls")
if anchor < 0:
    raise SystemExit("anchored keyword not found")

# Find the TRULY enclosing '{' by balancing backwards: scanning left from the
# anchor, a '}' deepens the nesting and a '{' closes it. The first '{' that takes
# depth below zero is the one we want. (A plain rfind grabs a nested '{}' instead.)
depth = 0
start = -1
for i in range(anchor, -1, -1):
    c = raw[i]
    if c == "}":
        depth += 1
    elif c == "{":
        if depth == 0:
            start = i
            break
        depth -= 1
if start < 0:
    raise SystemExit("no enclosing brace")

depth = 0
end = start
while end < len(raw):
    c = raw[end]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            break
    end += 1

block = raw[start:end + 1]

# rewrite the minifier idiom: (x={},x[A]=B,x[C]=D,x)  ->  A: B, C: D
def unfold(text):
    # Only the minifier's "Name:(x={},x[A]=v,x[C]=w,x)" idiom may be unfolded, and
    # the piece carries its "Name:" prefix, so test for the idiom rather than for a
    # leading "(". Splitting every piece silently mangled ordinary literal maps whose
    # values are identifier-like: `FrogMotionNum:{doku:0,doku_s:1,...}` broke at every
    # comma and the map was lost (likewise Season / HoursType / WeatherType).
    if not re.search(r":\([A-Za-z_$][\w$]*=\{\},", text):
        return text
    out = []
    for part in re.split(r",(?=[A-Za-z_$])", text):
        m = re.match(r"^\(([A-Za-z_$][\w$]*)=\{\},(.*)\)$", part, re.S)
        if not m:
            out.append(part)
            continue
        var, rest = m.group(1), m.group(2)
        pairs = re.findall(rf"{re.escape(var)}\[([^\]]+)\]\s*=\s*([^,]+)", rest)
        if pairs:
            out.append("  ".join(f"{k.strip()}: {v.strip()}," for k, v in pairs))
        else:
            out.append(part)
    return ",\n".join(out)

# split the top level on commas to get one constant per line
body = block[1:-1]
pieces = []
depth2 = 0
cur = []
for ch in body:
    if ch in "[{(":
        depth2 += 1
    elif ch in "]})":
        depth2 -= 1
    if ch == "," and depth2 == 0:
        pieces.append("".join(cur))
        cur = []
    else:
        cur.append(ch)
if cur:
    pieces.append("".join(cur))

lines = []
for p in pieces:
    p = p.strip()
    if not p:
        continue
    p = unfold(p)
    lines.append(p)

with open(OUT, "w", encoding="utf-8") as f:
    f.write(f"// extracted from {JS}\n")
    f.write(f"// block spans offsets {start}..{end} ({len(block)} chars)\n")
    f.write(f"// {len(lines)} top-level constants\n\n")
    for ln in lines:
        f.write(ln.rstrip() + "\n")

print(f"wrote {OUT}: {len(lines)} constants, block {len(block)} chars")
