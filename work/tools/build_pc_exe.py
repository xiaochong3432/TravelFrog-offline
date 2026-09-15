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
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os
import shutil
import subprocess
import sys

ROOT = str(PROJECT_ROOT)
SRC = os.path.join(ROOT, "work", "app", "pc", "FrogLauncher.cs")
OUT_DIR = os.path.join(ROOT, "dist")
OUT = os.path.join(OUT_DIR, "旅行青蛙.exe")
CSC_CANDIDATES = [
    os.environ.get("FROG_CSC", ""),
    os.path.join(os.environ.get("WINDIR", r"C:\Windows"),
                 r"Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    os.path.join(os.environ.get("WINDIR", r"C:\Windows"),
                 r"Microsoft.NET\Framework\v4.0.30319\csc.exe"),
]


def log(*a):
    print(*a, flush=True)


def main():
    csc = next((p for p in CSC_CANDIDATES if p and os.path.isfile(p)), None)
    if not csc:
        if os.name != "nt":
            log("!! 本脚本只在 Windows 上能编译 .NET 启动器（需要 .NET Framework 自带的 csc.exe）。")
            log("   非 Windows 请直接用 play_frog.py / 任意静态服务器打开 web/index.html，")
            log("   启动器只是给不装 Python 的 Windows 玩家准备的。")
            log("   也可以设置 FROG_CSC=<csc 或 Roslyn csc 的完整路径> 再试（需要 .NET Framework 目标）。")
        else:
            log("!! 找不到 csc.exe（Windows 自带的 .NET Framework 编译器）")
            log("   可用 FROG_CSC=<csc.exe 路径> 指定，或安装 .NET Framework 4.x 开发者组件。")
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
