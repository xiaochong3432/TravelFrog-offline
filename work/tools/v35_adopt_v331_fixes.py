#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""吸收 V3.3.1.apk.1 里的改动到我们的 V3.5。

V3.3.1 的构成（实测）：
  · 外壳 = 上游 3.4 的外壳（逐字节）
  · 原生 = 上游 3.4 的原生（dex 24488 B，18763 主源）
  · 载荷资源 = 我们的（4661 项，无 __migrate.html、无广告视频）
  · 客户端 = 上游 3.4 客户端 + 5 处改动
  · 引擎   = 上游 3.4 引擎 + 1 处改动（扭蛋奖励 id 清理）

我们的 V3.5 客户端与上游 3.4 客户端逐字节相同，所以那 5 处改动可以按"整行替换"精确施加。
本脚本默认只吸收 3 处明确是修复的改动（foldMenu 守卫、家具商店过滤、扭蛋奖励清理），
把三处"红灯置 0"留给人工决定（EDIT_SELECTION 里打开即可）。
"""
import pathlib
import re
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



BASE_CLIENT = _upstream34("client_main.min.js",
                          ROOT / "git-repo/work/run/web/js/main.min.js")   # 上游 3.4 客户端
V331_CLIENT = ROOT / "work/build/v331/client.js"                 # V3.3.1 的客户端
OUT_CLIENT = ROOT / "work/build/v4_client/main.min.js"           # 我们打补丁后的客户端
ENGINE = ROOT / "work/build/v4_engine/index.js"                  # 我们的引擎（上游 3.4 + 我们的东西）

# 客户端的 5 处改动按"上游的第几行"定位（1-based）
EDIT_SELECTION = {
    4: True,     # 工作台红灯：改成恒定 0（关掉红点）           —— 一并吸收（用户决定）
    5: True,     # GuideTaskModel 的 redotMap：全部置 0          —— 一并吸收
    7: True,     # 新笔记红灯：改成恒定 0                        —— 一并吸收
    19: True,    # 家具商店列表过滤掉 FurnitureShopDB 里没有的行  —— 吸收
    36: True,    # foldMenu 守卫：点到弹窗/通知层时不收菜单      —— 吸收（他说的动画优化）
}

base = BASE_CLIENT.read_bytes().decode("utf-8").split("\n")
v331 = V331_CLIENT.read_bytes().decode("utf-8").split("\n")
if len(base) != len(v331):
    sys.exit("两份客户端的行数不同（%d vs %d），不能按行替换" % (len(base), len(v331)))

out = list(base)
applied = []
for line_no, take in EDIT_SELECTION.items():
    i = line_no - 1
    if base[i] == v331[i]:
        sys.exit("第 %d 行两边相同，说明定位错了" % line_no)
    if take:
        out[i] = v331[i]
        applied.append(line_no)
print("客户端：吸收第 %s 行；跳过第 %s 行"
      % (", ".join(map(str, applied)), ", ".join(str(k) for k, v in EDIT_SELECTION.items() if not v)))
OUT_CLIENT.parent.mkdir(parents=True, exist_ok=True)
OUT_CLIENT.write_text("\n".join(out), encoding="utf-8", newline="")

# ------------------------------------------------------------------ 引擎：扭蛋奖励 id 清理（V3.3.1 的两处）
eng = ENGINE.read_bytes().decode("utf-8")
if "只把当前 capsuleData.reward 还认识的奖励 id 发出去" in eng:
    print("引擎：扭蛋奖励清理已经在里面了，跳过")
else:
    anchor = "      reward_list: (C.rewardList || []).map((r) => Number(r)),"
    if eng.count(anchor) != 1:
        sys.exit("引擎锚点1出现 %d 次" % eng.count(anchor))
    eng = eng.replace(anchor, """      /* 只把当前 capsuleData.reward 还认识的奖励 id 发出去（取自 V3.3.1 的修复）：
         旧表有 30 个键，旧存档抽到的 108/109/110/209/311 这些已被删掉的 id 会让客户端的
         capsuleData.get("reward")[id] 拿到 undefined，接着读 `.type` 直接抛错 ——
         表现就是"扭蛋机打不开"。发送侧过滤 + 下面读档侧清理，两头都堵住。 */
      reward_list: (C.rewardList || [])
        .map((r) => Number(r))
        .filter((r) => CAPSULE_REWARD[String(r)]),""", 1)

    anchor2 = """  function refreshCapsule(t) {
    const C = state.capsule;
    C.endTime = t + CAPSULE_DAYS * 86400;"""
    if eng.count(anchor2) != 1:
        sys.exit("引擎锚点2出现 %d 次" % eng.count(anchor2))
    eng = eng.replace(anchor2, """  function refreshCapsule(t) {
    const C = state.capsule;
    /* 旧存档里可能留着当前表已经删掉的抽奖奖励 id（108/109/110/209/311）：它们只是历史
       （东西早发过了），读档时清干净，免得客户端渲染扭蛋页时抛错。取自 V3.3.1 的修复。 */
    if (Array.isArray(C.rewardList)) {
      const valid = C.rewardList.filter((r) => CAPSULE_REWARD[String(Number(r))]);
      if (valid.length !== C.rewardList.length) { C.rewardList = valid; }
    }
    C.endTime = t + CAPSULE_DAYS * 86400;""", 1)
    ENGINE.write_text(eng, encoding="utf-8", newline="")
    print("引擎：已加入扭蛋奖励清理（发送侧 + refreshCapsule 读档侧）")

print("写出：%s" % OUT_CLIENT.relative_to(ROOT))
