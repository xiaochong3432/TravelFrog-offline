package com.frog.offline;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.DocumentsContract;
import android.provider.MediaStore;
import android.util.Log;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;

/**
 * A deliberately tiny replacement for the original channel/Oppo shell.
 *
 * <p>The shipped APK wraps the H5 game in a stack of channel SDKs (Oppo game
 * service, gosdk, Alibaba SecurityGuard, ad SDKs). Its Application class runs
 * channel initialisation on every launch and the game is only handed off to the
 * WebView after a channel login succeeds. That login can no longer succeed --
 * the game service was shut down on 2026-12-08 -- so the app parks on a login
 * screen forever. None of that machinery is needed to run the game itself, which
 * is plain H5: the desktop build proves it runs standalone in a browser.
 *
 * <p>So this activity does only what is required:
 * <ol>
 *   <li>start a loopback HTTP server over {@code assets/game}</li>
 *   <li>point a WebView at it</li>
 *   <li>bridge save export/import to the system file picker</li>
 * </ol>
 * Saves live in the WebView's {@code localStorage}, i.e. in this app's private
 * data directory, so they survive restarts and app updates.
 */
public class MainActivity extends Activity {

    private static final String TAG = "FrogOffline";

    private static final int REQ_FILE_CHOOSER = 1001;
    private static final int REQ_CREATE_SAVE = 1002;
    /** 3.4 的「把照片存到相册」：API 29 以下走系统文件选择器（SAF）。 */
    private static final int REQ_EXPORT_IMAGE = 1003;

    /** Native copy of the save, used only when localStorage comes up empty. */
    private static final String MIRROR_FILE = "save-mirror.json";

    private AssetServer server;
    private WebView web;

    /** Set while the WebView is waiting for a file to import. */
    private ValueCallback<Uri[]> fileCallback;

    /** Payload handed to us by the page for the pending export. */
    private String pendingSaveJson;
    private String pendingSaveName;

    /**
     * PNG handed to us by the page for the pending gallery export (3.4 起支持：
     * 客户端「抓拍」与相册的「保存图片」都走这里）。
     */
    private byte[] pendingImage;
    private final Object imageLock = new Object();

    /**
     * The origin a PREVIOUS build of this app served the page from.
     *
     * <p>The handover build used {@code http://127.0.0.1:18763}; this wrapper uses
     * {@link AssetServer#PORT}. {@code localStorage} is scoped to the origin, so a player
     * coming from that build has a save in a store this origin cannot see. The page's
     * one-time adoption probe (see LEGACY_SAVE_ADOPT in __probe.js) can only read it from
     * a document that actually runs on that origin -- hence a second, asset-only listener
     * here. It serves the payload read-only, exactly like the main one; nothing else
     * depends on it and a failure to bind is not an error (the game runs either way).
     */
    private static final int LEGACY_ORIGIN_PORT = 18763;

    private AssetServer legacyServer;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        server = startServer();
        legacyServer = startLegacyOriginServer();

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        // localStorage is where the game save lives -- without this the frog
        // would be forgotten on every launch.
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(true);
        s.setLoadsImagesAutomatically(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setJavaScriptCanOpenWindowsAutomatically(false);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);

