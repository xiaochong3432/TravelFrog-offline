#!/usr/bin/env python3
"""Make packForTrip self-contained (it runs before idsOfType is defined)."""
import io

T = r"H:\AI\frog\work\tools\engine_test.js"
src = io.open(T, encoding="utf-8").read()
old = """/** 没准备就不出门 (see the engine's note): a trip only happens with a packed bag. */
function packForTrip(engine, itemId) {
  const id = itemId === undefined ? idsOfType(0)[0] : itemId;
  engine.state.items.bag[0] = id;
  return id;
}"""
new = """/** 没准备就不出门 (see the engine's note): a trip only happens with a packed bag.
    Reads the table directly, because the early travel tests run before `idsOfType`. */
function packForTrip(engine, itemId) {
  let id = itemId;
  if (id === undefined) {
    const gd = JSON.parse(fs.readFileSync(
      path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
    id = gd.items.find((i) => i.type === 0).id;          // 0 = LunchBox
  }
  engine.state.items.bag[0] = id;
  return id;
}"""
assert src.count(old) == 1, "helper not found"
io.open(T, "w", encoding="utf-8").write(src.replace(old, new))
print("packForTrip is now self-contained")
