#!/usr/bin/env python3
"""Generate dist/开始游戏.cmd with the bytes cmd.exe actually needs.

Two traps this avoids:
  * batch files MUST use CRLF line endings - with LF only, cmd.exe mis-parses
    blocks and ends up executing fragments of the file as commands
  * the console code page here is 936 (GBK), so a UTF-8 .cmd shows mojibake and
    can break parsing outright; this launcher is therefore pure ASCII and lets
    play_frog.py (which Python prints correctly to a real console) do the talking
"""
import os

CMD = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "..", "dist", "开始游戏.cmd")

LINES = [
    "@echo off",
    "rem ============================================================",
    "rem  Travel Frog - China Journey : offline build, PC launcher",
    "rem  Double-click this file. It serves the game locally and opens",
    "rem  your browser. All game logic runs inside the page.",
    "rem ============================================================",
    "setlocal",
    'cd /d "%~dp0"',
    "",
    "where python >nul 2>nul",
    "if not errorlevel 1 goto runpython",
    "",
    "where py >nul 2>nul",
    "if not errorlevel 1 goto runpy",
    "",
    "echo.",
    "echo   Python 3 was not found on this computer.",
    "echo   Please install it from https://www.python.org/downloads/",
    'echo   and tick "Add python.exe to PATH" during setup.',
    "echo.",
    "pause",
    "exit /b 1",
    "",
    ":runpython",
    'python "%~dp0play_frog.py" %*',
    "goto done",
    "",
    ":runpy",
    'py "%~dp0play_frog.py" %*',
    "goto done",
    "",
    ":done",
    "if errorlevel 1 pause",
    "endlocal",
]


def main():
    path = os.path.abspath(CMD)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = "\r\n".join(LINES) + "\r\n"
    with open(path, "wb") as f:
        f.write(data.encode("ascii"))
    b = open(path, "rb").read()
    crlf = b.count(b"\r\n")
    lone_lf = b.count(b"\n") - crlf
    print(f"wrote {path}  ({len(b)} bytes)")
    print(f"  CRLF lines: {crlf}   bare LF: {lone_lf}")
    print(f"  ascii-only: {all(c < 128 for c in b)}")
    return 0 if lone_lf == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
