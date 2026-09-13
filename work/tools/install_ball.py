#!/usr/bin/env python3
"""Item 3: replace the shell's save tools with a game-styled 存档编辑 floating ball.

What changes
  * `gameConfig.json` gets `showGM: false`, which removes the client's own debug entry --
    the semi-transparent red square at the left edge (the config comment says as much).
    The GM CONSOLE view still exists, so the ball can still open it.
  * `installSaveTools()` becomes a round ball at the left middle. Tapping it opens a
    parchment panel holding what used to be scattered around: 立刻出门 / 立刻回家,
    导出存档 / 导入存档 (moved off the bottom-right corner), 指令台, and 关闭.
  * the duplicated installOfflineAds() call the earlier patch left behind is removed.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import re

PROBE = str(PROJECT_ROOT) + "/work/run/web/__probe.js"
CFG = str(PROJECT_ROOT) + "/work/run/web/resource/China/config/gameConfig.json"

NEW = r"""    function installSaveTools() {
        if (document.getElementById('__save_ball')) return;

        /* A round button in the game's own palette (the parchment tones the client uses
           for its dialogs: #f6f2e6 paper, #b9ad8d border, #4a4433 ink) instead of the
           debug red square the GM flag used to draw. Left middle, where that square was. */
        var PAPER = '#f6f2e6', EDGE = '#b9ad8d', INK = '#4a4433', LEAF = '#7ba05b';

        var ball = document.createElement('div');
        ball.id = '__save_ball';
        ball.title = '存档编辑';
        ball.style.cssText = [
            'position:fixed', 'left:8px', 'top:50%', 'margin-top:-30px',
            'width:60px', 'height:60px', 'border-radius:50%', 'z-index:99998',
            'background:radial-gradient(circle at 32% 28%, #fbf8ee 0%, ' + PAPER + ' 55%, #e6dfc9 100%)',
            'border:3px solid ' + LEAF,
            'box-shadow:0 3px 8px rgba(60,50,30,.35), inset 0 0 0 2px rgba(255,255,255,.6)',
            'cursor:pointer', 'user-select:none', '-webkit-user-select:none',
            'display:flex', 'align-items:center', 'justify-content:center',
            'flex-direction:column', 'line-height:1.05',
            'font-family:"PingFang SC","Microsoft YaHei","Heiti SC",sans-serif',
            'color:' + INK, 'font-size:15px', 'font-weight:600',
            'touch-action:manipulation', 'transition:transform .12s',
        ].join(';');
        ball.innerHTML = '<span>存档</span><span style="font-size:10px;font-weight:400">编辑</span>';

        /* ---- the panel ---- */
        var panel = document.createElement('div');
        panel.id = '__save_panel';
        panel.style.cssText = [
            'position:fixed', 'left:78px', 'top:50%', 'transform:translateY(-50%)',
            'width:214px', 'z-index:99999', 'display:none',
            'background:' + PAPER, 'border:2px solid ' + EDGE, 'border-radius:10px',
            'box-shadow:0 6px 18px rgba(60,50,30,.4)', 'padding:10px',
            'font-family:"PingFang SC","Microsoft YaHei","Heiti SC",sans-serif',
            'color:' + INK,
        ].join(';');

        var title = document.createElement('div');
        title.textContent = '存档编辑';
        title.style.cssText = 'font-size:15px;font-weight:700;text-align:center;'
            + 'padding-bottom:6px;margin-bottom:8px;border-bottom:1px solid ' + EDGE;
        panel.appendChild(title);

        var msg = document.createElement('div');
        msg.style.cssText = 'font-size:12px;line-height:1.5;min-height:16px;'
            + 'margin-top:8px;word-break:break-all;color:#6b6season'.replace('season', '553');
        panel.appendChild(msg);

        function note(text) { msg.textContent = text || ''; }

        /* Send a GM command through the CLIENT's own socket, exactly like the console
           does, so the reply (and any state push) comes back the normal way. */
        function gm(cmd) {
            try {
                core.SocketManage.getInstance().send('client_gm',
                    new core.Action2(function (r) {
                        note(r && r.succeed ? (r.info || '完成') : ('失败：' + (r && r.info || '')));
                    }), cmd);
            } catch (e) {
                note('执行失败: ' + e);
            }
        }

        function row(labels, handlers) {
            var line = document.createElement('div');
            line.style.cssText = 'display:flex;gap:6px;margin-bottom:6px';
            for (var i = 0; i < labels.length; i++) {
                var b = document.createElement('button');
                b.textContent = labels[i];
                b.style.cssText = [
                    'flex:1', 'padding:7px 4px', 'cursor:pointer', 'font-size:13px',
                    'border-radius:6px', 'border:1px solid ' + EDGE,
                    'background:linear-gradient(#fffdf6,#efe9d6)', 'color:' + INK,
                    'font-family:inherit',
                ].join(';');
                b.onclick = handlers[i];
                line.appendChild(b);
            }
            panel.appendChild(line);
            return line;
        }

        row(['立刻出门', '立刻回家'], [
            function () { gm('travel_now'); },
            function () { gm('come_home'); },
        ]);

        function usingLocalEngine() {
            return !!window.FrogEngine && !!window.__installLoopback && window.__loopbackActive;
        }

        row(['导出存档', '导入存档'], [
            function () {
                var stamp = new Date().toISOString().slice(0, 10);
                if (usingLocalEngine()) {
                    var data = window.localStorage.getItem('frog.offline.save') || '{}';
                    saveOut(data, 'frog-save-' + stamp + '.json');
                    note('已导出 frog-save-' + stamp + '.json');
                } else {
                    fetch('/__export').then(function (r) { return r.text(); })
                        .then(function (t) { saveOut(t, 'frog-save-' + stamp + '.json'); })
                        .catch(function (e) { note('导出失败: ' + e); });
                }
            },
            function () {
                var inp = document.createElement('input');
                inp.type = 'file';
                inp.accept = '.json,application/json';
                inp.onchange = function () {
                    var f = inp.files && inp.files[0];
                    if (!f) return;
                    var rd = new FileReader();
                    rd.onload = function () {
                        var text = String(rd.result);
                        try { JSON.parse(text); } catch (e) { note('不是合法的存档 JSON'); return; }
                        if (usingLocalEngine()) {
                            window.localStorage.setItem('frog.offline.save', text);
                            location.reload();
                        } else {
                            fetch('/__import', { method: 'POST', body: text })
                                .then(function (r) { return r.json(); })
                                .then(function (j) {
                                    if (j.ok) location.reload(); else note('导入失败: ' + j.error);
                                })
                                .catch(function (e) { note('导入失败: ' + e); });
                        }
                    };
                    rd.readAsText(f);
                };
                inp.click();
            },
        ]);

        row(['指令台（高级）', '关闭'], [
            function () {
                /* the client's own free-form console; the ball just opens it, so the
                   existing command set (state / add_clover / unlock_pictures / …) stays
                   available without its debug square on screen. */
                try {
                    core.PageManage.getInstance().addViewControl(GMViewController,
                        core.ViewLayerType.WindowLayer);
                    panel.style.display = 'none';
                } catch (e) {
                    note('打不开指令台: ' + e);
                }
            },
            function () { panel.style.display = 'none'; },
        ]);

        var hint = document.createElement('div');
        hint.textContent = '立刻出门需要背包里有东西；空手时蛙蛙会在家等。';
        hint.style.cssText = 'font-size:11px;line-height:1.4;color:#8a8168;margin-top:2px';
        panel.appendChild(hint);

        ball.onclick = function () {
            var open = panel.style.display === 'block';
            panel.style.display = open ? 'none' : 'block';
            ball.style.transform = open ? 'none' : 'scale(.94)';
            if (!open) note('');
        };
        ball.onmousedown = function () { ball.style.transform = 'scale(.92)'; };
        ball.onmouseup = function () { ball.style.transform = 'none'; };

        document.body.appendChild(ball);
        document.body.appendChild(panel);
        push('[shell]', ['存档编辑 ball installed (showGM is off)']);
    }

