#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Make the 存档编辑 ball draggable (with a remembered position) and give the panel
one-tap buttons for the common edits, so the free-text console is optional.

Edits work/run/web/__probe.js:
  1. the ball is positioned by explicit left/top (draggable) instead of top:50%;
  2. the panel gets max-height + scrolling, and follows the ball on either side;
  3. placeBall() -> applyPos()/defaultPos(), with the position kept in localStorage
     under 'frog.offline.ball' and a drag distinguishable from a tap;
  4. new rows: 解锁全部明信片 / 解锁博物馆图鉴 / 三叶草+1000 / 抽奖券+10 /
     改名（带输入框，不用 prompt）/ 重载界面.
A DOM `prompt()` would be a DEAD BUTTON inside the APK: WebView only shows a JS dialog
if the host implements onJsPrompt, which this wrapper does not.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

SHELL = str(PROJECT_ROOT) + "/work/run/web/__probe.js"
text = io.open(SHELL, encoding='utf-8').read()
done = []


def sub(old, new, what):
    global text
    n = text.count(old)
    assert n == 1, '%s: anchor matched %d times' % (what, n)
    text = text.replace(old, new)
    done.append(what)


# ---------------------------------------------------------------- 1. ball cssText
sub("""        ball.style.cssText = [
            'position:fixed', 'left:8px', 'top:50%', 'margin-top:-30px',""",
    """        ball.style.cssText = [
            /* left/top are set in px by the drag code below */
            'position:fixed', 'left:8px', 'top:200px',""",
    'ball positioning')

sub("""            'touch-action:manipulation', 'transition:transform .12s',""",
    """            /* none, not manipulation: a drag must not scroll the page under the ball */
            'touch-action:none', 'transition:transform .12s',""",
    'ball touch-action')

sub("""        ball.innerHTML = '<span>存档</span><span style="font-size:10px;font-weight:400">编辑</span>';""",
    """        ball.innerHTML = '<span>存档</span><span style="font-size:10px;font-weight:400">编辑</span>';
        ball.title = '点一下打开 / 按住可以拖到任意位置（位置会记住）';""",
    'ball tooltip')

# ---------------------------------------------------------------- 2. panel cssText
sub("""            'position:fixed', 'left:78px', 'top:50%', 'transform:translateY(-50%)',
            'width:214px', 'z-index:99999', 'display:none',""",
    """            'position:fixed', 'left:78px', 'top:120px',
            'width:214px', 'z-index:99999', 'display:none',
            /* a phone held upright is short: scroll instead of running off the screen */
            'max-height:88vh', 'overflow-y:auto', 'box-sizing:border-box',""",
    'panel positioning + scrolling')

# ---------------------------------------------------------------- 3. drag + placement
OLD_PLACE = """        /* Keep the ball over the GAME, not over the window.
           A phone canvas fills the screen, so anchoring to the window is the same thing
           -- but a desktop window is letterboxed: the canvas still fills it, yet egret
           only paints the centred design column and leaves the sides blank, so a
           window-anchored ball sits far out in that blank margin and reads as "the ball
           is missing on PC".
           Measured on a 1536x810 window: the canvas is 1536x810, the stage is 2158x1136
           (scaleMode fixedHeight), and the courtyard view occupies stage x 652..1506,
           i.e. CSS 465..1074 -- a 609px column centred in the window. So the mapping is
           cssX = stageX * (canvasWidth / stageWidth) with no offset, and the design
           column (DESIGN_W below) is what has to be centred. */
        var DESIGN_W = 640;      /* the client's design width; see index.html */
        function placeBall() {
            var left = BALL_INSET;
            try {
                var c = document.querySelector('canvas');
                var st = egret.MainContext.instance.stage;
                var r = c && c.getBoundingClientRect();
                if (r && r.width > 0 && st && st.stageWidth > 0) {
                    var scale = r.width / st.stageWidth;
                    var colW = DESIGN_W * scale;
                    left = Math.max(BALL_INSET,
                        Math.round(r.left + (r.width - colW) / 2 + BALL_INSET));
                }
            } catch (e) { /* window-anchored is an acceptable fallback */ }
            ball.style.left = left + 'px';
            /* never push the panel off the right edge */
            var pl = left + PANEL_GAP;
            var maxPl = window.innerWidth - 226;
            panel.style.left = Math.max(0, Math.min(pl, maxPl)) + 'px';
        }
        placeBall();
        window.addEventListener('resize', placeBall);
        /* The game chooses its scale mode (and so sizes the canvas) some time after boot,
           so this cannot be measured once at install time. */
        var placeTries = 0;
        var placeTimer = setInterval(function () {
            placeTries++;
            placeBall();
            if (placeTries > 40) clearInterval(placeTimer);
        }, 250);
"""

