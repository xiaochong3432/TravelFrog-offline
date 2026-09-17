package com.frog.offline;

import android.content.res.AssetManager;
import android.util.Log;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.*;

/** Read-only, loopback-only server. A fixed origin preserves WebView localStorage. */
final class AssetServer implements Closeable {
    static final String ORIGIN = "http://127.0.0.1:18763";
    private final AssetManager assets;
    private final ServerSocket server;
    private final ThreadPoolExecutor workers = new ThreadPoolExecutor(4, 4, 0,
        TimeUnit.SECONDS, new ArrayBlockingQueue<Runnable>(64));

    AssetServer(AssetManager assets) throws IOException {
        this.assets = assets;
        server = new ServerSocket();
        server.setReuseAddress(true);
        server.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), 18763));
        Thread accept = new Thread(() -> {
            while (!server.isClosed()) {
                try {
                    final Socket socket = server.accept();
                    try { workers.execute(() -> serve(socket)); }
                    catch (RejectedExecutionException e) { socket.close(); }
                } catch (IOException e) {
                    if (!server.isClosed()) Log.e("FrogAssets", "accept", e);
                }
            }
        }, "FrogAssets");
        accept.setDaemon(true);
        accept.start();
    }

    private static String line(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        int c;
        while ((c = in.read()) != -1 && c != '\n') {
            if (out.size() >= 8192) throw new IOException("Header too long");
            if (c != '\r') out.write(c);
        }
        return out.toString("US-ASCII");
    }

    private void serve(Socket socket) {
        try (Socket s = socket) {
            s.setSoTimeout(10000);
            InputStream in = new BufferedInputStream(s.getInputStream());
            OutputStream out = new BufferedOutputStream(s.getOutputStream());
            String[] request = line(in).split(" ");
            if (request.length != 3) return;
            int headers = 0;
            while (!line(in).isEmpty()) {
                if (++headers > 100) return;
            }
            if (!request[0].equals("GET") && !request[0].equals("HEAD")) {
                status(out, "405 Method Not Allowed", "text/plain");
            } else {
                String path = new URI(request[1]).getPath();
                if (path == null || !path.startsWith("/") || path.contains("\\")
                        || path.indexOf('\0') >= 0) throw new IOException("Invalid path");
                for (String part : path.split("/")) {
                    if (part.equals("..")) throw new IOException("Invalid path");
                }
                if (path.equals("/")) path = "/index.html";
                // The legacy client asks the optional remote update endpoint with an
                // undefined URL. Answer locally so its update promise can finish.
                if (path.equals("/undefined")) {
                    status(out, "200 OK", "application/json; charset=utf-8");
                    if (request[0].equals("GET")) out.write("{}".getBytes(StandardCharsets.UTF_8));
                    out.flush();
                    return;
                }
                InputStream file = null;
                try { file = assets.open("game" + path, AssetManager.ACCESS_STREAMING); }
                catch (IOException e) {
                    Log.w("FrogAssets", "404 " + path);
                    status(out, "404 Not Found", "text/plain");
                }
                if (file != null) {
                    try (InputStream data = file) {
                        status(out, "200 OK", mime(path));
                        if (request[0].equals("GET")) {
                            byte[] buf = new byte[32768];
                            int n;
                            while ((n = data.read(buf)) != -1) out.write(buf, 0, n);
                        }
                    }
                }
            }
            out.flush();
        } catch (Exception e) { Log.w("FrogAssets", "request: " + e); }
    }

    private static void status(OutputStream out, String status, String type) throws IOException {
        out.write(("HTTP/1.1 " + status + "\r\nContent-Type: " + type
            + "\r\nConnection: close\r\nCache-Control: no-cache\r\n\r\n")
            .getBytes(StandardCharsets.US_ASCII));
    }

    private static String mime(String path) {
        String p = path.toLowerCase(Locale.ROOT);
        if (p.endsWith(".js")) return "application/javascript; charset=utf-8";
        if (p.endsWith(".json")) return "application/json; charset=utf-8";
        if (p.endsWith(".html")) return "text/html; charset=utf-8";
        if (p.endsWith(".css")) return "text/css; charset=utf-8";
        String type = URLConnection.guessContentTypeFromName(p);
        return type == null ? "application/octet-stream" : type;
    }

    public void close() throws IOException {
        server.close();
        workers.shutdownNow();
    }
}
