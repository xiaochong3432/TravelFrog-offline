/* Offline shell for 《旅行青蛙·中国之旅》
 *
 * Runs before the game scripts and provides the things the Egret *native*
 * runtime would normally supply, plus the offline-specific fixes:
 *
 *   1. console/error bridge  -> window.__probeLog (always) + POST /__log with ?log=1
 *                               (so the game can be driven headlessly)
 *   2. native bridge stub     -> window.ExternalInterface (Ejoy SDK jsInvokeLua path)
 *   3. lifecycle kick         -> GameConfig.activate + the "resume" event the
 *                                native SDK raises; nothing in a browser does
 *   4. scene fix: scroll clamp -> the garden view's scroller comes up with a
 *                                negative scrollH (-706), pushing the whole
 *                                courtyard off-screen and leaving a blank scene
 *
 * Diagnostic helpers (all opt-in via query string):
 *   ?log=1              also POST the log to /__log (needs a probe server)
 *   ?tap=x,y[,x,y...]   synthesize taps (headless has no pointer)
 *   ?tapdelay=ms        when to start tapping (default 12000)
 *   ?dumptree=seconds   dump the Egret display list + seasonal resource state
 *   ?addtest=1          add raw textures as Bitmaps (isolate texture vs logic)
 *   ?exp=...            scene experiments: scroll=N, hidegroup, top, pos=x,y
 */
