#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Patch a shell + index.html for the V3 handover build.

Three changes, nothing else:

  1. 存档导出修复 (the round before this one): the shell's 导出存档 only did a Blob
     download, which an Android WebView drops silently -- so it claimed success while
     writing nothing. Now it calls the wrapper's FrogNative.exportSave(name, json) first,
     which writes into 内部存储/Download (API 29+) or opens the system 保存到 dialog, and
     reports the real location back through window.__saveExported(). Skipped when the
     target already has it.

  2. 帮助菜单的「联系客服」改为「制作人员」, and its content becomes the credits list.
     The button (client view Help, skin Menu/Help.exml, component `btn_customer`) gets its
     label rewritten AT RUNTIME -- the label text ships inside the client's encrypted
     config bundle, so it cannot be edited as data. The tap is already routed through
     BaseChannel.open_custom_service(), which this shell overrides, so the content is ours:
     a small overlay with 旅行青蛙离线版制作组 + the four names.

  3. 开始页面的《权利归属与告知声明》声明人 -> 旅行青蛙离线版制作组 (index.html).

Usage:
  python tools/v3_credits_and_export.py --shell <path to __probe.js> [--index <path to index.html>]
Both edits are idempotent: running it twice changes nothing the second time.
"""
import argparse
import io
import os
import sys

CREDITS_TITLE = '制作人员'
CREDITS_GROUP = '旅行青蛙离线版制作组'
CREDITS_NAMES = ['Balticx', '兔子国国王', '西瓜给我咬一口', 'yxcatqwq']

EXPORT_ANCHOR = """        function saveOut(text, filename) {"""
EXPORT_OLD = """        /* Hand the browser a file. This used to live in the old button helper; the ball
           replaced that function and took the helper with it, so 导出存档 threw
           "saveOut is not defined" and the client turned that into 呱呱吃坏肚子了. */
        function saveOut(text, filename) {"""

EXPORT_NEW = """        /* ---- where an exported save actually goes -----------------------------------
           Android (the APK) is the important case: a Blob download is SILENTLY DROPPED
           inside a WebView (the wrapper installs no DownloadListener), so the old code
           printed "已导出 frog-save-….json" while writing nothing at all.
           The wrapper's real channel is FrogNative.exportSave(name, json):
             · Android 10+ writes straight into 内部存储/Download and returns that path;
             · older Androids open the system 保存到 dialog and report the location
               afterwards through window.__saveExported().
           So the bridge comes first, and neither path may claim success we cannot see. */
        window.__saveExported = function (where) {
            note('存档已导出到：' + where + '\\n（要用的时候，点「导入存档」把它选回来）');
        };
        window.__saveExportFailed = function (why) {
            note('导出没有完成：' + (why || '已取消'));
        };

        /* Hand the browser a file. This used to live in the old button helper; the ball
           replaced that function and took the helper with it, so 导出存档 threw
           "saveOut is not defined" and the client turned that into 呱呱吃坏肚子了. */
        function saveOut(text, filename) {"""

EXPORT_BTN_OLD = """                    var data = window.localStorage.getItem('frog.offline.save') || '{}';
                    saveOut(data, 'frog-save-' + stamp + '.json');
                    note('已导出 frog-save-' + stamp + '.json');"""

EXPORT_BTN_NEW = """                    var data = window.localStorage.getItem('frog.offline.save') || '{}';
                    var name = 'frog-save-' + stamp + '.json';
                    /* On the APK this is the only channel that writes anything, and the
                       only one that can say WHERE. */
                    if (window.FrogNative && FrogNative.exportSave) {
                        var where = '';
                        try {
                            where = String(FrogNative.exportSave(name, data) || '');
                        } catch (e) {
                            where = '';
                        }
                        if (where === 'PICKER') {
                            note('已打开系统的「保存到」窗口：\\n选好文件夹 → 保存。文件名 ' + name
                                + '\\n保存完成后这里会告诉你具体位置。');
                        } else if (where) {
                            note('存档已导出到：' + where
                                + '\\n（要用的时候，点「导入存档」把它选回来）');
                        } else {
                            note('导出没有完成：系统没有给出保存位置。');
                        }
                        return;
                    }
                    saveOut(data, name);"""

CREDITS_ANCHOR = """        /* the help menu does `.then()` on the result, so this must be a thenable */
        P.open_custom_service = function () {
            try {
                core.PageManage.getInstance().addViewControl(
                    CustomerViewController, core.ViewLayerType.NoticeLayer);
            } catch (e) {
                push('[kefu-error]', [String(e && e.stack || e)]);
            }
            return Promise.resolve();
        };"""

CREDITS_NEW = """        /* ---- 帮助菜单里的「制作人员」-----------------------------------------------
           The client's Help view (skin Menu/Help.exml) has a `btn_customer` whose tap goes
           through BaseChannel.open_custom_service(). The original shipped the operator's
           own contact panel (Menu/Customer.exml: 官方微博 / 官方Q群), which is meaningless
           offline, and the button label itself lives inside the client's encrypted config
           bundle -- so the label is rewritten AT RUNTIME (see relabelHelpButton) and the
           content is this overlay. */
        var CREDITS_TITLE = __CREDITS_TITLE__;
        var CREDITS_GROUP = __CREDITS_GROUP__;
        var CREDITS_NAMES = __CREDITS_NAMES__;

        function showCredits() {
            if (!document || !document.body) return false;
            var old = document.getElementById('__credits');
            if (old && old.parentNode) old.parentNode.removeChild(old);
            var wrap = document.createElement('div');
            wrap.id = '__credits';
            wrap.style.cssText = [
                'position:fixed', 'left:0', 'top:0', 'right:0', 'bottom:0',
                'z-index:2147483000', 'background:rgba(20,18,14,.72)',
                'display:flex', 'align-items:center', 'justify-content:center',
                'font-family:"PingFang SC","Microsoft YaHei","Heiti SC",sans-serif',
            ].join(';');
            var card = document.createElement('div');
            card.style.cssText = [
                'min-width:250px', 'max-width:80vw', 'background:#f6f2e6',
                'border:2px solid #b9ad8d', 'border-radius:12px',
                'box-shadow:0 8px 26px rgba(0,0,0,.45)', 'padding:16px 20px 14px',
                'color:#4a4433', 'text-align:center',
            ].join(';');
            var h = document.createElement('div');
            h.textContent = CREDITS_TITLE;
            h.style.cssText = 'font-size:17px;font-weight:700;letter-spacing:.12em;'
                + 'padding-bottom:8px;margin-bottom:10px;border-bottom:1px solid #d8cfb4';
            card.appendChild(h);
            var g = document.createElement('div');
            g.textContent = CREDITS_GROUP;
            g.style.cssText = 'font-size:15px;font-weight:600;color:#5b7f43;margin-bottom:8px';
            card.appendChild(g);
            for (var i = 0; i < CREDITS_NAMES.length; i++) {
                var n = document.createElement('div');
                n.textContent = CREDITS_NAMES[i];
                n.style.cssText = 'font-size:14px;line-height:1.9';
                card.appendChild(n);
            }
            var btn = document.createElement('button');
            btn.id = '__credits_close';
            btn.textContent = '关闭';
            btn.style.cssText = [
                'margin-top:14px', 'min-width:88px', 'height:32px', 'border-radius:16px',
                'border:1px solid #b9ad8d', 'background:#fffdf6', 'color:#4a4433',
                'font:14px inherit', 'cursor:pointer',
            ].join(';');
            btn.onclick = function () { if (wrap.parentNode) wrap.parentNode.removeChild(wrap); };
            card.appendChild(btn);
            wrap.appendChild(card);
            wrap.onclick = function (ev) { if (ev.target === wrap) btn.onclick(); };
            document.body.appendChild(wrap);
            push('[shell]', ['credits shown']);
            return true;
        }
        window.__showCredits = showCredits;   /* exposed for probes */

        /* The label ships inside the client's encrypted config bundle, so it has to be
           overwritten on the live component. `btn_customer` is an eui.Button, so setting
           `.label` updates its labelDisplay. */
        function relabelHelpButton() {
            var hits = 0;
            function walk(node, depth) {
                if (!node || depth > 14) return;
                var b = null;
                try { b = node.btn_customer; } catch (e) { b = null; }
                if (b) {
                    try {
                        if (b.label !== CREDITS_TITLE) {
                            b.label = CREDITS_TITLE;
                            hits++;
                        }
                        if (b.labelDisplay && b.labelDisplay.text !== CREDITS_TITLE) {
                            b.labelDisplay.text = CREDITS_TITLE;
                        }
                    } catch (e) { push('[credits-error]', [String(e && e.message)]); }
                }
                var kids = node.$children || null;
                if (!kids) return;
                for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1);
            }
            try { walk(egret.MainContext.instance.stage, 0); } catch (e) { /* stage not up */ }
            return hits;
        }
        window.__relabelHelpButton = relabelHelpButton;

        /* The Help view builds its skin asynchronously, so poll briefly after it opens. */
        function scheduleCreditsFix(cls) {
            var tries = 0;
            var t = setInterval(function () {
                tries++;
                var hits = 0;
                try { hits = relabelHelpButton(); } catch (e) { }
                if (hits > 0 || tries > 30) clearInterval(t);
            }, 200);
        }

        P.open_custom_service = function () {
            try {
                showCredits();
            } catch (e) {
                push('[credits-error]', [String(e && e.stack || e)]);
            }
            return Promise.resolve();
        };"""


def patch_shell(path):
    text = io.open(path, encoding='utf-8').read()
    orig = text
    done = []

    # ---- 1. export fix
    if 'FrogNative.exportSave' in text and '__saveExported' in text:
        done.append('export fix: already present')
    else:
        if EXPORT_OLD in text:
            text = text.replace(EXPORT_OLD, EXPORT_NEW)
            done.append('export fix: callbacks + saveOut comment')
        elif EXPORT_ANCHOR in text:
            done.append('export fix: SKIPPED (anchor text differs) -- check manually')
        else:
            raise SystemExit('export fix: neither anchor found in ' + path)
        n = text.count(EXPORT_BTN_OLD)
        if n == 1:
            text = text.replace(EXPORT_BTN_OLD, EXPORT_BTN_NEW)
            done.append('export fix: export button uses the bridge')
        else:
            # the button may already take the other branch shape; report instead of guessing
            done.append('export fix: button anchor matched %d times -- check manually' % n)

    # ---- 2. credits
    if 'function showCredits' in text:
        done.append('credits: already present')
    else:
        if CREDITS_ANCHOR not in text:
            raise SystemExit('credits: anchor not found in ' + path)
        block = (CREDITS_NEW
                 .replace('__CREDITS_TITLE__', "'%s'" % CREDITS_TITLE)
                 .replace('__CREDITS_GROUP__', "'%s'" % CREDITS_GROUP)
                 .replace('__CREDITS_NAMES__',
                          '[' + ', '.join("'%s'" % n for n in CREDITS_NAMES) + ']'))
        text = text.replace(CREDITS_ANCHOR, block)
        done.append('credits: panel + open_custom_service redirect')

    # hook the relabel into the view-open wrapper (once). The guard has to be the CALL
    # shape, not `scheduleCreditsFix(cls)`: that substring also occurs in the function
    # definition above, which made this block skip itself silently the first time.
    if 'try { scheduleCreditsFix(cls); }' not in text:
        anchor = "            try { scheduleCalendarFix(cls); } catch (e) { }"
        if anchor in text:
            text = text.replace(
                anchor,
                anchor + "\n            try { scheduleCreditsFix(cls); } catch (e) { }")
            done.append('credits: relabel hook installed on view open')
        else:
            done.append('credits: WARNING -- view-open hook anchor not found')

    if text != orig:
        io.open(path, 'w', encoding='utf-8', newline='').write(text)
    return done


def patch_index(path):
    text = io.open(path, encoding='utf-8').read()
    done = []
    old = '<p class="__sign">声明人：Balticx</p>'
    new = '<p class="__sign">声明人：%s</p>' % CREDITS_GROUP
    if new in text:
        done.append('notice: already 声明人：%s' % CREDITS_GROUP)
    elif old in text:
        text = text.replace(old, new)
        io.open(path, 'w', encoding='utf-8', newline='').write(text)
        done.append('notice: 声明人 -> %s' % CREDITS_GROUP)
    else:
        done.append('notice: WARNING -- 声明人 line not found (check manually)')
    return done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--shell', required=True)
    ap.add_argument('--index', default=None)
    args = ap.parse_args()

    enc = getattr(sys.stdout, 'encoding', None) or 'utf-8'
    print('shell: %s' % args.shell)
    for d in patch_shell(args.shell):
        print('   ' + d.encode(enc, 'replace').decode(enc, 'replace'))
    if args.index:
        print('index: %s' % args.index)
        for d in patch_index(args.index):
            print('   ' + d.encode(enc, 'replace').decode(enc, 'replace'))


main()
