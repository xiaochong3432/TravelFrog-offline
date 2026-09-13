@echo off
rem 旅行青蛙·中国之旅 —— 离线单机版（PC）双击启动
rem
rem 顺序：① 旅行青蛙.exe（免 Python、免执行策略，推荐）→ ② Python 启动器
rem       → ③ Windows 自带的 PowerShell 启动器。三条路的端口策略完全一致。
setlocal
cd /d "%~dp0"

if exist "%~dp0旅行青蛙.exe" (
    "%~dp0旅行青蛙.exe" %*
    goto :end
)

where python >nul 2>nul
if %errorlevel%==0 (
    python "%~dp0play_frog.py"
    goto :end
)

where py >nul 2>nul
if %errorlevel%==0 (
    py "%~dp0play_frog.py"
    goto :end
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play-pc.ps1"

:end
endlocal