"""

src = io.open(PROBE, encoding="utf-8").read()
i = src.find("    function installSaveTools()")
j = src.find("    /* --------------------------------------------------- main watchdog */")
assert i > 0 and j > i, (i, j)
src = src[:i] + NEW + src[j:]

# remove the duplicated installOfflineAds() call the earlier patch left in the watchdog
dup = """        try { installOfflineAds(); } catch (e) { }
            try { installOfflineAds(); } catch (e) { }
"""
if src.count(dup) == 1:
    src = src.replace(dup, "        try { installOfflineAds(); } catch (e) { }\n")
    print("removed the duplicated installOfflineAds() call")

io.open(PROBE, "w", encoding="utf-8").write(src)
print("installSaveTools replaced; installOfflineAds call sites now:",
      src.count("installOfflineAds();"))

cfg = io.open(CFG, encoding="utf-8").read()
old_c = ('''    "_comment_showGM": "true 会显示一个半透明红方块(左上偏中)与菜单里的 GM 按钮；'''
         '''点开是游戏内置指令台，本离线版的存档编辑器就走它（见 engine/index.js 的 client_gm）",
    "showGM": true,''')
new_c = (
    '    "_comment_showGM": "false 关掉客户端自带的半透明红方块与菜单 GM 按钮。'
    '存档编辑器改由外壳的悬浮球（左侧「存档编辑」圆钮）打开，球里的「指令台」'
    '仍会打开这台内置控制台（见 engine/index.js 的 client_gm）",\n'
    '    "showGM": false,')
assert cfg.count(old_c) == 1, "gameConfig showGM block not found"
io.open(CFG, "w", encoding="utf-8").write(cfg.replace(old_c, new_c))
print("gameConfig.json: showGM -> false")
