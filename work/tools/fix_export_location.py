#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Make 导出存档 in the APK actually write a file, and tell the player WHERE.

The bug: saveOut() only did a Blob `<a download>` click. Inside an Android WebView that
is silently dropped (the wrapper installs no DownloadListener), yet the panel printed
"已导出 frog-save-….json" regardless -- a button that claims success while writing
nothing. The wrapper's real channel, FrogNative.exportSave(name, json), was never called.

New behaviour:
  * FrogNative.exportSave first. It returns the location ("内部存储/Download/…") on
    API 29+, or the sentinel PICKER on older Androids (the location then arrives through
    window.__saveExported()).
  * A failure or a cancel says so, instead of a fake success.
  * Without the bridge (PC browsers) the Blob download stays, and its message now names
    the browser's download folder.
"""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 2），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

SHELL = str(PROJECT_ROOT) + "/work/run/web/__probe.js"
text = io.open(SHELL, encoding='utf-8').read()
done = []


def sub(old, new, what):
    global text
    n = text.count(old)
    assert n == 1, '%s: matched %d times' % (what, n)
    text = text.replace(old, new)
    done.append(what)


OLD_SAVEOUT = """        /* Hand the browser a file. This used to live in the old button helper; the ball
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
        }"""

NEW_SAVEOUT = """        /* ---- where an exported save actually goes -----------------------------------
           The Android case is the one that matters: a Blob download is SILENTLY DROPPED
           inside a WebView (this wrapper installs no DownloadListener), so the old code
           printed "已导出 frog-save-….json" while writing nothing at all -- a success
           message for a file that did not exist.

           The wrapper's real channel is FrogNative.exportSave(name, json):
             · Android 10+ (API 29): writes straight into 内部存储/Download and returns
               that path -- no permission needed, and no dialog to hunt through;
             · older Androids: opens the system 保存到 dialog and reports the chosen
               location afterwards through window.__saveExported().
           So the bridge comes first, and neither path is allowed to claim success that
           we cannot see. */
        window.__saveExported = function (where) {
            note('存档已导出到：' + where + '\\n（要用的时候，点「导入存档」把它选回来）');
        };
        window.__saveExportFailed = function (why) {
            note('导出没有完成：' + (why || '已取消'));
        };

        /* PC / browser fallback. (This helper also used to go missing entirely, which is
           what made 导出存档 throw "saveOut is not defined" -> 呱呱吃坏肚子了.) */
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
                note('已导出 ' + a.download + '\\n（在你浏览器的下载目录里）');
            } catch (e) {
                /* A WebView that blocks blob downloads still has the text: show it so the
                   player can copy it out rather than losing the save. */
                note('浏览器不允许直接下载，请长按复制下面的存档：\\n' + String(text).slice(0, 400) + '…');
            }
        }"""

sub(OLD_SAVEOUT, NEW_SAVEOUT, 'saveOut + native callbacks')

OLD_BTN = """            function () {
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
            },"""

NEW_BTN = """            function () {
                var stamp = new Date().toISOString().slice(0, 10);
                var name = 'frog-save-' + stamp + '.json';
                if (usingLocalEngine()) {
                    var data = window.localStorage.getItem('frog.offline.save') || '{}';
                    /* On the APK this is the only channel that writes anything, and it is
                       the one that can tell us WHERE. */
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
                    saveOut(data, name);
                } else {
                    fetch('/__export').then(function (r) { return r.text(); })
                        .then(function (t) { saveOut(t, name); })
                        .catch(function (e) { note('导出失败: ' + e); });
                }
            },"""

sub(OLD_BTN, NEW_BTN, 'export button')

io.open(SHELL, 'w', encoding='utf-8', newline='').write(text)
print('patched __probe.js: %d edits' % len(done))
for d in done:
    print('  *', d)
