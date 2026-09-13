/* PERSISTENCE SWEEP: seed every subsystem, save, then (after a reload driven by
 * the harness) read it all back. Usage:
 *   step 1 (seed):   --evalfile probe/persist_sweep.js
 *   step 2:          --eval "location.reload();'x'" --wait 32000
 *   step 3 (verify): --evalfile probe/persist_verify.js
 * This file is step 1. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'sweep.json' });

  // --- clovers: harvest one so a regrowth span is stored
  eng.state.clovers[0].last_harvest = 0;
  eng.state.clovers[0].element = 0;
  eng.dispatch('clover_harvest', { clover_id: 1 });

  // --- album: one filed, one pending, one in the recycle bin
  eng.state.pictures = [{ id: 11, pic_id: 100, read: 0, new: 1 }];
  eng.state.albumPending = [{ id: 12, pic_id: 101, read: 0, new: 1 }];
  eng.dispatch('album_delete', { id: 11 });
  eng.state.pictures = [{ id: 13, pic_id: 102, read: 0, new: 1 }];

  // --- gift box
  eng.state.giftBox = {
    pictures: [{ id: 21, pic_id: 103, read: 0, new: 1 }],
    specialtys: [{ item_id: 3001, count: 4 }]
  };

  // --- items, furniture, decoration
  eng.state.items.house = [{ item_id: 10211, count: 7 }];
  eng.dispatch('furniture_putin_bench', { index: 3, id: 10211 });
  eng.state.decoration = { hasList: [{ id: 100, num: 2 }], putId: 100, status: 1 };

  // --- visitor + drawing + guest
  eng.state.acquireProvinces = ['上海', '云南'];
  eng.state.visitor = {
    province: '湖北', city: '湖北', name: '湖北', title: 9, partner: 0, food: 3,
    first: false, expire_time: 8e9, gift: { item_id: 100001, count: 4 }, carpet: 7
  };
  eng.state.drawing = {
    state: 2, guest: 1, bag: [3001, -1, -1, -1, -1, -1],
    pages: [1], colls: [1, 2], showColl: 0, penMotion: 'write'
  };
  eng.state.guest = {
    id: 1, confirmed: true, served: false, expire_time: 8e9, pos: 2, startAt: 0
  };

  // --- economy
  eng.state.clover = 4242;
  eng.state.ticket = 17;
  eng.dispatch('furniture_load_furniture', {});
  eng.dispatch('wishingpool_load', {});
  eng.state.wishingPool.coin = 9;
  // NOTE: do NOT set capsule.started here. It gates TWO things -- the one-off
  // opening allowance (FROG_CAPSULE_COIN) and the initial task dealing -- so
  // marking it started suppresses the board. Seed the raw coin and let the engine
  // open the event on its own; persist_verify expects the opening allowance on top.
  eng.state.capsule.coin = 33;
  eng.dispatch('capsule_patch', {});

  // --- cooking
  eng.state.cooking.month = 5;
  eng.state.cooking.monthPro = 2;
  eng.state.cooking.select = 2;
  eng.state.cooking.taskList = [{ id: 7, pro: 1, complete: true }];

  // --- lottery
  eng.state.lottery.phase = 7;
  eng.state.lottery.state = 2;
  eng.state.lottery.answer = [3001, 3002];
  eng.state.lottery.rightFlag = [1, 0];

  // --- animpicture
  eng.state.animPicture.guide = 3;
  eng.state.animPicture.phase = 1;
  eng.state.animPicture.picList = [{ id: 1, putNum: 1, pictures: [] }];

  // --- moments, story, tutorial
  eng.state.moments = [1, 101];
  eng.state.storyBook = {
    list: [{ id: 1, partner: 0, name: 'x', storyid: 1, gift: 3001, feedback: 1 }], newId: 1
  };
  eng.state.guide = { doorOpened: true, awardGiven: true, steps: ['open_door'] };

  eng.save();
  return JSON.stringify({
    seeded: true,
    clover: eng.state.clover,
    bench3: eng.state.furniture.bench[2],
    putId: eng.state.decoration.putId
  });
})()
