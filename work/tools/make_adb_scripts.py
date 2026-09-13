#!/usr/bin/env python3
"""Generate the adb helper .cmd files into dist/.

Why these exist
---------------
China's MIIT requires every app to be filed (APP备案), and that filing binds three
things: the package name, the public key and the signature MD5. OEM installers
(vivo/OriginOS and friends) verify the installed APK against that registry, so an
unfiled app -- or a filed app re-signed by anyone else -- cannot pass. We can
never satisfy it: we do not hold Lingxi's signing key, and filing someone else's
game as our own would be a false declaration.

Installing through `adb install` sidesteps the OEM installer UI entirely: the APK
goes to the package manager directly, so the installer's filing/verification step
never runs. That is the point of these scripts.

Same two hard-won rules as 开始游戏.cmd:
  * CRLF line endings (batch files break on bare LF)
  * ASCII only (a UTF-8 file in a GBK console turns into mojibake)
Chinese explanations therefore live in the .txt files, not here.
"""
import os
import shutil

ROOT = r"H:\AI\frog"
DIST = os.path.join(ROOT, "dist")
ADB_SRC = os.path.join(ROOT, r"work\adb\platform-tools")

# only what adb itself needs
ADB_FILES = ["adb.exe", "AdbWinApi.dll", "AdbWinUsbApi.dll", "NOTICE.txt"]

INSTALL_CMD = r"""@echo off
setlocal
cd /d "%~dp0"

set "ADB=%~dp0adb\adb.exe"
if not exist "%ADB%" set "ADB=adb"

echo ============================================================
echo   Travel Frog - offline build : install to phone via adb
echo ============================================================
echo.
echo Why this way: the phone's own installer verifies apps against
echo China's MIIT app filing registry, which an unfiled / self-signed
echo app can never pass. Installing through adb hands the APK straight
echo to the package manager, so that verification step is skipped.
echo.

"%ADB%" version >nul 2>&1
if errorlevel 1 (
    echo [X] adb not found.
    echo     Expected at: %~dp0adb\adb.exe
    echo     Get it from: https://developer.android.com/tools/releases/platform-tools
    echo.
    pause
    exit /b 1
)

"%ADB%" start-server >nul 2>&1

echo [1/3] Connected devices:
echo.
"%ADB%" devices
echo.
echo   If nothing is listed above:
echo     1. On the phone, turn on Developer options
echo        (Settings - About phone - tap Build number 7 times)
echo     2. Settings - System - Developer options - USB debugging: ON
echo     3. Plug in USB, then tap Allow on the phone's prompt
echo     4. Run this script again
echo.
pause

echo.
echo [2/3] Installing (this uploads about 236 MB, please wait)...
echo.
"%ADB%" install -r -d "%~dp0TravelFrog-offline.apk"
if errorlevel 1 (
    echo.
    echo [!] That failed. Retrying while granting all permissions...
    echo.
    "%ADB%" install -r -d -g "%~dp0TravelFrog-offline.apk"
)
if errorlevel 1 (
    echo.
    echo [X] Install still failed. See the error text above.
    echo     Common causes: USB debugging not allowed on the phone,
    echo     the phone is locked, or the cable is charge-only.
    echo.
    pause
    exit /b 1
)

echo.
echo [3/3] Done. The game should now be on the phone.
echo.
echo   Next step: open it and check the frog is there.
echo   To see the game's own log while it runs, use  game-log.cmd
echo.
pause
"""

LOG_CMD = r"""@echo off
setlocal
cd /d "%~dp0"

set "ADB=%~dp0adb\adb.exe"
if not exist "%ADB%" set "ADB=adb"

"%ADB%" version >nul 2>&1
if errorlevel 1 (
    echo [X] adb not found. Expected at: %~dp0adb\adb.exe
    pause
    exit /b 1
)

echo ============================================================
echo   Travel Frog - game log   (Ctrl+C to stop)
echo ============================================================
echo.
echo The wrapper forwards the page's console output to logcat under
echo the tag FrogGame, and logs the asset server under FrogAssetServer.
echo Startup shows whether the fixed port was taken:
echo   "asset server on 127.0.0.1:18080 (origin is stable...)"  = good
echo   "FALLBACK to random port"                                = saves at risk
echo.
pause

"%ADB%" logcat -s FrogGame FrogAssetServer
pause
"""


def write_cmd(path, text):
    """CRLF + ASCII, then prove both."""
    text = text.replace("\r\n", "\n").replace("\n", "\r\n")
    data = text.encode("ascii")          # raises if anything non-ASCII slipped in
    with open(path, "wb") as f:
        f.write(data)
    raw = open(path, "rb").read()
    bare_lf = raw.replace(b"\r\n", b"").count(b"\n")
    non_ascii = sum(1 for b in raw if b > 127)
    print(f"  {os.path.basename(path):22s} {len(raw):5d} bytes  "
          f"CRLF={raw.count(b'\r\n')}  bare_LF={bare_lf}  non_ASCII={non_ascii}")
    assert bare_lf == 0 and non_ascii == 0, "batch file must be CRLF + ASCII"
    return raw


def main():
    os.makedirs(DIST, exist_ok=True)

    adb_dir = os.path.join(DIST, "adb")
    os.makedirs(adb_dir, exist_ok=True)
    print("adb files:")
    for name in ADB_FILES:
        src = os.path.join(ADB_SRC, name)
        if not os.path.exists(src):
            print(f"  !! missing {src}")
            return 1
        shutil.copy2(src, os.path.join(adb_dir, name))
        print(f"  {name:20s} {os.path.getsize(os.path.join(adb_dir, name)):>9,} bytes")

    print("\nscripts:")
    write_cmd(os.path.join(DIST, "install-via-adb.cmd"), INSTALL_CMD)
    write_cmd(os.path.join(DIST, "game-log.cmd"), LOG_CMD)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
