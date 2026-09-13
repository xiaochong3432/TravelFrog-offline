#!/usr/bin/env python3
"""Analyze the Egret game bundle: version.json structure + network token census."""
import json, re, sys, collections, os

BASE = r"H:\AI\frog\work\base\assets\game"

def version_json():
    p = os.path.join(BASE, "version.json")
    d = json.load(open(p, encoding="utf8"))
    print("=== version.json ===")
    print("type:", type(d).__name__)
    if isinstance(d, dict):
        for k, v in d.items():
            if isinstance(v, (list, dict)):
                print(f"  {k}: {type(v).__name__} len={len(v)} sample={str(v[:3])[:200] if isinstance(v,list) else str(list(v.items())[:3])[:200]}")
            else:
                print(f"  {k}: {v!r}")
    elif isinstance(d, list):
        print("len:", len(d), "sample:", json.dumps(d[:3], ensure_ascii=False)[:500])

TOKENS = [
    rb"chat-wsclient", rb"friend\.ejoy", rb"gangplank", rb"vortex\.ejoy", rb"trace\.ejoy",
    rb"ali-x3-srv01", rb"launcher\.ejoy", rb"holo\.ejoy", rb"p10075-gangplank",
    rb"lingxigames", rb"aligames", rb"rantu\.com", rb"mmstat",
    rb"wss?://", rb"/api/", rb"api\.", rb"login", rb"Login", rb"token", rb"Token",
    rb"oauth", rb"sign", rb"Sign", rb"encrypt", rb"md5", rb"MD5", rb"aes", rb"AES",
    rb"websocket", rb"WebSocket", rb"XMLHttpRequest", rb"HttpRequest", rb"URLLoader",
    rb"protobuf", rb"protob", rb"msgId", rb"cmdId", rb"proto",
]

def token_census(paths):
    for path in paths:
        data = open(path, "rb").read()
        name = os.path.basename(path)
        print(f"\n=== token census: {name} ({len(data)} bytes) ===")
        for t in TOKENS:
            n = len(re.findall(t, data))
            if n:
                print(f"{n:6d}  {t.decode()}")

def context(path, pattern, width=160, limit=40):
    data = open(path, "rb").read()
    name = os.path.basename(path)
    print(f"\n=== context {pattern!r} in {name} ===")
    for i, m in enumerate(re.finditer(pattern, data)):
        if i >= limit:
            print("  ...more")
            break
        s = max(0, m.start() - width); e = min(len(data), m.end() + width)
        seg = data[s:e].decode("utf8", "replace").replace("\n", " ")
        print(f"[{m.start()}] ...{seg}...")

if __name__ == "__main__":
    version_json()
    js = os.path.join(BASE, "js")
    token_census([os.path.join(js, f) for f in ("main.min.js", "game.min.js", "index.min.js", "ejoySDK.min.js")])
