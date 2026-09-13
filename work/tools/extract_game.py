#!/usr/bin/env python3
"""Extract a prefix of entries from base.apk into a target dir (streaming, fast)."""
import zipfile, os, sys, time

APK = r"H:\AI\frog\base.apk"
PREFIX = "assets/game/"
OUT = r"H:\AI\frog\work\run\web"

def main():
    z = zipfile.ZipFile(APK)
    ents = [i for i in z.infolist() if i.filename.startswith(PREFIX) and not i.is_dir()]
    print(f"extracting {len(ents)} entries -> {OUT}")
    t0 = time.time()
    n = 0
    for i in ents:
        rel = i.filename[len(PREFIX):]
        dst = os.path.join(OUT, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with z.open(i) as src, open(dst, "wb") as f:
            while True:
                b = src.read(1 << 20)
                if not b:
                    break
                f.write(b)
        n += 1
        if n % 500 == 0:
            print(f"  {n}/{len(ents)}  {time.time()-t0:.0f}s")
    z.close()
    print(f"done {n} files in {time.time()-t0:.0f}s")

if __name__ == "__main__":
    main()