        web.setBackgroundColor(0xFF000000);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                // Everything the game needs is local; ignore external navigation.
                return !url.startsWith("http://127.0.0.1:")
                        && !url.startsWith("http://localhost:");
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage m) {
                Log.i(TAG, "console: " + m.message() + " @ " + m.sourceId() + ":" + m.lineNumber());
                return true;
            }

            /**
             * The page's "import save" button uses a plain
             * {@code <input type="file">}. WebView only opens a picker if the host
             * implements this -- otherwise the button does nothing at all.
             */
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                                             FileChooserParams params) {
                if (fileCallback != null) {
                    fileCallback.onReceiveValue(null);
                }
                fileCallback = callback;
                try {
                    startActivityForResult(params.createIntent(), REQ_FILE_CHOOSER);
                    return true;
                } catch (Exception e) {
                    Log.w(TAG, "no file chooser available: " + e);
                    fileCallback = null;
                    return false;
                }
            }
        });

        // Export path. The page normally offers the save as a Blob download, which
        // WebView silently drops, so __probe.js prefers this bridge when present.
        web.addJavascriptInterface(new SaveBridge(), "FrogNative");

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            WebView.setWebContentsDebuggingEnabled(true);
        }

        setContentView(web, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));

        if (server != null) {
            web.loadUrl("http://127.0.0.1:" + server.getPort() + "/index.html");
        }
    }

    /** Exposed to the page as {@code window.FrogNative}. */
    private final class SaveBridge {

        @JavascriptInterface
        public String platform() {
            return "android";
        }

        /**
         * 退出游戏 from the in-game help menu.
         *
         * <p>The help menu's exit button calls {@code BaseChannel.logout()}, which in
         * the original build went to the channel SDK and killed the app. There is no
         * SDK here, so the page calls this instead. {@code finishAndRemoveTask} also
         * clears the task from Recents; {@code finish} alone leaves a dead card
         * behind on some OEM launchers.
         *
         * <p>Always posted to the UI thread: a JavascriptInterface method is called
         * on a WebView-internal thread, and finishing an Activity from there is not
         * allowed.
         */
        @JavascriptInterface
        public void exitApp() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    Log.i(TAG, "exitApp requested by the page");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        finishAndRemoveTask();
                    } else {
                        finish();
                    }
                }
            });
        }

        /**
         * Safety net for the save.
         *
         * <p>localStorage normally persists on its own, but it is tied to the page
         * origin; if the fixed port could not be taken and we fell back to a random
         * one, the origin -- and with it the store -- changes between launches.
         * Keeping a copy in the app's private files means the frog survives that.
         *
         * <p>The page only consults this when localStorage has nothing, so it can
         * never override a good save.
         *
         * @return the mirrored JSON, or null when there is none
         */
        @JavascriptInterface
        public String readMirrorSave() {
            try {
                File f = new File(getFilesDir(), MIRROR_FILE);
                if (!f.isFile() || f.length() == 0) {
                    return null;
                }
                byte[] buf = new byte[(int) f.length()];
                FileInputStream in = new FileInputStream(f);
                try {
                    int off = 0;
                    while (off < buf.length) {
                        int n = in.read(buf, off, buf.length - off);
                        if (n <= 0) {
                            break;
                        }
                        off += n;
                    }
                } finally {
                    in.close();
                }
                Log.i(TAG, "readMirrorSave: " + buf.length + " bytes");
                return new String(buf, "UTF-8");
            } catch (Exception e) {
                Log.w(TAG, "readMirrorSave failed: " + e);
                return null;
            }
        }

        /** Best-effort mirror write; never lets a failure affect the game. */
        @JavascriptInterface
        public void mirrorSave(String json) {
            if (json == null) {
                return;
            }
            try {
                File dst = new File(getFilesDir(), MIRROR_FILE);
                File tmp = new File(getFilesDir(), MIRROR_FILE + ".tmp");
                FileOutputStream out = new FileOutputStream(tmp);
                try {
                    out.write(json.getBytes("UTF-8"));
                    out.flush();
                } finally {
                    out.close();
                }
                // swap so a crash mid-write cannot leave a torn save behind
                if (!tmp.renameTo(dst)) {
                    if (dst.delete() && tmp.renameTo(dst)) {
                        return;
                    }
                    Log.w(TAG, "mirrorSave: could not replace " + dst);
                }
            } catch (Exception e) {
                Log.w(TAG, "mirrorSave failed: " + e);
            }
        }

        /**
         * Write the save JSON somewhere the user can actually find it, and REPORT WHERE.
         *
         * <p>Two paths, because this app supports API 21+:
         * <ul>
         *   <li>API 29+: write straight into the public Downloads collection through
         *       MediaStore -- no permission needed and the location is fixed, so the
         *       page can simply print "内部存储/Download/xxx.json". A dialog would be
         *       worse here: it makes the player hunt for a folder for no reason.</li>
         *   <li>older: the Storage Access Framework {@code ACTION_CREATE_DOCUMENT}
         *       picker, which needs no permission on any API level; the chosen location
         *       comes back in {@link #onActivityResult} and is reported then.</li>
         * </ul>
         *
         * <p>Returns a human-readable location, the sentinel {@link #PICKER_SENTINEL}
         * when the picker was opened (the answer arrives later), or "" on failure.
         * Previously this returned a boolean and the page never called it at all: a Blob
         * download is dropped silently inside a WebView, so 导出存档 claimed success
         * while writing nothing.
         */
        @JavascriptInterface
        public String exportSave(final String filename, final String json) {
            final String name = (filename == null || filename.length() == 0)
                    ? "frog-save.json" : filename;
            final String body = json == null ? "{}" : json;

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                return writeToDownloads(name, body);
            }

            pendingSaveName = name;
            pendingSaveJson = body;
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    try {
                        Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                        i.addCategory(Intent.CATEGORY_OPENABLE);
                        i.setType("application/json");
                        i.putExtra(Intent.EXTRA_TITLE, pendingSaveName);
                        startActivityForResult(i, REQ_CREATE_SAVE);
                    } catch (Exception e) {
                        Log.w(TAG, "cannot open save picker: " + e);
                        pendingSaveJson = null;
                        toast("无法打开系统的保存窗口，导出未完成");
                        notifyPage("__saveExportFailed", "系统没有可用的保存窗口");
                    }
                }
            });
            return PICKER_SENTINEL;
        }

        /**
         * 把页面给的一张 PNG 存进相册（3.4 的客户端补丁 `save_texture_to_album` 调用它）。
         *
         * <p>Android 10+ 直接写 {@code Pictures/TravelFrog}（MediaStore，两段式 IS_PENDING，
         * 失败会把半成品删掉）；更低版本没有这个集合，退回系统文件选择器，结果通过
         * {@code window.__frogImageExportResult} 异步回给页面 —— 页面的 {@code where === 'PICKER'}
         * 分支就是等这个回调。
         *
         * <p>只接受 PNG，且限制 base64 长度（28 M 字符 ≈ 21 MB 图），避免一次大字符串把
         * WebView 顶爆。
         */
        @JavascriptInterface
        public String exportImage(String name, String dataUrl) {
            if (dataUrl == null || !dataUrl.startsWith("data:image/png;base64,")
                    || dataUrl.length() > 28000000) {
                return "";
            }
            final byte[] bytes;
            try {
                bytes = android.util.Base64.decode(dataUrl.substring(22), android.util.Base64.DEFAULT);
                android.graphics.BitmapFactory.Options options = new android.graphics.BitmapFactory.Options();
                options.inJustDecodeBounds = true;
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
                if (options.outWidth <= 0 || options.outHeight <= 0
                        || !"image/png".equals(options.outMimeType)) {
                    return "";
                }
            } catch (Exception e) {
                return "";
            }
            final String filename = safeFilename(name);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Uri uri = null;
                try {
                    ContentValues v = new ContentValues();
                    v.put(MediaStore.MediaColumns.DISPLAY_NAME, filename);
                    v.put(MediaStore.MediaColumns.MIME_TYPE, "image/png");
                    v.put(MediaStore.MediaColumns.RELATIVE_PATH,
                            Environment.DIRECTORY_PICTURES + "/TravelFrog");
                    v.put(MediaStore.MediaColumns.IS_PENDING, 1);
                    uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
                    if (uri == null) {
                        throw new IOException("cannot create image");
                    }
                    OutputStream os = getContentResolver().openOutputStream(uri, "w");
                    if (os == null) {
                        throw new IOException("cannot write image");
                    }
                    try {
                        os.write(bytes);
                        os.flush();
                    } finally {
                        try {
                            os.close();
                        } catch (Exception ignored) {
                        }
                    }
                    v.clear();
                    v.put(MediaStore.MediaColumns.IS_PENDING, 0);
                    if (getContentResolver().update(uri, v, null, null) < 1) {
                        throw new IOException("cannot publish image");
                    }
                    return uri.toString();
                } catch (Exception e) {
                    if (uri != null) {
                        try {
                            getContentResolver().delete(uri, null, null);
                        } catch (Exception ignored) {
                        }
                    }
                    Log.w(TAG, "cannot export image: " + e);
                    return "";
                }
            }

            synchronized (imageLock) {
                if (pendingImage != null || isFinishing() || isDestroyed()) {
                    return "";
                }
                pendingImage = bytes;
            }
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    try {
                        Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                        i.addCategory(Intent.CATEGORY_OPENABLE);
                        i.setType("image/png");
                        i.putExtra(Intent.EXTRA_TITLE, filename);
                        startActivityForResult(i, REQ_EXPORT_IMAGE);
                    } catch (Exception e) {
                        synchronized (imageLock) {
                            pendingImage = null;
                        }
                        Log.w(TAG, "cannot open image picker: " + e);
                        notifyPage("__frogImageExportResult", "");
                    }
                }
            });
            return PICKER_SENTINEL;
        }
    }

    /** 只留文件名本体：去掉目录分隔符与控制字符，最长 64 字符，缺省 frog-photo.png。 */
    private static String safeFilename(String name) {
        String base = name == null ? "" : name.trim();
        int slash = Math.max(base.lastIndexOf('/'), base.lastIndexOf('\\'));
        if (slash >= 0) {
            base = base.substring(slash + 1);
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < base.length() && sb.length() < 64; i++) {
            char c = base.charAt(i);
            if (c >= ' ' && c != ':' && c != '*' && c != '?' && c != '"' && c != '<' && c != '>'
                    && c != '|') {
                sb.append(c);
            }
        }
        String out = sb.toString();
        if (out.length() == 0) {
            out = "frog-photo";
        }
        return out.replaceAll("(?i)\\.png$", "") + ".png";
    }

    /** Returned by exportSave() when the system picker was opened instead of writing. */
    private static final String PICKER_SENTINEL = "PICKER";

    /**
     * API 29+: put the file in the public Downloads collection (no permission), then read
     * the display name back so the reported location is exact -- MediaStore renames a
     * duplicate to "name (1).json".
     */
    private String writeToDownloads(String name, String json) {
        Uri uri = null;
        try {
            ContentValues v = new ContentValues();
            v.put(MediaStore.Downloads.DISPLAY_NAME, name);
            v.put(MediaStore.Downloads.MIME_TYPE, "application/json");
            v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
            uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
            if (uri == null) {
                Log.w(TAG, "Download insert returned null");
                toast("导出失败：系统拒绝了写入");
                return "";
            }
            OutputStream os = getContentResolver().openOutputStream(uri);
            if (os == null) {
                toast("导出失败：无法写入下载目录");
                return "";
            }
            try {
                os.write(json.getBytes("UTF-8"));
                os.flush();
            } finally {
                os.close();
            }
            String shown = queryDisplayName(uri, name);
            String where = "内部存储/" + Environment.DIRECTORY_DOWNLOADS + "/" + shown;
            Log.i(TAG, "exportSave -> " + where);
            toast("存档已导出：" + where);
            return where;
        } catch (Exception e) {
            Log.w(TAG, "writeToDownloads failed: " + e);
            if (uri != null) {
                try {
                    getContentResolver().delete(uri, null, null);
                } catch (Exception ignored) {
                }
            }
            toast("导出失败：" + e.getMessage());
            return "";
        }
    }

    private String queryDisplayName(Uri uri, String fallback) {
        Cursor c = null;
        try {
            c = getContentResolver().query(uri, new String[]{MediaStore.MediaColumns.DISPLAY_NAME},
                    null, null, null);
            if (c != null && c.moveToFirst()) {
                String n = c.getString(0);
                if (n != null && n.length() > 0) {
                    return n;
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "queryDisplayName failed: " + e);
        } finally {
            if (c != null) {
                c.close();
            }
        }
        return fallback;
    }

    /** Tell the page where the file went, so the panel can show it instead of guessing. */
    private void notifyPage(final String fn, final String arg) {
        final WebView w = web;
        if (w == null) {
            return;
        }
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    String js = "window." + fn + " && window." + fn + "("
                            + jsString(arg) + ")";
                    w.evaluateJavascript(js, null);
                } catch (Exception e) {
                    Log.w(TAG, "notifyPage failed: " + e);
                }
            }
        });
    }

    private static String jsString(String s) {
        if (s == null) {
            return "''";
        }
        StringBuilder b = new StringBuilder("'");
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (ch == '\\' || ch == '\'') {
                b.append('\\').append(ch);
            } else if (ch == '\n') {
                b.append("\\n");
            } else if (ch == '\r') {
                b.append("\\r");
            } else if (ch < 0x20) {
                b.append(' ');
            } else {
                b.append(ch);
            }
        }
        return b.append("'").toString();
    }

    /**
     * Bind the asset server to a FIXED port.
     *
     * <p>This is what makes the save survive a restart: {@code localStorage} is
     * partitioned by origin, the origin includes the port, so a random port means
     * a blank store on every launch. See {@link AssetServer#PORT}.
     */
    private AssetServer startServer() {
        for (int attempt = 1; attempt <= 15; attempt++) {
            try {
                AssetServer s = new AssetServer(getAssets(), AssetServer.PORT);
                s.start();
                Log.i(TAG, "asset server on 127.0.0.1:" + s.getPort()
                        + " (origin is stable; save will persist)");
                return s;
            } catch (IOException e) {
                Log.w(TAG, "port " + AssetServer.PORT + " not free (attempt " + attempt + "): " + e);
                try {
                    Thread.sleep(200);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        // Last resort. The game still runs, but the origin changes between launches
        // so localStorage starts empty -- the native mirror in SaveBridge is what
        // keeps the frog alive in this case.
        try {
            AssetServer s = new AssetServer(getAssets(), 0);
            s.start();
            Log.e(TAG, "FALLBACK to random port " + s.getPort()
                    + "; relying on the native save mirror for persistence");
            return s;
        } catch (IOException e) {
            Log.e(TAG, "cannot start the asset server at all", e);
            return null;
        }
    }

    /**
     * Best-effort listener on the PREVIOUS build's origin, so the page can read the save a
     * player left in that store. See {@link #LEGACY_ORIGIN_PORT}.
     *
     * <p>Nothing in the game path depends on this: if the port is taken by something else,
     * we log it and carry on -- the player simply cannot adopt the old store automatically
     * (they can still 导入存档 from an exported file).
     */
    private AssetServer startLegacyOriginServer() {
        try {
            AssetServer s = new AssetServer(getAssets(), LEGACY_ORIGIN_PORT);
            s.start();
            Log.i(TAG, "legacy-origin server on 127.0.0.1:" + s.getPort()
                    + " (lets the page adopt a save left by an older build)");
            return s;
        } catch (IOException e) {
            Log.w(TAG, "legacy origin 127.0.0.1:" + LEGACY_ORIGIN_PORT
                    + " not available (" + e + "); old-store adoption will be skipped");
            return null;
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_FILE_CHOOSER) {
            Uri[] result = null;
            if (resultCode == RESULT_OK && data != null) {
                if (data.getDataString() != null) {
                    result = new Uri[]{Uri.parse(data.getDataString())};
                } else if (data.getClipData() != null) {
                    int n = data.getClipData().getItemCount();
                    result = new Uri[n];
                    for (int i = 0; i < n; i++) {
                        result[i] = data.getClipData().getItemAt(i).getUri();
                    }
                }
            }
            if (fileCallback != null) {
                fileCallback.onReceiveValue(result);
                fileCallback = null;
            }
            return;
        }

        if (requestCode == REQ_EXPORT_IMAGE) {
            byte[] bytes;
            synchronized (imageLock) {
                bytes = pendingImage;
                pendingImage = null;
            }
            Uri uri = resultCode == RESULT_OK && data != null ? data.getData() : null;
            String saved = "";
            if (uri != null && bytes != null) {
                OutputStream os = null;
                try {
                    os = getContentResolver().openOutputStream(uri, "wt");
                    if (os == null) {
                        throw new IOException("cannot write image document");
                    }
                    os.write(bytes);
                    os.flush();
                    saved = readableLocation(uri, "frog-photo.png");
                } catch (Exception e) {
                    Log.w(TAG, "cannot export image document: " + e);
                } finally {
                    if (os != null) {
                        try {
                            os.close();
                        } catch (Exception ignored) {
                        }
                    }
                }
            }
            notifyPage("__frogImageExportResult", saved);
            return;
        }

        if (requestCode == REQ_CREATE_SAVE) {
            String json = pendingSaveJson;
            pendingSaveJson = null;
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                // Say so rather than leaving the player wondering whether it worked.
                Log.i(TAG, "save picker cancelled");
                toast("已取消导出");
                notifyPage("__saveExportFailed", "已取消");
                return;
            }
            if (json == null) {
                return;
            }
            OutputStream os = null;
            try {
                Uri uri = data.getData();
                os = getContentResolver().openOutputStream(uri);
                os.write(json.getBytes("UTF-8"));
                os.flush();
                String where = readableLocation(uri, pendingSaveName);
                Log.i(TAG, "exportSave (SAF) -> " + where);
                toast("存档已导出：" + where);
                notifyPage("__saveExported", where);
            } catch (Exception e) {
                Log.w(TAG, "writing save failed: " + e);
                toast("导出失败：" + e.getMessage());
                notifyPage("__saveExportFailed", "写入失败");
            } finally {
                if (os != null) {
                    try {
                        os.close();
                    } catch (Exception ignored) {
                    }
                }
            }
            return;
        }

        super.onActivityResult(requestCode, resultCode, data);
    }

    /**
     * Turn a SAF document uri into something a player can act on. The document id looks
     * like {@code primary:Download/frog-save-2026-09-12.json}, which is exactly the
     * "存储位置" they need.
     */
    private static String readableLocation(Uri uri, String fallbackName) {
        String id = null;
        try {
            id = DocumentsContract.getDocumentId(uri);
        } catch (Exception e) {
            Log.w(TAG, "getDocumentId failed: " + e);
        }
        if (id == null || id.length() == 0) {
            return fallbackName == null ? "你选择的位置" : "你选择的位置（" + fallbackName + "）";
        }
        if (id.startsWith("primary:")) {
            return "内部存储/" + id.substring("primary:".length());
        }
        int colon = id.indexOf(':');
        if (colon > 0) {
            // e.g. "1A2B-3C4D:Download/x.json" -- a removable card / usb volume
            return "外部存储 " + id.substring(0, colon) + "/" + id.substring(colon + 1);
        }
        return id;
    }

    private void toast(final String msg) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                Toast.makeText(MainActivity.this, msg, Toast.LENGTH_SHORT).show();
            }
        });
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && web != null && web.canGoBack()) {
            web.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (web != null) {
            web.onPause();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) {
            web.onResume();
        }
    }

    @Override
    protected void onDestroy() {
        if (server != null) {
            server.stop();
        }
        if (legacyServer != null) {
            legacyServer.stop();
        }
        if (web != null) {
            web.destroy();
        }
        super.onDestroy();
    }
}
