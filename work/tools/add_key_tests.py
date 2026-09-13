#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests for the two reply-key mismatches the audit turned up:
  item_load_select_gift  (we sent `items`, the client builds its queue from `list`)
  calendar_task_update   (the client reads `e.task`; we answered undefined)
"""
import io

T = r"H:\AI\frog\work\tools\engine_test.js"
text = io.open(T, encoding='utf-8').read()

anchor = "test('album: load_by_id_list takes a plain NUMBER array (unlike album_load_all)'"
assert text.count(anchor) == 1, 'anchor'

NEW = """test('reply keys: item_load_select_gift answers under `list`, not `items`', ({ engine }) => {
  /* check_select_gift() pops selectGiftList[0] and shows GiftSelectView(row.num,
     row.items); the queue is filled from this reply's `list`. Answering with `items`
     (as we did) left the queue empty for the wrong reason. Nothing in this build queues
     a package, so the empty case is what actually ships -- both shapes are checked. */
  const empty = call(engine, 'item_load_select_gift', {}).reply;
  assert(Array.isArray(empty.list), 'the queue comes from `list`');
  assert(empty.items === undefined, 'and not from the old `items` key');
  eq(empty.list.length, 0, 'nothing is queued in this build');

  engine.state.selectGift = { 1: { item_id: 3001, count: 2, num: 1 } };
  const one = call(engine, 'item_load_select_gift', {}).reply;
  eq(one.list.length, 1, 'a queued package is delivered');
  eq(one.list[0].num, 1, 'GiftSelectView(num, items) needs the pick count');
  eq(one.list[0].items[0].item_id, 3001, 'and the item list');
  eq(one.list[0].items[0].count, 2, 'with its count');

  /* and the follow-up command still grants what it reports */
  const got = call(engine, 'item_select_gift', { index_list: [1] }).reply;
  assert(Array.isArray(got.items) && got.items.length === 1,
    'item_select_gift is read as `items` -- that one was already right');
  eq(got.items[0].count, 2, 'the granted count');
});

test('reply keys: calendar_task_update answers with the task row the client assigns', ({ engine }) => {
  /* The client sends this with NO parameters and does
     `data.task_list[e.task.id-1] = e.task`. Reading `d.task` (which never arrives) and
     answering undefined made the call a no-op. */
  const r = call(engine, 'calendar_task_update', {}).reply;
  assert(r && r.task, 'the reply must carry `task` or the client skips the update');
  assert(typeof r.task.id === 'number' && r.task.id >= 1 && r.task.id <= 3,
    'the id indexes task_list[id-1], which the client keeps three long');
  assert(typeof r.task.pro === 'number' && typeof r.task.complete === 'number',
    'the row carries the same fields as a calendar_load row');
});

"""

text = text.replace(anchor, NEW + anchor)
io.open(T, 'w', encoding='utf-8', newline='').write(text)
print('added the two reply-key tests')
