#!/usr/bin/env python3
"""PC entry point for 《旅行青蛙·中国之旅》 offline build.

Serves the patched game over http://127.0.0.1:<port> and opens the default
browser. The game itself needs no backend: the offline engine runs inside the
page (Route B), and the save lives in the browser's localStorage.

A local HTTP server is only needed because browsers refuse XHR over file://.

Usage:
  python play_frog.py [--port 8080] [--no-browser] [--web <dir>]
"""
import argparse, functools, http.server, os, socket, socketserver, sys, threading, time, webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))


def out(s=""):
    """Print immediately and never crash on an unmappable console code page."""
    try:
        print(s, flush=True)
    except UnicodeEncodeError:
        enc = (sys.stdout.encoding or "ascii")
        print(s.encode(enc, "replace").decode(enc, "replace"), flush=True)

# Where the game files might live, in order of preference. 全部相对本脚本自身，
# 所以整个包（或整个仓库）搬到哪里都能跑；也可以用 FROG_WEB 显式指定。
CANDIDATES = [
    os.environ.get("FROG_WEB", ""),
    os.path.join(HERE, "web"),                                  # shipped next to this script
    os.path.join(HERE, "..", "work", "run", "web"),             # repo layout
    os.path.join(HERE, "work", "run", "web"),                   # repo root
]
CANDIDATES = [c for c in CANDIDATES if c]

