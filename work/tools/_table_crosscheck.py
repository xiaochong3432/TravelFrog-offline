import json, os, hashlib
A = r"H:\AI\frog\work\run\engine\data\tables"   # my python XXTEA extraction
B = r"H:\AI\frog\work\spec\data"                # subagent js-decoder extraction
out = open(r"H:\AI\frog\work\build\table_crosscheck.txt", "w", encoding="utf-8")

def norm(obj):
    return hashlib.sha256(json.dumps(obj, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()

bfiles = os.listdir(B) if os.path.isdir(B) else []
out.write(f"B dir listing: {sorted(bfiles)}\n\n")

same = diff = onlyA = 0
for fn in sorted(os.listdir(A)):
    name = fn[:-5]
    pa, pb = os.path.join(A, fn), os.path.join(B, fn)
    if not os.path.exists(pb):
        # try alternate naming
        cands = [f for f in bfiles if f.lower().startswith(name.lower())]
        if cands:
            pb = os.path.join(B, cands[0])
        else:
            out.write(f"ONLY-A  {name}\n"); onlyA += 1; continue
    a = json.load(open(pa, encoding="utf-8"))
    b = json.load(open(pb, encoding="utf-8"))
    if norm(a) == norm(b):
        same += 1
    else:
        diff += 1
        out.write(f"DIFFER  {name}: A n={len(a) if hasattr(a,'__len__') else '?'} "
                  f"B n={len(b) if hasattr(b,'__len__') else '?'}\n")
out.write(f"\nidentical={same}  differing={diff}  only-in-A={onlyA}\n")
out.close()
print("written")
