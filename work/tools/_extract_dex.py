import zipfile, os, re
os.makedirs(r"H:\AI\frog\work\build\dex", exist_ok=True)
z = zipfile.ZipFile(r"H:\AI\frog\base.apk")
for n in z.namelist():
    if n.endswith(".dex"):
        p = os.path.join(r"H:\AI\frog\work\build\dex", n)
        open(p, "wb").write(z.read(n))
        print("extracted", n, z.getinfo(n).file_size)
