#!/usr/bin/env python3
"""Show the travel/task/value tests that assert the OLD (auto-depart, fast) pacing."""
import io

T = r"H:\AI\frog\work\tools\engine_test.js"
t = io.open(T, encoding="utf-8").read()
out = io.StringIO()
KEYS = ["test('travel: departure flips",
        "test('travel: returning home restores",
        "test('travel: with NO lunch box",
        "test('tasks: type-1 progress follows",
        "test('values: offline pacing stays short",
        "test('values: a STRAY trip uses"]
for k in KEYS:
    i = t.find(k)
    out.write("=" * 30 + "\n")
    out.write(t[i:i + 1100] if i >= 0 else "NOT FOUND: " + k)
    out.write("\n")
io.open(r"H:\AI\frog\work\logs\traveltests.txt", "w", encoding="utf-8").write(out.getvalue())
print("wrote logs/traveltests.txt")
