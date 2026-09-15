# 旅行青蛙·中国之旅 —— 离线单机版（PC 启动器，零依赖）
#
# 为什么需要一个"本地服务器"：浏览器不允许 file:// 下的网页去读取本地资源文件
# （XHR 会被跨域策略拦掉），所以双击 index.html 是打不开这个游戏的。
# 这个脚本只在 127.0.0.1 上开一个只读的小服务，把游戏目录发给浏览器，别的一概不做。
#
# 用 Windows 自带的 .NET HttpListener，不需要安装 Python / Node / 任何东西。
# 用法： 右键"使用 PowerShell 运行"，或者双击同目录的 play_frog.bat

param(
    [int]$Port = 8080,
    [switch]$NoBrowser,
    [switch]$AllowOtherPort   # 8080 被别的程序占用时允许换端口（会换到另一个存档位置）
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root = Join-Path $PSScriptRoot 'web'
if (-not (Test-Path (Join-Path $root 'index.html'))) {
    Write-Host "找不到游戏文件：$root\index.html 不存在。" -ForegroundColor Red
    Write-Host "请确认解压时保留了 web 子目录（不要只把 exe/脚本单独拿出来）。"
    Read-Host "按回车退出"
    exit 1
}

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.mp3'  = 'audio/mpeg'
    '.mp4'  = 'video/mp4'
    '.xml'  = 'application/xml'
    '.atlas' = 'text/plain; charset=utf-8'
    '.fnt'  = 'text/plain; charset=utf-8'
    '.txt'  = 'text/plain; charset=utf-8'
    '.eab'  = 'application/octet-stream'
    '.lua'  = 'text/plain; charset=utf-8'
}

$PING_BODY = 'frog-offline-pc-v1'

# 8080 上跑的是不是"我们自己"？是 -> 复用它（存档就在那个地址下），别再开一个换端口的。
function Test-OurServer([int]$p) {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$p/__frog_ping" -UseBasicParsing -TimeoutSec 2
        return ($r.Content.Trim() -eq $PING_BODY)
    } catch { return $false }
}

# 端口是否空闲：HttpListener 试一下最直接
function Test-PortFree([int]$p) {
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://127.0.0.1:$p/")
    try { $l.Start(); $l.Stop(); $l.Close(); return $true }
    catch { try { $l.Close() } catch { }; return $false }
}

$listener = $null
$chosen = 0
if (Test-PortFree $Port) {
    $try = New-Object System.Net.HttpListener
    $try.Prefixes.Add("http://127.0.0.1:$Port/")
    $try.Start()
    $listener = $try
    $chosen = $Port
} elseif (Test-OurServer $Port) {
    # 已经在运行：直接用同一个地址打开 —— 存档还在原处
    $url = "http://127.0.0.1:$Port/index.html"
    Write-Host ("=" * 64)
    Write-Host "  旅行青蛙·中国之旅  —  离线单机版（PC）"
    Write-Host ("=" * 64)
    Write-Host "  已经在运行：$url" -ForegroundColor Green
    Write-Host "  这次不重复启动服务，直接用同一个地址打开 —— 存档还在原处。"
    Write-Host ("=" * 64)
    if (-not $NoBrowser) { Start-Process $url }
    Read-Host "按回车退出"
    exit 0
} elseif ($AllowOtherPort) {
    for ($p = ($Port + 1); $p -lt ($Port + 20); $p++) {
        if (Test-PortFree $p) {
            $try = New-Object System.Net.HttpListener
            $try.Prefixes.Add("http://127.0.0.1:$p/")
            $try.Start()
            $listener = $try
            $chosen = $p
            break
        }
    }
}

