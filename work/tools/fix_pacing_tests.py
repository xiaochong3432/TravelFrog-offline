#!/usr/bin/env python3
"""Update the tests that assert the old pacing / auto-departure behaviour.

The engine now WAITS while the bag is empty (players reported the frog leaving with
nothing prepared), and the offline travel window is 12-40 minutes instead of 90-240 s.
Every test that expects a departure therefore has to pack something first -- which is
also what the new contract says.
"""
import io

T = r"H:\AI\frog\work\tools\engine_test.js"
src = io.open(T, encoding="utf-8").read()
edits = []


def sub(old, new, label):
    global src
    n = src.count(old)
    assert n == 1, "%s: expected 1 match, found %d" % (label, n)
    src = src.replace(old, new)
    edits.append(label)


# a shared helper, next to idsOfType
sub("""function test(name, fn) {""",
    """/** 没准备就不出门 (see the engine's note): a trip only happens with a packed bag. */
function packForTrip(engine, itemId) {
  const id = itemId === undefined ? idsOfType(0)[0] : itemId;
  engine.state.items.bag[0] = id;
  return id;
}

function test(name, fn) {""",
    "packForTrip helper")

# 1. departure
sub("""test('travel: departure flips status to away and pushes an event', ({ engine }) => {
  eq(engine.state.frog.status, 0, 'should start at home');
  engine.state.travel.nextDepartAt = 1;          // long past -> departs on next tick""",
    """test('travel: departure flips status to away and pushes an event', ({ engine }) => {
  eq(engine.state.frog.status, 0, 'should start at home');
  packForTrip(engine);                           // 没准备就不出门
  engine.state.travel.nextDepartAt = 1;          // long past -> departs on next tick""",
    "departure test packs first")

# 2. return
sub("""test('travel: returning home restores status and pays rewards', ({ engine, savePath }) => {
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  const cloverBefore = engine.state.clover;""",
    """test('travel: returning home restores status and pays rewards', ({ engine, savePath }) => {
  packForTrip(engine);                           // 没准备就不出门
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  const cloverBefore = engine.state.clover;""",
    "return test packs first")

# 3. stray: pack a TOOL (no lunch box), re-packed each loop because the bag empties
sub("""  const specBefore = engine.state.specialtys.length;
  const picBefore = engine.state.pictures.length;
  for (let i = 0; i < 20; i++) {
    engine.state.travel.nextDepartAt = 1;
    engine.tick();""",
    """  const specBefore = engine.state.specialtys.length;
  const picBefore = engine.state.pictures.length;
  /* A stray trip is one WITHOUT a lunch box, so the bag still has to hold something --
     the departure rule is "nothing packed, stay home". A tool keeps it prepared and
     still leaves `lunch === -1`. The bag is emptied by each departure, so re-pack. */
  const tool = idsOfType(2)[0];
  for (let i = 0; i < 20; i++) {
    packForTrip(engine, tool);
    engine.state.travel.nextDepartAt = 1;
    engine.tick();""",
    "stray test packs a tool each loop")

# 4. tasks: re-pack each loop
sub("""  engine.state.items.bag[0] = idsOfType(0)[0];
  for (let i = 0; i < 3; i++) {
    engine.state.travel.nextDepartAt = 1;
    engine.tick();""",
    """  for (let i = 0; i < 3; i++) {
    packForTrip(engine);                         // the bag is emptied by every departure
    engine.state.travel.nextDepartAt = 1;
    engine.tick();""",
    "task progress test re-packs each loop")

# 5. the offline window
sub("""  assert(w >= 90 && w <= 240,
    `offline travel window ${w}s must stay inside 90..240 (faithful mode is opt-in via FROG_FAITHFUL=1)`);""",
    """  /* 12..40 minutes: players reported the old 90-240 s as "a bit fast". Faithful mode
     (FROG_FAITHFUL=1) still gives the recovered 60 min..6 h. */
  assert(w >= 12 * 60 && w <= 40 * 60,
    `offline travel window ${w}s must stay inside 12..40 min (faithful mode is opt-in via FROG_FAITHFUL=1)`);""",
    "offline window assertion")

# 6. stray window: needs a packed non-lunch item
sub("""  // a trip with no lunch box is a 放浪, which the table says returns in 10-20
  engine.state.items.bag = [-1, -1, -1, -1];
  engine.state.travel.plan = null;""",
    """  // a trip with no lunch box is a 放浪, which the table says returns in 10-20
  engine.state.items.bag = [-1, -1, -1, -1];
  packForTrip(engine, idsOfType(2)[0]);          // prepared, but with no lunch box
  engine.state.travel.plan = null;""",
    "stray window test packs a tool")

io.open(T, "w", encoding="utf-8").write(src)
print("applied:", ", ".join(edits))
