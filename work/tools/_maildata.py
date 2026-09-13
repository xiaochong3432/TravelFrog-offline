import json, os
D = r"H:\AI\frog\work\run\engine\data\tables"
out = open(r"H:\AI\frog\work\build\mail_data.txt","w",encoding="utf-8")
me = json.load(open(os.path.join(D,"MailEvent.json"), encoding="utf-8"))
out.write("MailEvent (full):\n")
out.write(json.dumps(me, ensure_ascii=False, indent=1)[:1800] + "\n")
out.close(); print("ok")
