import json, os
D = r"H:\AI\frog\work\run\engine\data\tables"
ach = json.load(open(os.path.join(D,"Achieve.json"), encoding="utf-8"))
out = open(r"H:\AI\frog\work\build\achieve.txt","w",encoding="utf-8")
out.write(f"Achieve rows: {len(ach)}\n")
out.write("keys: %s\n\n" % list(ach[0].keys()))
for a in ach:
    out.write(f"  id={a.get('id'):<4} name={a.get('name')!r:<22} info={a.get('info')!r} special={a.get('is_special')!r}\n")
out.close(); print("ok")
