@echo off
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
