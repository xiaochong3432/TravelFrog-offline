#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Re-render the Help panel's 客服 button texture with the label 制作人员.

The button is an `eui.Image` whose art is button_02_png -- the label is DRAWN INTO the
image (the theme proves it: `_proto.btn_customer_i` is `new eui.Image(); t.source =
"button_02_png"`), and that texture is referenced exactly once in the whole theme, so
replacing it changes only this one button and needs no code change at all.

The original is a flat white pill with a thin olive border and dark olive heavy type, so
the text area can be cleared back to the flat background and redrawn faithfully. Every
measurement is taken from the original image rather than assumed:

Usage: python tools/patch_help_button.py <in.png> <out.png> [text]
"""
import sys
from collections import Counter

from PIL import Image, ImageDraw, ImageFont

FONT_CANDIDATES = [
    (r"C:\Windows\Fonts\msyhbd.ttc", 0),      # Microsoft YaHei Bold
    (r"C:\Windows\Fonts\msyh.ttc", 0),
    (r"C:\Windows\Fonts\simhei.ttf", 0),
    (r"C:\Windows\Fonts\Dengb.ttf", 0),       # DengXian Bold
]


def modal_color(im, box):
    px = im.convert("RGB").crop(box)
    return Counter(px.getdata()).most_common(1)[0][0]


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def main():
    src, dst = sys.argv[1], sys.argv[2]
    text = sys.argv[3] if len(sys.argv) > 3 else '制作人员'

    im = Image.open(src).convert("RGBA")
    w, h = im.size
    bg = modal_color(im, (8, 8, w - 8, h - 8))

    # The pill's BORDER is the same olive tone as the text, so the search window has to stay
    # well inside it -- my first attempt treated the border as text and cleared it away.
    sx0, sx1 = int(w * 0.12), int(w * 0.88)
    sy0, sy1 = int(h * 0.20), int(h * 0.80)

    xs, ys, dark = [], [], []
    for y in range(sy0, sy1):
        for x in range(sx0, sx1):
            p = im.getpixel((x, y))
            if p[3] < 200:
                continue
            if dist(p[:3], bg) > 60:
                xs.append(x)
                ys.append(y)
                dark.append(p[:3])
    if not xs:
        raise SystemExit("no text pixels found in the inner window -- wrong texture?")
    box = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
    text_color = Counter(dark).most_common(1)[0][0]
    print("image %dx%d  bg=%s  text=%s  search window=(%d,%d,%d,%d)"
          % (w, h, bg, text_color, sx0, sy0, sx1, sy1))
    print("original label box=%s (h=%d, w=%d)" % (box, box[3] - box[1], box[2] - box[0]))

    # clear the old label: a flat fill matches the original background exactly
    pad = 6
    clear = (max(0, box[0] - pad), max(0, box[1] - pad),
             min(w, box[2] + pad), min(h, box[3] + pad))
    d = ImageDraw.Draw(im)
    d.rectangle(clear, fill=bg + (255,))
    print("cleared %s with the background colour" % (clear,))

    target_h = box[3] - box[1]
    target_w = box[2] - box[0]
    avail_w = w - 40

    font = None
    best = None
    for path, index in FONT_CANDIDATES:
        try:
            f = ImageFont.truetype(path, 20, index=index)
        except Exception as e:
            print("  font unavailable %s (%s)" % (path, e))
            continue
        # find the size whose ink height matches the original
        lo, hi, chosen = 8, 90, None
        while lo <= hi:
            mid = (lo + hi) // 2
            f = ImageFont.truetype(path, mid, index=index)
            b = d.textbbox((0, 0), text, font=f)
            hh = b[3] - b[1]
            if hh < target_h:
                lo = mid + 1
            else:
                hi = mid - 1
        f = ImageFont.truetype(path, max(8, lo), index=index)
        b = d.textbbox((0, 0), text, font=f)
        score = abs((b[3] - b[1]) - target_h) + abs((b[2] - b[0]) - target_w) * 0.3
        print("  %s size=%d -> ink %dx%d (target %dx%d) score=%.1f"
              % (path, max(8, lo), b[2] - b[0], b[3] - b[1], target_w, target_h, score))
        if best is None or score < best[0]:
            best = (score, f, path)
    if best is None:
        raise SystemExit("no usable CJK font found")

    font = best[1]
    print("using %s" % best[2])

    # centre the new label on the OLD label's centre, so the button layout is untouched
    cx = (box[0] + box[2]) / 2.0
    cy = (box[1] + box[3]) / 2.0
    b = d.textbbox((0, 0), text, font=font)
    tw, th = b[2] - b[0], b[3] - b[1]
    if tw > avail_w:
        # shrink until it fits
        size = font.size
        while tw > avail_w and size > 8:
            size -= 1
            font = ImageFont.truetype(best[2], size)
            b = d.textbbox((0, 0), text, font=font)
            tw, th = b[2] - b[0], b[3] - b[1]
        print("shrunk to size %d to fit %dpx" % (size, avail_w))
    x = cx - tw / 2.0 - b[0]
    y = cy - th / 2.0 - b[1]
    d.text((x, y), text, font=font, fill=text_color + (255,))
    print("drew %r at (%.1f, %.1f) ink %dx%d" % (text, x, y, tw, th))

    im.save(dst)
    print("wrote %s" % dst)


main()
