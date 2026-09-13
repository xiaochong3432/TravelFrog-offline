#!/usr/bin/env python3
"""Selective APK/zip extraction + listing helper."""
import sys, zipfile, os, fnmatch, hashlib

def main():
    if len(sys.argv) < 3:
        print(__doc__); print("usage: zipx.py <zip> list [pattern] | extract <pattern> <outdir> | info")
        return
    zpath = sys.argv[1]
    cmd = sys.argv[2]
    z = zipfile.ZipFile(zpath)
    if cmd == "list":
        pat = sys.argv[3] if len(sys.argv) > 3 else "*"
        tot = 0
        for i in z.infolist():
            if fnmatch.fnmatch(i.filename, pat):
                print(f"{i.file_size:12d}  {i.filename}")
                tot += i.file_size
        print(f"-- total {tot} bytes")
    elif cmd == "extract":
        pat = sys.argv[3]; out = sys.argv[4]
        n = 0
        for i in z.infolist():
            if fnmatch.fnmatch(i.filename, pat) or fnmatch.fnmatch(i.filename, pat + "/*"):
                dst = os.path.join(out, i.filename.replace("/", os.sep))
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with z.open(i) as src, open(dst, "wb") as f:
                    f.write(src.read())
                n += 1
        print(f"extracted {n} -> {out}")
    elif cmd == "info":
        print(f"entries={len(z.infolist())}")
        print(f"comment={z.comment!r}")
    z.close()

if __name__ == "__main__":
    main()
