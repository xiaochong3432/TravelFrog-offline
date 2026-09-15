# 连不上 GitHub / 推送总是失败怎么办

国内网络下 `git push` 经常失败，典型表现（实测）：

| 现象 | 说明 |
|---|---|
| `Failed to connect to github.com` | DNS 解析到的那个前端 IP 连不上 |
| `Recv failure: Connection was reset` | 连上了但 TLS/HTTP 被重置 |
| 同一个提交**有时成功、有时失败** | 链路是断续的，不是配置错 |
| `api.github.com` 一直是通的 | 所以只能读接口、推不上去 |

先做一次 30 秒诊断：

```powershell
# 1) 解析到哪个 IP
Resolve-DnsName github.com -Type A | Select-Object -Expand IPAddress

# 2) 这个 IP 的 443 能不能连（换成上面解析出来的地址）
Test-NetConnection github.com -Port 443 -InformationLevel Quiet

# 3) 换几个已知的 GitHub 前端 IP 试试
foreach ($ip in '140.82.112.3','140.82.113.3','140.82.114.3','20.205.243.168','20.27.177.113') {
  $c = New-Object System.Net.Sockets.TcpClient
  $ok = $c.ConnectAsync($ip, 443).Wait(4000) -and $c.Connected
  "$ip : " + $(if ($ok) { '可连' } else { '连不上' })
  $c.Close()
}
```

只要有一个「可连」，就有下面四种解法（按推荐顺序）。

## 方案 1：走 SSH over 443（最稳，推荐）

GitHub 的 SSH 也可以跑在 443 端口上，通常比 HTTPS 稳定得多。

```powershell
# 1) 生成密钥（已做过就跳过）
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519 -N '""'

# 2) 写 ~/.ssh/config，让 github.com 自动走 ssh.github.com:443
@'
Host github.com
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 6
'@ | Set-Content $env:USERPROFILE\.ssh\config -Encoding ascii

# 3) 把公钥贴到 GitHub：Settings → SSH and GPG keys → New SSH key
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub

# 4) 验证（应显示 Hi <你的用户名>! You've successfully authenticated）
ssh -T -p 443 git@ssh.github.com

# 5) 仓库里加一个 ssh 远端并推送
git remote add ssh git@github.com:<owner>/<repo>.git
git push ssh main
```

## 方案 2：把 github.com 指到一个能连的前端 IP（需要管理员）

**以管理员身份**编辑 `C:\Windows\System32\drivers\etc\hosts`，追加：

```
140.82.112.3    github.com
140.82.112.3    codeload.github.com
20.205.243.168  api.github.com
```

（IP 会变；如果哪天又失败，按上面的诊断换一个。）

## 方案 3：挂代理

```powershell
git config --global http.proxy  http://127.0.0.1:7890
git config --global https.proxy http://127.0.0.1:7890
# 撤销：
git config --global --unset http.proxy; git config --global --unset https.proxy
```

## 方案 4：不改网络，靠重试脚本

`work/tools/push_github.ps1` 会依次尝试：SSH 远端 → 普通 HTTPS → HTTPS+HTTP/1.1 →
HTTPS 指定前端 IP，多轮重试；**默认不做任何强制推送**。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File work\tools\push_github.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File work\tools\push_github.ps1 -Rounds 10
powershell -NoProfile -ExecutionPolicy Bypass -File work\tools\push_github.ps1 -Remote ssh
```

单次手动写法（实测可用）：

```powershell
git -c http.curloptResolve=github.com:443:140.82.112.3 push origin main
```

另外这些全局设置对坏链路上的 HTTPS 有帮助（可随时 `--unset`）：

```powershell
git config --global http.version HTTP/1.1
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 120
```

## 踩过的坑

- **PowerShell 脚本必须保存为「UTF-8 with BOM」**：PS 5.1 会把没有 BOM 的 `.ps1` 当本地代码页读，
  中文注释被解码坏掉之后会直接报 `Missing closing '}'` 之类的语法错误（本项目在
  `work/tools/push_github.ps1` 与 `test_launcher_port.ps1` 上都踩过，`.gitattributes` 里已注明）。
- 不要用「把 IP 写进 remote URL」的办法（`https://140.82.112.3/...`）：Host 头与证书会对不上；
  要固定 IP 就用上面的 `http.curloptResolve` 或 hosts。
- 不要长期 `http.sslVerify=false`：那等于关掉中间人防护。
