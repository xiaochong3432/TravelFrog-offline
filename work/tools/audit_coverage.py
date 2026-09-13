#!/usr/bin/env python3
"""Audit how much of the wire protocol the offline engine actually implements.

Answers: of the N commands in the client's ProtocolList, which ones does
engine/index.js handle, and which of the *unhandled* ones does the client
actually need (needResponse) or push-expect?

Usage: python audit_coverage.py
"""
import os
import re
import subprocess

ROOT = r"H:\AI\frog"
ENGINE = os.path.join(ROOT, r"work\run\engine\index.js")
PROTOCOL = os.path.join(ROOT, r"work\run\engine\protocol.js")


def load_protocol():
    out = subprocess.run(
        ["node", "-e",
         f"const p=require({PROTOCOL!r});"
         "console.log(JSON.stringify(p))"],
        capture_output=True, encoding="utf-8", errors="replace")
    if out.returncode != 0:
        raise SystemExit("node failed: " + out.stderr)
    import json
    return json.loads(out.stdout)


def main():
    proto = load_protocol()
    src = open(ENGINE, encoding="utf8").read()

    # protocol handlers live in the `handlers` object literal; GM commands in a
    # switch. Collect identifiers of the form word_word: from the handlers block.
    start = src.index("const handlers = {")
    end = src.index("function dispatch(", start)
    block = src[start:end]
    handled = set(re.findall(r"^\s{4}([a-z][a-z0-9_]*)\s*:", block, re.M))

    # boot pushes count as implemented (the client never sends those)
    boot_start = src.index("const BOOT_PUSH = [")
    boot_end = src.index("];", boot_start)
    boot = set(re.findall(r"'([a-z0-9_]+)'", src[boot_start:boot_end]))

    print(f"protocol commands in ProtocolList : {len(proto)}")
    need = {k for k, v in proto.items() if v.get("needResponse")}
    print(f"  of which needResponse           : {len(need)}")
    print(f"handlers implemented              : {len(handled)}")
    print(f"BOOT_PUSH (client never sends)    : {len(boot)}")

    missing = sorted(set(proto) - handled)
    missing_need = sorted(set(need) - handled - boot)

    print(f"\nNOT implemented                    : {len(missing)}")
    print(f"NOT implemented AND needResponse   : {len(missing_need)}")

    print("\n--- not implemented, grouped by system ---")
    groups = {}
    for name in missing:
        groups.setdefault(name.split("_")[0], []).append(name)
    for g in sorted(groups, key=lambda k: -len(groups[k])):
        names = groups[g]
        need_mark = sum(1 for n in names if n in need)
        print(f"  {g:14s} {len(names):3d} commands  ({need_mark} need a reply)")
        print(f"      {', '.join(names)}")

    print("\n--- implemented-but-worth-checking (handlers with stub-looking bodies) ---")
    for name in sorted(handled):
        m = re.search(r"^\s{4}" + re.escape(name) + r"\s*:\s*(.{0,90})", block, re.M)
        if m:
            body = m.group(1).strip()
            if re.match(r"^\(\)\s*=>\s*\(\{\s*\}\)", body) or "code: 0" == body.strip("{} "):
                print(f"  {name:28s} {body}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
