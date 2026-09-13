#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Lock in the live-refresh behaviour: an editor command must PUSH the pages it changed."""
import io

T = r"H:\AI\frog\work\tools\engine_test.js"
text = io.open(T, encoding='utf-8').read()

anchor = "test('editor: all_furniture grants every row, and the client payload carries them'"
assert text.count(anchor) == 1, 'anchor'

NEW = """test('editor: an edit is pushed to the client, so no restart is needed', ({ engine }) => {
  /* 图鉴 / 百科 / 家具 / 博物馆 / 相册 each render from a MODEL that only their own
     `*_load` command fills, and the views do not re-request when they are opened
     (EncyView.childrenCreated sends nothing). So the editor has to push them; without
     that the player saw the old page and had to restart the game -- the reported bug. */
  const r = call(engine, 'client_gm', { cmd: 'unlock_all' });
  const names = r.pushes.map((p) => canon(p.cmd));
  for (const need of ['encyclopedia_load', 'item_load_handbook', 'furniture_load_furniture',
    'museum_load', 'album_load_all']) {
    assert(names.indexOf(need) !== -1,
      `unlock_all must push ${need}; pushed: ${names.join(', ')}`);
  }

  const enc = pushNamed(r, 'encyclopedia_load')[0].data;
  eq(enc.show_sub.length, 23, 'the pushed 百科 payload must be the real one');
  const hand = pushNamed(r, 'item_load_handbook')[0].data;
  assert(hand.collections.length > 0 && hand.specialtys.length > 0, 'the 图鉴 lists');
  const fur = pushNamed(r, 'furniture_load_furniture')[0].data;
  assert(fur.has_fur.length > 0, 'the 家具 list the book renders from');
  assert(pushNamed(r, 'museum_load')[0].data.museum_list.length > 0, 'the museum pages');
  assert(pushNamed(r, 'album_load_all')[0].data.id_list.length === engine.state.pictures.length,
    'the album list');

  /* every data-changing editor command, not just this one */
  for (const cmd of ['all_furniture', 'unlock_pictures', 'unlock_museum', 'add_specialty 101 1']) {
    const rr = call(engine, 'client_gm', { cmd });
    const nn = rr.pushes.map((p) => canon(p.cmd));
    assert(nn.indexOf('encyclopedia_load') !== -1, `${cmd} must refresh the pages too`);
    assert(nn.indexOf('item_load_handbook') !== -1, `${cmd} must refresh the 图鉴 too`);
  }
});

"""

text = text.replace(anchor, NEW + anchor)
io.open(T, 'w', encoding='utf-8', newline='').write(text)
print('added the refresh test')
