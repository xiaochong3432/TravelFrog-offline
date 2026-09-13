#!/usr/bin/env python3
"""Three museumday refinements from the finished spec (work/spec/museumday.md).

1. mdLootDesc used `(museum-1)*100 + 1..5`, but only the 1..5 and 101..105 rows are
   "picked something up" text (「得到了{0}个{1}」). Rows 201..205 are flavour with no
   placeholders and 301..305 name a specific museum and ticket, so museums 3 and 4 were
   getting nonsense log lines.
2. The arrival ticket gets the row that is literally about that ticket (301..304 are the
   four museums' ticket texts, in the same order as items 1017..1020).
3. `end_time` was `now + 20d` re-rolled on EVERY load, and the client keys its
   `museumDay_popup` cookie on `String(end_time)` -- so the invitation popup re-fired on
   every single tap. Pinning it to the next day boundary keeps it ~20 days out (the
   client arms `setTimeout(1000*(end_time-now+1))`, which must stay inside int32) while
   making the value stable for a whole day.
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


sub("""  const base = (museumId - 1) * 100;
  let row = MD_DESC_ROWS[String(base + randInt(1, 5))];
  if (!row) row = MD_DESC_ROWS[String(randInt(1, 5))];""",
    """  /* Only 1..5 and 101..105 are "picked something up" rows (both read
     「得到了{0}个{1}」). 201..205 are flavour with NO placeholders and 301..305 name a
     specific museum + ticket, so neither may describe a generic item find. */
  const base = Number(museumId) % 2 === 0 ? 100 : 0;
  const row = MD_DESC_ROWS[String(base + randInt(1, 5))];""",
    "loot description family")

sub("""  const ticket = MD_TICKET_IDS[s.curMuseum];
  if (ticket) grantItem(ctx, ticket, 1);""",
    """  const ticket = MD_TICKET_IDS[s.curMuseum];
  if (ticket) {
    grantItem(ctx, ticket, 1);
    /* 301..304 are literally "…获得了1张<museum>门票", one per museum in the same order
       as the ticket items, so this line matches exactly what was just granted. */
    const line = MD_DESC_ROWS[String(300 + Number(s.curMuseum))];
    if (typeof line === 'string') {
      s.logList.push({ desc: line, item_id: ticket, item_num: 1, time: nowSec() });
    }
  }""",
    "arrival ticket log line")

sub("""function cardEnd() {
  return nowSec() + CARD_ROLL_DAYS * 86400;
}""",
    """function cardEnd() {
  return nowSec() + CARD_ROLL_DAYS * 86400;
}

/** museumday's window, pinned to the NEXT DAY BOUNDARY + MD_ROLL_DAYS.
    The client stores its `museumDay_popup` cookie keyed on String(end_time), so a value
    that changed on every load re-showed the invitation on every tap; rounding to the
    day keeps it stable while staying inside the int32 limit the close timer implies. */
function mdEnd() {
  const now = nowSec();
  const nextDay = now - (now % 86400) + 86400;
  return nextDay + (MD_ROLL_DAYS - 1) * 86400;
}""",
    "day-stable mdEnd helper")

sub("      s.endTime = nowSec() + MD_ROLL_DAYS * 86400;", "      s.endTime = mdEnd();",
    "museumday_load uses mdEnd")

io.open(P, "w", encoding="utf-8").write(src)
print("applied:", ", ".join(edits))