NEW_PLACE = """        /* ---- where the ball sits, and dragging it ----
           Default position: just inside the GAME's own left edge, not the window's.
           A phone canvas fills the screen so the two are the same thing, but a desktop
           window is letterboxed: the canvas still fills it, yet egret paints only the
           centred design column and leaves the sides blank, so a window-anchored ball
           sits far out in that blank margin and reads as "the ball is missing on PC".
           Measured on a 1536x810 window: canvas 1536x810, stage 2158x1136 (fixedHeight),
           the courtyard view at stage x 652..1506 == CSS 465..1074. The mapping is
           cssX = stageX * (canvasWidth / stageWidth) with no offset. */
        var DESIGN_W = 640;      /* the client's design width; see index.html */
        var BALL_SIZE = 66;      /* 60 + the 3px border on each side */
        var PANEL_W = 226;
        var PANEL_H = 384;       /* enough to keep a 7-row panel on screen */
        var POS_KEY = 'frog.offline.ball';
        var curPos = null;       /* the position in use; drags update it */
        var posIsUsers = false;  /* a remembered/dragged position wins over the default */
        var suppressClick = false;

        function clampTo(v, lo, hi) { return Math.max(lo, Math.min(v, hi)); }

        function defaultPos() {
            var left = BALL_INSET;
            try {
                var c = document.querySelector('canvas');
                var st = egret.MainContext.instance.stage;
                var r = c && c.getBoundingClientRect();
                if (r && r.width > 0 && st && st.stageWidth > 0) {
                    var scale = r.width / st.stageWidth;
                    left = Math.max(BALL_INSET,
                        Math.round(r.left + (r.width - DESIGN_W * scale) / 2 + BALL_INSET));
                }
            } catch (e) { /* window-anchored is an acceptable fallback */ }
            return { x: left, y: Math.round(window.innerHeight / 2 - BALL_SIZE / 2) };
        }

        function loadSavedPos() {
            try {
                var raw = window.localStorage.getItem(POS_KEY);
                if (!raw) return null;
                var p = JSON.parse(raw);
                if (!p || typeof p.x !== 'number' || typeof p.y !== 'number') return null;
                return p;
            } catch (e) { return null; }   /* private mode: the position just isn't kept */
        }

        function applyPos(p) {
            var w = window.innerWidth, h = window.innerHeight;
            curPos = {
                x: clampTo(Math.round(p.x), 0, Math.max(0, w - BALL_SIZE)),
                y: clampTo(Math.round(p.y), 0, Math.max(0, h - BALL_SIZE)),
            };
            ball.style.left = curPos.x + 'px';
            ball.style.top = curPos.y + 'px';
            /* the panel opens on whichever side of the ball has room */
            var right = curPos.x + BALL_SIZE + 8;
            panel.style.left = ((right + PANEL_W <= w) ? right
                : Math.max(0, curPos.x - PANEL_W - 8)) + 'px';
            panel.style.top = clampTo(curPos.y, 8, Math.max(8, h - PANEL_H)) + 'px';
        }

        function savePos() {
            try {
                window.localStorage.setItem(POS_KEY, JSON.stringify(curPos));
            } catch (e) { /* nothing to do: the position simply isn't remembered */ }
        }

        /* ---- dragging ---- */
        var drag = null;

        function pointOf(ev) {
            var t = (ev.touches && ev.touches[0]) || (ev.changedTouches && ev.changedTouches[0]) || ev;
            return { x: t.clientX, y: t.clientY };
        }

        function dragStart(ev) {
            var p = pointOf(ev);
            var r = ball.getBoundingClientRect();
            drag = { dx: p.x - r.left, dy: p.y - r.top, x0: p.x, y0: p.y, moved: false };
            ball.style.transition = 'none';
        }

        function dragMove(ev) {
            if (!drag) return;
            var p = pointOf(ev);
            if (!drag.moved && (Math.abs(p.x - drag.x0) > 4 || Math.abs(p.y - drag.y0) > 4)) {
                drag.moved = true;
            }
            if (!drag.moved) return;         /* a tap must not shift the ball */
            applyPos({ x: p.x - drag.dx, y: p.y - drag.dy });
            if (ev.cancelable) ev.preventDefault();
        }

        function dragEnd() {
            if (!drag) return;
            var wasDrag = drag.moved;
            drag = null;
            ball.style.transition = 'transform .12s';
            if (wasDrag) {
                posIsUsers = true;
                savePos();
                /* the click event still fires after a drag: swallow that one */
                suppressClick = true;
            }
        }

        ball.addEventListener('mousedown', dragStart);
        ball.addEventListener('touchstart', dragStart, { passive: true });
        document.addEventListener('mousemove', dragMove);
        document.addEventListener('mouseup', dragEnd);
        document.addEventListener('touchmove', dragMove, { passive: false });
        document.addEventListener('touchend', dragEnd);

        var saved = loadSavedPos();
        if (saved) { posIsUsers = true; applyPos(saved); } else { applyPos(defaultPos()); }
        window.addEventListener('resize', function () {
            applyPos(curPos || (posIsUsers ? defaultPos() : defaultPos()));
        });
        /* The game chooses its scale mode (and so sizes the canvas) some time after boot,
           so the DEFAULT cannot be measured once at install time. Once the player has
           moved the ball, stop touching it. */
        var placeTries = 0;
        var placeTimer = setInterval(function () {
            placeTries++;
            if (!posIsUsers) applyPos(defaultPos());
            if (placeTries > 40) clearInterval(placeTimer);
        }, 250);
"""
sub(OLD_PLACE, NEW_PLACE, 'placement + drag')

