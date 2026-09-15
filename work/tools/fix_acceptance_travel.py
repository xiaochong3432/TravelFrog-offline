#!/usr/bin/env python3
"""The acceptance probe's round-trip check must pack the bag first.

The engine now waits at home while the bag is empty (players reported the frog leaving with
nothing prepared), so `nextDepartAt = 1; tick()` no longer departs. Pack a lunch box -- the
same thing the unit tests do -- and assert BOTH halves of the new rule while we are here.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

P = str(PROJECT_ROOT) + "/work/probe/acceptance.js"
src = io.open(P, encoding="utf-8").read()
old = """  ok('travel_round_trip', function () {
    eng.state.travel.nextDepartAt = 1;
    eng.tick();
    var away = eng.state.frog.status === 1;
    eng.state.travel.returnAt = 1;
    eng.tick();
    return away && eng.state.frog.status === 0;
  });"""
new = """  ok('travel_round_trip', function () {
    // 没准备就不出门: with an empty bag the frog must STAY home (that is the rule the
    // players asked for), so check that first and then pack something to actually go.
    eng.state.items.bag = [-1, -1, -1, -1];
    eng.state.travel.nextDepartAt = 1;
    eng.tick();
    var stayedHome = eng.state.frog.status === 0 && !!eng.state.travel.waitingForBag;

    var lunch = null;
    var items = eng.dispatch('item_load_items', {}).reply;
    // any LunchBox row the player owns; otherwise use the first food row there is
    var house = (items && items.house) || [];
    for (var i = 0; i < house.length; i++) {
      if (house[i] && house[i].count > 0) { lunch = Number(house[i].item_id); break; }
    }
    if (lunch === null) lunch = 1001;             // 岩壁·素 fallback from the seed row set
    eng.state.items.bag[0] = lunch;
    eng.state.travel.nextDepartAt = 1;
    eng.tick();
    var away = eng.state.frog.status === 1;
    eng.state.travel.returnAt = 1;
    eng.tick();
    return stayedHome && away && eng.state.frog.status === 0;
  });"""
assert src.count(old) == 1, "travel check not found"
io.open(P, "w", encoding="utf-8").write(src.replace(old, new))
print("acceptance travel check updated")
