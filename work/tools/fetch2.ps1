# 仓库根：按脚本自身位置推导，不写死绝对路径
$ProjectRoot = Split-Path -Parent (Split-Path -Parent ($PSScriptRoot))

param(
  [Parameter(Mandatory=$true)][string[]]$Urls,
  [string]$OutDir = (Join-Path $ProjectRoot 'raw'),
  [int]$TimeoutSec = 25
)
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"
if(-not (Test-Path $OutDir)){ New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

function ConvertTo-Text([string]$html){
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

function Decode-Bytes([byte[]]$bytes, [string]$contentType){
  # 1) charset from HTTP header
  $cs = $null
  if($contentType -match 'charset\s*=\s*["'']?([\w\-]+)' ){ $cs = $Matches[1] }
  # 2) charset from meta tag in first 4KB (ascii-safe scan)
  if(-not $cs){
    $head = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(4095,$bytes.Length-1))])
    if($head -match '(?i)charset\s*=\s*["'']?([\w\-]+)'){ $cs = $Matches[1] }
  }
  if(-not $cs){ $cs = 'utf-8' }
  $cs = $cs.ToLower()
  try{
    switch -Regex ($cs){
      '^(gb2312|gbk|gb18030|x-gbk|csgb2312)$' { $enc = [System.Text.Encoding]::GetEncoding(936) }
      '^(big5|big-5|csbig5|zh-tw)$'          { $enc = [System.Text.Encoding]::GetEncoding(950) }
      '^(shift_jis|sjis|shift-jis|windows-31j|cp932|x-sjis)$' { $enc = [System.Text.Encoding]::GetEncoding(932) }
      '^(euc-jp|x-euc-jp)$'                   { $enc = [System.Text.Encoding]::GetEncoding(51932) }
      '^(euc-kr|ks_c_5601-1987)$'             { $enc = [System.Text.Encoding]::GetEncoding(51949) }
      '^(iso-8859-1|latin1|windows-1252)$'    { $enc = $null }
      default                                  { $enc = [System.Text.Encoding]::UTF8 }
    }
  }catch{ $enc = [System.Text.Encoding]::UTF8 }
  if($enc -eq $null){ $enc = [System.Text.Encoding]::UTF8 }
  $txt = $enc.GetString($bytes)
  # if utf8 decode produced replacement chars, retry gbk / big5 heuristically
  $bad = ([regex]::Matches($txt,'\uFFFD')).Count
  if($bad -gt 3){
    foreach($e in @(936,950,932)){
      $cand = [System.Text.Encoding]::GetEncoding($e).GetString($bytes)
      if(([regex]::Matches($cand,'\uFFFD')).Count -lt $bad){ $txt = $cand; $bad = ([regex]::Matches($txt,'\uFFFD')).Count }
    }
  }
  return @{ Text=$txt; Charset=$cs; Bad=$bad }
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
    $bytes = $r.RawContentStream.ToArray()
    $ct = ""
    try{ $ct = $r.Headers["Content-Type"] }catch{}
    $d = Decode-Bytes $bytes $ct
    $txt = ConvertTo-Text $d.Text
    Set-Content -Path $outTxt -Value $txt -Encoding UTF8
    $junk = ([regex]::Matches($txt,'Ã|â€|ã‚|ï¿½')).Count
    Write-Output "OK   [$($txt.Length)] cs=$($d.Charset) bad=$($d.Bad) junk=$junk $u -> $name.txt"
  }catch{
    $msg = $_.Exception.Message
    Set-Content -Path $outTxt -Value "FETCH_ERROR: $msg`nURL: $u" -Encoding UTF8
    Write-Output "FAIL $u :: $msg"
  }
}
