#!/usr/bin/env python3
"""Turn the extracted Define block into engine/data/define.json.

The block (see extract_define.py) mixes three shapes:
    NAME:scalar
    NAME:{literal, map}                 e.g. Season:{spring:1, summer:2}
    NAME:(v={},v[Enum.Member]=val,...,v)   minifier idiom for enum-keyed maps

This resolves all three. Enum keys are reduced to their final segment
(Prize.Rank.White -> White) -- the numeric enum values are not needed, because
every consumer in the engine wants the map keyed by NAME, not by enum ordinal.

Verification built in: PrizeBalls' rank entries must sum to its RankMax entry
(40+25+22+9+3+1 == 100), which is a real check that the six rank entries were
captured and not, say, truncated.

Usage: python build_define_json.py
"""
import json
import os
import re
import sys

BLOCK = r"H:\AI\frog\work\build\define_block.txt"
OUT = r"H:\AI\frog\work\run\engine\data\define.json"


def parse_scalar(tok):
    tok = tok.strip()
    if tok in ("!0", "!1"):
        return tok == "!0"
    if re.fullmatch(r"-?\d+", tok):
        return int(tok)
    if re.fullmatch(r"-?\d*\.?\d+(e-?\d+)?", tok):
        return float(tok)
    if tok.startswith('"') and tok.endswith('"'):
        return tok[1:-1]
    return None


def split_top(s):
    """Split on commas that are NOT inside [], quotes or nesting."""
    out, cur, depth, in_str = [], [], 0, False
    for ch in s:
        if in_str:
            cur.append(ch)
            if ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
            cur.append(ch)
            continue
        if ch in "[{(":
            depth += 1
        elif ch in "]})":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    if cur:
        out.append("".join(cur))
    return out


def parse_value(tok):
    """A scalar, or an array literal (whose elements may themselves contain commas)."""
    tok = tok.strip()
    if tok.startswith("[") and tok.endswith("]"):
        vals = []
        for piece in split_top(tok[1:-1]):
            if not piece.strip():
                continue
            v = parse_value(piece)
            if v is None:
                return None
            vals.append(v)
        return vals
    return parse_scalar(tok)


def main():
    text = open(BLOCK, encoding="utf-8").read()
    lines = [ln.rstrip() for ln in text.splitlines() if not ln.startswith("//")]

    scalars, maps = {}, {}
    i = 0
    while i < len(lines):
        ln = lines[i].strip()
        i += 1
        if not ln:
            continue
        # NB: do NOT skip lines ending in ',' -- a block opener such as
        # "PrizeBalls:(p={}," ends with one, and skipping it loses the whole map.
        if ":" not in ln:
            continue
        name, rhs = ln.split(":", 1)
        name, rhs = name.strip(), rhs.rstrip().rstrip(",")

        # minifier idiom: NAME:(v={},  then v[Enum.Member]=value, ...  then v)
        if rhs.startswith("("):
            var = re.match(r"^\((\w+)=\{\},?$", rhs)
            if not var:
                continue
            v = var.group(1)
            entries = {}
            while i < len(lines):
                nxt = lines[i].strip()
                i += 1
                if nxt in (v + ")", v):
                    break
                m = re.match(rf"^{re.escape(v)}\[([^\]]+)\]\s*=\s*(.+?),?$", nxt)
                if m:
                    key = m.group(1).strip().split(".")[-1]
                    val = parse_scalar(m.group(2))
                    if val is not None:
                        entries[key] = val
            if entries:
                maps[name] = entries
            continue

        # literal map on one line: {a:1, b:2, c:[1,2,3]}
        # NB: values may be ARRAYS containing commas, so a naive k:v regex drops the
        # whole entry -- that is how Frogpattern went missing the first time.
        if rhs.startswith("{") and rhs.endswith("}"):
            entries = {}
            for piece in split_top(rhs[1:-1]):
                if ":" not in piece:
                    continue
                k, v = piece.split(":", 1)
                k = k.strip().strip('"')
                val = parse_value(v.strip())
                if val is not None:
                    entries[k] = val
            if entries:
                maps[name] = entries
            continue

        # array literal
        if rhs.startswith("[") and rhs.endswith("]"):
            vals = [parse_scalar(x) for x in rhs[1:-1].split(",")]
            if all(v is not None for v in vals):
                maps[name] = vals
            continue

        val = parse_scalar(rhs)
        if val is not None:
            scalars[name] = val

    # ---- verification: the prize rank weights must total RankMax
    balls = maps.get("PrizeBalls", {})
    ranks = {k: v for k, v in balls.items() if k != "RankMax"}
    total = sum(ranks.values())
    expect = balls.get("RankMax")
    ok = expect is not None and total == expect

    out = {
        "_source": "Tabikaeru.Define in assets/game/js/main.min.js "
                   "(offsets 418503..423223) - the original server's tuning table",
        "_note": "VERSION is 1.07, i.e. these constants came from the Japanese "
                 "single-player build that the China version reused.",
        "scalars": scalars,
        "maps": maps,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)

    print(f"scalars: {len(scalars)}   maps: {len(maps)}")
    print(f"prize weight check: {ranks} total={total} vs RankMax={expect} -> "
          f"{'OK' if ok else 'MISMATCH'}")
    print(f"wrote {OUT} ({os.path.getsize(OUT):,} bytes)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