if (-not $listener) {
    # 关键：**不**悄悄换端口。换端口 = 换 origin = 另一个空存档，玩家会以为存档被重置。
    Write-Host ("=" * 64)
    Write-Host "  端口 $Port 被别的程序占用了，这次没有启动。" -ForegroundColor Yellow
    Write-Host ("=" * 64)
    Write-Host "  为什么不能自动换端口：浏览器按「地址」保存存档，地址里包含端口，"
    Write-Host "  换端口 = 换一个空存档，看起来就像『存档被重置、重新开始』。"
    Write-Host ""
    Write-Host "  请二选一："
    Write-Host "    1) 先关掉占用 $Port 的程序，再重新双击启动（推荐）"
    Write-Host "       查看占用者：  netstat -ano | findstr :$Port"
    Write-Host "       结束进程：    taskkill /PID <上面的PID> /F"
    Write-Host "    2) 确认过可以换端口（会换存档位置）：命令行加 -AllowOtherPort"
    Write-Host "       换过去之后，用旧地址打开可以「导出存档」，再在新区里「导入存档」搬过来。"
    Write-Host ("=" * 64)
    Read-Host "按回车退出"
    exit 2
}

$url = "http://127.0.0.1:$chosen/index.html"
Write-Host ("=" * 64)
Write-Host "  旅行青蛙·中国之旅  —  离线单机版（PC）"
Write-Host ("=" * 64)
Write-Host "  游戏目录 : $root"
Write-Host "  地址     : $url"
Write-Host ""
Write-Host "  这个版本不需要任何后端服务，存档就在浏览器里（localStorage）。"
Write-Host "  ⚠ 存档跟「地址（含端口）」绑定：请始终用本启动器打开，" -ForegroundColor Yellow
Write-Host "     不要手动改端口、也不要换用 localhost/其他浏览器，否则会看到另一个空存档。" -ForegroundColor Yellow
Write-Host "  进游戏后，画面左侧那颗圆球就是【存档编辑】："
Write-Host "    · 点一下打开面板，按住可以拖到任意位置（位置会记住）"
Write-Host "    · 面板里可以直接点：解锁图鉴+百科 / 获得全部家具 / 三叶草 / 改名 …"
Write-Host "    · 「导出存档 / 导入存档」用来备份和搬存档，换电脑就靠它"
Write-Host "    · 「指令台（高级）」是原来那台可以打字的控制台"
Write-Host ""
if ($chosen -ne $Port) {
    Write-Host "  【注意】你用了 -AllowOtherPort，这次跑在 $chosen（不是 $Port）。" -ForegroundColor Yellow
    Write-Host "        这等于换了一个存档位置：旧存档仍在 http://127.0.0.1:$Port/ 。"
    Write-Host ""
}
Write-Host "  关闭本窗口即退出游戏服务。"
Write-Host ("=" * 64)

if (-not $NoBrowser) {
    Start-Process $url
}

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
    } catch {
        break
    }
    $req = $ctx.Request
    $res = $ctx.Response
    try {
        $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }
        # 探针：第二次双击启动时用它判断"8080 上是不是我们自己"（是就复用，不换端口）
        if ($rel -eq '__frog_ping') {
            $msg = [System.Text.Encoding]::UTF8.GetBytes($PING_BODY)
            $res.ContentType = 'text/plain; charset=utf-8'
            $res.ContentLength64 = $msg.Length
            $res.OutputStream.Write($msg, 0, $msg.Length)
            continue
        }
        # no directory escapes
        $full = [System.IO.Path]::GetFullPath((Join-Path $root $rel))
        if (-not $full.StartsWith([System.IO.Path]::GetFullPath($root))) {
            $res.StatusCode = 403
            $res.Close()
            continue
        }
        if (Test-Path $full -PathType Container) { $full = Join-Path $full 'index.html' }
        if (Test-Path $full -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($full)
            $ext = [System.IO.Path]::GetExtension($full).ToLower()
            $type = $mime[$ext]
            if (-not $type) { $type = 'application/octet-stream' }
            $res.ContentType = $type
            $res.Headers.Add('Cache-Control', 'no-store')
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $res.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes('404')
            $res.ContentLength64 = $msg.Length
            $res.OutputStream.Write($msg, 0, $msg.Length)
            Write-Host "  [404] $rel" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host ("  [err] " + $_.Exception.Message) -ForegroundColor DarkGray
    } finally {
        try { $res.Close() } catch { }
    }
}

$listener.Stop()
$listener.Close()
Write-Host "已退出。"
