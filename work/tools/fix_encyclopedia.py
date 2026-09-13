#!/usr/bin/env python3
"""百科: a flower the frog brings home unlocks its entry too.

The decoration table's rows carry `desc_handbook` ("堇菜科/堇菜属 粉白色系角堇") and their
`icon` is the SAME string as the encyclopedia row for that species+variant
(decoration 10011 角堇·火龙果 -> icon_chahua_zhongzhi_jiaojin_1 == encyclopedia 1010101's
icon). Only the flowerpot's `grown` list fed encyclopediaPayload before, so a player who
merely travelled and collected flowers saw the whole 百科 as 未收集.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

P = str(PROJECT_ROOT) + "/work/run/engine/index.js"
src = io.open(P, encoding="utf-8").read()
edits = []


def sub(old, new, label):
    global src
    n = src.count(old)
    assert n == 1, "%s: expected 1 match, found %d" % (label, n)
    src = src.replace(old, new)
    edits.append(label)


sub("""  function encyclopediaRowForPlant(plantId) {
    const table = ((gamedata.tables || {}).flowerpotData || {}).plant || {};
    const p = table[String(plantId)];
    return p ? ENC_BY_NAME.get(p.name) : undefined;
  }""",
    """  function encyclopediaRowForPlant(plantId) {
    const table = ((gamedata.tables || {}).flowerpotData || {}).plant || {};
    const p = table[String(plantId)];
    return p ? ENC_BY_NAME.get(p.name) : undefined;
  }

  /* The flowers the frog brings home are `decoration` rows, and their `icon` is the very
     same string as the encyclopedia row for that species + variant (decoration 10011
     角堇·火龙果 carries icon_chahua_zhongzhi_jiaojin_1, which is exactly what
     encyclopedia 1010101 uses). The rows even ship a `desc_handbook`. So a flower from a
     trip unlocks its 百科 entry just like one grown in the pot -- without this, a player
     who only travelled saw every entry as 未收集. */
  function encyclopediaRowForDecoration(decId) {
    const d = DECORATIONS[String(decId)];
    if (!d || !d.icon) return undefined;
    const rows = ENC.list || {};
    for (const k of Object.keys(rows)) {
      const row = rows[k];
      if (!row) continue;
      if (row.icon === d.icon || row.pic_img === d.icon) return row;
    }
    return undefined;
  }""",
    "encyclopediaRowForDecoration")

sub("""  /* Build the three payload fields from the plants actually grown to harvest. */
  function encyclopediaPayload() {
    const grown = state.flowerpot.grown || [];
    const ids = [];
    const desc = [];
    const show = [];
    const seen = new Set();
    for (const pid of grown) {
      const e = encyclopediaRowForPlant(pid);
      if (!e || seen.has(Number(pid))) continue;
      seen.add(Number(pid));""",
    """  /* Build the three payload fields from everything the player has actually grown or
     been given: the flowerpot's harvests AND the flowers brought home from trips. */
  function encyclopediaPayload() {
    const grown = (state.flowerpot.grown || []).map(
      (pid) => ({ key: 'p' + pid, row: encyclopediaRowForPlant(pid) }));
    const brought = (state.decoration.hasList || []).map(
      (d) => ({ key: 'd' + d.id, row: encyclopediaRowForDecoration(d.id) }));
    const sources = grown.concat(brought);
    const ids = [];
    const desc = [];
    const show = [];
    const seen = new Set();
    for (const src of sources) {
      const pid = src.key;
      const e = src.row;
      if (!e || seen.has(pid)) continue;
      seen.add(pid);""",
    "encyclopediaPayload reads both sources")

io.open(P, "w", encoding="utf-8").write(src)
print("applied:", ", ".join(edits))
