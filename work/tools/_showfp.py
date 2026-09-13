import json
d = json.load(open(r"H:\AI\frog\work\run\engine\data\define.json", encoding="utf-8"))
m = d["maps"]
print("maps now:", sorted(m.keys()))
if "Frogpattern" in m:
    for k in sorted(m["Frogpattern"]):
        print(f"  pattern {k}: {m['Frogpattern'][k]}")
print("FrogMotionNum:", m.get("FrogMotionNum"))
