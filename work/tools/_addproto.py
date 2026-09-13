import re
p = r"H:\AI\frog\work\run\engine\protocol.js"
src = open(p, encoding="utf-8").read()
if "notify_new_mail" in src:
    print("already present")
else:
    # push-only message: the client registers a handler but never sends it
    entry = (' "notify_new_mail": {\n'
             '  "needResponse": false,\n'
             '  "params": [],\n'
             '  "note": "push-only: registered via addProtocolCallback; absent from ProtocolList"\n'
             ' },\n')
    src = src.replace("module.exports = {\n", "module.exports = {\n" + entry, 1)
    open(p, "w", encoding="utf-8").write(src)
    print("added notify_new_mail to protocol.js")
