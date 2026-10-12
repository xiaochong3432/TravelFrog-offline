#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4 引擎：以他们 3.4 的 index.js 为基线，补回我们那段 V3 老档 helper（A0~A3）。

来源
  基线 = git-repo/work/run/engine/index.js（upstream34 = origin/main e25d744，他们 3.4）
  补丁 = work/build/merged_v31/index.js（我们这条线）里的同一段：
         ① loadState 里的 `__legacySlotAccounting` 判定（A2 需要它）
         ② “MERGE: additions grafted from the V3 handover line”整段：
            注释 + getHouseOnlyItemCount / realPictureId / normalizePictureBucket /
            normalizeMails / migrateTripSpecialtysToHouse / debitPackedSlotsOnce + 唯一调用点
输出 = work/build/v4_engine/index.js（数据仍用 work/run/engine/data，即我们的合并表）
"""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parents[2]

def _upstream34(name, fallback):
    """上游 3.4 基线：优先用不可变快照，避免 git-repo 被 PR 改动后污染构建基线。"""
    import os as _os
    import pathlib as _pl
    base = _os.environ.get("FROG_UPSTREAM34") or str(ROOT / "work" / "build" / "upstream34")
    cand = _pl.Path(base) / name
    return cand if cand.exists() else fallback


OURS = ROOT / "work/build/merged_v31/index.js"
BASE = _upstream34("engine_index.js", ROOT / "git-repo/work/run/engine/index.js")
OUT = ROOT / "work/build/v4_engine/index.js"


def lines(p):
    return p.read_text(encoding="utf-8").split("\n")


our = lines(OURS)
base = lines(BASE)

# ---------------------------------------------------------------- ① 取我们那段 graft 块
start = None
for i, l in enumerate(our):
    if l.startswith("  /* ==========================================================================") and "MERGE: additions grafted" in our[i + 1]:
        start = i
        break
if start is None:
    sys.exit("找不到我们的 graft 段起点")
end = None
for j in range(start, len(our)):
    if our[j].startswith("  } catch (e) {") and "V3 addition failed" in our[j + 1]:
        end = j + 3                     # catch 行 + console.warn 行 + 收尾的 `  }`
        break
if end is None:
    sys.exit("找不到我们的 graft 段结束点")
graft = our[start:end]
print("我们的 graft 段：第 %d~%d 行，共 %d 行" % (start + 1, end, len(graft)))

# ---------------------------------------------------------------- ② 取 loadState 的 flag 行
flag = None
for i, l in enumerate(our):
    if "__legacySlotAccounting = !(raw" in l:
        flag = our[i - 4:i + 1]          # 四行注释 + 判定语句
        break
if flag is None:
    sys.exit("找不到 __legacySlotAccounting 判定行")
print("loadState flag 段 %d 行" % len(flag))

# ---------------------------------------------------------------- ③ 插进他们的引擎
text = "\n".join(base)

# ③a flag：插在他们的 shopDailyBought 迁移之后（同一个 raw 语义）
anchor_a = "      if (!(raw.furniture || {}).shopDailyBought) {"
idx_a = text.find(anchor_a)
if idx_a < 0:
    sys.exit("他们引擎里找不到 shopDailyBought 迁移锚点")
# 找到该 if 块的收尾（下一条同缩进的 "      }"）
tail = text.find("\n      }\n", idx_a)
if tail < 0:
    sys.exit("找不到 shopDailyBought 块的收尾")
insert_at = tail + len("\n      }\n")
text = text[:insert_at] + "\n".join(flag) + "\n" + text[insert_at:]
print("已插入 loadState flag")

# ③b graft 块：插在“V3.1 自己的杂物归位”之后（与我们的相对位置一致）
anchor_b = "  for (const row of misplaced) placeBack(row.id, row.slot, row.from);"
n_b = text.count(anchor_b)
if n_b != 1:
    sys.exit("他们引擎里 placeBack 锚点出现 %d 次" % n_b)
idx_b = text.find(anchor_b)
eol = text.find("\n", idx_b) + 1
text = text[:eol] + "\n" + "\n".join(graft) + "\n" + text[eol:]
print("已插入 graft 块")

# ③c A0：幽灵 id（Item.json 不认识的 id）在"错位归置"之前先清掉
a0_start = None
for i, l in enumerate(our):
    if "/* A0 (merge): a slot holding an id Item.json does not know" in l:
        a0_start = i - 0
        break
if a0_start is None:
    sys.exit("找不到 A0 幽灵 id 块")
a0_end = None
for j in range(a0_start, a0_start + 30):
    if our[j].strip() == "}":
        a0_end = j + 1
        break
if a0_end is None:
    sys.exit("A0 块没闭合")
a0 = our[a0_start:a0_end]
anchor_c = "  const misplaced = [];"
n_c = text.count(anchor_c)
if n_c != 1:
    sys.exit("他们引擎里 misplaced 锚点出现 %d 次" % n_c)
text = text.replace(anchor_c, "\n".join(a0) + "\n\n" + anchor_c, 1)
print("已插入 A0 幽灵 id 清理块（%d 行）" % len(a0))

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(text, encoding="utf-8", newline="")
print("写出 %s（%d 行，%d 字节）" % (OUT.relative_to(ROOT), len(text.split("\n")), len(text.encode('utf-8'))))
