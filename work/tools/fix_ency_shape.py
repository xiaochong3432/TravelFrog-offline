#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fix the 百科 payload shape (the reason an unlocked 百科 page renders blank).

Read off the client's own consumer:
    EncyModel.encyclopedia_load(e):
        data.unlock_list = e.unlock_list                     // used as TABLE keys
        for (n of e.unlock_desc) data.unlock_desc[n.id] = convertArray(n.list)
        for (n of e.show_sub)    data.show_sub[n.id]    = n.sub_id   // also a TABLE key
    EncyView.getItemsByTab(tab): for (k in data.show_sub) { row = TABLE[data.show_sub[k]]; row.tab == tab && push(row) }
    EncyView.getSubItems(id):    for (longId of data.unlock_list) { row = TABLE[longId]; row.id == id && ... }
    EncyView.getPicItems(id, sub): same, keeping row.sub_id == sub
    tab.getChildAt(i).enabled = getItemsByTab(i).length > 0

encyclopedia.list is keyed by long_id, and each row carries id (species), sub_id
(variety), tab (1..4) and pic_id (one row per picture). Of the 238 rows, ZERO have
sub_id == key, so sending the variety number (as we did) made every tab lookup
undefined -> the species grid was 12 blank slots -> "百科解锁后里面还是空白的".
"""
import io

ENG = r"H:\AI\frog\work\run\engine\index.js"

NEW = '''  /* ---------------------------------------------------------- 百科 (encyclopedia)
     The three payload fields are NOT what their names suggest. Read off the client's
     own consumer (EncyModel.encyclopedia_load / EncyView):

         data.unlock_list = e.unlock_list                      // used as TABLE keys
         data.unlock_desc[n.id] = convertArray(n.list)         // keyed by SPECIES id
         data.show_sub[n.id]    = n.sub_id                     // also a TABLE key

         getItemsByTab(tab): for (k in data.show_sub) { var row = TABLE[data.show_sub[k]];
                             row.tab == tab && push(row) }
         getSubItems(id):    for (longId of data.unlock_list) { var row = TABLE[longId];
                             row.id == id && ... }
         getPicItems(id, s): the same, keeping row.sub_id == s
         tab.getChildAt(i).enabled = getItemsByTab(i).length > 0

     `encyclopedia.list` is keyed by **long_id** ("1010101"); every row also carries
     `id` (the species, 101..108 / 201..205 / 301..304 / 401..), `sub_id` (the variety,
     e.g. 角堇 has 火龙果/柠檬黄唇/彩蝶), `tab` (1..4, a property of the species) and
     `pic_id` (one row per picture: 主图/成长1..成长3/…). So:

       * unlock_list holds LONG_IDs (which pictures are unlocked), not species ids;
       * show_sub is {id: species, sub_id: LONG_ID of the shown variety} -- the field
         name is a lie, but `req_set_show_sub(longId)` client-side stores exactly that;
       * unlock_desc really is keyed by species id.

     We used to send the species id in unlock_list and the variety number in show_sub.
     Neither indexes the table -- verified: of the 238 rows, 0 have sub_id == key -- so
     every lookup came back undefined, all four tabs stayed disabled and the 百科 page
     rendered as a grid of blank slots. That is exactly the bug the player saw after
     "解锁全部图鉴和百科". */
  const ENC_LIST = ((gamedata.tables || {}).encyclopedia || {}).list || {};
  const ENC_ENTRIES = Object.keys(ENC_LIST)
    .map((k) => ({ longId: Number(k), row: ENC_LIST[k] }))
    .filter((e) => Number.isFinite(e.longId) && e.row)
    .sort((a, b) => a.longId - b.longId);

  function encySpeciesIds() {
    const ids = [];
    for (const e of ENC_ENTRIES) {
      const id = Number(e.row.id);
      if (Number.isFinite(id) && ids.indexOf(id) === -1) ids.push(id);
    }
    return ids.sort((a, b) => a - b);
  }

  /* Which rows are unlocked. The unit is the VARIETY, not the picture: the page's
     picture carousel reads exactly the rows of the shown variety, so unlocking one row
     of six would leave a one-page carousel. */
  function encyUnlockedEntries() {
    if (state.encyAll) return ENC_ENTRIES.slice();
    const wanted = [];
    for (const pid of (state.flowerpot.grown || [])) wanted.push(encyclopediaRowForPlant(pid));
    for (const d of (state.decoration.hasList || [])) wanted.push(encyclopediaRowForDecoration(d.id));
    const out = [];
    for (const row of wanted) {
      if (!row) continue;
      for (const e of ENC_ENTRIES) {
        if (Number(e.row.id) === Number(row.id) && Number(e.row.sub_id) === Number(row.sub_id)
            && out.indexOf(e) === -1) {
          out.push(e);
        }
      }
    }
    return out;
  }

  /* Build the payload from everything the player has actually grown or been given:
     the flowerpot's harvests AND the flowers brought home from trips. `unlock_all`
     (state.encyAll) reports the whole table instead. */
  function encyclopediaPayload() {
    const unlocked = encyUnlockedEntries();
    const ids = encySpeciesIds();
    const has = {};
    for (const e of unlocked) has[String(e.row.id)] = true;

    const unlock_list = unlocked.map((e) => e.longId);
    const unlock_desc = ids.filter((id) => has[String(id)]).map((id) => ({
      id,
      list: Object.keys((ENC.desc || {})[String(id)] || {}).map(Number).filter((n) => !isNaN(n)),
    }));

    /* One entry per species: the variety the player last looked at (the client sends
       its long_id on encyclopedia_set_show_sub, so the server could only ever remember
       one), else the species' first row in the table. */
    const picked = Number(state.encyclopediaShow);
    const show_sub = [];
    for (const id of ids) {
      const mine = ENC_ENTRIES.filter((e) => Number(e.row.id) === id);
      if (!mine.length) continue;
      const chosen = mine.find((e) => e.longId === picked) || mine[0];
      show_sub.push({ id, sub_id: chosen.longId });
    }
    return { unlock_list, unlock_desc, show_sub };
  }
'''

text = io.open(ENG, encoding='utf-8').read()
start = text.find('  /* Build the three payload fields from everything the player has actually grown or')
assert start > 0, 'start anchor not found'
end_marker = '    return { unlock_list: ids, unlock_desc: desc, show_sub: show };\n  }\n'
end = text.find(end_marker, start)
assert end > 0, 'end anchor not found'
end += len(end_marker)

old = text[start:end]
assert 'state.encyAll' in old and 'ENCY' not in old, 'unexpected region'
text = text[:start] + NEW + text[end:]
io.open(ENG, 'w', encoding='utf-8', newline='').write(text)
print('replaced %d chars with %d' % (len(old), len(NEW)))
print('ENCY_ENTRIES present:', 'ENC_ENTRIES' in text)
