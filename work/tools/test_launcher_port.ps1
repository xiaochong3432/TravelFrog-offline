# 仓库根：按脚本自身位置推导，不写死绝对路径
$ProjectRoot = Split-Path -Parent (Split-Path -Parent ($PSScriptRoot))

﻿# 启动器端口策略测试（PC 端"存档偶尔被重置"的根因就在这条策略上）
#
# 背景：玩家报"PC 进去后偶尔重置存档重新开始"。根因不是存档文件坏了，而是旧启动器在
# 8080 被占时**悄悄换到 8081/8082...**；浏览器按 origin（**含端口**）隔离 localStorage，
# 换端口就是打开另一个空存档。现在的策略是：自己的服务就复用，别的情况下宁可停下来说清楚。
#
# 本脚本把三个启动器（play_frog.py / play-pc.ps1 / 旅行青蛙.exe）放进一个临时沙箱
# （只有占位 index.html），逐场景真的启动/复用/拒绝，检查退出码、实际监听的端口与
# last-port.txt。
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File work\tools\test_launcher_port.ps1
#
# 注意：会占用 8080/8088 一小段时间，结束后自动清理。

$ErrorActionPreference = 'Continue'
$DIST = (Join-Path $ProjectRoot 'dist')
$BOX = (Join-Path $ProjectRoot 'work/build/launcher-test')
$PY = 'python'
$fail = @()
$pass = 0

function Say($m) { Write-Host $m }

function Check($cond, $msg) {
    if ($cond) { Say "  PASS  $msg"; $script:pass++ }
    else { Say "  FAIL  $msg"; $script:fail += $msg }
}

function Listening([int]$p) {
    $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    return [bool]$c
}
function PidsOn([int]$p) {
    (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) |
        Select-Object -ExpandProperty OwningProcess -Unique
}
function FreePort([int]$p) {
    foreach ($id in PidsOn $p) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 700
}
function PingFrog([int]$p) {
    try { return (Invoke-WebRequest "http://127.0.0.1:$p/__frog_ping" -UseBasicParsing -TimeoutSec 3).Content.Trim() }
    catch { return 'FAIL' }
}
function KillSandboxServers {
    # 只杀沙箱目录里的 python，别碰别的东西
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.CommandLine -and $_.CommandLine -like "*launcher-test*") {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds 500
}

# ---------------------------------------------------------------- sandbox
Remove-Item $BOX -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $BOX 'web') -Force | Out-Null
foreach ($f in 'play_frog.py', 'play-pc.ps1') {
    Copy-Item (Join-Path $DIST $f) (Join-Path $BOX $f) -Force
}
# 一键 exe（csc 编译，免 Python、免执行策略）
$EXE_SRC = Join-Path $DIST '旅行青蛙.exe'
$EXE = Join-Path $BOX '旅行青蛙.exe'
$haveExe = Test-Path $EXE_SRC
if ($haveExe) { Copy-Item $EXE_SRC $EXE -Force }
Set-Content -Path (Join-Path $BOX 'web\index.html') -Value '<html><body>sandbox</body></html>' -Encoding UTF8
Set-Content -Path (Join-Path $BOX 'web\__offline-engine.js') -Value '// stub' -Encoding UTF8
$PY_PATH = Join-Path $BOX 'play_frog.py'
$PS_PATH = Join-Path $BOX 'play-pc.ps1'
$REMEMBER = Join-Path $BOX 'last-port.txt'

function RunPyLauncher {
    # 用 cmd 重定向 stdin，避免启动器里的 input() 卡住
    $o = & cmd /c "cd /d `"$BOX`" && python play_frog.py --no-browser < NUL 2>&1"
    return @{ code = $LASTEXITCODE; text = ($o | Out-String) }
}
function RunPsLauncher {
    $o = & cmd /c "cd /d `"$BOX`" && powershell -NoProfile -ExecutionPolicy Bypass -File play-pc.ps1 -NoBrowser < NUL 2>&1"
    return @{ code = $LASTEXITCODE; text = ($o | Out-String) }
}
function RunExeLauncher {
    $o = & cmd /c "cd /d `"$BOX`" && `"$EXE`" --no-browser < NUL 2>&1"
    return @{ code = $LASTEXITCODE; text = ($o | Out-String) }
}

FreePort 8080; FreePort 8088
KillSandboxServers
Remove-Item $REMEMBER -Force -ErrorAction SilentlyContinue

# ------------------------------------------------- 场景 1：端口空闲 -> 直接用
Say "`n===== 场景 1：8080 空闲（应直接用 8080，并记进 last-port.txt）====="
Start-Process -FilePath $PY -ArgumentList 'play_frog.py', '--no-browser' -WorkingDirectory $BOX -WindowStyle Hidden | Out-Null
Start-Sleep -Seconds 3
Check ((PingFrog 8080) -eq 'frog-offline-pc-v1') "play_frog.py 在 8080 上提供服务"
Check ((Test-Path $REMEMBER) -and ((Get-Content $REMEMBER -Raw).Trim() -eq '8080')) "last-port.txt 记下 8080"
Check (-not (Listening 8088)) "没有额外开别的端口"

