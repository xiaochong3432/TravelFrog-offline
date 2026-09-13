#!/usr/bin/env python3
"""Slower travel pacing, and the frog now waits until the bag is prepared.

Two player reports:
  1. 旅行节奏稍微有点快了  -- the offline defaults were 90-240 s out / 20-45 s at home,
     against the original's 6-72 h. Slower now, but still playable in a sitting;
     FROG_FAITHFUL=1 still restores the recovered values.
  2. 没有做准备也会出门旅行 -- `tick()` called departFrog() on a timer regardless of the
     bag, so a frog with an empty bag left anyway and came back with nothing (that is the
     engine's stray-trip path). The frog now WAITS at home while there is nothing packed.
     This is OUR rule, not a recovered one: the original let it leave and simply sent it
     stray (放浪), which is still what happens when the bag holds tools but no lunch box.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

P = str(PROJECT_ROOT) + "/work/run/engine/index.js"
src = io.open(P, encoding="utf-8").read()
edits = []


def sub(old, new, label):
    global src
    n = src.count(old)
    assert n == 1, "%s: expected 1 match, found %d" % (label, n)
    src = src.replace(old, new)
    edits.append(label)


sub("""// Offline pacing: the live game used 6-72h trips (TRAVEL_TIME_MIN = 60 in
// define.json is the floor of the original unit). The default is deliberately
// short so the game is playable in a sitting; FROG_FAITHFUL=1 restores the
// recovered values, and the env vars always win.
const TRAVEL_MIN_SEC = pace('FROG_TRAVEL_MIN', 90, ORIG.travelTimeMin * 60);""",
    """// Offline pacing: the live game used 6-72h trips (TRAVEL_TIME_MIN = 60 in
// define.json is the floor of the original unit). The offline default used to be
// 90-240 s, which players reported as "a bit fast"; it is now 12-40 minutes, so a trip
// feels like a trip while a session can still see it leave and come back.
// FROG_FAITHFUL=1 restores the recovered values, and the env vars always win.
const TRAVEL_MIN_SEC = pace('FROG_TRAVEL_MIN', 12 * 60, ORIG.travelTimeMin * 60);""",
    "travel floor 12 min")

sub("""const TRAVEL_MAX_SEC = pace('FROG_TRAVEL_MAX', 240, ORIG.travelTimeMin * 60 * 6);
// How long the frog waits at home before heading out again.
const TRAVEL_IDLE_MIN = pace('FROG_IDLE_MIN', 20, ORIG.standbyWaitMin);
const TRAVEL_IDLE_MAX = pace('FROG_IDLE_MAX', 45, ORIG.restTick);""",
    """const TRAVEL_MAX_SEC = pace('FROG_TRAVEL_MAX', 40 * 60, ORIG.travelTimeMin * 60 * 6);
// How long the frog waits at home before heading out again.
const TRAVEL_IDLE_MIN = pace('FROG_IDLE_MIN', 2 * 60, ORIG.standbyWaitMin);
const TRAVEL_IDLE_MAX = pace('FROG_IDLE_MAX', 6 * 60, ORIG.restTick);
/* 没准备就不出门 (OUR rule, see the file header note): while the bag is empty the frog
   stays home, and it re-checks on this interval instead of leaving. */
const TRAVEL_WAIT_UNPREPARED_MIN = pace('FROG_WAIT_MIN', 3 * 60, ORIG.standbyWaitMin);
const TRAVEL_WAIT_UNPREPARED_MAX = pace('FROG_WAIT_MAX', 8 * 60, ORIG.restTick);""",
    "travel ceiling 40 min + home waits + unprepared wait")

sub("""      } else if (t >= state.travel.nextDepartAt) {
        departFrog(ctx, t);
      }""",
    """      } else if (t >= state.travel.nextDepartAt) {
        /* 没准备就不出门: `provisionTrip()` turns an empty bag into a 放浪 trip that
           brings nothing home, so the frog waits here until SOMETHING is packed -- a bag
           item, or a lunch box set out on the desk. The client's own bag/desk UI is where
           the player prepares, and the save editor has 立刻出门 for going out regardless. */
        if (tripPrepared()) {
          departFrog(ctx, t);
        } else {
          state.travel.waitingForBag = true;
          state.travel.nextDepartAt = t
            + randInt(TRAVEL_WAIT_UNPREPARED_MIN, TRAVEL_WAIT_UNPREPARED_MAX);
          save();
        }
      }""",
    "the frog waits while the bag is empty")

sub("""  function departFrog(ctx, t) {""",
    """  /** Is there anything to travel with? A packed bag, or a lunch box on the desk. */
  function tripPrepared() {
    if ((state.items.bag || []).some((id) => id !== -1 && id !== null && id !== undefined)) {
      return true;
    }
    return (state.items.desk || []).some((id) => isType(id, ITEM_TYPE_LUNCHBOX));
  }

  function departFrog(ctx, t) {
    state.travel.waitingForBag = false;""",
    "tripPrepared helper")

io.open(P, "w", encoding="utf-8").write(src)
print("applied:", ", ".join(edits))
