package com.frog.offline;

import android.content.res.AssetManager;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Minimal HTTP/1.1 server bound to 127.0.0.1 that serves the game's H5 build out
 * of the APK's {@code assets/game} directory.
 *
 * <p>Why a server instead of loading {@code file:///android_asset/...} directly:
 * the Egret engine fetches its resources with XMLHttpRequest, and WebView refuses
 * XHR against {@code file://} URLs. Serving over {@code http://127.0.0.1:<port>}
 * puts the page on a normal origin and makes those requests work -- this is the
 * same arrangement that was verified on desktop (a plain {@code http.server}).
 */
public final class AssetServer {

    private static final String TAG = "FrogAssetServer";
    private static final String ROOT = "game";
    private static final int READ_TIMEOUT_MS = 20000;

    /**
     * The port is FIXED on purpose, and this matters a lot.
     *
     * <p>{@code localStorage} -- which is where the game save lives -- is
     * partitioned per *origin*, and the origin includes the port. Binding to an
     * ephemeral port ({@code new ServerSocket(0)}) therefore hands the page a
     * different origin on every launch, so it reads an empty store and the frog
     * is forgotten each time. A fixed port keeps the origin stable.
     *
     * <p>Chosen below the 32768-60999 ephemeral range so that a transient outgoing
     * connection is unlikely to be holding it.
     */
    public static final int PORT = 18080;

    private static final Map<String, String> MIME = new HashMap<String, String>();

    static {
        MIME.put("html", "text/html; charset=utf-8");
        MIME.put("htm", "text/html; charset=utf-8");
        MIME.put("js", "application/javascript; charset=utf-8");
        MIME.put("mjs", "application/javascript; charset=utf-8");
        MIME.put("css", "text/css; charset=utf-8");
        MIME.put("json", "application/json; charset=utf-8");
        MIME.put("xml", "application/xml; charset=utf-8");
        MIME.put("txt", "text/plain; charset=utf-8");
        MIME.put("csv", "text/csv; charset=utf-8");
        MIME.put("png", "image/png");
        MIME.put("jpg", "image/jpeg");
        MIME.put("jpeg", "image/jpeg");
        MIME.put("gif", "image/gif");
        MIME.put("webp", "image/webp");
        MIME.put("bmp", "image/bmp");
        MIME.put("ico", "image/x-icon");
        MIME.put("svg", "image/svg+xml");
        MIME.put("mp3", "audio/mpeg");
        MIME.put("m4a", "audio/mp4");
        MIME.put("aac", "audio/aac");
        MIME.put("ogg", "audio/ogg");
        MIME.put("wav", "audio/wav");
        MIME.put("mp4", "video/mp4");
        MIME.put("webm", "video/webm");
        MIME.put("ttf", "font/ttf");
        MIME.put("otf", "font/otf");
        MIME.put("woff", "font/woff");
        MIME.put("woff2", "font/woff2");
        MIME.put("fnt", "application/octet-stream");
    }

    private final AssetManager assets;
    private final ServerSocket socket;
    private final ExecutorService pool = Executors.newCachedThreadPool();
    private volatile boolean running = true;

    public AssetServer(AssetManager assets, int port) throws IOException {
        this.assets = assets;
        // Bind explicitly to loopback so nothing on the network can reach it, and
        // to a caller-chosen port so the page origin stays stable across launches.
        ServerSocket ss = new ServerSocket();
        ss.setReuseAddress(true);
        ss.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), port), 64);
        this.socket = ss;
    }

    public int getPort() {
        return socket.getLocalPort();
    }

    public void start() {
        Thread t = new Thread(new Runnable() {
            @Override
            public void run() {
                while (running) {
                    try {
                        final Socket c = socket.accept();
                        pool.execute(new Runnable() {
                            @Override
                            public void run() {
                                handle(c);
                            }
                        });
                    } catch (IOException e) {
                        if (running) {
                            Log.w(TAG, "accept failed: " + e);
                        }
                    }
                }
            }
        }, "frog-asset-server");
        t.setDaemon(true);
        t.start();
    }

    public void stop() {
        running = false;
        try {
            socket.close();
        } catch (IOException ignored) {
            // shutting down anyway
        }
        pool.shutdownNow();
    }

    // ------------------------------------------------------------------ request

    private void handle(Socket c) {
        try {
            c.setSoTimeout(READ_TIMEOUT_MS);
            InputStream in = c.getInputStream();
            OutputStream out = c.getOutputStream();

            String requestLine = readLine(in);
            if (requestLine == null) {
                return;
            }
            String[] parts = requestLine.split(" ");
            if (parts.length < 2) {
                sendError(out, 400, "Bad Request");
                return;
            }
            String method = parts[0];
            String target = parts[1];

            int contentLength = 0;
            String header;
            while ((header = readLine(in)) != null && header.length() > 0) {
                int colon = header.indexOf(':');
                if (colon > 0) {
                    String k = header.substring(0, colon).trim().toLowerCase(Locale.US);
                    String v = header.substring(colon + 1).trim();
                    if ("content-length".equals(k)) {
                        try {
                            contentLength = Integer.parseInt(v);
                        } catch (NumberFormatException ignored) {
                        }
                    }
                }
            }

            String path = target;
            int q = path.indexOf('?');
            if (q >= 0) {
                path = path.substring(0, q);
            }
            path = percentDecode(path);

            // The offline shell posts its console log here (that is how it was
            // wired for the desktop diagnostics); accept it and forward to logcat
            // instead of 404-ing, which would spam the console with errors.
            if (path.equals("/__log")) {
                if (contentLength > 0) {
                    byte[] body = readExactly(in, contentLength);
                    Log.i("FrogGame", new String(body, "UTF-8"));
                }
                send(out, 200, "OK", "application/json", "{\"ok\":true}".getBytes("UTF-8"), false);
                return;
            }

            if (!"GET".equals(method) && !"HEAD".equals(method)) {
                sendError(out, 405, "Method Not Allowed");
                return;
            }

            if (path.equals("/") || path.isEmpty()) {
                path = "/index.html";
            }
            if (path.startsWith("/")) {
                path = path.substring(1);
            }
            if (path.contains("..")) {
                sendError(out, 403, "Forbidden");
                return;
            }

            byte[] body;
            try {
                body = readAsset(ROOT + "/" + path);
            } catch (IOException e) {
                sendError(out, 404, "Not Found");
                return;
            }
            send(out, 200, "OK", mimeOf(path), body, "HEAD".equals(method));
        } catch (Exception e) {
            Log.w(TAG, "request failed: " + e);
        } finally {
            try {
                c.close();
            } catch (IOException ignored) {
            }
        }
    }

    private byte[] readAsset(String path) throws IOException {
        InputStream is = assets.open(path);
        try {
            ByteArrayOutputStream bos = new ByteArrayOutputStream(64 * 1024);
            byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = is.read(buf)) > 0) {
                bos.write(buf, 0, n);
            }
            return bos.toByteArray();
        } finally {
            try {
                is.close();
            } catch (IOException ignored) {
            }
        }
    }

    // ------------------------------------------------------------------ response

    private void send(OutputStream out, int code, String reason, String type,
                      byte[] body, boolean headOnly) throws IOException {
        StringBuilder sb = new StringBuilder(256);
        sb.append("HTTP/1.1 ").append(code).append(' ').append(reason).append("\r\n");
        sb.append("Content-Type: ").append(type).append("\r\n");
        sb.append("Content-Length: ").append(body.length).append("\r\n");
        sb.append("Cache-Control: no-store\r\n");
        sb.append("Connection: close\r\n\r\n");
        out.write(sb.toString().getBytes("US-ASCII"));
        if (!headOnly) {
            out.write(body);
        }
        out.flush();
    }

    private void sendError(OutputStream out, int code, String reason) throws IOException {
        send(out, code, reason, "text/plain; charset=utf-8",
                (code + " " + reason).getBytes("UTF-8"), false);
    }

    private static String mimeOf(String path) {
        int dot = path.lastIndexOf('.');
        if (dot >= 0) {
            String ext = path.substring(dot + 1).toLowerCase(Locale.US);
            String m = MIME.get(ext);
            if (m != null) {
                return m;
            }
        }
        return "application/octet-stream";
    }

    // ------------------------------------------------------------------ helpers

    private static String readLine(InputStream in) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream(128);
        int c;
        while ((c = in.read()) != -1) {
            if (c == '\n') {
                break;
            }
            if (c != '\r') {
                b.write(c);
            }
        }
        if (c == -1 && b.size() == 0) {
            return null;
        }
        return new String(b.toByteArray(), "UTF-8");
    }

    private static byte[] readExactly(InputStream in, int n) throws IOException {
        byte[] buf = new byte[n];
        int off = 0;
        while (off < n) {
            int r = in.read(buf, off, n - off);
            if (r < 0) {
                break;
            }
            off += r;
        }
        return buf;
    }

    /** Percent-decoding that does NOT treat '+' as a space (unlike URLDecoder). */
    private static String percentDecode(String s) {
        StringBuilder sb = new StringBuilder(s.length());
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '%' && i + 2 < s.length()) {
                int hi = Character.digit(s.charAt(i + 1), 16);
                int lo = Character.digit(s.charAt(i + 2), 16);
                if (hi >= 0 && lo >= 0) {
                    sb.append((char) ((hi << 4) | lo));
                    i += 2;
                    continue;
                }
            }
            sb.append(c);
        }
        return sb.toString();
    }
}
