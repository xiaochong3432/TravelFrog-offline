#!/usr/bin/env python3
"""Pin the 图鉴 contract: a REAL trip must put ids into state.handbook.

The client renders 纪念品/特产 from two lists that come straight out of
`item_load_handbook`, and marks an entry as collected only when its id is present:

    n = itemModel.getCollectionsList()
    CollectDB.index(o) -> n.indexOf(t.id) >= 0 ? {count: 1} : {count: 0}     // "?"
    SpecialtyDB.index(o) -> n.indexOf(t.itemId) >= 0 ? row : -1              // "?"

and the engine fills those lists ONLY in returnFrog(). A frog that kept leaving with an
unprepared bag always took the 放浪 path, which returns early -- so after a week of play
the 图鉴 could still be entirely "?". That is the reported symptom, and it is fixed by the
departure rule; this test makes sure a normal trip keeps feeding both lists.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

T = str(PROJECT_ROOT) + "/work/tools/engine_test.js"
src = io.open(T, encoding="utf-8").read()
anchor = "/* ------------------------------------------------------------------ done */"
test = """test('handbook: a real trip feeds the two lists the 图鉴 renders from', ({ engine }) => {
  /* 放浪 trips return early and bring nothing, so a player whose frog kept leaving
     unprepared saw every 纪念品/特产 as "?" -- the lists below are exactly what the
     client turns into count:1 vs "?". */
  const hand = () => call(engine, 'item_load_handbook', {}).reply;
  eq(hand().collections.length, 0, 'a fresh save has nothing recorded');
  eq(hand().specialtys.length, 0, 'nor any specialty');

  const lunch = idsOfType(0)[0];
  const before = { cols: 0, spes: 0 };
  for (let i = 0; i < 25; i++) {
    engine.state.items.bag[0] = lunch;           // packed: a normal trip, not 放浪
    engine.state.travel.nextDepartAt = 1;
    engine.tick();
    engine.state.travel.returnAt = 1;
    engine.tick();
    const h = hand();
    before.cols = h.collections.length;
    before.spes = h.specialtys.length;
  }
  assert(before.cols > 0,
    'a provisioned trip must record a collection, or the 图鉴 stays "?" forever');
  assert(before.spes > 0,
    'a provisioned trip must record a specialty too');

  /* Every recorded id has to be a real table row, because the client looks each one up
     (CollectDB.index/SpecialtyDB.index) and prints "?" for anything it cannot resolve. */
  const collectIds = new Set(((GDATA.tables.Collection) || [])
    .map((r) => (typeof r === 'number' ? r : r && r.id)));
  for (const id of hand().collections) {
    assert(collectIds.has(id), `collection ${id} is not in the Collection table`);
  }
  const specIds = new Set(GDATA.items.filter((i) => i.type === 3).map((i) => i.id));
  for (const id of hand().specialtys) {
    assert(specIds.has(id), `specialty ${id} is not a Specialty item`);
  }
});

"""
assert src.count(anchor) == 1
io.open(T, "w", encoding="utf-8").write(src.replace(anchor, test + anchor))
print("handbook test added")
