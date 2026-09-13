import zipfile
z = zipfile.ZipFile(r"H:\AI\frog\base.apk")
for i in z.infolist():
    n = i.filename
    if n.startswith("res/") and ("launcher" in n or "icon" in n) and n.endswith(".png"):
        print(f"{i.file_size:>8,}  {n}")
