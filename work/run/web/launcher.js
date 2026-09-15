var getQuery = function (key) {
    if (window && window.location && window.location.search) {
        let reg = new RegExp("(^|&)" + key + "=([^&]*)(&|$)", "i");
        let r = window.location.search.substr(1).match(reg);
        return r != null ? r[2] : null;
    } else {
        return "";
    }
}

var loadScript = function (list, callback) {
    var loaded = 0;
    var loadNext = function () {
        loadSingleScript(list[loaded], function () {
            loaded++;
            if (loaded >= list.length) {
                callback();
            } else {
                loadNext();
            }
        })
    };
    loadNext();
};

var loadSingleScript = function (src, callback) {
    var s = document.createElement('script');
    s.async = false;
    s.src = src;
    s.addEventListener('load', function () {
        s.parentNode.removeChild(s);
        s.removeEventListener('load', arguments.callee, false);
        callback();
    }, false);
    document.body.appendChild(s);
};

var onHttpLoad = function (manifest) {
    window.resUrl = manifest.res;
    window.thmUrl = manifest.thm;
    window.manifestVersion = manifest.version;
    window.manifestBuild = manifest.build;
    window.appVersion = manifest.appVersion;
    window.appStatus = manifest.appStatus;

    window.frogCode = manifest.code;
    window.frogArgs = manifest.args;
    var list = manifest.initial.concat(manifest.game);
    // add cdn prefix for url
    for (var idx = 0; idx < list.length; idx++) {
        list[idx] = window.cdn + list[idx];
    }
    loadScript(list, function () {
        /**
         * {
         * "renderMode":, //Engine rendering mode, "canvas" or "webgl"
         * "audioType": 0 //Use the audio type, 0: default, 2: web audio, 3: audio
         * "antialias": //Whether the anti-aliasing is enabled in WebGL mode, true: on, false: off, defaults to false
         * "calculateCanvasScaleFactor": //a function return canvas scale factor
         * }
         **/
        egret.runEgret({
            renderMode: "webgl",
            audioType: 0,
            calculateCanvasScaleFactor: function (context) {
                var backingStore = context.backingStorePixelRatio ||
                    context.webkitBackingStorePixelRatio ||
                    context.mozBackingStorePixelRatio ||
                    context.msBackingStorePixelRatio ||
                    context.oBackingStorePixelRatio ||
                    context.backingStorePixelRatio || 1;
                return (window.devicePixelRatio || 1) / backingStore;
            }
        });
    });
}

var httpRequest = function (url, errorCallback, loadCallback) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.addEventListener("error", function () {
        console.log("..................error:", url);
        if (errorCallback) {
            errorCallback();
        }
    });
    xhr.addEventListener("load", function () {
        var manifest = JSON.parse(xhr.response);
        if (loadCallback) {
            loadCallback(manifest);
        }
    });
    xhr.send(null);
}

var manifestBranch = getQuery("manifest") || "";
var manifestVersionName = 'manifest' + (manifestBranch ? ("." + manifestBranch) : "") + '.json';
var manifestName = 'manifest.json';

var rmtRequest = function (errorCallback, loadCallback) {
    httpRequest(window.cdnLaunch + manifestVersionName + '?v=' + Math.random(), function () {
        httpRequest(window.ossLaunch + manifestVersionName + '?v=' + Math.random(), function () {
            if (manifestBranch) {
                httpRequest(window.cdnLaunch + manifestName + '?v=' + Math.random(), function () {
                    httpRequest(window.ossLaunch + manifestName + '?v=' + Math.random(), function () {
                        errorCallback();
                    }, function (manifest) {
                        loadCallback(manifest);
                    });
                }, function (manifest) {
                    loadCallback(manifest);
                });
            } else {
                errorCallback();
            }
        }, function (manifest) {
            loadCallback(manifest);
        });
    }, function (manifest) {
        loadCallback(manifest);
    });
}

// OFFLINE BUILD: skip the remote CDN entirely and boot from the local manifest.
window.launchInfo = "offline_local";
httpRequest(manifestVersionName + '?v=' + Math.random(), function () {
    window.launchInfo = "local_failed";
    console.log("offline: local manifest.json missing");
}, onHttpLoad);