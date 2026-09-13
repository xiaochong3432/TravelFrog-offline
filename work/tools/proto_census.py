#!/usr/bin/env python3
"""Census the game's socket protocol surface: command names sent/received."""
import re, collections, os, sys

def census(path):
    data = open(path, "rb").read().decode("utf8", "replace")
    print(f"===== {os.path.basename(path)} ({len(data)} chars) =====")

    sends = re.findall(r'\.send\(\s*"([A-Za-z0-9_\.\-]+)"', data)
    print(f"\n--- .send(\"cmd\") : {len(sends)} calls, {len(set(sends))} distinct ---")
    for k, v in collections.Counter(sends).most_common():
        print(f"{v:5d}  {k}")

    # named socket command registrations / dispatch
    oncmds = re.findall(r'\.(?:on|addEventListener|register|listen)\(\s*"([A-Za-z0-9_\.\-]{3,60})"', data)
    print(f"\n--- .on(\"name\") : {len(set(oncmds))} distinct ---")
    for k, v in collections.Counter(oncmds).most_common(120):
        print(f"{v:5d}  {k}")

    # hall_ / game_ style command literals anywhere
    lit = re.findall(r'"((?:hall|game|frog|user|item|bag|shop|task|friend|chat|mail|rank|photo|travel|scene|room|pay|order)_[a-zA-Z0-9_]{2,40})"', data)
    print(f"\n--- domain-prefixed command literals: {len(set(lit))} distinct ---")
    for k, v in collections.Counter(lit).most_common(400):
        print(f"{v:5d}  {k}")

if __name__ == "__main__":
    for p in sys.argv[1:]:
        census(p)