MIME = {
    ".js": "application/javascript",
    ".json": "application/json",
    ".html": "text/html",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".mp3": "audio/mpeg",
    ".mp4": "video/mp4",
    ".atlas": "text/plain",
    ".fnt": "text/plain",
    ".xml": "application/xml",
    ".eab": "application/octet-stream",
    ".lua": "text/plain",
    ".css": "text/css",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        ext = os.path.splitext(path)[1].lower()
        if ext in MIME:
            return MIME[ext]
        return super().guess_type(path)

    def end_headers(self):
        # never cache: the whole point is testing a moving build
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        # keep the console readable
        if "404" in (fmt % args):
            sys.stderr.write("  [404] %s\n" % (fmt % args))

    def do_GET(self):
        """`/__frog_ping` 只用来回答"8080 上是不是已经跑着一个本游戏的服务"。

        为什么需要它：浏览器把 localStorage 按 origin（含端口）隔离，所以"换个端口启动"
        == "换了一个空存档" —— 玩家看到的就是"存档被重置、重新开始"。启动器因此
        不允许悄悄换端口：8080 被占时必须先判断"占它的是不是我们自己"。
        """
        if self.path.split("?")[0] == "/__frog_ping":
            body = PING_BODY.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


PING_BODY = "frog-offline-pc-v1"
REMEMBER_FILE = "last-port.txt"


def port_is_free(port):
    with socket.socket() as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def our_server_on(port, timeout=0.8):
    """port 上跑的是不是本游戏的服务？（是 -> 直接复用，别再开一个换端口的）"""
    import urllib.request
    try:
        with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/__frog_ping", timeout=timeout) as r:
            return r.read().decode("utf-8", "replace").strip() == PING_BODY
    except Exception:
        return False


def remembered_port():
    """上一个版本**用过的端口**，记在启动器旁边的小文件里。

    为什么记：浏览器把 localStorage 按 origin（含端口）隔离，所以"这次换了个端口"
    就是"打开了一个空存档" —— 玩家看到的就是"存档被重置、重新开始"。
    跟手机壳里的做法一致（那版把端口写死 18080）：**端口一旦选定就沿用**，
    这样地址稳定、存档也稳定；8080 被占时也不会漂到别的存档位置去。
    """
    try:
        with open(os.path.join(HERE, REMEMBER_FILE), encoding="utf-8") as f:
            p = int(f.read().strip())
        return p if 1 <= p <= 65535 else None
    except Exception:
        return None


def remember_port(port):
    try:
        with open(os.path.join(HERE, REMEMBER_FILE), "w", encoding="utf-8") as f:
            f.write(str(port))
    except Exception:
        pass


def choose_port(preferred):
    """-> (port, how)。how ∈ {preferred, reuse, remembered, reuse-remembered, new, None}"""
    if port_is_free(preferred):
        return preferred, "preferred"
    if our_server_on(preferred):
        return preferred, "reuse"
    remember = remembered_port()
    if remember and remember != preferred:
        if port_is_free(remember):
            return remember, "remembered"
        if our_server_on(remember):
            return remember, "reuse-remembered"
    return None, "busy"


def find_web(explicit):
    if explicit:
        return explicit if os.path.isdir(explicit) else None
    for c in CANDIDATES:
        c = os.path.abspath(c)
        if os.path.isfile(os.path.join(c, "index.html")) and \
           os.path.isfile(os.path.join(c, "__offline-engine.js")):
            return c
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--web", default=None)
    ap.add_argument("--no-browser", action="store_true")
    ap.add_argument("--allow-other-port", action="store_true",
                    help="8080 被别的程序占用时，允许换端口启动（会换到另一个存档位置）")
    args = ap.parse_args()

    web = find_web(args.web)
    if not web:
        out("找不到游戏文件。期望在下面任一路径找到 index.html + __offline-engine.js：")
        for c in CANDIDATES:
            out("    " + os.path.abspath(c))
        out("也可以用 --web <目录> 指定。")
        return 1

    port, how = choose_port(args.port)
    reuse_only = how in ("reuse", "reuse-remembered")

    if port is None:
        if args.allow_other_port:
            for p in range(args.port + 1, args.port + 20):
                if port_is_free(p):
                    port, how = p, "new"
                    break
        if port is None:
            out("=" * 64)
            out(f"端口 {args.port} 被别的程序占用了，而且没找到可以沿用的旧端口。")
            out("=" * 64)
            out("  为什么不能随便换个端口：浏览器按「地址」保存存档，地址里包含端口，")
            out("  换端口 = 换一个空存档，看起来就像『存档被重置、重新开始』。")
            out("")
            out("  请二选一：")
            out(f"    1) 先关掉占用 {args.port} 的程序，再重新双击启动（推荐）")
            out(f"       查看占用者：  netstat -ano | findstr :{args.port}")
            out(f"       结束进程：    taskkill /PID <上面的PID> /F")
            out("    2) 明确要换到别的端口（会换存档位置）加上参数：")
            out("       python play_frog.py --allow-other-port")
            out("       换过去之后，用旧地址打开可以「导出存档」，再在新区里「导入存档」搬过来。")
            out("=" * 64)
            try:
                input("  按回车退出。")
            except EOFError:
                pass
            return 2

    if how in ("preferred", "new", "remembered"):
        remember_port(port)

    if reuse_only:
        url = f"http://127.0.0.1:{port}/index.html"
        out("=" * 64)
        out("  旅行青蛙·中国之旅  —  离线单机版（PC）")
        out("=" * 64)
        out(f"  已经在运行：{url}")
        out("  这次不重复启动服务，直接用同一个地址打开 —— 存档还在原处。")
        out("")
        out("  关闭本窗口不会停掉已经在跑的那个服务。")
        out("=" * 64)
        if not args.no_browser:
            webbrowser.open(url)
        try:
            input("  按回车退出。")
        except EOFError:
            pass
        return 0

    handler = functools.partial(Handler, directory=web)
    httpd = Server(("127.0.0.1", port), handler)
    url = f"http://127.0.0.1:{port}/index.html"

    out("=" * 64)
    out("  旅行青蛙·中国之旅  —  离线单机版（PC）")
    out("=" * 64)
    out(f"  游戏目录 : {web}")
    out(f"  地址     : {url}")
    out("")
    out("  这个版本不需要任何后端服务，存档就在浏览器里（localStorage）。")
    out("  ⚠ 存档跟「地址（含端口）」绑定：请始终用本启动器打开，")
    out("     不要手动改端口、也不要换用 localhost/其他浏览器，否则会看到另一个空存档。")
    out("  进游戏后，画面左侧那颗圆球就是【存档编辑】：")
    out("    · 点一下打开面板，按住可以拖到任意位置（位置会记住）")
    out("    · 面板里可以直接点：解锁图鉴+百科 / 获得全部家具 / 三叶草 / 改名 …")
    out("    · 「导出存档 / 导入存档」用来备份和搬存档，换电脑就靠它")
    out("    · 「指令台（高级）」是原来那台可以打字的控制台")
    out("")
    out("  关闭本窗口即退出游戏服务。")
    out("=" * 64)
    if how == "remembered":
        out(f"  【说明】8080 被别的程序占用了，这家用的是上次那个端口 {port}（记在 {REMEMBER_FILE}）。")
        out(f"        这样地址不变、存档就在原处。想回到 8080：先关掉占用它的程序再启动。")
        out("=" * 64)
    elif how == "new":
        out(f"  【注意】按 --allow-other-port 换了端口：地址从 8080 变成了 {port}。")
        out("        这等于换了一个存档位置（旧存档仍在 http://127.0.0.1:8080/ ）。")
        out("=" * 64)

    if not args.no_browser:
        threading.Thread(target=lambda: (time.sleep(1.0), webbrowser.open(url)),
                         daemon=True).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n已退出。")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
