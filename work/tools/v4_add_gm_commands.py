#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4 引擎：把上游 3.4 落下的我们这三条 gm 命令补回去。

  unlock_map      - 解锁全部足迹（离线版自制足迹页的 33 个省区）
  unlock_achieve  - 解锁全部称号
  anim_kit        - 动态照片材料补给（相框/存储券/三种显影液 + 可动明信片各 5 份）

上游 3.4 的 gm 命令表里没有这三条，而我们的外壳面板有对应按钮 —— 不补就是"点了没反应"。
三个 case 块从 work/build/merged_v31/index.js 原样取出，插到上游 `case 'unlock_museum'` 之后。
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parents[2]
OURS = ROOT / "work/build/merged_v31/index.js"
V4 = ROOT / "work/build/v4_engine/index.js"

our = OURS.read_text(encoding="utf-8").split("\n")
v4 = V4.read_text(encoding="utf-8")


def case_block(name):
    """取出我们引擎里 `case 'name': {` 到配对的 `}` 之间的行。"""
    start = None
    for i, l in enumerate(our):
        if l.strip().startswith("case '%s':" % name):
            start = i
            break
    if start is None:
        sys.exit("找不到我们的 case %s" % name)
    depth = 0
    seen = False
    for j in range(start, len(our)):
        depth += our[j].count("{") - our[j].count("}")
        if "{" in our[j]:
            seen = True
        if seen and depth == 0:
            return our[start:j + 1]
    sys.exit("case %s 的花括号不平衡" % name)


blocks = {n: case_block(n) for n in ("unlock_map", "unlock_achieve", "anim_kit")}
for n, b in blocks.items():
    print("%-16s %d 行：%s" % (n, len(b), b[0].strip()))

# 插在 case 'unlock_museum' 之后
anchor = "      case 'unlock_museum': {"
idx = v4.find(anchor)
if idx < 0:
    sys.exit("V4 引擎里找不到 unlock_museum 锚点")
# 找这个 case 的收尾
sub = v4[idx:]
depth = 0
end = None
for m in re.finditer(r"[{}]", sub):
    depth += 1 if m.group(0) == "{" else -1
    if depth == 0:
        end = idx + m.end()
        break
if end is None:
    sys.exit("unlock_museum 的块没闭合")
insert = "\n".join(
    ["", "      /* ---- 3.4 落下的三条命令，由我们这条线补回（见 docs/修复记录-4.0.md）---- */"]
    + ["      /* %s */" % w for w in (
        "解锁全部足迹：离线版自制「足迹页」(map.html) 按 state.acquireProvinces 标已认识，",
        "这里把访客表里的 33 个省区一次性发全，不发明任何地理数据。",
        "解锁全部称号：按 ACHIEVE_RULES 逐条判定，没有规则的行如实说明。",
        "动态照片材料：正式服靠「家具店买耗材 + 反复旅行攒同款明信片」，离线凑不齐，",
        "所以这条命令把 9001/9002/8002/8003/8004 与可动明信片副本一起给。")]
    + [""])
v4 = (v4[:end] + "\n" + insert
      + "\n".join(blocks["unlock_map"]) + "\n\n"
      + "\n".join(blocks["unlock_achieve"]) + "\n\n"
      + "\n".join(blocks["anim_kit"]) + "\n"
      + v4[end:])

# 帮助清单：按"包含 unlock_museum - "的那一行"定位，插在它后面
hlines = v4.split("\n")
hi = [i for i, l in enumerate(hlines) if "unlock_museum - " in l]
if len(hi) != 1:
    sys.exit("V4 引擎里 unlock_museum 的帮助行有 %d 行" % len(hi))
added = [
    "        'unlock_map - 解锁全部足迹（离线版自制足迹页的 33 个省区）',",
    "        'unlock_achieve - 解锁全部称号（成就；引擎判不了的会如实说明）',",
    "        'anim_kit - 动态照片材料补给（相框/存储券/三种显影液 + 可动明信片各 5 份）',",
]
hlines[hi[0] + 1:hi[0] + 1] = added
v4 = "\n".join(hlines)

V4.write_text(v4, encoding="utf-8", newline="")
print("写出 %s（%d 行）" % (V4.relative_to(ROOT), len(v4.split("\n"))))
