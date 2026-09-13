#!/usr/bin/env python3
"""Fix the quoting slip in install_ball.py, then run it."""
import io

P = r"H:\AI\frog\work\tools\install_ball.py"
src = io.open(P, encoding="utf-8").read()
start = src.index('new_c = (')
end = src.index('assert cfg.count(old_c) == 1')
fixed = (
    'new_c = (\n'
    '    \'    "_comment_showGM": "false 关掉客户端自带的半透明红方块与菜单 GM 按钮。\'\n'
    '    \'存档编辑器改由外壳的悬浮球（左侧「存档编辑」圆钮）打开，球里的「指令台」\'\n'
    '    \'仍会打开这台内置控制台（见 engine/index.js 的 client_gm）",\\n\'\n'
    '    \'    "showGM": false,\')\n'
)
src = src[:start] + fixed + src[end:]
io.open(P, "w", encoding="utf-8").write(src)
print("install_ball.py patched")
