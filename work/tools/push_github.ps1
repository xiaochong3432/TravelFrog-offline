<#
  在不稳定的网络下把提交推上去（本机到 github.com 的链路是断续的）。

  实测症状：同一个提交一次成功、下一次「Failed to connect」「Connection was reset」；
  DNS 解析到的 github.com 前端 IP（20.205.243.166）经常连不上，而其它 GitHub 前端
  （140.82.112.3 等）可以连。所以这个脚本每轮换一种打法，任何一种成功就结束：

    1) SSH 远端（若已配置并已把公钥加到 GitHub —— 走 ssh.github.com:443，最稳）
    2) 普通 HTTPS push
    3) HTTPS + HTTP/1.1 + 放宽低速超时
    4) HTTPS + 把 github.com 解析到某个能连的前端 IP（http.curloptResolve）
    5) 换下一个 IP 再来

  用法：
    powershell -NoProfile -ExecutionPolicy Bypass -File work\tools\push_github.ps1
    powershell -NoProfile -File work\tools\push_github.ps1 -Rounds 10
    powershell -NoProfile -File work\tools\push_github.ps1 -Status        # 只看状态
    powershell -NoProfile -File work\tools\push_github.ps1 -Remote ssh    # 只走 SSH 远端

  默认**不做任何强制推送**；确实需要覆盖远端时才加 -Force（会用 --force-with-lease）。
#>
[CmdletBinding()]
param(
  [string]$Remote = '',
  [string]$Branch = '',
  [switch]$Force,
  [switch]$Status,
  [int]$Rounds = 6
)

$ErrorActionPreference = 'Continue'
function Say($m) { Write-Host $m }

# 实测 443 可连、且属于 GitHub 前端的 IP（20.205.243.166 是经常连不上的那个）
$IPs = @('140.82.112.3', '140.82.113.3', '140.82.114.3', '20.205.243.168', '20.27.177.113')

$repo = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'git-repo'
if (-not (Test-Path (Join-Path $repo '.git'))) { $repo = (Get-Location).Path }
Push-Location $repo
try {
  if (-not (Test-Path '.git')) { Say '!! 这里不是 git 仓库'; exit 2 }
  if (-not $Branch) { $Branch = (git rev-parse --abbrev-ref HEAD).Trim() }

  $remotes = @(git remote)
  Say ("仓库      : " + (Get-Location).Path)
  Say ("分支      : $Branch")
  Say ("远端      : " + (($remotes | ForEach-Object { $_ }) -join ', '))

  foreach ($r in $remotes) { git fetch $r 2>$null | Out-Null }
  $sb = (git status -sb 2>$null | Select-Object -First 1)
  Say ("状态      : " + $sb)
  if ($Status) { exit 0 }

  # 需要推的目标远端：显式指定 > ssh（若存在且认证可用）> origin
  if (-not $Remote) {
    $sshOK = $false
    if ($remotes -contains 'ssh') {
      $probe = (& ssh -o ConnectTimeout=8 -T -p 443 git@ssh.github.com 2>&1 | Out-String)
      $sshOK = ($probe -match 'successfully authenticated')
    }
    if ($sshOK) { $Remote = 'ssh' } else { $Remote = 'origin' }
    $note = ""; if (-not $sshOK -and ($remotes -contains 'ssh')) { $note = "（SSH 已配置，但公钥还没加到 GitHub，先用 HTTPS）" }; Say ("自动选择  : " + $Remote + $note)
  }

  $head = (git rev-parse --short HEAD).Trim()
  $remoteHead = (git rev-parse --short "$Remote/$Branch" 2>$null)
  if ($head -eq $remoteHead) { Say "本地与 $Remote/$Branch 一致（$head），无需推送。"; exit 0 }
  Say "本地 $head  ->  $Remote/$Branch $remoteHead"

  $forceFlag = @()
  if ($Force) { $forceFlag = @('--force-with-lease') }

  $n = 0
  for ($round = 1; $round -le $Rounds; $round++) {
    $ip = $IPs[($round - 1) % $IPs.Count]
    $plans = @()
    if ($Remote -eq 'ssh') {
      $plans += @{ name = 'ssh:443'; args = @('-c', 'core.sshCommand=ssh -p 443 -o StrictHostKeyChecking=accept-new') }
    }
    $plans += @{ name = 'https'; args = @() }
    $plans += @{ name = 'https+http1.1'; args = @('-c', 'http.version=HTTP/1.1', '-c', 'http.lowSpeedLimit=1000', '-c', 'http.lowSpeedTime=120') }
    $plans += @{ name = "https@$ip"; args = @('-c', "http.curloptResolve=github.com:443:$ip", '-c', 'http.version=HTTP/1.1') }

    foreach ($plan in $plans) {
      $n++
      Say ("[轮 $round/$Rounds · $($plan.name)] 推送中 ...")
      $cmd = @('git') + $plan.args + @('push') + $forceFlag + @($Remote, $Branch)
      $out = (& $cmd[0] $cmd[1..($cmd.Count - 1)] 2>&1 | Out-String)
      if ($out -match '->\s+\S+' -or $out -match 'Everything up-to-date') {
        Say '推送成功 ✓'
        (($out -split "`n") | Where-Object { $_ -match '->' } | Select-Object -First 1) | ForEach-Object { Say ('   ' + $_.Trim()) }
        exit 0
      }
      $err = (($out -split "`n") | Where-Object { $_ -match 'fatal|error:|rejected' } | Select-Object -First 1)
      if (-not $err) { $err = ($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1) }
      Say ('   失败: ' + (($err -replace '.*?fatal:\s*', '') -replace '^\s+', '').Trim())
    }
    if ($round -lt $Rounds) {
      $wait = [Math]::Min(30, 4 * $round)
      Say ("   等 $wait 秒后重试")
      Start-Sleep -Seconds $wait
    }
  }

  Say ''
  Say "尝试 $n 次仍未成功。可用的三条路（详见 docs/GitHub连接问题.md）："
  Say '  1) 走 SSH-over-443：本机已生成密钥并写好 ~/.ssh/config，'
  Say '     把 ~/.ssh/id_ed25519.pub 加到 GitHub → Settings → SSH and GPG keys，然后：'
  Say '        git push ssh main        # 或 powershell -File work\tools\push_github.ps1 -Remote ssh'
  Say '  2) 挂代理后告诉 git：'
  Say '        git config --global http.proxy http://127.0.0.1:7890'
  Say '        git config --global https.proxy http://127.0.0.1:7890'
  Say '  3) 以管理员身份改 hosts（最省事的长期方案）：'
  Say '        140.82.112.3    github.com'
  Say '        140.82.112.3    codeload.github.com'
  Say '        20.205.243.168  api.github.com'
  exit 1
}
finally { Pop-Location }
