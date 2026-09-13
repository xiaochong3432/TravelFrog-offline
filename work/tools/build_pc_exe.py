#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the zero-dependency PC launcher: dist/TravelFrog-PC/旅行青蛙.exe

Why: the package shipped .bat (needs Python), .py (needs Python) and .ps1 (needs
the execution policy to allow scripts, which Windows blocks for downloaded files).
A single .exe compiled against the .NET Framework that SHIPS WITH WINDOWS needs
nothing installed and nothing configured -- double-clicking it is the whole
procedure.

The source is work/app/pc/FrogLauncher.cs; this script only drives csc.exe and
reports what it did.

    python work/tools/build_pc_exe.py
"""
import os
import shutil
import subprocess
import sys

ROOT = r"H:\AI\frog"
SRC = os.path.join(ROOT, "work", "app", "pc", "FrogLauncher.cs")
OUT_DIR = os.path.join(ROOT, "dist")
OUT = os.path.join(OUT_DIR, "旅行青蛙.exe")
CSC_CANDIDATES = [
    os.path.join(os.environ.get("WINDIR", r"C:\Windows"),
                 r"Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    os.path.join(os.environ.get("WINDIR", r"C:\Windows"),
                 r"Microsoft.NET\Framework\v4.0.30319\csc.exe"),
]


def log(*a):
    print(*a, flush=True)


def main():
    csc = next((p for p in CSC_CANDIDATES if os.path.isfile(p)), None)
    if not csc:
        log("!! no csc.exe found (need the .NET Framework compiler that ships with Windows)")
        return 1
    if not os.path.isfile(SRC):
        log("!! missing source:", SRC)
        return 1
    if os.path.isfile(OUT):
        os.remove(OUT)

    cmd = [
        csc, "/nologo", "/target:exe", "/platform:anycpu", "/optimize+",
        "/reference:System.dll", "/reference:System.Core.dll",
        "/out:" + OUT, SRC,
    ]
    log("  $ " + " ".join(cmd))
    p = subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace")
    for stream in (p.stdout, p.stderr):
        if stream and stream.strip():
            for line in stream.rstrip().splitlines():
                log("    " + line)
    if p.returncode != 0 or not os.path.isfile(OUT):
        log("!! csc failed")
        return 1

    size = os.path.getsize(OUT)
    log("")
    log("PC launcher: %s (%.1f KB)" % (OUT, size / 1024.0))
    log("  runs on the .NET Framework that ships with Windows -- no Python, no")
    log("  PowerShell execution policy, nothing to install")
    return 0


if __name__ == "__main__":
    sys.exit(main())
