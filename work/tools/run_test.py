#!/usr/bin/env python3
"""One-shot test harness for the offline runtime.

Cleans up processes, restarts the server, runs a headless CDP capture, and prints
the interesting client-side diagnostics. Exists because deleting logs while the
server holds them open silently loses the output.

  python work/tools/run_test.py [--url U] [--shot P] [--wait MS] [--port N]
                                [--grep PATTERN ...]
"""
import argparse, os, re, subprocess, sys, time

ROOT = r"H:\AI\frog"
RUN = os.path.join(ROOT, "work", "run")
LOGS = os.path.join(RUN, "logs")
SHOT_TOOL = os.path.join(ROOT, "work", "tools", "cdp_shot.js")


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)


def kill_all():
    sh('taskkill /F /IM node.exe /T')
    sh('taskkill /F /IM msedge.exe /T')
    time.sleep(2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080/index.html")
    ap.add_argument("--shot", default=os.path.join(ROOT, "work", "shot_test.png"))
    ap.add_argument("--wait", type=int, default=26000)
    ap.add_argument("--port", type=int, default=9340)
    ap.add_argument("--grep", action="append", default=None)
    ap.add_argument("--env", action="append", default=None,
                    help="extra env for the server, e.g. --env FROG_TRAVEL_MIN=8")
    ap.add_argument("--fresh", action="store_true", help="delete save.json first")
    args = ap.parse_args()

    kill_all()
    for f in os.listdir(LOGS) if os.path.isdir(LOGS) else []:
        try:
            os.remove(os.path.join(LOGS, f))
        except OSError:
            pass
    if args.fresh:
        try:
            os.remove(os.path.join(RUN, "save", "save.json"))
        except OSError:
            pass

    env = dict(os.environ)
    for kv in (args.env or []):
        k, _, v = kv.partition("=")
        env[k] = v

    creationflags = 0x00000008 | 0x08000000  # DETACHED_PROCESS | CREATE_NO_WINDOW
    subprocess.Popen(["node", "server\\main.js", "--port", "8080"], cwd=RUN, env=env,
                     creationflags=creationflags,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)

    if os.path.exists(args.shot):
        os.remove(args.shot)
    r = sh(f'node "{SHOT_TOOL}" --url "{args.url}" --out "{args.shot}" '
           f'--wait {args.wait} --port {args.port}')
    print(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "(no shot output)")
    if r.returncode:
        print("cdp stderr:", r.stderr.strip()[:400])
    if os.path.exists(args.shot):
        print(f"shot: {os.path.getsize(args.shot)} bytes")

    pats = args.grep or [r"\[view", r"\[res\]", r"\[tree-error\]", r"\[view-error\]",
                         r"window\.onerror", r"unhandledrejection"]
    log = os.path.join(LOGS, "client.log")
    if not os.path.exists(log):
        print("!! no client.log (server may not have started)")
        return 1
    txt = open(log, encoding="utf8", errors="replace").read()
    print(f"client.log: {len(txt)} chars")
    for p in pats:
        hits = [m.start() for m in re.finditer(p, txt)]
        if not hits:
            continue
        print(f"\n--- {p} ({len(hits)}) ---")
        for off in hits[:2]:
            print(txt[off:off + 900])
    return 0


if __name__ == "__main__":
    sys.exit(main())
