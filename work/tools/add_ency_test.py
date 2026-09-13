#!/usr/bin/env python3
"""Add a unit test for the decoration-driven 百科 unlock."""
import io

T = r"H:\AI\frog\work\tools\engine_test.js"
src = io.open(T, encoding="utf-8").read()
anchor = "/* ------------------------------------------------------------------ done */"
test = """test('encyclopedia: a flower brought home unlocks its entry, not just a grown one', ({ engine }) => {
  /* decoration rows carry `desc_handbook` and their `icon` equals the encyclopedia row's
     (decoration 10011 角堇·火龙果 -> icon_chahua_zhongzhi_jiaojin_1 == encyclopedia
     1010101). Only the flowerpot's `grown` list used to feed this payload, so a player
     who merely travelled saw the whole 百科 as 未收集. */
  const pay = () => call(engine, 'encyclopedia_load', {}).reply;
  eq(pay().unlock_list.length, 0, 'a fresh save has nothing unlocked');

  const decos = Object.keys(GDATA.tables.decoration || {});
  const withIcon = decos.filter((k) => {
    const d = GDATA.tables.decoration[k];
    return d && d.icon && d.icon.indexOf('chahua_zhongzhi') === 0;
  });
  assert(withIcon.length > 0, 'expected planted-flower decorations in the table');
  const decId = Number(withIcon[0]);
  engine.state.decoration.hasList.push({ id: decId, num: 1 });
  const r = pay();
  assert(r.unlock_list.length > 0,
    'a brought-home flower must unlock an encyclopedia species');
  for (const id of r.unlock_list) {
    const row = r.unlock_desc.find((x) => x.id === id);
    assert(row && row.list.length > 0, `species ${id} needs its description lines`);
  }
  assert(r.show_sub.length > 0 && typeof r.show_sub[0].sub_id === 'number',
    'show_sub picks the variant, so it needs a real sub_id');

  /* and the pot still works */
  const plant = Object.keys(((GDATA.tables.flowerpotData || {}).plant) || {})[0];
  if (plant) {
    engine.state.flowerpot.grown.push(Number(plant));
    assert(pay().unlock_list.length >= r.unlock_list.length,
      'a grown plant must not remove anything');
  }
});

"""
assert src.count(anchor) == 1
io.open(T, "w", encoding="utf-8").write(src.replace(anchor, test + anchor))
print("test added")
