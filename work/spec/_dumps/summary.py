#!/usr/bin/env python3
"""Summarise Item / Picture / Note tables for the travel spec."""
import json, io, sys, collections

out = io.open(r"H:\AI\frog\work\spec\_dumps\tables_summary.txt", "w", encoding="utf8")
B = r"H:\AI\frog\work\spec\_dumps\tables\%s.json"


def load(n):
    return json.load(open(B % n, encoding="utf8"))


def w(s):
    out.write(s + "\n")


item = load("Item")
w("### Item: %d entries" % len(item))
keys = collections.Counter()
for e in item:
    for k in e:
        keys[k] += 1
w("keys: %s" % dict(keys))
byt = collections.Counter(e.get("type") for e in item)
w("type histogram: %s" % dict(sorted(byt.items(), key=lambda x: (x[0] is None, x[0]))))
for t in (0, 1, 2, 3, 5, 14):
    ex = [e for e in item if e.get("type") == t]
    w("-- type %s: %d entries, ids %s" % (t, len(ex), [e["id"] for e in ex][:20]))
    for e in ex[:3]:
        w("     %s" % json.dumps(e, ensure_ascii=False)[:400])
w("")

pic = load("Picture")
w("### Picture: %d" % len(pic))
pt = collections.Counter(e.get("type") for e in pic)
w("type histogram: %s" % dict(pt))
w("place histogram (top): %s" % collections.Counter(e.get("place") for e in pic).most_common(12))
w("view histogram: %s  share: %s  effect non-empty: %d" % (
    [json.dumps(x) for x in collections.Counter(
        json.dumps(e.get("view"), sort_keys=True) for e in pic).most_common(6)],
    collections.Counter(e.get("share") for e in pic),
    sum(1 for e in pic if e.get("effect"))))
w("view example: %s" % json.dumps(pic[0].get("view"), ensure_ascii=False))
for e in pic[:2]:
    w(json.dumps(e, ensure_ascii=False))
for e in pic:
    if e.get("place"):
        w("first with place: %s" % json.dumps(e, ensure_ascii=False))
        break
w("")

note = load("Note")
w("### Note: %d" % len(note))
for tid in sorted({v.get("type") for v in note.values()}, key=lambda x: (x is None, x)):
    ids = sorted(int(k) for k, v in note.items() if v.get("type") == tid)
    w("type %s: %d ids, range %s..%s" % (tid, len(ids), ids[0], ids[-1]))
own = sorted(int(k) for k, v in note.items() if v.get("factorType") == "Own_Note")
w("Own_Note: %d, ids %s..%s" % (len(own), own[0], own[-1]))
w("")

word = load("Word")
w("### Word: %d, types %s" % (len(word), collections.Counter(v.get("type") for v in word.values())))
for k in list(word)[:3]:
    w("  %s %s" % (k, json.dumps(word[k], ensure_ascii=False)))
w("")

coll = load("Collection")
w("### Collection: %d, types %s" % (len(coll), collections.Counter(e.get("type") for e in coll)))
for e in coll[:2]:
    w("  %s" % json.dumps(e, ensure_ascii=False))
res = load("resources")
w("### resources: %d entries (resId -> path)" % len(res))
for k in ["0", "1", "2", "3", "4", "5", "100", "200"]:
    if k in res:
        w("  %s -> %s" % (k, res[k]))
out.close()
print("ok ->", out.name)
