@echo off
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
