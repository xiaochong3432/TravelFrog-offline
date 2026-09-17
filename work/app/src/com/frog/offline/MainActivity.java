package com.frog.offline;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.DocumentsContract;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.util.AtomicFile;
import android.util.Log;
import android.view.View;
import android.webkit.*;
import android.widget.Toast;
import java.io.*;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** Offline WebView host. Its fixed origin is part of the save compatibility contract. */
public final class MainActivity extends Activity {
    private static final String TAG = "FrogNative";
    private static final Object MIRROR_LOCK = new Object();
    private static final int IMPORT_DOCUMENT = 1;
    private static final int EXPORT_DOCUMENT = 2;
    private static AssetServer server;
    private WebView web;
    private ValueCallback<Uri[]> fileCallback;
    private final Object exportLock = new Object();
    private String pendingSave;
    private String pendingName;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        try {
            synchronized (MainActivity.class) {
                if (server == null) server = new AssetServer(getApplicationContext().getAssets());
            }
        } catch (IOException e) {
            new AlertDialog.Builder(this).setMessage("本地服务启动失败：" + e.getMessage())
                .setPositiveButton("关闭", (d, w) -> finish()).setCancelable(false).show();
            return;
        }
        web = new WebView(this);
        setContentView(web);
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(false);
        web.getSettings().setAllowContentAccess(true);
        web.getSettings().setMediaPlaybackRequiresUserGesture(false);
        WebView.setWebContentsDebuggingEnabled(true);
        SaveBridge bridge = new SaveBridge();
        web.addJavascriptInterface(bridge, "FrogNative");
        // Older pages used saveFile(text, name); keep their argument order intact.
        web.addJavascriptInterface(bridge, "SaveBridge");
        web.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest r) {
                if (isLocalUrl(r.getUrl().toString())) return null;
                return new WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden",
                    java.util.Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return !isLocalUrl(url);
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return !isLocalUrl(request.getUrl().toString());
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onConsoleMessage(ConsoleMessage m) {
                Log.i("FrogWeb", m.message() + " @ " + m.sourceId() + ":" + m.lineNumber());
                return true;
            }
            @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                    FileChooserParams params) {
                if (fileCallback != null) fileCallback.onReceiveValue(null);
                fileCallback = callback;
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("*/*");
                try { startActivityForResult(intent, IMPORT_DOCUMENT); }
                catch (Exception e) { callback.onReceiveValue(null); fileCallback = null; }
                return true;
            }
        });
        web.loadUrl(AssetServer.ORIGIN + "/index.html");
    }

    public final class SaveBridge {
        @JavascriptInterface public String platform() { return "android"; }

        @JavascriptInterface public void exitApp() {
            runOnUiThread(() -> finishAndRemoveTask());
        }

        @JavascriptInterface public String readMirrorSave() {
            synchronized (MIRROR_LOCK) {
                AtomicFile mirror = mirrorFile();
                try (InputStream in = mirror.openRead(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                    byte[] buffer = new byte[8192];
                    int length;
                    while ((length = in.read(buffer)) != -1) out.write(buffer, 0, length);
                    String text = out.toString("UTF-8");
                    new JSONObject(text);
                    return text;
                } catch (FileNotFoundException e) {
                    return null;
                } catch (Exception e) {
                    Log.w(TAG, "Cannot read save mirror", e);
                    return null;
                }
            }
        }

        @JavascriptInterface public void mirrorSave(String json) {
            synchronized (MIRROR_LOCK) {
                AtomicFile mirror = mirrorFile();
                FileOutputStream out = null;
                try {
                    // A rejected write must retain the last complete mirror.
                    if (json == null) throw new IOException("Missing save data");
                    new JSONObject(json);
                    out = mirror.startWrite();
                    out.write(json.getBytes(StandardCharsets.UTF_8));
                    mirror.finishWrite(out);
                } catch (Exception e) {
                    if (out != null) mirror.failWrite(out);
                    Log.w(TAG, "Cannot write save mirror", e);
                }
            }
        }

        @JavascriptInterface public String exportSave(String name, String json) {
            if (json == null) return "";
            String filename = safeFilename(name);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                return writeToDownloads(filename, json);
            }
            return beginDocumentExport(filename, json) ? "PICKER" : "";
        }

        @JavascriptInterface public void saveFile(String text, String name) {
            // Preserve the old SAF interaction for existing callers.
            beginDocumentExport(safeFilename(name), text);
        }
    }

    private AtomicFile mirrorFile() {
        return new AtomicFile(new File(getFilesDir(), "save-mirror.json"));
    }

    private static boolean isLocalUrl(String url) {
        if (url == null) return false;
        Uri uri = Uri.parse(url);
        return "http".equals(uri.getScheme()) && "127.0.0.1".equals(uri.getHost())
            && uri.getPort() == 18763;
    }

    private static String safeFilename(String name) {
        if (name == null) return "frog-save.json";
        String safe = name.replaceAll("[\\\\/\\p{Cntrl}]", "_").trim();
        return safe.isEmpty() || safe.equals(".") || safe.equals("..") ? "frog-save.json" : safe;
    }

    private boolean beginDocumentExport(String name, String json) {
        synchronized (exportLock) {
            if (pendingSave != null || json == null || isFinishing() || isDestroyed()) return false;
            pendingSave = json;
            pendingName = name;
        }
        runOnUiThread(() -> {
            try {
                Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("application/json");
                intent.putExtra(Intent.EXTRA_TITLE, name);
                startActivityForResult(intent, EXPORT_DOCUMENT);
            } catch (Exception e) {
                synchronized (exportLock) { pendingSave = null; pendingName = null; }
                Log.w(TAG, "Cannot open export picker", e);
                notifyPage("__saveExportFailed", "无法打开系统保存窗口");
                toast("无法打开系统保存窗口");
            }
        });
        return true;
    }

    private String writeToDownloads(String name, String json) {
        Uri uri = null;
        try {
            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
            values.put(MediaStore.MediaColumns.MIME_TYPE, "application/json");
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
            values.put(MediaStore.MediaColumns.IS_PENDING, 1);
            uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) throw new IOException("Cannot create download");
            try (OutputStream out = getContentResolver().openOutputStream(uri, "wt")) {
                if (out == null) throw new IOException("Cannot open download");
                out.write(json.getBytes(StandardCharsets.UTF_8));
                out.flush();
            }
            values.clear();
            values.put(MediaStore.MediaColumns.IS_PENDING, 0);
            if (getContentResolver().update(uri, values, null, null) < 1) {
                throw new IOException("Cannot publish download");
            }
            String actualName = queryDisplayName(uri);
            return actualName == null ? uri.toString() : "内部存储/Download/" + actualName;
        } catch (Exception e) {
            Log.w(TAG, "Cannot export save to Downloads", e);
            if (uri != null) {
                try { getContentResolver().delete(uri, null, null); }
                catch (Exception cleanup) { Log.w(TAG, "Cannot remove incomplete download", cleanup); }
            }
            return "";
        }
    }

    private String queryDisplayName(Uri uri) {
        try (Cursor cursor = getContentResolver().query(uri,
                new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (column >= 0 && !cursor.isNull(column)) return cursor.getString(column);
            }
        } catch (Exception e) { Log.w(TAG, "Cannot query exported filename", e); }
        return null;
    }

    private String readableDocumentLocation(Uri uri, String requestedName) {
        // Only the local document provider's primary volume maps to this path.
        if ("com.android.externalstorage.documents".equals(uri.getAuthority())) {
            try {
                String id = DocumentsContract.getDocumentId(uri);
                if (id.startsWith("primary:")) return "内部存储/" + id.substring(8);
            } catch (Exception e) { Log.w(TAG, "Cannot resolve exported document path", e); }
        }
        String actualName = queryDisplayName(uri);
        return (actualName == null ? requestedName : actualName) + "（" + uri.toString() + "）";
    }

    private void notifyPage(String function, String message) {
        runOnUiThread(() -> {
            if (web == null || !isLocalUrl(web.getUrl())) return;
            String callback = "window[" + JSONObject.quote(function) + "]";
            web.evaluateJavascript(callback + " && " + callback + "(" + JSONObject.quote(message) + ")", null);
        });
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        Uri uri = result == RESULT_OK && data != null ? data.getData() : null;
        if (request == IMPORT_DOCUMENT && fileCallback != null) {
            fileCallback.onReceiveValue(uri == null ? null : new Uri[] {uri});
            fileCallback = null;
        }
        if (request == EXPORT_DOCUMENT) {
            String text;
            String name;
            synchronized (exportLock) {
                text = pendingSave;
                name = pendingName;
                pendingSave = null;
                pendingName = null;
            }
            if (uri != null && text != null) {
                try (OutputStream out = getContentResolver().openOutputStream(uri, "wt")) {
                    if (out == null) throw new IOException("Cannot open document");
                    out.write(text.getBytes(StandardCharsets.UTF_8));
                    out.flush();
                } catch (Exception e) {
                    Log.w(TAG, "Cannot write exported document", e);
                    notifyPage("__saveExportFailed", "系统未能写入所选文件");
                    toast("导出失败：系统未能写入所选文件");
                    return;
                }
                String where = readableDocumentLocation(uri, name);
                notifyPage("__saveExported", where);
                toast("存档已导出到：" + where);
            } else {
                notifyPage("__saveExportFailed", uri == null ? "已取消" : "待导出的存档已失效，请重试");
            }
        }
    }

    private void toast(String text) { Toast.makeText(this, text, Toast.LENGTH_LONG).show(); }

    @Override public void onWindowFocusChanged(boolean focus) {
        super.onWindowFocusChanged(focus);
        if (focus) getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN
            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
    }

    @Override protected void onPause() { if (web != null) web.onPause(); super.onPause(); }
    @Override protected void onResume() { super.onResume(); if (web != null) web.onResume(); }
    @Override protected void onDestroy() {
        if (fileCallback != null) fileCallback.onReceiveValue(null);
        if (web != null) {
            web.removeJavascriptInterface("SaveBridge");
            web.removeJavascriptInterface("FrogNative");
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
