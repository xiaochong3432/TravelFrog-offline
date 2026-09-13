import os, re
pats = [b"is_offline_game", b"index.html", b"file:///android_asset", b"assets/game",
        b"MainActivity", b"EjoyWebViewActivity", b"lxqw", b"login", b"Login",
        b".html"]
d = r"H:\AI\frog\work\build\dex"
for f in sorted(os.listdir(d)):
    data = open(os.path.join(d, f), "rb").read()
    print("==", f, len(data))
    for p in pats:
        c = data.count(p)
        if c:
            print(f"   {p.decode():26s} {c}")
