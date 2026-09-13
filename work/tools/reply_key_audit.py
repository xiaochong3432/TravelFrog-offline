#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""REPLY-KEY AUDIT: for every command, which payload keys does the client's handler read,
and which of those does our reply not carry?

Motivation: we shipped two bugs of exactly this shape -- the 百科 payload (species ids
where the client indexes the table with long_ids) and album_load_by_id_list (we sent
`pictures`, the client reads `pic_list`). Both survived unit tests that only checked
"a reply came back". A missing key makes the client silently skip a branch, so it shows
up as a blank page rather than an error.

Usage: python tools/reply_key_audit.py
       (run tools/dump_reply_keys.js first)
"""
import io
import json
import os
import re

ROOT = r"H:\AI\frog\work"
CLIENT = os.path.join(ROOT, "run", "web", "js", "main.min.js")
KEYS = os.path.join(ROOT, "logs", "reply_keys.json")
OUT = os.path.join(ROOT, "logs", "reply_key_audit.txt")

# keys that are never payload fields we owe the client
IGNORE = {
    # the reply envelope
    "code", "data", "msg",
    # locals that shadow the parameter name in minified code
    "length", "push", "type", "index", "name", "id",
    "prototype", "call", "apply", "constructor", "parent", "numChildren",
    "addEventListener", "dispatchEvent", "forEach", "map", "filter", "concat",
    "indexOf", "toString", "slice", "shift", "sort", "join", "splice",
    "hasOwnProperty", "selectedIndex", "visible", "width", "height", "text",
}
# keys the client reads that come from a LOCAL model, not from our reply
LOCAL_HINTS = ("data", "list", "info", "getModel", "target", "currentTarget")
# In the minified bundle the module alias for `core` is very often also `e`, so
# `e.Event`, `e.Time`, `e.PageManage` … are core members, not payload fields. Any
# capitalised name is treated as a class/constant, never as a payload key.
CORE_MEMBERS = {
    "Event", "Time", "Log", "PageManage", "DisplayManage", "ViewLayerType",
    "SocketManage", "ModelManage", "String", "MathExtend", "Action", "Action1",
    "Action2", "EventType", "PathManage", "RemoveViewType", "UIView",
}

text = io.open(CLIENT, encoding="utf-8", errors="replace").read()
engine = json.load(io.open(KEYS, encoding="utf-8"))

out = io.open(OUT, "w", encoding="utf-8")
suspicious = []
no_handler = []
not_object = []

HANDLER = re.compile(r'\.prototype\.([A-Za-z_][\w]*)=function\(([A-Za-z_$][\w$]*)')

for cmd in sorted(engine):
    # the client's own handler is keyed by the UNDERSCORE name
    m = re.search(re.escape(".prototype.%s=function(" % cmd) + r'([A-Za-z_$][\w$]*)', text)
    if not m:
        no_handler.append(cmd)
        continue
    start = m.end()
    nxt = text.find(".prototype.", start)
    body = text[start:start + (nxt - start if nxt > 0 and nxt - start < 1500 else 1500)]
    param = m.group(1)
    read = set()
    # a word boundary matters: without it `TravelEventType.updateAlbum` matches as
    # `e.updateAlbum` (the trailing `e` of `...Type`) and floods the report.
    for km in re.finditer(r'(?<![\w$])' + re.escape(param) + r'\.([A-Za-z_][\w]*)', body):
        read.add(km.group(1))
    info = engine[cmd]
    if info.get("reply") == "object":
        have = set(info.get("keys") or [])
    else:
        have = set()
        if info.get("reply") not in (None,):
            not_object.append((cmd, info.get("reply")))
    missing = sorted(k for k in read - have
                     if k not in IGNORE and k not in CORE_MEMBERS
                     and not k.startswith("get") and not k[:1].isupper())
    if missing and info.get("reply") == "object":
        suspicious.append((cmd, missing, sorted(have), body))

out.write("commands in protocol: %d\n" % len(engine))
out.write("no client handler found: %d  %r\n" % (len(no_handler), no_handler[:40]))
out.write("\n=== replies that are not an object (client reads keys from them?)\n")
for cmd, kind in not_object:
    i = engine[cmd]
    if i.get("reply") not in ("undefined",):
        out.write("  %-32s reply=%s keys=%r\n" % (cmd, kind, i.get("keys")))

out.write("\n=== SUSPICIOUS: client reads keys our reply does not carry (%d)\n" % len(suspicious))
for cmd, missing, have, body in suspicious:
    out.write("\n  %-32s reads %-34r our keys %r\n" % (cmd, missing, have))
    out.write("      handler: %s\n" % body[:260].replace("\n", " "))
out.close()
print("wrote %s : %d suspicious" % (OUT, len(suspicious)))
