#!/usr/bin/env python3
"""Dump client handler bodies for named protocol messages -> readable reference.

Usage: dump_handlers.py out.txt cmd1 cmd2 ...
Writes each `prototype.<cmd>=function ... }` body, brace-balanced, lightly wrapped.
"""
import re, sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

BOOT = [
    # login phase
    "client_hello", "hall_gen_token", "hall_login", "hall_enter_game",
    "client_load_role", "notify_reload",
    # main-scene loads
    "client_load_decorate", "clover_load_clovers", "clover_update",
    "item_load_items", "item_load_shop_info", "item_load_handbook",
    "item_update", "item_update_ticket",
    "travel_load_note", "travel_load_gift", "album_load",
    "guest_load", "guest_load_drawing", "mail_load", "mail_load_mails",
    "task_load", "task_load_list", "furniture_load_furniture",
    "furniture_load_flowerpot", "furniture_load_compost", "furniture_load_pocket",
    "furniture_load_tumbler", "weather_load", "visit_load",
    "clover_notice_get", "client_load_events", "client_notice",
    "story_load", "encyclopedia_load", "lottery_load", "rank_load",
    "wishingpool_load", "calendar_load", "misc_moment_load", "other_load_touch",
    "share_load", "museum_load", "easteregg_load", "animpicture_load",
    "pray_load_grays", "capsule_load", "recharge_load", "greetcard_load",
    "springcard_load", "partycake_load", "cooking_load_cooking", "adsmgr_load",
    "item_gift_open", "museumday_load", "museumday_info",
]


def body(name):
    m = re.search(r'prototype\.' + re.escape(name) + r'\s*=\s*function', d)
    if not m:
        return None
    i = d.index("{", m.end() - 1)
    depth = 0
    for j in range(i, len(d)):
        c = d[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return d[m.start():j + 1]
    return None


def wrap(s):
    out, depth = [], 0
    for ch in s:
        if ch in "{":
            depth += 1
            out.append(ch + "\n" + "  " * depth)
        elif ch == "}":
            depth = max(0, depth - 1)
            out.append("\n" + "  " * depth + ch)
        elif ch == ";":
            out.append(ch + "\n" + "  " * depth)
        else:
            out.append(ch)
    return "".join(out)


if __name__ == "__main__":
    out_path = sys.argv[1]
    names = sys.argv[2:] or BOOT
    found, missing = 0, []
    with open(out_path, "w", encoding="utf8") as f:
        for n in names:
            b = body(n)
            if b is None:
                missing.append(n)
                continue
            found += 1
            f.write(f"\n\n{'='*100}\n### {n}   (len={len(b)})\n{'='*100}\n")
            f.write(wrap(b))
    print(f"found {found}/{len(names)}  -> {out_path}")
    if missing:
        print("missing (no handler; probably callback-style):")
        for m in missing:
            print("   ", m)
