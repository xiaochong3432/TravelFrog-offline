#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Wire the album's 地图 button to the offline 足迹 page.

Findings that drive this (read from run/web/js/main.min.js, minified client):

  AlbumView constructor:
      this.travelMapBtn.visible = this.travelMapBtn.includeInLayout = !1;
      var t = this.getModel(ActivityModel).getActivity("travelmap");
      null == t
        ? BaseChannel.getInstance().getAnnInfo({type:"activity",tags:["travelmap"],...})
            .then(function (t) {
               if (t && t.anns[0]) {
                 var i = t.anns[0].url, n = t.anns[0].isOpen;
                 n ? (getModel(ActivityModel).addActivity({id:"travelmap",params:{url:i,isOpen:n}}),
                      e.travelMapURL = i,
                      e.travelMapBtn.visible = e.travelMapBtn.includeInLayout = !0)
                   : getModel(ActivityModel).addActivity({id:"travelmap",params:{}});
               }
             })
        : t.params && t.params.isOpen && (...same reveal...);
      this.updateExtend()   // only touches extendBtn -- does NOT hide travelMapBtn

  BaseChannel.prototype.getAnnInfo = async function (e) { return null }

So offline the button is hidden for one reason only: the base channel's activity
request resolves to null. There is no crash and no hang -- it is simply a stub.
The client's OWN reveal path is therefore reusable: answer that one request.

  AlbumView.on_travelMapBtn():
      PageManage.addViewControl(TravelMapController, layerType, null, this.travelMapURL)

TravelMapController.open() is written for the native runtime: it derives the
registrable domain of the url, asks the channel whether WeChat share is
installed, and drives a BaseWebView. In a browser there is no such web view, so
the button is re-pointed at a DOM overlay instead: same page, game still running
underneath, nothing to reload.

Both edits are applied to work/run/web/__probe.js. Idempotent.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import sys

SHELL = str(PROJECT_ROOT) + "/work/run/web/__probe.js"

ANNOUNCE = """
        /* The album's 地图 toolbar button is revealed from a server-driven activity:
               getAnnInfo({type:'activity',tags:['travelmap']}) -> anns[0].url / .isOpen
           The base channel answers `null` (see the comment at openMapOverlay), so the
           button never appeared and the album looked like it had lost its map. There
           is no server offline, and the page the button opens is now one this project
           ships itself (run/web/map.html), so that one request is answered here.
           Only the travelmap tag is answered; every other caller still gets the
           channel's own (empty) answer, so nothing else changes behaviour. */
        P.getAnnInfo = function (opt) {
            try {
                var tags = (opt && opt.tags) || [];
                for (var i = 0; i < tags.length; i++) {
                    if (tags[i] === 'travelmap') {
                        return Promise.resolve({
                            anns: [{ url: MAP_PAGE, isOpen: true, type: 'activity', tags: tags }],
                        });
                    }
                }
            } catch (e) {
                push('[anninfo-error]', [String(e && e.stack || e)]);
            }
            return oGetAnnInfo.apply(this, arguments);
        };
"""

OVERRIDE = """        var oGetAnnInfo = P.getAnnInfo;
"""

