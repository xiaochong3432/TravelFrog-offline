#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Lock in the album fix: the reply must use the client's key, and the editor must push
both the list AND the layers (a card is drawn from `layers`)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

T = str(PROJECT_ROOT) + "/work/tools/engine_test.js"
text = io.open(T, encoding='utf-8').read()

anchor = "test('album: unlock_pictures fills pic_id AND keeps the handles unique'"
assert text.count(anchor) == 1, 'anchor'

NEW = """test('album: album_load_by_id_list replies under the key the client reads', ({ engine }) => {
  /* The client's handler is `if (e && e.pic_list) { group by id; entry.layers = … }`.
     We used to answer with `pictures`, so the branch never ran and a card added by an
     album command had no layers -- it rendered as an empty/transparent slot until the
     next login. (Same class of bug as the 百科 payload: right data, wrong key.) */
  call(engine, 'client_gm', { cmd: 'unlock_pictures' });
  const ids = engine.state.pictures.map((p) => p.id);
  assert(ids.length > 0, 'unlock_pictures must create album entries');

  const r = call(engine, 'album_load_by_id_list', { id_list: ids }).reply;
  assert(Array.isArray(r.pic_list),
    'the reply must carry `pic_list`; the client ignores everything else');
  assert(r.pictures === undefined, 'and must not carry the old `pictures` key');
  eq(r.pic_list.length, ids.length, 'one row per requested album entry');
  for (const row of r.pic_list) {
    assert(typeof row.id === 'number', 'each row needs the album handle');
    assert(Array.isArray(row.layers) && row.layers.length > 0,
      `album entry ${row.id} needs layers, or its card draws nothing`);
  }

  /* and the editor must PUSH the layers, not just the list */
  const p = call(engine, 'client_gm', { cmd: 'unlock_pictures' });
  const byId = pushNamed(p, 'album_load_by_id_list');
  assert(byId.length === 1, 'unlock_pictures must push album_load_by_id_list');
  const pushed = byId[0].data.pic_list;
  eq(pushed.length, engine.state.pictures.length,
    'the pushed layers must cover every album entry, not just the new ones');
  for (const row of pushed) {
    assert(Array.isArray(row.layers) && row.layers.length > 0,
      `pushed entry ${row.id} needs layers`);
  }
  /* album_load_all only carries id/pic_id -- it cannot fill a card on its own */
  const all = pushNamed(p, 'album_load_all')[0].data;
  assert(all.id_list.every((e) => e.layers === undefined),
    'album_load_all is the handle list; the layers come from the by-id-list push');
});

"""

text = text.replace(anchor, NEW + anchor)
io.open(T, 'w', encoding='utf-8', newline='').write(text)
print('added the album reply-key test')
