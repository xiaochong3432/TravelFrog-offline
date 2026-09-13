import json, os
D = r"H:\AI\frog\work\run\engine\data\tables"
out = open(r"H:\AI\frog\work\build\origin_map.txt", "w", encoding="utf-8")
origin = json.load(open(os.path.join(D, "origin.json"), encoding="utf-8"))
out.write("=== origin table (all) ===\n")
for k, v in sorted(origin.items()):
    out.write(f"  {k:22s} -> {v}\n")
out.close()
print("written")
