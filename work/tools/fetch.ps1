# 仓库根：按脚本自身位置推导，不写死绝对路径
$ProjectRoot = Split-Path -Parent (Split-Path -Parent ($PSScriptRoot))

param(
  [Parameter(Mandatory=$true)][string[]]$Urls,
  [string]$OutDir = (Join-Path $ProjectRoot 'raw'),
  [int]$TimeoutSec = 25
)
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"
if(-not (Test-Path $OutDir)){ New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

function ConvertTo-Text($html){
  $h = $html
  $h = [regex]::Replace($h,'(?s)<script.*?</script>',' ')
  $h = [regex]::Replace($h,'(?s)<style.*?</style>',' ')
  $h = [regex]::Replace($h,'(?s)<noscript.*?</noscript>',' ')
  $h = [regex]::Replace($h,'(?s)<!--.*?-->',' ')
  $h = [regex]::Replace($h,'<br\s*/?>',"`n")
  $h = [regex]::Replace($h,'</?(p|div|li|tr|h1|h2|h3|h4|h5|td|th|dt|dd|section|article|figcaption|blockquote)[^>]*>',"`n")
  $h = [regex]::Replace($h,'<[^>]+>',' ')
  $h = [System.Net.WebUtility]::HtmlDecode($h)
  $h = [regex]::Replace($h,'[ \t\u00a0]+',' ')
  $h = [regex]::Replace($h,'(\r?\n\s*){2,}',"`n")
  return $h.Trim()
}

foreach($u in $Urls){
  $name = ($u -replace '^https?://','' -replace '[^a-zA-Z0-9]','_')
  if($name.Length -gt 90){ $name = $name.Substring(0,90) }
  $outTxt = Join-Path $OutDir "$name.txt"
  try{
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec $TimeoutSec -Headers @{
      "User-Agent"=$ua
      "Accept"="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      "Accept-Language"="ja,zh-TW;q=0.9,zh;q=0.8,en;q=0.7"
    }
    $txt = ConvertTo-Text $r.Content
    Set-Content -Path $outTxt -Value $txt -Encoding UTF8
    Set-Content -Path (Join-Path $OutDir "$name.meta.txt") -Value "URL: $u`nSTATUS: $($r.StatusCode)`nBYTES_HTML: $($r.Content.Length)`nCHARS_TEXT: $($txt.Length)" -Encoding UTF8
    Write-Output "OK   [$($txt.Length)] $u -> $name.txt"
  }catch{
    $msg = $_.Exception.Message
    Set-Content -Path $outTxt -Value "FETCH_ERROR: $msg`nURL: $u" -Encoding UTF8
    Write-Output "FAIL $u :: $msg"
  }
}
