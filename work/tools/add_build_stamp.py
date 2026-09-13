#!/usr/bin/env python3
"""Stamp the build so a player can SEE whether their copy is current.

"悬浮球在 PC 不显示，手机正常" turned out not to reproduce here: the PC launcher path
(play_frog.py on its own port) renders the ball exactly like the phone does, and the
launcher already sends Cache-Control: no-store. The likely cause is a stale page (a tab or
launcher started before the change, or a copied game folder). Rather than guess, the shell
now prints a build stamp in the ball's panel, so "am I running the new build?" is answerable
at a glance -- and the stamp is the newest mtime among the files that make up the shell.
"""
import io
import os
import time

WEB = r"H:\AI\frog\work\run\web"
P = os.path.join(WEB, "__probe.js")

# The stamp: newest mtime of the files that decide what the player sees.
files = ["index.html", "__probe.js", "__offline-engine.js",
         os.path.join("resource", "China", "config", "gameConfig.json")]
newest = 0
for f in files:
    p = os.path.join(WEB, f)
    if os.path.exists(p):
        newest = max(newest, os.path.getmtime(p))
stamp = time.strftime("%Y-%m-%d %H:%M", time.localtime(newest))

src = io.open(P, encoding="utf-8").read()
old = """        var title = document.createElement('div');
        title.textContent = '存档编辑';"""
new = """        var BUILD_STAMP = '%s';

        var title = document.createElement('div');
        title.textContent = '存档编辑';""" % stamp
assert src.count(old) == 1, "title block not found"
src = src.replace(old, new)

hint_old = """        var hint = document.createElement('div');
        hint.textContent = '立刻出门需要背包里有东西；空手时蛙蛙会在家等。';"""
hint_new = """        var stampLine = document.createElement('div');
        stampLine.textContent = '版本 ' + BUILD_STAMP;
        stampLine.title = '这一份的文件时间；比对我的改动时间就知道是不是最新的一份';
        stampLine.style.cssText = 'font-size:10px;color:#a79c81;text-align:center;margin-top:6px';
        panel.appendChild(stampLine);

        var hint = document.createElement('div');
        hint.textContent = '立刻出门需要背包里有东西；空手时蛙蛙会在家等。';"""
assert src.count(hint_old) == 1, "hint block not found"
src = src.replace(hint_old, hint_new)

io.open(P, "w", encoding="utf-8").write(src)
print("build stamp added:", stamp)