(function () {
    var Q = location.search;

    /* ------------------------------------------------ 1. console bridge */
    /* POSTing is OPT-IN via ?log=1. Only a probe server (the old Java
       AssetServerMain) answers /__log; the shipped PC build and the APK serve
       static files, where every flush would return 501 and show up as a console
       error -- which pollutes "did this run throw anything?" checks. The
       in-memory copy below is always kept, so nothing is lost by default. */
    var ENDPOINT = '/__log';
    var POST_TO_SERVER = /[?&]log=1/.test(location.search);
    var queue = [];
    var timer = null;

    function send() {
        if (!queue.length) return;
        var lines = queue.splice(0, queue.length);
        if (!POST_TO_SERVER) return;
        var payload = lines.join('\n');
        try {
            if (navigator.sendBeacon) navigator.sendBeacon(ENDPOINT, payload);
            else fetch(ENDPOINT, { method: 'POST', body: payload, keepalive: true });
        } catch (e) { /* ignore */ }
    }

    /* The log is ALSO kept in memory at window.__probeLog. The POST endpoint
       (/__log) only exists when a probe server is running; the PC build
       (dist/play_frog.py) and the APK serve plain static files, so on those the
       POST would 404/501 and the whole log would be lost. Keeping the last 400
       lines on window lets any CDP client read them back with
       Runtime.evaluate, which needs no cooperation from the server at all. */
    window.__probeLog = [];
    function push(tag, args) {
        try {
            var parts = [];
            for (var i = 0; i < args.length; i++) {
                var a = args[i];
                if (a instanceof Error) parts.push(a.stack || String(a));
                else if (typeof a === 'object') {
                    try { parts.push(JSON.stringify(a)); } catch (e) { parts.push(String(a)); }
                } else parts.push(String(a));
            }
            var line = tag + ' ' + parts.join(' ');
            queue.push(line);
            try {
                window.__probeLog.push(line);
                if (window.__probeLog.length > 400) window.__probeLog.splice(0, window.__probeLog.length - 400);
            } catch (e2) { /* ignore */ }
            if (!timer) timer = setTimeout(function () { timer = null; send(); }, 200);
        } catch (e) { /* ignore */ }
    }

    ['log', 'info', 'warn', 'error'].forEach(function (level) {
        var orig = console[level].bind(console);
        console[level] = function () { push('[' + level + ']', arguments); orig.apply(null, arguments); };
    });
    window.addEventListener('error', function (e) {
        push('[window.onerror]', [e.message + ' @ ' + (e.filename || '') + ':' + (e.lineno || 0) +
            (e.error && e.error.stack ? '\n' + e.error.stack : '')]);
        send();
    });
    window.addEventListener('unhandledrejection', function (e) {
        push('[unhandledrejection]', [String(e.reason && (e.reason.stack || e.reason.message) || e.reason)]);
        send();
    });

    /* ------------------------------------------------ 2. native bridge */
    if (!window.ExternalInterface) {
        window.ExternalInterface = {
            call: function (name) {
                push('[native-stub]', ['ExternalInterface.call(' + name + ') ignored']);
                return null;
            },
            addCallback: function () { /* no-op */ },
        };
    }

    /* The real `EjoySDK` object is injected by the NATIVE app (it is implemented in
       resource/ejoysdk_lua/*.lua). js/ejoySDK.min.js, which IS in the manifest's
       initial list, exports ChatSDK/ZoneSDK/... into window.ALISDK and never
       defines an `EjoySDK` global at all -- so in a browser every
       `EjoySDK.instance()` reference is a ReferenceError.
       Most of the 24 call sites sit inside the Ejoy/WXgame channel classes and are
       never reached while the client runs as ChannelType.Test, but
       UserAgreementView.request() calls it UNCONDITIONALLY, from onComplete --
       so opening 协议 threw and the window never appeared, even though the view
       already carries the complete three-tab agreement text in the bundle
       (USER_ARGEEMENT_CONTENT_1..3, ~38KB) and only calls request() to refresh it
       from the service. This stub makes the bridge calls no-ops, so SDK-dependent
       views fall back to their built-in content instead of throwing. */
    if (!window.EjoySDK) {
        var ejoyStub = {
            init: function () { return ejoyStub; },
            jsInvokeLua: function (mod, fn) {
                push('[ejoysdk-stub]', [mod + '.' + fn + ' ignored']);
                return undefined;
            },
            jsInvokeLuaUseLongCallback: function () { return undefined; },
            jsInvokeLuaSync: function () { return undefined; },
            getConfig: function () {
                return { getConfig: function () { return ''; }, setConfig: function () { } };
            },
            on: function () { }, off: function () { }, onCallback: function () { },
            getVersion: function () { return '0.0.0-offline'; },
            destroy: function () { },
        };
        window.EjoySDK = { instance: function () { return ejoyStub; } };
    }

    /* ------------------------------------------------------ utilities */
    var hooked = false;

    function fp(cls) {
        try {
            if (!cls) return String(cls);
            if (cls.__fp) return cls.__fp;
            var s = String(cls).replace(/\s+/g, ' ').slice(0, 110);
            cls.__fp = s;
            return s;
        } catch (e) { return '?'; }
    }

    function findNodeIn(substr) {
        var stage = (window.egret && egret.MainContext && egret.MainContext.instance)
            ? egret.MainContext.instance.stage : null;
        if (!stage) return null;
        var found = null;
        (function walk(node, depth) {
            if (found || depth > 12 || !node) return;
            var kids = node.$children || [];
            for (var i = 0; i < kids.length; i++) {
                var c = kids[i];
                if (String(c.constructor).indexOf(substr) >= 0) { found = c; return; }
                walk(c, depth + 1);
                if (found) return;
            }
        })(stage, 0);
        return found;
    }

    function findMainOutView() {
        return findNodeIn('MainOut.exml');
    }

    /* ------------------------- 4b. Route B: in-page engine + loopback socket */
    /* Instead of talking to the local WS server, run the very same engine inside
       the page and feed its replies back through the client's own socket layer.
       core.Socket.prototype.connectByUrl/send are the single transport seam:
       SocketManage.send() serialises the envelope; AnalysisProtocol() consumes
       what we dispatch as ReceiveData. Everything in between is untouched. */
    var engine = null;
    var activeSock = null;

    function installLoopback() {
        if (engine) return true;
        // ?transport=ws forces Route A (talk to the local WS server) even when the
        // in-page engine bundle is present - handy for A/B comparison.
        if (/[?&]transport=ws\b/.test(Q)) return false;
        if (!window.FrogEngine || !window.core || !core.Socket || !window.egret) return false;

        engine = window.FrogEngine.createEngine({ savePath: 'save.json', verbose: true });
        /* Expose the live engine so headless probes can set up a scenario (e.g. grant
           a postcard to check that the museum detail page stops showing "?") without
           having to drive the in-game save editor or reload the page. Read-only
           testing aid: gameplay never touches it. */
        window.__engine = engine;
        push('[offlineB]', ['engine created; clover=' + engine.state.clover +
            ' status=' + engine.state.frog.status]);

        var STUB = {
            type: egret.WebSocket.TYPE_STRING,
            addEventListener: function () { }, removeEventListener: function () { },
            close: function () { }, writeUTF: function () { }, flush: function () { },
            readUTF: function () { return ''; },
        };

        function deliver(sock, obj) {
            sock.dispatchEvent(new core.Event(core.SocketEventType.ReceiveData,
                egret.WebSocket.TYPE_STRING, JSON.stringify(obj)));
        }

        var P = core.Socket.prototype;

        P.connectByUrl = function (url, type) {
            this.url = url || 'local://engine';
            this._socket = STUB;                    // getDataType() reads .type
            this.socket_Connect();                  // -> ConnectionSucceed + event
            activeSock = this;
            window.__loopbackActive = true;         // tells the save tools where the save lives
            push('[offlineB]', ['loopback connected (' + this.url + ')']);
        };

        P.send = function (json) {
            if (this._socketState !== core.SocketState.ConnectionSucceed) {
                push('[offlineB]', ['send before connect, dropped: ' + String(json).slice(0, 100)]);
                return;
            }
            var msg;
            try { msg = JSON.parse(json); } catch (e) { return; }
            var out;
            try {
                out = engine.dispatch(msg.cmd, msg.data || {});
            } catch (e) {
                push('[offlineB-error]', ['dispatch ' + msg.cmd + ': ' + (e && e.stack || e)]);
                return;
            }
            if (msg.session != null) {
                deliver(this, { session: msg.session, data: out.reply || {} });
            } else if (out.reply !== undefined) {
                deliver(this, {
                    cmd: window.FrogEngine.toWire(window.FrogEngine.canon(msg.cmd)),
                    data: out.reply,
                });
            }
            var ps = out.pushes || [];
            for (var i = 0; i < ps.length; i++) deliver(this, { cmd: ps[i].cmd, data: ps[i].data });
        };

        // broadcast time-driven pushes (clover regrowth, frog depart/return)
        setInterval(function () {
            if (!activeSock) return;
            var pushes;
            try { pushes = engine.tick(); } catch (e) {
                push('[offlineB-error]', ['tick: ' + (e && e.stack || e)]);
                return;
            }
            for (var i = 0; i < (pushes || []).length; i++) {
                push('[offlineB]', ['push ' + pushes[i].cmd]);
                deliver(activeSock, { cmd: pushes[i].cmd, data: pushes[i].data });
            }
        }, 5000);

        return true;
    }

    global_exposeLoopback(installLoopback);

    function global_exposeLoopback(fn) {
        window.__installLoopback = fn;
    }

    /* ------------------------------------------------- 3. lifecycle kick */
    var kicks = 0;

    function kick() {
        try {
            var G = window.GameConfig || (window.core && core.GameConfig) || null;
            var D = (window.core && core.ControllerDispatcher) ? core.ControllerDispatcher : null;
            if (G && G.activate !== true) {
                G.activate = true;
                push('[shell]', ['GameConfig.activate = true']);
            }
            if (D && core.Event) {
                D.getInstance().dispatchEvent(new core.Event(core.EventType.resume));
            }
        } catch (e) { /* core not ready yet */ }
    }

    function installHooks() {
        if (hooked || !window.core) return false;
        var pg = core.PageManage && core.PageManage.getInstance ? core.PageManage.getInstance() : null;
        if (!pg || !pg.addViewControl) return false;
        hooked = true;

        if (window.Music && Music.play) {
            var op = Music.play;
            Music.play = function () {
                /* The rights notice is up until the player taps 我已阅读，进入游戏.
                   Stay silent until then: the game boots behind the overlay (so
                   entering is instant), and playing the courtyard theme over a
                   legal notice would be both odd and, on a phone, noise the player
                   did not ask for. Once dismissed this wrapper is transparent. */
                if (!window.__noticeDismissed) return undefined;
                try { return op.apply(this, arguments); }
                catch (e) { push('[music-error]', [String(e && e.stack || e)]); }
            };
        }

        // Track the view stack so we can see what is actually on screen.
        window.__views = [];
        var oAdd = pg.addViewControl, oRem = pg.removeControl;
        pg.addViewControl = function (cls, layer) {
            var id = String(cls);
            window.__views.push({ op: 'add', fp: fp(cls), layer: layer, t: Date.now() });
            var r;
            /* The album's 地图 button opens the client's TravelMapController, which is
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
            /* A WindowController builds its skin FIRST and fills it in open(), so a throw
               during the fill leaves the skin on screen with nothing drawn -- the player
               sees a black window whose only working control is the close X. That is a
               whole class of dead end (it is how the visitor view behaves when it is
               opened with no visitor: VisitorView.open does
               `getAchieveInfo(data.title).name` and `getVisitorInfo(province).DisplayName`).
               So: if opening throws, undo the half-open view and say so, naming the skin
               (which is also the fastest way for a bug report to identify the view). */
            try {
                r = oAdd.apply(this, arguments);
            } catch (e) {
                var skin = '';
                try { skin = skinOf(cls); } catch (e2) { skin = ''; }
                /* skinOf() reads `cls.constructor`'s source; for a CLASS that is Function
                   itself, so it yields "function Function() { [native code] }" -- a label
                   that tells nobody anything. Fall back to the name __reflect put on the
                   prototype. */
                if (!skin || skin.indexOf('[native code]') >= 0) {
                    try {
                        skin = (cls && cls.prototype && cls.prototype.__class__) || '';
                    } catch (e5) { skin = ''; }
                }
                if (!skin) skin = '未知界面';
                push('[view-failed]', [skin + ' :: ' + String(e && e.stack || e)]);
                try { pg.removeControl(cls, layer); } catch (e3) { /* nothing to undo */ }
                try {
                    GuideHelpView.getInstance().show(
                        '这个界面暂时打不开' + (skin ? '（' + skin + '）' : '') +
                        '\n已为你返回，请把这句话告诉我',
                        null, core.DisplayManage.getInstance().getNoticeLayer());
                } catch (e4) { /* the toast is best-effort */ }
                return null;
            }
            try { scheduleCalendarFix(cls); } catch (e) { }
            try { scheduleCreditsFix(cls); } catch (e) { }
            try { scheduleAnnualFix(cls); } catch (e) { }
            try { installOfflinePay(); } catch (e) { }
            try { installOfflineChannel(); } catch (e) { }
        try { installOfflineAds(); } catch (e) { }
            return r;
        };
        pg.removeControl = function (cls) {
            window.__views.push({ op: 'remove', fp: fp(cls), t: Date.now() });
            return oRem.apply(this, arguments);
        };
        push('[shell]', ['hooks installed']);
        return true;
    }

    /* --------------------------------------------- 4. scene scroll fix */
    /* The garden view's `scroller.viewport.scrollH` initialises to a negative
       value (observed -706 in this environment). The content is 1152 wide in a
       ~626 viewport, so a negative offset shifts the entire courtyard off to the
       right and the scene renders blank white. A negative scroll is never valid,
       so clamp it and reset the already-applied layout. */
    var scrollFixed = false;

    function fixSceneScroll() {
        if (scrollFixed) return;
        var view = findMainOutView();
        if (!view || !view.scroller || !view.scroller.viewport) return;
        var vp = view.scroller.viewport;
        try {
            var pd = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(vp), 'scrollH');
            if (!pd || !pd.get || !pd.set) return;
            Object.defineProperty(vp, 'scrollH', {
                configurable: true,
                enumerable: true,
                get: function () {
                    var v = pd.get.call(this);
                    return (typeof v === 'number' && v < 0) ? 0 : v;
                },
                set: function (v) {
                    return pd.set.call(this, (typeof v === 'number' && v < 0) ? 0 : v);
                },
            });
            var was = pd.get.call(vp);
            pd.set.call(vp, 0);
            scrollFixed = true;
            push('[shell]', ['scene scrollH clamped: was ' + was + ', now ' + pd.get.call(vp)]);
        } catch (e) {
            push('[shell-error]', ['scroll fix: ' + (e && e.stack || e)]);
        }
    }

    /* ------------------------------------- 4c. calendar: real dates, not 2023 art */
    /* The month pages (resource/China/images/Scene/Calendar/calendar_N.png) are
       PRE-RENDERED 2023 calendars: the day numbers, the lunar dates, the zodiac
       ("癸卯兔年") and the year ("2023") are all pixels in the bitmap. The client,
       however, lays the today-ring and the daily-reward icons out from the REAL
       current month (CalendarModel.getMonthFirstWeek / getMonthMaxDay), so on any
       date outside 2023 the icons sit on the wrong printed day -- on 2026-09-11 the
       marker landed on the cell printed "1". No server-side data can reconcile a
       2023 bitmap with a 2026 grid, so the page is redrawn here using the SAME
       formula the overlay uses, which guarantees the two agree.
       Colours were sampled from the original art: #565f4e digits, #a4a696 for
       adjacent-month digits, white paper. The lunar dates and solar terms are
       NOT reproduced -- the shipped ones were 2023-only, and inventing them for
       other years would be a fabrication we cannot verify. */
    var CAL_INK = 0x565f4e;
    var CAL_FAINT = 0xa4a696;
    var CAL_CELL_W = 73;
    var CAL_CELL_H = 65;
    var CAL_WEEK = ['一', '二', '三', '四', '五', '六', '日'];

    function calLabel(parent, str, x, y, w, h, size, color, align, stroke) {
        var t = new egret.TextField();
        t.text = str;
        t.size = size;
        t.bold = true;
        t.textColor = color;
        if (stroke) {
            t.stroke = stroke;
            t.strokeColor = 0xffffff;
        }
        t.textAlign = align || egret.HorizontalAlign.CENTER;
        t.verticalAlign = egret.VerticalAlign.MIDDLE;
        t.width = w;
        t.height = h;
        t.x = x;
        t.y = y;
        parent.addChild(t);
        return t;
    }

    function rebuildCalendar() {
        var view = null;
        try { view = findNodeIn('CalendarSkin.exml'); } catch (e) { }
        if (!view) return false;

        var pic = view.imagePic, grid = view.groupDay, reward = view.groupReward;
        if (!grid || !reward || !grid.parent) return false;

        /* `pic` is only needed to size the white paper, and it is an eui.Image whose
           size stays 0 until the month texture has loaded. Requiring it BEFORE
           drawing anything was a real trap: on a slow load the whole redraw was
           skipped, so the player kept the baked 2023 page with the game's ring and
           reward icons laid over it -- which reads as "the dates and the weekdays
           don't line up" and "only 28 icons". So: draw the numbers and the header
           as soon as the grid exists, and fall back to the art's known size (the
           page is 553x648) for the paper. */
        var pageW = (pic && pic.width > 0) ? pic.width : 553;
        var pageH = (pic && pic.height > 0) ? pic.height : 648;
        var pageX = (pic && pic.parent) ? pic.x : 0;
        var pageY = (pic && pic.parent) ? pic.y : 0;

        var cm = core.ModelManage.getInstance().getModel(CalendarModel);
        var when = new Date(core.Time.getServerTime() * 1000);
        var year = when.getFullYear();
        var month = when.getMonth() + 1;
        var today = when.getDate();
        var firstWeek = cm.getMonthFirstWeek();          // 1 = Monday
        var maxDay = cm.getMonthMaxDay();

        if (view.__offlineCalMonth === month && view.__offlineCalText &&
            view.__offlineCalText.parent) return true;    // already correct

        /* A cached view can be reopened, so clear anything a previous pass left. */
        if (view.__offlineCalText && view.__offlineCalText.parent) {
            view.__offlineCalText.parent.removeChild(view.__offlineCalText);
        }
        if (view.__offlineCalPaper && view.__offlineCalPaper.parent) {
            view.__offlineCalPaper.parent.removeChild(view.__offlineCalPaper);
        }

        /* Z-ORDER, read off the live display list (paint order = child index):
             0 cover (full-screen touch layer)
             1 wrapper group holding imagePic   <- the page
             2 groupReward  (daily-reward icons + imageToday ring)
             3 groupDay     (42 calendar_mask_future_png cells that dim FUTURE days)
           The numbers go at the TOP of groupDay, i.e. above the page, above the
           reward icons and above the future-day masks. That deliberately differs
           from the original, where a 60x60 reward icon sits over a 73x65 cell and
           hides the printed number for almost every day -- which makes the date
           impossible to read. A white stroke keeps the digits legible on top of
           the icon art. */
        var wrap = pic && pic.parent;
        if (wrap) {
            var paper = new egret.Shape();
            paper.graphics.beginFill(0xffffff);      // the original page is plain white
            paper.graphics.drawRect(pageX, pageY, pageW, pageH);
            paper.graphics.endFill();
            wrap.addChildAt(paper, wrap.getChildIndex(pic));
            pic.visible = false;
            view.__offlineCalPaper = paper;
        }

        /* groupDay and groupReward sit at the SAME x/y/size, so their local
           coordinate spaces are identical -- numbers placed here line up with the
           ring and the icons exactly, with no coordinate conversion at all.
           (Conversion is not an option: a WindowView is scaled while it animates,
           and routing one point through globalToLocal once returned (306,568)
           for a true (30,244).) */
        var texts = new egret.Sprite();
        texts.name = 'offlineCalendarText';
        grid.addChild(texts);

        /* header above the grid, taking the original's 九月 / 癸卯兔年 slots */
        calLabel(texts, month + '月', 0, -104, 160, 44, 34, CAL_INK);
        calLabel(texts, year + '年', grid.width - 170, -100, 160, 38, 28, CAL_INK);

        for (var c = 0; c < 7; c++) {
            calLabel(texts, CAL_WEEK[c], c * CAL_CELL_W, -46, CAL_CELL_W, 40, 26, CAL_FAINT);
        }

        /* Day numbers, by the client's own formula: day 1 occupies column
           (firstWeek-1) of row 0, each cell 73x65. Pinned to the cell's
           top-left so the reward icon in the middle stays visible. */
        var lead = firstWeek - 1;
        var prevMax = new Date(year, month - 1, 0).getDate();
        var nextDay = 1;
        for (var e = 0; e < 42; e++) {
            var day = e - lead + 1;
            var text;
            var color = CAL_INK;
            if (day < 1) {
                text = String(prevMax + day);     // trailing days of the previous month
                color = CAL_FAINT;
            } else if (day > maxDay) {
                text = String(nextDay++);         // leading days of the next month
                color = CAL_FAINT;
            } else {
                text = String(day);
            }
            calLabel(texts, text,
                (e % 7) * CAL_CELL_W + 5,
                Math.floor(e / 7) * CAL_CELL_H + 1,
                44, 30, 26, color, egret.HorizontalAlign.LEFT, 3);
        }

        view.__offlineCalText = texts;
        view.__offlineCalMonth = month;
        push('[calendar]', ['redrawn ' + year + '-' + month + '-' + today +
            ' firstWeek=' + firstWeek + ' maxDay=' + maxDay +
            ' page=' + pageX + ',' + pageY + ' ' + pageW + 'x' + pageH +
            (pic && pic.width > 0 ? '' : ' (art size unknown, used fallback)') +
            ' grid=' + grid.x + ',' + grid.y + ' ' + grid.width + 'x' + grid.height]);
        return true;
    }

    /* The controller is created and then its skin is built over the next frames,
       so poll briefly instead of guessing a single delay.
       NOTE: identify the class by IDENTITY, not by name. `String(cls)` on a
       minified class is "function e(t){...}" -- the original name is gone, which
       is exactly how the first version of this hook silently never fired. */
    function scheduleCalendarFix(cls) {
        if (!window.CalendarViewControl || cls !== window.CalendarViewControl) return;
        var tries = 0;
        var t = setInterval(function () {
            tries++;
            var done = false;
            try { done = rebuildCalendar(); } catch (e) {
                push('[calendar-error]', [String(e && e.stack || e)]);
                clearInterval(t);
                return;
            }
            if (done || tries > 60) clearInterval(t);
        }, 100);
    }
    /* exposed so a CDP session can run the same repair on demand */
    window.__rebuildCalendar = rebuildCalendar;

    /* ------------------------------------- 4d. 充值 without a payment channel */
    /* BaseChannel.prototype.pay() is `function (e) {}` -- an empty stub. The real
       channels override it with the store SDK (ft_sdk.pay(...)), but the channel
       this build runs as is ChannelType.Test, so tapping any 充值 pack called a
       no-op and the button looked dead.
       There is no store offline and nothing can be charged, so rather than show a
       button that silently does nothing, the tap is routed to the engine's
       recharge_ready_pay -- the client's own "this pack was paid, deliver it"
       command (declared in ProtocolList, unused in this build because the SDK
       integration is gone). The engine grants the pack and pushes the same
       TimerEvent.Type.Recharge the live server sent after a verified payment.
       This is NOT a simulated payment: it is a free grant, and the toast says so. */
    function offlineRecharge(shopID) {
        let db = null;
        try { db = Tabikaeru.DataManager.instance().rechargeDB; } catch (e) { return false; }
        if (!db) return false;
        let packId = 0;
        for (let i = 1; i <= 64 && !packId; i++) {
            let row = null;
            try { row = db.get(i); } catch (e) { row = null; }
            if (!row) continue;
            if (String(row.shopID) === String(shopID) || String(row.shopID_iOS) === String(shopID)) {
                packId = row.id;
            }
        }
        if (!packId) return false;
        core.SocketManage.getInstance().send('recharge_ready_pay',
            new core.Action2(function (r) {
                push('[pay]', ['recharge_ready_pay ' + packId + ' -> ' + JSON.stringify(r)]);
                if (r && r.code === 0) {
                    GuideHelpView.getInstance().show(
                        '离线版没有付费渠道：' + packId + ' 号礼包已直接发放',
                        function () { Music.play('SE_Enter'); },
                        core.DisplayManage.getInstance().getNoticeLayer());
                }
            }), packId);
        return true;
    }

    function installOfflinePay() {
        if (!window.BaseChannel || !BaseChannel.prototype) return false;
        if (BaseChannel.prototype.__offlinePayInstalled) return true;
        var orig = BaseChannel.prototype.pay;
        BaseChannel.prototype.pay = function (shopID) {
            var handled = false;
            try {
                handled = offlineRecharge(shopID);
            } catch (e) {
                push('[pay-error]', [String(e && e.stack || e)]);
            }
            if (handled) return undefined;
            return orig.apply(this, arguments);
        };
        BaseChannel.prototype.__offlinePayInstalled = true;
        push('[shell]', ['offline pay installed: 充值 packs are granted free']);
        return true;
    }

    /* ------------------------------- 4e. annual review: the year is baked art */
    /* AnnualReviewStartPageSkin draws `summary_page1_1_png` at (52,149): a card
       whose top line is "2022" and which is PIXELS in the bitmap -- nothing the
       server sends can change it -- so on any other year the review opens with a
       heading that is simply wrong. Same problem as the calendar month pages.
       The original is a dark olive field (#545d4c, the card's dominant colour)
       with white-haloed text and sharp corners. Rather than try to repaint a
       composite I cannot reproduce exactly, the card is hidden and redrawn in the
       same palette with the player's own year -- rounded corners so it reads as a
       deliberate card. The subtitle 旅行日记 is year-neutral and kept.
       Also hides the FinishPage share button: it opens the WeChat share selector,
       which cannot work offline, and annual_load reports is_share=true so there is
       nothing left to claim behind it. */
    var SUMMARY_ART = 'summary_page1_1_png';
    var SUMMARY_BG = 0x545d4c;
    var SUMMARY_FG = 0xffffff;

    function rebuildAnnualReview() {
        var view = null;
        try { view = findNodeIn('AnnualReviewSkin.exml'); } catch (e) { }
        if (!view) return false;
        if (view.__offlineAnnualDone) return true;

        var card = null;
        (function walk(n, d) {
            if (d > 12 || !n) return;
            for (var i = 0; i < (n.$children || []).length; i++) {
                var c = n.$children[i];
                if (c.source === SUMMARY_ART) card = c;
                walk(c, d + 1);
            }
        })(view, 0);
        if (!card || !card.parent) return false;      // page not built yet, retry

        var year = new Date(core.Time.getServerTime() * 1000).getFullYear();
        var w = card.width, h = card.height;

        var panel = new egret.Sprite();
        panel.name = 'offlineAnnualYear';
        var bg = new egret.Shape();
        bg.graphics.beginFill(SUMMARY_BG);
        bg.graphics.drawRoundRect(card.x, card.y, w, h, 14, 14);
        bg.graphics.endFill();
        panel.addChild(bg);
        annualLabel(panel, String(year), card.x, card.y + h * 0.10, w, h * 0.52, Math.round(h * 0.40), SUMMARY_FG);
        annualLabel(panel, '旅行日记', card.x, card.y + h * 0.62, w, h * 0.30, Math.round(h * 0.20), SUMMARY_FG);
        card.parent.addChildAt(panel, card.parent.getChildIndex(card));
        card.visible = false;

        var shareHidden = false;
        (function walk2(n, d) {
            if (d > 14 || !n) return;
            for (var i = 0; i < (n.$children || []).length; i++) {
                var c = n.$children[i];
                if (c.source === 'year_summary_share_png') {
                    var t = c;
                    for (var k = 0; k < 4 && t && !t.touchEnabled; k++) t = t.parent;
                    if (t && t !== view) { t.visible = false; t.touchEnabled = false; shareHidden = true; }
                }
                walk2(c, d + 1);
            }
        })(view, 0);

        view.__offlineAnnualDone = true;
        push('[annual]', ['year card redrawn as ' + year + ' ' + Math.round(w) + 'x' + Math.round(h) +
            (shareHidden ? '; share button hidden' : '')]);
        return true;
    }

    function annualLabel(parent, str, x, y, w, h, size, color) {
        var t = new egret.TextField();
        t.text = str;
        t.size = size;
        t.bold = true;
        t.textColor = color;
        t.textAlign = egret.HorizontalAlign.CENTER;
        t.verticalAlign = egret.VerticalAlign.MIDDLE;
        t.width = w;
        t.height = h;
        t.x = x;
        t.y = y;
        parent.addChild(t);
        return t;
    }

    /* Exposed so a probe can run the repair without waiting for a tap. */
    window.__rebuildAnnualReview = rebuildAnnualReview;

    function scheduleAnnualFix(cls) {
        if (!window.AnnualReviewViewControl || cls !== window.AnnualReviewViewControl) return;
        var tries = 0;
        var t = setInterval(function () {
            tries++;
            var done = false;
            try { done = rebuildAnnualReview(); } catch (e) {
                push('[annual-error]', [String(e && e.stack || e)]);
                clearInterval(t);
                return;
            }
            if (done || tries > 40) clearInterval(t);
        }, 100);
    }

    /* ------------------------------------- 4f. 帮助菜单里三个走渠道桥接的按钮 */
    /* Help.totalTouchEvents routes three buttons through BaseChannel, and
       TestChannel (the channel this build actually runs as) does NOT override them,
       so they hit BaseChannel's empty stubs and did nothing at all -- which is why
       the player reported 协议 / 联系客服 / 退出游戏 as dead. Verified by reading
       Help's handler:
          btn_agree    -> BaseChannel.openAgreement()
          btn_privacy  -> BaseChannel.openPrivacy()      (hidden unless remoteArgs)
          btn_customer -> BaseChannel.open_custom_service().then()
          btn_exit     -> BaseChannel.logout()
          btn_copyright-> CopyrightViewController        (works, local content)
          btn_cdkey    -> CdkeyViewController            (works, local table codes)
       The content for all of these IS in the package, so they are wired to it
       instead of being removed:
          * 协议: USER_ARGEEMENT_CONTENT_1..3 (~38KB of HTML in main.min.js) shown by
            UserAgreementView, in its read-only "review" state.
          * 联系客服: Menu/Customer.exml is an information panel whose label is the
            developer's own static text (官方微博「旅行青蛙·中国之旅」 + 官方Q群
            1051431084), which is exactly what an offline build can offer.
          * 退出游戏: the wrapper exposes FrogNative.exitApp(); on PC the closest
            equivalent is closing the tab, and if the browser refuses (a tab the
            script did not open) the player is told to close it. */
    /* the offline replacement for the operator's hosted 地图 page (see openMapOverlay) */
    var MAP_PAGE = 'map.html';

    function installOfflineChannel() {
        if (!window.BaseChannel || !BaseChannel.prototype) return false;
        if (BaseChannel.prototype.__offlineChannelInstalled) return true;
        var P = BaseChannel.prototype;

        P.openAgreement = function () {
            try {
                core.PageManage.getInstance().addViewControl(
                    UserAgreementViewControl, core.ViewLayerType.NoticeLayer, null,
                    { review: true });
                return Promise.resolve();
            } catch (e) {
                push('[agreement-error]', [String(e && e.stack || e)]);
                return Promise.resolve();
            }
        };
        P.openPrivacy = P.openAgreement;

        /* ---- 帮助菜单里的「制作人员」-----------------------------------------------
           The client's Help view (skin Menu/Help.exml) has a `btn_customer` whose tap goes
           through BaseChannel.open_custom_service(). The original shipped the operator's
           own contact panel (Menu/Customer.exml: 官方微博 / 官方Q群), which is meaningless
           offline, and the button label itself lives inside the client's encrypted config
           bundle -- so the label is rewritten AT RUNTIME (see relabelHelpButton) and the
           content is this overlay. */
        var CREDITS_TITLE = '制作人员';
        var CREDITS_GROUP = '旅行青蛙离线版制作组';
        var CREDITS_NAMES = ['Balticx', '兔子国国王', '西瓜给我咬一口', 'yxcatqwq'];

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
                    /* The shipped button is an eui.Image whose label is baked into
                       button_02_png, so the visible name comes from that texture (see
                       tools/patch_help_button.py). Only a REAL eui.Button can be relabelled
                       at runtime -- check before writing, so this never pretends. */
                    try {
                        if (b.labelDisplay) {
                            if (b.labelDisplay.text !== CREDITS_TITLE) {
                                b.labelDisplay.text = CREDITS_TITLE;
                            }
                            if (b.label !== CREDITS_TITLE) {
                                b.label = CREDITS_TITLE;
                            }
                            hits++;
                        } else if (b.source === 'button_02_png') {
                            hits++;      /* label is in the texture; nothing to do here */
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

        /* The Help panel is a SINGLETON added straight to the popup layer
           (`Help.getInstance()` + getPopupLayer().addChild(...)), so it never goes through
           addViewControl and the view-open poll above cannot see it. Hook the two places
           where it actually appears. */
        function hookCreditsTargets() {
            var hooked = 0;
            try {
                var H = window.Help;
                if (H && H.prototype && H.prototype.show && !H.prototype.__creditsHooked) {
                    var oShow = H.prototype.show;
                    H.prototype.show = function () {
                        var r = oShow.apply(this, arguments);
                        try { relabelHelpButton(); } catch (e) { }
                        return r;
                    };
                    H.prototype.__creditsHooked = true;
                    hooked++;
                }
            } catch (e) { push('[credits-error]', ['Help.show hook: ' + (e && e.message)]); }
            try {
                var layer = core.DisplayManage.getInstance().getPopupLayer();
                if (layer && !layer.__creditsHooked) {
                    var oAdd = layer.addChild;
                    layer.addChild = function (child) {
                        var r = oAdd.apply(this, arguments);
                        try {
                            if (child && child.btn_customer) scheduleCreditsFix(null);
                        } catch (e) { }
                        return r;
                    };
                    layer.__creditsHooked = true;
                    hooked++;
                }
            } catch (e) { push('[credits-error]', ['popup hook: ' + (e && e.message)]); }
            return hooked;
        }
        window.__hookCreditsTargets = hookCreditsTargets;

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
        };

        P.logout = function () {
            push('[exit]', ['logout() -> exiting the game']);
            try {
                if (window.FrogNative && FrogNative.exitApp) { FrogNative.exitApp(); return; }
            } catch (e) { push('[exit-error]', [String(e && e.message)]); }
            try { window.close(); } catch (e) { /* browsers may refuse */ }
            /* If the tab is still here a moment later, the browser refused (it only
               closes windows the script opened), so say so instead of doing nothing. */
            setTimeout(function () {
                if (document.hidden) return;
                try {
                    GuideHelpView.getInstance().show('已退出游戏，请直接关闭本页面（或窗口）。',
                        null, core.DisplayManage.getInstance().getNoticeLayer());
                } catch (e) { /* ignore */ }
            }, 400);
        };

        var oGetAnnInfo = P.getAnnInfo;

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

        /* the Help panel can appear at any time later, so both hooks are installed now */
        try { hookCreditsTargets(); } catch (e) { }

        P.__offlineChannelInstalled = true;
        push('[shell]', ['offline channel installed: 协议 / 联系客服 / 退出游戏 are wired up']);
        return true;
    }

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
        /* Say whose page this is: the original button opened an operator-hosted map,
           this one is ours, and a player comparing the two should be told up front. */
        title.textContent = '足迹地图（离线版自制）';
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

    /* ------------------------------------------- 8. no ads offline: the video poster
       The garden has a notice poster (`adsNoticeBtn`) on the wall between the workbench
       and the house door. Its handler opens a video player when the channel is
       ChannelType.Test -- which is exactly how this build runs:

           on_adsNoticeBtn_tap() {
             if (GameConfig.channel == ChannelType.Test)
               return void getNoticeLayer().addChild(new AdsVideoView);
             ...
           }

       AdsVideoView loads resource/China/video/test.mp4 and closes ONLY when the video
       ENDS (or via its own close button). Offline there is nothing to advertise and
       autoplay/decode is not reliable, so the player sits on a black screen with nothing
       on it -- and because nothing throws, the view-failure guard above cannot help.

       So the player is not opened at all. Instead we take the branch the client itself
       takes when the video ends -- `AdsModel.req_share(1)`, i.e. adsmgr_share{ads_type:1},
       which the engine already answers by mailing the daily gift -- and say why. */
    function installOfflineAds() {
        if (!window.core || !core.DisplayManage) return false;
        var dm = core.DisplayManage.getInstance();
        if (!dm || !dm.getNoticeLayer) return false;
        var layer = null;
        try { layer = dm.getNoticeLayer(); } catch (e) { return false; }
        if (!layer || layer.__adsPatched) return false;
        var oAdd = layer.addChild;
        layer.addChild = function (child) {
            var cls = '';
            try { cls = String(child && child.__class__ || ''); } catch (e) { cls = ''; }
            if (cls === 'AdsVideoView') {
                push('[ads]', ['ad video poster tapped; granting the daily gift instead']);
                try {
                    core.SocketManage.getInstance().send('adsmgr_share',
                        new core.Action2(function (r) {
                            var okCode = r && r.code === 0;
                            try {
                                GuideHelpView.getInstance().show(
                                    okCode
                                        ? '离线版没有广告，不用看视频\n今日奖励已发到邮箱'
                                        : '离线版没有广告，这个按钮不消耗任何东西',
                                    null, core.DisplayManage.getInstance().getNoticeLayer());
                            } catch (e2) { /* best effort */ }
                        }), 1);
                } catch (e3) {
                    push('[ads]', ['adsmgr_share failed: ' + String(e3)]);
                }
                return child;                    // deliberately NOT added
            }
            return oAdd.apply(this, arguments);
        };
        layer.__adsPatched = true;
        push('[shell]', ['offline ads guard installed']);
        return true;
    }

    /* ------------------------------------- 5. diagnostics (opt-in) */
    installDiagnostics();

    /* --------------------------- 6. save export / import (small DOM overlay) */
    /* The frog must survive clearing browser storage, so give players a way to
       pull the save out and put it back. Route B keeps it in localStorage; Route
       A keeps it in the server's save.json, so the endpoints differ. */
    function installSaveTools() {
        if (document.getElementById('__save_ball')) return;

        /* A round button in the game's own palette (the parchment tones the client uses
           for its dialogs: #f6f2e6 paper, #b9ad8d border, #4a4433 ink) instead of the
           debug red square the GM flag used to draw. Left middle, where that square was.

           It is anchored to the CANVAS, not to the window: on a phone the canvas fills
           the screen so the two are the same, but on a desktop window the game is
           letterboxed and a window-anchored ball ends up in the white margin, far from
           the picture -- which reads as "the ball is missing on PC". placeBall() below
           keeps it just inside the game's left edge at any window shape. */
        var PAPER = '#f6f2e6', EDGE = '#b9ad8d', INK = '#4a4433', LEAF = '#7ba05b';
        var BALL_INSET = 8;      /* px from the canvas edge */
        var PANEL_GAP = 70;      /* ball width (60) + 10 */

        var ball = document.createElement('div');
        ball.id = '__save_ball';
        ball.title = '存档编辑';
        ball.style.cssText = [
            /* left/top are set in px by the drag code below */
            'position:fixed', 'left:8px', 'top:200px',
            'width:60px', 'height:60px', 'border-radius:50%', 'z-index:99998',
            'background:radial-gradient(circle at 32% 28%, #fbf8ee 0%, ' + PAPER + ' 55%, #e6dfc9 100%)',
            'border:3px solid ' + LEAF,
            'box-shadow:0 3px 8px rgba(60,50,30,.35), inset 0 0 0 2px rgba(255,255,255,.6)',
            'cursor:pointer', 'user-select:none', '-webkit-user-select:none',
            'display:flex', 'align-items:center', 'justify-content:center',
            'flex-direction:column', 'line-height:1.05',
            'font-family:"PingFang SC","Microsoft YaHei","Heiti SC",sans-serif',
            'color:' + INK, 'font-size:15px', 'font-weight:600',
            /* none, not manipulation: a drag must not scroll the page under the ball */
            'touch-action:none', 'transition:transform .12s',
        ].join(';');
        ball.innerHTML = '<span>存档</span><span style="font-size:10px;font-weight:400">编辑</span>';
        ball.title = '点一下打开 / 按住可以拖到任意位置（位置会记住）';

        /* ---- the panel ---- */
        var panel = document.createElement('div');
        panel.id = '__save_panel';
        panel.style.cssText = [
            'position:fixed', 'left:78px', 'top:120px',
            'width:214px', 'z-index:99999', 'display:none',
            /* a phone held upright is short: scroll instead of running off the screen */
            'max-height:88vh', 'overflow-y:auto', 'box-sizing:border-box',
            'background:' + PAPER, 'border:2px solid ' + EDGE, 'border-radius:10px',
            'box-shadow:0 6px 18px rgba(60,50,30,.4)', 'padding:10px',
            'font-family:"PingFang SC","Microsoft YaHei","Heiti SC",sans-serif',
            'color:' + INK,
        ].join(';');

        var BUILD_STAMP = '2026-09-15 18:32';

        var title = document.createElement('div');
        title.textContent = '存档编辑';
        title.style.cssText = 'font-size:15px;font-weight:700;text-align:center;'
            + 'padding-bottom:6px;margin-bottom:8px;border-bottom:1px solid ' + EDGE;
        panel.appendChild(title);

        var msg = document.createElement('div');
        msg.style.cssText = 'font-size:12px;line-height:1.5;min-height:16px;'
            + 'margin-top:8px;word-break:break-all;color:#6b6553';
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

        function row(labels, handlers, size) {
            var line = document.createElement('div');
            line.style.cssText = 'display:flex;gap:6px;margin-bottom:6px';
            for (var i = 0; i < labels.length; i++) {
                var b = document.createElement('button');
                b.textContent = labels[i];
                b.style.cssText = [
                    'flex:1', 'padding:7px 4px', 'cursor:pointer',
                    'font-size:' + (size || 13) + 'px',
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

        /* Two editor actions are common enough to deserve their own button rather than
           being typed into the console: the 大冒险 event is OFF in this build (the
           engine's MUSEUM_DAY_ENABLED), so its museum 图鉴 was replaced by "unlock them
           outright", and the furniture list is 294 rows. Both are ordinary engine
           commands (unlock_all / all_furniture) and are also listed in the 指令台 help,
           so the console route still works. */
        row(['解锁图鉴+百科', '获得全部家具'], [
            function () { gm('unlock_all'); },
            function () { gm('all_furniture'); },
        ], 11);

        row(['解锁全部明信片', '解锁博物馆图鉴'], [
            function () { gm('unlock_pictures'); },
            function () { gm('unlock_museum'); },
        ]);

        /* 相册容量是「30 页 + 已拥有的相册扩容」x 每页 6 张：客户端的扩容提示读的正是
           你拥有多少个 9000（"保留照片的页数+N"）。商店那条链一共 35 个，所以满扩容 =
           65 页 / 390 张 —— 一次「解锁全部明信片」放进来 351 张之后，不扩容的话相册就
           一直是"满"的，之后旅行带回的照片会被代码 75 直接丢掉。 */
        row(['扩容相册到上限', '相册用量'], [
            function () { gm('expand_album'); },
            function () { gm('album_state'); },
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
        panel.appendChild(nameLine);

        function usingLocalEngine() {
            return !!window.FrogEngine && !!window.__installLoopback && window.__loopbackActive;
        }

        /* 存档安全状态：把引擎自报的存档健康度摊开给玩家看。旧代码的毛病不是
           "会丢"，而是"丢了不说" —— 所以这里必须能一眼看到写在哪儿、有没有备份、
           有没有写失败。只读，不改状态。 */
        row(['存档状态'], [
            function () {
                var e = window.__engine;
                if (!e || typeof e.saveInfo !== 'function') {
                    note('当前不是本地引擎模式（Route A：由本地服务器存档），'
                        + '存档文件在 dist 目录下的 save 文件夹里。');
                    return;
                }
                var info = e.saveInfo();
                var r = info.report || {};
                var lines = [
                    '主档：' + info.path,
                    '备份：' + info.backup,
                    '暂存：' + info.pending,
                    '损坏归档：' + ((info.corrupt && info.corrupt.length)
                        ? info.corrupt.join('、') : '（无）'),
                    '本次启动：' + (r.action || '?')
                        + (r.restoredFrom ? ('（来源 ' + r.restoredFrom + '）') : ''),
                    '写入：' + (r.saves || 0) + ' 次成功，' + (r.failCount || 0) + ' 次失败',
                ];
                if (r.lastError) lines.push('最近错误：' + r.lastError);
                if (r.protectMain) lines.push('已停止写入：坏档无法归档，避免覆盖唯一副本');
                if (r.blocked) lines.push('已停止写入：存档来自更新版本');
                note(lines.join('\n'));
            },
        ]);

        /* ---- where an exported save actually goes -----------------------------------
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
            note('存档已导出到：' + where + '\n（要用的时候，点「导入存档」把它选回来）');
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
                note('已导出 ' + a.download + '\n（在你浏览器的下载目录里）');
            } catch (e) {
                /* A WebView that blocks blob downloads still has the text: show it so the
                   player can copy it out rather than losing the save. */
                note('浏览器不允许直接下载，请长按复制下面的存档：\n' + String(text).slice(0, 400) + '…');
            }
        }

        row(['导出存档', '导入存档'], [
            function () {
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
                            note('已打开系统的「保存到」窗口：\n选好文件夹 → 保存。文件名 ' + name
                                + '\n保存完成后这里会告诉你具体位置。');
                        } else if (where) {
                            note('存档已导出到：' + where
                                + '\n（要用的时候，点「导入存档」把它选回来）');
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

        row(['重载界面', '指令台（高级）'], [
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
        ]);

        var stampLine = document.createElement('div');
        stampLine.textContent = '版本 ' + BUILD_STAMP;
        stampLine.title = '这一份的文件时间；比对我的改动时间就知道是不是最新的一份';
        stampLine.style.cssText = 'font-size:10px;color:#a79c81;text-align:center;margin-top:6px';
        panel.appendChild(stampLine);

        var hint = document.createElement('div');
        hint.textContent = '这些按钮立刻生效，不用重启。点一下圆球打开面板，按住可以拖动它。'
            + '立刻出门需要背包里有东西，空手时蛙蛙会在家等。';
        hint.style.cssText = 'font-size:11px;line-height:1.4;color:#8a8168;margin-top:2px';
        panel.appendChild(hint);

        ball.onclick = function () {
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
        };

        /* ---- where the ball sits, and dragging it ----
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

        document.body.appendChild(ball);
        document.body.appendChild(panel);
        push('[shell]', ['存档编辑 ball installed (showGM is off)']);
    }

    /* --------------------------------------------------- main watchdog */
    /* The kick is only needed to bootstrap: GameConfig.activate and the
       "resume" event are what the native SDK supplies. Repeating it forever is
       actively harmful - it keeps re-entering the game's event system, which
       replaces notification views mid-tap so taps never land. Stop once the
       scene is up. */
    var kickArmed = true;
    var kickTimer = setInterval(function () {
        if (!kickArmed) { clearInterval(kickTimer); return; }
        kicks++;
        if (kicks > 40) { clearInterval(kickTimer); return; }
        installHooks();
        // Route B: swap the transport for the in-page engine before login runs
        if (window.__installLoopback) window.__installLoopback();
        try { installOfflinePay(); } catch (e) { }
        try { installOfflineChannel(); } catch (e) { }
        try { installOfflineAds(); } catch (e) { }
        var scene = null;
        try { scene = findMainOutView(); } catch (e) { }
        if (scene) {
            // scene exists => entry succeeded; one last kick then stop
            kick();
            fixSceneScroll();
            kickArmed = false;
            clearInterval(kickTimer);
            push('[shell]', ['bootstrap complete - kicking stopped at ' + kicks + 's']);
            return;
        }
        kick();
        fixSceneScroll();
    }, 1000);

    /* run the first pass immediately */
    setTimeout(function () { installHooks(); kick(); installSaveTools(); }, 300);

    function installDiagnostics() {
        /* synthetic taps (headless has no pointer) */
        var tm = /[?&]tap=([^&]+)/.exec(Q);
        if (tm) {
            var pts = tm[1].split(',').map(Number);
            var delay = Number((/[?&]tapdelay=(\d+)/.exec(Q) || [])[1] || 12000);

            function reportEnv() {
                try {
                    var cvs = document.querySelectorAll('canvas');
                    var info = [];
                    for (var i = 0; i < cvs.length; i++) {
                        var c = cvs[i];
                        var r = c.getBoundingClientRect();
                        info.push('#' + i + ' ' + c.width + 'x' + c.height +
                            ' css ' + Math.round(r.width) + 'x' + Math.round(r.height) +
                            ' cls=' + (c.className || '-'));
                    }
                    push('[tap-env]', ['canvases=' + cvs.length + ' [' + info.join(' | ') + ']' +
                        ' isMobile=' + (window.egret && egret.Capabilities
                            ? egret.Capabilities.isMobile : '?') +
                        ' os=' + (window.egret && egret.Capabilities ? egret.Capabilities.os : '?') +
                        ' dpr=' + (window.devicePixelRatio || 1)]);
                } catch (e) { push('[tap-env-error]', [String(e)]); }
            }

            function tap(x, y) {
                var cvs = document.querySelectorAll('canvas');
                if (!cvs.length) { push('[tap]', ['no canvas']); return; }
                var sent = 0;
                for (var i = 0; i < cvs.length; i++) {
                    var c = cvs[i];
                    var r = c.getBoundingClientRect();
                    if (!r.width || !r.height) continue;
                    var sx = r.left + x * (r.width / (c.width / (window.devicePixelRatio || 1)));
                    var sy = r.top + y * (r.height / (c.height / (window.devicePixelRatio || 1)));
                    // mouse path (Egret uses this when not on a mobile UA).
                    // down+up are dispatched back-to-back in the SAME tick: Egret
                    // resolves TOUCH_TAP from $touchingObject bookkeeping, and a
                    // separate tick between them loses that state.
                    c.dispatchEvent(new MouseEvent('mousedown', {
                        bubbles: true, cancelable: true, view: window,
                        clientX: sx, clientY: sy, screenX: sx, screenY: sy, button: 0,
                    }));
                    c.dispatchEvent(new MouseEvent('mouseup', {
                        bubbles: true, cancelable: true, view: window,
                        clientX: sx, clientY: sy, screenX: sx, screenY: sy, button: 0,
                    }));
                    // touch path: opt-in via ?touch=1. Sending both mouse and touch
                    // events confuses Egret's gesture state (the extra touch point
                    // cancels the mouse-derived tap), so default to mouse only.
                    if (/[?&]touch=1/.test(Q)) {
                        try {
                            var touch = new Touch({
                                identifier: 1, target: c, clientX: sx, clientY: sy,
                                screenX: sx, screenY: sy, pageX: sx, pageY: sy,
                            });
                            c.dispatchEvent(new TouchEvent('touchstart', {
                                bubbles: true, cancelable: true, view: window,
                                touches: [touch], targetTouches: [touch], changedTouches: [touch],
                            }));
                            c.dispatchEvent(new TouchEvent('touchend', {
                                bubbles: true, cancelable: true, view: window,
                                touches: [], targetTouches: [], changedTouches: [touch],
                            }));
                        } catch (e) { /* Touch ctor unavailable */ }
                    }
                }
                push('[tap]', [x + ',' + y + ' dispatched to ' + cvs.length + ' canvas(es)']);
            }

            setTimeout(function () {
                reportEnv();
                for (var i = 0; i + 1 < pts.length; i += 2) {
                    (function (x, y, k) { setTimeout(function () { tap(x, y); }, k * 900); })(pts[i], pts[i + 1], i / 2);
                }
            }, delay);
        }

        /* display list + resource state */
        var dm = /[?&]dumptree=(\d+)/.exec(Q);
        if (dm) {
            setTimeout(function () {
                try {
                    var stage = egret.MainContext.instance.stage;
                    var lines = [];
                    (function walk(node, depth) {
                        if (depth > 9 || !node) return;
                        var kids = node.$children || [];
                        for (var i = 0; i < kids.length; i++) {
                            var c = kids[i];
                            lines.push('  '.repeat(depth) + fp(c.constructor).slice(0, 60) +
                                ' vis=' + c.visible + ' ' + Math.round(c.x) + ',' + Math.round(c.y) +
                                ' ' + Math.round(c.width) + 'x' + Math.round(c.height));
                            walk(c, depth + 1);
                        }
                    })(stage, 0);
                    push('[tree]', [lines.slice(0, 40).join('\n')]);

                    ['season11_courtyard1_json', 'season11_courtyard_png',
                        'mainout_season11_bg_png', 'season11_courtyard_atlas'].forEach(function (n) {
                        var has = (window.RES && RES.hasRes) ? RES.hasRes(n) : '?';
                        var got = '?';
                        try {
                            var v = RES.getRes(n);
                            got = (v === null || v === undefined) ? 'NULL'
                                : (typeof v) + (v && v.textureWidth ? ' ' + v.textureWidth + 'x' + v.textureHeight : '');
                        } catch (e) { got = 'THREW'; }
                        push('[res]', [n + ' has=' + has + ' get=' + got]);
                    });
                    var view = findMainOutView();
                    if (view && view.scroller && view.scroller.viewport) {
                        push('[scroll]', ['scrollH=' + view.scroller.viewport.scrollH]);
                    }
                    // what does the client actually believe its settings are?
                    try {
                        var UM = window.UserModel;
                        push('[settings]', ['window.UserModel=' + (typeof UM)]);
                        if (UM && window.core && core.ModelManage) {
                            var um = core.ModelManage.getInstance().getModel(UM);
                            var cs = um && um.getClientSettings ? um.getClientSettings() : null;
                            push('[settings]', ['guideStep=' + (cs ? cs.guideStep : 'null') +
                                ' uid=' + (um ? um.getUID && um.getUID() : '?')]);
                        }
                    } catch (e14) { push('[settings-error]', [String(e14)]); }
                } catch (e) { push('[tree-error]', [String(e && e.stack || e)]); }
            }, Number(dm[1]) * 1000);
        }

        /* find display nodes whose class source contains a substring: ?find=Str[,Str2] */
        var fm2 = /[?&]find=([^&]+)/.exec(Q);
        if (fm2) {
            setTimeout(function () {
                try {
                    var keys = decodeURIComponent(fm2[1]).split(',');
                    var stage = egret.MainContext.instance.stage;
                    var hits = 0;
                    (function walk(node, depth) {
                        if (depth > 12 || !node) return;
                        var kids = node.$children || [];
                        for (var i = 0; i < kids.length; i++) {
                            var c = kids[i];
                            var src = fp(c.constructor);
                            for (var k = 0; k < keys.length; k++) {
                                if (src.indexOf(keys[k]) >= 0) {
                                    var g = null;
                                    try { g = c.localToGlobal(0, 0); } catch (e) { }
                                    push('[find]', ['d=' + depth + ' ' + keys[k] + ' ' +
                                        Math.round(c.width) + 'x' + Math.round(c.height) +
                                        ' vis=' + c.visible + ' a=' + c.alpha +
                                        ' global=' + (g ? Math.round(g.x) + ',' + Math.round(g.y) : '?') +
                                        ' ch=' + (c.$children ? c.$children.length : '?')]);
                                    // children detail: find the tap target
                                    try {
                                        (c.$children || []).forEach(function (k2, ki) {
                                            var g2 = null;
                                            try { g2 = k2.localToGlobal(0, 0); } catch (e) { }
                                            push('[findkid]', ['  ' + ki + ' ' + fp(k2.constructor).slice(14, 50) +
                                                ' ' + Math.round(k2.width) + 'x' + Math.round(k2.height) +
                                                ' global=' + (g2 ? Math.round(g2.x) + ',' + Math.round(g2.y) : '?') +
                                                ' touchEnabled=' + k2.touchEnabled +
                                                ' touchChildren=' + k2.touchChildren]);
                                        });
                                    } catch (e) { }
                                    // ancestors' touch flags: a false touchChildren
                                    // anywhere up the chain swallows the tap
                                    try {
                                        var anc = c.parent, ad = 0;
                                        while (anc && ad < 8) {
                                            push('[findanc]', ['  up' + ad + ' ' +
                                                fp(anc.constructor).slice(14, 46) +
                                                ' touchEnabled=' + anc.touchEnabled +
                                                ' touchChildren=' + anc.touchChildren +
                                                ' vis=' + anc.visible]);
                                            anc = anc.parent; ad++;
                                        }
                                    } catch (e) { }
                                    hits++;
                                }
                            }
                            walk(c, depth + 1);
                        }
                    })(stage, 0);
                    if (!hits) push('[find]', ['no match for ' + keys.join(',')]);
                } catch (e) { push('[find-error]', [String(e)]); }
            }, Number((/[?&]findat=(\d+)/.exec(Q) || [])[1] || 30) * 1000);
        }

        /* view-stack dump: ?views=seconds */
        var vm = /[?&]views=(\d+)/.exec(Q);
        if (vm) {
            setTimeout(function () {
                try {
                    var vs = window.__views || [];
                    var t0 = vs.length ? vs[0].t : Date.now();
                    push('[views]', ['count=' + vs.length]);
                    vs.slice(0, 40).forEach(function (v) {
                        push('[view1]', [v.op + ' +' + ((v.t - t0) / 1000).toFixed(1) + 's l=' +
                            (v.layer === undefined ? '-' : v.layer) + ' ' + v.fp.slice(14, 74)]);
                    });
                } catch (e) { push('[views-error]', [String(e)]); }
            }, Number(vm[1]) * 1000);
        }

        /* tutorial/settings watch: ?watch=seconds */
        var wm = /[?&]watch=(\d+)/.exec(Q);
        if (wm) {
            var every = Number(wm[1]) * 1000;
            var n = 0;
            var wid = setInterval(function () {
                n++;
                if (n > 25) { clearInterval(wid); return; }
                try {
                    var UM = window.UserModel;
                    if (!UM || !window.core) return;
                    var um = core.ModelManage.getInstance().getModel(UM);
                    var cs = um && um.getClientSettings ? um.getClientSettings() : null;
                    var rm = core.ModelManage.getInstance().getModel(window.RoleModel);
                    var extra = '';
                    try {
                        extra = ' frogStatus=' + (rm ? rm.getFrogStatus && rm.getFrogStatus() : '?') +
                            ' todayStep=' + (rm ? rm.getTodayStep && rm.getTodayStep() : '?');
                    } catch (e) { }
                    push('[watch]', ['t=' + n + ' guideStep=' + (cs ? cs.guideStep : 'null') + extra]);
                } catch (e) { push('[watch-error]', [String(e)]); }
            }, every);
        }

        /* dump the client's own data tables: ?dumpdb=seconds */
        var dbm = /[?&]dumpdb=(\d+)/.exec(Q);
        if (dbm) {
            setTimeout(function () {
                try {
                    var dm = Tabikaeru.DataManager.instance();
                    function ids(db) {
                        try {
                            if (db && db.list) return db.list().map(function (o) { return o.id; });
                            if (db && db.count && db.index) {
                                var a = [];
                                for (var i = 0; i < db.count(); i++) { var o = db.index(i); a.push(o && o.id); }
                                return a;
                            }
                            if (db && db.src && db.src.data) return db.src.data.map(function (o) { return o.id; });
                        } catch (e) { return []; }
                        return [];
                    }
                    function chunk(label, arr) {
                        var s = arr.join(',');
                        push('[db]', [label + ' n=' + arr.length]);
                        for (var i = 0; i < s.length; i += 900) {
                            push('[dbd]', [label + ':' + s.slice(i, i + 900)]);
                        }
                    }
                    var DBs = {
                        Item: dm.ItemDB, Specialty: dm.SpecialtyDB, Prize: dm.PrizeDB,
                        Collection: dm.CollectDB, Character: dm.CharaDB,
                        Shop: dm.ShopDataDB, Picture: dm.PictureDB, Goal: dm.GoalNumberDB,
                    };
                    for (var k in DBs) {
                        try { chunk(k, ids(DBs[k])); } catch (e) { push('[db-err]', [k + ' ' + e]); }
                    }
                    // item type/sub_type table is what travel rewards actually need
                    try {
                        var items = dm.ItemDB.list();
                        var rows = items.map(function (o) {
                            return o.id + '|' + o.type + '|' + (o.sub_type === undefined ? '' : o.sub_type);
                        });
                        push('[dbitem]', ['n=' + rows.length]);
                        var s2 = rows.join(';');
                        for (var j = 0; j < s2.length; j += 900) {
                            push('[dbitemd]', [s2.slice(j, j + 900)]);
                        }
                    } catch (e) { push('[dbitem-err]', [String(e)]); }
                } catch (e) { push('[db-error]', [String(e)]); }
            }, Number(dbm[1]) * 1000);
        }

        /* drive the in-game GM console: ?gm=command&gmat=seconds
           (the console must already be open - tap the red square first) */
        var gmm = /[?&]gm=([^&]+)/.exec(Q);
        if (gmm) {
            setTimeout(function () {
                try {
                    var v = findNodeIn('GM.exml');
                    if (!v) { push('[gm]', ['GM console not open']); return; }
                    var cmd = decodeURIComponent(gmm[1]);
                    if (v.t_context) v.t_context.text = cmd;
                    push('[gm]', ['executing: ' + cmd]);
                    v.execute(cmd);
                } catch (e) { push('[gm-error]', [String(e && e.stack || e)]); }
            }, Number((/[?&]gmat=(\d+)/.exec(Q) || [])[1] || 22) * 1000);
        }

        /* raw texture render test */
        if (/[?&]addtest=1/.test(Q)) {
            setTimeout(function () {
                try {
                    var stage = egret.MainContext.instance.stage;
                    [['sys_clover_window_png', 20, 20, 1.0],
                     ['season11_courtyard_png', 20, 120, 0.12],
                     ['mainout_season11_bg_png', 20, 420, 0.22]].forEach(function (t) {
                        var tex = RES.getRes(t[0]);
                        if (!tex) { push('[addtest]', [t[0] + ' NULL']); return; }
                        var bm = new egret.Bitmap(tex);
                        bm.x = t[1]; bm.y = t[2]; bm.scaleX = bm.scaleY = t[3];
                        stage.addChild(bm);
                        push('[addtest]', [t[0] + ' ' + tex.textureWidth + 'x' + tex.textureHeight]);
                    });
                } catch (e) { push('[addtest-error]', [String(e)]); }
            }, 14000);
        }

        /* scene experiments */
        var em = /[?&]exp=([^&]*)/.exec(Q);
        if (em) {
            setTimeout(function () {
                var view = findMainOutView();
                if (!view) { push('[exp]', ['no MainOut view']); return; }
                (em[1] || '').split(';').forEach(function (o) {
                    if (o.indexOf('scroll=') === 0 && view.scroller && view.scroller.viewport) {
                        view.scroller.viewport.scrollH = Number(o.slice(7));
                        push('[exp]', ['scrollH=' + view.scroller.viewport.scrollH]);
                    }
                    if (o === 'hidegroup' && view.bgGroup) {
                        view.bgGroup.visible = false;
                        push('[exp]', ['bgGroup hidden']);
                    }
                    if (o.indexOf('pos=') === 0) {
                        var xy = o.slice(4).split(',').map(Number);
                        ['animation3', 'animation2', 'animation1'].forEach(function (m) {
                            if (view[m]) { view[m].x = xy[0]; view[m].y = xy[1]; }
                        });
                        push('[exp]', ['animations -> ' + xy.join(',')]);
                    }
                });
            }, 15000);
        }
    }

    /* ------------------------------------------------------------------
     * Always-on driving hooks for a CDP client.
     *
     * These are NOT behind a query flag on purpose: a CDP client attaches to
     * the page AFTER it has already loaded, so it cannot add query params. With
     * these globals any probe can do
     *     window.__egretFind(['Calendar.exml'])   -> where is that view?
     *     window.__egretTap(x, y)                 -> tap it (Egret content coords)
     *     window.__egretPart('MainOut','btnCalendar') -> a skinned button
     * from a plain Runtime.evaluate, with no server endpoint involved.
     * ------------------------------------------------------------------ */

    /* The skin path is what actually identifies a view; a raw class source is
       unreadable when minified, so pull out getSkinsPath("...") when present. */
    function skinOf(obj) {
        var src = '';
        try { src = fp(obj.constructor); } catch (e) { return ''; }
        var m = /getSkinsPath\("([^"]+)"\)/.exec(src);
        return m ? m[1] : (src.slice(0, 40) + ' ..');
    }

    /* List live display nodes whose CLASS SOURCE **or `name`** contains any of
       `keys`. Matching the name matters: an EXML skin does
       `this.enterCalendarBtn = t` and never sets a class of its own, so a
       button is only identifiable by the property the skin gave it -- which
       Egret does not copy onto `.name` either. Callers therefore pass
       identifiers, and __egretFind2 below resolves skin PROPERTIES properly.
       Returns Egret content coordinates, the same space __egretTap consumes. */
    window.__egretFind = function (keys, maxDepth) {
        if (typeof keys === 'string') keys = [keys];
        var stage = egret.MainContext.instance.stage;
        var out = [];
        (function walk(node, depth) {
            if (depth > (maxDepth || 14) || !node || out.length > 300) return;
            var kids = node.$children || [];
            for (var i = 0; i < kids.length; i++) {
                var c = kids[i];
                var src = '';
                try { src = fp(c.constructor) + ' ' + (c.name || ''); } catch (e) { src = ''; }
                for (var k = 0; k < keys.length; k++) {
                    if (src.indexOf(keys[k]) >= 0) {
                        var g = null;
                        try { g = c.localToGlobal(0, 0); } catch (e) { g = null; }
                        out.push({
                            key: keys[k], depth: depth,
                            cls: skinOf(c) + (c.name ? (' name=' + c.name) : ''),
                            x: g ? Math.round(g.x) : null, y: g ? Math.round(g.y) : null,
                            w: Math.round(c.width), h: Math.round(c.height),
                            vis: c.visible, alpha: c.alpha,
                            name: c.name || '',
                            touch: c.touchEnabled, touchChildren: c.touchChildren,
                            kids: c.$children ? c.$children.length : 0,
                        });
                    }
                }
                walk(c, depth + 1);
            }
        })(stage, 0);
        return out;
    };

    /* Find a view by its skin path, then read ONE OF ITS PROPERTIES -- that is
       how a skinned part (enterCalendarBtn, btnWatch, btnShare ...) is actually
       reachable. Returns geometry in content coordinates. */
    window.__egretPart = function (skinKey, prop, maxDepth) {
        var stage = egret.MainContext.instance.stage;
        var out = [];
        (function walk(node, depth) {
            if (depth > (maxDepth || 12) || !node || out.length > 60) return;
            var kids = node.$children || [];
            for (var i = 0; i < kids.length; i++) {
                var c = kids[i];
                var src = '';
                try { src = fp(c.constructor); } catch (e) { src = ''; }
                if (src.indexOf(skinKey) >= 0) {
                    var part = c[prop];
                    var g = null;
                    try { g = part && part.localToGlobal(0, 0); } catch (e) { g = null; }
                    out.push({
                        view: skinOf(c), prop: prop,
                        found: !!part,
                        x: g ? Math.round(g.x) : null, y: g ? Math.round(g.y) : null,
                        w: part ? Math.round(part.width) : null,
                        h: part ? Math.round(part.height) : null,
                        vis: part ? part.visible : null,
                        touch: part ? part.touchEnabled : null,
                        label: (part && part.text) ? part.text : ((part && part.label) ? part.label : null),
                        src: (part && part.source) ? part.source : null,
                    });
                }
                walk(c, depth + 1);
            }
        })(stage, 0);
        return out;
    };


    /* Tap at Egret content coordinates. Same conversion and same
       same-tick down+up as ?tap=, which is the path that has actually been
       verified to reach Egret's TOUCH_TAP. */
    window.__egretTap = function (x, y) {
        var cvs = document.querySelectorAll('canvas');
        var sent = 0;
        for (var i = 0; i < cvs.length; i++) {
            var c = cvs[i];
            var r = c.getBoundingClientRect();
            if (!r.width || !r.height) continue;
            var dpr = window.devicePixelRatio || 1;
            var sx = r.left + x * (r.width / (c.width / dpr));
            var sy = r.top + y * (r.height / (c.height / dpr));
            ['mousedown', 'mouseup'].forEach(function (type) {
                c.dispatchEvent(new MouseEvent(type, {
                    bubbles: true, cancelable: true, view: window,
                    clientX: sx, clientY: sy, screenX: sx, screenY: sy, button: 0,
                }));
            });
            sent++;
        }
        return 'tapped ' + x + ',' + y + ' on ' + sent + ' canvas(es)';
    };

    /* ---------------------------------------- 5. 存档"住址"提醒（跨端口安全网）
     *
     * 为什么需要：浏览器把 localStorage 按 origin（**含端口**）隔离，所以"换个端口打开"
     * 等于打开一个空存档 —— 玩家看到的就是"存档被重置、重新开始"。PC 启动器现在不会
     * 再悄悄换端口（8080 被占时会复用或直接停下），但如果玩家手动改了地址/端口、
     * 或者换了 localhost 而不是 127.0.0.1，仍然会碰到这件事。
     *
     * cookie 是按**主机**（不含端口）隔离的，正好能跨端口留个"存档案"的线索：
     * 记下上一次存档所在的 origin 与大小；这次是空存档而 cookie 说别处有 -> 明确提示。
     */
    (function () {
        var SAVE_KEY = 'frog.offline.save';
        var COOKIE = 'frog_save_home';

        function readCookie() {
            var m = document.cookie.match(new RegExp('(?:^|;\\s*)' + COOKIE + '=([^;]*)'));
            if (!m) return null;
            try { return JSON.parse(decodeURIComponent(m[1])); } catch (e) { return null; }
        }
        function writeCookie(v) {
            try {
                document.cookie = COOKIE + '=' + encodeURIComponent(JSON.stringify(v))
                    + ';path=/;max-age=' + (3600 * 24 * 365) + ';SameSite=Lax';
            } catch (e) { /* ignore */ }
        }
        function sizeOf(s) { try { return s ? s.length : 0; } catch (e) { return 0; } }

        function check() {
            var mine = null;
            try { mine = localStorage.getItem(SAVE_KEY); } catch (e) { /* ignore */ }
            var here = { origin: location.origin, size: sizeOf(mine), at: Math.floor(Date.now() / 1000) };
            var prev = readCookie();

            /* 这里没有存档，但 cookie 记着别处有一份 -> 说清楚去哪找 */
            if (!mine && prev && prev.origin && prev.origin !== location.origin && prev.size > 200) {
                var when = prev.at ? new Date(prev.at * 1000).toLocaleString() : '之前';
                showBanner('这台电脑上另有一份存档在 <b>' + prev.origin + '</b>（'
                    + Math.round(prev.size / 1024) + ' KB，' + when + '）。<br>'
                    + '用那个地址打开就能接着玩；或者在那个地址的「存档编辑」里<b>导出存档</b>，'
                    + '再回到这里<b>导入存档</b>搬过来。<br>'
                    + '<span style="opacity:.75">（这次的进度是新的：浏览器按地址分开保存，'
                    + '换地址/端口就会看到另一个存档）</span>');
            }
            if (mine) writeCookie(here);
            else if (!prev) writeCookie(here);
        }

        /* The banner used to be single-shot: the first message won and any later,
           more serious one was dropped. It now accumulates, because "your save was
           damaged and restored from backup" can arrive after "another origin has a
           save", and the player needs both. */
        var bannerBox = null;
        var bannerBlocks = [];
        function showBanner(html) {
            if (bannerBlocks.indexOf(html) !== -1) return;
            bannerBlocks.push(html);
            var body = bannerBlocks.join(
                '<hr style="border:none;border-top:1px dashed #c9b79a;margin:9px 0">');
            if (bannerBox) {
                bannerBox.firstChild.innerHTML = body;
                return;
            }
            function draw() {
                var box = document.createElement('div');
                box.style.cssText = [
                    'position:fixed', 'left:12px', 'right:12px', 'top:12px', 'z-index:2147483646',
                    'background:#fffdf3', 'color:#2f2a20', 'border:2px solid #b9482f',
                    'border-radius:10px', 'padding:10px 12px', 'font:13px/1.5 system-ui,sans-serif',
                    'box-shadow:0 6px 20px rgba(0,0,0,.35)', 'max-width:760px', 'margin:0 auto',
                ].join(';');
                box.innerHTML = '<div style="font-weight:700;margin-bottom:4px">存档提醒</div>'
                    + '<div>' + body + '</div>';
                var btn = document.createElement('button');
                btn.textContent = '知道了';
                btn.style.cssText = 'margin-top:8px;padding:5px 12px;border-radius:6px;'
                    + 'border:1px solid #b9482f;background:#b9482f;color:#fff;cursor:pointer;'
                    + 'font:inherit';
                btn.onclick = function () { box.remove(); bannerBox = null; };
                box.appendChild(btn);
                document.body.appendChild(box);
                bannerBox = box;
            }
            if (document.body) draw();
            else document.addEventListener('DOMContentLoaded', draw);
        }

        /* ------------------------------------ 5b. 存档安全状态（引擎自报）
         *
         * 引擎现在自己会做：主档 -> 备份 -> 手机镜像 的读取链、写入前的备份、
         * 写回校验、坏档先归档再重开、拒绝覆盖更新版本的存档。这些都必须是
         * **玩家看得见**的 —— 因为旧代码的毛病不是丢数据本身，而是丢得无声无息
         * （parse 失败 -> try/catch -> 直接开新档）。
         *
         * 这里只读 window.__engine.state.__saveReport，不改任何状态。
         */
        function saveReportCheck() {
            var e = window.__engine;
            if (!e || !e.state || !e.state.__saveReport) return false;
            var r = e.state.__saveReport;
            var info = (typeof e.saveInfo === 'function') ? e.saveInfo() : null;

            if (r.action === 'restore') {
                var src = r.restoredFrom === 'mirror' ? '手机里保存的那份（原生镜像）' : '上一次的完整备份';
                showBanner('这次的存档文件读不出来（' + (r.reason || '损坏') + '），'
                    + '已经自动从 <b>' + src + '</b> 恢复，进度没有丢。<br>'
                    + (r.corruptKept
                        ? '<span style="opacity:.75">损坏的那份保留在 <code>' + r.corruptKept
                          + '</code>，没有删掉。</span>'
                        : ''));
            } else if (r.reason && r.reason !== 'missing') {
                showBanner('上一次的存档文件读不出来（' + r.reason + '），而且没有可用的备份，'
                    + '所以这次是<b>新开始</b>。损坏的那份已保留在 <code>'
                    + (r.corruptKept || '（未能归档）') + '</code>。');
            }
            if (r.protectMain) {
                showBanner('<b>已停止写入存档</b>：旧的存档文件无法读取，也没能归档保存，'
                    + '继续写会把它彻底覆盖掉。<br>请先把 <code>' + ((info && info.path) || 'save.json')
                    + '</code> 复制出来备份，再决定是否放弃它。');
            } else if (r.blocked) {
                showBanner('<b>已停止写入存档</b>：这份存档是更新版本的游戏写的（'
                    + 'saveVersion ' + e.state.saveVersion + '），用当前版本继续玩不会覆盖它。');
            } else if (r.lastError) {
                showBanner('<b>保存失败</b>（' + r.lastError + '）：磁盘/浏览器存储写不进去，'
                    + '旧存档还在，但<b>最新进度没能写进存档</b>。请检查磁盘空间后重启游戏。<br>'
                    + (info && info.pending
                        ? '<span style="opacity:.75">完整的一份暂存在 <code>' + info.pending + '</code>。</span>'
                        : ''));
            }
            return true;
        }
        /* The engine is created inside installLoopback(), which runs a little after
           this script does, and never at all under ?transport=ws. Poll briefly. */
        var reportTries = 0;
        (function waitForEngine() {
            if (saveReportCheck() || reportTries++ > 40) return;
            setTimeout(waitForEngine, 250);
        })();

        /* 引擎装载后再看：这个检查要在 localStorage 有内容时也更新 cookie */
        setTimeout(check, 1500);
        setTimeout(check, 6000);
        window.__saveHomeCheck = check;
        window.__saveReportCheck = saveReportCheck;
    })();

    /* ------------------------------------------- 6. 蛙出门了，帽子却留在屋里
     *
     * 玩家报的："蛙蛙旅行的时候帽子还在家里？" —— **属实**，而且是客户端自己的缺陷，
     * 引擎侧表达不了"玩家此刻正站在屋里"：
     *
     *   MainInView.updateFlogStatus():
     *       var isHome = Tabikaeru.Game.instance().isHome;
     *       ...拆掉/重建屋里的小青蛙...
     *       if (isHome) { this.frogCap.visible = true; ... }      // ← 只有 if，没有 else
     *
     *   MainInController 不订阅 RoleEventType.loadRole（MainOutController 订阅了），
     *   所以"蛙从在家变成出门"这一刻屋里视图根本不会重算；而任何一次 reset()
     *   都会**重建蛙却不关帽子** —— 结果就是蛙没了、`frogCap.visible` 还是上次
     *   "在家"留下的 true。实测：进屋 → 让蛙出门 → 再进屋，`frogCap.visible === true`
     *   而蛙的身体不在（截图 work/shots/baghat_3_away_hat_only.png）。
     *
     * 修法：这里补上客户端缺的那半条规矩 —— 引擎说蛙不在家，帽子就不该在屋里。
     * 只改**可见性**，不碰蛙的重建逻辑（那是客户端的事，动它风险大）。
     */
    (function () {
        var cached = null;
        function findRoomView() {
            if (cached && cached.frogCap) return cached;
            cached = null;
            try {
                var stage = egret.MainContext.instance.stage;
                (function walk(node, depth) {
                    if (cached || depth > 16 || !node) return;
                    if (node.frogCap) { cached = node; return; }
                    var kids = node.$children || [];
                    for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1);
                })(stage, 0);
            } catch (e) { /* 还没建好 */ }
            return cached;
        }

        function watchHat() {
            try {
                var eng = window.__engine;
                if (!eng || !eng.state || !eng.state.frog) return;
                var away = Number(eng.state.frog.status) !== 0;   // 0 = 在家
                var view = findRoomView();
                if (!view || !view.frogCap) return;
                if (away && view.frogCap.visible) view.frogCap.visible = false;
            } catch (e) { /* 绝不因为这条补丁影响游戏 */ }
        }

        window.__hatWatch = watchHat;      // 探针/验收可以直接调
        setInterval(watchHat, 700);
    })();

    /* Which views are currently on screen (the controller stack). */
    window.__egretViews = function () {
        var stage = egret.MainContext.instance.stage;
        var out = [];
        (function walk(node, depth) {
            if (depth > 10 || !node || out.length > 200) return;
            var kids = node.$children || [];
            for (var i = 0; i < kids.length; i++) {
                var c = kids[i];
                if (/\.exml/.test(fp(c.constructor)) && c.visible) {
                    var g = null;
                    try { g = c.localToGlobal(0, 0); } catch (e) { }
                    out.push({ d: depth, skin: skinOf(c),
                        xy: g ? Math.round(g.x) + ',' + Math.round(g.y) : '?',
                        wh: Math.round(c.width) + 'x' + Math.round(c.height) });
                }
                walk(c, depth + 1);
            }
        })(stage, 0);
        return out;
    };
})();
