import zipfile
z = zipfile.ZipFile(r"H:\AI\frog\base.apk")
for n in z.namelist():
    if n.endswith(".dex") or (n.startswith("assets/") and not n.startswith("assets/game/")) or n.endswith(".so") and n.count("/")==1:
        print(f"{z.getinfo(n).file_size:>12,}  {n}")
