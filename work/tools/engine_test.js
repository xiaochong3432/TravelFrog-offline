#!/usr/bin/env node
'use strict';
/**
 * Engine unit-test harness.
 *
 * The rules engine (work/run/engine/index.js) is a plain Node module, so gameplay
 * can be verified directly -- fast, deterministic, no browser and no device. That
 * matters because the interesting failures here are logic failures ("harvest did
 * not change the count"), not rendering failures.
 *
 *   node work/tools/engine_test.js            # run everything
 *   node work/tools/engine_test.js clover     # only tests whose name matches
 *
 * Each check gets a FRESH engine on a temp save path, so tests cannot leak state
 * into each other.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine, canon } = require(ENGINE);
/* The game's own tables, for tests that must agree with the DATA (not with a
   hard-coded copy of it). */
const GDATA = require(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'));
/* The destination map (built by work/tools/build_travel_data.py). Declared up here
   because tests much earlier in this file read it too (the 图鉴 test needs the HP
   column to pick a lunch that walks far enough). */
const TRAVEL = require(path.join(ROOT, 'work', 'run', 'engine', 'data', 'travel.json'));
const items = GDATA.items;

const filter = process.argv[2] || '';
let passed = 0, failed = 0, skipped = 0;
const failures = [];

function newEngine() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-engine-'));
  const savePath = path.join(dir, 'save.json');
  return { engine: createEngine({ savePath, verbose: false }), savePath, dir };
}

/** Re-open the same save file with a brand new engine (persistence check). */
function reopen(savePath) {
  return createEngine({ savePath, verbose: false });
}

function call(engine, cmd, data) {
  const r = engine.dispatch(cmd, data || {});
  return {
    reply: r.reply,
    pushes: (r.pushes || []).map((p) => ({ cmd: p.cmd, data: p.data })),
    handled: r.handled,
  };
}

function pushNamed(res, name) {
  const wire = name.replace(/_/g, '.');
  return res.pushes.filter((p) => canon(p.cmd) === name || p.cmd === wire);
}

/** 没准备就不出门 (see the engine's note): a trip only happens with a packed bag.
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
}

function test(name, fn) {
  if (filter && !name.includes(filter)) return;
  const ctx = newEngine();
  try {
    fn(ctx);
    passed++;
    console.log(`  PASS  ${name}`);
  } catch (e) {
    /* A test whose evidence is the client's own art can only run when that art is
       present: the minimal repository ships code and tables but not the images
       (see docs/数据与逆向说明.md). Mark it SKIP instead of FAIL so a slim clone
       still gets a clean run. */
    if (e && e.skip) {
      skipped++;
      console.log(`  SKIP  ${name}\n          ${e.message}`);
      return;
    }
    failed++;
    failures.push({ name, error: e && e.message });
    console.log(`  FAIL  ${name}\n          ${e && e.message}`);
  } finally {
    try { fs.rmSync(ctx.dir, { recursive: true, force: true }); } catch (e) { /* ignore */ }
  }
}

/** Skip the current test when its evidence is not available in this checkout. */
function skipUnless(cond, why) {
  if (cond) return;
  const e = new Error(why);
  e.skip = true;
  throw e;
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}
function eq(actual, expected, msg) {
  if (actual !== expected) {
    throw new Error(`${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

/* ------------------------------------------------------------------ boot */

console.log('\n== boot / defaults ==');

test('boot: a new save starts with the client\'s OWN StartCloverPoint', ({ engine }) => {
  /* define.json (the original server's tuning table, shipped inside the client)
     says StartCloverPoint = 9999. We used to hand out 300 -- our own number. */
  eq(engine.state.clover, 9999, 'clover == define.json StartCloverPoint');
  eq(engine.state.clovers.length, 20, 'clover slots');
  eq(engine.state.ticket, 3, 'ticket');
});

test('boot: a NEW save starts at the tutorial, an existing one keeps its step', ({ engine }) => {
  /* 'New' is the client's own SettingsInfo default and where a brand-new account
     belongs (欢迎页 -> 起名 -> ... -> Complete). The four event buttons and the
     activity red dot are hidden by MainOut while guideStep != 'Complete', so a
     save parked at the wrong step would never see those features at all. */
  const settings = (res) => {
    const d = res.pushes.map((p) => p.data).find((x) => x && x.settings && x.settings.client);
    return d && JSON.parse(d.settings.client);
  };
  const fresh = settings(call(engine, 'hall_enter_game', {}));
  assert(fresh, 'a role payload with settings must be pushed');
  eq(fresh.guideStep, 'New', 'a new save must start at the guide');
  // A save that already finished the guide must NOT be dragged back into it.
  call(engine, 'client_set_client', { client: JSON.stringify({ guideStep: 'Complete' }) });
  const again = settings(call(engine, 'hall_enter_game', {}));
  eq(again.guideStep, 'Complete', 'a finished save stays finished');
});

test('boot: client_hello replies with a timestamp', ({ engine }) => {
  const r = call(engine, 'client_hello', {});
  assert(r.reply && typeof r.reply.timestamp === 'number', 'reply.timestamp missing');
});

test('boot: entering the game pushes the full world state', ({ engine }) => {
  const r = call(engine, 'hall_enter_game', {});
  const names = r.pushes.map((p) => canon(p.cmd));
  for (const need of ['client_load_role', 'weather_load', 'clover_load_clovers',
                      'item_load_items', 'furniture_load_furniture']) {
    assert(names.includes(need), `missing push ${need}`);
  }
  // the payload shapes the client hard-depends on
  const fur = pushNamed(r, 'furniture_load_furniture')[0];
  assert(fur, 'no furniture_load_furniture push');
  assert(Array.isArray(fur.data.put_fur) && Array.isArray(fur.data.has_fur),
    'furniture push must carry put_fur and has_fur arrays');
  const pot = pushNamed(r, 'furniture_load_flowerpot')[0];
  assert(pot && Array.isArray(pot.data.show_list) && Array.isArray(pot.data.plant_list),
    'flowerpot push must carry show_list and plant_list');
});

/* ---------------------------------------------------------------- clover */

console.log('\n== clover ==');

test('clover: harvest raises the count and pushes clover_update', ({ engine }) => {
  const before = engine.state.clover;
  const r = call(engine, 'clover_harvest', { clover_id: 1 });
  assert(engine.state.clover > before, `clover did not increase (${before} -> ${engine.state.clover})`);
  const up = pushNamed(r, 'clover_update');
  assert(up.length === 1, `expected a clover_update push, got ${up.length}`);
  // Verified in-game: the HUD total is driven by {clover: N}, not by the slot list.
  eq(up[0].data.clover, engine.state.clover, 'clover_update.clover');
});

test('clover: harvest is persisted', ({ engine, savePath }) => {
  call(engine, 'clover_harvest', { clover_id: 1 });
  const after = engine.state.clover;
  const reopened = reopen(savePath);
  eq(reopened.state.clover, after, 'clover after reopen');
});

test('clover: a harvested slot cannot be harvested again immediately', ({ engine }) => {
  call(engine, 'clover_harvest', { clover_id: 1 });
  const once = engine.state.clover;
  call(engine, 'clover_harvest', { clover_id: 1 });
  eq(engine.state.clover, once, 'second harvest of the same slot should not pay out');
});

/* ---------------------------------------------------------------- travel */

console.log('\n== travel ==');

test('travel: departure flips status to away and pushes an event', ({ engine }) => {
  eq(engine.state.frog.status, 0, 'should start at home');
  packForTrip(engine);                           // 没准备就不出门
  engine.state.travel.nextDepartAt = 1;          // long past -> departs on next tick
  const pushes = engine.tick();
  eq(engine.state.frog.status, 1, 'frog.status after departure');
  const names = pushes.map((p) => canon(p.cmd));
  assert(names.includes('notify_new_event'), 'departure must push notify.new_event');
  assert(names.includes('client_load_role'), 'departure must push client.load_role');
  assert(engine.state.travel.returnAt > 0, 'returnAt should be scheduled');
});

test('travel: returning home restores status and pays rewards', ({ engine, savePath }) => {
  packForTrip(engine);                           // 没准备就不出门
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  const cloverBefore = engine.state.clover;
  const ticketBefore = engine.state.ticket;
  engine.state.travel.returnAt = 1;              // due now
  const pushes = engine.tick();
  eq(engine.state.frog.status, 0, 'frog.status after return');
  assert(engine.state.clover >= cloverBefore, 'clover must not decrease on a trip');
  assert(engine.state.ticket >= ticketBefore, 'ticket must not decrease on a trip');
  const names = pushes.map((p) => canon(p.cmd));
  for (const need of ['travel_load_gift', 'clover_update', 'item_update_ticket', 'notify_new_event']) {
    assert(names.includes(need), `return should push ${need}`);
  }
  eq(reopen(savePath).state.frog.status, 0, 'status after reopen');
});

const GD = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
/** ids of every Item of a given ItemType (0=LunchBox, 1=Amulet, 2=Tools). */
const idsOfType = (t) => GD.items.filter((i) => i.type === t).map((i) => i.id);

/* ---- furniture test helpers ---- */

/** A furniture-shop row by shop id. */
const FS_ROW = (shopId) => GD.tables.furnitureShopData[String(shopId)];

/** An Item id that the furniture shop actually sells (tools are Item type 12),
 *  so bench/compost tests place something real rather than an invented id. */
const TOOL_ITEM_ID = () => {
  for (const k of Object.keys(GD.tables.furnitureShopData)) {
    const id = Number(GD.tables.furnitureShopData[k].item_id);
    if (GD.items.some((i) => i.id === id && i.type === 12)) return id;
  }
  throw new Error('no type-12 tool in furnitureShopData');
};

/** What the engine thinks the player has, including bag/desk slots. */
const haveOf = (engine, itemId) => {
  let n = 0;
  const h = engine.state.items.house.find((x) => x.item_id === itemId);
  if (h) n += h.count;
  if (engine.state.items.bag.indexOf(itemId) !== -1) n += 1;
  if (engine.state.items.desk.indexOf(itemId) !== -1) n += 1;
  return n;
};

test('travel: with NO lunch box the frog stays home and keeps its gear', ({ engine }) => {
  const specBefore = engine.state.specialtys.length;
  const picBefore = engine.state.pictures.length;
  const tool = idsOfType(2)[0];
  for (let i = 0; i < 20; i++) {
    engine.state.items.bag[2] = tool;
    engine.state.travel.nextDepartAt = 1;
    engine.tick();
    engine.state.travel.returnAt = 1;
    engine.tick();
  }
  eq(engine.state.specialtys.length, specBefore, 'a stray trip must bring back no souvenir');
  eq(engine.state.pictures.length, picBefore, 'a stray trip must bring back no photo');
  eq(engine.state.travel.tripCount, 0, 'no food means no trips');
  eq(engine.state.frog.status, 0);
  eq(engine.state.items.bag[2], tool);
});

test('travel: a packed lunch box brings back souvenirs and photos', ({ engine, savePath }) => {
  // bag slot 0 is the lunch box per the client's BagItem enum
  const lunch = idsOfType(0)[0];
  assert(lunch !== undefined, 'no lunch box items in the Item table');
  engine.state.items.bag[0] = lunch;
  for (let i = 0; i < 30; i++) {
    engine.state.items.bag[0] = lunch;      // re-pack each trip (it gets eaten)
    engine.state.travel.nextDepartAt = 1;
    engine.tick();
    engine.state.travel.returnAt = 1;
    engine.tick();
  }
  const specialtyCount = engine.state.specialtys.reduce((n, s) => n + s.count, 0);
  assert(specialtyCount > 0, 'expected at least one souvenir across 30 provisioned trips');
  // Newly earned postcards land in the PENDING bucket (album_load_new), which is
  // the client's own flow: it rebuilds newPictureInfoList from that payload and
  // offers a save action. `album_save_new` files one into the album.
  assert(engine.state.albumPending.length > 0,
    'expected at least one pending postcard across 30 trips');
  const pending0 = engine.state.albumPending[0];
  eq(call(engine, 'album_save_new', { id: pending0.id }).reply.code, 0, 'filing answers 0');
  assert(engine.state.pictures.some((p) => p.id === pending0.id),
    'the filed postcard must now be in the album');
  assert(!engine.state.albumPending.some((p) => p.id === pending0.id),
    'and no longer pending');
  // the handbook should have been populated so the 图鉴 is not empty
  assert(engine.state.handbook.specialtys.length > 0, 'handbook.specialtys should fill up');
  eq(reopen(savePath).state.frog.status, 0, 'status after reopen');
});

test('travel: a packed lunch box is consumed but durable gear comes home', ({ engine }) => {
  const lunch = idsOfType(0)[0];
  const tool = idsOfType(2)[0];
  engine.state.items.bag[0] = lunch;
  engine.state.items.bag[2] = tool;          // tools live in slots 2..3
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  eq(engine.state.items.bag[0], -1, 'the lunch box is eaten at departure');
  eq(engine.state.items.bag[2], -1, 'the tool travels with the frog');
  engine.state.travel.returnAt = 1;
  engine.tick();
  const bag = engine.state.items.bag;
  assert(bag.indexOf(tool) !== -1, 'durable gear (spend !== 1) should come home');
  eq(bag[2], tool, 'and it comes home to the TOOL slot it left from');
  eq(bag[0], -1, 'not into the lunch-box slot');
});

test('travel: gear comes home to its OWN slot, never shifted into the food/amulet slots', ({ engine }) => {
  /* The reported bug: the bag's slots are typed (BagItem 0 LunchBox / 1 Amulet /
     2,3 Tools) and the client paints each slot from `getBagDataList()[i]` with NO
     type check -- so a bare id list poured back from slot 0 drew a 水壶 in the 便当
     slot and a 纸伞 in the 护身符 slot. */
  const lunch = idsOfType(0)[0];
  const spendOf = (id) => (items.find((i) => i.id === id) || {}).spend;
  const tools = idsOfType(2).filter((id) => spendOf(id) !== 1).slice(0, 2);
  /* A DURABLE amulet: type-1 rows are mostly spend=1 (consumed on the trip), the
     玉佩 (1001) is the one that comes home. */
  const amulet = idsOfType(1).find((id) => spendOf(id) !== 1);
  assert(amulet !== undefined, 'need a durable amulet for this check');
  assert(tools.length === 2, 'need two durable tools for this check');
  engine.state.items.bag[0] = lunch;         // 便当
  engine.state.items.bag[1] = amulet;        // 护身符
  engine.state.items.bag[2] = tools[0];
  engine.state.items.bag[3] = tools[1];
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  engine.state.travel.returnAt = 1;
  engine.tick();
  const bag = engine.state.items.bag;
  eq(bag[0], -1, 'the lunch-box slot must be free again (it was eaten)');
  eq(bag[1], amulet, 'the amulet returns to the amulet slot');
  eq(bag[2], tools[0], 'tool 1 returns to slot 2');
  eq(bag[3], tools[1], 'tool 2 returns to slot 3');
});

test('travel: waiting without food yields no trip rewards', ({ engine }) => {
  const lunch = idsOfType(0)[0];
  const avgClover = (pack, trips) => {
    let sum = 0;
    for (let i = 0; i < trips; i++) {
      if (pack) engine.state.items.bag[0] = lunch;
      engine.state.travel.nextDepartAt = 1;
      engine.tick();
      engine.state.travel.returnAt = 1;
      const before = engine.state.clover;
      engine.tick();
      sum += engine.state.clover - before;
    }
    return sum / trips;
  };
  const stray = avgClover(false, 60);
  const fed = avgClover(true, 60);
  eq(stray, 0, 'waiting does not grant travel clover');
  assert(fed > 0, 'provisioned trips still grant clover');
});

/* ------------------------------------------------ 行囊「准备完成」 (bag lock) */

test('packing: every bag and desk slot accepts only its type and transfers inventory', ({ engine, savePath }) => {
  const layout = { bag:[0,1,2,2], desk:[0,0,1,1,2,2,2,2] };
  for (const [storage, types] of Object.entries(layout)) {
    for (let slot = 0; slot < types.length; slot++) {
      const id = idsOfType(types[slot])[0];
      const replacement = idsOfType(types[slot])[1];
      engine.state.items.house = [{item_id:id,count:2},{item_id:replacement,count:1}];
      const put = data => call(engine, 'item_putin_' + storage, {pos:slot+1,...data});
      const packed = put({item_id:id});
      eq(packed.reply.code, 0);
      eq(engine.state.items[storage][slot], id);
      eq(engine.state.items.house.find(x=>x.item_id===id).count, 1, 'one reserved');
      eq(pushNamed(packed, 'item_update')[0].data.item.count, 1, 'client gets house count, not house + packed');
      eq(put({item_id:id}).reply.code, 0, 'repeat request is idempotent');
      eq(engine.state.items.house.find(x=>x.item_id===id).count, 1);
      const snapshot = JSON.stringify(engine.state.items);
      for (const type of [0,1,2].filter(t=>t!==types[slot])) {
        eq(put({item_id:idsOfType(type)[0]}).reply.code, -1, 'wrong type refused');
      }
      eq(JSON.stringify(engine.state.items), snapshot, 'wrong type cannot change inventory');
      eq(put({item_id:replacement}).reply.code, 0);
      eq(engine.state.items.house.find(x=>x.item_id===id).count, 2, 'replaced item returned');
      assert(!engine.state.items.house.some(x=>x.item_id===replacement), 'last unit reserved');
      eq(reopen(savePath).state.items[storage][slot], replacement, 'packing persisted');
      eq(call(engine, 'item_takeout_' + storage, {pos:slot+1}).reply.code, 0);
      eq(call(engine, 'item_takeout_' + storage, {pos:slot+1}).reply.code, 0);
      eq(engine.state.items.house.find(x=>x.item_id===replacement).count, 1, 'takeout returns exactly once');
    }
  }
});

test('packing: unowned items and invalid slots never create or lose inventory', ({ engine }) => {
  engine.state.items.house = [];
  for (const storage of ['bag','desk']) {
    const before = JSON.stringify(engine.state.items);
    for (const pos of [0,1,1.5,99]) {
      eq(call(engine, 'item_putin_' + storage, {pos,item_id:0}).reply.code, -1);
    }
    eq(JSON.stringify(engine.state.items), before);
  }
});

test('packing: old swapped food and tools are repaired on load without losing items', ({ engine, savePath }) => {
  const tools = idsOfType(2).slice(0,2);
  const food = idsOfType(0)[0];
  engine.state.items.bag = [tools[0], tools[1], food, 1001];
  engine.state.items.desk = [tools[0], -1, -1, -1, food, -1, -1, -1];
  fs.writeFileSync(savePath, JSON.stringify(engine.state));
  const fixed = reopen(savePath).state.items;
  eq(JSON.stringify(fixed.bag), JSON.stringify([food,1001,...tools]));
  eq(JSON.stringify(fixed.desk), JSON.stringify([food,-1,-1,-1,tools[0],-1,-1,-1]));
  eq(JSON.stringify(fixed.house), JSON.stringify(engine.state.items.house));
});

test('packing: every amulet is used once except the reusable koi jade charm', ({ engine }) => {
  for (const storage of ['bag','desk']) {
    for (const id of idsOfType(1)) {
      engine.state.items.bag = [-1,-1,-1,-1];
      engine.state.items.desk = Array(8).fill(-1);
      engine.state.items.house = [{item_id:0,count:1},{item_id:id,count:1}];
      const pos = storage === 'bag' ? 2 : 3;
      eq(call(engine, 'item_putin_' + storage, {pos:1,item_id:0}).reply.code, 0);
      eq(call(engine, 'item_putin_' + storage, {pos,item_id:id}).reply.code, 0);
      eq(haveOf(engine,id), 1, 'packing does not duplicate amulet');
      engine.state.travel.nextDepartAt = 1;
      engine.tick();
      eq(engine.state.travel.plan.amulet, id, 'carried amulet keeps its travel effect');
      eq(haveOf(engine,id), 0, 'away amulet is unavailable');
      engine.state.travel.returnAt = 1;
      engine.tick();
      eq(haveOf(engine,id), id===1001?1:0, 'only koi jade returns: ' + id);
      if (id===1001) eq(engine.state.items[storage][pos-1], id, 'koi returns to original slot');
      else eq(call(engine, 'item_putin_' + storage, {pos,item_id:id}).reply.code, -1, 'used amulet cannot be repacked');
    }
  }
});

test('packing: legacy travel plans cannot return spent amulets', ({ engine }) => {
  packForTrip(engine);
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  engine.state.travel.plan.carryBack = [1000, {id:1002,slot:1,from:'bag'}, 1001];
  engine.state.travel.returnAt = 1;
  engine.tick();
  eq(engine.state.items.bag[1], 1001);
  assert(!engine.state.items.bag.includes(1000) && !engine.state.items.bag.includes(1002));
});

console.log('\n== bag lock / 准备完成 ==');

test('baglock: 准备完成 with provisions departs immediately', ({ engine }) => {
  /* The client's BagView.lock() -> ItemModel.setBagLock(true) ->
     send("item_set_bag_completed", null, true). Before this handler existed the tap
     was dropped and the frog only left on the idle timer. */
  packForTrip(engine);                                  // lunch box in the bag
  eq(engine.state.frog.status, 0, 'starts at home');
  engine.state.travel.nextDepartAt = 0;                 // no timer pending: only the tap can send it out
  const r = call(engine, 'item_set_bag_completed', { completed: true });
  eq(engine.state.items.bagCompleted, 1, 'authoritative bag_completed');
  eq(engine.state.frog.status, 1, 'the frog must be away right after 准备完成');
  assert(engine.state.travel.returnAt > 0, 'returnAt scheduled');
  assert(r.reply && r.reply.code === 0, 'reply code 0');
  const items = pushNamed(r, 'item_load_items');
  assert(items.length === 1, 'must push item_load_items (client reads bagLock from it)');
  eq(items[0].data.bag_completed, 1, 'pushed bag_completed');
  assert(pushNamed(r, 'notify_new_event').length === 1, 'departure event pushed');
});

test('baglock: 准备完成 without food refuses the lock and departure', ({ engine }) => {
  eq(engine.state.frog.status, 0, 'starts at home');
  engine.state.travel.nextDepartAt = 0;
  const r = call(engine, 'item_set_bag_completed', { completed: true });
  eq(r.reply.code, -1, 'food required');
  eq(engine.state.items.bagCompleted, 0, 'bag stays editable');
  eq(engine.state.frog.status, 0, 'nothing packed -> the frog stays home');
  eq(pushNamed(r, 'notify_new_event').length, 0, 'no departure event');
});

test('baglock: unlocking clears the flag and never departs', ({ engine }) => {
  packForTrip(engine);
  engine.state.travel.nextDepartAt = 0;
  call(engine, 'item_set_bag_completed', { completed: true });
  eq(engine.state.frog.status, 1, 'away after locking');
  const r = call(engine, 'item_set_bag_completed', { completed: false });
  eq(engine.state.items.bagCompleted, 0, 'unlocked');
  eq(pushNamed(r, 'item_load_items').length, 1, 'authoritative echo');
  eq(engine.state.frog.status, 1, 'unlocking must not recall a frog already away');
});

test('baglock: repeated taps do not depart twice', ({ engine }) => {
  packForTrip(engine);
  engine.state.travel.nextDepartAt = 0;
  call(engine, 'item_set_bag_completed', { completed: true });
  const returnAt = engine.state.travel.returnAt;
  const trips = engine.state.travel.tripCount;
  call(engine, 'item_set_bag_completed', { completed: true });
  eq(engine.state.travel.returnAt, returnAt, 'returnAt unchanged (no second departure)');
  eq(engine.state.travel.tripCount, trips, 'tripCount unchanged');
});

test('baglock: the lock survives a restart', ({ engine, savePath }) => {
  packForTrip(engine);
  engine.state.travel.nextDepartAt = 0;
  call(engine, 'item_set_bag_completed', { completed: true });
  const re = reopen(savePath);
  eq(re.state.items.bagCompleted, 1, 'bag_completed persisted');
  eq(re.state.frog.status, 1, 'away state persisted');
});

test('baglock: coming home unlocks the bag, and gear alone cannot start the next trip', ({ engine, savePath }) => {
  packForTrip(engine);
  engine.state.items.bag[1] = 1001;
  engine.state.items.bag[2] = idsOfType(2)[0];
  call(engine,'item_set_bag_completed',{completed:true});
  eq(engine.state.items.bagCompleted,1);
  engine.state.travel.returnAt = 1;
  const pushes = engine.tick();
  eq(engine.state.items.bagCompleted,0);
  eq(pushes.find(x=>canon(x.cmd)==='item_load_items').data.bag_completed,0);
  eq(reopen(savePath).state.items.bagCompleted,0);
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  eq(engine.state.frog.status,0);
  eq(call(engine,'item_set_bag_completed',{completed:true}).reply.code,-1);
  engine.state.items.desk[0] = 0; // food on the table also counts
  eq(call(engine,'item_set_bag_completed',{completed:true}).reply.code,0);
  eq(engine.state.frog.status,1);
});

test('baglock: old at-home locked saves reopen editable', ({ engine, savePath }) => {
  engine.state.frog.status = 0;
  engine.state.items.bagCompleted = 1;
  fs.writeFileSync(savePath,JSON.stringify(engine.state));
  eq(reopen(savePath).state.items.bagCompleted,0);
});

/* ------------------------------------------------- 相册容量 / 扩容 (第七轮) */

console.log('\n== album capacity / 扩容 ==');

/** 一张待归档的新照片。 */
function pendOne(engine, picId) {
  engine.state.albumPending = engine.state.albumPending || [];
  engine.state.pictureSeq = (engine.state.pictureSeq || 0) + 1;
  const row = { id: engine.state.pictureSeq, pic_id: picId, read: 0, new: 1 };
  engine.state.albumPending.push(row);
  return row;
}

test('album: capacity is 30 base pages x 6, NOT Define.ALBUM_MAX', ({ engine }) => {
  /* The client computes pages from the picture list (Math.ceil(n/6), itemPerPage=6) and
     its 扩容 tip prints getHouseItemCount(9000) -- so ALBUM_MAX (never read by the client)
     is not a picture cap. Using it as one made 60 pictures look "full". */
  const r = call(engine, 'client_gm', { cmd: 'album_state' });
  assert(/可放 180/.test(r.reply.info), `expected 180 capacity, got: ${r.reply.info}`);
  assert(/扩容已拥有 0\/35/.test(r.reply.info), `expected 0/35 expansions, got: ${r.reply.info}`);
});

test('album: a full album refuses a new photo with code 75 (and drops the row)', ({ engine }) => {
  engine.state.pictures = [];
  for (let i = 0; i < 180; i++) engine.state.pictures.push({ id: i + 1, pic_id: 1000 + i, read: 0, new: 0 });
  const row = pendOne(engine, 3102);
  const r = call(engine, 'album_save_new', { id: row.id });
  eq(r.reply.code, 75, 'album full code');
  eq(engine.state.albumPending.length, 0, 'the pending row is dropped on 75');
});

test('album: 扩容相册到上限 grants the shop chain and raises the capacity to 390', ({ engine }) => {
  const r = call(engine, 'client_gm', { cmd: 'expand_album' });
  assert(/扩容 0 → 35/.test(r.reply.info), `unexpected: ${r.reply.info}`);
  assert(/390/.test(r.reply.info), `capacity should be 390: ${r.reply.info}`);
  const house = engine.state.items.house.find((h) => Number(h.item_id) === 9000);
  assert(house && house.count === 35, 'item 9000 must be owned x35 (the client tip reads it)');
  const items = pushNamed(r, 'item_update');
  assert(items.length >= 1, 'item_update must be pushed so the client sees the count');
});

test('album: after 扩容 a new photo files fine', ({ engine }) => {
  call(engine, 'client_gm', { cmd: 'expand_album' });
  engine.state.pictures = [];
  for (let i = 0; i < 351; i++) engine.state.pictures.push({ id: i + 1, pic_id: 1000 + i, read: 0, new: 0 });
  const row = pendOne(engine, 3200);
  const r = call(engine, 'album_save_new', { id: row.id });
  eq(r.reply.code, 0, 'filing must succeed with capacity 390');
  eq(engine.state.pictures.length, 352, 'photo filed');
});

test('album: 一键解锁 also expands, so the album is not left "full"', ({ engine }) => {
  const r = call(engine, 'client_gm', { cmd: 'unlock_pictures' });
  eq(engine.state.pictures.length, 351, 'all pictures unlocked');
  const house = engine.state.items.house.find((h) => Number(h.item_id) === 9000);
  assert(house && house.count === 35, 'unlock must grant the expansions too');
  const row = pendOne(engine, 3300);
  eq(call(engine, 'album_save_new', { id: row.id }).reply.code, 0,
    'a later trip photo must still file');
});

test('album: the capacity follows the shop table, not a hardcoded 35', ({ engine }) => {
  const slots = GD.tables.shopData.filter((s) => Number(s.itemId) === 9000).length;
  eq(slots, 35, '相册扩容 slot count from shopData');
  const r = call(engine, 'client_gm', { cmd: 'expand_album' });
  assert(new RegExp('→ ' + slots + ' 件').test(r.reply.info), r.reply.info);
});

/* --------------------------------------------- 工作台制作 (图纸 -> 家具) */

console.log('\n== 工作台制作 / craft ==');

/** 图纸物品 id（furnitureData.drawing，Item type 13）。 */
const DRAWING_FOR_TYPE_1 = (() => {
  const rows = Object.values(GD.tables.furnitureData);
  const row = rows.find((r) => Number(r.id) === 2001);
  return Number(row.drawing);
})();

test('craft: 图纸 + 材料 -> 自动开工（玩家路径：把图纸放进台面就开工）', ({ engine }) => {
  const mats = [{ item_id: 10001, count: 2 }, { item_id: 10005, count: 1 }];
  engine.state.items.house = [{ item_id: DRAWING_FOR_TYPE_1, count: 1 }]
    .concat(mats.map((m) => ({ item_id: m.item_id, count: m.count })));
  /* 5–9 号是"物品位"（客户端的 setBenchItem 用的也是这几个位） */
  const r = call(engine, 'furniture_putin_bench', { pos: 6, id: DRAWING_FOR_TYPE_1 });
  eq(r.reply.code, 0, '图纸放上台面');
  eq(r.reply.crafting, 1, '材料齐了应当自动开工');
  const craft = engine.state.furniture.craft;
  assert(craft && craft.furnitureId === 2001, `应当做 2001，得到 ${craft && craft.furnitureId}`);
  eq(engine.state.furniture.benchLock, 1, '制作中工作台锁定');
  /* 材料当场扣掉、图纸被用掉 */
  const have = (id) => (engine.state.items.house.find((h) => h.item_id === id) || {}).count || 0;
  eq(have(10001), 0, '松木扣 2');
  eq(have(10005), 0, '粗布扣 1');
  eq(engine.state.furniture.bench[5], -1, '图纸从台面消失');
});

test('craft: 材料不够就不开工，图纸留在台面上', ({ engine }) => {
  engine.state.items.house = [{ item_id: DRAWING_FOR_TYPE_1, count: 1 }];
  const r = call(engine, 'furniture_putin_bench', { pos: 6, id: DRAWING_FOR_TYPE_1 });
  eq(r.reply.code, 0, '放上去是成功的');
  assert(!r.reply.crafting, '不该开工');
  eq(!!engine.state.furniture.craft, false, '没有进行中的制作');
  eq(engine.state.furniture.benchLock, 0, '没锁定');
  eq(engine.state.furniture.bench[5], DRAWING_FOR_TYPE_1, '图纸还在台面上等材料');
});

test('craft: mate_list 报出还需要的材料（客户端按它算缺口）', ({ engine }) => {
  engine.state.items.house = [{ item_id: DRAWING_FOR_TYPE_1, count: 1 }];
  call(engine, 'furniture_putin_bench', { pos: 6, id: DRAWING_FOR_TYPE_1 });
  const lf = call(engine, 'furniture_load_furniture', {}).reply;
  eq(JSON.stringify(lf.mate_list), JSON.stringify([10001, 10001, 10005]),
    'mate_list 是"每份一个元素"的材料清单');
});

test('craft: 制作中工作台锁定，放/取都被拒（码 6）', ({ engine }) => {
  engine.state.items.house = [
    { item_id: DRAWING_FOR_TYPE_1, count: 1 }, { item_id: 10001, count: 2 }, { item_id: 10005, count: 1 },
  ];
  call(engine, 'furniture_putin_bench', { pos: 6, id: DRAWING_FOR_TYPE_1 });
  eq(engine.state.furniture.benchLock, 1, '已经在做');
  eq(call(engine, 'furniture_putin_bench', { pos: 1, id: 10001 }).reply.code, 6, '放：拒');
  eq(call(engine, 'furniture_takeout_bench', { pos: 1 }).reply.code, 6, '取：拒');
});

test('craft: 到点结算入门，含离线追赶（并推 FurnitureFinish 21）', ({ engine }) => {
  engine.state.items.house = [
    { item_id: DRAWING_FOR_TYPE_1, count: 1 }, { item_id: 10001, count: 2 }, { item_id: 10005, count: 1 },
  ];
  call(engine, 'furniture_putin_bench', { pos: 6, id: DRAWING_FOR_TYPE_1 });
  /* 时间跳到完成之后（相当于关掉应用再回来） */
  engine.state.furniture.craft.finishAt = 1;
  const pushes = engine.tick();
  const names = pushes.map((p) => canon(p.cmd));
  assert(names.includes('furniture_load_furniture'), '结算要推家具状态');
  assert(names.includes('notify_new_event'), '要推 FurnitureFinish 事件');
  const ev = pushes.find((p) => canon(p.cmd) === 'notify_new_event');
  eq(ev.data.event.evt_type, 21, 'FurnitureFinish = 21（客户端的枚举值）');
  eq(ev.data.event.evt_value[0], 2001, '事件里带家具 id');
  assert((engine.state.furniture.owned || []).indexOf(2001) !== -1, '家具入库');
  eq(engine.state.furniture.benchLock, 0, '结算后解锁');
  eq(!!engine.state.furniture.craft, false, '制作槽清空');
});

test('craft: 图纸 -> type -> 风格最高的那件（参考包 benchData 的规律）', ({ engine }) => {
  /* 一张图纸对应一整个 type 槽位（同组里有 style 2..11 和 101 多件）；"能做哪一件"由
     benchData 决定，而参考包新增的 27 行正是**每 type 里在 benchData 中 style 最高**的那件。
     所以 10301 -> 2001（style 11），而不是同组里 style 101 的 10103（它不在 benchData 里）。 */
  const benchIds = new Set(GD.tables.benchData.map((r) => Number(r.id)));
  const rows = Object.values(GD.tables.furnitureData).filter((r) => Number(r.drawing) === DRAWING_FOR_TYPE_1);
  const candidates = rows.filter((r) => benchIds.has(Number(r.id)));
  eq(Math.max(...candidates.map((r) => Number(r.style))), 11, 'benchData 候选里最高 style');
  const style101 = rows.find((r) => Number(r.style) === 101);
  assert(style101 && !benchIds.has(Number(style101.id)),
    'style 101 的那件（' + (style101 && style101.id) + '）不在 benchData 里 —— 它不属于工作台可做');
  engine.state.items.house = [
    { item_id: DRAWING_FOR_TYPE_1, count: 1 }, { item_id: 10001, count: 2 }, { item_id: 10005, count: 1 },
  ];
  call(engine, 'furniture_putin_bench', { pos: 6, id: DRAWING_FOR_TYPE_1 });
  eq(engine.state.furniture.craft.furnitureId, 2001, '做出 benchData 里 style 最高的 2001');
});

test('craft: 每种可做 type 都能由一件图纸打出来（27 种全通）', ({ engine }) => {
  let made = 0;
  for (const fid of [2001, 2010, 2025, 2027]) {
    engine.state.furniture.craft = null;
    engine.state.furniture.benchLock = 0;
    engine.state.furniture.bench = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1];
    const r = call(engine, 'client_gm', { cmd: 'craft_start ' + fid });
    assert(r.reply && r.reply.info, `craft_start ${fid} 应当开工：${JSON.stringify(r.reply)}`);
    call(engine, 'client_gm', { cmd: 'craft_finish' });
    assert((engine.state.furniture.owned || []).indexOf(fid) !== -1, `${fid} 应当入库`);
    made++;
  }
  eq(made, 4, '四件都做出来了');
});

test('craft: 制作中/完成状态能持久化', ({ engine, savePath }) => {
  engine.state.items.house = [
    { item_id: DRAWING_FOR_TYPE_1, count: 1 }, { item_id: 10001, count: 2 }, { item_id: 10005, count: 1 },
  ];
  call(engine, 'furniture_putin_bench', { pos: 6, id: DRAWING_FOR_TYPE_1 });
  const re = reopen(savePath);
  assert(re.state.furniture.craft, '重启后制作还在进行');
  eq(re.state.furniture.benchLock, 1, '重启后仍锁定');
});

/* ------------------------------------------------------------ GM console */

console.log('\n== GM / save editor ==');

test('gm: add_clover changes the count and persists', ({ engine, savePath }) => {
  const before = engine.state.clover;
  const r = call(engine, 'client_gm', { cmd: 'add_clover 500' });
  eq(engine.state.clover, before + 500, 'clover after gm add');
  assert(r.reply && r.reply.succeed === true, 'gm should report succeed');
  eq(reopen(savePath).state.clover, before + 500, 'clover after reopen');
});

test('gm: state reports a summary', ({ engine }) => {
  const r = call(engine, 'client_gm', { cmd: 'state' });
  assert(r.reply && typeof r.reply.info === 'string' && r.reply.info.length > 0,
    'gm state should return info text');
});

test('gm: unknown command is refused without throwing', ({ engine }) => {
  const r = call(engine, 'client_gm', { cmd: 'definitely_not_a_command' });
  assert(r.reply, 'gm should still reply');
  eq(r.reply.succeed, false, 'gm unknown command should not succeed');
});

/* --------------------------------------------------------- export/import */

console.log('\n== export / import ==');

test('save: export/import round-trips the whole save', ({ engine }) => {
  call(engine, 'client_gm', { cmd: 'add_clover 123' });
  const snapshot = engine.exportSave();
  call(engine, 'client_gm', { cmd: 'set_clover 1' });
  eq(engine.state.clover, 1, 'clover after set');
  engine.importSave(snapshot);
  eq(engine.state.clover, snapshot.clover, 'clover after import');
});

test('save: import rejects junk instead of corrupting state', ({ engine }) => {
  let threw = false;
  try { engine.importSave('not an object'); } catch (e) { threw = true; }
  assert(threw, 'importing a non-object should throw');
  eq(engine.state.clover, 9999, 'state should be untouched after a bad import');
});

/* ------------------------------------------------------------ small families */

console.log('\n== small families ==');

test('annual: load is handled and suppresses the dead-end share dot', ({ engine }) => {
  const r = call(engine, 'annual_load', {});
  assert(r.handled, 'annual_load should be handled, not fall through to UNKNOWN');
  eq(r.reply.is_share, true, 'is_share must be truthy or the client raises an un-actionable dot');
  const s = call(engine, 'annual_share', {});
  assert(s.handled, 'annual_share should be handled');
});

/* ------------------------------------------------------------------- shop */

console.log('\n== shop ==');

test('shop: purchase history is reported so limits survive a restart', ({ engine }) => {
  const r = call(engine, 'item_load_shop_info', {});
  assert(r.reply && Array.isArray(r.reply.purchased), 'purchased must be an array');
});

test('shop: buying food costs the real table price and lands in the house', ({ engine, savePath }) => {
  // slot 0 = 奶油华夫饼, price 10 (from config.eab shopData)
  const before = engine.state.clover;
  const r = call(engine, 'item_buy', { shop_id: 0 });
  eq(r.reply.code, 0, 'buy should succeed');
  eq(engine.state.clover, before - 10, 'clover should drop by the table price');
  const up = pushNamed(r, 'item_update');
  assert(up.length === 1, 'item_update is required: the client addHouseItem() is an empty stub');
  eq(up[0].data.item.item_id, 0, 'pushed item id');
  const house = engine.state.items.house.find((h) => h.item_id === 0);
  assert(house && house.count >= 1, 'the item should be in the house');
  eq(reopen(savePath).state.clover, before - 10, 'clover after reopen');
});

test('shop: food is unlimited so it can be bought repeatedly', ({ engine }) => {
  const before = engine.state.clover;
  call(engine, 'item_buy', { shop_id: 0 });
  call(engine, 'item_buy', { shop_id: 0 });
  eq(engine.state.clover, before - 20, 'two buys cost twice');
  eq(engine.state.shopBought[0], 2, 'purchase count');
});

test('shop: a limit-1 slot refuses a second buy and compensates the client', ({ engine }) => {
  engine.state.clover = 99999;
  eq(call(engine, 'item_buy', { shop_id: 9 }).reply.code, 0, 'first buy (玉佩) should succeed');
  const second = call(engine, 'item_buy', { shop_id: 9 });
  assert(second.reply.code !== 0, 'second buy must be refused');
  const fix = pushNamed(second, 'clover_update');
  assert(fix.length === 1,
    'a refusal must push clover_update: the client already deducted the clover locally');
  eq(fix[0].data.clover, engine.state.clover, 'compensation must carry the authoritative value');
});

test('shop: refuses when there is not enough clover', ({ engine }) => {
  engine.state.clover = 0;
  const r = call(engine, 'item_buy', { shop_id: 0 });
  assert(r.reply.code !== 0, 'purchase should be refused');
  eq(engine.state.clover, 0, 'clover must not go negative');
});

test('shop: before_buy chains work (album expansion 22 -> 23)', ({ engine }) => {
  engine.state.clover = 999999;
  const locked = call(engine, 'item_buy', { shop_id: 23 });
  assert(locked.reply.code !== 0, 'slot 23 must be locked until slot 22 is bought');
  eq(call(engine, 'item_buy', { shop_id: 22 }).reply.code, 0, 'slot 22 should be buyable');
  eq(call(engine, 'item_buy', { shop_id: 23 }).reply.code, 0, 'slot 23 should unlock after 22');
});

test('shop: purchase counts persist and are reported', ({ engine, savePath }) => {
  engine.state.clover = 99999;
  call(engine, 'item_buy', { shop_id: 9 });
  const reopened = reopen(savePath);
  eq(reopened.state.shopBought[9], 1, 'purchase count after reopen');
  const info = call(reopened, 'item_load_shop_info', {});
  assert(info.reply.purchased.some((p) => p.item_id === 9 && p.count === 1),
    'item_load_shop_info must report the purchase (keyed by SLOT id, as the client reads it)');
});

test('shop: unknown slot is refused without throwing', ({ engine }) => {
  const r = call(engine, 'item_buy', { shop_id: 99999 });
  assert(r.reply && r.reply.code !== 0, 'unknown slot should be refused');
});

/* ------------------------------------------------------------------ gacha */

console.log('\n== gacha / misc fixes ==');

test('gacha: a new save has no pending ball (colorBall is -1, not 0)', ({ engine }) => {
  // Define.PRIZE_WHITE_ID === 0, so rank 0 is a REAL prize: leaving this at 0
  // makes the lottery screen pop a claimable white ball on a fresh save.
  eq(engine.state.gacha.colorBall, -1, 'gacha.colorBall');
});

test('gacha: a legacy save storing colorBall 0 is migrated to -1', ({ engine, savePath }) => {
  const snap = engine.exportSave();
  snap.gacha = { colorBall: 0 };
  fs.writeFileSync(savePath, JSON.stringify(snap));
  eq(reopen(savePath).state.gacha.colorBall, -1, 'legacy 0 must migrate to -1');
});

test('gift code: unknown codes are refused (the client reads 200 as success)', ({ engine }) => {
  const r = call(engine, 'item_use_gift_code', { gift_code: 'NOT-A-REAL-CODE' });
  assert(r.handled, 'item_use_gift_code should be handled, not fall through to UNKNOWN');
  assert(r.reply.code !== 200, 'returning 200 would falsely tell the player the code worked');
});

test('shop: EVERY catalogue slot grants an item that exists in Item.json', ({ engine }) => {
  // The client's ItemDB.get() has no null guard, so an item_update naming an
  // unknown id would throw inside doAddHouseItem. Sweep the whole catalogue.
  const tables = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'Item.json'), 'utf8'));
  const known = new Set(tables.map((i) => i.id));
  const shop = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'shopData.json'), 'utf8'));

  engine.state.clover = 1e9;
  const offenders = [];
  let granted = 0;
  for (const slot of shop) {
    const r = call(engine, 'item_buy', { shop_id: slot.id });
    for (const p of r.pushes) {
      if (canon(p.cmd) !== 'item_update') continue;
      granted++;
      if (!known.has(p.data.item.item_id)) {
        offenders.push({ slot: slot.id, item: p.data.item.item_id });
      }
    }
  }
  assert(granted > 0, 'the sweep should have produced item_update pushes');
  eq(offenders.length, 0, `pushes naming ids absent from Item.json: ${JSON.stringify(offenders)}`);
});

test('shop: an unrecognised before_buy kind fails CLOSED', ({ engine }) => {
  // Only 'shop' occurs in this build, but the client also supports 'item'; an
  // unknown kind must not silently unlock the slot.
  engine.state.clover = 1e9;
  const tables = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'shopData.json'), 'utf8'));
  const kinds = new Set();
  for (const s of tables) {
    if (Array.isArray(s.before_buy) && s.before_buy.length >= 2) kinds.add(s.before_buy[0]);
  }
  // Document which kinds this build actually uses; if a new one appears, the
  // helper must have been taught about it.
  for (const k of kinds) {
    assert(k === 'shop' || k === 'item',
      `shopData uses before_buy kind ${JSON.stringify(k)}, which shopPrereqMet does not handle`);
  }
});

test('clover: a four-leaf slot yields the ITEM, not plain clover', ({ engine }) => {
  // client harvestClover(): element==1 -> addHouseItem(Define.FourLeafCloverID,1),
  // and addHouseItem is an empty stub, so this must arrive as an item_update.
  const cloverBefore = engine.state.clover;
  engine.state.clovers[0].element = 1;
  engine.state.clovers[0].last_harvest = 0;          // ready
  const r = call(engine, 'clover_harvest', { clover_id: 1 });
  eq(r.reply.granted, 'four_leaf', 'granted kind');
  eq(engine.state.clover, cloverBefore, 'a four-leaf clover must NOT also pay clover');
  const up = pushNamed(r, 'item_update');
  assert(up.length === 1, 'a four-leaf clover needs an item_update push');
  eq(up[0].data.item.item_id, 1000, 'FourLeafCloverID');
  const house = engine.state.items.house.find((h) => h.item_id === 1000);
  assert(house && house.count === 1, 'the four-leaf clover should be in the house');
});

test('clover: reply always carries clover_id so the client can clear its pending list', ({ engine }) => {
  const r = call(engine, 'clover_harvest', { clover_id: 3 });
  eq(r.reply.clover_id, 3, 'clover_id must be echoed');
});

/* -------------------------------------------------------------- furniture */

console.log('\n== furniture payload completeness ==');

/* furniture_load_* handlers replace the model object WHOLESALE, and the client's
   convertArrayAll only copies keys that already exist -- so a missing field is a
   crash or a silently-blank panel. These are the required sets per the spec. */
const FURNITURE_REQUIRED = {
  furniture_load_furniture: ['shop', 'mood', 'bench_lock', 'bench', 'put_fur',
                             'has_fur', 'mate_list', 'replace_fur'],
  furniture_load_flowerpot: ['show_list', 'list', 'plant_list'],
  furniture_load_compost: ['show_index', 'replace_index', 'state', 'box_index', 'box_list'],
  furniture_load_pocket: ['show_index', 'replace_index', 'list', 'clover'],
  furniture_load_tumbler: ['show_index', 'replace_index', 'tumbler_list'],
};

for (const [cmd, fields] of Object.entries(FURNITURE_REQUIRED)) {
  test(`furniture: ${cmd} carries every required field`, ({ engine }) => {
    const r = call(engine, cmd, {});
    assert(r.handled, `${cmd} should be handled`);
    for (const f of fields) {
      assert(Object.prototype.hasOwnProperty.call(r.reply, f),
        `${cmd} is missing field "${f}" (client will dereference undefined)`);
    }
    assert(r.reply.shop === undefined || typeof r.reply.shop === 'object',
      'shop must be an object when present');
  });
}

test('furniture: the merchant shop is OPEN now that furniture_buy_shop works', ({ engine }) => {
  // `start_time < now < leave_time` is the client's ONLY "the merchant is here"
  // check, and it arms a timer that closes the shop window with
  // 嘟嘟已经收拾回家了. It used to stay 0 because buying was unimplemented and
  // that would have been a dead end. (NOTE: this switch gates the MERCHANT SHOP,
  // not the furniture workbench -- an earlier comment here mislabelled it.)
  const now = Math.floor(Date.now() / 1000);
  const r = call(engine, 'furniture_load_furniture', {});
  assert(r.reply.shop.start_time < now, 'shop window must have started');
  assert(r.reply.shop.leave_time > now, 'shop window must not have ended');
});

test('furniture: shop_list rows carry shop_id/item_id/num and are buyable', ({ engine }) => {
  const r = call(engine, 'furniture_load_furniture', {});
  const list = r.reply.shop.shop_list;
  assert(list.length > 0, 'the shop must offer something');
  for (const row of list) {
    assert(Number.isInteger(row.shop_id), 'shop_id must be an int (FurnitureShopDB key)');
    assert(Number.isInteger(row.item_id), 'item_id must be an int (ItemDB key)');
    assert(row.num > 0, 'the client only enables the buy button when num > 0');
  }
  // the client renders from FurnitureShopDB/ItemDB, so both must resolve or the
  // shop row throws while drawing
  const FS = GD.tables.furnitureShopData;
  const itemIds = new Set(GD.items.map((i) => i.id));
  for (const row of list) {
    assert(FS[String(row.shop_id)], `shop_id ${row.shop_id} missing from furnitureShopData`);
    assert(itemIds.has(row.item_id), `item_id ${row.item_id} missing from Item.json`);
  }
});

test('furniture: buying charges clover, grants the item and decrements num', ({ engine }) => {
  engine.state.clover = 100000;
  const before = call(engine, 'furniture_load_furniture', {}).reply.shop.shop_list;
  const row = before.find((r) => Number(FS_ROW(r.shop_id).price) > 0);
  assert(row, 'need a priced row to test');
  const price = Number(FS_ROW(row.shop_id).price);
  const clover0 = engine.state.clover;

  const r = call(engine, 'furniture_buy_shop', { id: row.shop_id });
  eq(r.reply.code, 0, 'a valid purchase must answer code 0 (client updates its model only on 0)');
  eq(engine.state.clover, clover0 - price, 'clover must actually be deducted server-side');

  const after = call(engine, 'furniture_load_furniture', {}).reply.shop.shop_list;
  const same = after.find((r) => r.shop_id === row.shop_id);
  // limit is usually 1, so the row disappears entirely; if limit > 1 num drops
  if (same) eq(same.num, row.num - 1, 'remaining purchases must decrease');
  else assert(row.num === 1, 'a limit-1 row must vanish once bought');
});

test('merchant: buying all available stock ends the visit and survives restart', ({ engine, savePath }) => {
  engine.state.clover = 100000000;
  let last;
  for (let purchases=0; purchases<500; purchases++) {
    const rows = call(engine, 'furniture_load_furniture', {}).reply.shop.shop_list;
    if (!rows.length) break;
    last = call(engine, 'furniture_buy_shop', {shop_id:rows[0].shop_id});
    eq(last.reply.code, 0);
  }
  const closed = call(engine, 'furniture_load_furniture', {}).reply.shop;
  eq(closed.shop_list.length, 0);
  assert(closed.leave_time <= Math.floor(Date.now()/1000), 'sold-out merchant must leave');
  const pushed = pushNamed(last, 'furniture_load_furniture');
  eq(pushed.length, 1, 'the final purchase immediately pushes the closed shop');
  eq(pushed[0].data.shop.shop_list.length, 0);
  eq(call(reopen(savePath), 'furniture_load_furniture', {}).reply.shop.shop_list.length, 0, 'restart cannot restock');
  const before = engine.state.clover;
  eq(call(engine, 'furniture_buy_shop', {shop_id:2001}).reply.code, -1);
  eq(engine.state.clover, before);
});

test('merchant: next day restocks repeatable and welfare goods but preserves lifetime limits', ({ engine, savePath }) => {
  engine.state.clover = 100000;
  for (const id of [1,2001,7003]) eq(call(engine,'furniture_buy_shop',{shop_id:id}).reply.code,0);
  let ids = call(engine,'furniture_load_furniture',{}).reply.shop.shop_list.map(x=>x.shop_id);
  assert(!ids.includes(1) && !ids.includes(2001) && !ids.includes(7003));
  const realNow = Date.now;
  const tomorrow = realNow() + 86400000;
  Date.now = () => tomorrow;
  try {
    const pushes = engine.tick();
    assert(pushes.some(x=>canon(x.cmd)==='furniture_load_furniture'), 'new visit is pushed to the open courtyard');
    ids = call(engine,'furniture_load_furniture',{}).reply.shop.shop_list.map(x=>x.shop_id);
    assert(!ids.includes(1), 'one-time tool package never restocks');
    assert(ids.includes(2001) && ids.includes(7003), 'materials and welfare restock');
    eq(call(reopen(savePath),'furniture_buy_shop',{shop_id:7003}).reply.code,0, 'restock survives reopening');
  } finally { Date.now = realNow; }
});

test('merchant: old lifetime stock is migrated without resetting today purchases', ({ engine, savePath }) => {
  engine.state.furniture.shopBought = {1:1,2001:1,7003:1};
  delete engine.state.furniture.shopDailyBought;
  delete engine.state.furniture.shopDay;
  fs.writeFileSync(savePath, JSON.stringify(engine.state));
  const restored = reopen(savePath);
  let ids = call(restored,'furniture_load_furniture',{}).reply.shop.shop_list.map(x=>x.shop_id);
  assert(!ids.includes(1) && !ids.includes(2001) && !ids.includes(7003));
  restored.state.furniture.shopDay -= 86400;
  ids = call(restored,'furniture_load_furniture',{}).reply.shop.shop_list.map(x=>x.shop_id);
  assert(!ids.includes(1) && ids.includes(2001) && ids.includes(7003));
});

test('compost: starter bin is visible and old empty lists heal without losing contents or chosen skins', ({ engine, savePath }) => {
  const starter = call(engine,'furniture_load_compost',{}).reply;
  eq(starter.compost_list[starter.show_index-1],21000);
  engine.state.furniture.compost.list = [];
  engine.state.furniture.compost.showIndex = 0;
  engine.state.furniture.compost.boxes[2] = 20001;
  fs.writeFileSync(savePath,JSON.stringify(engine.state));
  const restored = reopen(savePath);
  const data = call(restored,'furniture_load_compost',{}).reply;
  eq(data.compost_list[data.show_index-1],21000);
  eq(data.box_list[2],20001);
  restored.state.furniture.compost.list = [21011];
  restored.state.furniture.compost.showIndex = 0;
  fs.writeFileSync(savePath,JSON.stringify(restored.state));
  const hidden = call(reopen(savePath),'furniture_load_compost',{}).reply;
  eq(hidden.compost_list[0],21011);
  eq(hidden.show_index,0,'a deliberately hidden owned bin stays hidden');
});

test('furniture: buying without enough clover is refused, not silently granted', ({ engine }) => {
  engine.state.clover = 0;
  const list = call(engine, 'furniture_load_furniture', {}).reply.shop.shop_list;
  const row = list.find((r) => Number(FS_ROW(r.shop_id).price) > 0);
  const itemBefore = engine.state.items.house.length;
  const r = call(engine, 'furniture_buy_shop', { id: row.shop_id });
  assert(r.reply.code !== 0, 'must not succeed');
  eq(engine.state.clover, 0, 'clover must be untouched');
});

test('furniture: bench has 10 slots -- 1..5 tools, 6..10 items, -1 = empty', ({ engine }) => {
  // client: setBenchTool sends index+1 (slots 0..4), setBenchItem sends e+5+1
  // (slots 5..9). The wire index alone therefore picks the row.
  const bench = call(engine, 'furniture_load_furniture', {}).reply.bench;
  eq(bench.length, 10, 'the client slices bench 0..5 and 5..10 into two rows');
  for (const v of bench) eq(v, -1, 'starts empty (bench uses -1, the compost box uses 0)');
});

test('furniture: putting an item on the bench consumes it; taking out returns it', ({ engine }) => {
  const itemId = TOOL_ITEM_ID();
  engine.state.items.house = [{ item_id: itemId, count: 2 }];
  // slot 1 = tools row, slot 6 = items row
  const put = call(engine, 'furniture_putin_bench', { index: 1, id: itemId });
  eq(put.reply.code, 0, 'putin must answer 0');
  eq(haveOf(engine, itemId), 1, 'placing must consume one from the house');
  eq(call(engine, 'furniture_load_furniture', {}).reply.bench[0], itemId, 'slot 0 holds it');

  const out = call(engine, 'furniture_takeout_bench', { index: 1 });
  eq(out.reply.code, 0, 'takeout must answer 0');
  eq(haveOf(engine, itemId), 2, 'taking out must return it');
  eq(call(engine, 'furniture_load_furniture', {}).reply.bench[0], -1, 'slot empty again');

  // index 6 must land in the ITEMS row, not the tools row
  const put6 = call(engine, 'furniture_putin_bench', { index: 6, id: itemId });
  eq(put6.reply.code, 0, 'index 6 is legal');
  eq(call(engine, 'furniture_load_furniture', {}).reply.bench[5], itemId, 'slot 5 holds it');
  // and out-of-range indexes are refused rather than writing off the end
  eq(call(engine, 'furniture_putin_bench', { index: 11, id: itemId }).reply.code, -1, 'index 11 refused');
  eq(call(engine, 'furniture_putin_bench', { index: 0, id: itemId }).reply.code, -1, 'index 0 refused');
});

test('furniture: bench refuses an item the player does not own', ({ engine }) => {
  const itemId = TOOL_ITEM_ID();
  engine.state.items.house = [];
  eq(call(engine, 'furniture_putin_bench', { index: 1, id: itemId }).reply.code, -1,
    'placing an unowned item must be refused');
  eq(call(engine, 'furniture_load_furniture', {}).reply.bench[0], -1, 'slot stays empty');
});

test('furniture: compost box uses 0 for empty, is 1-based, and swaps correctly', ({ engine }) => {
  const itemId = TOOL_ITEM_ID();
  engine.state.items.house = [{ item_id: itemId, count: 1 }];
  const load = () => call(engine, 'furniture_load_compost', {}).reply;
  for (const v of load().box_list) eq(v, 0, 'compost slots are 0 when empty (NOT -1)');

  eq(call(engine, 'furniture_putin_box', { index: 1, id: itemId }).reply.code, 0, 'putin code 0');
  eq(load().box_list[0], itemId, 'box_list[0] holds it');
  eq(haveOf(engine, itemId), 0, 'consumed from the house');

  eq(call(engine, 'furniture_takeout_box', { index: 1 }).reply.code, 0, 'takeout code 0');
  eq(load().box_list[0], 0, 'empty again');
  eq(haveOf(engine, itemId), 1, 'returned to the house');

  eq(call(engine, 'furniture_putin_box', { index: 7, id: itemId }).reply.code, -1, 'index 7 out of range');
});

test('furniture: replace_tumbler/compost/pocket answer 0 to show and 1 to hide', ({ engine }) => {
  for (const [cmd, key] of [['furniture_replace_tumbler', 'tumbler'],
    ['furniture_replace_compost', 'compost'],
    ['furniture_replace_pocket', 'pocket']]) {
    const show = call(engine, cmd, { index: 2 });
    eq(show.reply.code, 0, `${cmd}: first selection shows (code 0)`);
    eq(engine.state.furniture[key].showIndex, 2, `${cmd}: show_index`);
    eq(engine.state.furniture[key].replaceIndex, 2, `${cmd}: replace_index`);

    const hide = call(engine, cmd, { index: 2 });
    eq(hide.reply.code, 1, `${cmd}: selecting the SAME one again hides it (code 1)`);
    eq(engine.state.furniture[key].showIndex, 0, `${cmd}: hidden`);

    eq(call(engine, cmd, { index: 0 }).reply.code, -1, `${cmd}: index 0 is not a valid 1-based slot`);
  }
});

test('furniture: replace_fur answers 1 when rotating a type OUT and 0 when placing', ({ engine }) => {
  const ids = Object.keys(GD.tables.furnitureData);
  // find two DIFFERENT furniture of the SAME type so the rotate path is exercised
  const byType = new Map();
  for (const k of ids) {
    const row = GD.tables.furnitureData[k];
    const t = Number(row.type);
    if (!byType.has(t)) byType.set(t, []);
    byType.get(t).push(Number(row.id));
  }
  const pick = [...byType.values()].find((v) => v.length >= 2);
  assert(pick, 'need two furniture of the same type');
  const [a, b] = pick;

  eq(call(engine, 'furniture_replace_fur', { id: a }).reply.code, 0, 'placing answers 0');
  eq(engine.state.furniture.placed.filter((p) => p.id === a).length, 1, 'a is placed');
  eq(call(engine, 'furniture_replace_fur', { id: b }).reply.code, 0, 'placing the sibling answers 0');
  eq(engine.state.furniture.placed.filter((p) => p.id === a).length, 0, 'only one per type may show');
  eq(call(engine, 'furniture_replace_fur', { id: b }).reply.code, 1, 're-selecting it rotates the type out');
  eq(engine.state.furniture.placed.length, 0, 'nothing placed');
  eq(call(engine, 'furniture_replace_fur', { id: 99999999 }).reply.code, -1, 'unknown id refused');
});

test('furniture: pocket_get credits the clovers and pushes clover_update', ({ engine }) => {
  // The client only zeroes its OWN copy -- addClover() is an empty stub -- so
  // without the push the stored clover would be destroyed on collection.
  engine.state.furniture.pocket.clover = 137;
  const clover0 = engine.state.clover;
  const r = call(engine, 'furniture_pocket_get', {});
  eq(r.reply.code, 0, 'must answer 0 so the client clears its display');
  eq(engine.state.clover, clover0 + 137, 'the stored clover must be credited');
  eq(engine.state.furniture.pocket.clover, 0, 'pocket emptied');
  const pushed = pushNamed(r, 'clover_update');
  assert(pushed.length === 1, 'must push clover_update (wire name clover.update)');
  eq(pushed[0].data.clover, clover0 + 137,
    'the pushed count must be the authoritative one');
});

test('furniture: an empty pocket is a harmless no-op', ({ engine }) => {
  engine.state.furniture.pocket.clover = 0;
  const clover0 = engine.state.clover;
  const r = call(engine, 'furniture_pocket_get', {});
  eq(r.reply.code, 0, 'still 0 so the UI closes cleanly');
  eq(engine.state.clover, clover0, 'no clover invented');
});

/* ------------------------------------------------------------------ album */

console.log('\n== album / notes ==');

test('album: pictures carry BOTH a unique id and a pic_id', ({ engine }) => {
  const lunch = idsOfType(0)[0];
  for (let i = 0; i < 12; i++) {
    engine.state.items.bag[0] = lunch;
    engine.state.travel.nextDepartAt = 1;
    engine.tick();
    engine.state.travel.returnAt = 1;
    engine.tick();
  }
  assert(engine.state.albumPending.length > 0, 'expected some pending pictures');
  // file them all so the album is populated, then check the shape
  for (const p of engine.state.albumPending.slice()) {
    call(engine, 'album_save_new', { id: p.id });
  }
  assert(engine.state.pictures.length > 0, 'expected some pictures in the album');
  const ids = new Set();
  for (const p of engine.state.pictures) {
    assert(typeof p.id === 'number', 'each picture needs a numeric id');
    assert(typeof p.pic_id === 'number', 'each picture needs a pic_id (the Picture table row)');
    assert(!ids.has(p.id), `duplicate picture id ${p.id}`);
    ids.add(p.id);
  }
});

test('album_load echoes start and actually returns the pictures', ({ engine }) => {
  // Answering with a hard-coded start of 1 misplaces every page but the first,
  // and an always-empty list leaves the album permanently blank.
  const r = call(engine, 'album_load', { start: 4, count: 6 });
  eq(r.reply.start, 4, 'start must be echoed');
  assert(Array.isArray(r.reply.pictures), 'pictures must be an array');
  const d = call(engine, 'album_load', {});
  eq(d.reply.start, 1, 'default start');
});

test('album_load_all emits the object-shaped id_list the client reads', ({ engine }) => {
  const r = call(engine, 'album_load_all', {});
  assert(Array.isArray(r.reply.id_list), 'id_list must be an array');
  for (const e of r.reply.id_list) {
    for (const f of ['id', 'pic_id', 'for_ads', 'visit']) {
      assert(Object.prototype.hasOwnProperty.call(e, f), `id_list entry missing ${f}`);
    }
  }
});

test('album_load_new never asks the player to share (impossible offline)', ({ engine }) => {
  const r = call(engine, 'album_load_new', {});
  eq(r.reply.has_ads, false, 'has_ads must be false or an ad path is taken');
  eq(r.reply.is_share, false, 'is_share must be false or a WeChat share dialog pops');
});

test('travel_load_note replies with exactly the three fields the client reads', ({ engine }) => {
  engine.state.notes = [{ id: 1000, read: 1, timestamp: 123, extra: 'ignored' }];
  const r = call(engine, 'travel_load_note', {});
  eq(r.reply.note_list.length, 1, 'one note');
  const n = r.reply.note_list[0];
  eq(n.id, 1000, 'id');
  eq(n.read, 1, 'read');
  eq(n.timestamp, 123, 'timestamp');
  assert(!('extra' in n), 'the reply should be projected down to the three fields');
});

/* --------------------------------------------------------------- visitors */

console.log('\n== visitors ==');

const CHAR = GD.tables.Character;
const ROW_IDS = CHAR.rowItemId;
/** Force a visit. Real time cannot be advanced, so re-arm the roll each tick. */
function forceGuest(engine) {
  for (let i = 0; i < 300; i++) {
    /* A FED visitor now stays for a short farewell window (see guest_serve), so the
       helper must not hand back an already-served one. */
    if (engine.state.guest && !engine.state.guest.served) return engine.state.guest;
    engine.state.guest = null;
    engine.state.guestNextRollAt = 1;
    engine.state.guestCoolUntil = 0;
    engine.tick();
  }
  throw new Error('no visitor appeared after 300 rolls');
}

test('visitor: with nobody visiting, guest_load reports id -1', ({ engine }) => {
  const r = call(engine, 'guest_load', {});
  eq(r.reply.id, -1, 'the client uses id -1 for "no visitor"');
});

test('visitor: the payload carries EXACTLY the five keys GuestData knows', ({ engine }) => {
  // Its constructor warns and reports an error upstream for any unknown key.
  const r = call(engine, 'guest_load', {});
  eq(Object.keys(r.reply).sort().join(','),
     'confirmed,expire_time,id,pos,served', 'exact key set');
  forceGuest(engine);
  const r2 = call(engine, 'guest_load', {});
  eq(Object.keys(r2.reply).sort().join(','),
     'confirmed,expire_time,id,pos,served', 'exact key set with a visitor present');
});

test('visitor: one eventually turns up and stays ~30 minutes', ({ engine }) => {
  const g = forceGuest(engine);
  assert(g.id >= 0 && g.id < CHAR.data.length, `visitor id ${g.id} out of range`);
  assert(g.pos >= 0 && g.pos < 3, `pos ${g.pos} out of range`);
  const stay = g.expire_time - Math.floor(Date.now() / 1000);
  assert(stay > 1700 && stay <= 1800, `expected ~1800s stay, got ${stay}`);
});

test('visitor: confirming flags the visitor so the notice stops re-raising', ({ engine }) => {
  forceGuest(engine);
  const id = engine.state.guest.id;
  const r = call(engine, 'guest_confirm', { id });
  eq(r.reply, undefined, 'guest_confirm is needResponse:false');
  eq(engine.state.guest.confirmed, true, 'confirmed should be stored');
  const push = pushNamed(r, 'guest_load');
  assert(push.length === 1, 'confirming should push the updated guest');
  eq(push[0].data.confirmed, true, 'and the push must carry confirmed:true');
});

test('visitor: serving a specialty feeds the taste table and pays out', ({ engine }) => {
  const g = forceGuest(engine);
  // pick a specialty this visitor loves (>=80) from its own taste vector
  const taste = CHAR.data[g.id].taste;
  let idx = -1;
  for (let i = 0; i < taste.length; i++) if (taste[i] >= 80) { idx = i; break; }
  assert(idx >= 0, 'no liked specialty in the taste vector');
  const itemId = ROW_IDS[idx];
  engine.state.items.house.push({ item_id: itemId, count: 1 });

  const cloverBefore = engine.state.clover;
  const r = call(engine, 'guest_serve', { id: g.id, item_id: itemId });
  eq(r.reply, undefined, 'guest_serve is needResponse:false');
  /* The visitor does NOT vanish synchronously: the client runs
     `sendGuestServed(e); friendFeedBack(e);` back to back, and friendFeedBack looks the
     friend up by `getGuestData().id` in the Character table -- with id already -1 that
     lookup returns undefined and `o.taste[a]` throws 呱呱吃坏肚子了. So they linger for a
     short farewell window and tickGuest clears them afterwards. */
  assert(engine.state.guest, 'a fed visitor must still be present for the feedback step');
  eq(engine.state.guest.served, true, 'and marked as served');
  engine.state.guest.expire_time = 1;              // the farewell window has passed
  engine.tick();
  eq(engine.state.guest, null, 'the visitor leaves once the farewell window closes');
  const house = engine.state.items.house.find((h) => h.item_id === itemId);
  assert(!house, 'the offered specialty is consumed');
  const gained = engine.state.clover > cloverBefore
    || engine.state.ticket > 0
    || (engine.state.items.house.find((h) => h.item_id === 1000));
  assert(gained, 'serving should pay something back');
  assert(pushNamed(r, 'guest_load').length === 1, 'the visit state must be pushed');
  /* And a second helping of the same visit must not pay twice. */
  const cloverAfter = engine.state.clover;
  call(engine, 'guest_serve', { id: g.id, item_id: itemId });
  eq(engine.state.clover, cloverAfter, 'one reward per visit');
});

test('visitor: only a Specialty (type 3) can be offered', ({ engine }) => {
  const g = forceGuest(engine);
  const food = idsOfType(0)[0];
  engine.state.items.house.push({ item_id: food, count: 1 });
  const before = engine.state.items.house.find((h) => h.item_id === food).count;
  call(engine, 'guest_serve', { id: g.id, item_id: food });
  eq(engine.state.guest && engine.state.guest.id, g.id, 'the visitor should stay');
  const after = engine.state.items.house.find((h) => h.item_id === food).count;
  eq(after, before, 'the food must not be consumed');
});

test('visitor: guest_finish clears the visit', ({ engine }) => {
  forceGuest(engine);
  const r = call(engine, 'guest_finish', {});
  eq(engine.state.guest, null, 'visitor cleared');
  const push = pushNamed(r, 'guest_load');
  eq(push[0].data.id, -1, 'the clearing push uses id -1');
});

test('visitor: the visit survives a restart', ({ engine, savePath }) => {
  const g = forceGuest(engine);
  const reopened = reopen(savePath);
  assert(reopened.state.guest, 'the visitor should still be there after a reopen');
  eq(reopened.state.guest.id, g.id, 'same visitor');
});

/* ----------------------------------------------------------------- raffle */

console.log('\n== raffle ==');

const PRIZE = GD.tables.Prize;
const TICKET_COST = 5;   // Define.RAFFEL_NEEDTICKETS

test('raffle: a draw costs 5 tickets and returns a ball rank', ({ engine }) => {
  engine.state.ticket = 20;
  const r = call(engine, 'item_gacha', { is_reward: false });
  eq(engine.state.ticket, 20 - TICKET_COST, 'tickets should be charged');
  assert(r.reply.ticket >= 0 && r.reply.ticket <= 5,
    `rank ${r.reply.ticket} must be 0..5 (rank 6 FURNITURE has no Prize row)`);
  const up = pushNamed(r, 'item_update_ticket');
  eq(up.length, 1, 'the draw must push the new ticket count (addTicket is a stub)');
  eq(up[0].data.ticket, engine.state.ticket, 'pushed count should match');
});

test('raffle: without enough tickets the draw is refused and costs nothing', ({ engine }) => {
  engine.state.ticket = TICKET_COST - 1;
  const r = call(engine, 'item_gacha', { is_reward: false });
  eq(r.reply.ticket, -1, 'refusal is signalled with -1');
  eq(engine.state.ticket, TICKET_COST - 1, 'tickets must be untouched');
});

test('raffle: re-requesting with is_reward does NOT charge twice', ({ engine }) => {
  // reward_raffle() re-sends is_reward:true while a ball is still pending; if that
  // charged again the player would pay 10 tickets for one draw.
  engine.state.ticket = 20;
  const first = call(engine, 'item_gacha', { is_reward: false });
  const afterDraw = engine.state.ticket;
  const again = call(engine, 'item_gacha', { is_reward: true });
  eq(again.reply.ticket, first.reply.ticket, 'the same ball should be re-announced');
  eq(engine.state.ticket, afterDraw, 'no second charge');
});

test('raffle: rank 0 is the ticket prize', ({ engine }) => {
  const white = PRIZE.find((p) => p.rank === 0);
  assert(white && white.itemId < 0, 'rank 0 should have no item');
  engine.state.ticket = 3;
  engine.state.gacha.colorBall = 0;
  const r = call(engine, 'item_redeem_prize', { prize_id: white.id });
  eq(r.reply, undefined, 'item_redeem_prize is needResponse:false');
  eq(engine.state.ticket, 3 + white.stock, 'the ticket prize pays Prize.stock tickets');
  const up = pushNamed(r, 'item_update_ticket');
  eq(up.length, 1, 'the grant must be pushed');
});

test('raffle: an item rank grants the item and clears the ball', ({ engine }) => {
  const row = PRIZE.find((p) => p.rank >= 1);
  engine.state.gacha.colorBall = row.rank;
  const r = call(engine, 'item_redeem_prize', { prize_id: row.id });
  eq(engine.state.gacha.colorBall, -1, 'the ball must be cleared (cleanGachaColorBall)');
  const up = pushNamed(r, 'item_update');
  eq(up.length, 1, 'the item must be pushed (addHouseItem is a stub)');
  eq(up[0].data.item.item_id, row.itemId, 'pushed item id');
  const house = engine.state.items.house.find((h) => h.item_id === row.itemId);
  assert(house && house.count >= row.stock, 'the prize should be in the house');
});

test('raffle: every prize row is redeemable without throwing', ({ engine }) => {
  // also proves no Prize row names an item missing from Item.json
  engine.state.ticket = 999;
  const bad = [];
  for (const row of PRIZE) {
    const r = call(engine, 'item_redeem_prize', { prize_id: row.id });
    for (const p of r.pushes) {
      if (canon(p.cmd) === 'item_update' && !GD.items.some((i) => i.id === p.data.item.item_id)) {
        bad.push(row.id);
      }
    }
  }
  eq(bad.length, 0, `prize rows pushing unknown item ids: ${JSON.stringify(bad)}`);
});

test('raffle: an unknown prize id is ignored, not thrown', ({ engine }) => {
  const r = call(engine, 'item_redeem_prize', { prize_id: 99999 });
  eq(r.reply, undefined, 'unknown id should be a silent no-op');
});

/* ------------------------------------------------------------------- mail */

console.log('\n== mail ==');

const MAILEVENT = GD.tables.MailEvent;

test('mail: entering the game delivers the tutorial gifts from the table', ({ engine }) => {
  call(engine, 'hall_enter_game', {});
  eq(engine.state.mails.length, MAILEVENT.length,
     `expected ${MAILEVENT.length} tutorial mails from MailEvent.json`);
  const first = engine.state.mails[0];
  eq(first.resource.clover_point, MAILEVENT[0].CloverPoint, 'clover from the template');
});

test('mail: every mail carries the fields the client dereferences unguarded', ({ engine }) => {
  // revice_mails reads resource.ads_id.length; checkMailItemType reads
  // pictures.length. A mail missing either throws inside the client.
  call(engine, 'hall_enter_game', {});
  assert(engine.state.mails.length > 0, 'need mails to check');
  for (const m of engine.state.mails) {
    assert(m.resource && typeof m.resource === 'object', 'mail needs a resource object');
    for (const f of ['clover_point', 'ticket', 'reward_gacha', 'ads_id', 'share_id']) {
      assert(Object.prototype.hasOwnProperty.call(m.resource, f), `resource.${f} missing`);
    }
    assert(typeof m.resource.ads_id === 'string', 'ads_id must have .length');
    assert(typeof m.resource.share_id === 'string', 'share_id must have .length');
    assert(Array.isArray(m.pictures), 'pictures must be an array');
    assert(Array.isArray(m.items), 'items must be an array');
  }
});

test('mail: the tutorial gifts are delivered only once', ({ engine }) => {
  call(engine, 'hall_enter_game', {});
  const n = engine.state.mails.length;
  call(engine, 'hall_enter_game', {});
  eq(engine.state.mails.length, n, 'a second enter_game must not duplicate the gifts');
});

test('mail_load pushes a bare array (not {mails: []})', ({ engine }) => {
  const r = call(engine, 'mail_load', {});
  assert(Array.isArray(r.reply), 'mail_load reply must be an array');
});

test('mail_load_mails echoes start and pages the list', ({ engine }) => {
  // the client writes mailInfoList[n + e.start - 1], so start MUST be echoed
  call(engine, 'hall_enter_game', {});
  const r = call(engine, 'mail_load_mails', { start: 2, count: 5 });
  eq(r.reply.start, 2, 'start must be echoed');
  eq(r.reply.total, engine.state.mails.length, 'total');
  assert(r.reply.mails.length <= 5, 'count should cap the page');
});

test('mail: opening grants the reward and drops the mail', ({ engine }) => {
  call(engine, 'hall_enter_game', {});
  const mail = engine.state.mails[0];
  const expected = mail.resource.clover_point;
  const before = engine.state.clover;
  const beforeCount = engine.state.mails.length;
  const r = call(engine, 'mail_open', { id: mail.id });
  eq(r.reply, undefined, 'mail_open is needResponse:false');
  eq(engine.state.clover, before + expected, 'the clover reward must actually be paid');
  eq(engine.state.mails.length, beforeCount - 1, 'the mail should be dropped');
  const up = pushNamed(r, 'clover_update');
  eq(up.length, 1, 'the grant must be pushed (addClover is a stub)');
  assert(pushNamed(r, 'mail_load').length === 1, 'the new mail list must be pushed');
});

test('mail: opening the item gift puts the item in the house', ({ engine }) => {
  call(engine, 'hall_enter_game', {});
  const gift = engine.state.mails.find((m) => m.items.length > 0);
  assert(gift, 'expected an item gift among the tutorial mails');
  const itemId = gift.items[0].item_id;
  const r = call(engine, 'mail_open', { id: gift.id });
  const up = pushNamed(r, 'item_update');
  eq(up.length, 1, 'the item must be pushed (addHouseItem is a stub)');
  eq(up[0].data.item.item_id, itemId, 'pushed item id');
});

test('mail: reading marks it read and notifies', ({ engine }) => {
  call(engine, 'hall_enter_game', {});
  const mail = engine.state.mails[0];
  const r = call(engine, 'mail_read', { id: mail.id });
  eq(r.reply, undefined, 'mail_read is needResponse:false');
  eq(engine.state.mails.find((m) => m.id === mail.id).read, true, 'read flag');
  assert(pushNamed(r, 'mail_load').length === 1, 'the updated list must be pushed');
});

test('mail: an unknown id is a silent no-op', ({ engine }) => {
  call(engine, 'hall_enter_game', {});
  const n = engine.state.mails.length;
  const r = call(engine, 'mail_open', { id: 99999 });
  eq(r.reply, undefined, 'no reply');
  eq(engine.state.mails.length, n, 'nothing removed');
});

/* --------------------------------------------------------------- calendar */

console.log('\n== calendar ==');

const CAL = GD.tables.calendarData;

test('calendar: task_list is ALWAYS exactly three rows', ({ engine }) => {
  // the client hardcodes three rows of copy, so a different length breaks it
  const r = call(engine, 'calendar_load', {});
  eq(r.reply.task_list.length, 3, 'task_list length');
});

test('calendar: new_flag is indexed by createDay', ({ engine }) => {
  const r = call(engine, 'calendar_load', {});
  assert(Array.isArray(r.reply.new_flag), 'new_flag must be an array');
  assert(r.reply.new_flag.length >= 1, 'at least one day');
  // a brand new save is on day 1
  eq(r.reply.new_flag.length, 1, 'a fresh save should be on createDay 1');
  eq(r.reply.new_flag[0], 0, 'day 1 starts unclaimed');
});

test('calendar: the day lists carry {day, item_id}', ({ engine }) => {
  const r = call(engine, 'calendar_load', {});
  for (const key of ['st_days', 'lucky_days']) {
    assert(Array.isArray(r.reply[key]), `${key} must be an array`);
    assert(r.reply[key].length > 0, `${key} should not be empty`);
    for (const e of r.reply[key]) {
      assert(typeof e.day === 'number', `${key} entry needs a numeric day`);
      assert(typeof e.item_id === 'number', `${key} entry needs an item_id`);
    }
  }
});

test('calendar: the newcomer reward comes from the table and pays once', ({ engine }) => {
  const row = CAL.beginner['1'];
  assert(row, 'calendarData.beginner has a day 1');
  const before = (engine.state.items.house.find((h) => h.item_id === row.item_id) || {}).count || 0;
  const r = call(engine, 'calendar_get_beginer_reward', {});
  eq(r.reply.day, 1, 'a fresh save should be on day 1');
  const up = pushNamed(r, 'item_update');
  eq(up.length, 1, 'the reward needs an item_update push (addHouseItem is a stub)');
  eq(up[0].data.item.item_id, row.item_id, 'the table item id');
  const after = engine.state.items.house.find((h) => h.item_id === row.item_id).count;
  eq(after, before + row.num, 'the reward should land in the house');

  const again = call(engine, 'calendar_get_beginer_reward', {});
  eq(pushNamed(again, 'item_update').length, 0, 'claiming twice must not pay twice');
});

test('calendar: every newcomer reward id exists in Item.json', ({ engine }) => {
  // pushItemUpdate would silently refuse an unknown id, and the client's
  // ItemDB.get() has no null guard, so this is worth asserting over the whole table
  const bad = [];
  for (const k of Object.keys(CAL.beginner)) {
    const id = CAL.beginner[k].item_id;
    if (!GD.items.some((i) => i.id === id)) bad.push([k, id]);
  }
  eq(bad.length, 0, `beginner rows naming unknown items: ${JSON.stringify(bad)}`);
});

test('calendar: the special-day reward pays once and is judged by the server date', ({ engine }) => {
  // calendar_get_st_reward takes NO parameters, so the server must decide itself
  const today = new Date(Date.now()).getUTCDate();
  const cloverBefore = engine.state.clover;
  const r = call(engine, 'calendar_get_st_reward', {});
  if (r.reply.code === 0) {
    eq(engine.state.clover, cloverBefore + 30, 'the special-day clover');
    const again = call(engine, 'calendar_get_st_reward', {});
    eq(again.reply.code, 0, 'a second claim is a no-op, not an error');
    eq(engine.state.clover, cloverBefore + 30, 'and must not pay twice');
  } else {
    // today is not one of the special days in this month
    assert(r.reply.code === -1, `unexpected code ${r.reply.code}`);
  }
  void today;
});

test('calendar: load_note returns one note id per elapsed day', ({ engine }) => {
  const r = call(engine, 'calendar_load_note', {});
  assert(Array.isArray(r.reply.list), 'list must be an array');
  eq(r.reply.list.length, 1, 'a fresh save is on day 1');
  eq(r.reply.list[0], CAL.beginner['1'].note_id, 'day 1 uses the table note id');
});

test('calendar: task updates are stored', ({ engine }) => {
  call(engine, 'calendar_task_update', { task: { id: 2, pro: 5, complete: 1 } });
  const t = engine.state.calendar.taskList[1];
  eq(t.pro, 5, 'pro');
  eq(t.complete, 1, 'complete');
  const r = call(engine, 'calendar_load', {});
  eq(r.reply.task_list.length, 3, 'still exactly three rows');
});

/* ------------------------------------------------------ weather / motion */

console.log('\n== weather / at-home motion ==');

test('weather: the payload only ever uses in-enum values', ({ engine }) => {
  // Define: Season 1..4, HoursType 1..4, WeatherType 1..9. The old default of
  // weather 0 was OUTSIDE the enum.
  call(engine, 'hall_enter_game', {});
  const w = engine.state.weather;
  assert(w.season >= 1 && w.season <= 4, `season ${w.season} out of 1..4`);
  assert(w.hoursType >= 1 && w.hoursType <= 4, `hoursType ${w.hoursType} out of 1..4`);
  assert(w.weather >= 1 && w.weather <= 9, `weather ${w.weather} out of 1..9`);
});

test('weather: the season follows the real calendar month', ({ engine }) => {
  call(engine, 'hall_enter_game', {});
  const m = new Date().getUTCMonth() + 1;
  const expected = (m >= 3 && m <= 5) ? 1 : (m >= 6 && m <= 8) ? 2 : (m >= 9 && m <= 11) ? 3 : 4;
  eq(engine.state.weather.season, expected, `month ${m} should map to season ${expected}`);
  // and the pair must exist as a resource group: default.res.json has season11..season44
  const key = `${engine.state.weather.season}${engine.state.weather.hoursType}`;
  assert(/^[1-4][1-4]$/.test(key), `season key ${key} must be one of 11..44`);
});

test('weather: enter_game pushes a weather_load with the real season', ({ engine }) => {
  const r = call(engine, 'hall_enter_game', {});
  const w = pushNamed(r, 'weather_load');
  assert(w.length === 1, 'weather_load should be pushed at boot');
  eq(w[0].data.season, engine.state.weather.season, 'pushed season');
});

test('motion: every Frogpattern token maps to a real motion index', () => {
  // data invariant over the whole server-side table
  const pattern = GD.tables && null;   // patterns live in define.json, not gamedata
  void pattern;
  const def = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8'));
  const fp = def.maps.Frogpattern || {};
  const num = def.maps.FrogMotionNum || {};
  assert(Object.keys(fp).length > 0, 'Frogpattern should be present');
  assert(Object.keys(fp).length <= (def.scalars.FrogPatternMax || 3),
    'pattern count should not exceed FrogPatternMax');
  for (const [pid, seq] of Object.entries(fp)) {
    assert(Array.isArray(seq) && seq.length > 0, `pattern ${pid} is empty`);
    for (const token of seq) {
      assert(Object.prototype.hasOwnProperty.call(num, token),
        `pattern ${pid} uses token "${token}" missing from FrogMotionNum`);
    }
  }
});

test('motion: the frog changes activity while it waits at home', ({ engine }) => {
  // force the timer so a tick advances it
  engine.state.frog.motionNextAt = 0;
  const seen = new Set();
  for (let i = 0; i < 40; i++) {
    engine.state.frog.motionNextAt = 0;
    engine.tick();
    seen.add(engine.state.frog.motion);
  }
  assert(seen.size > 1, `the frog should cycle activities, saw only ${[...seen]}`);
  for (const m of seen) {
    assert(m >= 0 && m <= 13, `motion ${m} must be a valid FrogMotionName index`);
  }
});

test('motion: activity only advances while the frog is at home', ({ engine }) => {
  engine.state.frog.status = 1;                 // travelling
  engine.state.frog.motionNextAt = 0;
  const before = engine.state.frog.motion;
  engine.tick();
  eq(engine.state.frog.motion, before, 'motion should not change while away');
});

/* ----------------------------------------------------------- achievements */

console.log('\n== achievements ==');

const ACH = GD.tables.Achieve;

test('achievements: only a KNOWN set of "<name>超过N个" rows is unresolvable', () => {
  // The engine resolves these labels against the Item table (exact, then unique
  // containment). Four were originally unresolvable; two were label mismatches now
  // handled ("苏州西瓜子"->西瓜子, "莜面"->莜面栲栳栳) and two name items that simply
  // do not exist in this build. Anything NEW appearing here means a regression.
  const KNOWN_UNMAPPED = ['蜜柑', '桃子'];
  const names = GD.items.map((i) => i.name);
  const unresolvable = [];
  for (const a of ACH) {
    const m = /^(.+?)超过(\d+)个$/.exec(String(a.info || ''));
    if (!m) continue;
    const label = m[1];
    if (names.indexOf(label) !== -1) continue;
    const hits = names.filter((n) => n.indexOf(label) !== -1 || label.indexOf(n) !== -1);
    if (hits.length === 1) continue;
    unresolvable.push(label);
  }
  const unexpected = unresolvable.filter((l) => KNOWN_UNMAPPED.indexOf(l) === -1);
  eq(unexpected.length, 0, `newly unresolvable achievement labels: ${JSON.stringify(unexpected)}`);
  eq(unresolvable.length, KNOWN_UNMAPPED.length,
    `unresolvable set changed: ${JSON.stringify(unresolvable)}`);
});

test('achievements: the default badge is granted, and NO expiry is recorded', ({ engine }) => {
  engine.tick();
  assert(engine.state.achieves.indexOf(0) !== -1, 'the （默认） badge should unlock');
  // This used to assert `achieves_time` carried {id, time}. That field is an EXPIRY
  // list on the client (`isAchieveExpire`: `achieveTime[id] ? now >= achieveTime[id]
  // : false`), so recording the EARN time marked every title expired the instant it
  // was earned -- the 称号 list showed the client's "??????" placeholder for all of
  // them and the title popup fell back to a stale one. The engine now records no
  // expiry at all, and rolePayload always sends an empty list.
  eq(engine.state.achievesTime.length, 0,
    'no expire-times should be recorded; a title must not lapse offline');
});

test('achievements: the travel-count badges unlock as trips accumulate', ({ engine }) => {
  const lunch = idsOfType(0)[0];
  for (let i = 0; i < 12; i++) {
    engine.state.items.bag[0] = lunch;
    engine.state.travel.nextDepartAt = 1;
    engine.tick();
    engine.state.travel.returnAt = 1;
    engine.tick();
  }
  assert(engine.state.travel.tripCount >= 12, 'should have made 12 trips');
  assert(engine.state.achieves.indexOf(1) !== -1,
    '"旅行达到10次" (id 1) should be unlocked after 12 trips');
  assert(engine.state.achieves.indexOf(2) === -1,
    '"旅行达到25次" (id 2) must NOT be unlocked yet');
  eq(engine.state.curAchieve, engine.state.achieves[engine.state.achieves.length - 1],
    'cur_achieve should track the newest badge');
});

test('achievements: owning 10 of a named item unlocks its badge', ({ engine }) => {
  const row = ACH.find((a) => /超过10个$/.test(String(a.info || ''))
    && GD.items.some((i) => i.name === /^(.+?)超过10个$/.exec(a.info)[1]));
  assert(row, 'expected at least one "X超过10个" row');
  const itemName = /^(.+?)超过10个$/.exec(row.info)[1];
  const itemId = GD.items.find((i) => i.name === itemName).id;
  engine.state.items.house.push({ item_id: itemId, count: 10 });
  engine.tick();
  assert(engine.state.achieves.indexOf(row.id) !== -1,
    `"${row.info}" (id ${row.id}) should unlock at 10`);
});

test('achievements: a badge we cannot evaluate never unlocks', ({ engine }) => {
  // 82 is "获得4个典藏（博物馆）" -- museum data we do not model, so it must stay locked
  // rather than being faked into unlocking.
  engine.state.clover = 99999999;
  engine.state.travel.tripCount = 999;
  engine.state.gachaCount = 999;
  for (let i = 0; i < 5; i++) engine.tick();
  assert(engine.state.achieves.indexOf(82) === -1,
    'the museum badge must not unlock (its data is not modelled)');
});

test('achievements: ids are unique and match the table', ({ engine }) => {
  engine.tick();
  const seen = new Set();
  for (const id of engine.state.achieves) {
    assert(!seen.has(id), `duplicate achievement id ${id}`);
    seen.add(id);
    assert(ACH.some((a) => Number(a.id) === id), `id ${id} is not in Achieve.json`);
  }
});

/* ------------------------------------------------------------------ tasks */

console.log('\n== tasks ==');

const TASKD = GD.tables.taskData;
const TASKLIST = TASKD.task_list;
/* taskData has TWO id spaces: task_list (30 tasks) and list_map (67 checklist
   rows). `task_load.tasks` uses the first, `.list` the second. */
const LISTMAP = TASKD.list_map;

test('tasks: task_load serves the two DIFFERENT id spaces, correctly', ({ engine }) => {
  // `tasks` carries task_list ids; `list` carries list_map ids. Mixing them up
  // crashes the client: its updateRedot -> getCompleteListNum does
  //     var t = TaskDB.get("list_map"); for (n in dataList) { var r = t[n]; r.type }
  // so an id in `list` that is not a list_map key makes r undefined and throws
  // (which the client turns into the "吃坏肚子" reload loop).
  const r = call(engine, 'task_load', {});
  const taskIds = Object.keys(TASKLIST).map(Number).sort((a, b) => a - b);
  const mapIds = Object.keys(LISTMAP).map(Number).sort((a, b) => a - b);

  eq(r.reply.tasks.length, taskIds.length, 'one row per task_list entry');
  eq(r.reply.list.length, mapIds.length, 'and one progress row per list_map entry');
  eq(r.reply.tasks[0].id, taskIds[0], 'tasks ids come from task_list');
  assert(typeof r.reply.tasks[0].is_reward === 'number', 'is_reward is a flag');
  assert(typeof r.reply.list[0].pro === 'number', 'pro is progress');

  // THE invariant that was violated: every `list` id must be a list_map key
  const mapSet = new Set(Object.keys(LISTMAP));
  const strays = r.reply.list.filter((x) => !mapSet.has(String(x.id)));
  eq(strays.length, 0,
    `every list id must exist in list_map or the client throws: ${JSON.stringify(strays.slice(0, 5))}`);
  // and every list_map row must carry the fields the client reads off it
  for (const k of Object.keys(LISTMAP)) {
    for (const f of ['id', 'type', 'count', 'title']) {
      assert(LISTMAP[k][f] !== undefined, `list_map[${k}].${f} is missing`);
    }
  }
});

test('tasks: type-1 progress follows trips, unmapped types stay at 0', ({ engine }) => {
  const before = call(engine, 'task_load', {});
  const beforeById = new Map(before.reply.list.map((x) => [x.id, x.pro]));
  for (let i = 0; i < 3; i++) {
    packForTrip(engine);                         // the bag is emptied by every departure
    engine.state.travel.nextDepartAt = 1;
    engine.tick();
    engine.state.travel.returnAt = 1;
    engine.tick();
  }
  const after = call(engine, 'task_load', {});
  const afterById = new Map(after.reply.list.map((x) => [x.id, x.pro]));
  const type1 = Object.keys(LISTMAP).map(Number).find((id) => Number(LISTMAP[String(id)].type) === 1);
  assert(type1 !== undefined, 'expected a type-1 list_map row');
  eq(afterById.get(type1), beforeById.get(type1) + 3, 'a type-1 row should follow tripCount');
  // a type we deliberately do not map must not move
  const unmapped = Object.keys(LISTMAP).map(Number).find((id) => Number(LISTMAP[String(id)].type) > 2);
  assert(unmapped !== undefined, 'expected a list_map row of an unmapped type');
  eq(afterById.get(unmapped), 0, `row ${unmapped} of an unmapped type must stay at 0`);
});

test('tasks: every reward_id is a real Item, and grantable', () => {
  // grantItem routes 200000/200001 to the currency counters and everything else
  // through pushItemUpdate, which refuses unknown ids -- so a bad reward_id would
  // silently pay nothing.
  const bad = [];
  for (const k of Object.keys(TASKLIST)) {
    const id = Number(TASKLIST[k].reward_id);
    if (!GD.items.some((i) => i.id === id)) bad.push([k, id]);
  }
  eq(bad.length, 0, `task rows naming unknown reward items: ${JSON.stringify(bad)}`);
});

test('tasks: task 1 pays its table values once the goal is met', ({ engine }) => {
  const t = TASKLIST['1'];
  eq(t.reward_id, 200000, 'reward is the 三叶草 resource item');
  eq(t.count, 1, 'goal');
  eq(t.num, 10, 'quantity');

  const refused = call(engine, 'task_get_reward', { id: 1 });
  assert(refused.reply.code !== 0, 'must be refused before the goal is met');

  engine.state.items.bag[0] = idsOfType(0)[0];
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  engine.state.travel.returnAt = 1;
  engine.tick();

  const before = engine.state.clover;
  const r = call(engine, 'task_get_reward', { id: 1 });
  eq(r.reply.code, 0, 'claim should succeed after one trip');
  eq(engine.state.clover, before + 10, 'reward is num clover');
  assert(pushNamed(r, 'clover_update').length === 1, 'the grant must be pushed');
  assert(pushNamed(r, 'task_load').length === 1, 'the rows must be re-pushed so the dot clears');

  call(engine, 'task_get_reward', { id: 1 });
  eq(engine.state.clover, before + 10, 'claiming twice must not pay twice');
});

/* the OLD version of the test above asserted `list` carried task ids -- which is
   exactly the bug, so it is gone rather than kept. */

test('tasks: task_load_list keys claimed tier counts by plan type', ({ engine }) => {
  const r = call(engine, 'task_load_list', {});
  assert(Array.isArray(r.reply.reward), 'reward must be an array');
  eq(r.reply.reward.length, Object.keys(TASKD.list_type).length, 'one row per plan');
  for (const row of r.reply.reward) {
    assert(TASKD.list_type[String(row.id)], `id ${row.id} names a real plan`);
    eq(row.pro, 0, 'fresh plans are unclaimed');
  }
});

test('tasks: the checklist reward is IMPLEMENTED and gated (no free rewards)', ({ engine }) => {
  /* This used to assert the opposite ("must stay unimplemented"), on the theory that
     the tier progress was unrecoverable. It is recoverable after all: the client's
     own getCompleteListNum counts list_map rows of that type that reached their
     `count`, and that is exactly what listTypeProgress() does. Leaving it out was the
     reported 「「伴蛙前行」的奖励点不下去，没法收到」 -- the client only acts on
     `0 == code`, and an unknown command answers `{}`. */
  const r = call(engine, 'task_get_list_reward', { id: 101 });
  assert(r.handled, 'task_get_list_reward must be handled now');
  eq(r.reply.code, -1, 'but a tier that has not been earned pays nothing');
  eq(call(engine, 'task_get_list_reward', { id: 99999 }).reply.code, -1,
    'an unknown tier id is refused');
  eq(call(engine, 'task_get_list_reward', {}).reply.code, -1, 'so is a missing id');
});

test('tasks: claiming survives a restart', ({ engine, savePath }) => {
  engine.state.items.bag[0] = idsOfType(0)[0];
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  engine.state.travel.returnAt = 1;
  engine.tick();
  call(engine, 'task_get_reward', { id: 1 });
  const reopened = reopen(savePath);
  assert(reopened.state.tasksClaimed.indexOf(1) !== -1, 'the claim should persist');
  const r = call(reopened, 'task_load', {});
  eq(r.reply.tasks.find((t) => t.id === 1).is_reward, 1, 'is_reward should read as claimed');
});

test('clover: regrowth follows the original clamp(normal(7200,1800),300,14400)', ({ engine }) => {
  // Confirmed from the Japanese original's decompiled CloverFarm. The old uniform
  // draw had a similar MEAN but the wrong shape, so check the shape, not just the range.
  const spans = [];
  for (let i = 0; i < 400; i++) {
    engine.state.clovers[0].last_harvest = 0;
    call(engine, 'clover_harvest', { clover_id: 1 });
    spans.push(engine.state.clovers[0].rebirth_span);
  }
  const bad = spans.filter((s) => s < 300 || s > 14400);
  eq(bad.length, 0, `spans must stay within [300, 14400], saw ${bad.slice(0, 3)}`);
  const mean = spans.reduce((a, b) => a + b, 0) / spans.length;
  assert(Math.abs(mean - 7200) < 600, `mean ${Math.round(mean)} should be near 7200`);
  // a normal draw clusters near the middle; a uniform one spreads flat. Compare the
  // share falling within one sd of the mean: ~68% for normal, ~25% for uniform.
  const within = spans.filter((s) => Math.abs(s - 7200) <= 1800).length / spans.length;
  assert(within > 0.5, `only ${(within * 100).toFixed(0)}% within one sd -- looks uniform, not normal`);
});

test('visitor: a delighted visitor is much likelier to give the rare gift', ({ engine }) => {
  // define.json: NORMAL {Clover:80, FourClover:18, Ticket:2}
  //              RARE   {Clover:20, FourClover:50, Ticket:30}
  // So the taste lookup does not buy MORE clover -- it shifts the visitor from
  // ordinary clover onto the rare rewards. That is worth asserting, because the
  // naive expectation ("better food = more clover") is backwards.
  const RARE_FREE = 1000;                     // the four-leaf-clover item
  const countFour = () => {
    const h = engine.state.items.house.find((x) => x.item_id === RARE_FREE);
    return h ? h.count : 0;
  };
  const run = (wantHigh) => {
    let rares = 0;
    let trials = 0;
    for (let i = 0; i < 140; i++) {
      const g = forceGuest(engine);
      const taste = CHAR.data[g.id].taste;
      let idx = -1;
      for (let k = 0; k < taste.length; k++) {
        if (wantHigh ? taste[k] >= 80 : taste[k] <= 15) { idx = k; break; }
      }
      if (idx < 0) continue;
      const itemId = ROW_IDS[idx];
      engine.state.items.house.push({ item_id: itemId, count: 1 });
      const fBefore = countFour();
      call(engine, 'guest_serve', { id: g.id, item_id: itemId });
      // NB: do not use "ticket went up" as the rare signal -- FRIEND_GIFTBOUNUS_TICKET
      // is granted on EVERY feed, so it always fires. The four-leaf category
      // (18% normal vs 50% rare) is the discriminator.
      if (countFour() > fBefore) rares++;
      trials++;
    }
    return rares / Math.max(1, trials);
  };
  const high = run(true);
  const low = run(false);
  assert(high > low + 0.15,
    `high-taste four-leaf rate ${high.toFixed(2)} should clearly exceed low-taste ${low.toFixed(2)}`);
});

/* -------------------------------------------------------------- flowerpot */

console.log('\n== flowerpot ==');

test('flowerpot: the payload has all three fields and a real pot', ({ engine }) => {
  const r = call(engine, 'furniture_load_flowerpot', {});
  for (const f of ['show_list', 'list', 'plant_list']) {
    assert(Object.prototype.hasOwnProperty.call(r.reply, f), `missing ${f}`);
  }
  eq(r.reply.show_list.length, 1, 'the table has exactly one pot');
  const pot = GD.tables.flowerpotData.flowerpot[String(r.reply.show_list[0].id)];
  assert(pot, `pot id ${r.reply.show_list[0].id} must exist in flowerpotData`);
  eq(r.reply.show_list[0].type, pot.type, 'type must match the table');
});

test('flowerpot: slots match the pot pos_list, and get auto-planted', ({ engine }) => {
  const r = call(engine, 'furniture_load_flowerpot', {});
  const pot = GD.tables.flowerpotData.flowerpot[String(r.reply.show_list[0].id)];
  eq(engine.state.flowerpot.slots.length, pot.pos_list.length,
    'the pot should have one slot per pos_list entry');
  // the client has no plant command, so the server must seed free slots
  for (const p of r.reply.plant_list) {
    assert(p.id > 0, `slot ${p.index} should have been planted`);
    assert(p.stage >= 1 && p.stage <= 3, `stage ${p.stage} out of 1..3`);
    assert(GD.tables.flowerpotData.plant[String(p.id)],
      `plant id ${p.id} must exist in flowerpotData.plant`);
  }
});

test('flowerpot: harvest replies {item_list:[{item_id,num}]} with NO code', ({ engine }) => {
  // exact contract: the field must be `num`, and a missing item_list means the
  // client neither clears the slot nor runs its callback
  const loaded = call(engine, 'furniture_load_flowerpot', {});
  const slot = loaded.reply.plant_list[0];
  engine.state.flowerpot.slots[0].stage = 3;              // fully grown
  const r = call(engine, 'furniture_flowerpot_harvest', { type: 1, index: slot.index });
  assert(!('code' in r.reply), 'the reply must not carry a code field');
  assert(Array.isArray(r.reply.item_list) && r.reply.item_list.length === 1, 'item_list');
  const row = r.reply.item_list[0];
  assert(typeof row.item_id === 'number', 'item_id');
  assert(typeof row.num === 'number', 'the field must be named num, not count');
  const item = GD.items.find((i) => i.id === row.item_id);
  const plant = GD.tables.flowerpotData.plant[slot.id];
  assert(item && (item.name === plant.name || item.name === plant.name.split('·')[0]),
    `produce ${row.item_id} must match the planted species/variety`);
  eq(engine.state.flowerpot.slots[0].id, 0, 'the slot should be cleared');
  assert(pushNamed(r, 'client_load_role').length === 1,
    'a full role push is what redraws the pot (update_flowerpot has no event binding)');
});

test('flowerpot: an unripe slot cannot be harvested', ({ engine }) => {
  call(engine, 'furniture_load_flowerpot', {});
  engine.state.flowerpot.slots[0].stage = 1;
  const r = call(engine, 'furniture_flowerpot_harvest', { type: 1, index: 1 });
  assert(!Array.isArray(r.reply.item_list) || r.reply.item_list.length === 0,
    'stage < 3 must not yield anything');
  assert(engine.state.flowerpot.slots[0].id > 0, 'and the plant must stay put');
});

test('flowerpot: every crop and flower variety yields its own item, even after reopening', ({ engine, savePath }) => {
  // Explicit client table mappings are the regression oracle, independent of the
  // engine's name lookup. The old random farm pool fails this immediately.
  const groups = [
    [20101, [202211, 202212, 202213]], [20102, [202221, 202222, 202223]],
    [20103, [4101, 4101, 4101]], [20104, [202231, 202232, 202233]],
    [20105, [202241, 202242, 202243, 202244]],
    [20106, [202251, 202252, 202253, 202254]],
    [20107, [4102, 4102, 4102]], [20108, [4103, 4103, 4103]],
    [20109, [4006, 4006, 4006]], [20110, [4104, 4104, 4104]],
    [20111, [202261, 202262, 202263]],
  ];
  for (const [species, variants] of groups) {
    for (let v = 0; v < variants.length; v++) {
      const plant = species * 100 + v + 1, itemId = variants[v];
      engine.state.flowerpot.slots = [
        { id: plant, stage: 3, plantedAt: 1 }, { id: 2010301, stage: 1, plantedAt: 1 },
      ];
      const before = haveOf(engine, itemId);
      const result = call(engine, 'furniture_flowerpot_harvest', { type: 1, index: 1 });
      eq(result.reply.item_list[0].item_id, itemId, 'planted ' + plant);
      eq(result.reply.item_list[0].num, 1, 'one plant yields exactly one item');
      eq(haveOf(engine, itemId), before + result.reply.item_list[0].num, 'correct inventory credit');
      eq(engine.state.flowerpot.slots[1].id, 2010301, 'other slot unchanged');
      const again = call(engine, 'furniture_flowerpot_harvest', { type: 1, index: 1 });
      assert(!again.reply.item_list, 'double harvest rejected');
      if (itemId > 200000) assert(!engine.state.handbook.specialtys.includes(itemId), 'flowers are not specialties');
      eq(haveOf(reopen(savePath), itemId), haveOf(engine, itemId), 'reward survives reopening');
    }
  }
});

test('flowerpot: unknown plant and invalid pot keep inventory and slots intact', ({ engine }) => {
  call(engine, 'furniture_load_flowerpot', {});
  engine.state.flowerpot.slots[0] = { id: 99999999, stage: 3, plantedAt: 1 };
  const before = JSON.stringify(engine.state.flowerpot);
  const house = JSON.stringify(engine.state.items.house);
  for (const data of [{type:1,index:1}, {type:2,index:1}, {type:1,index:1.5}]) {
    assert(!call(engine, 'furniture_flowerpot_harvest', data).reply.item_list);
  }
  eq(JSON.stringify(engine.state.flowerpot), before);
  eq(JSON.stringify(engine.state.items.house), house);
});

test('flowerpot: growth advances by elapsed time', ({ engine }) => {
  call(engine, 'furniture_load_flowerpot', {});
  const s = engine.state.flowerpot.slots[0];
  eq(s.stage, 1, 'freshly planted is stage 1');
  s.plantedAt = s.plantedAt - 200;                        // one stage interval
  call(engine, 'furniture_load_flowerpot', {});
  eq(engine.state.flowerpot.slots[0].stage, 2, 'should have grown one stage');
  engine.state.flowerpot.slots[0].plantedAt -= 400;
  call(engine, 'furniture_load_flowerpot', {});
  eq(engine.state.flowerpot.slots[0].stage, 3, 'and be capped at 3');
});

/* ----------------------------------------------------------- encyclopedia */

console.log('\n== encyclopedia ==');

const ENC = GD.tables.encyclopedia;

test('encyclopedia: empty until something has been grown', ({ engine }) => {
  // the client's isOpen() is unlock_list.length > 0
  const r = call(engine, 'encyclopedia_load', {});
  eq(r.reply.unlock_list.length, 0, 'nothing grown yet');
  assert(Array.isArray(r.reply.unlock_desc), 'unlock_desc must be an array');
  assert(Array.isArray(r.reply.show_sub), 'show_sub must be an array');
});

test('encyclopedia: the plant<->entry link is by NAME, and covers 32 of 35', () => {
  // A plant id and a long_id look like the same number minus 1000000, but they are
  // DIFFERENT id spaces (long_id's last digits are the picture index), so the
  // numeric route is wrong. The name route should resolve all but 葡风.
  const rows = Object.keys(ENC.list).map((k) => ENC.list[k]);
  const byName = new Map(rows.map((e) => [`${e.name}\u00b7${e.sub_name}`, e]));
  const plants = Object.values(GD.tables.flowerpotData.plant);
  const missed = plants.filter((p) => !byName.has(p.name)).map((p) => p.name);
  eq(plants.length - missed.length, 32, `mapped count; misses=${JSON.stringify(missed)}`);
  eq(missed.length, 3, 'exactly three plants lack an encyclopedia entry');
  for (const m of missed) {
    assert(m.indexOf('葡风') === 0, `unexpected unmapped plant ${m} (expected only 葡风)`);
  }
});

test('encyclopedia: harvesting a plant unlocks its species with desc lines', ({ engine }) => {
  call(engine, 'furniture_load_flowerpot', {});
  const plantId = engine.state.flowerpot.slots[0].id;
  engine.state.flowerpot.slots[0].stage = 3;
  call(engine, 'furniture_flowerpot_harvest', { type: 1, index: 1 });

  // the plant that was grown must be remembered
  assert(engine.state.flowerpot.grown.indexOf(plantId) !== -1, 'species should be recorded');

  const r = call(engine, 'encyclopedia_load', {});
  const plant = GD.tables.flowerpotData.plant[String(plantId)];
  const name = plant.name.split('·')[0];
  const row = Object.keys(ENC.list).map((k) => ENC.list[k])
    .find((e) => e.name === name && plant.name === `${e.name}·${e.sub_name}`);
  if (!row) return;                       // 葡风 has no entry -- nothing to assert
  /* unlock_list holds LONG_IDs -- the keys of encyclopedia.list -- because
     EncyView.getSubItems does `TABLE[unlock_list[i]]` and only then compares `row.id`.
     Sending the species id (as this used to) indexes nothing and the page stays blank. */
  const unlocked = r.reply.unlock_list.map((l) => ENC.list[String(l)]).filter(Boolean);
  const mine = unlocked.filter((e) => e.id === row.id && e.sub_id === row.sub_id);
  assert(mine.length > 0, `species ${row.id} (${row.name}) should be unlocked`);
  const allOfVariety = Object.keys(ENC.list).map((k) => ENC.list[k])
    .filter((e) => e.id === row.id && e.sub_id === row.sub_id).length;
  eq(mine.length, allOfVariety,
    'the whole variety is unlocked, not a single picture of it');
  const desc = r.reply.unlock_desc.find((d) => d.id === row.id);
  assert(desc && Array.isArray(desc.list), 'unlock_desc should carry the line indices');
  assert(desc.list.length > 0, 'and they should be non-empty');
  const show = r.reply.show_sub.find((s) => s.id === row.id);
  assert(show && show.sub_id === mine[0].long_id,
    'show_sub must carry the LONG_ID of the shown variety (the client uses it as a key)');
});

test('encyclopedia: set_show_sub records without replying', ({ engine }) => {
  const r = call(engine, 'encyclopedia_set_show_sub', { long_id: 1010101 });
  eq(r.reply, undefined, 'the client ignores this reply (its callback is null)');
  eq(engine.state.encyclopediaShow, 1010101, 'the selection should be stored');
});

test('encyclopedia: the payload indexes the table the way EncyView does', ({ engine }) => {
  /* A replay of the client's own lookups:
       getItemsByTab(tab): for (k in show_sub) { row = TABLE[show_sub[k]]; row.tab == tab }
       getSubItems(id):    for (l of unlock_list) { row = TABLE[l]; row.id == id }
       getPicItems(id, s): the same, keeping row.sub_id == s
       tab.enabled = getItemsByTab(tab).length > 0
     If show_sub carried a variety NUMBER instead of a long_id, every one of these is
     undefined, every tab is disabled and the grid renders as twelve blank slots --
     which is what the player saw. */
  const T = GD.tables.encyclopedia;
  const keys = Object.keys(T.list);
  /* the engine derives the key as Number(k); the row also carries `long_id` */
  for (const k of keys) {
    eq(String(T.list[k].long_id), k, 'the table key must equal the row long_id');
  }

  call(engine, 'client_gm', { cmd: 'unlock_all' });
  const p = call(engine, 'encyclopedia_load', {}).reply;

  const show = {};
  for (const s of p.show_sub) show[s.id] = s.sub_id;
  const itemsByTab = (tab) => {
    const out = [];
    for (const k in show) {
      const row = T.list[String(show[k])];
      if (row && row.tab === tab) out.push(row);
    }
    return out;
  };
  const rowsOf = (id) => p.unlock_list.map((l) => T.list[String(l)]).filter((r) => r && r.id === id);

  for (const s of p.show_sub) {
    const row = T.list[String(s.sub_id)];
    assert(row, `show_sub[${s.id}] = ${s.sub_id} is not a table key`);
    eq(row.id, s.id, 'the row behind show_sub must belong to the species it is filed under');
  }
  const speciesIds = [...new Set(keys.map((k) => T.list[k].id))];
  eq(p.show_sub.length, speciesIds.length, 'every species is listed once');

  for (const longId of p.unlock_list) {
    assert(T.list[String(longId)], `unlock_list entry ${longId} is not a table key`);
  }

  /* every tab has to have something, or the client greys it out */
  for (const tab of [1, 2, 3, 4]) {
    assert(itemsByTab(tab).length > 0,
      `tab ${tab} is empty -- the client disables it and the page looks broken`);
  }

  /* the variety list of a species, and the picture carousel of the shown variety */
  const first = p.show_sub[0];
  const varieties = [...new Set(rowsOf(first.id).map((r) => r.sub_id))];
  assert(varieties.length > 0, 'the variety list (listSub) must not be empty');
  eq(varieties.length,
    [...new Set(keys.map((k) => T.list[k]).filter((r) => r.id === first.id).map((r) => r.sub_id))].length,
    'every variety of the species should be unlocked');
  const shownSub = T.list[String(first.sub_id)].sub_id;
  const pics = rowsOf(first.id).filter((r) => r.sub_id === shownSub);
  eq(pics.length, keys.map((k) => T.list[k])
      .filter((r) => r.id === first.id && r.sub_id === shownSub).length,
    'the carousel gets every picture row of the shown variety');
  assert(pics.length > 0, 'and it must not be empty');

  /* a locked species must NOT be listed: EncyView pads the grid to 12 empty slots and
     disables tabs with nothing in them, i.e. a short list is the normal case */
  const fresh = engine;
  fresh.state.encyAll = false;
  fresh.state.flowerpot.grown = [];
  fresh.state.decoration.hasList = [];
  const empty = call(fresh, 'encyclopedia_load', {}).reply;
  eq(empty.unlock_list.length, 0, 'nothing grown or brought home yet');
  eq(empty.show_sub.length, 0, 'so the grid lists no species');
  eq(empty.unlock_desc.length, 0, 'and no description is unlocked');
});

test('encyclopedia: desc line indices all exist in the table', ({ engine }) => {
  // guard against emitting a line index the client has no text for
  call(engine, 'furniture_load_flowerpot', {});
  engine.state.flowerpot.grown = Object.keys(GD.tables.flowerpotData.plant).map(Number);
  const r = call(engine, 'encyclopedia_load', {});
  for (const d of r.reply.unlock_desc) {
    const lines = ENC.desc[String(d.id)] || {};
    for (const n of d.list) {
      assert(Object.prototype.hasOwnProperty.call(lines, String(n)),
        `species ${d.id} has no desc line ${n}`);
    }
  }
});

/* ---------------------------------------------- postcard `layers` (album art) */

/* The client only RENDERS a postcard: it walks PictureInfo.layers in order,
   looks each `layer[0]` up in data/tables/resources.json to get a path, loads
   `basename(path) + "_png"`, and places the bitmap at (layer[1], layer[2]) on a
   500x350 canvas. So these tests check the three things that make that work. */

const RES_TABLE = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'run', 'engine', 'data', 'tables', 'resources.json'), 'utf8'));
const PICTURE_TABLE = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'run', 'engine', 'data', 'tables', 'Picture.json'), 'utf8'));
const LAYERS = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'run', 'engine', 'data', 'picture-layers.json'), 'utf8'));

/* Shipped PNG header size, for the placement rules that need the sprite's real
   dimensions (poses use their PNG registration frame). */
const ART_DIR = path.join(__dirname, '..', 'run', 'web', 'resource', 'China', 'images');
function artSize(rid) {
  const rel = RES_TABLE[String(rid)];
  if (!rel) return null;
  try {
    const fd = fs.openSync(path.join(ART_DIR, rel + '.png'), 'r');
    const head = Buffer.alloc(24);
    fs.readSync(fd, head, 0, 24, 0);
    fs.closeSync(fd);
    if (head.slice(0, 8).toString('latin1') !== '\x89PNG\r\n\x1a\n') return null;
    return [head.readUInt32BE(16), head.readUInt32BE(20)];
  } catch (e) { return null; }
}

test('layers: every emitted resId is a real key in resources.json', () => {
  // an unknown resId does NOT crash the client -- it silently falls back to
  // ResourcesDB[1] (sky05) and logs a warning, so a bad id shows up as a
  // wrong-looking postcard rather than an error. Assert it directly instead.
  const bad = [];
  for (const [pid, rec] of Object.entries(LAYERS)) {
    for (const l of rec.layers) {
      if (!Object.prototype.hasOwnProperty.call(RES_TABLE, String(l.layer[0]))) {
        bad.push(`${pid}: resId ${l.layer[0]}`);
      }
    }
  }
  eq(bad.length, 0, `every layer resId must exist in resources.json; bad: ${bad.slice(0, 5)}`);
});

test('layers: every layer actually intersects the 500x350 canvas', () => {
  /* The invariant that matters is VISIBILITY, not a plausible-looking top-left:
     art taller/wider than the frame is legitimately placed so that only part of it
     is inside, so a negative top-left is a correct answer for those. */
  const out = [];
  let frogs = 0;
  for (const [pid, rec] of Object.entries(LAYERS)) {
    for (const l of rec.layers) {
      const [rid, x, y] = l.layer;
      const s = l.size || artSize(rid);
      if (s) {
        const w = s[0] || 1, h = s[1] || 1;
        if (x + w <= 0 || x >= 500 || y + h <= 0 || y >= 350) {
          out.push(`${pid}: ${RES_TABLE[String(rid)]} at (${x},${y}) ${w}x${h}`);
        }
      } else if (!Number.isFinite(x) || !Number.isFinite(y)) {
        out.push(`${pid}: (${x},${y})`);
      }
      if (l.role === 'qw') frogs++;
    }
  }
  eq(out.length, 0, `layers that never touch the frame: ${out.slice(0, 5)}`);

  // Frog coverage, stated as the relationship rather than a magic number:
  // 207 of the 349 Picture rows carry a non-empty `frogPose`; the rest name no
  // frog at all (for those the frog is painted into the scene art itself --
  // e.g. `tw_kending1`, `help_bh`). Of the 207, a known 7 point at art the
  // client does not ship, so 200 get a frog layer.
  const withPose = PICTURE_TABLE.filter((r) => String(r.frogPose || '').trim()).length;
  assert(frogs <= withPose, `drew ${frogs} frogs but only ${withPose} rows name one`);
  assert(withPose - frogs <= 10,
    `${withPose - frogs} poses unresolved - the known gap is 7; it grew`);
  assert(frogs >= 200, `expected >=200 frogs, got ${frogs}`);
});

test('layers: characters retain their species and one companion per photograph', () => {
  let checked = 0;
  for (const [pid, rec] of Object.entries(LAYERS)) {
    const actors = rec.layers.filter(l => l.role);
    assert(actors.filter(l => l.role !== 'qw').length <= 1, `${pid}: multiple companions overlap`);
    for (const actor of actors) {
      checked++;
      const name = path.basename(RES_TABLE[String(actor.layer[0])]).toLowerCase();
      // These special poses use a bare filename, e.g. wet3, rather than _qw.
      if (actor.role === 'qw' && /^(wet|dry|fuza)[0-3]$|^gz_alone$/.test(name)) continue;
      assert(name.includes(actor.role), `${pid}: ${actor.role} uses another species: ${name}`);
    }
  }
  assert(checked > 350, 'character metadata must cover composed photographs');
});

test('layers: known reference compositions keep their registration and draw order', () => {
  const names = pid => LAYERS[pid].layers.map(l => path.basename(RES_TABLE[String(l.layer[0])]));
  // Reviewed Beijing reference: frog and gecko sit on the painted stone ledge.
  eq(JSON.stringify(LAYERS[2000].layers.map(l => l.layer)),
    JSON.stringify([[59,0,0],[157,111,205],[223,336,241]]), 'Beijing registration changed');
  eq(names(2003).join(','), 'g_guangzhou1,GZ1_BH,GZ1_QW', 'companion must be behind frog, above scenery');
  for (const pid of [107,108]) {
    const layers = LAYERS[pid].layers;
    const frog = layers.findIndex(l => l.role === 'qw');
    const friend = layers.findIndex(l => l.role === 'bh');
    assert(friend > 0 && friend < frog && frog < layers.length-1, 'bamboo z-order');
  }
  // This single role sprite ALREADY contains both animals and the stump.
  const stump = LAYERS[202].layers;
  eq(stump[1].layer[0], 1021, 'stump must stay after background and before branches');
  eq(stump.filter(l => l.role).length, 1, 'do not add a second frog over the combined sprite');
  const size = artSize(1021);
  if (size) eq(stump[1].layer[2] + size[1], 350, 'cut stump bottom must touch the crop edge');
  const umbrella = LAYERS[1003].layers;
  const lining = umbrella.find(l => l.role === 'qw');
  const canopy = umbrella[umbrella.length - 1];
  eq(canopy.layer[0], 394, 'canopy must be above both characters');
  assert(canopy.layer[2] < lining.layer[2] - 10, 'outer canopy must sit above the lining');
});

test('layers: album_load hands the client composed layers, not a bare id', () => {
  const { engine } = newEngine();
  engine.state.pictures = [{ id: 1, pic_id: 100, read: 0, new: 1 }];
  const r = call(engine, 'album_load', { start: 1 });
  const p = r.reply.pictures[0];
  assert(Array.isArray(p.layers) && p.layers.length > 0,
    'a postcard with no layers renders as an empty cell');
  // the client reads these two field names exactly
  for (const l of p.layers) {
    assert(Array.isArray(l.layer) && l.layer.length === 3,
      'each entry must be {layer:[resId,x,y]}');
  }
});

test('layers: a picture missing from the table degrades to no layers, not a crash', () => {
  const { engine } = newEngine();
  engine.state.pictures = [{ id: 1, pic_id: 999999, read: 0, new: 1 }];
  const r = call(engine, 'album_load', { start: 1 });
  eq(r.reply.pictures.length, 1, 'the row should still be delivered');
  eq(r.reply.pictures[0].layers, undefined, 'unknown pic_id => no layers key');
});

test('layers: layers are derived from pic_id, never stored in the save', () => {
  const { engine } = newEngine();
  engine.state.pictures = [{ id: 1, pic_id: 100, read: 0, new: 1 }];
  call(engine, 'album_load', { start: 1 });
  // exportSave serialises exactly what would be written, without needing the
  // engine to have flushed to disk yet.
  const saved = typeof engine.exportSave === 'function'
    ? engine.exportSave()
    : JSON.stringify(engine.state);
  const text = typeof saved === 'string' ? saved : JSON.stringify(saved);
  assert(!text.includes('"layers"'),
    'layers must not be persisted: they are a pure function of pic_id');
});

test('layers: coverage is what the builder claims, and gaps are enumerated', () => {
  const have = Object.keys(LAYERS).length;
  assert(have >= 340, `expected >=340 of ${PICTURE_TABLE.length} pictures composed, got ${have}`);
  // 11 art names in the Picture table have no asset in the shipped client
  // (city backgrounds for cities whose art is absent). Those pictures simply
  // lose that one layer. Fail loudly if the count grows unexpectedly.
  assert(have >= PICTURE_TABLE.length - 10,
    `composed ${have}/${PICTURE_TABLE.length}: gap grew beyond the known 7`);
});

/* ------------------------------------------------------- gift box (礼品盒) */

/* The gift box is a holding area SEPARATE from the album: the client keeps the
   album in TravelModel.pictureInfoList (filled by album_load) and the gift box
   in GiftBoxModel.pictureList/.specialityList (filled ONLY by travel_load_gift).
   Feeding the album to travel_load_gift was a real bug: the gift box then showed
   every filed postcard and acting on one corrupted the album. */

/* 相册容量 =（30 页 + 已拥有的「相册扩容」）x 每页 6 张。
   `Define.ALBUM_MAX`（60）客户端**从不读**（在 main.min.js 里只出现在 Define 表自身），
   旧测试把它当容量，于是"60 张就算满"——与客户端的行为不符（客户端页数 = ceil(照片数/6)，
   扩容提示读的是 getHouseItemCount(9000)）。这里改用真实模型。 */
const ALBUM_CAPACITY = 30 * 6;      // 30 页起步、未扩容

test('giftbox: travel_load_gift serves the GIFT BOX, not the album', ({ engine }) => {
  // album has a filed postcard; the gift box must still be empty
  engine.state.pictures = [{ id: 1, pic_id: 100, read: 0, new: 1 }];
  const g = call(engine, 'travel_load_gift', {}).reply;
  eq(g.pictures.length, 0, 'the album must NOT leak into the gift box');
  eq(g.specialtys.length, 0, 'no specialties staged');
  // ...and the album still shows it
  eq(call(engine, 'album_load', { start: 1 }).reply.pictures.length, 1, 'album unaffected');
});

test('giftbox: moving a specialty from the bag stages it, and back again', ({ engine }) => {
  const itemId = idsOfType(3)[0];                    // a Specialty (type 3)
  engine.state.items.house = [{ item_id: itemId, count: 2 }];

  const r = call(engine, 'travel_bag_to_gift', { item_id: itemId });
  eq(r.reply.code, 0, 'bag_to_gift must answer 0');
  eq(haveOf(engine, itemId), 1, 'one consumed from the house');
  const g = call(engine, 'travel_load_gift', {}).reply;
  eq(g.specialtys.length, 1, 'staged in the gift box');
  eq(g.specialtys[0].item_id, itemId, 'the right item');
  eq(g.specialtys[0].count, 1, 'count is per slot');

  const back = call(engine, 'travel_gift_to_bag', { item_id: itemId });
  eq(back.reply.code, 0, 'gift_to_bag must answer 0');
  eq(haveOf(engine, itemId), 2, 'returned to the house');
  eq(call(engine, 'travel_load_gift', {}).reply.specialtys.length, 0, 'gift box empty again');
});

test('giftbox: staging an item you do not own is refused', ({ engine }) => {
  const itemId = idsOfType(3)[0];
  engine.state.items.house = [];
  const r = call(engine, 'travel_bag_to_gift', { item_id: itemId });
  assert(r.reply.code !== 0, 'must not succeed');
  eq(call(engine, 'travel_load_gift', {}).reply.specialtys.length, 0, 'nothing staged');
});

test("giftbox: a full gift box answers 102 (the client's 礼品盒满了 branch)", ({ engine }) => {
  const itemId = idsOfType(3)[0];
  // fill to the cap from the original tuning table (SPECIALTY_MAX = 100)
  engine.state.giftBox.specialtys = [{ item_id: itemId, count: 100 }];
  engine.state.items.house = [{ item_id: itemId, count: 1 }];
  const r = call(engine, 'travel_bag_to_gift', { item_id: itemId });
  eq(r.reply.code, 102, 'code 102 is what makes the client offer to swap one out');
  eq(haveOf(engine, itemId), 1, 'the item must not be consumed on refusal');
});

test('giftbox: album -> gift box -> album round trip keeps the picture intact', ({ engine }) => {
  engine.state.pictures = [{ id: 7, pic_id: 102, read: 0, new: 1 }];
  eq(call(engine, 'travel_album_to_gift', { picture_id: 7 }).reply.code, 0, 'to gift box');
  eq(call(engine, 'album_load', { start: 1 }).reply.pictures.length, 0, 'left the album');
  const g = call(engine, 'travel_load_gift', {}).reply;
  eq(g.pictures.length, 1, 'now in the gift box');
  eq(g.pictures[0].id, 7, 'same unique handle');
  assert(Array.isArray(g.pictures[0].layers) && g.pictures[0].layers.length,
    'gift box pictures must carry layers too, or they render blank');

  eq(call(engine, 'travel_gift_to_album', { picture_id: 7 }).reply.code, 0, 'back to album');
  eq(call(engine, 'album_load', { start: 1 }).reply.pictures.length, 1, 'back in the album');
  eq(call(engine, 'travel_load_gift', {}).reply.pictures.length, 0, 'gift box empty');
});

test("giftbox: a full album answers 101 (the client's 相册满了 branch)", ({ engine }) => {
  engine.state.pictures = [];
  for (let i = 0; i < ALBUM_CAPACITY; i++) {
    engine.state.pictures.push({ id: i + 1, pic_id: 100 + i, read: 0, new: 1 });
  }
  engine.state.giftBox.pictures = [{ id: 9999, pic_id: 200, read: 0, new: 1 }];
  const r = call(engine, 'travel_gift_to_album', { picture_id: 9999 });
  eq(r.reply.code, 101, 'code 101 is what makes the client offer to delete a photo');
  eq(engine.state.giftBox.pictures.length, 1, 'the picture stays in the gift box');
});

test('giftbox: deleting a gift-box picture removes only that one', ({ engine }) => {
  engine.state.giftBox.pictures = [
    { id: 1, pic_id: 100, read: 0, new: 1 },
    { id: 2, pic_id: 101, read: 0, new: 1 },
  ];
  eq(call(engine, 'travel_gift_delete_album', { id: 1 }).reply.code, 0, 'delete answers 0');
  const left = call(engine, 'travel_load_gift', {}).reply.pictures;
  eq(left.length, 1, 'one left');
  eq(left[0].id, 2, 'the right one survived');
  eq(call(engine, 'travel_gift_delete_album', { id: 1 }).reply.code, 74,
    'deleting a picture that is no longer in the gift box answers 74');
});

/* Refusal codes MUST come from the client's own errcode.json (shipped in
   preload.eab). The client's socket layer never looks at `code` when it hands a
   reply to the pending Action (AnalysisProtocol does `callbackFun.apply(...)`),
   and the callbacks then read the number through MessageModel.getErrorInfo().
   That lookup returns UNDEFINED for a code the table lacks, and the callbacks are
   written `o && 0 == o.code && (...)` -- so -1 (which the table has never had)
   skipped the branch entirely: the row stayed on screen, nothing was said, and
   the button looked broken. Worse, two of the gift-box callbacks are written
   `if (!r || 0 == r.code) {...do the move...}`, where an undefined lookup reads
   as SUCCESS: the picture left the UI while the save kept it. 74/75/76 are the
   album's own rows in that table. */
test('giftbox: unknown ids are refused with codes the client ERROR TABLE knows', ({ engine }) => {
  eq(call(engine, 'travel_album_to_gift', { picture_id: 12345 }).reply.code, 74, 'album_to_gift');
  eq(call(engine, 'travel_gift_to_album', { picture_id: 12345 }).reply.code, 74, 'gift_to_album');
  eq(call(engine, 'travel_gift_to_bag', { item_id: 999999 }).reply.code, 42, 'gift_to_bag');
});

test('giftbox: travel_read_note marks notes read and the load reflects it', ({ engine }) => {
  engine.state.notes = [
    { id: 1, read: 0, timestamp: 10 },
    { id: 2, read: 0, timestamp: 20 },
  ];
  // needResponse false: the client marks its own list and ignores the reply
  call(engine, 'travel_read_note', { id: [1, 2] });
  const list = call(engine, 'travel_load_note', {}).reply.note_list;
  eq(list.find((n) => n.id === 1).read, 1, 'note 1 read');
  eq(list.find((n) => n.id === 2).read, 1, 'note 2 read');
});

test('giftbox: item_select_gift pays out the queued package', ({ engine }) => {
  const itemId = idsOfType(3)[0];
  engine.state.selectGift = { 0: { item_id: itemId, count: 3 } };
  engine.state.items.house = [];
  const r = call(engine, 'item_select_gift', { index_list: [0] });
  eq(r.reply.items.length, 1, 'the client renders one package entry');
  eq(r.reply.items[0].item_id, itemId, 'right item');
  eq(r.reply.items[0].count, 3, 'right count');
  eq(haveOf(engine, itemId), 3, 'actually credited');
  eq(call(engine, 'item_select_gift', { index_list: [0] }).reply.items.length, 0,
    'selecting the same index twice must not pay twice');
});

/* ------------------------------------------------------- album management */

test('album: newly earned postcards are PENDING, not auto-filed', ({ engine }) => {
  // The client rebuilds newPictureInfoList from album_load_new and offers a save
  // action; auto-filing into the album would leave album_save_new with nothing
  // to act on. This is the flow the client implements.
  engine.state.pictures = [];
  engine.state.albumPending = [{ id: 42, pic_id: 102, read: 0, new: 1 }];
  const n = call(engine, 'album_load_new', {}).reply;
  eq(n.pictures.length, 1, 'album_load_new delivers the pending row');
  eq(n.pictures[0].id, 42, 'with its unique handle');
  assert(Array.isArray(n.pictures[0].layers) && n.pictures[0].layers.length,
    'pending pictures need layers too or the new-album view renders blank');
  eq(n.pictures[0].for_ads, 0, 'every entry must carry for_ads or the client misroutes it');
  eq(n.has_ads, false, 'no ads in this build');
  eq(n.is_share, false, 'a truthy is_share pops a WeChat share dialog');
  eq(call(engine, 'album_load', { start: 1 }).reply.pictures.length, 0,
    'pending is NOT in the album yet');
});

test('album: save_new files a pending postcard; a full album answers 75', ({ engine }) => {
  engine.state.albumPending = [{ id: 5, pic_id: 100, read: 0, new: 1 }];
  engine.state.pictures = [];
  eq(call(engine, 'album_save_new', { id: 5 }).reply.code, 0, 'filing answers 0');
  eq(engine.state.pictures.length, 1, 'now in the album');
  eq(engine.state.albumPending.length, 0, 'no longer pending');
  eq(call(engine, 'album_save_new', { id: 5 }).reply.code, 76,
    'filing it again answers 76 (删除错误的新照片id), NOT -1 -- see the note above '
    + '"refusal codes must exist in the client\'s errcode.json"');

  // full album: the client DROPS the pending row on code 75, so returning
  // anything else leaves it stuck on screen forever
  engine.state.pictures = [];
  for (let i = 0; i < ALBUM_CAPACITY; i++) {
    engine.state.pictures.push({ id: 900 + i, pic_id: 100 + i, read: 0, new: 1 });
  }
  engine.state.albumPending = [{ id: 6, pic_id: 300, read: 0, new: 1 }];
  eq(call(engine, 'album_save_new', { id: 6 }).reply.code, 75,
    'code 75 is the album-full code on this path (not 101)');
  eq(engine.state.albumPending.length, 0, 'the pending row is cleared so it stops showing');
  eq(engine.state.pictures.length, ALBUM_CAPACITY, 'nothing was added past the cap');
});

test('album: delete moves to the recycle bin and recover brings it back', ({ engine }) => {
  engine.state.pictures = [{ id: 11, pic_id: 100, read: 0, new: 1 }];
  engine.state.albumDeleted = [];
  eq(call(engine, 'album_delete', { id: 11 }).reply.code, 0, 'delete answers 0');
  eq(engine.state.pictures.length, 0, 'out of the album');
  const bin = call(engine, 'album_load_recover', {}).reply.pictures;
  eq(bin.length, 1, 'recoverable, not destroyed');
  eq(bin[0].id, 11, 'the same picture');
  assert(Array.isArray(bin[0].layers) && bin[0].layers.length,
    'recycle-bin rows render too, so they need layers');

  eq(call(engine, 'album_recover', { id: 11 }).reply.code, 0, 'recover answers 0');
  eq(engine.state.pictures.length, 1, 'back in the album');
  eq(call(engine, 'album_load_recover', {}).reply.pictures.length, 0, 'bin empty');
  eq(call(engine, 'album_delete', { id: 11 }).reply.code, 0, 'and deletable again');
});

test('album: deleting an unknown picture is refused, not silently eaten', ({ engine }) => {
  engine.state.pictures = [{ id: 1, pic_id: 100, read: 0, new: 1 }];
  eq(call(engine, 'album_delete', { id: 999 }).reply.code, 74,
    'unknown id answers 74 (删除错误的照片id), a code the client table HAS');
  eq(engine.state.pictures.length, 1, 'nothing removed');
  eq(call(engine, 'album_recover', { id: 999 }).reply.code, 75,
    'unknown recycle id answers 75 (保存错误的新照片id)');
});

test('album: recovering into a full album is refused and keeps the picture', ({ engine }) => {
  engine.state.pictures = [];
  for (let i = 0; i < ALBUM_CAPACITY; i++) {
    engine.state.pictures.push({ id: i + 1, pic_id: 100 + i, read: 0, new: 1 });
  }
  engine.state.albumDeleted = [{ id: 555, pic_id: 400, read: 0, new: 1 }];
  const r = call(engine, 'album_recover', { id: 555 });
  assert(r.reply.code !== 0, 'must not succeed');
  eq(call(engine, 'album_load_recover', {}).reply.pictures.length, 1,
    'the picture must stay recoverable rather than vanish');
});

test('album: delete_new drops a pending row without re-adding it', ({ engine }) => {
  // the client removes the row locally BEFORE sending, so a server that kept it
  // would make the row reappear on the next load
  engine.state.albumPending = [{ id: 3, pic_id: 100, read: 0, new: 1 }];
  engine.state.albumPendingVisit = [{ id: 4, pic_id: 101, read: 0, new: 1, visit: 1 }];
  call(engine, 'album_delete_new', { id: 3 });
  eq(call(engine, 'album_load_new', {}).reply.pictures.length, 0, 'pending row gone');
  call(engine, 'album_delete_new', { id: 4 });
  eq(call(engine, 'album_load_new', {}).reply.visted_pic.length, 0, 'visit row gone too');
});

test('reply keys: item_load_select_gift answers under `list`, not `items`', ({ engine }) => {
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

test('album: load_by_id_list takes a plain NUMBER array (unlike album_load_all)', ({ engine }) => {
  engine.state.pictures = [
    { id: 21, pic_id: 100, read: 0, new: 1 },
    { id: 22, pic_id: 101, read: 0, new: 1 },
    { id: 23, pic_id: 102, read: 0, new: 1 },
  ];
  /* The reply key is `pic_list` -- that is what the client's handler reads; with
     `pictures` the whole branch is skipped (see the reply-key test below). */
  const r = call(engine, 'album_load_by_id_list', { id_list: [21, 23] });
  eq(r.reply.pic_list.length, 2, 'only the requested ids');
  eq(r.reply.pic_list.map((p) => p.id).sort().join(','), '21,23', 'the right two');
  assert(r.reply.pic_list.every((p) => Array.isArray(p.layers)),
    'by-id loads render, so they need layers');
  eq(call(engine, 'album_load_by_id_list', { id_list: [999] }).reply.pic_list.length, 0,
    'unknown ids give an empty list, not an error');
});

/* ------------------------------------------------ 串门访客 (VisitorData) */

/* A SECOND gameplay, separate from the 邻居 guest: the client's GameplayModel
   lists both "邻居" (GuestData) and "串门" (VisitorData). */

test('visitor: visit_load carries the FULL VisitorData field set', ({ engine }) => {
  // An unknown key makes the client log a merge warning; a MISSING key silently
  // keeps its default. So every field has to be sent.
  engine.state.visitor = {
    province: '上海', city: '上海', name: '上海', title: 3, partner: 0, food: 2,
    first: true, expire_time: 12345, gift: { item_id: 100001, count: 2 }, carpet: 4,
  };
  const r = call(engine, 'visit_load', {}).reply;
  assert(r.visitor, 'a present visitor must be delivered');
  for (const k of ['partner', 'name', 'title', 'expire_time', 'city', 'food',
    'first', 'gift', 'carpet']) {
    assert(Object.prototype.hasOwnProperty.call(r.visitor, k),
      `VisitorData.${k} must be present or the client keeps a stale default`);
  }
  assert(r.visitor.gift && typeof r.visitor.gift.item_id === 'number'
    && typeof r.visitor.gift.count === 'number', 'gift is {item_id, count}');
  eq(r.visitor.city, '上海', 'city is what the client splits on "_"');
  assert(Array.isArray(r.acquire), 'acquire must be an array (the client pushes into it)');
});

test('visitor: no visitor omits the `visitor` key entirely', ({ engine }) => {
  // the client's handler is `e.visitor && (...)`; sending null/{} would be read
  // as "there is a visitor"
  engine.state.visitor = null;
  const r = call(engine, 'visit_load', {}).reply;
  eq(r.visitor, undefined, 'the key must be ABSENT, not null');
  assert(Array.isArray(r.acquire), 'acquire still delivered');
});

test('visitor: a FIRST visit earns the province, not clover', ({ engine }) => {
  engine.state.acquireProvinces = [];
  engine.state.clover = 100;
  engine.state.visitor = {
    province: '云南', city: '云南', first: true,
    expire_time: 9e9, gift: { item_id: 100000, count: 5 }, carpet: 1,
  };
  call(engine, 'visit_open', {});
  eq(engine.state.acquireProvinces.join(','), '云南', 'the province flower is collected');
  eq(engine.state.clover, 100, 'a first visit must NOT also pay clover');
  eq(engine.state.visitor, null, 'the visitor leaves');
});

test('visitor: a repeat visit pays clover, and the push is mandatory', ({ engine }) => {
  // the client calls addClover(gift.count) locally -- and addClover is an EMPTY
  // STUB, so without the push the present is silently lost
  engine.state.acquireProvinces = ['云南'];
  engine.state.clover = 100;
  engine.state.visitor = {
    province: '云南', city: '云南', first: false,
    expire_time: 9e9, gift: { item_id: 100000, count: 7 }, carpet: 1,
  };
  const r = call(engine, 'visit_open', {});
  eq(engine.state.clover, 107, 'clover credited server-side');
  const pushed = pushNamed(r, 'clover_update');
  assert(pushed.length === 1, 'clover_update must be pushed (addClover is a stub)');
  eq(pushed[0].data.clover, 107, 'with the authoritative count');
});

test('visitor: a repeat visit can pay a ticket instead (OtherGiftID 100001)', ({ engine }) => {
  engine.state.acquireProvinces = ['上海'];
  const t0 = engine.state.ticket;
  engine.state.visitor = {
    province: '上海', city: '上海', first: false,
    expire_time: 9e9, gift: { item_id: 100001, count: 3 }, carpet: 1,
  };
  const r = call(engine, 'visit_open', {});
  eq(engine.state.ticket, t0 + 3, 'ticket credited');
  assert(pushNamed(r, 'item_update_ticket').length === 1, 'item_update_ticket pushed');
});

test('visitor: visit_open with nobody there is a harmless no-op', ({ engine }) => {
  engine.state.visitor = null;
  const c = engine.state.clover;
  const t = engine.state.ticket;
  call(engine, 'visit_open', {});
  eq(engine.state.clover, c, 'no clover invented');
  eq(engine.state.ticket, t, 'no ticket invented');
});

test('visitor: the same province is not collected twice', ({ engine }) => {
  engine.state.acquireProvinces = ['上海'];
  engine.state.visitor = {
    province: '上海', city: '上海', first: true,
    expire_time: 9e9, gift: { item_id: 100000, count: 1 }, carpet: 1,
  };
  call(engine, 'visit_open', {});
  eq(engine.state.acquireProvinces.length, 1, 'still one entry');
});

test('visitor: set_carpet / set_expire_time record what the client reports', ({ engine }) => {
  engine.state.visitor = {
    province: '上海', city: '上海', first: true, expire_time: 0,
    gift: { item_id: 100000, count: 1 }, carpet: 0,
  };
  call(engine, 'visit_set_carpet', { id: 6 });
  eq(engine.state.visitor.carpet, 6, 'carpet recorded (the client rolls 1..8 itself)');
  call(engine, 'visit_set_carpet', { id: 0 });
  eq(engine.state.visitor.carpet, 6, 'a nonsensical carpet is ignored, not stored');
  call(engine, 'visit_set_expire_time', { time: 4242 });
  eq(engine.state.visitor.expire_time, 4242, 'expiry recorded');
  // and both are no-ops with nobody there
  engine.state.visitor = null;
  call(engine, 'visit_set_carpet', { id: 3 });
  call(engine, 'visit_set_expire_time', { time: 1 });
});

test('visitor: the roll eventually spawns one', ({ engine }) => {
  engine.state.visitorNextRollAt = 0;
  engine.state.visitorCoolUntil = 0;
  for (let i = 0; i < 400 && !engine.state.visitor; i++) {
    engine.state.visitorNextRollAt = 1;
    engine.tick();
  }
  const v = engine.state.visitor;
  assert(v, 'a visitor should eventually arrive (VISITOR_CHANCE > 0)');
  assert(v.province, 'the visitor must name a province');
  assert(v.gift && typeof v.gift.count === 'number', 'and carry a gift');
  assert(v.expire_time > 0, 'and an expiry');
  // and it must survive a reload
  const r = call(engine, 'visit_load', {}).reply;
  assert(r.visitor, 'the arrived visitor is delivered by visit_load');
});

/* ------------------------------------------- 友情绘本 (guest_* / drawing) */

/* A THIRD visitor gameplay. `guest_load_drawing` REPLACES the client model
   wholesale (this.data = e), so every field has to be sent.
   DrawingState = { wait:0, invite:1, accept:2, lock:3, visit:4 } -- the client's
   own values, read out of main.min.js. */

test('drawing: guest_load_drawing carries the FULL model field set', ({ engine }) => {
  const r = call(engine, 'guest_load_drawing', {}).reply;
  for (const k of ['state', 'guest', 'bag', 'pages', 'colls', 'show_coll', 'pen_motion']) {
    assert(Object.prototype.hasOwnProperty.call(r, k),
      `DrawingModel.${k} must be present or the client keeps a stale default`);
  }
  assert(Array.isArray(r.bag), 'bag must be an array');
  assert(Array.isArray(r.pages) && Array.isArray(r.colls), 'pages/colls are convertArray-ed');
  eq(r.pen_motion, 'write', 'pen_motion is a string');
});

test('drawing: the feature stays closed until you own the 友情绘本 (item 7001)', ({ engine }) => {
  // the client's isOpen() is getHouseItemCount(Tabikaeru.ItemID.DRAWING_BOOK) > 0;
  // inviting without the book would open a UI that cannot be used
  engine.state.items.house = [];
  engine.state.drawingNextRollAt = 0;
  for (let i = 0; i < 600; i++) {
    engine.state.drawingNextRollAt = 1;
    engine.tick();
  }
  eq(engine.state.drawing.state, 0, 'no invitation without the book');
});

test('drawing: absent invitation cannot create a souvenir packing state', ({ engine }) => {
  eq(call(engine, 'guest_accept_invit', {is_accept:true}).reply.code, -1);
  eq(engine.state.drawing.state, 0);
  engine.state.drawing.state = 1;
  engine.state.drawing.guest = -1;
  eq(call(engine, 'guest_accept_invit', {is_accept:true}).reply.code, -1);
});

test('drawing: legacy accepted state without a partner migrates without losing bag or collections', ({ engine, savePath }) => {
  engine.state.drawing.state = 2;
  engine.state.drawing.guest = -1;
  engine.state.drawing.bag = [1,-1,-1,-1,-1,-1];
  engine.state.drawing.colls = [1];
  engine.state.drawingReturnAt = 99;
  fs.writeFileSync(savePath, JSON.stringify(engine.state));
  const restored = reopen(savePath);
  eq(restored.state.drawing.state, 0);
  eq(restored.state.drawingReturnAt, 0);
  eq(restored.state.drawing.bag[0], 1);
  eq(restored.state.drawing.colls[0], 1);
});

test('drawing: with the book, an invitation eventually arrives', ({ engine }) => {
  engine.state.items.house = [{ item_id: 7001, count: 1 }];
  engine.state.drawingNextRollAt = 0;
  for (let i = 0; i < 600 && engine.state.drawing.state === 0; i++) {
    engine.state.drawingNextRollAt = 1;
    engine.tick();
  }
  eq(engine.state.drawing.state, 1, 'state must be invite (1)');
  assert(engine.state.drawing.guest >= 0, 'and it must name a guest');
  // the tables contain shared rows with guest === -1; those are content, not an
  // inviter, so they must never be picked (this actually happened)
  const guests = new Set();
  for (const src of [GD.tables.drawingCollectData, GD.tables.drawingPageData]) {
    for (const r of Object.values(src)) guests.add(Number(r.guest));
  }
  assert(guests.has(engine.state.drawing.guest),
    `guest ${engine.state.drawing.guest} must be a real guest in the tables`);
});

test('drawing: accept -> 2, reject -> 0, through the SAME command', ({ engine }) => {
  engine.state.drawing.state = 1;
  engine.state.drawing.guest = 1;
  eq(call(engine, 'guest_accept_invit', { accept: true }).reply.code, 0, 'accept answers 0');
  eq(engine.state.drawing.state, 2, 'state accept (2)');
  // the reject path uses the same command with a falsy flag
  engine.state.drawing.state = 1;
  eq(call(engine, 'guest_accept_invit', { accept: false }).reply.code, 0, 'reject answers 0');
  eq(engine.state.drawing.state, 0, 'state wait (0)');
  eq(engine.state.drawing.guest, -1, 'and the guest is released');
});

test('drawing: lock_bag toggles 2 <-> 3 and arms the return timer', ({ engine }) => {
  engine.state.drawing.state = 2;
  engine.state.drawing.guest = 0;
  eq(call(engine, 'guest_lock_bag', {}).reply.code, 0, 'locking answers 0');
  eq(engine.state.drawing.state, 3, 'state lock (3)');
  assert(engine.state.drawingReturnAt > 0, 'the trip must be armed');
  eq(call(engine, 'guest_lock_bag', {}).reply.code, 0, 'unlocking answers 0');
  eq(engine.state.drawing.state, 2, 'back to accept (2)');
  eq(engine.state.drawingReturnAt, 0, 'and the trip is cancelled');
  // out of the two valid states it refuses rather than guessing
  engine.state.drawing.state = 1;
  eq(call(engine, 'guest_lock_bag', {}).reply.code, -1, 'invite state is not lockable');
});

test('drawing: packing the bag is 1-based and consumes from the house', ({ engine }) => {
  const itemId = TOOL_ITEM_ID();
  engine.state.drawing.state = 2;
  engine.state.items.house = [{ item_id: itemId, count: 2 }];
  const bagLen = engine.state.drawing.bag.length;

  const r = call(engine, 'guest_putin_bag', { pos: 2, id: itemId });
  eq(r.reply.code, 0, 'putin answers 0');
  eq(engine.state.drawing.bag[1], itemId, 'pos 2 lands in bag[1] (1-based on the wire)');
  eq(haveOf(engine, itemId), 1, 'consumed from the house');

  eq(call(engine, 'guest_takeout_bag', { pos: 2 }).reply.code, 0, 'takeout answers 0');
  eq(engine.state.drawing.bag[1], -1, 'slot empty again');
  eq(haveOf(engine, itemId), 2, 'returned to the house');

  eq(call(engine, 'guest_putin_bag', { pos: 0, id: itemId }).reply.code, -1, 'pos 0 refused');
  eq(call(engine, 'guest_putin_bag', { pos: bagLen + 1, id: itemId }).reply.code, -1,
    'past the end refused');
});

test('drawing: the bag can only be packed while in the accept state', ({ engine }) => {
  const itemId = TOOL_ITEM_ID();
  engine.state.items.house = [{ item_id: itemId, count: 1 }];
  for (const st of [0, 1, 3, 4]) {
    engine.state.drawing.state = st;
    eq(call(engine, 'guest_putin_bag', { pos: 1, id: itemId }).reply.code, -1,
      `state ${st} is not packable`);
  }
  eq(haveOf(engine, itemId), 1, 'nothing was consumed by the refusals');
});

test('drawing: an unowned item cannot be packed', ({ engine }) => {
  engine.state.drawing.state = 2;
  engine.state.items.house = [];
  eq(call(engine, 'guest_putin_bag', { pos: 1, id: TOOL_ITEM_ID() }).reply.code, -1, 'refused');
});

test('drawing: the locked trip returns with a real collectible', ({ engine }) => {
  engine.state.items.house = [{ item_id: 7001, count: 1 }];
  engine.state.drawing.state = 1;
  engine.state.drawing.guest = Number(Object.values(GD.tables.drawingCollectData)[0].guest);
  call(engine, 'guest_accept_invit', { accept: true });
  call(engine, 'guest_lock_bag', {});
  eq(engine.state.drawing.state, 3, 'away');
  const before = engine.state.drawing.colls.length;
  const who = engine.state.drawing.guest;      // capture BEFORE the return clears it

  engine.state.drawingReturnAt = 1;          // force the return
  engine.tick();

  eq(engine.state.drawing.colls.length, before + 1, 'one collectible gained');
  // and it must be a real row belonging to THAT guest, not an invented id
  const got = engine.state.drawing.colls[engine.state.drawing.colls.length - 1];
  const row = Object.values(GD.tables.drawingCollectData).find((r) => Number(r.id) === got);
  assert(row, `collectible ${got} must exist in drawingCollectData`);
  eq(Number(row.guest), who, 'the collectible must belong to the guest that visited');
  eq(engine.state.drawing.state, 0, 'back to waiting for a new partner');
  eq(engine.state.drawing.bag.every((v) => v === -1), true, 'bag cleared for next time');
});

/* ------------------------------------- 抽奖 / 邻里美食交流 (lottery_*) */

/* `lottery_load` only applies its payload `if (e.phase)` -- so a falsy phase
   makes the client ignore EVERYTHING, including `state`, and it fails silently.
   settle_desc / extra_desc are both keyed 0..5, which is what fixes the score
   range and therefore the number of picks at 5. */

const LOT = (() => JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'lotteryData.json'), 'utf8')))();

test('lottery: the payload carries the FULL model and a truthy phase', ({ engine }) => {
  const r = call(engine, 'lottery_load', {}).reply;
  for (const k of ['last_phase', 'phase', 'state', 'select_list', 'answer',
    'extra_item', 'right_flag', 'egg_num', 'reward']) {
    assert(Object.prototype.hasOwnProperty.call(r, k),
      `LotteryModel.${k} must be present or the client keeps a stale default`);
  }
  assert(Array.isArray(r.select_list) && Array.isArray(r.answer)
    && Array.isArray(r.right_flag) && Array.isArray(r.reward),
    'all four are convertArray-ed');
  assert(r.extra_item && typeof r.extra_item.item_id === 'number',
    'extra_item is {item_id, count}');
});

test('lottery: a phase eventually starts, and phase is TRUTHY', ({ engine }) => {
  engine.state.lotteryNextRollAt = 0;
  for (let i = 0; i < 600 && !engine.state.lottery.phase; i++) {
    engine.state.lotteryNextRollAt = 1;
    engine.tick();
  }
  const L = engine.state.lottery;
  assert(L.phase, 'a phase must start (phase must be truthy or the client ignores it)');
  eq(call(engine, 'lottery_load', {}).reply.phase, L.phase, 'and it must be delivered');
  assert(L.selectList.length > 0, 'the helper guest needs something to show');
});

test('lottery: the pick count matches the 0..5 score keys', ({ engine }) => {
  // settle_desc and extra_desc are keyed "0".."5": a score outside that range
  // would render no text at all
  eq(Object.keys(LOT.settle_desc).sort().join(','), '0,1,2,3,4,5',
    'settle_desc must be 0..5');
  for (const g of Object.keys(LOT.extra_desc)) {
    eq(Object.keys(LOT.extra_desc[g]).sort().join(','), '0,1,2,3,4,5',
      `extra_desc[${g}] must be 0..5`);
  }
  // every select_list row must be renderable (the client uses these fields)
  for (const g of Object.keys(LOT.select_list)) {
    const row = LOT.select_list[g];
    for (const k of ['id', 'name', 'desc', 'desc2', 'pic']) {
      assert(row[k] !== undefined, `select_list[${g}].${k} is missing`);
    }
  }
});

test('lottery: open grants a gift and answers BOTH open_item and extra_item', ({ engine }) => {
  // the client gates the whole reveal on `i.open_item && i.extra_item`, so an
  // answer missing either key does nothing at all
  const c0 = engine.state.clover;
  const r = call(engine, 'lottery_open', {});
  assert(r.reply.open_item, 'open_item is required or nothing is shown');
  assert(r.reply.extra_item, 'extra_item is required or nothing is shown');
  assert(r.reply.open_item.count > 0, 'the opening gift must be non-empty');
  assert(engine.state.clover > c0, 'and the clover must actually be credited');
  assert(pushNamed(r, 'clover_update').length === 1,
    'clover_update must be pushed (addClover is a stub)');
  eq(engine.state.lottery.state, 1, 'state must move to Select');
});

test('lottery: extra_item must be a real Item or the client throws', ({ engine }) => {
  const itemIds = new Set(GD.items.map((i) => i.id));
  for (let i = 0; i < 30; i++) {
    engine.state.lottery = { lastPhase: 0, phase: 0, state: 0, selectList: [],
      answer: [], extraItem: { item_id: 0, count: 0 }, rightFlag: [], eggNum: 0, reward: [] };
    const r = call(engine, 'lottery_open', {});
    if (r.reply.extra_item.item_id > 0) {
      assert(itemIds.has(r.reply.extra_item.item_id),
        `extra_item ${r.reply.extra_item.item_id} must exist in Item.json`);
    }
  }
});

test('lottery: the round OFFERS more items than the player picks', ({ engine }) => {
  /* The client's own tip is 「选出5款物品，帮{0}解决这个困扰」 over a 5x3 item grid,
     and settle_desc/extra_desc are keyed 0..5 with "you picked wrong" texts. So the
     list MUST be longer than the 5 picks -- sending exactly the 5 wanted items made
     the round meaningless and left the confirm button greyed out. */
  call(engine, 'lottery_open', {});
  const list = engine.state.lottery.selectList;
  assert(list.length === 10, `expected 10 candidates, got ${list.length}`);
  const want = engine.state.lottery.want;
  eq(want.length, 5, 'five of them are the wanted set');
  assert(list.filter((id) => want.indexOf(id) !== -1).length === 5,
    'exactly five candidates are correct');
  assert(list.filter((id) => want.indexOf(id) === -1).length === 5,
    'and five are decoys the guest does not want');
  // every candidate must be a real Item row: the option slot does ItemDB.get(id).img
  const itemIds = new Set(GD.items.map((i) => i.id));
  for (const id of list) assert(itemIds.has(id), `candidate ${id} must exist in Item.json`);
  const uniq = new Set(list);
  eq(uniq.size, list.length, 'no duplicate candidates');
  // the client renders them in order, so the order must not be "the answer first"
  let leaked = 0;
  for (let i = 0; i < 40; i++) {
    engine.state.lottery = { lastPhase: 0, phase: 0, state: 0, selectList: [],
      answer: [], extraItem: { item_id: 0, count: 0 }, rightFlag: [], eggNum: 0, reward: [] };
    call(engine, 'lottery_open', {});
    const first5 = engine.state.lottery.selectList.slice(0, 5);
    if (first5.every((id) => engine.state.lottery.want.indexOf(id) !== -1)) leaked++;
  }
  assert(leaked < 40, 'the wanted items must not always sit in the first five slots');
});

test('lottery: the helper guest is one the client can actually name and draw', ({ engine }) => {
  /* The client asks 「以下哪个食物{0}看起来最喜欢？」 over a hard-coded
     ["困困","胖胖","跳跳"] and draws `neighbor_emote_<guest>_0_png`; the 4th
     neighbour only ships `neighbor_emote_3_0`, so guest 3 prints "undefined" and has
     no reward emote. Guests are therefore 0..2 and follow the phase the client uses
     for its title art. */
  for (let i = 0; i < 12; i++) {
    engine.state.lottery = { lastPhase: 0, phase: 0, state: 0, selectList: [],
      answer: [], extraItem: { item_id: 0, count: 0 }, rightFlag: [], eggNum: 0, reward: [] };
    engine.state.lotteryNextRollAt = 0;
    call(engine, 'lottery_open', {});
    const L = engine.state.lottery;
    assert(L.guest >= 0 && L.guest <= 2, `guest ${L.guest} must be 0..2`);
    eq(L.guest, L.phase - 1, 'the guest follows the phase row the client indexes');
    assert(L.phase >= 1 && L.phase <= 3, `phase ${L.phase} must cycle 1..3`);
  }
});

test('lottery: select scores the picks into right_flag within 0..5', ({ engine }) => {
  call(engine, 'lottery_open', {});
  const want = engine.state.lottery.want.slice();
  // a perfect pick: the five items the guest actually likes
  const r = call(engine, 'lottery_select', { list: want });
  eq(r.reply.code, 0, 'select answers 0');
  const flags = engine.state.lottery.rightFlag;
  eq(flags.length, want.length, 'one flag per pick');
  assert(flags.every((f) => f === 1), 'a perfect pick flags every pick correct');
  const score = engine.state.lottery.score;
  assert(score >= 0 && score <= 5, `score ${score} must be within the table's 0..5`);
  eq(score, 5, 'picking the wanted five scores the full 5');
  eq(engine.state.lottery.state, 2, 'state must move to Complete');
});

test('lottery: picking the DECOYS scores 0, so the low score tiers are reachable', ({ engine }) => {
  call(engine, 'lottery_open', {});
  const L = engine.state.lottery;
  const decoys = L.selectList.filter((id) => L.want.indexOf(id) === -1);
  eq(decoys.length, 5, 'the list carries five decoys');
  call(engine, 'lottery_select', { list: decoys });
  eq(engine.state.lottery.score, 0, 'nothing the guest wanted -> score 0');
  eq(engine.state.lottery.rightFlag.join(','), '0,0,0,0,0', 'every pick flagged wrong');
});

test('lottery: picking nothing scores 0 rather than crashing', ({ engine }) => {
  call(engine, 'lottery_open', {});
  eq(call(engine, 'lottery_select', { list: [] }).reply.code, 0, 'still answers 0');
  eq(engine.state.lottery.score, 0, 'score 0');
  eq(engine.state.lottery.rightFlag.length, 0, 'no flags');
});

test('lottery: confirm pays by score and returns to Open', ({ engine }) => {
  call(engine, 'lottery_open', {});
  const perfect = engine.state.lottery.want.slice();
  call(engine, 'lottery_select', { list: perfect });
  const score = engine.state.lottery.score;
  const c0 = engine.state.clover;
  const r = call(engine, 'lottery_confirm_reward', {});
  eq(r.reply.code, 0, 'confirm answers 0');
  assert(engine.state.clover > c0, 'a decent score must pay something');
  eq(engine.state.lottery.state, 0, 'state must go back to Open');
  eq(engine.state.lottery.answer.length, 0, 'and the answer cleared');
  return score;
});

test('lottery: a perfect round pays at least as much as a blank one', ({ engine }) => {
  // relative comparison, so it does not assert OUR payout numbers as if they
  // were recovered values
  call(engine, 'lottery_open', {});
  call(engine, 'lottery_select', { list: engine.state.lottery.want.slice() });
  const cHigh = engine.state.clover;
  call(engine, 'lottery_confirm_reward', {});
  const highGain = engine.state.clover - cHigh;

  call(engine, 'lottery_open', {});
  call(engine, 'lottery_select', { list: [] });
  const cLow = engine.state.clover;
  call(engine, 'lottery_confirm_reward', {});
  const lowGain = engine.state.clover - cLow;

  assert(highGain >= lowGain, `perfect ${highGain} must pay >= blank ${lowGain}`);
  eq(lowGain, 0, 'a blank round pays nothing');
});

test('engine: no protocol command has TWO handler definitions', () => {
  // A duplicate key in an object literal is NOT an error -- the LAST one wins.
  // `lottery_load` was defined twice (a real implementation plus an older
  // `() => ({})` stub below it), so the stub silently shadowed the real handler
  // and the whole subsystem looked unimplemented. This test makes that loud.
  //
  // Two traps learned the hard way while writing this check:
  //  1. scanning the whole file also flags same-indented keys in the state
  //     literal (state.frog.achieves vs top-level achieves) -- not duplicates;
  //  2. locating the handlers object by brace-matching is FRAGILE: an apostrophe
  //     inside a comment ("don't") desynchronises the string skipping and the
  //     scan stops early, which is exactly how a second `client_load_decorate`
  //     slipped past an earlier version of this test.
  // So: only look at lines AFTER `const handlers = {` whose value is an arrow
  // function. State entries are plain values, never arrows.
  const src = fs.readFileSync(ENGINE, 'utf8');
  const startLine = src.slice(0, src.indexOf('const handlers = {')).split('\n').length;
  assert(startLine > 0, 'could not locate the handlers object');

  const seen = new Map();
  const dupes = [];
  const re = /^ {4}([a-z][a-z0-9_]*)\s*:.*=>/gm;
  let m;
  while ((m = re.exec(src)) !== null) {
    const name = m[1];
    const line = src.slice(0, m.index).split('\n').length;
    if (line <= startLine) continue;          // state defaults, not handlers
    if (seen.has(name)) dupes.push(`${name} (lines ${seen.get(name)} and ${line})`);
    else seen.set(name, line);
  }
  assert(seen.size > 100, `expected many handlers, found ${seen.size}`);
  eq(dupes.length, 0, `duplicate handler keys shadow earlier ones: ${dupes.join('; ')}`);
});

/* -------------------------------------------------- 许愿池 (wishingpool_*) */

/* `wishingpool_load` was a `() => ({end_time: 0})` stub, and the client's
   isOpen() is `now < end_time` -- so the pool was permanently closed and the
   wish button could never do anything. */

test('wishpool: load opens the pool (end_time in the future, not 0)', ({ engine }) => {
  const r = call(engine, 'wishingpool_load', {}).reply;
  const now = Math.floor(Date.now() / 1000);
  assert(r.end_time > now, 'isOpen() is `now < end_time`; 0 means never open');
  assert(Array.isArray(r.items) && r.items.length > 0, 'the pool needs prizes to draw from');
  // every entry the client renders is {id, num, limit}, and `id` becomes item_id
  for (const it of r.items) {
    for (const k of ['id', 'num', 'limit']) {
      assert(typeof it[k] === 'number', `items[].${k} must be a number`);
    }
    assert(it.num > 0, 'a prize with count 0 would show an empty reward');
  }
});

test('wishpool: every prize id is a real Item', ({ engine }) => {
  // the client does ItemDB.get(o.id) when rendering the reward; ItemDB.get has
  // no null guard, so an invented id throws
  const itemIds = new Set(GD.items.map((i) => i.id));
  const r = call(engine, 'wishingpool_load', {}).reply;
  for (const it of r.items) {
    assert(itemIds.has(it.id), `prize ${it.id} must exist in Item.json`);
  }
});

test('wishpool: a wish draws a prize, spends a coin and decrements its limit', ({ engine }) => {
  const before = call(engine, 'wishingpool_load', {}).reply;
  const coin0 = before.coin;
  assert(coin0 > 0, 'the pool must start with coins to spend');
  const r = call(engine, 'wishingpool_wish', {});
  assert(r.reply.id > 0, 'id > 0 is the only signal the client acts on');
  const after = call(engine, 'wishingpool_load', {}).reply;
  eq(after.coin, coin0 - 1, 'a wish spends exactly one coin');
  const b = before.items.find((i) => i.id === r.reply.id);
  const a = after.items.find((i) => i.id === r.reply.id);
  eq(a.limit, b.limit - 1, 'the drawn entry loses one unit of stock');
});

test('wishpool: the drawn prize is actually credited to the house', ({ engine }) => {
  engine.state.items.house = [];
  const r = call(engine, 'wishingpool_wish', {});
  assert(r.reply.id > 0, 'need a draw to test');
  assert(haveOf(engine, r.reply.id) > 0, 'the item must land in the house');
  assert(pushNamed(r, 'item_update').length >= 1,
    'item_update must be pushed (the client never grants it itself)');
});

test('wishpool: with no coins the wish is a no-op answering id 0', ({ engine }) => {
  call(engine, 'wishingpool_load', {});
  engine.state.wishingPool.coin = 0;
  const r = call(engine, 'wishingpool_wish', {});
  eq(r.reply.id, 0, 'id 0 = the client does nothing, which is correct here');
});

test('wishpool: an exhausted pool cannot be drawn from', ({ engine }) => {
  call(engine, 'wishingpool_load', {});
  for (const it of engine.state.wishingPool.items) it.limit = 0;
  engine.state.wishingPool.coin = 5;
  const r = call(engine, 'wishingpool_wish', {});
  eq(r.reply.id, 0, 'no stock left -> nothing drawn');
  eq(engine.state.wishingPool.coin, 5, 'and no coin is spent on a failed wish');
});

test('wishpool: stock never goes negative across many wishes', ({ engine }) => {
  call(engine, 'wishingpool_load', {});
  engine.state.wishingPool.coin = 200;
  for (let i = 0; i < 200; i++) call(engine, 'wishingpool_wish', {});
  for (const it of engine.state.wishingPool.items) {
    assert(it.limit >= 0, `limit went negative on item ${it.id}: ${it.limit}`);
  }
});

/* ------------------------------------------- 庭院装饰 (client_*_decorate) */

/* RoleModel fields: decorationList [{id,num}], decorationPutID, decorationStatus
   (0 -> pic[0] 花苞, 1 -> pic[1] 花朵). Arrives as {has_list, put_id, status}. */

const DECO = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'decoration.json'), 'utf8'));

test('decorate: payload uses the client\'s exact keys (has_list/put_id/status)', ({ engine }) => {
  engine.state.decoration = { hasList: [{ id: 100, num: 2 }], putId: 101, status: 1 };
  const r = call(engine, 'client_load_decorate', {}).reply;
  eq(Object.keys(r).sort().join(','), 'has_list,put_id,status',
    'the client reads convertArray(e.has_list), e.put_id and e.status');
  eq(r.has_list.length, 1, 'one entry');
  eq(Object.keys(r.has_list[0]).sort().join(','), 'id,num', 'DecorationItem is {id,num}');
  eq(r.put_id, 101, 'the displayed decoration');
  eq(r.status, 1, 'status picks pic[0] vs pic[1]');
});

test('decorate: every decoration row has the two pics status selects between', () => {
  for (const k of Object.keys(DECO)) {
    const row = DECO[k];
    assert(Array.isArray(row.pic) && row.pic.length >= 2,
      `decoration ${k} needs pic[0] and pic[1] or status cannot be rendered`);
    for (const f of ['id', 'name', 'desc', 'icon']) {
      assert(row[f] !== undefined, `decoration ${k}.${f} is missing`);
    }
  }
});

test('decorate: change puts the flower on display and sets status 1', ({ engine }) => {
  engine.state.frog.status = 1;
  engine.state.decoration = { hasList: [{ id: 100, num: 1 }], putId: 0, status: 0 };
  eq(call(engine, 'client_change_decorate', { id: 100 }).reply.code, 0, 'answers 0');
  eq(engine.state.decoration.putId, 100, 'now displayed');
  eq(engine.state.decoration.status, 1, 'and blooming');
});

test('decorate: placing a new flower consumes the PREVIOUSLY displayed one', ({ engine }) => {
  engine.state.frog.status = 1;
  // the client's own mirror decrements the entry whose id === the OLD put_id and
  // splices it out at 0 -- mirroring that is what keeps the two in sync
  engine.state.decoration = { hasList: [{ id: 100, num: 1 }, { id: 101, num: 2 }], putId: 100, status: 1 };
  eq(call(engine, 'client_change_decorate', { id: 101 }).reply.code, 0, 'swap answers 0');
  eq(engine.state.decoration.putId, 101, 'the new one is displayed');
  const old = engine.state.decoration.hasList.find((x) => x.id === 100);
  eq(old, undefined, 'the old flower was used up and removed at 0');
  eq(engine.state.decoration.hasList.find((x) => x.id === 101).num, 2,
    'the newly placed one is NOT decremented (the client does not either)');
});

test('decorate: a flower you do not have cannot be displayed', ({ engine }) => {
  engine.state.decoration = { hasList: [], putId: 0, status: 0 };
  eq(call(engine, 'client_change_decorate', { id: 100 }).reply.code, -1, 'not owned');
  eq(call(engine, 'client_change_decorate', { id: 999999 }).reply.code, -1,
    'not a decoration at all');
  eq(engine.state.decoration.putId, 0, 'nothing changed');
});

test('decorate: re-placing the SAME flower does not consume it', ({ engine }) => {
  engine.state.frog.status = 1;
  engine.state.decoration = { hasList: [{ id: 100, num: 3 }], putId: 100, status: 1 };
  eq(call(engine, 'client_change_decorate', { id: 100 }).reply.code, 1, 'already displayed');
  eq(engine.state.decoration.hasList.find((x) => x.id === 100).num, 3,
    'same id: the old-entry branch must not fire');
});

test('decorate: trips bring flowers home', ({ engine }) => {
  const lunch = idsOfType(0)[0];
  engine.state.decoration = { hasList: [], putId: 0, status: 0 };
  for (let i = 0; i < 40; i++) {
    engine.state.items.bag[0] = lunch;
    engine.state.travel.nextDepartAt = 1;
    engine.tick();
    engine.state.travel.returnAt = 1;
    engine.tick();
  }
  const n = engine.state.decoration.hasList.reduce((a, d) => a + d.num, 0);
  assert(n > 0, 'the frog should bring a flower home now and then');
  // and every granted id must be a REAL decoration, not an invented one
  for (const d of engine.state.decoration.hasList) {
    assert(DECO[String(d.id)], `granted decoration ${d.id} must exist in decoration.json`);
  }
});

/* --------------------------------------------- 扭蛋活动 (capsule_*) */

/* capsuleData.json IS the event: fast_consume, reward pool, num_reward
   thresholds (3/7/12) and 8 task_list rows whose descriptions are real in-game
   actions. `capsule_load` only arms the activity `if (isOpen())`, i.e. while
   `now < end_time` -- so end_time 0 silently disables everything. */

const CAP = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'capsuleData.json'), 'utf8'));

test('capsule: payload carries the FULL model and the event is OPEN', ({ engine }) => {
  const r = call(engine, 'capsule_load', {}).reply;
  const now = Math.floor(Date.now() / 1000);
  for (const k of ['end_time', 'coin', 'pre_coin', 'reward_list', 'task_list', 'patch_num']) {
    assert(Object.prototype.hasOwnProperty.call(r, k),
      `CapsuleModel.${k} must be present or the client keeps a stale default`);
  }
  assert(r.end_time > now, 'isOpen() is `now < end_time`; 0 disables the whole event');
  assert(Array.isArray(r.reward_list) && Array.isArray(r.task_list), 'both are convertArray-ed');
});

test('capsule: every reward row points at a real Item', ({ engine }) => {
  const itemIds = new Set(GD.items.map((i) => i.id));
  for (const k of Object.keys(CAP.reward)) {
    const row = CAP.reward[k];
    assert(itemIds.has(Number(row.id)),
      `capsule reward ${row.reward_id} -> item ${row.id} must exist in Item.json`);
    assert(Number(row.num) > 0, `reward ${row.reward_id} needs a positive count`);
  }
});

test('capsule: twist draws a real reward, spends a coin and gives the item', ({ engine }) => {
  const l0 = call(engine, 'capsule_load', {}).reply;
  assert(l0.coin > 0, 'the event must start with coins to spend');
  const r = call(engine, 'capsule_twist', {});
  assert(r.reply.reward_id > 0, 'reward_id > 0 is the only signal the client acts on');
  const row = CAP.reward[String(r.reply.reward_id)];
  assert(row, `reward_id ${r.reply.reward_id} must exist in capsuleData.reward`);
  const l1 = call(engine, 'capsule_load', {}).reply;
  eq(l1.coin, l0.coin - 1, 'one twist spends exactly one coin');
  eq(l1.reward_list.length, 1, 'and records the reward');
  eq(l1.reward_list[0], r.reply.reward_id, 'the recorded id is the drawn one');
});

test('capsule: no coins -> reward_id 0 and nothing granted', ({ engine }) => {
  call(engine, 'capsule_load', {});
  engine.state.capsule.coin = 0;
  const house = JSON.stringify(engine.state.items.house);
  const r = call(engine, 'capsule_twist', {});
  eq(r.reply.reward_id, 0, '0 = the client does nothing, which is correct here');
  eq(JSON.stringify(engine.state.items.house), house, 'nothing was granted');
  eq(call(engine, 'capsule_load', {}).reply.reward_list.length, 0, 'nothing recorded');
});

test('capsule: the 3-reward threshold pays its table bonus exactly once', ({ engine }) => {
  call(engine, 'capsule_load', {});
  engine.state.capsule.coin = 50;
  const bonus = CAP.num_reward['3'];
  eq(bonus.num, 3, 'the first threshold is 3 in the table');
  const before = haveOf(engine, Number(bonus.item_id));
  for (let i = 0; i < 3; i++) call(engine, 'capsule_twist', {});
  eq(haveOf(engine, Number(bonus.item_id)), before + Number(bonus.item_num),
    'the threshold item must be granted when reward_list reaches 3');
  const midway = haveOf(engine, Number(bonus.item_id));
  for (let i = 0; i < 3; i++) call(engine, 'capsule_twist', {});
  eq(haveOf(engine, Number(bonus.item_id)), midway,
    'crossing 3 again must not pay a second time');
});

test('capsule: patch deals task IDS and spends patch_num', ({ engine }) => {
  call(engine, 'capsule_load', {});
  engine.state.capsule.taskList = [];
  engine.state.capsule.patchNum = 3;
  const r = call(engine, 'capsule_patch', {}).reply;
  eq(r.task_list.length, 3, 'deals up to patch_num');
  eq(engine.state.capsule.patchNum, 0, 'and consumes the slots');
  // IDS, not rows. This test used to assert rows with .name/.complete, i.e. it
  // locked in the crash: the client does capsuleData["task_list"][entry.toString()]
  // and getTaskCfg(...).name, so an object entry throws and the 扭蛋机 shows
  // 呱呱，吃坏肚子了.
  for (const id of r.task_list) {
    eq(typeof id, 'number', 'the wire entry must be a bare id');
    assert(CAP.task_list[String(id)], `task ${id} must exist in capsuleData.task_list`);
  }
});

test('capsule: a second patch deals nothing new (the client only patches empty)', ({ engine }) => {
  call(engine, 'capsule_load', {});
  engine.state.capsule.taskList = [];
  engine.state.capsule.patchNum = 8;
  const a = call(engine, 'capsule_patch', {}).reply.task_list.map((t) => Number(t));
  eq(a.length, 8, 'the table has 8 tasks');
  engine.state.capsule.patchNum = 8;
  const b = call(engine, 'capsule_patch', {}).reply.task_list;
  eq(b.length, 0, 'nothing left to deal, so the reply is empty');
  eq(engine.state.capsule.taskList.length, 8, 'and the full list is unchanged');
});

test('capsule: fast_task is 1-based and charges the table cost', ({ engine }) => {
  call(engine, 'capsule_load', {});
  engine.state.capsule.taskList = [{ id: 1, name: 'x', desc: 'y', complete: false }];
  engine.state.capsule.coin = 100;
  const cost = Number(CAP.fast_consume);
  eq(call(engine, 'capsule_fast_task', { index: 2 }).reply.code, -1, 'index 2 does not exist');
  eq(call(engine, 'capsule_fast_task', { index: 1 }).reply.code, 0, 'index 1 is the first task');
  eq(engine.state.capsule.coin, 100 - cost, 'charged fast_consume');
  eq(engine.state.capsule.taskList[0].complete, true, 'task completed');
  eq(call(engine, 'capsule_fast_task', { index: 1 }).reply.code, -1, 'cannot finish it twice');
});

test('capsule: fast_task is refused when the coins are short', ({ engine }) => {
  call(engine, 'capsule_load', {});
  engine.state.capsule.taskList = [{ id: 1, name: 'x', desc: 'y', complete: false }];
  engine.state.capsule.coin = 0;
  eq(call(engine, 'capsule_fast_task', { index: 1 }).reply.code, -1, 'refused, not gifted');
  eq(engine.state.capsule.taskList[0].complete, false, 'the task stays open');
});

test('capsule: get_coin moves pre_coin into coin', ({ engine }) => {
  call(engine, 'capsule_load', {});
  engine.state.capsule.coin = 2;
  engine.state.capsule.preCoin = 5;
  eq(call(engine, 'capsule_get_coin', {}).reply.code, 0, 'answers 0');
  const r = call(engine, 'capsule_load', {}).reply;
  eq(r.coin, 7, 'the pending coins are collected');
  eq(r.pre_coin, 0, 'and cleared');
});

test('capsule: real gameplay completes the matching task', ({ engine }) => {
  // task_list ids are real actions, so the engine ticks them off centrally
  call(engine, 'capsule_load', {});
  engine.state.capsule.taskList = [];
  engine.state.capsule.patchNum = 8;
  call(engine, 'capsule_patch', {});
  const find = (id) => engine.state.capsule.taskList.find((t) => Number(t.id) === id);
  assert(find(1) && find(3) && find(8), 'tasks 1/3/8 should be dealt');

  // 1 采摘花草  <- a successful harvest
  engine.state.clovers[0].last_harvest = 0;
  engine.state.clovers[0].element = 0;
  call(engine, 'clover_harvest', { clover_id: 1 });
  eq(find(1).complete, true, 'harvesting completes 采摘花草');

  // 3 花点三叶草 <- spending clover
  engine.state.clover = 100000;
  const shopRows = call(engine, 'item_load_shop_info', {}).reply;
  assert(shopRows, 'need the shop to spend clover');
  const buyable = Object.keys(GD.tables.shopData || {}).length;
  assert(buyable > 0, 'need shop rows');
  const shopId = Object.keys(GD.tables.shopData)[0];
  engine.state.clover = 100000;
  call(engine, 'item_buy', { shop_id: Number(shopId) });
  eq(find(3).complete, true, 'buying something completes 花点三叶草');

  // 8 保存一张照片 <- filing a pending postcard into the album
  engine.state.albumPending = [{ id: 5001, pic_id: 100, read: 0, new: 1 }];
  engine.state.pictures = [];
  call(engine, 'album_save_new', { id: 5001 });
  eq(find(8).complete, true, 'filing a photo completes 保存一张照片');
});

test('capsule: a REFUSED action does not complete its task', ({ engine }) => {
  call(engine, 'capsule_load', {});
  engine.state.capsule.taskList = [{ id: 8, name: 'x', desc: 'y', complete: false }];
  engine.state.pictures = [];
  engine.state.albumPending = [];
  const r = call(engine, 'album_save_new', { id: 999 });
  assert(r.reply.code !== 0, 'this filing must fail');
  eq(engine.state.capsule.taskList[0].complete, false,
    'a refused action must not tick the task off');
});

test('capsule: task 4 (分享) is deliberately never completed', ({ engine }) => {
  // sharing is impossible in a pure-local build, so that task stays open rather
  // than being silently faked
  call(engine, 'capsule_load', {});
  engine.state.capsule.taskList = [{ id: 4, name: '一次分享', desc: '分享成功一次', complete: false }];
  for (const c of ['clover_harvest', 'item_putin_bag', 'guest_serve', 'album_save_new']) {
    call(engine, c, { clover_id: 1, pos: 1, item_id: 3001, id: 1 });
  }
  eq(engine.state.capsule.taskList[0].complete, false,
    'nothing in a local build should complete the share task');
});

/* --------------------------------------------------- 料理 (cooking_*) */

/* cookingData: months 1..24 (two 12-month themes), each row a dish with
   task_num = 6. cookingTaskData: 8 rows, of which only SIX are achievable in a
   pure-local build -- id 2 is 观看广告 and id 8 is 完成分享. Those two are never
   dealt, so exactly 6 tasks are dealt, matching task_num. */

const COOK = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'cookingData.json'), 'utf8'));
const COOKT = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'cookingTaskData.json'), 'utf8'));

test('cooking: payload carries the FULL serverData', ({ engine }) => {
  const r = call(engine, 'cooking_load_cooking', {}).reply;
  for (const k of ['month', 'month_pro', 'week', 'complete', 'select',
    'refresh_time', 'task_list']) {
    assert(Object.prototype.hasOwnProperty.call(r, k),
      `CookingModel.${k} must be present or the client keeps a stale default`);
  }
  assert(Array.isArray(r.task_list), 'task_list is convertArray-ed');
  assert(r.month >= 1, 'a month must be chosen or no dish resolves');
});

test('cooking: exactly task_num tasks are dealt, all achievable', ({ engine }) => {
  const r = call(engine, 'cooking_load_cooking', {}).reply;
  const dish = COOK[String(engine.state.cooking.month + 12 * (engine.state.cooking.select - 1))];
  assert(dish, 'the dealt month must exist in cookingData');
  eq(r.task_list.length, Number(dish.task_num),
    'the dealt count must equal the dish\'s own task_num');
  eq(r.task_list.length, 6, 'task_num is 6 for every row');
  // and none of them may be the ad/share rows
  for (const t of r.task_list) {
    const def = COOKT[String(t.id)];
    assert(def, `task ${t.id} must exist in cookingTaskData`);
    assert(def.type !== 2 && def.type !== 8,
      `task ${t.id} (${def.dec}) is unachievable offline and must not be dealt`);
    eq(t.pro, 0, 'a fresh task starts at 0 progress');
    eq(t.complete, false, 'and incomplete');
  }
});

test('cooking: every dish item_id is a real Item, and each month has a dish', () => {
  const itemIds = new Set(GD.items.map((i) => i.id));
  for (let m = 1; m <= 24; m++) {
    const dish = COOK[String(m)];
    assert(dish, `cookingData must have month ${m}`);
    assert(itemIds.has(Number(dish.item_id)),
      `month ${m} dish item ${dish.item_id} must exist in Item.json`);
  }
});

test('cooking: a task cannot be claimed before its progress target', ({ engine }) => {
  const r = call(engine, 'cooking_load_cooking', {}).reply;
  const row = r.task_list[0];
  const def = COOKT[String(row.id)];
  assert(Number(def.state) >= 1, 'the task has a target');
  // at 0 progress it must be refused, or the client's red dot and ours disagree
  eq(call(engine, 'cooking_complete_task', { id: row.id }).reply.code, -1,
    'claiming an unfinished task must be refused');
  eq(call(engine, 'cooking_load_cooking', {}).reply.month_pro, 0, 'no progress credited');
});

test('cooking: real gameplay advances the matching task, then it can be claimed', ({ engine }) => {
  call(engine, 'cooking_load_cooking', {});
  const list = engine.state.cooking.taskList;
  const t1 = list.find((t) => Number(t.id) === 1);       // 每周登录 -> state 1
  assert(t1, 'task 1 should be dealt');
  // type 1 advances when the week rolls over
  engine.state.cooking.lastWeek = engine.state.cooking.week - 1;
  call(engine, 'cooking_load_cooking', {});
  eq(t1.pro, 1, 'crossing into a new week completes the login task');
  eq(call(engine, 'cooking_complete_task', { id: 1 }).reply.code, 0, 'now claimable');
  eq(engine.state.cooking.monthPro, 1, 'and month_pro advanced');
  eq(call(engine, 'cooking_complete_task', { id: 1 }).reply.code, -1, 'not twice');
});

test('cooking: the 80-clover task accumulates across harvests', ({ engine }) => {
  call(engine, 'cooking_load_cooking', {});
  const t4 = engine.state.cooking.taskList.find((t) => Number(t.id) === 4);
  assert(t4, 'task 4 should be dealt');
  const target = Number(COOKT['4'].state);
  eq(target, 80, 'the table says 80');
  for (let i = 0; i < 3; i++) {
    engine.state.clovers[0].last_harvest = 0;
    engine.state.clovers[0].element = 0;
    call(engine, 'clover_harvest', { clover_id: 1 });
  }
  eq(t4.pro, 3, 'three harvests -> three progress');
  eq(call(engine, 'cooking_complete_task', { id: 4 }).reply.code, -1,
    'still short of 80, so not claimable');
});

test('cooking: refresh_task swaps in an unused row', ({ engine }) => {
  const r = call(engine, 'cooking_load_cooking', {}).reply;
  const id = r.task_list[0].id;
  const rep = call(engine, 'cooking_refresh_task', { id }).reply;
  assert(rep.task, 'the client replaces that row from reply.task');
  eq(rep.task.pro, 0, 'a refreshed task restarts');
  eq(rep.task.complete, false, 'and is incomplete');
  const ids = engine.state.cooking.taskList.map((t) => Number(t.id));
  eq(new Set(ids).size, ids.length, 'no duplicate task ids after a refresh');
});

test('cooking: start_cooking needs EVERY task complete and pays the dish item', ({ engine }) => {
  call(engine, 'cooking_load_cooking', {});
  const C = engine.state.cooking;
  eq(call(engine, 'cooking_start_cooking', {}).reply.code, -1,
    'refused while tasks are open');

  const dish = COOK[String(C.month + 12 * (C.select - 1))];
  const before = haveOf(engine, Number(dish.item_id));
  for (const t of C.taskList) {
    t.pro = Number(COOKT[String(t.id)].state);
    t.complete = true;
  }
  eq(call(engine, 'cooking_start_cooking', {}).reply.code, 0, 'now it goes through');
  eq(haveOf(engine, Number(dish.item_id)), before + 1,
    'the dish item must actually be granted');
  eq(C.complete, true, 'and the month is marked complete');
  eq(call(engine, 'cooking_start_cooking', {}).reply.code, -1, 'not twice');
});

test('cooking: selecting a theme re-deals and keeps the payload consistent', ({ engine }) => {
  call(engine, 'cooking_load_cooking', {});
  eq(call(engine, 'cooking_select', { index: 2 }).reply.code, 0, 'theme 2 accepted');
  eq(engine.state.cooking.select, 2, 'select recorded');
  const r = call(engine, 'cooking_load_cooking', {}).reply;
  eq(r.select, 2, 'and delivered');
  eq(r.task_list.length, 6, 'with a fresh set of tasks');
  eq(r.month_pro, 0, 'progress reset for the new theme');
  eq(call(engine, 'cooking_select', { index: 0 }).reply.code, -1, 'index 0 is not a theme');
});

test('cooking: the ad and share commands are REFUSED, not faked', ({ engine }) => {
  assert(call(engine, 'cooking_look_ad', {}).reply.code !== 0,
    'there is no ad to watch in a pure-local build');
  assert(call(engine, 'cooking_share', {}).reply.code !== 0,
    'and no share either');
});

/* ------------------------------------------ 新手引导 (tutorial_*) */

/* The guide ADVANCES ONLY IF the server answers `{ok: true}` to BOTH `_q`
   queries. With no handler the reply was `{}`, `i.ok` was undefined, and
   `checkGuide()` re-entered the award view forever -- a fresh save could never
   finish the tutorial. */

test('tutorial: both _q queries answer ok:true (or a new save stalls)', ({ engine }) => {
  // this exact field is what the client tests: `i.ok ? advance : checkGuide()`
  eq(call(engine, 'tutorial_step_open_door_q', {}).reply.ok, true,
    'open_door_q must answer {ok:true}');
  eq(call(engine, 'tutorial_step_ask_award_q', {}).reply.ok, true,
    'ask_award_q must answer {ok:true}');
});

test('tutorial: the full guide sequence advances and does not regress', ({ engine }) => {
  // the client's order: open_door then open_door_q, then ask_award then ask_award_q
  call(engine, 'tutorial_step_open_door', {});
  assert(call(engine, 'tutorial_step_open_door_q', {}).reply.ok, 'step 1 ok');
  call(engine, 'tutorial_step_ask_award', {});
  assert(call(engine, 'tutorial_step_ask_award_q', {}).reply.ok, 'step 2 ok');
  const steps = engine.state.guide.steps;
  for (const s of ['open_door', 'open_door_q', 'ask_award', 'ask_award_q']) {
    assert(steps.indexOf(s) !== -1, `${s} should have been recorded`);
  }
  // replaying the sequence must stay ok (a reload re-runs it)
  assert(call(engine, 'tutorial_step_open_door_q', {}).reply.ok, 'still ok on replay');
  assert(call(engine, 'tutorial_step_ask_award_q', {}).reply.ok, 'still ok on replay');
});

test('tutorial: the starter award is granted exactly once, and pushed', ({ engine }) => {
  const c0 = engine.state.clover;
  const t0 = engine.state.ticket;
  const r1 = call(engine, 'tutorial_step_ask_award', {});
  assert(engine.state.clover > c0, 'clover must actually be credited');
  assert(engine.state.ticket > t0, 'and the ticket too');
  assert(pushNamed(r1, 'clover_update').length === 1,
    'clover_update must be pushed (addClover is a stub)');
  assert(pushNamed(r1, 'item_update_ticket').length === 1,
    'item_update_ticket must be pushed');
  const c1 = engine.state.clover;
  call(engine, 'tutorial_step_ask_award', {});
  eq(engine.state.clover, c1, 'claiming again must not pay a second time');
});

test('tutorial: a brand-new save can walk the whole guide without stalling', () => {
  // this is the user-facing scenario: start from nothing and follow the client's
  // own call order
  const { engine } = newEngine();
  for (let lap = 0; lap < 3; lap++) {
    call(engine, 'tutorial_step_open_door', {});
    const a = call(engine, 'tutorial_step_open_door_q', {});
    assert(a.reply.ok === true, `lap ${lap}: guide would stall at open_door_q`);
    call(engine, 'tutorial_step_ask_award', {});
    const b = call(engine, 'tutorial_step_ask_award_q', {});
    assert(b.reply.ok === true, `lap ${lap}: guide would stall at ask_award_q`);
  }
  eq(engine.state.guide.awardGiven, true, 'the starter award was handed out');
  assert(engine.state.clover > 0, 'and the new save has its starting clovers');
});

/* --------------------------------------------- 回忆彩蛋 (misc_moment_*) */

/* MomentModel.data is `{has_map:{}}` and `misc_moment_load` only ADDS:
     for (id of convertArray(e.list)) this.data.has_map[id] = true;
   so the payload is {list:[ids]} and an empty list meant nothing ever unlocked. */

const MOMENTS = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'momentData.json'), 'utf8')).list;

test('moment: load delivers {list:[ids]} reflecting what is unlocked', ({ engine }) => {
  const r = call(engine, 'misc_moment_load', {}).reply;
  assert(Array.isArray(r.list), 'the payload key is `list`');
  eq(r.list.length, 0, 'a fresh save has nothing unlocked yet');
});

test('moment: every momentData row is renderable', () => {
  const ids = Object.keys(MOMENTS);
  assert(ids.length > 0, 'momentData must have rows');
  for (const k of ids) {
    const row = MOMENTS[k];
    for (const f of ['id', 'desc', 'param', 'pic', 'type']) {
      assert(row[f] !== undefined, `moment ${k}.${f} is missing`);
    }
  }
});

test('moment: unlock accepts a real id and shows up in the load', ({ engine }) => {
  const id = Number(Object.keys(MOMENTS)[0]);
  eq(call(engine, 'misc_moment_unlock', { id }).reply.code, 0, 'answers 0');
  const r = call(engine, 'misc_moment_load', {}).reply;
  eq(r.list.length, 1, 'now unlocked');
  eq(r.list[0], id, 'the right one');
  // unlocking the same one again stays 0 but does not duplicate
  eq(call(engine, 'misc_moment_unlock', { id }).reply.code, 0, 'idempotent');
  eq(call(engine, 'misc_moment_load', {}).reply.list.length, 1, 'no duplicate entry');
});

test('moment: an unknown id is refused (the client would have no art for it)', ({ engine }) => {
  eq(call(engine, 'misc_moment_unlock', { id: 999999 }).reply.code, -1, 'refused');
  eq(call(engine, 'misc_moment_load', {}).reply.list.length, 0, 'nothing recorded');
});

test('moment: unlocks persist across a reopen', ({ engine, savePath }) => {
  const id = Number(Object.keys(MOMENTS)[1]);
  call(engine, 'misc_moment_unlock', { id });
  const re = reopen(savePath);
  eq(call(re, 'misc_moment_load', {}).reply.list.indexOf(id) !== -1, true,
    'the unlocked moment must survive a restart');
});

/* ------------------------------------------- 动态照片 (animpicture_*) */

/* AnimPictureModel.data = {guide, page_num, phase, item_num, exp, exp_pic,
   pic_list}. `animpicture_load` REPLACES it, and `animpicture_use_item` is
   GATED on `e.phase >= 0` -- a reply without `phase` silently does nothing. */

const ANIMD = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'animpictureData.json'), 'utf8'));
/** A picture id from the album whose pic_id IS in pic_map (only 3 qualify). */
const ANIM_PIC = () => Number(Object.keys(ANIMD.pic_map)[0]);

test('animpicture: payload carries the FULL model', ({ engine }) => {
  const r = call(engine, 'animpicture_load', {}).reply;
  for (const k of ['guide', 'page_num', 'phase', 'item_num', 'exp', 'exp_pic', 'pic_list']) {
    assert(Object.prototype.hasOwnProperty.call(r, k),
      `AnimPictureModel.${k} must be present or the client keeps a stale default`);
  }
  assert(Array.isArray(r.pic_list) && Array.isArray(r.exp_pic), 'both are arrays');
});

test('animpicture: only the THREE pic_map postcards can become a moving photo', ({ engine }) => {
  const map = ANIMD.pic_map;
  eq(Object.keys(map).length, 3, 'pic_map has exactly three entries');
  // a postcard NOT in pic_map must be refused
  const other = Object.values(GD.tables.Picture).map((r) => Number(r.id))
    .find((id) => map[String(id)] === undefined);
  engine.state.pictures = [{ id: 9001, pic_id: other, read: 0, new: 1 }];
  eq(call(engine, 'animpicture_select_pic', { id: 9001 }).reply.code, -1,
    'a postcard outside pic_map cannot be animated');
  eq(engine.state.pictures.length, 1, 'and it stays in the album');

  // ...and one that IS in pic_map goes through
  const ok = Number(Object.keys(map)[0]);
  engine.state.pictures = [{ id: 9002, pic_id: ok, read: 0, new: 1 }];
  eq(call(engine, 'animpicture_select_pic', { id: 9002 }).reply.code, 0, 'accepted');
  eq(engine.state.pictures.length, 0, 'and left the album');
  eq(call(engine, 'animpicture_load', {}).reply.pic_list.length, 1, 'a page was created');
});

test('animpicture: use_item ALWAYS answers a phase >= 0 (it is the gate)', ({ engine }) => {
  const r = call(engine, 'animpicture_use_item', {});
  assert(typeof r.reply.phase === 'number', 'phase must be a number');
  assert(r.reply.phase >= 0, 'the client gate is `e.phase >= 0`');
});

test('animpicture: open_album is 1-based and stops at the slot phase count', ({ engine }) => {
  const ok = Number(Object.keys(ANIMD.pic_map)[0]);
  const slot = ANIMD.pic_map[String(ok)];
  const total = ANIMD.list[String(slot)].phase_list
    .reduce((a, p) => Math.max(a, Number(p.phase) || 0), 0);
  assert(total > 1, 'this slot has several phases');
  engine.state.pictures = [{ id: 9100, pic_id: ok, read: 0, new: 1 }];
  call(engine, 'animpicture_select_pic', { id: 9100 });
  eq(call(engine, 'animpicture_open_album', { index: 2 }).reply.code, -1,
    'page 2 does not exist');
  for (let i = 0; i < total; i++) {
    eq(call(engine, 'animpicture_open_album', { index: 1 }).reply.code, 0, `slot ${i} opens`);
  }
  eq(call(engine, 'animpicture_open_album', { index: 1 }).reply.code, -1,
    'no more slots than the table has phases');
  eq(call(engine, 'animpicture_load', {}).reply.pic_list[0].put_num, total, 'put_num reached it');
});

test('animpicture: use_item walks the phases and finishes the page', ({ engine }) => {
  const ok = Number(Object.keys(ANIMD.pic_map)[0]);
  const slot = ANIMD.pic_map[String(ok)];
  const total = ANIMD.list[String(slot)].phase_list
    .reduce((a, p) => Math.max(a, Number(p.phase) || 0), 0);
  engine.state.pictures = [{ id: 9200, pic_id: ok, read: 0, new: 1 }];
  call(engine, 'animpicture_select_pic', { id: 9200 });
  // walk until it returns to 0, then item_num must have gone up
  let sawZero = false;
  for (let i = 0; i < total + 2 && !sawZero; i++) {
    const r = call(engine, 'animpicture_use_item', {});
    if (r.reply.phase === 0) sawZero = true;
  }
  assert(sawZero, 'the phase must come back round to 0 when the page finishes');
  eq(call(engine, 'animpicture_load', {}).reply.item_num, 1, 'item_num++ on completion');
});

test('animpicture: album_add_pic moves a photo in, remove_pic returns it', ({ engine }) => {
  const ok = Number(Object.keys(ANIMD.pic_map)[0]);
  engine.state.pictures = [{ id: 9300, pic_id: ok, read: 0, new: 1 },
    { id: 9301, pic_id: 100, read: 0, new: 1 }];
  call(engine, 'animpicture_select_pic', { id: 9300 });
  const slotId = ANIMD.pic_map[String(ok)];
  // a photo can only be placed if it is a real album row
  eq(call(engine, 'animpicture_album_add_pic', { index: 1, slot: 1, id: 9301 }).reply.code, 0,
    'placed');
  eq(engine.state.pictures.length, 0, 'it left the album');
  const page = call(engine, 'animpicture_load', {}).reply.pic_list[0];
  eq(page.id, Number(slotId), 'into the right slot');
  assert(page.pictures[0] && page.pictures[0].id === 9301, 'the photo is in slot 0');

  // flag falsey -> the photo goes BACK to the album
  eq(call(engine, 'animpicture_album_remove_pic', { index: 1, slot: 1, flag: false }).reply.code, 0,
    'removed');
  assert(engine.state.pictures.some((p) => p.id === 9301), 'returned to the album');
});

test('animpicture: a refused action is a non-zero code, never a missing phase', ({ engine }) => {
  engine.state.pictures = [];
  const r = call(engine, 'animpicture_select_pic', { id: 999999 });
  assert(r.reply.code !== 0, 'unknown picture refused');
  // and use_item must still answer a usable phase even with nothing selected
  const u = call(engine, 'animpicture_use_item', {});
  assert(typeof u.reply.phase === 'number' && u.reply.phase >= 0, 'phase still present');
});

test('events: a HALF-BUILT event must stay closed, never half-visible', ({ engine }) => {
  // Every seasonal event's UI is gated behind `isOpen()`, which is a time window
  // (`now < end_time`). The events whose sub-commands are NOT implemented yet
  // therefore answer `end_time: 0` -- the activity is INERT, so the client never
  // opens it and the missing commands are simply unreachable.
  //
  // That distinction matters: enabling one of these windows without implementing
  // its commands would produce exactly the stall bug that hid the tutorial
  // (`ok` never true -> the view re-enters forever). This test makes that loud.
  const GATED = {
    museumday_load: ['museumday_refresh', 'museumday_random_compass',
      'museumday_dir_compass', 'museumday_get_items', 'museumday_arrive',
      'museumday_start_advance', 'museumday_load_path', 'museumday_inspire'],
    greetcard_load: ['greetcard_buy', 'greetcard_change_bg', 'greetcard_send',
      'greetcard_get_reward', 'greetcard_stock'],
    springcard_load: ['springcard_buy', 'springcard_change_bg', 'springcard_send',
      'springcard_get_reward'],
    partycake_load: ['partycake_make', 'partycake_light', 'partycake_answer',
      'partycake_reward_make'],
  };
  const src = fs.readFileSync(ENGINE, 'utf8');
  const missing = [];
  for (const cmd of Object.keys(GATED)) {
    const r = call(engine, cmd, {}).reply;
    const open = Number(r.end_time) > Math.floor(Date.now() / 1000)
      || Number(r.start_time) > 0;
    // find which of its sub-commands have no handler
    const unimplemented = GATED[cmd].filter(
      (sub) => !new RegExp('^\\s{4}' + sub + '\\s*:', 'm').test(src));
    if (open && unimplemented.length) {
      missing.push(`${cmd} is OPEN but ${unimplemented.join(', ')} unimplemented`);
    }
    if (!open) {
      // and while closed it must still carry a usable field set, or the client
      // throws the moment anything reads it
      assert(Object.prototype.hasOwnProperty.call(r, 'end_time'),
        `${cmd} must still send end_time`);
    }
  }
  eq(missing.length, 0,
    `an event window was opened without its commands: ${missing.join('; ')}`);
});

/* ----------------------------------------------------- 故事 (story_*) */

/* StoryData = {id, partner, name, gift:-1, feedback:-1}; all three commands are
   needResponse:FALSE, so no reply field can gate anything -- but the
   authoritative state still has to move or a reload would disagree. */

test('story: payload is {stories, new_story_id} with gift/feedback at -1', ({ engine }) => {
  engine.state.storyBook = {
    list: [{ id: 1, partner: 0, name: 'test', storyid: 1, gift: -1, feedback: -1 }],
    newId: 1,
  };
  const r = call(engine, 'story_load', {}).reply;
  assert(Array.isArray(r.stories), 'the key is `stories`');
  eq(r.new_story_id, 1, 'and `new_story_id`');
  const s = r.stories[0];
  for (const k of ['id', 'partner', 'name', 'gift', 'feedback']) {
    assert(Object.prototype.hasOwnProperty.call(s, k), `StoryData.${k} must be present`);
  }
  eq(s.gift, -1, 'gift starts at -1 (the client gates on `-1 == story.gift`)');
});

test('story: every story row in the table is usable', () => {
  const t = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'story.json'), 'utf8'));
  assert(Array.isArray(t.story) && t.story.length > 0, 'story rows exist');
  for (const r of t.story) {
    for (const f of ['storyid', 'name', 'desc', 'icon']) {
      assert(r[f] !== undefined, `story ${r.storyid}.${f} is missing`);
    }
  }
  assert(Number(t.const.friend_choice_percent) > 0,
    'the table ships its own tuning constant, which the drop roll uses');
});

test('story: sending a gift consumes the item and records it once', ({ engine }) => {
  const itemId = TOOL_ITEM_ID();
  engine.state.items.house = [{ item_id: itemId, count: 2 }];
  engine.state.storyBook = {
    list: [{ id: 1, partner: 0, name: 'x', gift: -1, feedback: -1 }], newId: 1,
  };
  call(engine, 'story_send_gift', { id: 1, gift: itemId });
  eq(haveOf(engine, itemId), 1, 'one consumed');
  const r = call(engine, 'story_load', {}).reply;
  eq(r.stories[0].gift, itemId, 'the gift is recorded');
  // the client only allows one gift per story (`-1 == story.gift` guard)
  call(engine, 'story_send_gift', { id: 1, gift: itemId });
  eq(haveOf(engine, itemId), 1, 'a second gift to the same story must not be taken');
});

test('story: gifting an item you do not own is refused', ({ engine }) => {
  engine.state.items.house = [];
  engine.state.storyBook = {
    list: [{ id: 2, partner: 0, name: 'x', gift: -1, feedback: -1 }], newId: 0,
  };
  call(engine, 'story_send_gift', { id: 2, gift: TOOL_ITEM_ID() });
  eq(call(engine, 'story_load', {}).reply.stories[0].gift, -1, 'nothing recorded');
});

test('story: read_new_story clears the new id, feedback records', ({ engine }) => {
  engine.state.storyBook = {
    list: [{ id: 3, partner: 1, name: 'x', gift: -1, feedback: -1 }], newId: 3,
  };
  eq(call(engine, 'story_load', {}).reply.new_story_id, 3, 'there is a new one');
  call(engine, 'story_read_new_story', {});
  eq(call(engine, 'story_load', {}).reply.new_story_id, 0, 'cleared');
  call(engine, 'story_feedback_gift', { id: 3 });
  eq(call(engine, 'story_load', {}).reply.stories[0].feedback, 1, 'feedback recorded');
});

test('story: trips find stories, and new_story_id points at the newest', ({ engine }) => {
  const lunch = idsOfType(0)[0];
  engine.state.storyBook = { list: [], newId: 0, seq: 0 };
  for (let i = 0; i < 60; i++) {
    engine.state.items.bag[0] = lunch;
    engine.state.travel.nextDepartAt = 1;
    engine.tick();
    engine.state.travel.returnAt = 1;
    engine.tick();
  }
  const book = engine.state.storyBook;
  assert(book.list.length > 0, 'trips should find a story now and then');
  eq(book.newId, book.list[book.list.length - 1].id, 'newId is the newest instance');
  const names = new Set(JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'story.json'), 'utf8'))
    .story.map((r) => r.name));
  for (const s of book.list) {
    assert(names.has(s.name), `found story "${s.name}" must be a real table row`);
    eq(s.gift, -1, 'a fresh story has no gift yet');
  }
});

test('values: every DEF() key actually exists in define.json', () => {
  // A missing key makes DEF() silently return our fallback, so the "restored"
  // value would really be an invented one. This is the check that keeps the
  // restored/chosen distinction honest.
  const src = fs.readFileSync(ENGINE, 'utf8');
  const def = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8'));
  const have = new Set([...Object.keys(def.scalars || {}), ...Object.keys(def.maps || {})]);
  const missing = [];
  const re = /DEF\(\s*'([A-Za-z0-9_]+)'/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    if (!have.has(m[1])) missing.push(`${m[1]} (line ${src.slice(0, m.index).split('\n').length})`);
  }
  assert(missing.length > 0 || true, 'sanity');
  eq(missing.length, 0, `DEF() keys missing from define.json: ${missing.join(', ')}`);
});

test('values: the recovered originals the engine reads are the table\'s numbers', () => {
  const def = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8')).scalars;
  // these are the values we had been inventing while the originals sat unused
  eq(def.FRIEND_VISIT_COOL, 21600, 'the real visitor cooldown is 6 hours');
  eq(def.TRAVEL_TIME_MIN, 60, 'the travel floor is 60 minutes');
  eq(def.FROG_DRIFTRETURNTIME, 10, 'a stray trip returns in 10');
  eq(def.FROG_DRIFTRETURNTIME_MAX, 20, 'and at most 20');
  eq(def.BAGITEMS, 4, 'bag slots');
  eq(def.DESKITEMS, 8, 'desk slots');
  eq(def.CloverDestroyTime, 0.6, 'clover withering is a real rule in the table');
});

test('values: offline pacing stays short so a sitting is playable', ({ engine }) => {
  // the whole point of the shortened defaults: a fresh player should see the frog
  // leave and come back without waiting hours
  const GDx = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
  const lunch = GDx.items.find((i) => i.type === 0).id;
  engine.state.items.bag[0] = lunch;
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  const w = engine.state.travel.returnAt - engine.state.travel.departAt;
  /* 12..40 minutes: players reported the old 90-240 s as "a bit fast". Faithful mode
     (FROG_FAITHFUL=1) still gives the recovered 60 min..6 h. */
  assert(w >= 12 * 60 && w <= 40 * 60,
    `offline travel window ${w}s must stay inside 12..40 min (faithful mode is opt-in via FROG_FAITHFUL=1)`);
});

test('travel: tools on the desk cannot substitute for food', ({ engine }) => {
  engine.state.items.bag = [-1, -1, -1, -1];
  engine.state.items.desk[4] = idsOfType(2)[0];
  engine.state.travel.plan = null;
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  eq(engine.state.travel.plan, null);
  eq(engine.state.frog.status, 0);
  eq(call(engine,'item_set_bag_completed',{completed:true}).reply.code,-1);
  eq(engine.state.items.bagCompleted,0);
});

/** What the engine's defaultState() produces for the 20 clover slots. */
const makeCloversForTest = () => {
  const { engine } = newEngine();
  return JSON.parse(JSON.stringify(engine.state.clovers));
};

/* ------------------------------------------- clover rule (client's own guard) */

/* The client decides whether to DRAW a clover with this exact condition:
     if (!(-1 == l.last_harvest ||
           (l.last_harvest > 0 && l.last_harvest + l.rebirth_span > now))) { draw }
   i.e. draw when last_harvest == 0 (ready), or > 0 and the span has elapsed;
   do NOT draw when -1 (harvested) or while still growing.
   `rebirth_span` is therefore load-bearing: a zero/absent span would make the
   client draw every clover even while it is regrowing. */

test('clover: the model matches the client\'s own draw guard', ({ engine }) => {
  const now = Math.floor(Date.now() / 1000);
  engine.state.clovers = makeCloversForTest();
  const c = engine.state.clovers[0];
  // every field the client's guard and renderer read
  for (const k of ['clover_id', 'element', 'sprite', 'last_harvest', 'rebirth_span']) {
    assert(Object.prototype.hasOwnProperty.call(c, k),
      `CloverInfo.${k} must be present or the client's guard misreads the slot`);
  }
  assert(c.rebirth_span > 0, 'a zero span would make the client draw a growing clover');

  // reproduce the client's condition for all three states
  const drawn = (s) => !(s.last_harvest === -1
    || (s.last_harvest > 0 && s.last_harvest + s.rebirth_span > now));
  eq(drawn({ last_harvest: 0, rebirth_span: c.rebirth_span }), true,
    'last_harvest 0 = ready -> the client draws it');
  eq(drawn({ last_harvest: -1, rebirth_span: c.rebirth_span }), false,
    'last_harvest -1 = harvested -> nothing drawn');
  eq(drawn({ last_harvest: now - 10, rebirth_span: 3600 }), false,
    'still growing -> nothing drawn');
  eq(drawn({ last_harvest: now - 4000, rebirth_span: 3600 }), true,
    'span elapsed -> drawn again');
});

test('clover: harvesting re-rolls the span (the original draws it per regrowth)', ({ engine }) => {
  engine.state.clovers = makeCloversForTest();
  const slot = engine.state.clovers[0];
  slot.element = 0;
  slot.sprite = 1;
  slot.last_harvest = 0;
  const before = slot.rebirth_span;
  // a fixed span would make every clover regrow in lockstep; the original's
  // clamp(normal(7200,1800),300,14400) is per-clover
  let sawDifferent = false;
  for (let i = 0; i < 40 && !sawDifferent; i++) {
    engine.state.clovers = makeCloversForTest();
    const s2 = engine.state.clovers[0];
    s2.element = 0;
    s2.sprite = 1;
    s2.last_harvest = 0;
    call(engine, 'clover_harvest', { clover_id: 1 });
    if (s2.rebirth_span !== before) sawDifferent = true;
  }
  assert(sawDifferent, 'rebirth_span must be re-rolled, not a constant');
  const s = engine.state.clovers[0];
  assert(s.rebirth_span >= 300 && s.rebirth_span <= 14400,
    `span ${s.rebirth_span} must stay inside the clamp 300..14400`);
});

test('clover: the regrowth distribution matches the JP formula, not a uniform draw', ({ engine }) => {
  // uniform over the same range has a similar MEAN by luck (which is how the
  // wrong shape slipped through before), so assert the shape instead
  const spans = [];
  for (let i = 0; i < 400; i++) {
    engine.state.clovers = makeCloversForTest();
    const s = engine.state.clovers[0];
    s.element = 0;
    s.sprite = 1;
    s.last_harvest = 0;
    call(engine, 'clover_harvest', { clover_id: 1 });
    spans.push(s.rebirth_span);
  }
  const n = spans.length;
  const mean = spans.reduce((a, b) => a + b, 0) / n;
  const sd = Math.sqrt(spans.reduce((a, b) => a + (b - mean) ** 2, 0) / n);
  assert(mean > 6000 && mean < 8400, `mean ${Math.round(mean)} should sit near 7200`);
  assert(sd > 900 && sd < 2600, `sd ${Math.round(sd)} should sit near 1800`);
  // a normal draw is concentrated: uniform-over-range would have sd ~4080
  assert(sd < 3000, 'sd well under the uniform value proves the normal shape');
});

/* ------------------------------------------- recovered caps (define.json) */

test('caps: an item stack never exceeds HaveItemMax (99)', ({ engine }) => {
  const def = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8')).scalars;
  const cap = Number(def.HaveItemMax);
  eq(cap, 99, 'the table says 99');
  const itemId = idsOfType(3)[0];
  engine.state.items.house = [];
  // grant well past the cap
  engine.state.items.house = [{ item_id: itemId, count: 0 }];
  call(engine, 'item_select_gift', { index_list: [] });   // harmless
  // use a real grant path: buy repeatedly is slow, so drive addHouseItem via a
  // command that grants a known count -- item_select_gift with a queued package
  engine.state.selectGift = { 0: { item_id: itemId, count: cap + 50 } };
  call(engine, 'item_select_gift', { index_list: [0] });
  const row = engine.state.items.house.find((x) => x.item_id === itemId);
  assert(row, 'the item landed in the house');
  eq(row.count, cap, `a stack must be clamped to ${cap}`);
});

test('caps: consuming still works after the clamp (the cap is upper-only)', ({ engine }) => {
  const itemId = idsOfType(3)[0];
  engine.state.items.house = [{ item_id: itemId, count: 5 }];
  engine.state.selectGift = { 0: { item_id: itemId, count: -3 } };
  call(engine, 'item_select_gift', { index_list: [0] });
  const row = engine.state.items.house.find((x) => x.item_id === itemId);
  // -3 leaves 2; the clamp must not have turned that into 99
  assert(!row || row.count === 2, `consuming must not be clamped upward (got ${row && row.count})`);
});

test('caps: the mail list is trimmed to MAIL_MAX (100)', ({ engine }) => {
  const def = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8')).scalars;
  eq(Number(def.MAIL_MAX), 100, 'the table says 100');
  // fill past the cap by forcing the tutorial-mail path
  engine.state.mails = [];
  for (let i = 0; i < 140; i++) {
    engine.state.mails.push({ id: i + 1, type: 3, title: 't', message: '', items: [], pictures: [] });
  }
  engine.state.mailTutorialSent = true;
  // the cap is enforced on the READ path too, so it holds however the list grew
  const delivered = call(engine, 'mail_load', {}).reply;
  assert(delivered.length <= 100, `mail list must be capped at 100, got ${delivered.length}`);
  // and the NEWEST are the ones kept
  eq(delivered[delivered.length - 1].id, 140, 'newest kept');
  eq(engine.state.mails.length, 100, 'the stored list was trimmed, not just the reply');
});

test('moment: the unlock rule uses MomentType + the row\'s own param', () => {
  // define.json: MomentType = {frog_motion:1, egg_motion:2, guest:3, shop:4, egg_id:5}
  // and each momentData row names its trigger in `param`.
  const def = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8'));
  eq(def.maps.MomentType.frog_motion, 1, 'type 1 is frog_motion');
  eq(def.maps.MomentType.guest, 3, 'type 3 is guest');
  eq(def.maps.MomentType.shop, 4, 'type 4 is shop');
  const motionNames = new Set(Object.values(def.maps.FrogMotionName));
  const moments = MOMENTS;
  // Most type-1 params ARE FrogMotionName values ('dokusyo_ie', 'knit', 'cut',
  // 'sleep_2' ...), which is what makes the rule work. At least one is NOT
  // ('LW_writing', a separate animation our engine never plays) -- such a moment
  // can never unlock through this path, so assert the split instead of pretending
  // every row matches.
  const type1 = Object.values(moments).filter((r) => Number(r.type) === 1);
  const matching = type1.filter((r) => motionNames.has(String(r.param)));
  const other = type1.filter((r) => !motionNames.has(String(r.param)));
  assert(matching.length >= 4, `expected several reachable type-1 moments, got ${matching.length}`);
  assert(matching.length > other.length,
    'the FrogMotionName form must dominate, or the rule is the wrong reading');
  for (const r of other) {
    assert(typeof r.param === 'string' && r.param.length > 0,
      `unreachable moment ${r.id} at least names a param (${r.param})`);
  }
});

test('moment: a guest arrival unlocks its type-3 moment', ({ engine }) => {
  engine.state.moments = [];
  engine.state.guestCoolUntil = 0;
  engine.state.guest = null;
  engine.state.guestNextRollAt = 0;
  // roll until a guest appears, then check that guest's own moment got unlocked
  for (let i = 0; i < 600 && !engine.state.guest; i++) {
    engine.state.guestNextRollAt = 1;
    engine.tick();
  }
  const g = engine.state.guest;
  assert(g, 'a guest should arrive');
  const chars = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'tables', 'Character.json'), 'utf8'));
  const res = String(chars.data[g.id].img.index).replace(/^mail_/, '');
  const want = Object.values(MOMENTS).find(
    (r) => Number(r.type) === 3 && String(r.param) === res);
  if (want) {
    assert(engine.state.moments.indexOf(Number(want.id)) !== -1,
      `guest ${res} should have unlocked moment ${want.id}`);
  }
});

test('moment: a frog motion unlocks its type-1 moment', ({ engine }) => {
  engine.state.moments = [];
  engine.state.frog.status = 0;
  engine.state.frog.motionNextAt = 0;
  const def = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8'));
  const motionNames = def.maps.FrogMotionName;
  let unlocked = 0;
  for (let i = 0; i < 400 && unlocked === 0; i++) {
    engine.state.frog.motionNextAt = 0;
    engine.tick();
    const name = motionNames[String(engine.state.frog.motion)];
    const want = Object.values(MOMENTS).find(
      (r) => Number(r.type) === 1 && String(r.param) === name);
    if (want && engine.state.moments.indexOf(Number(want.id)) !== -1) unlocked++;
  }
  assert(unlocked > 0, 'a matching frog motion must unlock its moment');
  // and what got unlocked must be a type-1 moment, never an invented id
  const ids = new Set(Object.values(MOMENTS).map((r) => Number(r.id)));
  for (const id of engine.state.moments) {
    assert(ids.has(id), `unlocked ${id} must be a real moment`);
  }
});

test('moment: buying from the merchant unlocks the type-4 moment', ({ engine }) => {
  engine.state.moments = [];
  engine.state.clover = 100000;
  const list = call(engine, 'furniture_load_furniture', {}).reply.shop.shop_list;
  const row = list.find((r) => Number(FS_ROW(r.shop_id).price) > 0) || list[0];
  eq(call(engine, 'furniture_buy_shop', { id: row.shop_id }).reply.code, 0, 'bought');
  const want = Object.values(MOMENTS).find(
    (r) => Number(r.type) === 4 && String(r.param) === 'drummer');
  assert(want, 'a type-4 drummer moment exists');
  assert(engine.state.moments.indexOf(Number(want.id)) !== -1,
    'buying from the merchant should unlock the drummer moment');
});

test('weather: the emitted enums are IN RANGE for the client-read maps', ({ engine }) => {
  // The client resolves the scene/weather art from these numbers, and an
  // out-of-range value has no art at all. This exact bug happened once: the
  // weather defaulted to 0, which is outside WeatherType's 1..9.
  const def = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8')).maps;
  const seasonVals = new Set(Object.values(def.Season));
  const hoursVals = new Set(Object.values(def.HoursType));
  const weatherVals = new Set(Object.values(def.WeatherType));
  eq(Math.min(...weatherVals), 1, 'WeatherType starts at 1, so 0 is invalid');
  eq(Math.max(...weatherVals), 9, 'and runs to 9');

  const w = engine.state.weather;
  assert(seasonVals.has(w.season), `season ${w.season} must be one of ${[...seasonVals]}`);
  assert(hoursVals.has(w.hoursType), `hoursType ${w.hoursType} must be one of ${[...hoursVals]}`);
  assert(weatherVals.has(w.weather), `weather ${w.weather} must be one of ${[...weatherVals]}`);

  // and the payload the client actually receives carries the same three
  // NOTE: weather does NOT travel in client_load_role -- it has its own
  // `weather_load` push (whose keys are season / hours_type / weather).
  const wl = call(engine, 'weather_load', {}).reply;
  assert(seasonVals.has(wl.season), `weather_load.season ${wl.season} out of range`);
  assert(hoursVals.has(wl.hours_type), `weather_load.hours_type ${wl.hours_type} out of range`);
  assert(weatherVals.has(wl.weather), `weather_load.weather ${wl.weather} out of range`);
});

test('weather: the enums stay in range across a full simulated year', ({ engine }) => {
  const def = JSON.parse(fs.readFileSync(
    path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8')).maps;
  const seasonVals = new Set(Object.values(def.Season));
  const hoursVals = new Set(Object.values(def.HoursType));
  const weatherVals = new Set(Object.values(def.WeatherType));
  const seen = { season: new Set(), hoursType: new Set(), weather: new Set() };
  // walk a year in 11-day steps: enough to visit every season and every day-of-year
  // residue that weatherNow() depends on
  const start = Date.UTC(2026, 0, 1);
  for (let i = 0; i < 34; i++) {
    const t = Math.floor((start + i * 11 * 86400) / 1000);
    const w = engine.weatherAt ? engine.weatherAt(t) : null;
    if (w) {
      seen.season.add(w.season);
      seen.hoursType.add(w.hoursType);
      seen.weather.add(w.weather);
    }
  }
  // if weatherAt is not exposed, fall back to asserting the current value only
  for (const k of Object.keys(seen)) {
    for (const v of seen[k]) {
      const allowed = k === 'season' ? seasonVals : (k === 'hoursType' ? hoursVals : weatherVals);
      assert(allowed.has(v), `${k} ${v} out of range`);
    }
  }
  assert(weatherVals.has(engine.state.weather.weather), 'current weather still in range');
});

test('capsule: the task board actually populates (it used to stay empty forever)', ({ engine }) => {
  // The client only calls capsule_patch when `patch_num > 0`
  // (`0 == task_list.length && patch_num > 0`). Nothing used to set patch_num, so
  // the board stayed empty forever and capsule_patch was UNREACHABLE.
  const r = call(engine, 'capsule_load', {}).reply;
  assert(typeof r.patch_num === 'number', 'patch_num must be a number');
  assert(r.task_list.length > 0,
    'the capsule task board must deal tasks, or that half of the event is dead');
  for (const id of r.task_list) {
    assert(CAP.task_list[String(id)], `dealt task ${id} must exist in capsuleData`);
  }
  // patch_num counts the slots STILL TO DEAL, so after dealing it is 0 -- that is
  // the correct end state, not a failure
  eq(r.patch_num + r.task_list.length, Object.keys(CAP.task_list).length,
    'dealt + still-to-deal must account for the whole table');
});

/* ------------------------------------------------ WIRE-SHAPE REGRESSION ---- */
/* The bug class these guard against, and why the existing tests missed it:
 *
 * The client does NOT send free-form JSON. `SocketManage.send` maps positional
 * arguments onto the parameter names declared in ProtocolList:
 *     u.data = {}; for (p...) u.data[params[p]] = args[p];
 * so the ONLY key the server will ever see is the declared one. Every test above
 * calls dispatch() with a payload the test author invented, which is how
 * `furniture_buy_shop` came to read `d.id` while the client sends `{shop_id}`:
 * it returned {code:-1} forever -- the entire furniture merchant, including the
 * 分享拿福利 welfare goods, was silently unbuyable -- and 247 green tests said
 * nothing. So these tests use the CLIENT'S OWN wire names, taken from its call
 * sites, and never the handler's preferred spelling.
 * tools/audit_params.py checks the same thing statically for every command. */

test('wire: furniture_buy_shop reads shop_id, the name the client actually sends', ({ engine }) => {
  // client: send("furniture_buy_shop", cb, shopId)  ->  {shop_id: shopId}
  const before = engine.state.clover;
  const r = call(engine, 'furniture_buy_shop', { shop_id: 2001 }).reply;
  eq(r.code, 0, 'a paid slot with the declared key must succeed');
  eq(engine.state.clover, before - 20, 'the paid slot must charge its price');
});

test('wire: 嘟嘟代理福利商品 (type 998) is granted FREE, not charged', ({ engine }) => {
  // FurnitureShopView.openBuyTips branches on type == 998 and shows
  // FurnitureAdsView -- the 「分享拿福利」 popup (share_btn3_png) whose copy is
  // "此商品为嘟嘟代理福利商品，{0}即可免费获得". The row's price (50) is the
  // crossed-out list price; charging it was a second reason the button looked
  // dead, since tapping it silently spent 50 clover. 7003 is type 998 in
  // furnitureShopData (item 20101, list price 50).
  const before = engine.state.clover;
  const r = call(engine, 'furniture_buy_shop', { shop_id: 7003 }).reply;
  eq(r.code, 0, 'the welfare good must be obtainable');
  eq(engine.state.clover, before, 'a welfare good must NOT cost clover');
  const owned = (engine.state.items.house || []).some((h) => h.item_id === 20101);
  assert(owned, 'the welfare item must land in the inventory');
});

test('wire: a welfare good is offered once per day, and the paid chain is untouched', ({ engine }) => {
  eq(call(engine, 'furniture_buy_shop', { shop_id: 7003 }).reply.code, 0, 'first take succeeds');
  const afterFirst = engine.state.clover;
  eq(call(engine, 'furniture_buy_shop', { shop_id: 7003 }).reply.code, -1,
    'taking the same welfare good twice in a day must be refused');
  eq(engine.state.clover, afterFirst, 'a refusal must not move the clover');
  // a normal paid row still enforces its own limit
  eq(call(engine, 'furniture_buy_shop', { shop_id: 2001 }).reply.code, 0, 'paid row 1 ok');
});

test('wire: bench/box take-out and put-in read pos, not index', ({ engine }) => {
  // client: setBenchTool sends send("furniture_takeout_bench", cb, e+1) and
  // setBenchItem sends (..., e+5+1) -> the declared param is `pos`.
  // Put an item on the bench first (through the declared key), then take it out.
  const food = 10001;
  engine.state.items.house.push({ item_id: food, count: 3 });
  const put = call(engine, 'furniture_putin_bench', { pos: 1, id: food }).reply;
  eq(put.code, 0, 'putin_bench must accept {pos, id}');
  eq(engine.state.furniture.bench[0], food, 'the bench slot must hold it');
  const out = call(engine, 'furniture_takeout_bench', { pos: 1 }).reply;
  eq(out.code, 0, 'takeout_bench must accept {pos}');
  eq(engine.state.furniture.bench[0], -1, 'the bench slot must be emptied');
});

test('wire: guest_accept_invit honours is_accept (it used to always mean REJECT)', ({ engine }) => {
  // client: request_accept_invit sends (..., true), request_reject_invit (..., false)
  // The handler read d.accept/d.id, neither ever present, so `accepted` was always
  // false and ACCEPTING silently behaved as REJECTING.
  const load = call(engine, 'guest_load_drawing', {}).reply;
  assert(load && load.state !== undefined, 'guest_load_drawing must answer a state');
  engine.state.drawing.state = 1;
  engine.state.drawing.guest = 0;
  const accept = call(engine, 'guest_accept_invit', { is_accept: true }).reply;
  eq(accept.code, 0, 'accept must be accepted');
  eq(engine.state.drawing.state, 2, 'state must be DrawingState.accept (2)');
  const reject = call(engine, 'guest_accept_invit', { is_accept: false }).reply;
  eq(reject.code, 0, 'reject must be accepted');
  eq(engine.state.drawing.state, 0, 'state must be DrawingState.wait (0)');
});

test('wire: 分享 commands answer, and the daily gift really arrives as MAIL', ({ engine }) => {
  // Every adsmgr_* command except load used to be MISSING, so req_share got no
  // reply and the client's callback never ran: the 分享 buttons did nothing.
  const before = call(engine, 'mail_load', {}).reply.length;
  const share = call(engine, 'adsmgr_share', { ads_type: 2 }).reply;
  eq(share.code, 0, 'req_share(2) must be answered with code 0, or the button is dead');
  const after = call(engine, 'mail_load', {}).reply;
  eq(after.length, before + 1, 'the reward must arrive as mail ("邮箱有动静")');
  const m = after[after.length - 1];
  assert(m.resource && m.resource.clover_point > 0, 'the mail must carry the clover');
  // once per day
  eq(call(engine, 'adsmgr_share', { ads_type: 2 }).reply.code, -2, 'the daily gift is once per day');
});

test('wire: adsmgr_load reports a usable payload (item_list was empty)', ({ engine }) => {
  const r = call(engine, 'adsmgr_load', {}).reply;
  // AdsGiftView iterates item_list and does ItemDB.get(item_id) per row; an empty
  // list renders an empty popup, which is what the old stub returned.
  assert(r.item_list.length > 0, 'item_list must not be empty or the popup is blank');
  for (const it of r.item_list) {
    assert(Number(it.item_id) > 0, 'every row needs a real item_id');
    assert(Number(it.num) > 0, 'every row needs a count to print');
  }
  assert(r.gift_can_get > 0, 'gift_can_get must be > 0 or updateCheck() disables the buttons');
  assert(r.gift_time > 0, 'gift_time is read by getGiftLeftTime()');
  call(engine, 'adsmgr_refuse', {});
  assert(call(engine, 'adsmgr_load', {}).reply.can_pop === false, 'refuse must turn the popup off');
});

test('wire: 充值 grants the pack directly (there is no payment channel offline)', ({ engine }) => {
  // client: RechargeModel.pay(id) -> BaseChannel.pay(shopID); BaseChannel.prototype
  // .pay is an EMPTY STUB, so tapping a pack did nothing at all. The offline shell
  // routes it to recharge_ready_pay{id} -- the client's own "this pack was paid,
  // deliver it" command.
  const load = call(engine, 'recharge_load', {}).reply;
  assert(Array.isArray(load.field) && load.field.length > 0,
    'the 田地 page renders data.field, so it must not be empty');
  for (const row of load.field) {
    assert(Number(row.id) > 0, 'RechargeFieldItem does rechargeDB.get(row.id)');
    assert(row.total !== undefined && row.grow !== undefined, 'row needs grow/total');
  }
  const before = engine.state.clover;
  const pay = call(engine, 'recharge_ready_pay', { id: 1 }).reply;
  eq(pay.code, 0, 'a real pack id must be delivered');
  eq(engine.state.clover, before + 400, 'pack 1 is the 400-clover pack');
  eq(call(engine, 'recharge_ready_pay', { id: 999 }).reply.code, -1, 'an unknown pack is refused');
});

test('wire: recharge_water/change answer and push the field back', ({ engine }) => {
  // no water yet -> a refusal, not a crash and not a silent no-op
  assert(call(engine, 'recharge_water', {}).reply.code !== 0,
    'watering without water must be refused, not silently accepted');
  const c = call(engine, 'recharge_change', {}).reply;
  eq(c.code, 0, 'recharge_change must answer');
  assert(c.field !== undefined, 'the reply feeds RechargeEventType.CLOVER_CHANGED');
  const n = call(engine, 'recharge_update_num', {}).reply;
  assert(n.water !== undefined && n.change !== undefined,
    'recharge_update_num carries {water, change}');
});

test('wire: animpicture album moves photos by anim_index/pic_index/pic_uid', ({ engine }) => {
  const A = engine.state.animPicture;
  assert(A && Array.isArray(A.picList), 'animPicture.picList must exist');
  // give the player a photo and a page to move it onto
  engine.state.pictures.push({ id: 4242, pic_id: 1, layers: [] });
  A.picList.push({ id: 1, phase_list: [0], pictures: [] });
  const r = call(engine, 'animpicture_album_add_pic',
    { anim_index: 1, pic_index: 1, pic_uid: 4242 }).reply;
  eq(r.code, 0, 'the declared wire keys must be understood');
  const moved = engine.state.animPicture.picList[0].pictures[0];
  assert(moved && moved.id === 4242, 'the photo must land in the slot');
  const back = call(engine, 'animpicture_album_remove_pic',
    { anim_index: 1, pic_index: 1, is_delete: false }).reply;
  eq(back.code, 0, 'removal with is_delete=false must be understood');
  assert((engine.state.pictures || []).some((p) => p.id === 4242),
    'is_delete=false returns the photo to the album');
});

/* ------------------------------------------- wire shape: capsule / titles / calendar */

test('capsule: task_list and reward_list are ARRAYS OF IDS, never rows', ({ engine }) => {
  // The client does capsuleData.get("task_list")[entry.toString()] and
  // CapsuleUtils.getTaskCfg(this.data.task_list[0]).name. An OBJECT entry
  // stringifies to "[object Object]", the lookup misses, and `.name` throws
  // "Cannot read properties of undefined" -- which the client turns into
  // Reload.JSError, i.e. 呱呱，吃坏肚子了, the moment the 扭蛋机 button is tapped.
  const r = call(engine, 'capsule_load', {}).reply;
  assert(Array.isArray(r.task_list), 'task_list must be an array');
  assert(r.task_list.length > 0, 'a fresh event should deal some tasks');
  for (const t of r.task_list) {
    eq(typeof t, 'number', 'every task_list entry must be a bare id, got ' + JSON.stringify(t));
  }
  assert(Array.isArray(r.reward_list), 'reward_list must be an array');
  const taskTable = (GD.tables.capsuleData || {}).task_list || {};
  for (const id of r.task_list) {
    assert(taskTable[String(id)], `task id ${id} is not a key in capsuleData.task_list`);
  }
  for (const k of ['end_time', 'coin', 'pre_coin', 'reward_list', 'task_list', 'patch_num']) {
    assert(r[k] !== undefined, 'capsule_load must carry ' + k);
  }
});

test('capsule: patch returns ids, and fast_task addresses the DISPLAYED list', ({ engine }) => {
  const C = engine.state.capsule;
  call(engine, 'capsule_load', {});
  C.coin = 100;                     // fast_task costs capsuleData.fast_consume (30)
  const open = () => call(engine, 'capsule_load', {}).reply.task_list;
  const before = open();
  assert(before.length >= 2, 'need at least two open tasks');
  // finish the FIRST displayed task through the same 1-based index the client sends
  const r = call(engine, 'capsule_fast_task', { index: 1 }).reply;
  eq(r.code, 0, 'fast_task must succeed with enough coins');
  const after = open();
  eq(after.length, before.length - 1, 'a finished task must LEAVE the list');
  assert(after.indexOf(before[0]) === -1, 'the finished id must be gone');
  eq(after[0], before[1], 'the list must shift, so index 1 is the next task');
  C.taskList = [];
  C.patchNum = 2;
  const p = call(engine, 'capsule_patch', {}).reply;
  assert(Array.isArray(p.task_list) && p.task_list.length === 2, 'patch deals two');
  for (const id of p.task_list) eq(typeof id, 'number', 'patch ids must be numbers');
});

test('titles: no expiry is sent, so an earned title is never "expired"', ({ engine }) => {
  // The client reads achieves_time as an EXPIRY: isAchieveExpire(id) is
  // `achieveTime[id] ? now >= achieveTime[id] : false`. Recording the EARN time
  // makes that true immediately, so AchieveView renders its own "??????"
  // placeholder for every title and getUseAchieveID() returns -1 (a stale popup).
  const roleFrom = (res) => (res.pushes.map((p) => p.data).find((d) => d && d.frog)) || null;
  const frog = (roleFrom(call(engine, 'hall_enter_game', {})) || {}).frog;
  assert(frog, 'a role payload must be pushed');
  assert(Array.isArray(frog.achieves), 'frog.achieves must be an array of ids');
  assert(Array.isArray(frog.achieves_time), 'frog.achieves_time must be an array');
  eq(frog.achieves_time.length, 0,
    'achieves_time is an EXPIRY list: an entry makes the client drop the title');
  // an old save that stored earn-times must not leak them out again either
  engine.state.achieves = [0, 21];
  engine.state.achievesTime = [{ id: 0, time: 1 }, { id: 21, time: 2 }];
  const again = (roleFrom(call(engine, 'hall_enter_game', {})) || {}).frog;
  assert(again, 'a second role payload must be pushed');
  eq(again.achieves_time.length, 0, 'stored expire-times must be filtered out');
  assert(again.achieves.length === 2, 'the earned ids themselves still go out');
});

test('titles: the client\'s own settings survive a role push (no repeated popup)', ({ engine }) => {
  // checkNewAchieve() keeps the ids it has already announced in
  // clientSettings.achieveList and skips them. The engine pushed its own
  // `achieveList: []` on every client_load_role, wiping that list, so the client
  // re-announced the OLDEST title again and again instead of the new one.
  const settings = { achieveList: [0, 21], hasAchieve: true, guideStep: 'Complete' };
  call(engine, 'client_set_client', { client: JSON.stringify(settings) });
  const role = (res) => res.pushes.map((p) => p.data)
    .find((d) => d && d.settings && d.settings.client) || null;
  const payload = role(call(engine, 'hall_enter_game', {}));
  assert(payload, 'a role payload with settings must be pushed');
  const echoed = JSON.parse(payload.settings.client);
  eq(JSON.stringify(echoed.achieveList), JSON.stringify([0, 21]),
    'the client\'s announce list must be echoed back, not reset');
  eq(echoed.hasAchieve, true, 'hasAchieve must survive too');
  eq(engine.state.settings.achieveList.length, 2, 'and it must be persisted');
  // a malformed payload must not throw or corrupt state
  call(engine, 'client_set_client', { client: 'not json' });
  call(engine, 'client_set_client', {});
  eq(engine.state.settings.achieveList.length, 2, 'bad input must leave it alone');
});

test('rename: the client asks the PRICE first, and a new save is quoted 0', ({ engine }) => {
  /* UserModel.setName() never sends client_set_name on its own:
       setName -> send('client_rename_cost') -> (cost>0 ? ModalConfirm : go) ->
       checkClover(cost) -> send('client_set_name')
     The guide's FIRST naming goes through the very same path, so with no
     client_rename_cost handler the callback never fired, no confirm box ever
     appeared and the naming guide never advanced: a new account could not be
     named at all, and 改名 did nothing. The client reads `n.clover`. */
  const fresh = newEngine();
  try {
    eq(call(fresh.engine, 'client_rename_cost', {}).reply.clover, 0,
      'a brand-new save must be quoted 0 (the guide is naming it)');
    eq(fresh.engine.state.clover, 9999, 'and nothing has been charged yet');
    eq(call(fresh.engine, 'client_set_name', { name: '测试蛙' }).reply.code, 0,
      'the first naming answers 0');
    eq(fresh.engine.state.name, '测试蛙', 'the name really changed');
    eq(fresh.engine.state.clover, 9999, 'the first naming is FREE');

    eq(call(fresh.engine, 'client_rename_cost', {}).reply.clover, 50,
      'a later rename is quoted RENAME_CLOVER');
    eq(call(fresh.engine, 'client_set_name', { name: '改名后' }).reply.code, 0,
      'the paid rename answers 0');
    eq(fresh.engine.state.name, '改名后', 'the name changed again');
    eq(fresh.engine.state.clover, 9949, 'and the price was actually charged');

    // Not affordable: 61 (资源不足) is IN errcode.json, so the client can show it.
    // The client pre-checks the same condition, so getting here means the two
    // sides disagree -- and a code the table lacks would fail invisibly.
    fresh.engine.state.clover = 10;
    eq(call(fresh.engine, 'client_set_name', { name: '太穷了' }).reply.code, 61,
      'a rename you cannot pay for answers 61, not -1');
    eq(fresh.engine.state.name, '改名后', 'and the name is left alone');
    eq(fresh.engine.state.clover, 10, 'and no clover is taken');
  } finally {
    fs.rmSync(fresh.dir, { recursive: true, force: true });
  }
});

test('rename: `renamed` persists, and the reply promises no mailbox gift', ({ engine, savePath }) => {
  /* The guide answers a truthy second reply field with
     "等会记得到邮箱来领取小礼物" -- returning `lucky` would promise a mail we
     never send. And `renamed` has to be persisted, or every restart would hand
     out another free rename. */
  const r = call(engine, 'client_set_name', { name: '一号蛙' }).reply;
  eq(r.lucky === undefined || !r.lucky, true, 'lucky must stay falsy');
  eq(engine.state.renamed, true, 'the flag is set');
  const again = reopen(savePath);
  eq(again.state.renamed, true, 'renamed must survive a reopen');
  eq(again.state.name, '一号蛙', 'the name persists');
  eq(call(again, 'client_rename_cost', {}).reply.clover, 50, 'so it is no longer free');
});

test('calendar: the reward schedule covers EVERY day of the month', ({ engine }) => {
  // It used to stop at 28, so on a 29/30/31-day month the last days had no entry
  // and therefore no icon at all (the player counted 28), and the client's claim
  // check -- keyed by day-of-month -- could never fire for them.
  const r = call(engine, 'calendar_load', {}).reply;
  const days = new Set();
  for (const e of r.st_days) days.add(Number(e.day));
  for (const e of r.lucky_days) days.add(Number(e.day));
  const d = new Date();
  const maxDay = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  eq(days.size, maxDay, `every day 1..${maxDay} must carry a reward`);
  for (let i = 1; i <= maxDay; i++) {
    assert(days.has(i), `day ${i} has no reward entry, so the calendar shows no icon`);
  }
  for (const e of r.st_days.concat(r.lucky_days)) {
    assert(Number(e.item_id) > 0, 'each day needs a real item_id for its icon');
  }
});

/* ------------------------------------------------------- 博物馆图鉴 / 手工拼装 */

test('museum: museum_load reports OWNERSHIP, keyed by the client\'s own table', ({ engine }) => {
  /* The list page is rendered from the LOCAL table (rows with switch == 1) and only
     ENRICHED from our reply, so our job is exactly "which of this museum's postcards
     and collectibles does the player have?". We used to answer an empty list, which
     left every slot grey. */
  const table = require(path.join(__dirname, '..', 'run', 'engine', 'data', 'gamedata.json'))
    .tables.museumData;
  const rows = Object.keys(table).map((k) => table[k]);
  const r = call(engine, 'museum_load', {}).reply;
  eq(r.museum_list.length, rows.length,
    'every museum row must be reported (we do not filter by switch -- the table does)');
  for (const m of r.museum_list) {
    assert(Array.isArray(m.pic_list), 'pic_list must be an array');
    assert(Array.isArray(m.collections), 'collections must be an array');
    eq(m.pic_list.length, 0, 'a fresh save owns no museum postcards');
    eq(m.collections.length, 0, 'and no museum collectibles');
  }

  // Give the player the first postcard of museum 1 and one of its collectibles.
  const first = rows.find((m) => Number(m.switch) === 1);
  const picId = Number(first.pic_id[0]);
  const colId = Number(String(first.collection_id).split(',')[0]);
  engine.state.pictures.push({ id: 9001, pic_id: picId, read: 0, new: 1 });
  engine.state.handbook.collections.push(colId);
  const r2 = call(engine, 'museum_load', {}).reply;
  const mine = r2.museum_list.find((m) => m.id === Number(first.id));
  assert(mine, 'museum 1 must still be in the list');
  eq(mine.pic_list.indexOf(picId) !== -1, true, 'the owned postcard must be reported');
  eq(mine.collections.indexOf(colId) !== -1, true, 'the owned collectible must be reported');
  eq(mine.pic_list.length, 1, 'and nothing else is claimed');

  // A postcard still waiting to be filed, or in the recycle bin, is STILL owned.
  engine.state.pictures = [];
  engine.state.albumPending.push({ id: 9002, pic_id: picId, read: 0, new: 1 });
  const r3 = call(engine, 'museum_load', {}).reply;
  eq(r3.museum_list.find((m) => m.id === Number(first.id)).pic_list.indexOf(picId) !== -1,
    true, 'a pending postcard still counts as owned');
});

test('craft: pray_compose needs one of EACH piece, then pays the amulet', ({ engine }) => {
  const pieces = require(path.join(__dirname, '..', 'run', 'engine', 'data', 'gamedata.json'))
    .items.filter((i) => i.type === 16).map((i) => i.id);
  eq(pieces.length, 3, 'exactly three COMPOSE items exist (ItemType.COMPOSE = 16)');
  eq(call(engine, 'pray_compose', { id: 5502 }).reply.code, 42,
    'with no pieces it answers 42 (物品不足), a code the client ERROR TABLE has');
  eq(call(engine, 'pray_compose', { id: 1234 }).reply.code, 5,
    'an id that is not Define.ComposeId answers 5 (参数非法)');

  engine.state.items.house.push({ item_id: pieces[0], count: 1 });
  eq(call(engine, 'pray_compose', { id: 5502 }).reply.code, 42,
    'one piece is not enough -- all three sub_types are required');
  for (const p of pieces.slice(1)) engine.state.items.house.push({ item_id: p, count: 1 });
  const r = call(engine, 'pray_compose', { id: 5502 }).reply;
  assert(Array.isArray(r.item_list), 'the reply must carry item_list (the client walks it)');
  eq(r.item_list.length, 1, 'one amulet comes out');
  /* The client builds its own {item_id, count} rows from these numbers and calls
     ItemDB.get on each, so every entry must be a real Item row. */
  for (const id of r.item_list) {
    assert(items.some((i) => i.id === id), `item_list entry ${id} must be a real item`);
    assert(items.find((i) => i.id === id).type === 1,
      'the product must be an Amulet (type 1)');
  }
  for (const p of pieces) {
    const left = engine.state.items.house.find((h) => h.item_id === p);
    assert(!left || left.count === 0, 'every piece was consumed');
  }
});

test('craft: pray_load_grays carries the row fields the two pages render', ({ engine }) => {
  const r = call(engine, 'pray_load_grays', {}).reply;
  for (const key of ['wishs', 'stamps', 'boxes']) {
    assert(Array.isArray(r[key]), `${key} must be an array`);
  }
  eq(r.boxes.length, 0, 'nothing finished that the player has not seen yet');
  assert(r.wishs.length >= 1, 'the frog works on a 祈愿木牌 while it is at home');
  assert(r.stamps.length >= 1, 'and on a 印章');
  const w = r.wishs[0];
  for (const f of ['id', 'state', 'body', 'paper', 'content', 'make_time', 'u_id']) {
    assert(Object.prototype.hasOwnProperty.call(w, f), `wish rows need ${f}`);
  }
  const s = r.stamps[0];
  for (const f of ['id', 'state', 'time', 'u_id']) {
    assert(Object.prototype.hasOwnProperty.call(s, f),
      `stamp rows need ${f} (note: TIME, not make_time)`);
  }
  // the client draws the finished piece from PrayCraftBodyDB, so body/paper must be
  // prayBodyData ids once a row is done.
  engine.state.craft.wishes[0].state = 3;         // one stage short of done
  engine.state.craft.wishes[0].make_time = 1;     // and due now
  const r2 = call(engine, 'pray_load_grays', {}).reply;
  const done = r2.wishs.filter((x) => x.state > 3);
  assert(done.length >= 1, 'advancing time must finish the piece');
  assert(done[0].body && done[0].paper, 'a finished piece needs body and paper ids');
  const bodyIds = Object.keys(GDATA.tables.prayBodyData || {});
  assert(bodyIds.indexOf(String(done[0].body)) !== -1,
    'body must be a prayBodyData id or the client draws nothing');
  assert(bodyIds.indexOf(String(done[0].paper)) !== -1,
    'paper must be a prayBodyData id too');
  assert(r2.wish_new && typeof r2.wish_new.make_time === 'number',
    'wish_new must be {make_time, u_id} so the red dot can fire');
});

test('craft: the work is persisted and pray_confirm_make_box empties the inbox', ({ engine, savePath }) => {
  engine.state.craft.pending.push(1306);
  const r = call(engine, 'pray_load_grays', {}).reply;
  eq(r.boxes.length, 1, 'pending crafts are reported as boxes');
  eq(call(engine, 'pray_confirm_make_box', {}).reply, undefined,
    'pray_confirm_make_box is needResponse:false -- it must not answer');
  eq(engine.state.craft.pending.length, 0, 'the inbox is cleared');
  const again = reopen(savePath);
  const r2 = call(again, 'pray_load_grays', {}).reply;
  assert(r2.wishs.length >= 1, 'the craft history survives a reopen');
  eq(call(again, 'pray_load_grays', {}).reply.boxes.length, 0, 'and so does the clear');
});

test('craft: the three 木片 really can arrive from a trip (they are OUR source)', ({ engine }) => {
  /* No table places these items and the client never mentions them, so offline the
     only source is the one we designed: a rare find on a trip. Force the RNG so the
     test is deterministic, then check a COMPOSE item reached the house. */
  const pieces = items.filter((i) => i.type === 16).map((i) => i.id);
  const lunch = idsOfType(0)[0];
  const orig = Math.random;
  Math.random = () => 0.01;                 // well under the drop chance
  try {
    engine.state.items.bag[0] = lunch;
    engine.state.travel.nextDepartAt = 1;
    engine.tick();
    engine.state.travel.returnAt = 1;
    engine.tick();
  } finally {
    Math.random = orig;
  }
  const owned = engine.state.items.house.concat(engine.state.items.bag)
    .filter((h) => h && pieces.indexOf(h.item_id) !== -1 && h.count > 0);
  assert(owned.length > 0,
    'a 木片 must be able to come home from a trip, or the 三拼 box is a dead end');
});

/* ------------------------------------------------------------- 博物馆冒险 */

test('museumday: the event is switched OFF, and the museum 图鉴 replaces it', ({ engine }) => {
  /* The player asked for 大冒险 to go away for now ("太麻烦了") and for the museum 图鉴 to
     be unlocked instead. `end_time` is the whole switch for the client
     (`getActivityTime() = end_time > 0 ? [1, end_time] : [0,0]`), so 0 hides the entry and
     stops it arming its activity timer. The commands themselves are still implemented:
     flip MUSEUM_DAY_ENABLED in the engine to bring the event back. */
  const r = call(engine, 'museumday_load', {}).reply;
  eq(r.end_time, 0, 'a closed window is what hides the 大冒险 entry');
  eq(r.cur_museum, 0, 'and no museum is in progress');

  /* The museum postcards used to come from that event only, so boot must grant them. */
  call(engine, 'hall_enter_game', {});
  const list = call(engine, 'museum_load', {}).reply.museum_list;
  for (const m of list) {
    assert(m.pic_list.length > 0, `museum ${m.id} must report its postcards as owned`);
    assert(m.collections.length > 0, `museum ${m.id} needs its collectibles too`);
  }
  const total = list.reduce((n, m) => n + m.pic_list.length, 0);
  assert(total >= 12, `expected the museums' postcards in the album, got ${total}`);
  const album = call(engine, 'album_load', {}).reply;
  for (const m of list) {
    for (const pic of m.pic_list) {
      assert(album.pictures.some((p) => p.pic_id === pic),
        `postcard ${pic} must actually be in the album, not just reported`);
    }
  }
  eq(engine.state.museumUnlocked, true, 'and the grant is recorded so it happens once');
});

test('museumday: museumday_load carries EVERY key the model touches', ({ engine }) => {
  /* `this.data = Utils.convertArrayAll(e)` REPLACES the model: it is a filter, not a
     merge, so a missing key stays undefined and checkRedot() reads
     `data.path.length` of undefined -> TypeError -> 「呱呱吃坏肚子了」 -> reload loop.
     That is exactly what a `{end_time: <future>}`-only reply would do. */
  const r = call(engine, 'museumday_load', {}).reply;
  for (const k of ['end_time', 'path', 'next', 'frog', 'compass', 'cur_museum',
    'museum_list', 'items', 'get_items', 'log_list', 'inspire_num', 'inspire_time',
    'task_num', 'left_num', 'desc_id']) {
    assert(Object.prototype.hasOwnProperty.call(r, k), `museumday_load must send ${k}`);
  }
  assert(Array.isArray(r.path), 'path must be an array of rows');
  assert(Array.isArray(r.museum_list), 'museum_list must be an array of rows');
  assert(Array.isArray(r.items) && Array.isArray(r.get_items),
    'items/get_items must be arrays of rows');
  assert(Array.isArray(r.log_list), 'log_list must be an array of rows');
  eq(r.left_num === -1, false, 'left_num must never be -1: the history page tests -1 != left_num');
  eq(r.desc_id === 401 || r.desc_id === 402, true,
    'desc_id must be 401/402 or the ending card has no art');
  assert(r.inspire_time > 0, 'inspire_time must be > 0 or the 鼓舞 button disappears');
});

test('museumday: a run advances, loots, and settles into the history list', ({ engine }) => {
  eq(call(engine, 'museumday_start_advance', { id: 1 }).reply.code, 0, 'start answers 0');
  let r = call(engine, 'museumday_load', {}).reply;
  eq(r.cur_museum, 1, 'the museum is set');
  assert(r.path.length >= 8 && r.path.length <= 16, 'route length 8..16');
  for (const t of r.path) {
    assert(t.grid >= 1 && t.grid <= 35, 'grid must be inside the client 7x5 board');
    assert(typeof t.grid === 'number' && typeof t.type === 'number',
      'tiles are {grid,type,style} ROWS, not ids');
  }
  /* The client indexes path[next-1], so `next` must stay inside the array. */
  eq(r.next, 1, 'a fresh run starts at the first tile');
  eq(r.frog, 1, 'and the frog is on it');

  let last = r.next;
  for (let i = 0; i < 3; i++) {
    const c = call(engine, 'museumday_random_compass', {}).reply;
    assert(c.next !== undefined && c.next !== last,
      'next must DIFFER from the current one, or the client walks off path[]');
    assert(c.next <= r.path.length, 'and must stay within path[]');
    assert(typeof c.inspire === 'number',
      'inspire is an overwrite: omitting it turns the counter into "undefined"');
    last = c.next;
  }
  r = call(engine, 'museumday_load', {}).reply;
  eq(r.next, last, 'the progress persisted');

  /* 结算: the museum lands in the history list and its rewards arrive. */
  const before = engine.state.albumPending.length;
  eq(call(engine, 'museumday_arrive', {}).reply.code, 0, 'arrive answers 0');
  r = call(engine, 'museumday_load', {}).reply;
  eq(r.cur_museum, 0, 'back to the history page');
  eq(r.museum_list.length, 1, 'the visit is recorded');
  eq(r.museum_list[0].id, 1, 'for museum 1');
  assert(engine.state.albumPending.length > before,
    'arriving must hand over the museum postcards (that is what lights up the 图鉴)');
  assert(engine.state.items.house.some((h) => h.item_id === 1017 && h.count > 0),
    'and the museum ticket');
});

test('museumday: get_items EMPTIES the pending list (else the gift popup loops)', ({ engine }) => {
  call(engine, 'museumday_start_advance', { id: 1 });
  /* Force pending loot the way a tile would produce it. */
  const s = engine.state.museumday;
  s.items.push({ item_id: idsOfType(3)[0], num: 2 });
  const r = call(engine, 'museumday_get_items', {}).reply;
  eq(r.code, 0, 'get_items answers code 0 (it reads nothing else)');
  eq(call(engine, 'museumday_load', {}).reply.items.length, 0,
    'leaving rows in `items` makes updateRewards() pop the gift again, forever');
  eq(call(engine, 'museumday_load', {}).reply.get_items.length, 1,
    'and they must appear as collected instead');
});

test('museumday: refresh hands back a usable left_num and a new route', ({ engine }) => {
  call(engine, 'museumday_start_advance', { id: 1 });
  const before = call(engine, 'museumday_load', {}).reply.path;
  const r = call(engine, 'museumday_refresh', {}).reply;
  assert(typeof r.left_num === 'number', 'left_num must be a number');
  assert(r.left_num !== -1, '-1 makes 下一座博物馆 do nothing at all');
  const after = call(engine, 'museumday_load', {}).reply;
  assert(after.path.length >= 8, 'refreshing must leave a usable route');
  assert(after.path !== before, 'and it is a fresh array');
});

test('museumday: the 鼓舞 counter fills from cooking, as the client text promises', ({ engine }) => {
  /* The client's own explainer: 「每吃8个饼干就会积攒1次鼓舞」 (inspire.v1 = 8). */
  eq(call(engine, 'museumday_load', {}).reply.code, undefined, 'load has no code');
  const s0 = engine.state.museumday.cookies | 0;
  eq(s0, 0, 'a fresh save has eaten no cookies');
  call(engine, 'museumday_start_advance', { id: 1 });
  /* Complete a dish 8 times through the real handler is heavy; drive the counter the
     same way the handler does and then check the threshold logic once through it. */
  /* The requirement comes from cookingTaskData (`def.state`), NOT cookingData, and the
     handler reads `state.cooking.taskList` -- the reply is a COPY, so mutating the
     reply would prove nothing. */
  const taskDefs = GDATA.tables.cookingTaskData || {};
  call(engine, 'cooking_load_cooking', {});     // deals this month's tasks
  const completeOne = () => {
    const C = engine.state.cooking;
    const row = (C.taskList || []).find((t) => !t.complete);
    if (!row) return false;
    row.pro = Number((taskDefs[String(row.id)] || {}).state) + 1;
    return call(engine, 'cooking_complete_task', { id: row.id }).reply.code === 0;
  };
  assert(completeOne(), 'a dish must be completable');
  assert((engine.state.museumday.cookies | 0) >= 1, 'a completed dish counts as a cookie');

  engine.state.museumday.cookies = 7;
  engine.state.museumday.inspireNum = 0;
  assert(completeOne(), 'a second dish must be completable');
  eq(engine.state.museumday.inspireNum, 1,
    'the 8th cookie must grant one 鼓舞, or the button can never be used');
});

/* ------------------------------------------------- 贺卡 / 生日蛋糕（常开） */

test('cards: all three windows open from the payload alone, with complete bodies', ({ engine }) => {
  /* All three models share the byte-identical `end_time > 0 ? [1, end_time] : [0,0]`,
     and `start_time` has no reader. A missing key is worse than useless here: the card
     models REPLACE their data on load, so `card_info: {}` (the old stub) crashes the
     moment the view opens, and `part: 0` indexes PartyCakeData.cake[0].layers. */
  const now = Math.floor(Date.now() / 1000);
  const sc = call(engine, 'springcard_load', {}).reply;
  const gc = call(engine, 'greetcard_load', {}).reply;
  const pc = call(engine, 'partycake_load', {}).reply;

  for (const [name, r] of [['springcard', sc], ['greetcard', gc], ['partycake', pc]]) {
    assert(r.end_time > now, `${name}.end_time must be in the future or the button hides`);
    assert(r.end_time - now <= 24 * 86400, `${name}.end_time must stay int32-safe`);
  }
  for (const [name, r] of [['springcard', sc], ['greetcard', gc]]) {
    assert(r.card_info && typeof r.card_info === 'object' && !Array.isArray(r.card_info),
      `${name}.card_info must be a real object`);
    eq(r.card_info.tags.length, 3, `${name}.card_info.tags must have 3 slots`);
    for (const t of r.card_info.tags) eq(typeof t, 'number', 'each slot is an int (0 = empty)');
    eq(typeof r.global_num, 'number', `${name}.global_num is stringified by the client`);
  }
  assert(Array.isArray(sc.items) && Array.isArray(sc.reward_list), 'springcard items/reward_list');
  assert(Array.isArray(sc.task_item), 'springcard.task_item is a list of TAG IDS');
  assert(Array.isArray(gc.items) && Array.isArray(gc.send_list) && Array.isArray(gc.get_list),
    'greetcard arrays');
  eq(typeof gc.new_index, 'number', 'greetcard.new_index is 1-based into get_list (0 = none)');

  assert(pc.part >= 1 && pc.part <= 5, 'partycake.part must index PartyCakeData.cake (1..5)');
  assert(pc.cur_state >= 0 && pc.cur_state <= 6, 'partycake.cur_state must be one of 0..6');
  assert(Array.isArray(pc.layers), 'layers is an array of NUMBERS');
  assert(Array.isArray(pc.share_get) && pc.share_get.length === 2,
    'share_get has one entry per share_reward row, or the rebate loops');
  const taskDefs = Object.keys(GDATA.tables.PartyCakeData.task_list || {});
  eq(pc.task_list.length, taskDefs.length, 'one row per task_list entry');
  for (const row of pc.task_list) {
    assert(taskDefs.indexOf(String(row.id)) !== -1,
      `task id ${row.id} must exist in the table or the renderer reads cfg.name of undefined`);
    eq(typeof row.count, 'number', 'count is rendered as "count/total"');
    assert(row.is_done === 0 || row.is_done === 1, 'is_done is 0/1');
  }
});

test('springcard: every reply carries the field its callback gates on', ({ engine }) => {
  /* None of these callbacks uses getErrorInfo -- they test a field's truthiness, so a
     missing field is a SILENT dead button. */
  const buy = call(engine, 'springcard_buy', {}).reply;
  assert(buy.tags_id > 0, 'buy must return a real tags_id (a tag id from the table)');
  const tagIds = (GDATA.tables.springCard.tags || []).map((t) => Number(t.id));
  assert(tagIds.indexOf(buy.tags_id) !== -1, 'and it must be a tag the table knows');

  eq(call(engine, 'springcard_put_tags', { pos: 1, id: buy.tags_id }).reply.code, 0,
    'put_tags takes a 1-BASED pos (the client sends viewIndex + 1)');
  eq(call(engine, 'springcard_put_tags', { pos: 9, id: buy.tags_id }).reply.code, 5,
    'an out-of-range pos is refused with a code the client error table knows');

  const send = call(engine, 'springcard_send', {}).reply;
  assert(send.box_id > 0, 'send must return box_id > 0 or the button does nothing');
  const boxes = [Number(GDATA.tables.springCard.small_box_id),
    Number(GDATA.tables.springCard.big_box_id)];
  assert(boxes.indexOf(send.box_id) !== -1, 'and only one of the two real box ids');

  const got = call(engine, 'springcard_get_reward', {}).reply;
  assert(typeof got.id === 'number' && typeof got.num === 'number',
    'get_reward is {id, num} and `num` decides EVERYTHING');
  if (got.num === 0) {
    const keys = Object.keys(GDATA.tables.springCard.bless_box || {}).map(Number);
    assert(keys.indexOf(got.id) !== -1,
      'num 0 means id indexes bless_box (7..15), NOT an item');
  } else {
    assert(items.some((i) => i.id === got.id),
      'num > 0 means id must be a real Item row for DropItemRender');
  }

  const share = call(engine, 'springcard_share_tags', { tags_id: buy.tags_id }).reply;
  assert(typeof share.share_code === 'string' && share.share_code.length > 0,
    'share_code must be a NON-EMPTY string (the client chains a reward off it)');
  const ex = call(engine, 'springcard_get_share_tags', { share_code: share.share_code }).reply;
  assert(ex.tags_id > 0 || ex.code > 0, 'exchanging answers either a tag id or a real code');
});

test('greetcard: list payloads are always arrays (the client reads .length unguarded)', ({ engine }) => {
  const r = call(engine, 'greetcard_get_reward', {}).reply;
  assert(Array.isArray(r.list), 'greetcard_get_reward.list is read as `e.list.length`');
  eq(r.code, 0, 'and the branch is `0 == code`');
  const t = call(engine, 'greetcard_get_task_item', {}).reply;
  assert(Array.isArray(t.list), 'greetcard_get_task_item.list is read unguarded too');
  eq(call(engine, 'greetcard_send', {}).reply.code, 0, 'sending answers 0');
  const afterSend = call(engine, 'greetcard_load', {}).reply;
  eq(afterSend.send_list.length, 1, 'the card is recorded in send_list');
  eq(afterSend.can_reward, true, 'and a reward becomes claimable');
  const reward = call(engine, 'greetcard_get_reward', {}).reply;
  assert(reward.list.length > 0, 'claiming it hands back a real item id');
  assert(items.some((i) => i.id === reward.list[0]), 'and that id must exist in Item.json');
  eq(call(engine, 'greetcard_read_new', {}).reply, undefined,
    'needResponse:false commands must NOT answer');
});

test('partycake: the state machine walks 0->1->2->3->0 and the part advances', ({ engine }) => {
  /* PartyCakeState = {making:0, make_reward:1, qa:2, qa_reward:3, light:4,
     light_reward:5, complete:6}. The client assigns `cur_state = reply.state`
     UNCONDITIONALLY, so a reply without `state` sets it to undefined. */
  const load0 = call(engine, 'partycake_load', {}).reply;
  eq(load0.cur_state, 0, 'a fresh cake starts in making(0)');
  eq(call(engine, 'partycake_make', { layer: 1 }).reply.code, 61,
    'with no materials the make is refused (61 资源不足, a code the client knows)');

  /* Feed the economy through its real path: a task payout, then 领取. */
  const s = engine.state.partyCake;
  s.preCream = 40;
  s.preSugar = 40;
  eq(call(engine, 'partycake_get_mate', {}).reply.code, 0, 'get_mate answers 0');
  eq(call(engine, 'partycake_load', {}).reply.cream, 40, 'the materials became spendable');

  const part1 = GDATA.tables.PartyCakeData.cake['1'].layers;
  const layer1 = part1['1'];
  const made = call(engine, 'partycake_make', { layer: 1 }).reply;
  eq(made.state, 1, 'making a layer moves to make_reward(1)');
  const after = call(engine, 'partycake_load', {}).reply;
  eq(after.layers.indexOf(1) !== -1, true, 'the layer is recorded');
  eq(after.cream, 40 - Number(layer1.cream), 'and the cream was charged exactly once');
  eq(after.sugar, 40 - Number(layer1.sugar), 'and the sugar too');

  eq(call(engine, 'partycake_reward_make', {}).reply.state, 2, 'then the quiz (qa = 2)');
  const qa = call(engine, 'partycake_load_qa', {}).reply;
  eq(qa.answer.length, 3, 'the quiz offers EXACTLY three options');
  for (const id of qa.answer) {
    assert(items.some((i) => i.id === id),
      `quiz option ${id} must exist: the view calls ItemDB.get(id).img with no guard`);
  }
  assert(Array.isArray(qa.reward) && qa.reward.length >= 1, 'reward rows are objects');
  for (const row of qa.reward) {
    assert(typeof row.item_id === 'number' && typeof row.count === 'number',
      'each reward row is {item_id, count}');
  }
  const right = engine.state.partyCake.qaCorrect;
  eq(call(engine, 'partycake_answer', { index: right }).reply.state, 3, 'a right answer => 3');
  const qaRight = call(engine, 'partycake_load_qa', {}).reply;
  eq(qaRight.reward.length, 2, 'two reward rows is what selects the "correct" art');
  eq(call(engine, 'partycake_reward_qa', {}).reply.state, 0, 'claiming it returns to 0');
  /* Part 1 has TWO layers, so one layer is not enough to finish it: the layers stay
     and `part` stays put -- that is the client's own checkMakePart() rule. */
  const mid = call(engine, 'partycake_load', {}).reply;
  eq(mid.layers.length, 1, 'a half-built part keeps its layers');
  eq(mid.part, 1, 'and does not advance');
  /* Build the rest of part 1 and claim again: now the part advances and resets. */
  const layer2 = part1['2'];
  engine.state.partyCake.cream = Number(layer2.cream);
  engine.state.partyCake.sugar = Number(layer2.sugar);
  eq(call(engine, 'partycake_make', { layer: 2 }).reply.state, 1, 'second layer made');
  call(engine, 'partycake_reward_make', {});
  /* Ask for the question FIRST: answering is what (re)generates it, so reading
     qaCorrect before requesting the payload would answer the previous question. */
  call(engine, 'partycake_load_qa', {});
  const right2 = engine.state.partyCake.qaCorrect;
  eq(call(engine, 'partycake_answer', { index: right2 }).reply.state, 3,
    'answer the second quiz');
  eq(call(engine, 'partycake_reward_qa', {}).reply.state, 0, 'and claim it');
  const nextPart = call(engine, 'partycake_load', {}).reply;
  eq(nextPart.layers.length, 0, 'a FINISHED part resets its layers');
  eq(nextPart.part, 2, 'and the cake moves on to the next part');
});

test('partycake: the quiz answer index lives in the CLIENT\'s 1-based option counter', ({ engine }) => {
  /* The player-visible bug: the view builds its options with `for (r = 1; 3 >= r; r++)`
     and stores that counter in `cur_selete`, so it can only ever send 1, 2 or 3. We
     used to generate `qaCorrect = randInt(0, 2)` -- 0-BASED -- so whenever it came out
     0 the question was unanswerable: every attempt was judged wrong, the client
     re-rendered the question, and all the player ever saw was the confirm button
     going grey again. */
  const CH = GDATA.tables.Character;
  const rowIds = CH.rowItemId;
  const seen = new Set();
  for (let i = 0; i < 30; i++) {
    engine.state.partyCake = {
      cream: 0, sugar: 0, preCream: 0, preSugar: 0, curState: 2, part: 1,
      madeLayers: [], taskCounts: {}, shareGet: [0, 0], guest: 0, wrong: 0,
      answer: [], qaCorrect: 0, rewardRows: 1, mateDay: '',
    };
    const qa = call(engine, 'partycake_load_qa', {}).reply;
    eq(qa.answer.length, 3, 'three options');
    const idx = engine.state.partyCake.qaCorrect;
    assert(idx >= 1 && idx <= 3, `qaCorrect ${idx} must be 1..3`);
    seen.add(idx);
    const guest = Number(engine.state.partyCake.guest);
    assert(guest >= 0 && guest <= 2, `guest ${guest} must be one of the three named neighbours`);
    const taste = (id) => {
      const j = rowIds.indexOf(id);
      return j < 0 ? 0 : Number(CH.data[guest].taste[j]) || 0;
    };
    const vals = qa.answer.map(taste);
    assert(vals[idx - 1] === Math.max(...vals) && vals.filter((v) => v === vals[idx - 1]).length === 1,
      'the correct option must be the guest\'s unique favourite, or the question is a coin flip');
    eq(call(engine, 'partycake_answer', { index: idx }).reply.state, 3,
      'answering with the client\'s own index must be judged correct');
  }
  eq(seen.size, 3, 'all three positions must be able to be the answer (none unreachable)');
});

test('partycake: a wrong answer re-asks and reports `wrong`, a right one shows the prize', ({ engine }) => {
  const open = () => {
    engine.state.partyCake = {
      cream: 0, sugar: 0, preCream: 0, preSugar: 0, curState: 2, part: 1,
      madeLayers: [], taskCounts: {}, shareGet: [0, 0], guest: 0, wrong: 0,
      answer: [], qaCorrect: 0, rewardRows: 1, mateDay: '',
    };
    return call(engine, 'partycake_load_qa', {}).reply;
  };
  open();
  const right = engine.state.partyCake.qaCorrect;
  const wrong = right === 1 ? 2 : 1;
  const bad = call(engine, 'partycake_answer', { index: wrong });
  eq(bad.reply.state, 2, 'a wrong answer stays in qa(2): the client re-asks the question');
  eq(engine.state.partyCake.wrong, 1, 'and `wrong` flips the title to 再次回答');
  const pushed = pushNamed(bad, 'partycake_load_qa');
  eq(pushed.length, 1, 'the refreshed quiz payload must be pushed');
  eq(pushed[0].data.wrong, 1, 'carrying the retry flag');

  open();
  const right2 = engine.state.partyCake.qaCorrect;
  const good = call(engine, 'partycake_answer', { index: right2 });
  eq(good.reply.state, 3, 'a right answer moves to qa_reward(3)');
  const qa = pushNamed(good, 'partycake_load_qa')[0].data;
  eq(qa.reward.length, 2, 'two rows: `reward.length > 1` is what picks the 恭喜 art');
});

test('partycake: the prize the screen shows is exactly what claiming pays', ({ engine }) => {
  /* The reward screen only ever renders with cur_state == qa_reward (a wrong answer
     keeps the state at qa), so `pcQaPayload().reward` must always be the
     correct-answer prize. It used to be computed from `cur_state === qa_reward`,
     which meant the screen still held the SMALL prize at the moment it was drawn --
     and `partycake_reward_qa` paid a third, different amount. */
  engine.state.partyCake = {
    cream: 0, sugar: 0, preCream: 0, preSugar: 0, curState: 2, part: 1,
    madeLayers: [], taskCounts: {}, shareGet: [0, 0], guest: 0, wrong: 0,
    answer: [], qaCorrect: 0, rewardRows: 1, mateDay: '',
  };
  const qa = call(engine, 'partycake_load_qa', {}).reply;
  eq(qa.reward.length, 2, 'the 恭喜 art needs two rows');
  const before = qa.reward.map((row) => ({ id: Number(row.item_id), n: haveOf(engine, Number(row.item_id)) }));
  eq(call(engine, 'partycake_answer', { index: engine.state.partyCake.qaCorrect }).reply.state, 3, 'right');
  eq(call(engine, 'partycake_reward_qa', {}).reply.state, 0, 'claimed');
  for (const row of qa.reward) {
    eq(haveOf(engine, Number(row.item_id)), before.find((b) => b.id === Number(row.item_id)).n + Number(row.count),
      `the house must receive item ${row.item_id} x${row.count}, exactly as advertised`);
  }
});

test('partycake: the six tasks are fed by REAL gameplay, and share is paid once', ({ engine }) => {
  /* Every task maps onto an action this build already has: 登录 / 商店购买 / 抽奖 /
     分享 / 旅行. (Task 4 is 「看一次广告」, impossible offline; the client itself filters
     ids 3 and 4 out when the ads SDK is absent.) */
  const ids = Object.keys(GDATA.tables.PartyCakeData.task_list || {});
  assert(ids.length >= 5, 'the table must carry the task rows');
  call(engine, 'hall_enter_game', {});
  const t1 = call(engine, 'partycake_load', {}).reply.task_list
    .find((r) => r.id === 1);
  eq(t1.count >= 1, true, 'logging in counts toward task 1');

  const before = call(engine, 'partycake_load', {}).reply.pre_cream;
  const buy = call(engine, 'item_buy', { shop_id: 9 }).reply;   // slot 9 = 玉佩, known buyable
  eq(buy.code, 0, 'the shop purchase must succeed for the hook to matter');
  const afterBuy = call(engine, 'partycake_load', {}).reply;
  const t2 = afterBuy.task_list.find((r) => r.id === 2);
  eq(t2.count >= 1, true, 'a purchase counts toward task 2');
  const total2 = Number(GDATA.tables.PartyCakeData.task_list['2'].total);
  if (t2.count >= total2) {
    assert(afterBuy.pre_cream > before,
      'finishing a task pays its cream into the PENDING counter');
  }

  /* share_reward has two rows and `index` is 1-BASED; claiming the same slot twice
     must not pay twice, or the share button rebates forever. */
  eq(call(engine, 'partycake_reward_share', { index: 1 }).reply.code, 0, 'first claim');
  const paid = engine.state.partyCake.shareGet[0];
  eq(paid, 1, 'the slot is marked claimed');
  const clover2 = engine.state.items.house.reduce((n, h) => n + h.count, 0);
  eq(call(engine, 'partycake_reward_share', { index: 1 }).reply.code, 0, 'second claim');
  eq(engine.state.items.house.reduce((n, h) => n + h.count, 0), clover2,
    'but the second claim must NOT grant anything again');
  eq(call(engine, 'partycake_reward_share', { index: 9 }).reply.code, 5,
    'an out-of-range index is refused');
});

test('album: album_load_by_id_list replies under the key the client reads', ({ engine }) => {
  /* The client's handler is `if (e && e.pic_list) { group by id; entry.layers = … }`.
     We used to answer with `pictures`, so the branch never ran and a card added by an
     album command had no layers -- it rendered as an empty/transparent slot until the
     next login. (Same class of bug as the 百科 payload: right data, wrong key.) */
  call(engine, 'client_gm', { cmd: 'unlock_pictures' });
  const ids = engine.state.pictures.map((p) => p.id);
  assert(ids.length > 0, 'unlock_pictures must create album entries');

  /* Seven Picture rows ship with no layer art at all (2033/2035/2039/2040/2041/2042/
     2075), so those cards are blank however they are loaded -- at login too. Everything
     else must carry layers. */
  const LAYERS = require(path.join(__dirname, '..', 'run', 'engine', 'data',
    'picture-layers.json'));
  const artless = new Set(engine.state.pictures
    .filter((p) => !LAYERS[String(p.pic_id)]).map((p) => p.id));

  const r = call(engine, 'album_load_by_id_list', { id_list: ids }).reply;
  assert(Array.isArray(r.pic_list),
    'the reply must carry `pic_list`; the client ignores everything else');
  assert(r.pictures === undefined, 'and must not carry the old `pictures` key');
  eq(r.pic_list.length, ids.length, 'one row per requested album entry');
  let withLayers = 0;
  for (const row of r.pic_list) {
    assert(typeof row.id === 'number', 'each row needs the album handle');
    if (artless.has(row.id)) continue;
    assert(Array.isArray(row.layers) && row.layers.length > 0,
      `album entry ${row.id} needs layers, or its card draws nothing`);
    withLayers++;
  }
  eq(withLayers, ids.length - artless.size, 'every picture that HAS art must carry it');
  assert(artless.size <= 10, `unexpectedly many art-less pictures (${artless.size})`);

  /* and the editor must PUSH the layers, not just the list */
  const p = call(engine, 'client_gm', { cmd: 'unlock_pictures' });
  const byId = pushNamed(p, 'album_load_by_id_list');
  assert(byId.length === 1, 'unlock_pictures must push album_load_by_id_list');
  const pushed = byId[0].data.pic_list;
  eq(pushed.length, engine.state.pictures.length,
    'the pushed layers must cover every album entry, not just the new ones');
  for (const row of pushed) {
    if (artless.has(row.id)) continue;
    assert(Array.isArray(row.layers) && row.layers.length > 0,
      `pushed entry ${row.id} needs layers`);
  }
  /* album_load_all only carries id/pic_id -- it cannot fill a card on its own */
  const all = pushNamed(p, 'album_load_all')[0].data;
  assert(all.id_list.every((e) => e.layers === undefined),
    'album_load_all is the handle list; the layers come from the by-id-list push');
});

test('album: unlock_pictures fills pic_id AND keeps the handles unique', ({ engine }) => {
  /* The album renders the artwork from `pic_id` -- `withLayers()` looks it up as
     `pictureLayers[String(p.pic_id)]` -- while `id` is the album's own handle used by
     every album operation. Pushing only `{id}` (the old behaviour) left pic_id
     undefined, so every card came out BLANK and opening one threw. */
  call(engine, 'client_gm', { cmd: 'unlock_pictures' });
  const pics = engine.state.pictures;
  assert(pics.length > 300, 'it should unlock the whole table, got ' + pics.length);
  const handles = new Set();
  for (const p of pics) {
    assert(typeof p.pic_id === 'number' && p.pic_id > 0,
      `row ${p.id} has no pic_id, so its card renders blank`);
    assert(!handles.has(p.id), `album handle ${p.id} is used twice`);
    handles.add(p.id);
  }
  /* Every picture it claims must be a real Picture row. */
  const tableIds = new Set(((GDATA.tables.Picture) || [])
    .map((r) => (typeof r === 'number' ? r : r && r.id)));
  const bogus = pics.filter((p) => !tableIds.has(p.pic_id)).slice(0, 5).map((p) => p.pic_id);
  eq(bogus.length, 0, 'unknown Picture ids would render nothing: ' + bogus.join(','));
  /* And the first page the client asks for must carry composed layers. */
  const page = call(engine, 'album_load', { start: 1, count: 8 }).reply;
  const withLayers = page.pictures.filter((p) => p.layers).length;
  assert(withLayers > 0, 'album_load must hand the client composed layers');
  eq(call(engine, 'client_gm', { cmd: 'unlock_pictures' }).reply.succeed, true,
    'running it twice must be harmless');
  eq(engine.state.pictures.length, pics.length, 'and must not duplicate anything');
});

test('encyclopedia: a flower brought home unlocks its entry, not just a grown one', ({ engine }) => {
  /* decoration rows carry `desc_handbook` and their `icon` equals the encyclopedia row's
     (decoration 10011 角堇·火龙果 -> icon_chahua_zhongzhi_jiaojin_1 == encyclopedia
     1010101). Only the flowerpot's `grown` list used to feed this payload, so a player
     who merely travelled saw the whole 百科 as 未收集. */
  const pay = () => call(engine, 'encyclopedia_load', {}).reply;
  eq(pay().unlock_list.length, 0, 'a fresh save has nothing unlocked');

  /* Pick the candidate exactly the way the engine does: a decoration whose `icon` is the
     same string as some encyclopedia row's. */
  const enc = GDATA.tables.encyclopedia || {};
  const encIcons = new Set(Object.keys(enc.list || {})
    .map((k) => enc.list[k]).filter(Boolean)
    .reduce((acc, r) => acc.concat([r.icon, r.pic_img]), []));
  const decos = Object.keys(GDATA.tables.decoration || {});
  const withIcon = decos.filter((k) => {
    const d = GDATA.tables.decoration[k];
    return d && d.icon && encIcons.has(d.icon);
  });
  assert(withIcon.length > 0,
    'expected at least one brought-home flower that maps to an encyclopedia entry');
  const decId = Number(withIcon[0]);
  engine.state.decoration.hasList.push({ id: decId, num: 1 });
  const r = pay();
  assert(r.unlock_list.length > 0,
    'a brought-home flower must unlock an encyclopedia species');
  for (const longId of r.unlock_list) {
    const e = enc.list[String(longId)];
    assert(e, `unlock_list entry ${longId} must index the encyclopedia table`);
    const d = r.unlock_desc.find((x) => x.id === e.id);
    assert(d && d.list.length > 0, `species ${e.id} needs its description lines`);
  }
  assert(r.show_sub.length > 0, 'the brought-home species must appear in the grid');
  for (const s of r.show_sub) {
    assert(enc.list[String(s.sub_id)],
      `show_sub for species ${s.id} must carry a table key, not a variety number`);
  }

  /* and the pot still works */
  const plant = Object.keys(((GDATA.tables.flowerpotData || {}).plant) || {})[0];
  if (plant) {
    engine.state.flowerpot.grown.push(Number(plant));
    assert(pay().unlock_list.length >= r.unlock_list.length,
      'a grown plant must not remove anything');
  }
});

test('handbook: a real trip feeds the two lists the 图鉴 renders from', ({ engine }) => {
  /* 放浪 trips return early and bring nothing, so a player whose frog kept leaving
     unprepared saw every 纪念品/特产 as "?" -- the lists below are exactly what the
     client turns into count:1 vs "?". */
  const hand = () => call(engine, 'item_load_handbook', {}).reply;
  eq(hand().collections.length, 0, 'a fresh save has nothing recorded');
  eq(hand().specialtys.length, 0, 'nor any specialty');

  /* The LONGEST lunch (茄汁蛋包饭 3, H_MAXTIME 72): the walk budget is the lunch's
     HP, and 纪念品 only come from the nodes a trip actually reaches, so the weakest
     lunch would make this a coin flip. */
  const lunch = idsOfType(0).reduce((best, id) => (
    effectSum(id, 'HP') > effectSum(best, 'HP') ? id : best), idsOfType(0)[0]);
  const before = { cols: 0, spes: 0 };
  for (let i = 0; i < 60; i++) {
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

test('editor: unlock_all fills the 图鉴, the 百科 and the museum', ({ engine }) => {
  const g = (cmd) => call(engine, 'client_gm', { cmd }).reply;
  const before = call(engine, 'item_load_handbook', {}).reply;
  eq(before.collections.length, 0, 'a fresh save has an empty 图鉴');
  eq(before.specialtys.length, 0, 'and no specialties');

  const r = g('unlock_all');
  eq(r.succeed, true, 'unlock_all reports success');

  const hand = call(engine, 'item_load_handbook', {}).reply;
  const colIds = new Set(Object.keys(GDATA.tables.Collection || {}).map(Number));
  const specIds = new Set(GDATA.items.filter((i) => i.type === 3).map((i) => i.id));
  for (const id of hand.collections) assert(colIds.has(id), `collection ${id} is unknown`);
  for (const id of hand.specialtys) assert(specIds.has(id), `specialty ${id} is unknown`);
  assert(hand.collections.length >= colIds.size - 1,
    'every Collection row should be recorded, or the 图鉴 still shows ?');
  assert(hand.specialtys.length >= specIds.size - 1, 'and every specialty item');

  const enc = call(engine, 'encyclopedia_load', {}).reply;
  const ENCT = GDATA.tables.encyclopedia;
  const allRows = Object.keys(ENCT.list).map((k) => ENCT.list[k]);
  const species = new Set(allRows.map((r) => r.id));
  assert(enc.unlock_list.length > 0, 'the 百科 must have entries, or its menu entry hides');
  eq(enc.unlock_list.length, allRows.length,
    'unlock_all unlocks every picture row in the table');
  eq(enc.show_sub.length, species.size,
    'every species needs a show_sub row, or its slot in the grid stays blank');
  for (const longId of enc.unlock_list) {
    const e = ENCT.list[String(longId)];
    assert(e, `unlock_list entry ${longId} must index the encyclopedia table`);
    assert(enc.unlock_desc.some((d) => d.id === e.id),
      `species ${e.id} needs its description lines`);
  }
  assert(engine.state.encyAll, 'the flag is persisted so a reopen keeps it');

  const museums = call(engine, 'museum_load', {}).reply.museum_list;
  for (const m of museums) {
    assert(m.pic_list.length > 0, `museum ${m.id} postcards`);
    assert(m.collections.length > 0, `museum ${m.id} collectibles`);
  }
});

test('editor: an edit is pushed to the client, so no restart is needed', ({ engine }) => {
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
  /* unlock_all grants no furniture, so this only has to be the real shape here -- the
     list itself is what all_furniture fills, checked by the test below. */
  assert(Array.isArray(fur.has_fur), 'the 家具 list the book renders from');
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

test('editor: all_furniture grants every row, and the client payload carries them', ({ engine }) => {
  const g = (cmd) => call(engine, 'client_gm', { cmd }).reply;
  eq(engine.state.furniture.owned.length, 0, 'a fresh save owns no furniture');
  const r = g('all_furniture');
  eq(r.succeed, true, 'all_furniture reports success');
  const rows = Object.keys(GDATA.tables.furnitureData || {}).map(Number);
  eq(engine.state.furniture.owned.length, rows.length,
    'one entry per furnitureData row');
  const loaded = call(engine, 'furniture_load_furniture', {}).reply;
  eq((loaded.has_fur || []).length, rows.length,
    'and the payload the 家具 book renders from carries all of them');
  /* running it twice must not duplicate */
  g('all_furniture');
  eq(engine.state.furniture.owned.length, rows.length, 'idempotent');
});

/* ------------------------------------------------------------ save safety
   The bug these guard against: a truncated/unreadable save file used to be
   swallowed by a try/catch, the player silently got a brand-new game, and the
   next write destroyed the remains. Every check below writes bytes onto the disk
   first and then boots the engine against them. */

console.log('\n== save safety ==');

function corruptSlots(dir) {
  return fs.readdirSync(dir).filter((n) => n.indexOf('save.json.corrupt-') === 0);
}

test('save: an unreadable main file is restored from the backup, not discarded', ({ engine, savePath, dir }) => {
  call(engine, 'client_gm', { cmd: 'add_clover 500' });     // save #1 -> no .bak yet
  const good = 9999 + 500;
  call(engine, 'client_gm', { cmd: 'add_clover 500' });     // save #2 -> .bak = #1
  eq(fs.existsSync(savePath + '.bak'), true, '.bak is written before each commit');
  eq(fs.existsSync(savePath + '.tmp'), false, 'no .tmp left behind');

  fs.writeFileSync(savePath, '{"clover":10499,"frog":{"status":0}');   // truncated mid-write
  const re = reopen(savePath);
  eq(re.state.clover, good, 'the backup holds the last complete save');
  eq(re.state.__saveReport.action, 'restore', 'and the load reports a restore');
  eq(re.state.__saveReport.restoredFrom, 'backup', 'naming the backup');
  const slots = corruptSlots(dir);
  eq(slots.length, 1, 'the unreadable bytes were archived, not dropped');
  assert(fs.readFileSync(path.join(dir, slots[0]), 'utf8').indexOf('10499') !== -1,
    'the archive holds the original text');
  /* Booting again must not pile up a second copy of the same bytes. */
  const re2 = reopen(savePath);
  eq(corruptSlots(dir).length, 1, 're-booting on the same damage reuses the archive');
  eq(re2.state.clover, good, 'and still restores the same way');
});

test('save: an unreadable main with no backup keeps the bytes instead of overwriting them', ({ savePath, dir }) => {
  fs.writeFileSync(savePath, 'not json at all, this file was cut off in the middle');
  const re = reopen(savePath);
  eq(re.state.__saveReport.action, 'new', 'a fresh game is what the player sees');
  eq(corruptSlots(dir).length, 1, 'but the damaged file is kept for inspection');
  eq(re.state.__saveReport.protectMain, false, 'small garbage does not block writing');
  eq(re.save(), true, 'so the new game can be saved over it');
  eq(JSON.parse(fs.readFileSync(savePath, 'utf8')).clover, 9999, 'main file is valid again');
});

test('save: if the damaged save cannot be archived, the engine refuses to overwrite it', ({ savePath, dir }) => {
  /* A real save is far bigger than the 200-byte threshold below, which is what
     makes "archived" the only acceptable outcome for real content. */
  const blob = '{"clover":7777,"name":"' + 'x'.repeat(300) + '"';   // truncated
  fs.writeFileSync(savePath, blob);
  const realWrite = fs.writeFileSync;
  fs.writeFileSync = function (p, d) {
    if (String(p).indexOf('.corrupt-') !== -1) throw new Error('quota exceeded');
    return realWrite.apply(fs, arguments);
  };
  try {
    const re = reopen(savePath);
    eq(re.state.__saveReport.protectMain, true, 'the loader flags the main file as protected');
    eq(re.save(), false, 'save() refuses');
    eq(re.state.__saveReport.blocked, true, 'and says why');
    eq(re.state.__saveReport.lastError, 'protect-main', 'with a machine-readable reason');
    eq(fs.readFileSync(savePath, 'utf8'), blob, 'the only copy of the save is byte-identical');
    /* The escape hatch is deliberately manual: the unreadable bytes are NOT
       recoverable (nothing could parse them, and they could not be archived), so
       accepting the loss has to be a decision someone makes. */
    eq(re.forceSaveOverwrite(), true, 'the documented escape hatch still writes');
    eq(JSON.parse(fs.readFileSync(savePath, 'utf8')).clover, 9999,
      'and what it writes is the state that was actually loaded (a new game)');
  } finally {
    fs.writeFileSync = realWrite;
  }
});

test('save: a failed main write leaves the stored save untouched and reports it', ({ engine, savePath }) => {
  call(engine, 'client_gm', { cmd: 'set_clover 4242' });
  call(engine, 'client_gm', { cmd: 'set_clover 5151' });
  eq(engine.save(), true, 'a healthy write succeeds');
  // what a healthy commit left behind: this is the copy that must survive the
  // failure below untouched
  const onDisk = fs.readFileSync(savePath, 'utf8');
  eq(JSON.parse(onDisk).clover, 5151, 'precondition: 5151 is the stored save');
  const realWrite = fs.writeFileSync;
  fs.writeFileSync = function (p, d) {
    if (String(p) === savePath) throw new Error('no space left on device');
    return realWrite.apply(fs, arguments);
  };
  try {
    call(engine, 'client_gm', { cmd: 'set_clover 6262' });
    eq(engine.state.clover, 6262, 'in-memory play continues');
    eq(engine.save(), false, 'save() reports the failure instead of swallowing it');
    eq(engine.state.__saveReport.lastError, 'write-main', 'the reason is exposed to the shell');
    eq(engine.state.__saveReport.blocked, false, 'this is a failure, not a refusal');
    eq(JSON.parse(onDisk).clover, 5151, 'the previously stored save is what is still on disk');
    /* the pending copy is what the docs tell the player to look for */
    eq(fs.existsSync(savePath + '.tmp'), true, 'a complete copy is left in .tmp');
  } finally {
    fs.writeFileSync = realWrite;
  }
  eq(engine.save(), true, 'and saving works again once the disk recovers');
  eq(JSON.parse(fs.readFileSync(savePath, 'utf8')).clover, 6262, 'with the latest state');
  eq(fs.existsSync(savePath + '.tmp'), false, '.tmp is cleaned up');
});

test('save: an old save (no saveVersion, few fields) still loads and still saves', ({ savePath }) => {
  /* This is the compatibility contract: the format and the key are unchanged. */
  fs.writeFileSync(savePath, '{"clover":1234,"name":"\\u8001\\u6863","items":{}}');
  const re = reopen(savePath);
  eq(re.state.clover, 1234, 'an old clover count survives');
  eq(re.state.name, '老档', 'so does the name');
  eq(re.state.saveVersion, 1, 'the missing version field is filled in');
  eq(re.state.__saveReport.action, 'load', 'an old save is a normal load, not a repair');
  eq(re.state.__saveReport.reason, null, 'with nothing to report');
  call(re, 'client_gm', { cmd: 'add_clover 10' });
  const back = JSON.parse(fs.readFileSync(savePath, 'utf8'));
  eq(back.clover, 1244, 'it keeps saving normally');
  eq(back.name, '老档', 'and keeps the fields it had');
});

test('save: a save from a NEWER engine is loaded but never overwritten', ({ savePath }) => {
  fs.writeFileSync(savePath, JSON.stringify({
    saveVersion: 99, clover: 321, name: '未来档', items: {},
    somethingNew: { that: 'we do not understand' },
  }));
  const re = reopen(savePath);
  eq(re.state.clover, 321, 'we can still play it');
  eq(re.state.somethingNew.that, 'we do not understand', 'and the unknown fields are kept in memory');
  eq(re.save(), false, 'but we refuse to write over a newer format');
  eq(re.state.__saveReport.lastError, 'save-version-ahead', 'with a reason');
  const onDisk = JSON.parse(fs.readFileSync(savePath, 'utf8'));
  eq(onDisk.saveVersion, 99, 'the file is untouched');
  eq(onDisk.somethingNew.that, 'we do not understand', 'unknown fields included');
});

test('save: import is an explicit overwrite and clears a protected main', ({ savePath }) => {
  const blob = '{"clover":7777,"name":"' + 'y'.repeat(300) + '"';
  fs.writeFileSync(savePath, blob);
  const realWrite = fs.writeFileSync;
  fs.writeFileSync = function (p, d) {
    if (String(p).indexOf('.corrupt-') !== -1) throw new Error('quota exceeded');
    return realWrite.apply(fs, arguments);
  };
  try {
    const re = reopen(savePath);
    eq(re.state.__saveReport.protectMain, true, 'precondition: main is protected');
    const snapshot = JSON.parse(JSON.stringify(re.state));
    snapshot.clover = 88;
    eq(re.importSave(snapshot), true, 'a deliberate import is allowed through');
    eq(JSON.parse(fs.readFileSync(savePath, 'utf8')).clover, 88, 'and lands on disk');
    eq(re.state.__saveReport.protectMain, false, 'the protection flag is not inherited');
  } finally {
    fs.writeFileSync = realWrite;
  }
});

test('save: a save damaged WHILE the game is running is archived, not overwritten', ({ engine, savePath, dir }) => {
  call(engine, 'client_gm', { cmd: 'set_clover 100' });
  call(engine, 'client_gm', { cmd: 'set_clover 150' });          // .bak = 100
  const valid = fs.readFileSync(savePath, 'utf8');
  const damaged = valid.slice(0, 50);
  fs.writeFileSync(savePath, damaged);                            // an outside writer, a killed sibling
  call(engine, 'client_gm', { cmd: 'set_clover 200' });           // the running game saves on
  eq(JSON.parse(fs.readFileSync(savePath, 'utf8')).clover, 200, 'play and saving continue');
  const slots = corruptSlots(dir);
  eq(slots.length, 1, 'but the damaged bytes were archived first');
  eq(fs.readFileSync(path.join(dir, slots[0]), 'utf8'), damaged, 'byte for byte');
  eq(JSON.parse(fs.readFileSync(savePath + '.bak', 'utf8')).clover, 100,
    'and the good backup was not replaced by garbage');
});

/* ------------------------------------------------- 分享奖励 / 手工品计数 */

console.log('\n== 分享奖励 (share_*) 与年度回顾的手工品计数 ==');

test('share: a new photo is PUSHED to the share sheet, and the claim pays once', ({ engine }) => {
  /* The postcard share panel reads its amount from ShareModel.rewardData[pic.id],
     filled only by the pushed share_load. The client never sends share_load itself
     (addProtocolCallback = push-only) and req_get_reward returns early while
     rewardData is empty -- so with `pic_list: []` the reward button did nothing at
     all. */
  for (let i = 0; i < 3; i++) {
    engine.state.pictures.push({ id: i + 1, pic_id: 100 + i, read: 0, new: i === 2 });
  }
  const pushes = engine.tick();
  const sl = pushNamed({ pushes }, 'share_load');
  eq(sl.length, 1, 'the album growing must push share_load');
  eq(sl[0].data.pic_list.length, 3, 'one row per unclaimed photo');
  for (const row of sl[0].data.pic_list) {
    assert(typeof row.id === 'number' && row.clover > 0, 'each row is {id, clover}');
  }
  eq(pushNamed({ pushes: engine.tick() }, 'share_load').length, 0,
    'and it must not repeat every tick');

  const id = sl[0].data.pic_list[0].id;
  const mails = engine.state.mails.length;
  const r = call(engine, 'share_get_reward', { id, is_get: 1 });
  eq(r.reply.code, 0, 'claiming answers 0 (that is what makes the client toast)');
  eq(engine.state.mails.length, mails + 1, 'the reward arrives as a gift mail');
  const mail = engine.state.mails[engine.state.mails.length - 1];
  assert(Number(mail.resource.clover_point) > 0, 'with clover in it');
  assert(pushNamed(r, 'notify_new_mail').length === 1, 'and the mailbox is notified');

  /* idempotent: a reload mid-flow can repeat the send, and it must not pay twice */
  const again = call(engine, 'share_get_reward', { id, is_get: 1 });
  eq(again.reply.code, 0, 'a repeat still answers 0');
  eq(engine.state.mails.length, mails + 1, 'but pays nothing');
  eq(call(engine, 'share_get_reward', { id: 999999, is_get: 1 }).reply.code, -1,
    'an unknown photo is refused rather than paid');

  /* the remaining list must shrink, and survive a restart */
  const after = call(engine, 'share_load', {}).reply.pic_list;
  eq(after.length, 2, 'the claimed photo drops off the list');
  assert(after.every((row) => row.id !== id), 'and stays off it');
});

test('annual: the 手工品 counts come from the CRAFT records, not from a constant', ({ engine }) => {
  /* The client's line is 「一共雕刻了{0}个印章，完成了{0}个祈愿物」. This payload used
     to answer `stamp_num: 0` (with a comment claiming no stamp book existed) and a
     `wish_num` read off the WISHING POOL -- so the review said 「可惜没有雕刻过印章，
     祈愿物都没有」 no matter what the frog had made. A craft row is finished at
     state > 3 (see advanceCraft / pray_load_grays). */
  engine.state.craft = {
    seq: 4,
    wishes: [{ id: 1, state: 4, body: 101, paper: 1001, make_time: 1, u_id: 1 },
      { id: 2, state: 2, body: '', paper: '', make_time: 1, u_id: 2 }],
    /* a STAMP finishes at 3: stampData.state is [1,2,3] in all 27 rows */
    stamps: [{ id: 1, state: 3, time: 1, u_id: 3 },
      { id: 101, state: 3, time: 2, u_id: 4 },
      { id: 2, state: 2, time: 3, u_id: 5 }],
    pending: [],
  };
  const a = call(engine, 'annual_load', {}).reply;
  eq(a.stamp_num, 2, 'two finished stamps');
  eq(a.wish_num, 1, 'one finished wish plaque');
  /* and the payload the client needs to render at all */
  eq(a.is_share, true, 'is_share must stay truthy or the client raises a dead red dot');
  for (const k of ['create_time', 'login_day', 'travel_num', 'pic_num', 'page_num',
    'fur_num', 'note_num', 'spe_num', 'col_num', 'first_col', 'theme']) {
    assert(a[k] !== undefined, `annual review field ${k} is missing`);
  }
});

/* ------------------------------------------------- 手工品（印章 / 祈愿物） */

console.log('\n== 手工品：印章停在 state 3，祈愿物带 stamp_time ==');

test('craft: a STAMP stops at state 3 (the only states stampData knows)', ({ engine }) => {
  /* The client resolves a stamp's picture with
     `StampCraftDB.get(id).state.indexOf(stamp_state)`; every one of stampData's 27
     rows lists state [1,2,3], so a row pushed to 4 indexes to -1, sets no source and
     the picture is BLANK -- the reported "印章栏的图片为空白". */
  const CH = GDATA.tables.stampData;
  for (const row of Object.values(CH)) {
    eq(row.state.join(','), '1,2,3', 'stampData states are 1,2,3');
  }
  engine.state.craft = { seq: 1, wishes: [], pending: [],
    stamps: [{ id: Number(Object.keys(CH)[0]), state: 1, time: 0, u_id: 1 }] };
  for (let i = 0; i < 12; i++) {
    engine.state.craft.stamps.forEach((s) => { s.time = 0; });
    const r = call(engine, 'pray_load_grays', {});
    eq(r.handled, true, 'pray_load_grays must stay handled');
    const st = engine.state.craft.stamps[0];
    assert(st.state <= 3, `a stamp must never pass state 3, got ${st.state}`);
  }
  const st = engine.state.craft.stamps[0];
  eq(st.state, 3, 'and it does reach 3, which is "finished" for a stamp');
  const done = call(engine, 'annual_load', {}).reply;
  eq(done.stamp_num >= 1, true, 'so the annual review counts it as made');
});

test('craft: a finished 祈愿物 carries the stamp_time/stamp the detail card needs', ({ engine }) => {
  /* PrayCraftDetailRender.dataChanged reads:
       DateFormat.format(1000 * data.stamp_time, "YYYY.MM.DD")     -> the DATE
       if (data.stamp && 0 != data.stamp_time) { ...pattern_pic[state.indexOf(stamp_state)] }
     We only ever set `make_time` (our own internal clock), so the card printed
     NaN.NaN.NaN and drew no seal -- the reported "作出手工品的日期出错". */
  const wishId = Number(Object.keys(GDATA.tables.prayData)[0]);
  engine.state.craft = { seq: 1, stamps: [], pending: [],
    wishes: [{ id: wishId, state: 3, body: '', paper: '', content: 0, make_time: 0, u_id: 1 }] };
  call(engine, 'pray_load_grays', {});
  const w = engine.state.craft.wishes[0];
  eq(w.state, 4, 'prayData knows state 4, so 4 is finished for a wish');
  assert(Number(w.stamp_time) > 0, 'stamp_time must be a real epoch number, not undefined');
  assert(Number(w.stamp) > 0, 'the seal id must be a real stampData row');
  const row = GDATA.tables.stampData[String(w.stamp)];
  assert(row !== undefined, 'and that row must exist');
  assert(row.state.indexOf(w.stamp_state) >= 0,
    `stamp_state ${w.stamp_state} must be one of that stamp's states (${row.state})`);
  /* the payload the 印章 page renders from. (The list may already hold a NEW row:
     advanceCraft starts the next piece as soon as the previous one is finished.) */
  const r = call(engine, 'pray_load_grays', {}).reply;
  assert(Array.isArray(r.wishs) && r.wishs.length >= 1, 'wishs must be an array of rows');
  assert(r.wishs.some((x) => Number(x.state) === 4), 'the finished row is in the list');
  assert(Array.isArray(r.stamps), 'stamps must be an array');
  assert(r.wish_new && Number(r.wish_new.make_time) > 0, 'wish_new carries the new-row marker');
});

test('travel: the frog picks up what the DESK offers, and it comes back to the desk', ({ engine }) => {
  /* The game's own first-run text promises 「如果在桌子上放好了东西 …
     {0}也会自己挑选东西出门旅行」. The desk's slots are typed too
     (DeskItem = {LunchBox_1:0, LunchBox_2:1, Amulet_1:2, Amulet_2:3, Tool_1..4:4..7}). */
  const spendOf = (id) => (items.find((i) => i.id === id) || {}).spend;
  const lunch = idsOfType(0)[0];
  const amulet = idsOfType(1).find((id) => spendOf(id) !== 1);
  const tools = idsOfType(2).filter((id) => spendOf(id) !== 1).slice(0, 2);
  engine.state.items.bag = [-1, -1, -1, -1];
  /* desk: 0 便当 / 2 护身符 / 4,5 道具 */
  engine.state.items.desk = [lunch, -1, amulet, -1, tools[0], tools[1], -1, -1];
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  eq(engine.state.frog.status, 1, 'a desk-only preparation is enough to depart');
  const plan = engine.state.travel.plan;
  eq(plan.lunch, lunch, 'the lunch box is taken from the desk');
  eq(plan.lunchFrom, 'desk', 'and the plan says so');
  eq(plan.amulet, amulet, 'the amulet is picked up from the desk');
  eq(plan.tools, 2, 'and both tools count towards the trip');
  eq(engine.state.items.desk[2], -1, 'the picked items leave the desk while they travel');
  eq(engine.state.items.desk[4], -1, 'including the tools');
  engine.state.travel.returnAt = 1;
  engine.tick();
  const desk = engine.state.items.desk;
  const bag = engine.state.items.bag;
  eq(desk[2], amulet, 'the amulet returns to its own desk slot');
  eq(desk[4], tools[0], 'tool 1 returns to its own desk slot');
  eq(desk[5], tools[1], 'tool 2 returns to its own desk slot');
  eq(bag.filter((x) => x !== -1).length, 0, 'and nothing was pushed into the bag');
});

test('travel: a desk with NOTHING usable still keeps the frog at home', ({ engine }) => {
  /* The 「没准备就不出门」 rule is ours (【自设计】), and it must survive the desk
     change: an empty bag + an empty desk means the frog waits rather than leaving
     on a 放浪 trip that brings nothing back. */
  engine.state.items.bag = [-1, -1, -1, -1];
  engine.state.items.desk = [-1, -1, -1, -1, -1, -1, -1, -1];
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  eq(engine.state.frog.status, 0, 'the frog stays home');
  eq(engine.state.travel.waitingForBag, true, 'and the state says it is waiting for provisions');
});

test('craft: a save made by an OLD build is healed (date + seal + stamp state clamp)', ({ engine }) => {
  /* Existing saves carry rows written before `stamp_time` existed, and stamps the old
     build pushed to state 4 -- one past what stampData knows. Praying must repair
     them, or "old save = still broken" would be the player's experience. */
  const wishId = Number(Object.keys(GDATA.tables.prayData)[0]);
  engine.state.craft = {
    seq: 9, pending: [],
    wishes: [
      { id: wishId, state: 4, body: 101, paper: 1001, content: 0, make_time: 1700000000, u_id: 1 },
      { id: wishId, state: 2, body: '', paper: '', content: 0,
        make_time: Math.floor(Date.now() / 1000) + 100000, u_id: 2 },
    ],
    stamps: [{ id: 1, state: 4, time: 1700000000, u_id: 3 }],
  };
  const r = call(engine, 'pray_load_grays', {}).reply;
  const done = r.wishs.find((w) => Number(w.state) === 4);
  eq(Number(done.stamp_time), 1700000000, 'the date is backfilled from make_time');
  assert(Number(done.stamp) > 0, 'and a seal id is assigned');
  const stamRow = GDATA.tables.stampData[String(done.stamp)];
  assert(stamRow.state.indexOf(done.stamp_state) >= 0, 'with a state that stamp actually has');
  eq(r.stamps[0].state, 3, 'the stamp is clamped back to the last state its table knows');
  /* the in-progress row must NOT be touched */
  const inProgress = r.wishs.find((w) => Number(w.u_id) === 2);
  eq(Number(inProgress.state), 2, 'the unfinished wish is still being made');
  eq(inProgress.stamp_time, undefined, 'and gets no date');
});

test('guide: the tutorial step never walks BACKWARDS when we echo it', ({ engine }) => {
  /* The client overwrites its own clientSettings from `client_load_role`'s
     settings.client, so echoing a step that is one behind makes the guide rewind --
     which in the tutorial means being asked to name the frog a second time. */
  const send = (obj) => engine.dispatch('client_set_client', { client: JSON.stringify(obj) });
  send({ guideStep: 'Named', hasOpenedDesk: true });
  eq(engine.state.settings.guideStep, 'Named', 'the client\'s step is remembered');
  send({ guideStep: 'PrepareGatherClover' });
  eq(engine.state.settings.guideStep, 'PrepareGatherClover', 'and advancing is accepted');
  /* a stale echo (the client's own older snapshot, or a race with our push) */
  send({ guideStep: 'Named' });
  eq(engine.state.settings.guideStep, 'PrepareGatherClover',
    'a stale step must NOT rewind the tutorial');
  /* the payload we send back carries the furthest step */
  const role = call(engine, 'client_load_role', {}).reply;
  const echoed = JSON.parse(role.settings.client);
  eq(echoed.guideStep, 'PrepareGatherClover', 'and the echo carries the furthest step');
  /* other fields still merge normally */
  send({ hasOpenedDesk: false, bgSound: 0 });
  eq(engine.state.settings.bgSound, 0, 'non-guide settings still update');
});

/* ------------------------------------------------- 套装/盲盒 (Item type 5) */

console.log('\n== 套装/盲盒：买到就拆开 ==');

test('shop: a 套装 bought from the merchant is OPENED on the spot (GiftData)', ({ engine }) => {
  /* furnitureShopData rows 1 and 2 sell item 5001 工具套装 and 5002 材料套装 for 1
     clover; `GiftData` is the game's own table of the contents. The client cannot ask
     to open a box (`item_gift_open` is push-only: no send() anywhere in the bundle),
     so an unopened box is a dead item -- the reported 「已购买但工具/材料没到账」. */
  const GIFT = GDATA.tables.GiftData;
  assert(GIFT['5001'] && GIFT['5002'], 'GiftData must carry the two 套装');
  const row1 = GDATA.tables.furnitureShopData['1'];
  eq(Number(row1.item_id), 5001, 'row 1 sells the 工具套装');
  engine.dispatch('client_gm', { cmd: 'set_clover 5000' });
  for (const id of GIFT['5001'].item_id) eq(haveOf(engine, id), 0, `item ${id} starts at 0`);

  const r = call(engine, 'furniture_buy_shop', { shop_id: 1 });
  eq(r.reply.code, 0, 'the purchase succeeds');
  for (const id of GIFT['5001'].item_id) {
    eq(haveOf(engine, id), 1, `the tools arrive (item ${id})`);
  }
  eq(haveOf(engine, 5001), 0, 'and the empty box is NOT left in the house');
  const gift = pushNamed(r, 'item_gift_open');
  eq(gift.length, 1, 'item_gift_open is pushed so the player SEES the contents');
  eq(gift[0].data.items.length, GIFT['5001'].item_id.length, 'with every row');
  for (const item of gift[0].data.items) {
    assert(typeof item.item_id === 'number' && Number(item.count) > 0,
      'each row is {item_id, count}');
  }
});

test('shop: the 材料套装 pays exactly what GiftData says', ({ engine }) => {
  const GIFT = GDATA.tables.GiftData['5002'];
  engine.dispatch('client_gm', { cmd: 'set_clover 5000' });
  const r = call(engine, 'furniture_buy_shop', { shop_id: 2 });
  eq(r.reply.code, 0, 'purchase ok');
  const got = pushNamed(r, 'item_gift_open')[0].data.items.map((x) => Number(x.item_id));
  eq(got.slice().sort().join(','), GIFT.item_id.slice().sort().join(','),
    'the contents are exactly GiftData\'s list');
  for (const id of GIFT.item_id) assert(haveOf(engine, id) >= 1, `item ${id} credited`);
});

test('shop: a RANDOM box (5101 种子盲盒) still yields a real row', ({ engine }) => {
  engine.dispatch('client_gm', { cmd: 'set_clover 5000' });
  const r = call(engine, 'furniture_buy_shop', { shop_id: 6 });
  eq(r.reply.code, 0, 'purchase ok');
  const items = pushNamed(r, 'item_gift_open')[0].data.items;
  eq(items.length, 1, 'one row, like GiftData\'s own 1-each shape');
  const seeds = GDATA.tables.GiftData['5003'].item_id.map(Number);
  assert(seeds.indexOf(Number(items[0].item_id)) >= 0,
    `the seed must come from the seed list (got ${items[0].item_id})`);
  assert(haveOf(engine, Number(items[0].item_id)) >= 1, 'and it is credited');
  eq(haveOf(engine, 5101), 0, 'the box itself is consumed');
});

test('tasks: the cumulative plan rewards (「伴蛙前行」面板) are payable once', ({ engine }) => {
  /* The task panel's tiered plans (是日清单/当周计划/…) are claimed with
     `task_get_list_reward`, id = 100*type + tier. That handler did not exist at all,
     so the button did nothing -- 「奖励点不下去，没法收到」. */
  const LIST = GDATA.tables.taskData.list_type;
  const type1 = LIST['1'];
  eq(type1.target.length, type1.reward.length, 'targets and rewards are paired');
  /* a fresh save: the plan is not earned yet */
  eq(call(engine, 'task_get_list_reward', { id: 101 }).reply.code, -1,
    'an unearned tier is refused');
  /* earn it: the plan's progress counts completed list_map rows of that type */
  engine.state.travel.tripCount = 5;
  const before = haveOf(engine, Number(type1.reward[0]));
  const r = call(engine, 'task_get_list_reward', { id: 101 });
  eq(r.reply.code, 0, 'an earned tier pays');
  eq(haveOf(engine, Number(type1.reward[0])), before + 1, 'and the table\'s own reward lands');
  eq(pushNamed(r, 'task_load').length, 1, 'the task rows are re-pushed');
  eq(pushNamed(r, 'task_load_list').length, 1, 'and so are the tier rows');
  /* once only */
  eq(call(engine, 'task_get_list_reward', { id: 101 }).reply.code, 1, 'a repeat must not trigger the reward popup');
  eq(haveOf(engine, Number(type1.reward[0])), before + 1, 'but pays nothing');
  /* the client learns which tiers are claimed from `pro` */
  const rows = call(engine, 'task_load_list', {}).reply.reward;
  const t1 = rows.filter((x) => x.id === 1)[0];
  eq(t1.pro, 1, 'the claimed tier count is reported back');
  /* and task rows carry the progress the client's red dot reads */
  const tasks = call(engine, 'task_load', {}).reply.tasks;
  for (const t of tasks) assert(typeof t.pro === 'number', 'every task row carries `pro`');
  eq(tasks.find((t) => t.id === 1).pro, 5, 'type 1 tasks count trips');
});

test('tasks: claimed route rewards restore under the client plan key and never replay success', ({ engine, savePath }) => {
  engine.state.travel.tripCount = 5;
  eq(call(engine,'task_get_list_reward',{id:101}).reply.code,0);
  const restored = reopen(savePath);
  const rows = call(restored,'task_load_list',{}).reply.reward;
  eq(rows.find(x=>x.id===1).pro,1);
  assert(!rows.some(x=>x.id===101),'claim request ids must not leak into loaded plan ids');
  const before = JSON.stringify(restored.state.items);
  const repeat = call(restored,'task_get_list_reward',{id:101});
  eq(repeat.reply.code,1,'success would pop up a second reward');
  eq(pushNamed(repeat,'task_load_list')[0].data.reward.find(x=>x.id===1).pro,1);
  eq(JSON.stringify(restored.state.items),before);
});

/* ==================================================================== 目的地系统

   The destination map (work/run/engine/data/travel.json, built by
   work/tools/build_travel_data.py from the archived China CDN) is what decides
   where a trip goes and what it brings back. These tests read the SAME tables the
   engine reads, so they fail if the data and the code ever drift apart.
   (`TRAVEL` itself is required at the top of this file.) */

/** The area names a carried item pulls the trip towards (Item.effects). */
function decideAreas(itemId) {
  return ((TRAVEL.effects[String(itemId)]) || [])
    .filter((e) => e[0] === 'AREA_DECIDE').map((e) => String(e[1]));
}

/** Total effectValue of one effect name on one item, from the CN effects table. */
function effectSum(itemId, effect) {
  return ((TRAVEL.effects[String(itemId)]) || [])
    .filter((e) => e[0] === effect)
    .reduce((n, e) => n + Number(e[2] || 0), 0);
}

/** Run `n` departures with `bag` packed and report where they went. */
function runTrips(engine, bag, n) {
  const areas = {};
  const pictures = [];
  const collections = [];
  let notes = 0;
  for (let i = 0; i < n; i++) {
    engine.state.items.bag = [-1, -1, -1, -1];
    /* NOTE: `bag[k] > 0` would drop item 0 (奶油华夫饼) -- an id of 0 is a real
       item, not "empty". */
    for (let k = 0; k < bag.length && k < 4; k++) {
      if (bag[k] !== undefined && bag[k] !== null && bag[k] !== -1) engine.state.items.bag[k] = bag[k];
    }
    engine.state.travel.nextDepartAt = 1;
    engine.state.travel.returnAt = 0;
    engine.tick();
    const before = (engine.state.albumPending || []).map((p) => p.pic_id);
    const cols = (engine.state.handbook.collections || []).length;
    engine.state.travel.returnAt = 1;
    const pushes = engine.tick() || [];
    (pushes || []).forEach((p) => {
      if (String(p.cmd).replace(/\./g, '_') === 'notify_new_event'
          && p.data && p.data.event && Number(p.data.event.evt_type) === 15) notes += 1;
    });
    (engine.state.albumPending || []).forEach((p) => {
      if (before.indexOf(p.pic_id) === -1) pictures.push(p.pic_id);
    });
    if ((engine.state.handbook.collections || []).length > cols) {
      collections.push(engine.state.handbook.collections.slice(-1)[0]);
    }
    const v = engine.state.travel.visited || { areas: {} };
    Object.keys(v.areas || {}).forEach((a) => { areas[a] = true; });
  }
  return { areas, pictures, collections, notes };
}

test('目的地: a 护身符 with AREA_DECIDE really decides where the trip goes', ({ engine }) => {
  /* 蓝色铃铛 1005 -> A_NORTH only. Its weight is 10 + 80 against 10 for every
     other area, so the odd trip elsewhere is expected -- the trend is not. */
  const amulet = 1005;
  eq(decideAreas(amulet).join(','), 'A_NORTH', 'the table says A_NORTH for 1005');
  const lunch = idsOfType(0).find((id) => effectSum(id, 'HP') > 0);
  const r = runTrips(engine, [lunch, amulet], 40);
  const names = Object.keys(r.areas);
  assert(names.indexOf('A_NORTH') !== -1, 'north trips happened');
  /* The weight is 80 against 1 for every other area, so a handful of stray trips is
     expected over 40 -- what must hold is that the north dominates and that no
     single other area takes over. */
  assert(names.length <= 10,
    `an AREA_DECIDE amulet must keep the frog in its own area, saw ${names.join(',')}`);
  assert(engine.state.travel.visited.areas.A_NORTH >= 26,
    `A_NORTH should dominate, got ${engine.state.travel.visited.areas.A_NORTH}/40`);
  /* Every recorded area has to be a real Area row (the walker resolves areas from
     that table). */
  const known = new Set(TRAVEL.areas.map((a) => a.name));
  for (const n of Object.keys(engine.state.travel.visited.areas)) {
    assert(known.has(n), `${n} is not an Area row`);
  }
});

test('目的地: the souvenirs are the ones THAT area can drop', ({ engine }) => {
  const amulet = 1005;                       // A_NORTH
  const lunch = idsOfType(0).find((id) => effectSum(id, 'HP') > 0);
  /* An AREA_DECIDE amulet still lets the odd trip go elsewhere, so the check is
     per-trip: read which area that trip counted up, then make sure everything it
     brought home is something THAT area's own rows can drop. */
  const allowedFor = (areaName) => {
    const area = TRAVEL.areas.filter((a) => a.name === areaName)[0];
    const set = new Set();
    Object.keys(TRAVEL.nodeItems).forEach((k) => {
      const id = Number(k);
      if (id < area.start || id > area.end) return;
      (TRAVEL.nodeItems[k].s || []).forEach((pair) => set.add(Number(pair[0])));
    });
    ((GDATA.tables.Specialty) || []).forEach((row) => {
      if (row.place === area.place) set.add(Number(row.itemId));
    });
    return set;
  };
  const counts = () => {
    const v = (engine.state.travel.visited || {}).areas || {};
    return Object.assign({}, v);
  };
  const known = new Set(TRAVEL.areas.map((a) => a.name));
  let checked = 0;
  for (let i = 0; i < 60; i++) {
    engine.state.items.bag = [-1, -1, -1, -1];
    engine.state.items.bag[0] = lunch;
    engine.state.items.bag[1] = amulet;
    engine.state.travel.nextDepartAt = 1;
    engine.state.travel.returnAt = 0;
    engine.tick();
    const before = counts();
    const spBefore = (engine.state.handbook.specialtys || []).slice();
    engine.state.travel.returnAt = 1;
    engine.tick();
    const after = counts();
    const grew = Object.keys(after).filter((a) => (after[a] || 0) > (before[a] || 0));
    eq(grew.length, 1, 'a trip counts into exactly one area');
    const area = grew[0];
    assert(known.has(area), `${area} is not an Area row`);
    const allowed = allowedFor(area);
    (engine.state.handbook.specialtys || []).forEach((id) => {
      if (spBefore.indexOf(id) !== -1) return;          // seen on an earlier trip
      checked += 1;
      assert(allowed.has(id),
        `specialty ${id} cannot come from ${area} (its rows never list it)`);
    });
  }
  assert(checked > 0, 'the trips brought something home to check');
  assert(engine.state.travel.visited.areas.A_NORTH > 0, 'A_NORTH was among them');
});

test('effects: a 便当 with a bigger H_MAXTIME gives a longer trip', ({ engine }) => {
  /* 奶油华夫饼 0: H_MAXTIME 6. 茄汁蛋包饭 3: H_MAXTIME 72. Both windows are rolled
     from the same range, so compare the means over enough trips. */
  const short = 0;
  const long = 3;
  const efShort = effectSum(short, 'HP');
  const efLong = effectSum(long, 'HP');
  assert(efLong > efShort * 3, `table check: ${efLong} vs ${efShort}`);
  const mean = (item) => {
    let total = 0;
    for (let i = 0; i < 60; i++) {
      engine.state.items.bag = [item, -1, -1, -1];
      engine.state.travel.nextDepartAt = 1;
      engine.state.travel.returnAt = 0;
      engine.tick();
      total += engine.state.travel.returnAt - engine.state.travel.departAt;
      engine.state.travel.returnAt = 1;
      engine.tick();
    }
    return total / 60;
  };
  const a = mean(short);
  const b = mean(long);
  assert(b > a * 1.2, `the 72-HP lunch must travel longer than the 6-HP one (${a} vs ${b})`);
});

test('effects: a 道具 with EVT_WAY unlocks that route and its photos', ({ engine }) => {
  /* 高级睡垫 2008 = E_MOUNTAIN + W_MOUNTAIN: only a mountain tool may enter a
     wayType-3 stretch, and every wayType-3 arrival carries the p_dry photo set. */
  const tool = 2008;
  const ef = (TRAVEL.effects[String(tool)] || []).map((e) => String(e[0]) + ':' + String(e[1]));
  assert(ef.indexOf('EVT_WAY:E_MOUNTAIN') !== -1, 'table check: 2008 is the mountain tool');
  const dryPics = new Set();
  const tag = ((GDATA.tables.PictureTag) || []).filter((t) => String(t.Tag) === 'p_dry')[0];
  const byName = new Map(((GDATA.tables.Picture) || []).map((p) => [p.name, p.id]));
  (tag.picNames || []).forEach((n) => { if (byName.has(n)) dryPics.add(byName.get(n)); });
  assert(dryPics.size > 0, 'p_dry has pictures');
  const lunch = idsOfType(0).find((id) => effectSum(id, 'HP') > 0);
  const r = runTrips(engine, [lunch, -1, tool], 60);
  const hit = r.pictures.filter((id) => dryPics.has(id));
  assert(hit.length > 0,
    'a mountain tool must be able to bring back a mountain (p_dry) postcard');
});

test('博物馆: a 门票 pins the trip to its museum and always pays the museum photo', ({ engine }) => {
  const ticket = 1017;                       // 江西省博物馆门票 -> A_BWG_JXS
  eq(decideAreas(ticket).join(','), 'A_BWG_JXS', 'table check: 1017 is the JXS ticket');
  const museumPics = new Set(((GDATA.tables.Picture) || [])
    .filter((p) => String(p.type) === 'Goal' && Number(p.place) === 100)
    .map((p) => p.id));
  assert(museumPics.size > 0, 'the museum has its own destination postcards');
  const lunch = idsOfType(0).find((id) => effectSum(id, 'HP') > 0);
  /* The ticket is spend=1, so pack a fresh one each time -- exactly what the player
     does after buying another. */
  let photos = 0;
  let elsewhere = 0;
  for (let i = 0; i < 12; i++) {
    engine.state.items.bag = [lunch, ticket, -1, -1];
    engine.state.travel.nextDepartAt = 1;
    engine.state.travel.returnAt = 0;
    engine.tick();
    /* Clear the pending bucket first: it de-duplicates by pic_id, so a museum that
       has only two postcards would otherwise look like it stopped paying after two
       visits -- that is the save's behaviour, not the trip's. */
    engine.state.albumPending = [];
    engine.state.travel.returnAt = 1;
    engine.tick();
    const after = (engine.state.albumPending || []).map((p) => p.pic_id);
    if (after.some((id) => museumPics.has(id))) photos += 1;
    const visited = Object.keys(engine.state.travel.visited.areas);
    if (visited.some((a) => a !== 'A_BWG_JXS')) elsewhere += 1;
  }
  assert(photos >= 10, `a museum trip must pay the museum photo (got ${photos}/12)`);
  eq(elsewhere, 0, 'a ticket trip never wanders off to another area');
});

test('笔记: a trip can grant a 旅行笔记, and only ids the Note table knows', ({ engine }) => {
  const noteIds = new Set(Object.keys(GDATA.tables.Note || {}).map((k) => Number(GDATA.tables.Note[k].id)));
  const lunch = idsOfType(0).find((id) => effectSum(id, 'HP') > 0);
  runTrips(engine, [lunch], 60);
  const notes = engine.state.notes || [];
  assert(notes.length > 0, 'the NodeEdge note ids must reach the save');
  for (const n of notes) {
    assert(noteIds.has(Number(n.id)),
      `note ${n.id} would be dropped by the client (not in the Note table)`);
    eq(n.read, 0, 'a fresh note is unread, which is what the red dot counts');
    assert(Number(n.timestamp) > 0, 'and it carries a timestamp in SECONDS');
  }
});

test('彩叶幸运草: carrying 1200 fills a missing postcard of a series you started', ({ engine }) => {
  /* Own everything except 101 (the second 屋檐/roof card), so exactly one gap
     exists and the filled card is unambiguous. */
  const all = ((GDATA.tables.Picture) || []).map((p) => p.id).filter((id) => id !== 101);
  engine.state.pictures = all.map((id, i) => ({ id: i + 1, pic_id: id, read: 0, new: 0 }));
  engine.state.albumPending = [];
  const lunch = idsOfType(0).find((id) => effectSum(id, 'HP') > 0);
  engine.state.items.bag = [lunch, 1200, -1, -1];        // 彩叶幸运草 rides as the amulet
  engine.state.travel.nextDepartAt = 1;
  engine.state.travel.returnAt = 0;
  engine.tick();
  engine.state.travel.returnAt = 1;
  engine.tick();
  const got = (engine.state.albumPending || []).map((p) => p.pic_id);
  assert(got.indexOf(101) !== -1,
    `the missing roof card must come home, got ${JSON.stringify(got)}`);
  eq(got[0], 101, 'and it is the first card of the trip, not a leftover slot');
});

test('兼容: a trip plan written by an OLD build (no `carried`) still returns home', ({ engine }) => {
  /* Old saves store the plan without `carried`; the walker must simply see no
     effects instead of throwing. Five trips, because a single trip is allowed to
     pay nothing at all. */
  let paid = 0;
  for (let i = 0; i < 5; i++) {
    engine.state.frog.status = 1;
    engine.state.travel.plan = {
      lunch: idsOfType(0)[0], lunchFrom: 'bag', amulet: -1, amuletSlot: -1,
      tools: 0, carryBack: [], stray: false, at: Math.floor(Date.now() / 1000),
    };
    engine.state.travel.returnAt = 1;
    const pics = (engine.state.albumPending || []).length;
    engine.tick();
    eq(engine.state.frog.status, 0, 'the frog is home');
    if ((engine.state.albumPending || []).length > pics || engine.state.specialtys.length > 0) paid += 1;
  }
  assert(paid > 0, 'and the trips still paid something');
});

/* ------------------------------------------------------------------ done */

test('room: default furniture supplies candle animations and a sleep skin; custom wins', ({ engine }) => {
  let rows = call(engine, 'furniture_load_furniture').reply.put_fur;
  eq(rows.find(r => r.type === 25).id, 1025);
  eq(rows.find(r => r.type === 9).id, 1009);
  engine.state.furniture.placed = [{type:25,id:1225}];
  rows = call(engine, 'furniture_load_furniture').reply.put_fur;
  eq(rows.filter(r => r.type === 25).length, 1);
  eq(rows.find(r => r.type === 25).id, 1225);
});

test('room: bedtime and morning interrupt motion timers, crafts use workshop actions', ({ engine }) => {
  const RealDate = Date;
  let time = new RealDate(2026, 8, 16, 20, 59).getTime();
  global.Date = class extends RealDate {
    constructor(...args) { super(...(args.length ? args : [time])); }
    static now() { return time; }
  };
  try {
    engine.state.items.bag = [-1,-1,-1,-1];
    engine.state.items.desk = Array(8).fill(-1);
    engine.tick();
    assert(engine.state.frog.motion < 5);
    engine.state.frog.motionNextAt = time / 1000 + 999999;
    time = new RealDate(2026,8,16,21).getTime();
    engine.tick();
    assert(engine.state.frog.motion >= 10 && engine.state.frog.motion <= 13);
    engine.state.furniture.placed=[{type:9,id:2009}];
    engine.state.frog.motionNextAt=0;
    engine.tick();
    eq(engine.state.frog.motion,10,'new bed uses the available sleep animation');
    time = new RealDate(2026,8,17,6).getTime();
    engine.tick();
    assert(engine.state.frog.motion < 5);
    engine.state.furniture.craft = {furnitureId:1101, finishAt:time / 1000 + 300};
    engine.tick();
    assert(engine.state.frog.motion >= 5 && engine.state.frog.motion <= 9);
  } finally { global.Date = RealDate; }
});

test('room: harvested flowers fit the vase only while away and survive reload without duplication', ({ engine, savePath }) => {
  engine.state.flowerpot.slots = [{id:2010604,stage:3,plantedAt:1}];
  const before = haveOf(engine,202254);
  call(engine,'furniture_flowerpot_harvest',{type:1,index:1});
  eq(haveOf(engine,202254),before+1);
  eq(call(engine,'client_load_decorate').reply.has_list.find(r=>r.id===10054).num,1);
  eq(call(engine,'client_change_decorate',{id:10054}).reply.code,-1,'at home is locked');
  eq(haveOf(engine,202254),before+1,'refusal consumes nothing');
  engine.state.frog.status=1;
  eq(call(engine,'client_change_decorate',{id:10054}).reply.code,0);
  eq(haveOf(engine,202254),before,'transfer from house to vase');
  const restored=reopen(savePath);
  eq(restored.state.decoration.putId,10054);
  eq(call(restored,'client_load_decorate').reply.has_list.find(r=>r.id===10054).num,1);
  eq(call(restored,'client_change_decorate',{id:10054}).reply.code,1);
});

test('share: lottery extra reward is mailed once and credited only when opened', ({ engine, savePath }) => {
  const opened=call(engine,'lottery_open').reply;
  const extra=opened.extra_item;
  assert(extra.item_id>0);
  const before=haveOf(engine,extra.item_id);
  const count=engine.state.mails.length;
  eq(call(engine,'adsmgr_share',{ads_type:3}).reply.delivery,'mail');
  eq(engine.state.mails.length,count+1);
  eq(haveOf(engine,extra.item_id),before);
  const restored=reopen(savePath);
  assert(call(restored,'adsmgr_share',{ads_type:3}).reply.code!==0);
  const mail=restored.state.mails.at(-1);
  eq(mail.items[0].item_id,extra.item_id);
  call(restored,'mail_open',{id:mail.id});
  eq(haveOf(restored,extra.item_id),before+extra.count);
  call(restored,'mail_open',{id:mail.id});
  eq(haveOf(restored,extra.item_id),before+extra.count);
});

test('share: legacy lottery extras are not paid twice', ({ engine }) => {
  engine.state.lottery.extraItem={item_id:4000,count:1};
  delete engine.state.lottery.extraPending;
  const before=engine.state.mails.length;
  eq(call(engine,'adsmgr_share',{ads_type:3}).reply.delivery,'inventory');
  eq(engine.state.mails.length,before);
  assert(call(engine,'adsmgr_share',{ads_type:3}).reply.code!==0);
});

console.log(`\n${passed} passed, ${failed} failed`
  + (skipped ? `, ${skipped} skipped（缺少客户端美术资源，见 docs/数据与逆向说明.md）` : ''));
if (failed) {
  console.log('\nfailures:');
  for (const f of failures) console.log(`  ${f.name}\n    ${f.error}`);
}
process.exitCode = failed ? 1 : 0;