# ---------------------------------------------------------------- 4. click vs drag
sub("""        ball.onclick = function () {
            var open = panel.style.display === 'block';
            panel.style.display = open ? 'none' : 'block';
            ball.style.transform = open ? 'none' : 'scale(.94)';
            if (!open) note('');
        };
        ball.onmousedown = function () { ball.style.transform = 'scale(.92)'; };
        ball.onmouseup = function () { ball.style.transform = 'none'; };""",
    """        ball.onclick = function () {
            if (suppressClick) { suppressClick = false; return; }   /* that was a drag */
            var open = panel.style.display === 'block';
            panel.style.display = open ? 'none' : 'block';
            ball.style.transform = open ? 'none' : 'scale(.94)';
            if (!open) {
                note('');
                /* the panel can be taller than the window on a short screen */
                panel.style.top = clampTo(curPos ? curPos.y : 8, 8,
                    Math.max(8, window.innerHeight - Math.min(PANEL_H, panel.scrollHeight || PANEL_H))) + 'px';
            }
        };""",
    'click vs drag')

# ---------------------------------------------------------------- 5. new rows
sub("""        row(['立刻出门', '立刻回家'], [
            function () { gm('travel_now'); },
            function () { gm('come_home'); },
        ]);""",
    """        row(['解锁全部明信片', '解锁博物馆图鉴'], [
            function () { gm('unlock_pictures'); },
            function () { gm('unlock_museum'); },
        ]);

        row(['三叶草 +1000', '抽奖券 +10'], [
            function () { gm('add_clover 1000'); },
            function () { gm('add_ticket 10'); },
        ]);

        row(['立刻出门', '立刻回家'], [
            function () { gm('travel_now'); },
            function () { gm('come_home'); },
        ]);

        /* Renaming needs a text box, NOT window.prompt(): inside the APK the page runs in
           a WebView, which only shows a JS dialog if the host implements onJsPrompt --
           this wrapper does not, so prompt() would be a button that does nothing. */
        var nameLine = document.createElement('div');
        nameLine.style.cssText = 'display:flex;gap:6px;margin-bottom:6px';
        var nameInput = document.createElement('input');
        nameInput.type = 'text';
        nameInput.maxLength = 12;
        nameInput.placeholder = '新名字（最多 12 字）';
        nameInput.style.cssText = [
            'flex:1', 'min-width:0', 'padding:6px 7px', 'box-sizing:border-box',
            'border-radius:6px', 'border:1px solid ' + EDGE, 'background:#fffdf6',
            'color:' + INK, 'font-family:inherit', 'font-size:12px',
        ].join(';');
        var nameBtn = document.createElement('button');
        nameBtn.textContent = '改名';
        nameBtn.style.cssText = [
            'flex:0 0 62px', 'padding:7px 4px', 'cursor:pointer', 'font-size:12px',
            'border-radius:6px', 'border:1px solid ' + EDGE,
            'background:linear-gradient(#fffdf6,#efe9d6)', 'color:' + INK,
            'font-family:inherit',
        ].join(';');
        nameBtn.onclick = function () {
            var n = (nameInput.value || '').trim();
            if (!n) { note('先在上面输入新名字'); return; }
            gm('set_name ' + n);
            nameInput.value = '';
        };
        nameLine.appendChild(nameInput);
        nameLine.appendChild(nameBtn);
        panel.appendChild(nameLine);""",
    'new action rows + rename input')

OLD_GM_ROW = """        row(['指令台（高级）', '关闭'], [
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
        ]);"""

NEW_GM_ROW = """        row(['重载界面', '指令台（高级）'], [
            /* Everything above now applies immediately (the engine pushes the pages it
               changed), so this is only a fallback for anything that still looks stale. */
            function () {
                note('正在重新载入…');
                setTimeout(function () { location.reload(); }, 120);
            },
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
        ]);

        row(['关闭'], [
            function () { panel.style.display = 'none'; },
        ]);"""

sub(OLD_GM_ROW, NEW_GM_ROW, 'reload + close rows')

sub("""        var hint = document.createElement('div');
        hint.textContent = '立刻出门需要背包里有东西；空手时蛙蛙会在家等。';""",
    """        var hint = document.createElement('div');
        hint.textContent = '这些按钮立刻生效，不用重启。点一下圆球打开面板，按住可以拖动它。'
            + '立刻出门需要背包里有东西，空手时蛙蛙会在家等。';""",
    'hint text')

sub("""        var BUILD_STAMP = '2026-09-12 12:49';""",
    """        var BUILD_STAMP = '2026-09-12 13:26';""",
    'build stamp')

io.open(SHELL, 'w', encoding='utf-8', newline='').write(text)
print('patched __probe.js: %d edits' % len(done))
for d in done:
    print('  *', d)
