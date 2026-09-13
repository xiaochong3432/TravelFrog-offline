#!/usr/bin/env python3
"""Explain the size difference between base.apk and the repacked APK."""
import zipfile, os, collections

A_PATH = r"H:\AI\frog\base.apk"
B_PATH = r"H:\AI\frog\dist\TravelFrog-offline.apk"

a = zipfile.ZipFile(A_PATH)
b = zipfile.ZipFile(B_PATH)
A = {i.filename: i for i in a.infolist()}
B = {i.filename: i for i in b.infolist()}


def total(z, names):
    return sum(z.getinfo(n).compress_size for n in names)


both = [n for n in A if n in B]
game = [n for n in both if n.startswith("assets/game/")]
rest = [n for n in both if not n.startswith("assets/game/")]
only_a = [n for n in A if n not in B]
only_b = [n for n in B if n not in A]

print(f"entries: base={len(A)}  new={len(B)}  shared={len(both)}")
print()
print(f"{'bucket':<34}{'base':>13}{'new':>13}{'delta':>12}")
print(f"{'assets/game/** (shared)':<34}{total(a, game):>13,}{total(b, game):>13,}"
      f"{total(b, game) - total(a, game):>+12,}")
print(f"{'everything else (shared)':<34}{total(a, rest):>13,}{total(b, rest):>13,}"
      f"{total(b, rest) - total(a, rest):>+12,}")
print(f"{'dropped entries':<34}{total(a, only_a):>13,}{0:>13,}{-total(a, only_a):>+12,}")
print(f"{'added entries':<34}{0:>13,}{total(b, only_b):>13,}{total(b, only_b):>+12,}")

ta, tb = os.path.getsize(A_PATH), os.path.getsize(B_PATH)
print(f"\n{'file total':<34}{ta:>13,}{tb:>13,}{tb - ta:>+12,}")

print("\ndropped (compressed bytes):")
for n in sorted(only_a, key=lambda x: -A[x].compress_size)[:8]:
    print(f"    {A[n].compress_size:>10,}  {n}")
print("\nadded (compressed bytes):")
for n in sorted(only_b, key=lambda x: -B[x].compress_size)[:8]:
    print(f"    {B[n].compress_size:>10,}  {n}")

# how many shared entries changed compression size, and by how much
changed = [(n, B[n].compress_size - A[n].compress_size) for n in both
           if B[n].compress_size != A[n].compress_size]
print(f"\nshared entries whose compressed size changed: {len(changed)}")
print(f"  net change: {sum(d for _, d in changed):+,} bytes")
big = sorted(changed, key=lambda t: -abs(t[1]))[:5]
for n, d in big:
    print(f"    {d:>+9,}  {n}")

a.close()
b.close()
