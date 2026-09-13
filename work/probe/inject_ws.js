/* Pre-document injection: record EVERY WebSocket the page opens, with the JS
   stack that opened it. Purpose: find out whether the client's own socket layer
   ever bypasses the in-page loopback and dials a real server -- which would
   surface as "呱呱，吃坏肚子了" (Reload.Broken) and an endless reload loop.
   Read back with:  window.__wsLog */
(function () {
    var Real = window.WebSocket;
    var log = [];
    window.__wsLog = log;

    function Proxy(url, protocols) {
        var stack = '';
        try { throw new Error('ws-open'); } catch (e) { stack = e.stack || ''; }
        log.push({ url: String(url), at: Date.now(), stack: stack.split('\n').slice(1, 7).join('\n') });
        // Let the real socket proceed: we only want to OBSERVE, not change
        // behaviour, so a failure here is still the genuine one.
        return protocols === undefined ? new Real(url) : new Real(url, protocols);
    }
    Proxy.prototype = Real.prototype;
    ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach(function (k) { Proxy[k] = Real[k]; });
    window.WebSocket = Proxy;
})();
