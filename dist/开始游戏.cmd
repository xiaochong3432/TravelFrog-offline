@echo off
rem ============================================================
rem  Travel Frog - China Journey : offline build, PC launcher
rem  Double-click this file. It serves the game folder read-only on
rem  127.0.0.1 and opens your browser. All game logic runs in the page.
rem
rem  Order: python -> py -> Windows PowerShell (no dependencies).
rem  The PowerShell path (play-pc.ps1) ships in this folder, so a machine
rem  with no Python installed can still play.
rem ============================================================
setlocal
cd /d "%~dp0"

where python >nul 2>nul
if not errorlevel 1 goto runpython

where py >nul 2>nul
if not errorlevel 1 goto runpy

if exist "%~dp0play-pc.ps1" goto runps

echo.
echo   Neither Python nor play-pc.ps1 was found next to this file.
echo   Please keep the whole folder together (play-pc.ps1 + web\).
echo.
pause
exit /b 1

:runpython
python "%~dp0play_frog.py" %*
goto done

:runpy
py "%~dp0play_frog.py" %*
goto done

:runps
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play-pc.ps1"
goto done

:done
if errorlevel 1 pause
endlocal