# ------------------------------------- 场景 2：自己的服务已在 -> 复用同一个地址
Say "`n===== 场景 2：8080 上是自己的服务（应复用，不再开新端口）====="
$r = RunPyLauncher
Check ($r.code -eq 0) "play_frog.py 第二次启动退出码 0（复用），实际 $($r.code)"
Check (-not (Listening 8081)) "没有在 8081 上又开一个（那就是另一个空存档）"
$r = RunPsLauncher
Check ($r.code -eq 0) "play-pc.ps1 退出码 0（复用），实际 $($r.code)"
Check (-not (Listening 8081)) "play-pc.ps1 也没有另开端口"
Check ($r.text -match 'index\.html') "play-pc.ps1 提示里给出了复用地址"

# --------------------------------- 场景 3：8080 被别的程序占用 -> 停下来说清楚
Say "`n===== 场景 3：8080 被外来程序占用（应停下并说明，绝不悄悄换端口）====="
KillSandboxServers; FreePort 8080
Remove-Item $REMEMBER -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $PY -ArgumentList '-m', 'http.server', '8080', '--bind', '127.0.0.1' -WorkingDirectory $BOX -WindowStyle Hidden | Out-Null
Start-Sleep -Seconds 3
Check (-not ((PingFrog 8080) -eq 'frog-offline-pc-v1')) "8080 上是外来程序（ping 不通）"
$r = RunPyLauncher
Check ($r.code -eq 2) "play_frog.py 退出码 2（拒绝启动），实际 $($r.code)"
Check ($r.text -match 'netstat') "并给出查看占用者的办法"
Check ($r.text -match 'allow-other-port') "并给出显式换端口的方法"
$r = RunPsLauncher
Check ($r.code -eq 2) "play-pc.ps1 退出码 2（拒绝启动），实际 $($r.code)"
Check ($r.text -match 'AllowOtherPort') "并给出显式换端口的方法"
if ($haveExe) {
    $r = RunExeLauncher
    Check ($r.code -eq 2) "旅行青蛙.exe 退出码 2（拒绝启动），实际 $($r.code)"
    Check ($r.text -match 'netstat') "exe 也给出查看占用者的办法"
}
Check (-not (Listening 8081)) "三个启动器都没有偷偷换到 8081"
Check (-not (Test-Path $REMEMBER)) "拒绝启动时不会写 last-port.txt"

# ------------------------------- 场景 4：8080 被占，但上次用的是 8088 -> 沿用 8088
Say "`n===== 场景 4：8080 被占、上次用的是 8088（应沿用 8088，地址与存档位置不变）====="
Set-Content -Path $REMEMBER -Value '8088' -Encoding ASCII
Start-Process -FilePath $PY -ArgumentList 'play_frog.py', '--no-browser' -WorkingDirectory $BOX -WindowStyle Hidden | Out-Null
Start-Sleep -Seconds 3
Check ((PingFrog 8088) -eq 'frog-offline-pc-v1') "真的在记下的 8088 上提供服务"
Check (-not ((PingFrog 8080) -eq 'frog-offline-pc-v1')) "8080 仍是那个外来程序（没被顶掉）"
Check ((Get-Content $REMEMBER -Raw).Trim() -eq '8088') "last-port.txt 保持 8088"

# --------------------------------- 场景 5：一键 exe（免 Python / 免执行策略）
Say "`n===== 场景 5：旅行青蛙.exe（双击即玩，端口策略必须与另两个一致）====="
if (-not $haveExe) {
    Say "  SKIP  dist\旅行青蛙.exe 不存在（先跑 python work\tools\build_pc_exe.py）"
} else {
    KillSandboxServers; FreePort 8080; FreePort 8088
    Remove-Item $REMEMBER -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $EXE -ArgumentList '--no-browser' -WorkingDirectory $BOX -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 3
    Check ((PingFrog 8080) -eq 'frog-offline-pc-v1') "exe 自己在 8080 上提供服务（不依赖 Python/PS）"
    Check ((Test-Path $REMEMBER) -and ((Get-Content $REMEMBER -Raw).Trim() -eq '8080')) "exe 记下 8080"
    $r = RunExeLauncher
    Check ($r.code -eq 0) "第二次双击 exe 复用已有服务（退出码 0），实际 $($r.code)"
    Check ($r.text -match 'index\.html') "并打印了复用地址"
    Check (-not (Listening 8081)) "exe 没有另开端口"
    # 真正取到页面内容（不只是 ping）
    $page = ''
    try { $page = (Invoke-WebRequest 'http://127.0.0.1:8080/index.html' -UseBasicParsing -TimeoutSec 5).Content } catch { $page = '' }
    Check ($page -match 'sandbox') "exe 真的把 web 目录发出去了（拿到 index.html 内容）"
    try { $p404 = (Invoke-WebRequest 'http://127.0.0.1:8080/../secret.txt' -UseBasicParsing -TimeoutSec 5).StatusCode } catch { $p404 = 404 }
    Check ($p404 -ne 200) "目录穿越被挡住（web 之外的文件取不到）"
    Get-Process '旅行青蛙' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- 收尾
Say "`n===== 收尾 ====="
KillSandboxServers; FreePort 8080; FreePort 8088
Remove-Item $BOX -Recurse -Force -ErrorAction SilentlyContinue
Say "  沙箱已删除，端口已释放"

if ($fail.Count) {
    Say "`nFAIL: $($fail.Count) 项未通过"
    foreach ($f in $fail) { Say "  - $f" }
    exit 1
}
Say "`nPASS: 启动器端口策略 $pass 项检查通过"
exit 0
