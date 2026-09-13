#!/usr/bin/env python3
"""Analyze the reference (single-player) Unity Assembly-CSharp.dll.

Uses dnfile for .NET metadata when available; falls back to raw string census.
"""
import re, sys, os, collections

P = r"H:\AI\frog\work\frog\assets\bin\Data\Managed\Assembly-CSharp.dll"

def raw_census():
    d = open(P, "rb").read()
    print(f"size = {len(d)} bytes")
    strs = sorted({s.decode("utf8", "replace") for s in re.findall(rb"[\x20-\x7e]{4,90}", d)})
    kws = ["Save", "Load", "PlayerPrefs", "Server", "Http", "Url", "API", "Random",
           "Item", "Goods", "Travel", "Frog", "Photo", "Local", "Json", "Offline",
           "Login", "User", "Data", "Time", "Scene", "Shop", "Bag", "Ticket"]
    for k in kws:
        hits = [s for s in strs if k.lower() in s.lower()]
        if hits:
            print(f"\n### {k} ({len(hits)}) ###")
            for h in hits[:30]:
                print("   ", h)

def metadata():
    try:
        import dnfile
    except ImportError:
        print("dnfile not available; raw only")
        return
    pe = dnfile.dnPE(P)
    print("\n===== .NET metadata =====")
    try:
        ver = pe.net.metadata.struct.MajorRuntimeVersion, pe.net.metadata.struct.MinorRuntimeVersion
    except Exception:
        ver = "?"
    print("runtime:", ver)
    if not pe.net or not pe.net.mdtables:
        print("no metadata tables")
        return
    td = pe.net.mdtables.TypeDef
    print(f"TypeDef count: {len(td.rows)}")
    ns = collections.Counter()
    types = []
    for t in td.rows:
        n = str(t.TypeName)
        nsp = str(t.TypeNamespace)
        name = f"{nsp}.{n}" if nsp else n
        types.append(name)
        ns[nsp] += 1
    print("\ntop namespaces:")
    for k, v in ns.most_common(30):
        print(f"{v:5d}  {k or '(global)'}")
    print(f"\nall types ({len(types)}):")
    for t in sorted(types):
        print("   ", t)

if __name__ == "__main__":
    raw_census()
    metadata()
