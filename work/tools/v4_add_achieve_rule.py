#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4 引擎：补回我们那条「典藏（博物馆）」称号判定规则。

上游 3.4 的成就谓词里少一条：Achieve.json 的四行（获得 4/8/12/20 个典藏）只有文案、
没有判定 —— 我们这条线给它写了谓词，3.4 没带上。补回去，位置与我们的引擎一致。
"""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parents[2]
OURS = ROOT / "work/build/merged_v31/index.js"
V4 = ROOT / "work/build/v4_engine/index.js"

block = None
ours = OURS.read_text(encoding="utf-8").split("\n")
for i, l in enumerate(ours):
    if "典藏（博物馆）数量" in l:
        # 从注释行取到配对的 `}`（不能按固定行数切，容易漏掉收尾括号）
        depth, seen = 0, False
        for j in range(i, i + 20):
            depth += ours[j].count("{") - ours[j].count("}")
            if "{" in ours[j]:
                seen = True
            if seen and depth == 0:
                block = ours[i:j + 1]
                break
        break
if block is None:
    sys.exit("找不到我们的典藏判定块")
print("取到我们的典藏规则 %d 行：%s" % (len(block), block[-1].strip()))

text = V4.read_text(encoding="utf-8")
if "典藏（博物馆）数量" in text:
    print("V4 引擎里已经有这条规则，跳过")
    sys.exit(0)
anchor = "    if ((m = /^(.+?)超过(\\d+)个$/.exec(info))) {"
if text.count(anchor) != 1:
    sys.exit("锚点出现 %d 次" % text.count(anchor))
text = text.replace(anchor, "\n".join(block) + "\n" + anchor, 1)
V4.write_text(text, encoding="utf-8", newline="")
print("已把典藏规则插进 %s（现 %d 行）" % (V4.relative_to(ROOT), len(text.split("\n"))))
