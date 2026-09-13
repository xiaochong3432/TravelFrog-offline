#!/usr/bin/env python3
"""Merge the A-tier rows while PRESERVING the retail formatting of every other table.

Why not json.dumps: the retail tables are serialized heterogeneously (only 11/60 match
`indent=2`; the rest use 5-space steps, `", "` separators, ragged nesting, ...). A single
serializer therefore cannot reproduce them, and re-serializing all 60 rewrote 51 tables
that had no business changing (it shrank config.eab by ~350 KB with no content change).

This tool starts from the RETAIL bundle and performs TEXT surgery:
  * untouched tables      -> byte-identical to retail (passed through untouched);
  * modified tables       -> the retail text is kept as-is and the new rows are APPENDED,
                            formatted to match the indentation of the last existing element
                            (measured from the text, not assumed).

Usage:
    python tools/merge_rows_preserving_format.py --apply
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import argparse
import json
import os
import re
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eab_decrypt as E      # noqa: E402
import eab_encode as ENC     # noqa: E402

ROOT = str(PROJECT_ROOT)
WEB = os.path.join(ROOT, "work", "run", "web")
OUR_EAB = os.path.join(WEB, "resource", "China", "eab", "config.eab")
BACKUP_ROOT = os.path.join(ROOT, "work", "merge-backup")
RETAIL = os.path.join(BACKUP_ROOT, "20260912-202751", "resource", "China", "eab", "config.eab")
THEIR_EAB = os.path.join(ROOT, "work", "compare-eab", "theirs.eab")

ROW_TABLES = ["furnitureData_json", "furnitureShopData_json", "shopData_json", "Item_json",
              "Picture_json", "PictureTag_json", "furnitureCommon_json", "benchData_json"]


def load(path):
    man, payload, _ = E.open_bundle(path)
    entries, blobs, pos = [], [], 0
    for it in man:
        entries.append(dict(it))
        blobs.append(payload[pos:pos + it["s"]])
        pos += it["s"]
    return entries, blobs


def rows_of(t):
    return list(t.values()) if isinstance(t, dict) else list(t)


def key_of(t, row):
    return list(t.keys())[list(t.values()).index(row)] if isinstance(t, dict) else None


def measure_indent(text):
    """(element_indent, step) measured from the LAST element of a JSON table text."""
    closes = text.rstrip()
    close_ch = closes[-1]                      # ']' or '}'
    body = closes[:-1]
    # last element opener: the last line whose stripped content starts with { or [
    lines = body.split("\n")
    idx = None
    for i in range(len(lines) - 1, -1, -1):
        s = lines[i].lstrip()
        if s.startswith("{") or s.startswith("["):
            idx = i
            break
    if idx is None:
        return 0, 2
    elem_indent = len(lines[idx]) - len(lines[idx].lstrip())
    step = 2
    for j in range(idx + 1, len(lines)):
        s = lines[j]
        if s.strip().startswith('"'):
            inner = len(s) - len(s.lstrip())
            step = max(1, inner - elem_indent)
            break
    return elem_indent, step


def insert_rows(text, rendered, closing):
    """Append pre-rendered row texts just before the final closing bracket."""
    stripped = text.rstrip()
    assert stripped.endswith(closing), "unexpected table tail"
    head = stripped[: -len(closing)].rstrip()
    # the separator that the retail text already uses before the last element
    m = re.search(r"(\n[ \t]*)$", head)
    tail_ws = m.group(1) if m else "\n"
    body = head.rstrip()
    return body + "," + tail_ws + ("," + tail_ws).join(rendered) + "\n" + stripped[len(stripped) - len(closing):]


def render(row, elem_indent, step, as_dict_entry=False, key=None):
    text = json.dumps(row, ensure_ascii=False, indent=step)
    lines = text.split("\n")
    out = []
    for i, line in enumerate(lines):
        out.append((" " * elem_indent) + line if i else (" " * elem_indent) + line)
    rendered = "\n".join(out)
    if as_dict_entry:
        rendered = '"%s": %s' % (key, rendered)
    return rendered


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    entries, blobs = load(RETAIL)
    their_entries, their_blobs = load(THEIR_EAB)
    their_tables = {e["n"]: json.loads(b.decode("utf-8")) for e, b in zip(their_entries, their_blobs)}
    our_tables = {e["n"]: json.loads(b.decode("utf-8")) for e, b in zip(entries, blobs)}

    report = {}
    for name in ROW_TABLES:
        i = next(k for k, e in enumerate(entries) if e["n"] == name)
        text = blobs[i].decode("utf-8")
        o, t = our_tables[name], their_tables[name]
        elem_indent, step = measure_indent(text)
        closing = "]" if isinstance(o, list) else "}"
        added = []
        if isinstance(o, list):
            have = {str(r.get("id")) for r in o}
            # Appended at the end (text surgery) rather than re-serialized: the retail
            # formatting of every existing row must survive. The reference build puts
            # benchData's new rows in the middle (index 245); the list order is cosmetic
            # for the client's craftable list, so we accept the difference and record it.
            for row in rows_of(t):
                if str(row.get("id")) not in have:
                    added.append(render(row, elem_indent, step))
        else:
            have = {str(r.get("id")) for r in o.values()}
            for k, row in t.items():
                if str(row.get("id")) not in have:
                    added.append(render(row, elem_indent, step, True, k))
        if not added:
            print(f"  {name:26} nothing to add")
            continue
        new_text = insert_rows(text, added, closing)
        json.loads(new_text)                      # must stay valid
        blobs[i] = new_text.encode("utf-8")
        report[name] = {"added": len(added), "elem_indent": elem_indent, "step": step,
                        "bytes": [len(text), len(blobs[i])]}
        print(f"  {name:26} +{len(added)} rows  (indent={elem_indent}, step={step}, "
              f"{len(text)} -> {len(blobs[i])} B)")

    # resources_json is dict-shaped but keyed by resId strings -> same path
    name = "resources_json"
    i = next(k for k, e in enumerate(entries) if e["n"] == name)
    text = blobs[i].decode("utf-8")
    o, t = our_tables[name], their_tables[name]
    elem_indent, step = measure_indent(text)
    added = [render(v, elem_indent, step, True, k) if False else None for k, v in []]
    added = []
    for k, v in t.items():
        if k not in o:
            added.append(('" %s"' % k).replace('" ', '"') + ": " + json.dumps(v, ensure_ascii=False))
    if added:
        new_text = insert_rows(text, added, "}")
        json.loads(new_text)
        blobs[i] = new_text.encode("utf-8")
        report[name] = {"added": len(added), "bytes": [len(text), len(blobs[i])]}
        print(f"  {name:26} +{len(added)} keys")

    out = ENC.build(entries, blobs)
    print(f"\nrebuilt bundle: {len(out)} bytes (retail {os.path.getsize(RETAIL)})")
    if args.apply:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        bak = os.path.join(BACKUP_ROOT, stamp, "resource", "China", "eab", "config.eab")
        os.makedirs(os.path.dirname(bak), exist_ok=True)
        shutil.copy2(OUR_EAB, bak)
        open(OUR_EAB, "wb").write(out)
        print(f"written; previous tree copy backed up to {bak}")
    else:
        print("(dry run -- nothing written)")
    json.dump(report, open(os.path.join(ROOT, "work", "format-merge-report.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
