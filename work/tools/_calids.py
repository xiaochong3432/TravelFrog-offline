import json, os
D = r"H:\AI\frog\work\run\engine\data\tables"
items = {i["id"]: i for i in json.load(open(os.path.join(D,"Item.json"), encoding="utf-8"))}
cd = json.load(open(os.path.join(D,"calendarData.json"), encoding="utf-8"))
out = open(r"H:\AI\frog\work\build\cal_ids.txt","w",encoding="utf-8")
bad = []
for k in sorted(cd["beginner"], key=lambda x:int(x)):
    e = cd["beginner"][k]
    iid = e["item_id"]
    it = items.get(iid)
    ok = iid in items
    if not ok: bad.append((k, iid))
    out.write(f"  day {k}: item_id={iid} num={e['num']} exists={ok} name={it.get('name') if it else '-'!r} type={it.get('type') if it else '-'}\n")
out.write(f"\nMISSING ids: {bad}\n")
# note ids used by beginner
out.write("note_ids: %s\n" % [cd["beginner"][k]["note_id"] for k in sorted(cd["beginner"], key=lambda x:int(x))])
out.write("all note_ids present in note table: %s\n" % all(str(cd["beginner"][k]["note_id"]) in cd["note"] for k in cd["beginner"]))
out.close(); print("ok")
