#!/usr/bin/env python3
"""Restore the saveOut() helper my ball rewrite dropped (clicking 导出存档 threw).

The old installSaveTools() defined `saveOut(data, filename)` in its own scope. When the
ball replaced that function wholesale, the helper went with it -- so the button called an
undefined name, the exception reached the client's global handler, and the player got
「呱呱吃坏肚子了」. This puts a self-contained implementation back in the panel.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

P = str(PROJECT_ROOT) + "/work/run/web/__probe.js"
src = io.open(P, encoding="utf-8").read()

anchor = """        function usingLocalEngine() {
            return !!window.FrogEngine && !!window.__installLoopback && window.__loopbackActive;
        }
"""
assert src.count(anchor) == 1, "anchor not found"

helper = anchor + """
        /* Hand the browser a file. This used to live in the old button helper; the ball
           replaced that function and took the helper with it, so 导出存档 threw
           "saveOut is not defined" and the client turned that into 呱呱吃坏肚子了. */
        function saveOut(text, filename) {
            try {
                var blob = new Blob([String(text)], { type: 'application/json' });
                var url = URL.createObjectURL(blob);
                var a = document.createElement('a');
                a.href = url;
                a.download = filename || 'frog-save.json';
                document.body.appendChild(a);
                a.click();
                setTimeout(function () {
                    document.body.removeChild(a);
                    URL.revokeObjectURL(url);
                }, 1000);
                note('已导出 ' + a.download);
            } catch (e) {
                /* A WebView that blocks blob downloads still has the text: show it so the
                   player can copy it out rather than losing the save. */
                note('浏览器不允许直接下载，请长按复制下面的存档：\\n' + String(text).slice(0, 400) + '…');
            }
        }
"""
src = src.replace(anchor, helper)
io.open(P, "w", encoding="utf-8").write(src)
print("saveOut restored; definitions now:", src.count("function saveOut"))