MAPFN = """
    /* ------------------------------------------ 9b. 足迹地图 (self-made, offline)
       The original 地图 button opened a web page hosted by the operator (a China map
       with the provinces the frog had visited). Nothing of that server exists offline
       and the album therefore had no map at all.

       What is drawn here instead is a 33-province 足迹 board built from the client's
       OWN province table (visitors.provinceList: DisplayName / FlowerIcon / FlowerName)
       and the flower art the game already ships at
       resource/China/images/visitor/flower/visitor_flower_N.png. It shows which
       provinces the frog has been to (read from the save's acquireProvinces) and which
       four hold a museum.

       It deliberately draws NO administrative boundaries: published maps of China must
       be standard maps with a 审图号, so this page is a card board, not a map outline,
       and it says so on the page itself.

       It is presented as a full-screen DOM overlay rather than a new page so the game
       keeps running behind it and nothing has to reload. */
    function openMapOverlay() {
        if (!document || !document.body) return false;
        var cls = 'note';
        var old = document.getElementById('__map_overlay');
        if (old && old.parentNode) old.parentNode.removeChild(old);

        var wrap = document.createElement('div');
        wrap.id = '__map_overlay';
        wrap.style.cssText = [
            'position:fixed', 'left:0', 'top:0', 'right:0', 'bottom:0',
            'z-index:2147483000', 'background:#1b1b1b',
            'display:flex', 'flex-direction:column',
        ].join(';');

        var bar = document.createElement('div');
        bar.style.cssText = [
            'flex:0 0 auto', 'height:46px', 'display:flex', 'align-items:center',
            'justify-content:space-between', 'padding:0 14px',
            'background:#2b2b2b', 'color:#f6f2e6',
            'font:15px/46px system-ui,-apple-system,"Microsoft YaHei",sans-serif',
            'box-shadow:0 1px 0 rgba(255,255,255,.12)',
        ].join(';');

        var title = document.createElement('div');
        title.textContent = '足迹地图';
        title.style.cssText = 'font-weight:600;letter-spacing:.06em';

        var btn = document.createElement('button');
        btn.id = '__map_close';
        btn.textContent = '关闭';
        btn.style.cssText = [
            'min-width:76px', 'height:32px', 'border-radius:16px',
            'border:1px solid #b9ad8d', 'background:#f6f2e6', 'color:#4a4433',
            'font:14px system-ui,-apple-system,"Microsoft YaHei",sans-serif',
            'cursor:pointer', 'padding:0 14px',
        ].join(';');
        btn.onclick = function () {
            if (wrap.parentNode) wrap.parentNode.removeChild(wrap);
        };

        var frame = document.createElement('iframe');
        frame.id = '__map_frame';
        /* same directory as index.html, so it is there in the APK too */
        frame.src = MAP_PAGE;
        frame.style.cssText = 'flex:1 1 auto;width:100%;border:0;background:#f6f2e6';

        bar.appendChild(title);
        bar.appendChild(btn);
        wrap.appendChild(bar);
        wrap.appendChild(frame);
        document.body.appendChild(wrap);
        push('[shell]', ['map overlay opened: ' + MAP_PAGE]);
        return true;
    }
    window.__openMapOverlay = openMapOverlay;   /* exposed for probes / manual use */
"""

MAP_CONST = """    /* the offline replacement for the operator's hosted 地图 page (see openMapOverlay) */
    var MAP_PAGE = 'map.html';

"""

PATCH_HOOK = """            /* The album's 地图 button opens the client's TravelMapController, which is
               built for the native runtime (it derives the url's registrable domain and
               drives a BaseWebView + the channel share SDK). Reached from the album it
               would not produce a map in a browser, so the page it was pointed at --
               this project's own 足迹 board -- is shown as a DOM overlay instead and
               the controller is not opened at all. Identified by the name __reflect put
               on the prototype, since the class is not a page global. */
            var clsName = '';
            try { clsName = (cls && cls.prototype && cls.prototype.__class__) || ''; } catch (e0) { clsName = ''; }
            if (clsName === 'TravelMapController') {
                try {
                    openMapOverlay();
                } catch (e1) {
                    push('[map-error]', [String(e1 && e1.stack || e1)]);
                }
                return null;
            }
"""


def main():
    text = io.open(SHELL, encoding='utf-8').read()
    orig = text
    report = []

    if 'var MAP_PAGE' not in text:
        anchor = "    function installOfflineChannel() {"
        assert text.count(anchor) == 1, 'installOfflineChannel anchor'
        text = text.replace(anchor, MAP_CONST + anchor)
        report.append('MAP_PAGE const added')
    else:
        report.append('MAP_PAGE const already present')

    if 'function openMapOverlay()' not in text:
        anchor = "    /* ------------------------------------------- 8. no ads offline: the video poster"
        assert text.count(anchor) == 1, 'section 8 anchor'
        text = text.replace(anchor, MAPFN.lstrip('\n') + '\n' + anchor)
        report.append('openMapOverlay added')
    else:
        report.append('openMapOverlay already present')

    if 'P.getAnnInfo = function (opt)' not in text:
        anchor = "        P.__offlineChannelInstalled = true;"
        assert text.count(anchor) == 1, 'install flag anchor'
        text = text.replace(anchor, OVERRIDE + ANNOUNCE + '\n' + anchor)
        report.append('getAnnInfo override added')
    else:
        report.append('getAnnInfo override already present')

    if "clsName === 'TravelMapController'" not in text:
        anchor = """            var r;
            /* A WindowController builds its skin FIRST"""
        assert text.count(anchor) == 1, 'addViewControl body anchor'
        text = text.replace(anchor, "            var r;\n" + PATCH_HOOK +
                            "            /* A WindowController builds its skin FIRST")
        report.append('TravelMapController interception added')
    else:
        report.append('TravelMapController interception already present')

    if text != orig:
        io.open(SHELL, 'w', encoding='utf-8', newline='').write(text)
    out = io.open(str(PROJECT_ROOT) + "/work/logs/fix_map_button.txt", 'w', encoding='utf-8')
    out.write('shell bytes: %d -> %d\n' % (len(orig.encode('utf-8')), len(text.encode('utf-8'))))
    for line in report:
        out.write('  * %s\n' % line)
    out.close()
    print('wrote logs/fix_map_button.txt')


main()
