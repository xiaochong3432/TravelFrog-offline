#!/usr/bin/env python3
"""Audit engine handlers against the client's REAL protocol parameter names.

WHY: every other test in this repo calls `FrogEngine.dispatch(cmd, payload)`
with a payload the test author invented. The client does not send free-form JSON
-- `SocketManage.send` maps positional arguments onto the parameter names
declared in ProtocolList:

    u.data = {}; for (p=0; p<params.length; p++) u.data[params[p]] = args[p];

so a handler that reads `d.id` for a command whose declared parameter is
`shop_id` receives undefined and silently fails. That is exactly how
`furniture_buy_shop` came to return {code:-1} forever, making the whole
furniture merchant (including the 分享拿福利 welfare goods) dead.

This script reports, per command:
  MISSING-PARAM  a declared parameter name never appears in the handler body
  UNKNOWN-READ   the handler reads a payload field that is not declared

Usage: python tools/audit_params.py [--only cmd1,cmd2] [--verbose]
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROTOCOL = os.path.join(ROOT, "run", "engine", "protocol.js")
ENGINE = os.path.join(ROOT, "run", "engine", "index.js")


def load_protocol():
    with open(PROTOCOL, encoding="utf-8") as fh:
        t = fh.read()
    t = t[t.index("{"):t.rindex("}") + 1]
    return json.loads(t)


def handler_bodies(src):
    """Map command -> body text for `cmd: (args) => { ... }` entries."""
    out = {}
    for m in re.finditer(r"^\s{4}([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\(", src, re.M):
        cmd = m.group(1)
        i = m.end() - 1                      # at '(' of the parameter list
        depth = 0
        j = i
        n = len(src)
        started = False
        while j < n:
            ch = src[j]
            if ch == "(":
                depth += 1
                started = True
            elif ch == ")":
                depth -= 1
                if started and depth == 0:
                    break
            j += 1
        # now walk the body until depth-balanced, tracking strings and comments
        k = j + 1
        while k < n and src[k] in " \t":
            k += 1
        if k < n and src[k] == "=" and src[k + 1:k + 2] == ">":
            k += 2
        while k < n and src[k] in " \t":
            k += 1
        if k >= n or src[k] != "{":
            # expression-bodied: take to end of line
            e = src.find("\n", k)
            out[cmd] = src[k:e if e > 0 else n]
            continue
        depth = 0
        e = k
        in_s = None
        while e < n:
            ch = src[e]
            if in_s:
                if ch == "\\":
                    e += 2
                    continue
                if ch == in_s:
                    in_s = None
            elif ch in "'\"`":
                in_s = ch
            elif src.startswith("//", e):
                nl = src.find("\n", e)
                e = nl if nl > 0 else n
                continue
            elif src.startswith("/*", e):
                end = src.find("*/", e)
                e = (end + 2) if end > 0 else n
                continue
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    break
            e += 1
        out[cmd] = src[k:e + 1]
    return out


def read_fields(body):
    """Payload field names the handler actually looks at.

    Must see through the accessor helpers the engine uses, or the report is
    misleading: `posOf(d)` reads pos/index and `shopIdOf(d)` reads shop_id/id, so
    a handler written with them showed up as "never reads pos" until this was
    taught about them. `firstDefined(d, ['a','b'])` lists names directly.
    """
    names = set()
    for m in re.finditer(r"\bd\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)", body):
        names.add(m.group(1))
    for m in re.finditer(r"\bd\s*\[\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]\s*\]", body):
        names.add(m.group(1))
    for m in re.finditer(r"\{\s*([^}]*?)\s*\}\s*=\s*d\b", body):
        for part in m.group(1).split(","):
            nm = part.split(":")[0].strip()
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", nm):
                names.add(nm)
    # firstDefined(d, ['a', 'b'])
    for m in re.finditer(r"firstDefined\(\s*d\s*,\s*\[([^\]]*)\]", body):
        for nm in re.findall(r"['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]", m.group(1)):
            names.add(nm)
    # the named accessors
    if re.search(r"\bposOf\s*\(\s*d\b", body):
        names.update({"pos", "index"})
    if re.search(r"\bshopIdOf\s*\(\s*d\b", body):
        names.update({"shop_id", "id"})
    return names


FALSY_OK = {"cmd", "data", "session", "timestamp", "id", "type", "code"}

# Verified by hand against the client's own call sites: the handler is correct even
# though the declared name is not read. Listed here with a reason so the report
# stays trustworthy instead of crying wolf -- an audit nobody reads is worthless.
KNOWN_OK = {
    "furniture_flowerpot_harvest":
        "plantList() emits type:1 for EVERY row, so `type` carries no information; "
        "the slot is keyed by index alone, exactly as the handler does.",
    "mail_load_mails":
        "the client only reads start/total from the reply (count is used from its "
        "own REQUEST), and `is_clear` only asks the server to drop ad mails -- no "
        "mail the engine creates has an ads_id.",
    "guest_serve":
        "guarded now: `id` is read to reject a stale request, but the served guest "
        "comes from state.guest because only one visitor exists at a time.",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    proto = load_protocol()
    with open(ENGINE, encoding="utf-8") as fh:
        src = fh.read()
    bodies = handler_bodies(src)

    only = set(args.only.split(",")) if args.only else None

    missing, unknown, both_empty = [], [], 0
    checked = 0
    for cmd, info in sorted(proto.items()):
        params = info.get("params") or []
        if not params:
            continue
        if only and cmd not in only:
            continue
        body = bodies.get(cmd)
        if body is None:
            continue
        checked += 1
        reads = read_fields(body)
        if not reads:
            both_empty += 1
            continue
        miss = [p for p in params if p not in reads]
        if miss:
            missing.append((cmd, params, sorted(reads), miss))
        extra = [r for r in sorted(reads) if r not in params]
        if extra:
            unknown.append((cmd, params, extra))

    print("commands with declared params and an engine handler: %d" % checked)
    print("handlers that never touch the payload: %d" % both_empty)

    print("\n=== MISSING-PARAM: declared name never read (handler likely looks for the wrong key) ===")
    for cmd, params, reads, miss in missing:
        if cmd in KNOWN_OK:
            print("  %-28s declared=%s  reads=%s  NEVER=%s\n      OK: %s"
                  % (cmd, params, reads, miss, KNOWN_OK[cmd]))
            continue
        print("  %-28s declared=%s  reads=%s  NEVER=%s" % (cmd, params, reads, miss))
    if not missing:
        print("  (none)")

    print("\n=== UNKNOWN-READ: handler reads an undeclared field ===")
    fallbacks = []
    for cmd, params, extra in unknown:
        if cmd in KNOWN_OK:
            print("  %-28s declared=%s  extra=%s   OK: %s" % (cmd, params, extra, KNOWN_OK[cmd]))
            continue
        reads = read_fields(bodies[cmd])
        if all(p in reads for p in params):
            # every declared name IS read, so the extra names can only be
            # deliberate back-compat fallbacks -- not a bug
            fallbacks.append((cmd, extra))
            continue
        print("  %-28s declared=%s  extra=%s   <-- reads nothing declared"
              % (cmd, params, extra))
    if fallbacks:
        print("  (the following also read every declared name, so their extra keys are"
              " deliberate legacy fallbacks, not bugs:)")
        for cmd, extra in fallbacks:
            print("     %-28s extra=%s" % (cmd, extra))
    if not unknown:
        print("  (none)")
    if not unknown:
        print("  (none)")

    if args.verbose:
        print("\n=== all checked ===")
        for cmd in sorted(bodies):
            if cmd in proto and (proto[cmd].get("params") or []):
                print("  %-30s %s  reads=%s" % (cmd, proto[cmd]["params"], sorted(read_fields(bodies[cmd]))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
