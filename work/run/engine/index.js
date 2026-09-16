'use strict';
/**
 * Offline engine for 《旅行青蛙·中国之旅》.
 *
 * Shared by both delivery routes:
 *   Route A - server/main.js wraps this behind a WebSocket server.
 *   Route B - the same module is inlined into the client, replacing core.SocketManage.
 *
 * Wire commands arrive dotted ("client.load_role"); handlers are keyed by the
 * client's underscore names (matching ProtocolList / addProtocolCallback).
 */
const fs = require('fs');
const path = require('path');
const protocol = require('./protocol');

/* Data tables scraped from the client's own loaded DBs (see
   work/tools/extract_gamedata.py). */
let gamedata = { tables: {}, items: [] };
try {
  gamedata = require('./data/gamedata.json');
} catch (e) {
  console.warn('[engine] gamedata.json missing - travel rewards will be limited');
}
const ITEM_TYPE_SPECIALTY = 3;

/* Tabikaeru.Define -- the original server's tuning table that shipped inside the
   client (see README). First consumer: the four-leaf-clover item id. */
let defineData = { scalars: {}, maps: {} };
try {
  defineData = require('./data/define.json');
} catch (e) {
  console.warn('[engine] define.json missing - falling back to built-in defaults');
}
const DEF = (name, fallback) => (
  defineData.scalars && defineData.scalars[name] !== undefined
    ? defineData.scalars[name] : fallback
);

/* ---------------------------------------------------------------------------
   FROG_FAITHFUL -- use the ORIGINAL timings instead of the shortened ones.

   define.json is the original server's own tuning table, and it still contains
   the real pacing values -- which we had been leaving UNUSED while inventing our
   own. A values audit found 70 of its 85 scalars unread, these among them. The
   shortened defaults exist so the game is playable in one sitting; with
   FROG_FAITHFUL=1 every one of them is replaced by the recovered value.

   | what                | original (define.json)             | offline default |
   |---------------------|------------------------------------|-----------------|
   | visitor cooldown    | FRIEND_VISIT_COOL = 21600 (6 h)    | 300 s           |
   | visitor arrival     | RNDPER 10 / RNDSEC 1800            | 60 s roll       |
   | travel length       | TRAVEL_TIME_MIN = 60               | 90-240 s        |
   | stray (放浪) return | FROG_DRIFTRETURNTIME 10 / MAX 20   | same            |
   | frog rest           | FROG_RESTTIME 400 / MAX 900        | 20-45 s         |
   | standby wait        | FROG_STANDBY_WAIT_MIN = 60         | 20-45 s         |
   | rest tick           | REST_TIME = 180                    | (unused)        |
   | clover withering    | CloverDestroyTime = 0.6            | (was missing)   |
   --------------------------------------------------------------------------- */
const FAITHFUL = ['1', 'true', 'yes'].indexOf(
  String(process.env.FROG_FAITHFUL || '').toLowerCase()) !== -1;
/** Original values, read from the table (fallbacks repeat the table's numbers). */
const ORIG = {
  friendVisitCool: DEF('FRIEND_VISIT_COOL', 21600),
  friendVisitRndPer: DEF('FRIEND_VISIT_RNDPER', 10),
  friendVisitRndSec: DEF('FRIEND_VISIT_RNDSEC', 1800),
  friendVisitActMin: DEF('FRIEND_VISIT_ACTCOUNT_MIN', 6),
  friendVisitActMax: DEF('FRIEND_VISIT_ACTCOUNT_MAX', 8),
  travelTimeMin: DEF('TRAVEL_TIME_MIN', 60),
  driftReturn: DEF('FROG_DRIFTRETURNTIME', 10),
  driftReturnMax: DEF('FROG_DRIFTRETURNTIME_MAX', 20),
  restTime: DEF('FROG_RESTTIME', 400),
  restTimeMax: DEF('FROG_RESTTIME_MAX', 900),
  standbyWaitMin: DEF('FROG_STANDBY_WAIT_MIN', 60),
  restTick: DEF('REST_TIME', 180),
  cloverDestroy: DEF('CloverDestroyTime', 0.6),
  bagItems: DEF('BAGITEMS', 4),
  deskItems: DEF('DESKITEMS', 8),
  startClover: DEF('StartCloverPoint', 9999),
  mailMax: DEF('MAIL_MAX', 100),
  haveItemMax: DEF('HaveItemMax', 99),
  detourMax: DEF('DetourMax', 3),
};
/** Pick the faithful value or the offline one; an explicit env var always wins. */
const pace = (envName, offlineDefault, original) => Number(
  process.env[envName] !== undefined ? process.env[envName]
    : (FAITHFUL ? original : offlineDefault));

/* Precomputed postcard `layers`, keyed by Picture-table id (built by
   work/tools/build_picture_layers.py).

   Why this file exists: the CLIENT ONLY RENDERS, it never composes. Its album
   code does

       bmp.texture = RES.getRes(basename(ResourcesDB[layer[0]]) + "_png")
       bmp.x = layer[1];  bmp.y = layer[2]
       drawToTexture(container, new Rectangle(0, 0, 500, 350))

   -- array order is draw order, canvas is 500x350, and `ResourcesDB` is
   data/tables/resources.json. So a postcard without `layers` is a blank cell,
   and the composition itself lived only on the (now dead) server.

   We reconstruct it from the Picture table's own columns (backImage /
   frontImage / frogPose / frogPos / travelerPos) plus the shipped art. That is
   a RECONSTRUCTION validated by looking at rendered output, not a recovered
   original. frogPos/travelerPos are centre-relative (see the builder).

   Layers are NOT persisted in the save: they are a pure function of pic_id, so
   hydrating at reply time keeps saves small and cannot go stale. */
let pictureLayers = {};
try {
  pictureLayers = require('./data/picture-layers.json');
} catch (e) {
  console.warn('[engine] picture-layers.json missing - postcards will render blank');
}

/** Attach the composed `layers` for a postcard's pic_id. */
function withLayers(p) {
  if (!p) return p;
  const rec = pictureLayers[String(p.pic_id)];
  if (!rec) return p;
  const out = Object.assign({}, p, { layers: rec.layers });
  if (rec.travelers) out.travelers = rec.travelers;
  return out;
}



/* =========================================================================
   目的地系统 —— TravelData 6 张表 + Item.effects

   这一切在客户端里根本不存在：main.min.js 搜 `TravelData` 0 命中，搜
   AREA_DECIDE 只命中 Item.EffectType 那个枚举（客户端会把"这个食物会去哪儿"
   显示给玩家，但从不结算）。所以地图算法原本只在服务器上，本文件就是把它补回来。

   数据（本地已归档，work/cdn/live/1020_1021/resource/China/config/）：
     TravelData/Area.json        17 个区域，带 id 区间 —— 也正是 effects 里
                                 AREA_DECIDE / AREA_STEP 的取值空间
     TravelData/Node.json        373 个点：nodeType -1/0 普通、1 = 终点(34 个，
                                 与 NodeGoal 一一对应)、2/3 岔路/特殊路段
     TravelData/NodeConnect.json 邻接表（edge 列相邻点）
     TravelData/NodeEdge.json    按"抵达该点"索引 1:1：耗时 time、特殊路段加时
                                 plusTime、wayType(0 普通 / 1 洞穴 / 2 海 / 3 山)、
                                 三类照片标签及其权重、遭遇伙伴、笔记 id
     TravelData/NodeGoal.json    34 个终点（29 省市 + 5 座博物馆）
     TravelData/NodeItem.json    每个点的特产/典藏/装饰掉落
     MainData/Item.json          181 行的 effects（客户端自己的 411 行 Item 没有
                                 这一列，这是服务端独有的表）

   连接键（都在本地表里闭合）：
     NodeEdge 的 65 个照片标签 65/65 命中 PictureTag.Tag，picNames 就是 Picture.name；
     终点点的 picTag(g_beijing) == 客户端 GoalNumber.tag；
     Picture.type=='Goal' 且 place==GoalNumber.id 就是目的地照（5 座博物馆是 100..104）。
   ========================================================================= */
let travelMap = { areas: [], nodes: {}, connect: {}, edges: {}, goals: [], nodeItems: {}, effects: {} };
try {
  travelMap = require('./data/travel.json');
} catch (e) {
  console.warn('[engine] data/travel.json missing - trips fall back to uniform rewards');
}

/** Is the destination map usable? When not, the old uniform roll still runs. */
const TV_OK = !!(travelMap && Array.isArray(travelMap.areas) && travelMap.areas.length
  && travelMap.nodes && Object.keys(travelMap.nodes).length);

const TV_AREAS = (travelMap.areas || []).slice();
const TV_AREA_BY_NAME = {};
const TV_AREA_BY_ID = {};
TV_AREAS.forEach((a) => { TV_AREA_BY_NAME[a.name] = a; TV_AREA_BY_ID[a.id] = a; });

const TV_NODES = travelMap.nodes || {};
const TV_CONNECT = travelMap.connect || {};
const TV_EDGES = travelMap.edges || {};
const TV_NODE_ITEMS = travelMap.nodeItems || {};
const TV_EFFECTS = travelMap.effects || {};

const TV_GOALS = (travelMap.goals || []).slice();
const TV_GOAL_BY_NODE = {};
TV_GOALS.forEach((g) => { TV_GOAL_BY_NODE[String(g.node)] = g; });

/** area id -> the node ids inside the Area table's own id range. */
const TV_AREA_NODES = {};
Object.keys(TV_NODES).forEach((k) => {
  const id = Number(k);
  for (let i = 0; i < TV_AREAS.length; i++) {
    const a = TV_AREAS[i];
    if (id >= a.start && id <= a.end) {
      if (!TV_AREA_NODES[a.id]) TV_AREA_NODES[a.id] = [];
      TV_AREA_NODES[a.id].push(id);
      break;
    }
  }
});

/* wayType -> the EVT_WAY family that unlocks it. DERIVED, not guessed: every
   cave edge (wayType 1) carries ToolsTag p_fuza, sea (2) p_wet, mountain (3)
   p_dry, and the tools' own effects are EVT_WAY E_CAVE (竹筒/葫芦/水壶),
   E_SEA (纸伞), E_MOUNTAIN (睡垫), E_NORMAL (围巾). */
const TV_WAY_TYPE = { 1: 'E_CAVE', 2: 'E_SEA', 3: 'E_MOUNTAIN' };

/** Walkable neighbours. `NodeConnect.edge` stores an edge as a PAIR on ONE
    endpoint's row (node 12001 -> [12000, 12001]) and occasionally a lone self
    entry, so adjacency is the union of both directions. Reading it one-way only
    reaches the goal node in 10 of the 17 areas (all five museums are dead ends
    that way); the union reaches all 17, which is how the reading was pinned down
    (work/tools/analyze_traveldata2.py). */
const TV_NBR = {};
(function tvIndexNeighbours() {
  Object.keys(TV_CONNECT).forEach((k) => {
    const n = Number(k);
    (TV_CONNECT[k] || []).forEach((x) => {
      if (x === n || !TV_NODES[String(x)]) return;
      if (!TV_NBR[n]) TV_NBR[n] = {};
      if (!TV_NBR[x]) TV_NBR[x] = {};
      TV_NBR[n][x] = true;
      TV_NBR[x][n] = true;
    });
  });
})();

/** How many steps a trip may take at most. 【自设计】: the tables give per-edge
    times and per-tool extras but no base count -- and the time budget is the real
    limit (an average edge costs 30 of the 60..172 minutes a trip gets). */
const TV_BASE_STEPS = Number(process.env.FROG_TRAVEL_STEPS || 14);

/** How far into the walk a goal node counts as "arrived". 【自设计】: the goal of
    some areas is adjacent to the entry (A_NORTH's 北京 is node 1, next to the entry
    node 0), and ending there would make every north trip a single step. */
const TV_GOAL_MIN_STEPS = Number(process.env.FROG_TRAVEL_GOAL_STEPS || 3);

/** Walk budget = Define.TRAVEL_TIME_MIN x this. 【自设计·口径】: the map's edge times
    are minutes (3..90) and a route across one area costs 150-300 of them, while
    TRAVEL_TIME_MIN = 60 is the original's per-trip MINIMUM -- with a factor of 1 a
    trip would end after two steps and the whole NodeEdge table would be moot. The
    lunch's HP still scales it (see tvPacePct). */
const TV_WALK_MINUTES = Number(process.env.FROG_TRAVEL_MINUTES || 3);

/** A gamedata table as a row list. The scraped tables are arrays for some names
    and {id: row} objects for others, so every reader goes through this. */
function tvRows(name) {
  const t = gamedata.tables && gamedata.tables[name];
  if (!t) return [];
  if (Array.isArray(t)) return t;
  return Object.keys(t).map((k) => t[k]).filter((r) => r && typeof r === 'object');
}

/** tag -> Picture ids (PictureTag.picNames are Picture.name), and the reverse. */
const TV_TAG_PICS = {};
const TV_PIC_TAG = {};
(function tvIndexPictures() {
  const byName = {};
  tvRows('Picture').forEach((p) => { if (p && p.name !== undefined) byName[p.name] = p.id; });
  tvRows('PictureTag').forEach((t) => {
    const ids = [];
    (t.picNames || []).forEach((n) => {
      const id = byName[n];
      if (id !== undefined && ids.indexOf(id) === -1) ids.push(id);
    });
    if (!ids.length) return;
    TV_TAG_PICS[String(t.Tag)] = ids;
    ids.forEach((id) => { TV_PIC_TAG[id] = String(t.Tag); });
  });
})();

/** GoalNumber id -> the destination postcards (Picture.place is that id). */
const TV_GOAL_PICS = {};
(function tvIndexGoalPics() {
  tvRows('Picture').forEach((p) => {
    if (!p || String(p.type) !== 'Goal') return;
    if (p.place === undefined || p.place === null) return;
    const k = String(p.place);
    if (!TV_GOAL_PICS[k]) TV_GOAL_PICS[k] = [];
    TV_GOAL_PICS[k].push(p.id);
  });
})();

/** 地区名 -> Specialty itemIds / Collection ids (the CLIENT's own tables). */
const TV_SP_BY_PLACE = {};
const TV_COL_BY_PLACE = {};
(function tvIndexPlaces() {
  tvRows('Specialty').forEach((r) => {
    if (!r.place) return;
    if (!TV_SP_BY_PLACE[r.place]) TV_SP_BY_PLACE[r.place] = [];
    TV_SP_BY_PLACE[r.place].push(Number(r.itemId));
  });
  tvRows('Collection').forEach((r) => {
    if (!r.place) return;
    if (!TV_COL_BY_PLACE[r.place]) TV_COL_BY_PLACE[r.place] = [];
    TV_COL_BY_PLACE[r.place].push(Number(r.id));
  });
})();

/** Note ids that exist in the client's Note table (an unknown id is dropped by
    TravelNoteModel.travel_load_note, so it must never be handed out). */
const TV_NOTE_IDS = (function () {
  const out = {};
  tvRows('Note').forEach((r) => { out[Number(r.id)] = true; });
  return out;
})();

/** 彩叶幸运草 (550 草, Item 1200, consumable amulet). It has NO row in the CN
    effect table -- it is the one mechanic the guide describes that only exists as
    server logic: carried on a trip it fills a GAP in a postcard series the player
    already owns (PictureTag.picNames is exactly that series). */
const TV_LUCKY_CLOVER_ID = 1200;

/** 博物馆门票 1017..1021 -- the amulets whose only effect is `AREA_DECIDE
    A_BWG_*`, i.e. "this trip goes to that museum". */
const TV_MUSEUM_TICKETS = Object.keys(TV_EFFECTS)
  .map(Number)
  .filter((id) => TV_EFFECTS[String(id)].some(
    (e) => e[0] === 'AREA_DECIDE' && String(e[1]).indexOf('A_BWG_') === 0))
  .sort((a, b) => a - b);

/** Effects of one item, as [{effect, effectType, effectValue}]. */
function tvEffects(itemId) { return TV_EFFECTS[String(itemId)] || []; }

/* Effect conversion table -- every reading sits here, so nothing is buried:
     HP / H_MAXTIME, H_UP, H_UP_RND  -> trip minutes. Define.BASE_HP = 100 is the
                                        anchor; the values are 6..72, i.e. percents.
     WAY_SPEED / W_ALL, W_<FAMILY>   -> percent faster on that route family
     WAY_STEP  / W_<FAMILY>          -> extra steps (10 / 12 / 20)
     COST_STEP / W_ALL               -> percent cheaper steps
     AREA_DECIDE / A_<AREA>          -> destination weight (80 = strongly pulled)
     AREA_DECIDE / A_NEW_AREA        -> weight for areas not yet visited
     AREA_STEP   / A_<AREA>          -> percent more steps inside that area
     DETOUR_STEP                     -> extra steps (Define.DetourMax caps it)
     ITEM_PERCENT / I_CLOVER,RND     -> chance of one more clover  【自设计·换算】
     ITEM_PERCENT / I_TICKET         -> chance of one more ticket  【自设计·换算】
     ITEM_PERCENT / I_UP             -> extra souvenir rolls       【自设计·换算】
     EVT_WAY / E_*                   -> unlocks that route family
     FLAG_ITEM / FL_*                -> recorded on the trip (rare/province flags)
     GET_REWARD / DROP_ID            -> NOT implemented: it indexes a server drop
                                        table this archive does not have (the same
                                        space as NodeItem.drop 301/602/...)
     FRIENDSHIP, TRAVELER_STEP       -> left to the existing visitor / 伴蛙前行 code */
function tvSum(effects, effect, kind) {
  let out = 0;
  for (let i = 0; i < effects.length; i++) {
    const e = effects[i];
    if (e[0] !== effect) continue;
    if (kind && e[1] !== kind) continue;
    out += Number(e[2] || 0);
  }
  return out;
}

/** Every effect of everything the frog carried. */
function tvCarriedEffects(carried) {
  const out = [];
  (carried || []).forEach((id) => {
    if (!(Number(id) > 0)) return;
    tvEffects(Number(id)).forEach((e) => out.push(e));
  });
  return out;
}

/** The museum area a 门票 forces, or '' when none is carried. A ticket's ONLY
    effect is AREA_DECIDE with a NEGATIVE value (-2), which cannot be a weight, so
    the reading is 【自设计】: a ticket pins the trip to its own museum. */
function tvTicketArea(carried) {
  let area = '';
  tvCarriedEffects(carried).forEach((e) => {
    if (e[0] === 'AREA_DECIDE' && String(e[1]).indexOf('A_BWG_') === 0) area = String(e[1]);
  });
  return area;
}

/** Percent the packed lunch adds to the travel window (H_MAXTIME + H_UP, with
    H_UP_RND counted at half -- it is the random variant). */
function tvPacePct(carried) {
  const ef = tvCarriedEffects(carried);
  return tvSum(ef, 'HP', 'H_MAXTIME') + tvSum(ef, 'HP', 'H_UP')
    + tvSum(ef, 'HP', 'H_UP_RND') / 2;
}

/** Same contract as the engine's own `randInt`, which lives INSIDE createEngine
    -- a scope these map helpers cannot see. Kept identical on purpose. */
function tvRand(a, b) {
  const lo = Math.min(a, b);
  const hi = Math.max(a, b);
  return lo + Math.floor(Math.random() * (hi - lo + 1));
}

function tvWeighted(pairs) {
  let total = 0;
  for (let i = 0; i < pairs.length; i++) total += Math.max(0, pairs[i][1]);
  if (total <= 0) return null;
  let roll = Math.random() * total;
  for (let i = 0; i < pairs.length; i++) {
    roll -= Math.max(0, pairs[i][1]);
    if (roll <= 0) return pairs[i][0];
  }
  return pairs[pairs.length - 1][0];
}

/** The entry point of an area: its nodeType -1 node when it has one (every area
    starts with one), else the ordinary node with the smallest pathPoint. */
function tvStartNode(areaId) {
  const ids = TV_AREA_NODES[areaId] || [];
  let best = -1;
  let bestKey = null;
  for (let i = 0; i < ids.length; i++) {
    const n = TV_NODES[String(ids[i])];
    if (!n) continue;
    const key = [n[0] === -1 ? 0 : 1, n[1]];
    if (!bestKey || key[0] < bestKey[0] || (key[0] === bestKey[0] && key[1] < bestKey[1])) {
      bestKey = key;
      best = ids[i];
    }
  }
  return best;
}

/** Where to go: AREA_DECIDE weights, or the ticket's museum. */
function tvPickArea(effects, visited, ticketArea) {
  const weights = [];
  for (let i = 0; i < TV_AREAS.length; i++) {
    const a = TV_AREAS[i];
    const museum = a.name.indexOf('A_BWG_') === 0;
    if (museum) {
      if (a.name === ticketArea) weights.push([a.id, 100]);
      continue;                            // museums are ticket-only
    }
    if (!(TV_AREA_NODES[a.id] || []).length) continue;
    /* Base 1 per area, so an AREA_DECIDE value reads as the table's percentages do
       everywhere else (HP 72, ITEM_PERCENT 10..50, WAY_SPEED 20..50): 80 means
       "this area wins overwhelmingly", 50 (A_NEW_AREA) "probably somewhere new". */
    let w = 1;
    for (let j = 0; j < effects.length; j++) {
      const e = effects[j];
      if (e[0] !== 'AREA_DECIDE') continue;
      const v = Number(e[2] || 0);
      if (e[1] === a.name) w += v;
      else if (e[1] === 'A_NEW_AREA' && !visited[a.name]) w += v;
    }
    weights.push([a.id, w]);
  }
  return tvWeighted(weights);
}

/** Walk the route. `minutes` is the budget the lunch pays for; every arrival
    costs its own NodeEdge.time (+plusTime for cave/sea/mountain stretches, which
    only a matching tool -- or a museum ticket, see `opts.ticket` -- can enter). */
function tvWalk(areaId, effects, minutes, opts) {
  const ticketPass = !!(opts && opts.ticket);
  const fam = {};
  effects.forEach((e) => {
    if (e[0] === 'EVT_WAY') fam[e[1]] = Math.max(fam[e[1]] || 0, Number(e[2] || 0));
  });
  const speedOf = (way) => {
    let pct = tvSum(effects, 'WAY_SPEED', 'W_ALL');
    const evt = TV_WAY_TYPE[way];
    if (evt) pct = Math.max(pct, tvSum(effects, 'WAY_SPEED', 'W_' + evt.slice(2)));
    return Math.max(0, Math.min(90, pct));
  };
  let extra = tvSum(effects, 'WAY_STEP', 'W_ALL');
  [1, 2, 3].forEach((w) => {
    const evt = TV_WAY_TYPE[w];
    if (evt && fam[evt]) extra += tvSum(effects, 'WAY_STEP', 'W_' + evt.slice(2));
  });
  const costPct = tvSum(effects, 'COST_STEP', 'W_ALL');
  const areaName = TV_AREA_BY_ID[areaId] ? TV_AREA_BY_ID[areaId].name : '';
  const areaStep = areaName ? tvSum(effects, 'AREA_STEP', areaName) : 0;
  const detour = Math.min(Number(DEF('DetourMax', 3)),
    Math.round(tvSum(effects, 'DETOUR_STEP', 'DETOUR_STEP') / 100));
  const maxSteps = Math.max(2, Math.round(
    (TV_BASE_STEPS + extra + detour * 2) * (1 + (costPct + areaStep) / 100)));
  const areaRow = TV_AREA_BY_ID[areaId] || { start: -Infinity, end: Infinity };
  const areaStart = areaRow.start;
  const areaEnd = areaRow.end;

  const path = [];
  const seen = {};
  let node = tvStartNode(areaId);
  let used = 0;
  let firstGoal = null;
  if (node >= 0) seen[String(node)] = true;
  while (node >= 0 && path.length < maxSteps) {
    const cands = Object.keys(TV_NBR[String(node)] || {}).map(Number).filter((n) => {
      if (n === node || seen[String(n)] || !TV_NODES[String(n)]) return false;
      /* Stay inside the chosen area: the areas are adjacent in the id space, so
         without this the frog would wander into a neighbouring region and bring
         back souvenirs that area cannot drop. */
      if (n < areaStart || n > areaEnd) return false;
      const e = TV_EDGES[String(n)];
      const w = e ? e.w : 0;
      if (!w) return true;
      const evt = TV_WAY_TYPE[w];
      /* A special stretch needs its tool -- or the museum ticket that pinned this
         trip 【自设计】: every museum's own route contains one (江西省博物馆 arrives
         at node 12007 over a wayType-2 stretch), and a visit must not require the
         player to also pack a 纸伞. */
      return !!(evt && (fam[evt] || ticketPass));
    });
    if (!cands.length) break;
    /* A packed tool is meant to be USED: when a stretch of its own route family is
       on offer, take it most of the time -- otherwise the frog always picks the
       biggest pathPoint and a 睡垫 never actually leads up a mountain (measured:
       2 of 300 trips before this rule). */
    const special = cands.filter((n) => {
      const e = TV_EDGES[String(n)];
      return !!(e && e.w && TV_WAY_TYPE[e.w]);
    });
    let pick = cands[0];
    if (special.length && Math.random() < 0.7) {
      pick = special[tvRand(0, special.length - 1)];
    } else if (cands.length > 1) {
      /* Otherwise prefer the neighbour with the larger pathPoint (further along
         the route) 8 times out of 10 -- a walk can oscillate between two nodes. */
      const sorted = cands.slice().sort(
        (a, b) => (TV_NODES[String(b)][1] || 0) - (TV_NODES[String(a)][1] || 0));
      pick = Math.random() < 0.8 ? sorted[0] : cands[tvRand(0, cands.length - 1)];
    }
    const e = TV_EDGES[String(pick)]
      || { t: 30, pt: 0, w: 0, n: '', p: '', u: '', np: 0, pp: 0, up: 0, no: [] };
    const speed = speedOf(e.w) / 100;
    const base = Number(e.t || 0) * (1 - speed);
    const cost = (Number(e.t || 0) + Number(e.pt || 0)) * (1 - speed);
    /* The ENTRY decision uses the plain travel time: `plusTime` is the surcharge a
       cave/sea/mountain detour adds (90..120), and letting it block entry meant a
       tool could never actually take its own route (the budget is 60..172 min). */
    if (path.length && used + base > minutes) break;
    used += cost;
    path.push({ from: node, node: pick, e });
    seen[String(pick)] = true;
    node = pick;
    /* The FIRST goal node the walk touches is the trip's destination. In most areas
       that is the 终点 row itself, but in A_NORTH the goal (北京, node 1) sits right
       next to the entry (node 0), so arriving there must not end a one-step trip:
       the frog arrives at its city and then keeps wandering, and the trip ends on
       the budget (or when a goal is reached after a real walk). */
    const goalRow = TV_GOAL_BY_NODE[String(pick)];
    if (goalRow && !firstGoal) firstGoal = goalRow;
    if (goalRow && path.length >= TV_GOAL_MIN_STEPS) break;
  }
  const goal = firstGoal;
  return { area: areaId, path, minutes: used, goal, families: fam };
}

/** A missing postcard from a series the player already started (彩叶幸运草). */
function tvGapPicture(ownedTags, trip) {
  const cands = [];
  Object.keys(TV_TAG_PICS).forEach((tag) => {
    const ids = TV_TAG_PICS[tag];
    const owned = ownedTags[tag] || [];
    if (!owned.length || owned.length >= ids.length) return;
    ids.forEach((id) => { if (owned.indexOf(id) === -1) cands.push([id, tag]); });
  });
  if (!cands.length) return null;
  const stepTags = [];
  trip.path.forEach((s) => {
    [s.e.n, s.e.p, s.e.u].forEach((t) => { if (t) stepTags.push(String(t)); });
  });
  const hit = cands.filter((c) => stepTags.indexOf(c[1]) !== -1);
  const pool = hit.length ? hit : cands;
  return pool[tvRand(0, pool.length - 1)][0];
}

/** The postcards a trip brings home: one per photo slot that rolls under its own
    NodeEdge weight, plus the mandatory 目的地照 on arrival. */
function tvPhotos(trip, wantFill, ownedTags) {
  const cap = Math.max(1, Number(DEF('PICTURE_GETMAX', 4)));
  const out = [];
  const add = (id) => {
    if (id === undefined || id === null) return;
    if (out.indexOf(id) === -1 && out.length < cap) out.push(id);
  };
  if (wantFill) {
    const gap = tvGapPicture(ownedTags, trip);
    if (gap !== null) add(gap);
  }
  trip.path.forEach((step) => {
    [['n', step.e.n, step.e.np], ['p', step.e.p, step.e.pp], ['u', step.e.u, step.e.up]]
      .forEach((slot) => {
        if (!slot[1] || out.length >= cap) return;
        if (Math.random() * 100 >= Number(slot[2] || 0)) return;
        const ids = TV_TAG_PICS[String(slot[1])] || [];
        if (ids.length) add(ids[tvRand(0, ids.length - 1)]);
      });
  });
  if (trip.goal) {
    const ids = (TV_TAG_PICS[String(trip.goal.picTag)] || [])
      .concat(TV_GOAL_PICS[String(trip.goal.place)] || []);
    const fresh = ids.filter((id) => out.indexOf(id) === -1);
    if (fresh.length) add(fresh[tvRand(0, fresh.length - 1)]);
  }
  if (!out.length && PICTURE_IDS.length) {
    /* A short trip can roll nothing at all; keep the old behaviour that a trip
       usually brings a photo (Define.BASE_PICTURE_PER). */
    if (Math.random() * 100 < Number(DEF('BASE_PICTURE_PER', 70))) {
      add(PICTURE_IDS[tvRand(0, PICTURE_IDS.length - 1)]);
    }
  }
  return out;
}

/** Souvenirs and 典藏 for the ground the frog actually covered. */
function tvSouvenirs(trip, effects, place, ownedCollections) {
  const items = [];
  const collections = [];
  const flagItems = [];
  const collectPer = Number(DEF('COLLECT_PER', [15])[0]);
  /* 纪念品/典藏: the destination decides which ones are even possible (the
     Collection table's own `place` column: 华北地区 / 江西省博物馆 / ...). A node
     whose NodeItem row carries `collection >= 0` is a node that CAN hand one out.
     When the area's place cannot be resolved, fall back to the whole table. */
  const byPlace = TV_COL_BY_PLACE[place] || [];
  const owned = ownedCollections || [];
  const fresh = byPlace.filter((id) => owned.indexOf(id) === -1);
  const pool = fresh.length ? fresh : (byPlace.length ? byPlace : COLLECTION_IDS);
  let collectionNode = false;
  /* The START node counts too: it is the area's entry and the frog sets off from
     there (A_NORTH's node 0 lists 京味点心 and a 纪念品), so its row has to be read
     as well as the rows of everything arrived at. */
  const walkNodes = [trip.path.length ? trip.path[0].from : -1]
    .concat(trip.path.map((s) => s.node));
  walkNodes.forEach((id) => {
    const ni = TV_NODE_ITEMS[String(id)];
    if (!ni) return;
    (ni.s || []).forEach((pair) => {
      if (!(Math.random() * 100 < Number(pair[1] || 0))) return;
      const item = Number(pair[0]);
      if (ITEM_BY_ID.has(item)) items.push(item);
    });
    /* `collection >= 0` marks a node that can hand a 纪念品 out at all; the roll
       itself is once per trip (Define.COLLECT_PER = 15), so passing more of those
       nodes does not multiply the odds. */
    if (ni.c >= 0) collectionNode = true;
  });
  if (collectionNode && pool.length && Math.random() * 100 < collectPer) {
    collections.push(pool[tvRand(0, pool.length - 1)]);
  }
  /* I_UP (四叶草 50) buys extra souvenirs from the destination's own list. */
  const bonus = Math.floor(tvSum(effects, 'ITEM_PERCENT', 'I_UP') / 50);
  const spPool = TV_SP_BY_PLACE[place] || [];
  for (let i = 0; i < bonus && spPool.length; i++) items.push(spPool[tvRand(0, spPool.length - 1)]);
  /* FLAG_ITEM rides on whatever we hand out (FL_RARE = 稀有特产, FL_<province>,
     FL_<crop> for the flowerpot produce) -- recorded so the save knows what has
     been seen. */
  items.forEach((id) => {
    tvEffects(id).forEach((e) => { if (e[0] === 'FLAG_ITEM') flagItems.push(String(e[1])); });
  });
  return { items, collections, flagItems };
}

/** The whole trip, map-driven. Returns null when the map is unusable.
    `opts.visitedAreas` = {A_NORTH: true, ...} for A_NEW_AREA, `opts.ownedTags` =
    {n_roof: [picture ids]} for 彩叶幸运草's gap fill. */
function tvRollTrip(plan, opts) {
  if (!TV_OK) return null;
  const carried = (plan && plan.carried) || [];
  const effects = tvCarriedEffects(carried);
  const visitedAreas = (opts && opts.visitedAreas) || {};
  const ticketArea = tvTicketArea(carried);
  let minutes = Math.max(10, Math.round(
    Number(DEF('TRAVEL_TIME_MIN', 60)) * TV_WALK_MINUTES
    * (1 + tvPacePct(carried) / 100)));
  /* 门票缩短旅行 【自设计·换算】: the ticket's only effect is AREA_DECIDE(-2), and the
     short museum route (10 steps, own time column) is what the visit actually is.
     So the WALK gets a floor big enough to arrive, while the window the player sees
     stays shortened -- a ticket trip is a short, targeted outing. */
  if (ticketArea) minutes = Math.max(minutes, 200);

  const areaId = ticketArea
    ? (TV_AREA_BY_NAME[ticketArea] || {}).id
    : tvPickArea(effects, visitedAreas, ticketArea);
  if (areaId === undefined || areaId === null) return null;

  const trip = tvWalk(areaId, effects, minutes, { ticket: !!ticketArea });
  const area = TV_AREA_BY_ID[areaId] || { name: '', place: '' };
  const place = area.place || '';

  const souv = tvSouvenirs(trip, effects, place,
    (opts && opts.ownedCollections) || []);
  const wantFill = carried.indexOf(TV_LUCKY_CLOVER_ID) !== -1;
  const ownedTags = (opts && opts.ownedTags) || {};
  const pictures = tvPhotos(trip, wantFill, ownedTags);

  const notes = [];
  trip.path.forEach((step) => {
    (step.e.no || []).forEach((id) => {
      if (TV_NOTE_IDS[id] && notes.indexOf(id) === -1 && notes.length < 3) notes.push(id);
    });
  });

  let clover = tvRand(1, 3);
  if (Math.random() * 100 < tvSum(effects, 'ITEM_PERCENT', 'I_CLOVER')) clover += 1;
  if (Math.random() * 100 < tvSum(effects, 'ITEM_PERCENT', 'I_CLOVER_RND')) clover += 1;
  /* The offline base chance stays what it was (45%); I_TICKET adds 10 points each. */
  const ticketPct = Math.min(90, 45 + 10 * tvSum(effects, 'ITEM_PERCENT', 'I_TICKET'));
  const ticket = Math.random() * 100 < ticketPct ? 1 : 0;

  return {
    clover, ticket, notes, pictures,
    items: souv.items, flags: souv.flagItems,
    collection: souv.collections.length ? souv.collections[0] : -1,
    area: area.name, areaId,
    place,
    goal: trip.goal ? { node: trip.goal.node, name: trip.goal.name, picTag: trip.goal.picTag } : null,
    steps: trip.path.length,
    minutes: Math.round(trip.minutes),
    museum: !!ticketArea,
    luckyFill: wantFill,
  };
}

/* ---- furniture reference tables (data/tables/*.json from config.eab) ----
   furnitureData      : {id -> {name, type (1..27 = 墙壁/地面/... slot), style, res}}
   furnitureShopData  : {id -> {item_id, price, limit, has_item, type, order}}
                        `item_id` is an ITEM id (tools are Item type 12),
                        `has_item` is the furniture id that must be owned first
                        (the shop's unlock chain). */
const FURNITURE_TABLE = (gamedata.tables && gamedata.tables.furnitureData) || {};
const FURNITURE_SHOP_TABLE = (gamedata.tables && gamedata.tables.furnitureShopData) || {};
const FURNITURE_BY_ID = new Map();
for (const k of Object.keys(FURNITURE_TABLE)) {
  const row = FURNITURE_TABLE[k];
  const id = Number((row && row.id) !== undefined ? row.id : k);
  if (Number.isFinite(id)) FURNITURE_BY_ID.set(id, row);
}
const FURNITURE_SHOP = new Map();
for (const k of Object.keys(FURNITURE_SHOP_TABLE)) {
  const row = FURNITURE_SHOP_TABLE[k];
  const id = Number((row && row.id) !== undefined ? row.id : k);
  if (Number.isFinite(id)) FURNITURE_SHOP.set(id, row);
}

/* ---- 套装 / 盲盒 (Item type 5) ----------------------------------------------
   The shop sells PACKAGES: furnitureShopData rows 1 and 2 carry item_id 5001
   (工具套装) and 5002 (材料套装) for 1 clover each, row 6 carries 5101 (种子盲盒).
   `GiftData` is the game's OWN table of what is inside them:

     5001 -> 10201,10202,10203,10204,10205   (the five workbench tools)
     5002 -> 10001..10007 + 10101            (the craft materials)
     5003 -> 20101,20102,20103               (seeds)

   A package is not usable itself, and the client CANNOT ask to open one:
   `item_gift_open` is registered with addProtocolCallback, i.e. PUSH-ONLY (there is
   no `send("item_gift_open")` anywhere in the bundle). The server therefore opens
   the box when it is acquired and pushes the contents, and the client shows them in
   GiftPackageView. We answered `item_gift_open` with `{}` and never pushed it, so a
   bought 套装 did nothing at all -- 「显示已购买，但背包里没有工具、材料也没增加」.

   【自设计】 the RANDOM boxes (5101-5105) have no GiftData row; their pools are the
   families the tables themselves imply: seeds from 5003's own list, 普通材料 =
   Item type 10, 特殊材料 = Item type 11, 野花野草 = the `decoration` rows a vase
   can hold. Each random box yields ONE row, matching GiftData's own 1-each shape. */
const GIFT_DATA = (gamedata.tables && gamedata.tables.GiftData) || {};
const SEED_IDS = (((GIFT_DATA['5003'] || {}).item_id) || []).map(Number);
const MATERIAL_IDS = gamedata.items.filter((i) => i.type === 10).map((i) => i.id);
const SPECIAL_MATERIAL_IDS = gamedata.items.filter((i) => i.type === 11).map((i) => i.id);
const FLOWER_IDS = Object.keys((gamedata.tables && gamedata.tables.decoration) || {}).map(Number);

/* Wire-parameter accessors.
 *
 * The client does NOT send free-form JSON: `SocketManage.send` maps positional
 * arguments onto the parameter names declared in ProtocolList --
 *     u.data = {}; for (p...) u.data[params[p]] = args[p];
 * -- so the ONLY correct key is the declared one. Every handler below used to
 * guess, and `furniture_buy_shop` reading `d.id` while the client sends
 * `{shop_id}` returned {code:-1} forever: the whole furniture merchant, welfare
 * goods included, was silently unbuyable and no unit test noticed, because the
 * tests called dispatch() with the shape the handler expected.
 *
 * These helpers read the DECLARED name and keep the old guess as a fallback, so
 * the client works and the existing tests keep passing.
 * `tools/audit_params.py` checks every handler against protocol.js. */
function firstDefined(d, names) {
  if (d === null || d === undefined) return undefined;
  for (const n of names) {
    if (d[n] !== undefined && d[n] !== null) return d[n];
  }
  return undefined;
}
/** `pos` is the declared name for every bench/box slot command (1-based). */
function posOf(d) { return Number(firstDefined(d, ['pos', 'index'])); }
/** `shop_id` is the declared name for both item_buy and furniture_buy_shop. */
function shopIdOf(d) { return Number(firstDefined(d, ['shop_id', 'id'])); }

/* The bench wire index alone picks the row: the client's setBenchTool sends
   index+1 for slots 0..4 and setBenchItem sends index+5+1 for slots 5..9, so
   1..5 are TOOLS and 6..10 are ITEMS. Nothing else needs to be inspected. */
function benchSlotFor(index) {
  const i = Number(index);
  if (!Number.isInteger(i) || i < 1 || i > 10) return -1;
  return i - 1;
}

/* 福利商品. FurnitureShopDB.type == 998 is the client's own marker for
   "嘟嘟代理福利商品": FurnitureShopView.openBuyTips branches on it and, instead
   of the normal buy confirm, shows FurnitureAdsView -- whose button is the
   「分享拿福利」 art (share_btn3_png) and whose copy is "此商品为嘟嘟代理福利商品
   {0}，即可免费获得". The row's `price` (50 / 100) is the crossed-out list price,
   NOT what the player pays: the good is obtained by sharing or watching an ad,
   and in the channel the client actually runs as (Test) that short-circuits to
   requestBuy + req_share. So these must be granted WITHOUT charging clover --
   charging was a second reason the button looked dead, since it silently spent
   50 clover. `limit`/`shop_limit` are 0 for every one of the 33 rows, which the
   old `Number(row.limit) || 1` turned into a single purchase. */
const FURNITURE_TYPE_WELFARE = 998;
function isWelfareRow(row) { return Number(row && row.type) === FURNITURE_TYPE_WELFARE; }

/* How many times a welfare good may be taken. The live service windowed these
   (limit 0 = unlimited as far as the client is concerned), and re-offering one
   per day is the closest honest offline reading: the item itself is permanent,
   the offer is not. */
const WELFARE_PER_DAY = 1;

function merchantDayAt(seconds) {
  const day = new Date(seconds * 1000);
  day.setHours(0, 0, 0, 0);
  return Math.floor(day.getTime() / 1000);
}

/* tumbler / compost / pocket share one contract: payload is index+1 (1-based),
   code 1 = "hide it", code 0 = "show it", and the client sets BOTH show_index and
   replace_index from that. The client sends `selection + 1` with a 0-based
   selection, so the smallest real value on the wire is 1.
   Pure: mutates `state.furniture[kind]` and returns the reply code. */
function applyReplaceOther(state, kind, d) {
  const wire = Number(d && d.index);
  if (!Number.isInteger(wire) || wire < 1) return -1;
  const cur = state.furniture[kind];
  if (!cur) return -1;
  if (cur.showIndex === wire) {
    cur.showIndex = 0;              // same one selected again -> hide
    cur.replaceIndex = 0;
    return 1;
  }
  cur.showIndex = wire;
  cur.replaceIndex = wire;
  return 0;
}
/** Harvesting a slot whose element==1 yields this ITEM (not clover). */
const FOUR_LEAF_CLOVER_ID = DEF('FourLeafCloverID', 1000);

/* Caps for the album and the gift box. These are NOT invented: both are rows in
   the original server's own tuning table (data/define.json, extracted from the
   client), and the client's error branches key off exactly these conditions
   (101 -> "相册满了，要删除一张照片继续保存吗?", 102 -> "礼品盒满了，..."). */
const ALBUM_MAX = DEF('ALBUM_MAX', 60);

/* 相册容量 —— how many PICTURES the album holds.
   Define.ALBUM_MAX is NOT it: the client never reads that value (it appears exactly
   once in main.min.js, inside the Define table itself). What the client actually does:
     * page count = Math.ceil(pictureList.length / itemPerPage), itemPerPage = 6
       (AlbumView.updateScroller);
     * the 扩容 button's tip is "相册经过了扩容\n保留照片的页数+" + getHouseItemCount(9000)
       -- so every OWNED「相册扩容」item is one extra page.
   The shop sells that item as a chained set (shopData rows with itemId 9000), so the
   real ceiling is the base pages plus those slots. Using ALBUM_MAX as a picture cap
   (as this used to) made the album look "full" at 60 pictures: album_save_new then
   answered 75, and the client DROPS the pending row on 75 -- so every photo earned
   after a 一键解锁 was silently thrown away. */
const ALBUM_BASE_PAGES = 30;      // 30 页起步（副本口径；客户端不读这个数）
const ALBUM_PAGE_SIZE = 6;        // 客户端 AlbumView.itemPerPage
const ALBUM_EXPAND_ITEM = 9000;   // Item「相册扩容」

/* ---- 工作台制作：图纸 + 材料 -> 家具 ------------------------------------
   The client has NO craft command (`send("furniture_*")` never sends one) and no recipe
   table (`Recipe` appears 0 times in main.min.js): the original SERVER watched the bench,
   settled the craft and pushed TimerEvent.FurnitureFinish (21). Two things are therefore
   server-side and not recoverable from the package:
     * `benchData` = what the bench can make (furniture ids, plus a few special items);
     * the material bill, which the client merely DISPLAYS:
       `FurnitureBenchView.update()` renders resourceTypes = [10001..10007] (Item type 10:
       松木/楠竹/砂石/灯芯草/粗布/毛边纸/铜块) with
       `count = houseItemCount(id) - required[id]`, where `required` is counted from the
       server-sent `mate_list`. So the recipe is ours to define -- see CRAFT_MATERIALS below,
       labelled 【自设计】, as is the duration. */
const BENCH_IDS = new Set(((gamedata.tables && gamedata.tables.benchData) || [])
  .map((r) => Number(r && r.id)).filter((v) => Number.isFinite(v)));
const CRAFT_MATERIAL_IDS = [10001, 10002, 10003, 10004, 10005, 10006, 10007];
/* 【自设计】材料配方（原版在服务端）：按家具 style 给一套固定的、看得懂的材料；
   两种新风格各用自己的主题材料，其余家具退回默认配方。 */
const CRAFT_MATERIALS_BY_STYLE = {
  11: [{ item_id: 10001, count: 2 }, { item_id: 10005, count: 1 }],   // 田园庆典: 松木 x2 + 粗布 x1
  101: [{ item_id: 10003, count: 2 }, { item_id: 10007, count: 1 }],  // 许愿池: 砂石 x2 + 铜块 x1
};
const CRAFT_DEFAULT_MATERIALS = [{ item_id: 10001, count: 2 }];
/* 【自设计】制作时长：原版在服务端。默认 15 分钟，可用 FROG_CRAFT_SEC 覆盖。 */
const CRAFT_SECONDS = Math.max(5, Number(process.env.FROG_CRAFT_SEC || 15 * 60));
const ITEM_TYPE_DRAWING = 13;      // 图册（图纸物品）
const SPECIALTY_MAX = DEF('SPECIALTY_MAX', 100);

/* Price quoted to the client for a rename. The real price was decided by the
   ORIGINAL SERVER -- the client only ever renders "本次改名需消耗 {0} 三叶草" and
   never carries the number -- so 50 is OUR value, not a recovered one, and it is
   disclosed as such in dist/README.txt. A brand-new save is quoted 0, because the
   guide's very first naming travels through exactly the same two commands; quoting
   a price there would strand a new player on the naming step with
   "改名失败，三叶草不足！" and no way forward. */
const RENAME_CLOVER = 50;

/* ---------------------------------------------------------------- 手工拼装
   The client's 手工 window (HandCraftView) has two pages, both fed by ONE command,
   `pray_load_grays`:
     page 1  祈愿木牌 : rows from `wishs` (PrayCraftDB rows 1..7 x 4 stages)
     page 2  印章     : rows from `stamps` (StampCraftDB rows)
   plus `wish_new` / `stamp_new` (the just-finished one, for the red dot) and
   `boxes` (finished crafts, popped up by MainIn via BoxCraftShowView).

   A SEPARATE, fully table-backed piece is the 三拼 box: BoxCraftView counts the
   player's house items by `ItemDB.sub_type` 1/2/3 -- which only items of
   `ItemType.COMPOSE` (=16) have, and there are exactly three of them:
     8501 木制护符的1号木片 / 8502 ...2号 / 8503 ...3号
   -- and sends `pray_compose` with `Define.ComposeId` = 5502
   (「木制护符的三拼技巧」) once all three counts are above zero. The reply is read
   as `item_list` and each entry is shown as a reward.

   WHAT IS RECOVERED vs OURS:
   * recovered  : the materials (8501/8502/8503), the recipe id (5502), the fact
                  that composing consumes one of each, the item type enum, and the
                  field names every row must carry.
   * OURS       : the PRODUCT of the三拼 (the materials are named after the wooden
                  amulet and the only wooden amulet in the Item table is 1306
                  紫檀木护符, so that is what we grant -- the original mapping was
                  server-side and is not in our snapshot);
                  WHERE the pieces come from (no table places them and the client
                  never mentions 8501-8503, so the original source was a pure
                  server grant: we make them a rare travel find);
                  the craft PACING below.
   All three are disclosed in dist/README.txt. */
const CRAFT_STAGE_SEC = 90;          // one stage per 90 s, OURS
const COMPOSE_RECIPE_ID = 5502;      // Define.ComposeId, recovered
const COMPOSE_AMULET_ID = 1306;      // 紫檀木护符 -- OUR reading, see above
const COMPOSE_PIECE_CHANCE = 12;     // % per trip, OURS
/* The three pieces, taken from the Item table rather than hard-coded so the list
   cannot drift from the data. */
const COMPOSE_PIECE_IDS = gamedata.items
  .filter((i) => i.type === 16)
  .map((i) => i.id);

/* ------------------------------------------------------- 博物馆冒险 (museumday)
   Recovered from the client + its tables (see work/spec/museumday.md):
     * the window is `end_time > 0 && now <= end_time`, nothing hardcoded;
     * the board is 7x5 with `grid = 1 + col + 7 * row` (client-hardcoded);
     * 罗盘 = item 200002, one of the four museum tickets = 1017..1020;
     * museumDayCommon carries base.v1 = 8 / v3 = 10 / restart_clover.v1 = "100,200,200"
       and inspire.v1 = 8;
     * museumDayDesc rows 1-5/101-105/201-205/301-305 are the four museums' loot
       messages, 401/402 are the two ending cards.
   【自设计】 (the rest -- route shape, per-tile loot, one tile per compass, the
   restart count, `inspire_time`) was server-side and is not recoverable; those
   choices are labelled at their use sites and in dist/README.txt. */
/* 大冒险 (museum adventure) master switch. The player asked for it to go away for now
   and for the museum 图鉴 to be unlocked instead; flipping this to true restores it. */
const MUSEUM_DAY_ENABLED = false;
const MD_MUSEUMS = [1, 2, 3, 4];
const MD_DESC_END = 401;
const MD_COMPASS_ID = 200002;
const MD_TICKET_IDS = { 1: 1017, 2: 1018, 3: 1019, 4: 1020 };
const MD_GRID_W = 7;
const MD_GRID_H = 5;
/* end_time is rolled forward on every load rather than set to a far-future
   constant: the client arms `setTimeout(closeActivity, 1000 * (end_time - now + 1))`
   and that product overflows int32 beyond ~24.8 days. */
const MD_ROLL_DAYS = 20;
const MD_RESTARTS = 2;                       // 【自设计】
const MD_COMMON = (gamedata.tables && gamedata.tables.museumDayCommon) || {};
const MD_RESTART_PRICE = String((MD_COMMON.restart_clover || {}).v1 || '100,200,200')
  .split(',').map((v) => Number(v.trim())).filter((v) => !Number.isNaN(v));
const MD_COMPASS_START = Number((MD_COMMON.base || {}).v1) || 8;
const MD_INSPIRE_PER = Number((MD_COMMON.inspire || {}).v1) || 8;
const MD_DESC_ROWS = (gamedata.tables && gamedata.tables.museumDayDesc) || {};

/* ------------------------------------ 春节贺卡 / 祝福贺卡 / 生日蛋糕 (cards)
   Spec: work/spec/cards_cake.md. All three share ONE window rule, byte-identical in
   their models: `getActivityTime(){ var e = this.data.end_time; return e>0?[1,e]:[0,0] }`
   -- so `end_time` is the whole开关, and `start_time` has no reader at all. The same
   roll-forward-as-now+20d trick as museumday keeps the client's close timer inside
   int32. Recovered from the tables: prices, tag ids/weights, box ids, cake part
   layers, task rows and their cream/sugar payouts. 【自设计】 (the original server's
   rules): the daily caps, `can_buy_num`, `global_num` growth, the small-vs-big box
   rule, share-code format, and the QA question pool -- labelled at each use site. */
const CARD_ROLL_DAYS = 20;
const SC_TABLE = (gamedata.tables && gamedata.tables.springCard) || {};
const GC_TABLE = (gamedata.tables && gamedata.tables.greetCard) || {};
const PC_TABLE = (gamedata.tables && gamedata.tables.PartyCakeData) || {};
const SC_TAGS = (SC_TABLE.tags || []).map((r) => ({ id: Number(r.id), weight: Number(r.buy_weight) || 1 }));
const GC_TAGS = (GC_TABLE.tags || []).map((r) => Number(r.id));
const SC_BG_IDS = (SC_TABLE.bg_list || []).map((r) => Number(r.id));
const GC_BG_IDS = (GC_TABLE.bg_list || []).map((r) => Number(r.id));
const SC_BLESS_IDS = (SC_TABLE.bless || []).map((r) => Number(r.id));
const GC_BLESS_IDS = (GC_TABLE.bless || []).map((r) => Number(r.id));
const SC_BLESS_BOX_KEYS = Object.keys(SC_TABLE.bless_box || {}).map(Number);
const SC_SMALL_BOX = Number(SC_TABLE.small_box_id) || 200009;
const SC_BIG_BOX = Number(SC_TABLE.big_box_id) || 200010;
const SC_STICKER_BAG = Number(SC_TABLE.tags_box_id) || 200008;
const SC_TAGS_PRICE = Number(SC_TABLE.tags_price) || 20;
const SC_SHARE_LIMIT = Number(SC_TABLE.tags_share_limit) || 3;
const GC_TAGS_PRICE = Number(GC_TABLE.tags_price) || 20;
const GC_BG_PRICE = (GC_TABLE.bg_price || [100]).map(Number);
const GC_SEND_SELECT = ((GC_TABLE.send_reward || {}).select_list || [47]).map(Number);
const GC_SEND_RANDOM = ((GC_TABLE.send_reward || {}).random_list || [14]).map(Number);
const PC_TASKS = (PC_TABLE.task_list || {});
const PC_SHARE_REWARD = (PC_TABLE.share_reward || [14, 204001]).map(Number);
const PC_LIGHT_REWARD = PC_TABLE.light_reward || { item_id: 204001, item_num: 2 };
/* The quiz's three options. Must be SPECIALTY ids, not food-type-0 ids: the
   question is 「以下哪个食物{0}看起来最喜欢？」 and the only table that can answer
   it is Character.rowItemId + taste, which is aligned 1:1 with the 64 Specialty
   rows. (Rendering is safe either way -- every option is a real Item row, which is
   what ItemDB.get(...).img needs.) */
const SPECIALTY_IDS = gamedata.items.filter((i) => i.type === ITEM_TYPE_SPECIALTY).map((i) => i.id);
const PC_QA_POOL = SPECIALTY_IDS.slice();
/* tables.Picture comes out of config.eab as full postcard specs ({id, name,
   backImage, frogPose, ...}); older extractions stored a bare id list. Accept
   both so the reward roll keeps working either way. */
const PICTURE_IDS = ((gamedata.tables && gamedata.tables.Picture) || [])
  .map((p) => (typeof p === 'number' ? p : p && p.id))
  .filter((v) => typeof v === 'number');

/* Shop catalogue out of config.eab: {id (slot), itemId, name, price, limit,
   order, before_buy[], is_hide_before}. Only 4 of the 64 slots have
   id === itemId, so the slot id and the item id must be kept apart. */
const SHOP_DATA = (gamedata.tables && gamedata.tables.shopData) || [];
const SHOP_BY_ID = new Map(SHOP_DATA.map((s) => [s.id, s]));

/* How many「相册扩容」the shop can ever sell (the chained before_buy set: 相册扩容·1..N).
   Derived from the table, not hardcoded -- if a future client adds slots, the ceiling
   follows. */
const ALBUM_EXPANSION_SLOTS = SHOP_DATA.filter((r) => Number(r.itemId) === ALBUM_EXPAND_ITEM).length;
const ITEM_BY_ID = new Map(gamedata.items.map((i) => [i.id, i]));

/* Collection ids are 0..61 -- a DIFFERENT id space from Item ids (specialties are
   3000+). evt_value[4] on the BackHome event carries a Collection id, not a
   Picture id and not an Item id. */
const COLLECTION_IDS = ((gamedata.tables && gamedata.tables.Collection) || [])
  .map((c) => (typeof c === 'number' ? c : c && c.id))
  .filter((v) => typeof v === 'number');

/* ItemType values (from Tabikaeru.Define.ItemPutDesc / the ItemType enum). */
const ITEM_TYPE_LUNCHBOX = 0;
const ITEM_TYPE_AMULET = 1;
const ITEM_TYPE_TOOLS = 2;

/* Raffle prize pool: 23 rows, ranks 0..5 (Prize.Rank also defines FURNITURE = 6,
   but the table has NO row for it -- rolling a 6 would hand the client an empty
   picker). stock is 1 on every row. Only rank 0 has itemId -1, which is the
   pure-ticket prize the client handles in its own switch case. */
const PRIZE_BY_ID = new Map(
  ((gamedata.tables && gamedata.tables.Prize) || []).map((p) => [p.id, p]));

/* Achievements ("称号"). The condition lives as TEXT in Achieve.json's `info`
   field -- "旅行达到10次", "双皮奶超过10个", "拥有超过10万棵三叶草" -- and the client
   only ever DISPLAYS the result: it toasts whenever the server's frog.achieves
   array grows. So the rules must be parsed and evaluated engine-side.
   Item-name lookups come from the real Item table, which is what makes the ~60
   "<name>超过N个" rows evaluable without hard-coding any id. */
const ITEM_BY_NAME = new Map(
  ((gamedata.tables && gamedata.tables.Item) || []).map((i) => [i.name, i.id]));

/* The `<name>超过N个` achievements use a player-facing LABEL, which is not always
   the Item table's name: "苏州西瓜子" is item 3003 "西瓜子", and "莜面" is 3034
   "莜面栲栳栳". So fall back to containment, but only when it is unambiguous --
   guessing between candidates would silently credit the wrong item. */
function resolveItemByName(label) {
  const exact = ITEM_BY_NAME.get(label);
  if (exact !== undefined) return exact;
  const hits = ((gamedata.tables && gamedata.tables.Item) || [])
    .filter((i) => i.name && (i.name.indexOf(label) !== -1 || label.indexOf(i.name) !== -1));
  return hits.length === 1 ? Number(hits[0].id) : undefined;
}
/* Farm-produced specialties (place is 谷物/蔬菜/水果/牛乳/乳制品/饮料) -- the set the
   "获得所有特产食材" achievement covers. */
const FARM_PLACES = ['谷物', '蔬菜', '水果', '牛乳', '乳制品', '饮料', '调料'];
const FARM_SPECIALTY_IDS = ((gamedata.tables && gamedata.tables.Specialty) || [])
  .filter((s) => FARM_PLACES.indexOf(s.place) !== -1)
  .map((s) => Number(s.itemId));

const SAVE_VERSION = 1;
const CLOVER_SLOTS = 20;
/* Clover timing, now CONFIRMED rather than guessed: the Japanese original's
   decompiled CloverFarm uses
       span = clamp(rand_normal(7200, 1800), 300, 14400)   // mean 2h, sd 30m
       cloverMax = 20 slots, fourLeaf = 1%
   Our 300 / 14400 / 1% / 20 all match it exactly. What did NOT match was the
   SHAPE of the draw: we used a uniform pick over the same range, which has a
   similar mean by luck but the wrong distribution. */
const CLOVER_REBIRTH_MEAN = 7200;
const CLOVER_REBIRTH_SD = 1800;
const CLOVER_REBIRTH_SPAN = 300;      // clamp floor, seconds
const CLOVER_REBIRTH_SPAN_MAX = 14400; // clamp ceiling, seconds
const FOUR_LEAF_CHANCE = 0.01;

/** clamp(rand_normal(mean, sd), floor, ceiling), the original's own formula. */
function rollCloverRebirth() {
  let u = 0;
  let v = 0;
  while (u === 0) u = Math.random();            // Box-Muller needs non-zero
  while (v === 0) v = Math.random();
  const z = Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  const s = CLOVER_REBIRTH_MEAN + z * CLOVER_REBIRTH_SD;
  return Math.min(CLOVER_REBIRTH_SPAN_MAX, Math.max(CLOVER_REBIRTH_SPAN, Math.round(s)));
}

/* ---------------------------------------------------------------- travel */
/* The frog departs on its own (there is no "go travel" client command): the
   server pushes a GoTravel event, then a BackHome event when it returns.
   evt_value layout, read off MainOutController's BackHome handler:
     [2] clover gained   [3] tickets gained
     [4] COLLECTION id, 0..61 (-1 = none)  -- NOT a picture id; the client reads
         it via CollectDB.get() in Result.ModalSpeciality. Postcards travel a
         completely separate album_* channel.
     [5..] item ids (type Specialty=3 go to the gift box, others are drops)
   frog.status: 0 = home, 1 = travelling.                                  */
const TIMER_EVENT = { NONE: 0, GoTravel: 1, BackHome: 2, Picture: 3, NewNote: 15, FurnitureFinish: 21, FurniturePut: 22 };
const EV_GO_TRAVEL = TIMER_EVENT.GoTravel;
const EV_BACK_HOME = TIMER_EVENT.BackHome;
/* 15 = the client's own `TimerEvent.Type.NewNote` (Result.eventSystem's
   `case TimerEvent.Type.NewNote` is what re-loads the note list). */
const EV_NEW_NOTE = TIMER_EVENT.NewNote;
/* 21/22 are the client's own enum values (`e[e.FurnitureFinish=21]="FurnitureFinish"`,
   `e[e.FurniturePut=22]="FurniturePut"` in main.min.js) -- the client's event system
   branches on them, so the workbench completion must be reported with 21. */
const EV_FURNITURE_FINISH = TIMER_EVENT.FurnitureFinish;

/* --------------------------------------------------------------- visitors */
/* Original cadence, straight from the tuning table that shipped inside the
   client (Define): roll every FRIEND_VISIT_RNDSEC = 1800s with a
   FRIEND_VISIT_RNDPER = 10% chance, then a FRIEND_VISIT_COOL = 21600s cooldown
   once the visitor leaves -- i.e. an expected wait of hours, which suits a live
   service but not a sitting. Same policy as the travel pacing above: default to
   something playable, keep the original numbers documented here, allow env
   overrides. */
const GUEST_ROLL_SEC = Number(process.env.FROG_GUEST_ROLL || 60);
const GUEST_CHANCE = Number(process.env.FROG_GUEST_CHANCE || 35);/* 串门访客 pacing -- these are OUR choices (the original schedule was
   server-side), kept separate from the 邻居 guest knobs so each can be tuned. */
const VISITOR_ROLL_SEC = Number(process.env.FROG_VISITOR_ROLL || 300);
const VISITOR_CHANCE = Number(process.env.FROG_VISITOR_CHANCE || 25);
const VISITOR_STAY_SEC = Number(process.env.FROG_VISITOR_STAY || 900);
const VISITOR_COOL_SEC = Number(process.env.FROG_VISITOR_COOL || 600);
const VISITOR_FOOD_MAX = Number(process.env.FROG_VISITOR_FOOD_MAX || 20);
/* 友情绘本 (drawing) pacing -- OUR choices, the original schedule was server-side. */
const DRAWING_ROLL_SEC = Number(process.env.FROG_DRAWING_ROLL || 420);
const DRAWING_CHANCE = Number(process.env.FROG_DRAWING_CHANCE || 20);
const DRAWING_TRIP_SEC = Number(process.env.FROG_DRAWING_TRIP || 600);
/* The item that unlocks the whole feature: the client's `isOpen()` is
   `ItemModel.getHouseItemCount(Tabikaeru.ItemID.DRAWING_BOOK) > 0`, and that
   enum is DRAWING_BOOK = 7001 (item 友情绘本, type 7). */
const DRAWING_BOOK_ID = 7001;
/* 抽奖 / 邻里美食交流 pacing -- OUR choices (the original schedule was on the
   dead server). */
const LOTTERY_ROLL_SEC = Number(process.env.FROG_LOTTERY_ROLL || 300);
const LOTTERY_CHANCE = Number(process.env.FROG_LOTTERY_CHANCE || 30);
/** The client's `Tabikaeru.LotteryState`. Only the ORDER is observable in the
 *  client (Open -> Select -> Complete -> Reward, with `state` defaulting to 0),
 *  so these numbers are INFERRED, not read: Open 0 / Select 1 / Complete 2 /
 *  Reward 3. The flow below never depends on the two middle values. */
const LOTTERY_STATE = { Open: 0, Select: 1, Complete: 2, Reward: 3 };
/** How many items the player picks. `settle_desc` and `extra_desc` are both
 *  keyed 0..5, i.e. the score runs 0..5, which fixes the slot count at 5. */
const LOTTERY_PICKS = 5;
/** How many items the round OFFERS. This must be more than LOTTERY_PICKS, and
 *  the client is the proof of both halves:
 *
 *   - its skin (`Lottery/LotterySkin.exml`, compiled into
 *     `js/default.thm.js`) lays the options out in a TileLayout of 80px cells
 *     inside a 424x260 box -- 5 columns x 3 rows -- and its own label reads
 *     「选出5款物品，帮{0}解决这个困扰」;
 *   - `settle_desc`/`extra_desc` are keyed 0..5 with texts like 「很感谢你的帮忙，
 *     但还是看得出有点可惜」, i.e. picking WRONG items has to be possible.
 *
 *  We used to send exactly the 5 wanted items (`L.selectList = want`), so the
 *  round offered no choice at all: every pick was correct, the score was always 5,
 *  and -- because the client only enables its confirm button once 5 items are
 *  ticked -- the button sat greyed out while the player wondered what to do.
 *  【自设计】 the count itself: the original number lived on the server. 10 fills
 *  two of the grid's three rows. */
const LOTTERY_OPTIONS = Math.max(LOTTERY_PICKS, Number(process.env.FROG_LOTTERY_OPTIONS || 10));
/** Phases the round cycles through. The client derives the guest from the phase
 *  row (`(phase-1)%4+1` indexes lotteryData.select_list) but its quiz line is
 *  `_("以下哪个食物{0}看起来最喜欢？")` over a HARD-CODED `["困困","胖胖","跳跳"]`
 *  and `neighbor_emote_<guest>_0_png`; Character.json has exactly those three rows
 *  and the 4th neighbour (嘟嘟, the plant-themed row) ships only
 *  `neighbor_emote_3_0` -- the reward screen would ask for `_3_1`/`_3_2` and find
 *  nothing, and the question would print "undefined". So the round cycles 1..3. */
const LOTTERY_PHASES = 3;
/* 许愿池 (wishing pool). The original ran as a timed event whose schedule lived
   on the server, and its prize table is not in the client either. So: the pool
   is held permanently OPEN (end_time = now + 10 years), the prize list is OUR
   choice built from real Items, and coins are topped up daily. All three are
   labelled below; nothing here is presented as a recovered value. */
const WISH_POOL_DAYS = Number(process.env.FROG_WISH_POOL_DAYS || 3650);
const WISH_POOL_COINS_PER_DAY = Number(process.env.FROG_WISH_COINS_PER_DAY || 3);
const WISH_POOL_COIN_MAX = Number(process.env.FROG_WISH_COIN_MAX || 10);
/* The visitor cooldown WE chose is 300 s for playability; the ORIGINAL is
   define.json's FRIEND_VISIT_COOL = 21600 (6 h). FROG_FAITHFUL=1 uses the real
   one, and FROG_GUEST_COOL always wins if set. */
const GUEST_COOL_SEC = pace('FROG_GUEST_COOL', 300, ORIG.friendVisitCool);
/* gameplay table: 串门/邻居 both have DurationFloor = DurationUpper = 30 minutes,
   so a visit lasts 1800 seconds. */
const GUEST_STAY_SEC = 1800;
const GUEST_POS_MAX = Number(DEF('FRIEND_RNDPOS_MAX', 3));

// Offline pacing: the live game used 6-72h trips (TRAVEL_TIME_MIN = 60 in
// define.json is the floor of the original unit). The offline default used to be
// 90-240 s, which players reported as "a bit fast"; it is now 12-40 minutes, so a trip
// feels like a trip while a session can still see it leave and come back.
// FROG_FAITHFUL=1 restores the recovered values, and the env vars always win.
const TRAVEL_MIN_SEC = pace('FROG_TRAVEL_MIN', 12 * 60, ORIG.travelTimeMin * 60);
/* define.json gives the travel FLOOR (TRAVEL_TIME_MIN = 60 min) but no ceiling,
   so in faithful mode the ceiling is OUR choice: 6x the floor. Labelled because
   it is not a recovered number. */
const TRAVEL_MAX_SEC = pace('FROG_TRAVEL_MAX', 40 * 60, ORIG.travelTimeMin * 60 * 6);
// How long the frog waits at home before heading out again.
const TRAVEL_IDLE_MIN = pace('FROG_IDLE_MIN', 2 * 60, ORIG.standbyWaitMin);
const TRAVEL_IDLE_MAX = pace('FROG_IDLE_MAX', 6 * 60, ORIG.restTick);
/* 没准备就不出门 (OUR rule, see the file header note): while the bag is empty the frog
   stays home, and it re-checks on this interval instead of leaving. */
const TRAVEL_WAIT_UNPREPARED_MIN = pace('FROG_WAIT_MIN', 3 * 60, ORIG.standbyWaitMin);
const TRAVEL_WAIT_UNPREPARED_MAX = pace('FROG_WAIT_MAX', 8 * 60, ORIG.restTick);
/* The original also shortens a 放浪 (stray) trip: FROG_DRIFTRETURNTIME 10 /
   _MAX 20. We were not using these at all, so a stray trip used the normal
   travel window -- now it uses the table's own numbers. */
const DRIFT_RETURN_MIN = Number(process.env.FROG_DRIFT_MIN || ORIG.driftReturn);
const DRIFT_RETURN_MAX = Number(process.env.FROG_DRIFT_MAX || ORIG.driftReturnMax);

/**
 * The upstream server PUSHES the whole game state right after hall_enter_game.
 * The client never requests any of these itself - every one of them appears only
 * in an addProtocolCallback() registration, never in a send() call. Missing any
 * of them leaves the corresponding model empty (and can wedge scene startup).
 * Names here are canonical (underscore) form; toWire() converts them.
 */
const BOOT_PUSH = [
  'client_load_decorate',
  'clover_load_clovers',
  'item_load_items',
  'item_load_shop_info',
  'item_load_handbook',
  'furniture_load_furniture',
  'furniture_load_flowerpot',
  'furniture_load_compost',
  'furniture_load_pocket',
  'furniture_load_tumbler',
  'travel_load_note',
  'travel_load_gift',
  'album_load',
  'guest_load',
  'mail_load',
  'task_load',
  'task_load_list',
  'client_load_events',
  'story_load',
  'encyclopedia_load',
  'lottery_load',
  'wishingpool_load',
  'calendar_load',
  'misc_moment_load',
  'other_load_touch',
  'share_load',
  'museum_load',
  'easteregg_load',
  'animpicture_load',
  'pray_load_grays',
  'capsule_load',
  'recharge_load',
  'greetcard_load',
  'springcard_load',
  'partycake_load',
  'cooking_load_cooking',
  'adsmgr_load',
  'museumday_load',
  'visit_load',
  'client_load_publicity',
];

/* The client's own GuideStep order (it takes `getNextGuideStep` from the enum's key
   order). Used to keep `guideStep` MONOTONIC -- see the note in client_set_client. */
const GUIDE_STEPS = ['New', 'Named', 'PrepareGatherClover', 'StartGatherClover',
  'EnterRoom', 'Introduce', 'OpenShop', 'BuyGoods', 'EnterRoom2', 'OpenBag',
  'CloseBag', 'GetAward', 'Complete', 'OpenNote'];
function guideStepRank(step) {
  const i = GUIDE_STEPS.indexOf(String(step || ''));
  return i < 0 ? -1 : i;
}

function canon(cmd) {
  return String(cmd || '').replace(/\./g, '_');
}
// The client turns only the FIRST underscore of a command into a dot on the wire
// (client_load_all_info -> "client.load_all_info"), so pushes must do the same.
// Normalise first so this is idempotent for already-dotted input.
function toWire(cmd) {
  const s = canon(cmd);
  const i = s.indexOf('_');
  return i < 0 ? s : s.slice(0, i) + '.' + s.slice(i + 1);
}
function nowSec() {
  return Math.floor(Date.now() / 1000);
}

/* ------------------------------------------------------------------ state */

function defaultState() {
  const t = nowSec();
  return {
    saveVersion: SAVE_VERSION,
    account: 'offline',
    uid: 10001,
    name: '呱呱',
    /* A brand-new account's clover. This is the CLIENT'S OWN value, not one we
       invented: define.json (the original server's tuning table, shipped inside
       the client) has `StartCloverPoint = 9999`. We used to hand out 300, which
       was our own number. `startClover` above already reads that key -- this line
       had simply never been made to use it. */
    clover: ORIG.startClover,
    ticket: 3,
    createTime: t,
    curAchieve: 0,
    achieves: [],
    achievesTime: [],
    frog: {
      status: 0, motion: 0, icon: 0, picShow: 0, todayStep: 0, taobaoData: null,
      // at-home activity sequence (see refreshFrogMotion)
      motionPattern: null, motionStep: 0, motionNextAt: 0,
    },
    clovers: [],
    // slot counts match the client's own defaults
    // (ItemModel: bagDataList=[-1,-1,-1,-1], deskDataList=[8 x -1])
    items: {
      house: [],
      bag: [-1, -1, -1, -1],
      desk: [-1, -1, -1, -1, -1, -1, -1, -1],
      bagCompleted: 0, bagConflict: 0, deskConflict: 0,
    },
    // -1 means "no gacha ball waiting". The client's ItemModel initialises
    // gachaColorBall to -1 and cleanGachaColorBall() resets it to -1; rank 0 is a
    // REAL prize (Define.PRIZE_WHITE_ID === 0), so leaving this at 0 makes the
    // lottery screen pop a claimable white ball on a brand new save.
    gacha: { colorBall: -1 },
    gachaCount: 0,          // raffle draws, for the "抽奖20次以上" achievement
    achieves: [],
    achievesTime: [],
    curAchieve: 0,
    // shop slot id -> how many times it has been bought. The client keeps the
    // same map (ItemModel.purchasedMap) and keys it by SLOT id, not item id.
    shopBought: {},
    // NOTE: `weather` must be a VALID WeatherType (1..9). It used to default to 0,
    // which is outside the enum -- the client has no art for it, and a boot-time
    // client_load_role sent before the first refreshWeather() carried that 0.
    // (A range-checking unit test caught it.)
    weather: { season: 1, hoursType: 1, weather: 1 },
    travel: { departAt: 0, returnAt: 0, nextDepartAt: 0, tripCount: 0 },
    /* Visitor. null means nobody is visiting -- the client's own GuestData
       defaults id to -1 to mean exactly that. */
    guest: null,
    guestNextRollAt: 0,
    guestCoolUntil: 0,
    guestBonusTickets: 0,
    guestFeeds: 0,           // repeat-feeding count, drives FRIEND_ITEM_DEBUFF
    guestVisits: 0,          // cumulative arrivals, for the 年度总结 visit_num
    firstGuest: 0,           // first visitor's Character id (年度总结 first_guest)
    eventSeq: 1,
    pictures: [],
    pictureSeq: 0,          // monotonic handle handed out as PictureInfo.id
    specialtys: [],
    /* ---- gift box (礼品盒): a holding area SEPARATE from the album ----
       The client keeps these in GiftBoxModel.pictureList / .specialityList, fed
       only by `travel_load_gift`. See the travel_gift_* handlers. */
    giftBox: { pictures: [], specialtys: [] },
    /* ---- album buckets (see the album management handlers) ----
       albumPending      -> album_load_new.pictures   (not yet filed)
       albumPendingVisit -> album_load_new.visted_pic (earned from a visit)
       albumDeleted      -> album_load_recover        (recycle bin)
       Ad-earned pictures are deliberately absent: this build has no ads. */
    albumPending: [],
    albumPendingVisit: [],
    albumDeleted: [],
    /* ---- 串门访客 (a separate gameplay from the 邻居 guest) ---- */
    visitor: null,
    acquireProvinces: [],   // provinces whose flower has been collected
    visitorNextRollAt: 0,
    visitorCoolUntil: 0,
    /* ---- 友情绘本 (DrawingModel / guest_*): a THIRD visitor gameplay ----
       `state` uses the client's own enum values exactly:
         DrawingState = { wait:0, invite:1, accept:2, lock:3, visit:4 }
       The whole object is what `guest_load_drawing` replaces wholesale. */
    drawing: {
      state: 0,          // DrawingState.wait
      guest: -1,
      bag: [-1, -1, -1, -1, -1, -1],
      pages: [],         // drawingPageData ids collected
      colls: [],         // drawingCollectData ids collected
      showColl: 0,
      penMotion: 'write',
    },
    drawingNextRollAt: 0,
    drawingReturnAt: 0,
    /* ---- 抽奖 / 邻里美食交流 (LotteryModel) ----
       The client's model, verbatim from main.min.js:
         {last_phase, phase, state, select_list, answer,
          extra_item:{item_id,count}, right_flag, egg_num, reward}
       `lottery_load` only applies the payload `if (e.phase)`, so phase MUST be
       truthy or the whole thing is ignored -- that is the silent trap here. */
    lottery: {
      lastPhase: 0,
      phase: 0,
      state: 0,
      selectList: [],
      answer: [],
      extraItem: { item_id: 0, count: 0 },
      rightFlag: [],
      eggNum: 0,
      reward: [],
    },
    lotteryNextRollAt: 0,
    /* ---- 许愿池 (WishingPoolModel) ----
       The client's model is {end_time, coin, items:[...]} and `wishingpool_load`
       REPLACES it via Utils.convertArrayAll. `isOpen()` is simply
       `now < end_time`, so end_time === 0 means the pool is never open.
       `wishingpool_wish` carries NO payload: the SERVER draws the prize and
       answers `{id}` -- the client then decrements its own coin, decrements that
       entry's `limit`, and shows `[{item_id: o.id, count: o.num}]`. */
    wishingPool: {
      endTime: 0,
      coin: 0,
      items: [],
      lastGrantDay: 0,
    },
    /* ---- 庭院装饰 (client_load_decorate / client_change_decorate) ----
       RoleModel fields, read from main.min.js:
         decorationList : [{id, num}]   (DecorationItem)
         decorationPutID: the decoration currently on display
         decorationStatus: 0/1 -> picks pic[0] (花苞) or pic[1] (花朵)
       They arrive as `{has_list, put_id, status}`. */
    decoration: { hasList: [], putId: 0, status: 0 },
    /* ---- 料理 (CookingModel) ----
       The client's serverData, verbatim:
         {month, month_pro, week, complete, select, refresh_time, task_list}
       `cooking_load_cooking` assigns it (`serverData = e || serverData`), so the
       payload must carry every field. A task row is `{id, pro, complete}`, and
       the client's red dot fires when `pro == <table state>` -- i.e. tasks have
       PROGRESS, not just a done flag. */
    cooking: {
      month: 0,
      monthPro: 0,
      week: 0,
      complete: false,
      select: 1,
      refreshTime: 0,
      taskList: [],
    },
    /* Cumulative clover EARNED (not the balance) -- cooking task type 4 is
       "累计获得80株三叶草" and the achievements distinguish balance from total. */
    cloverEarned: 0,
    /* ---- 新手引导 (tutorial) ----
       GuideStep itself lives CLIENT-side (SettingsInfo.guideStep, default "New",
       advanced with setClientSettings), so this only records what the server has
       been told and whether the starter award was already handed out. */
    guide: { doorOpened: false, awardGiven: false, steps: [] },


  /* ---- 回忆彩蛋 (MomentModel) ----
       The client's model is `{has_map:{}}`, and `misc_moment_load` ADDS to it:
         for (id of convertArray(e.list)) this.data.has_map[id] = true;
       so the payload is `{list:[ids]}` and it is additive, not a reset. */
    moments: [],
    /* ---- 手工拼装 (HandCraftModel) ----
       wish rows  : {id (prayData 1..7), state 1..4, body, paper, content, make_time, u_id}
                    `state > 3` means finished, and then `body`/`paper` are the
                    prayBodyData ids the client draws (PrayCraftPageView groups rows
                    by `id_body_paper`); `content` is a prayNoteData row whose `info`
                    provides the note text.
       stamp rows : {id (stampData), state, time, u_id} -- NOTICE the field is `time`
                    here but `make_time` for wishes; the client reads exactly that.
       pending    : finished crafts waiting for the player to acknowledge them
                    (pray_load_grays.boxes -> BoxCraftShowView -> pray_confirm_make_box).
       seq        : monotonic `u_id`, which the client stores in a cookie to stop
                    re-announcing the same craft. */
    craft: { wishes: [], stamps: [], pending: [], seq: 0 },
    /* ---- 春节贺卡 / 祝福贺卡 / 生日蛋糕 ----
       `card_info` is a REAL OBJECT with `tags` of length 3 -- the client indexes
       `card_info.tags[n]` and maps a slot to a card layer with `tags[slot]-1`, so an
       empty object (the old stub) throws as soon as the view opens. `part` is 1..5
       because the view indexes `PartyCakeData.cake[part].layers` with no guard. */
    springCard: {
      bg: 0, bless: 0, tags: [0, 0, 0], taskHarvest: 0, buyNum: 0, shareNum: 0,
      shareGet: 0, boxId: 0, shareCode: '', items: [], taskItem: [], rewardList: [],
      globalNum: 0,
    },
    greetCard: {
      bg: 0, bless: 0, tags: [0, 0, 0], sendList: [], getList: [], items: [],
      taskLogin: false, taskShare: false, taskItem: [], canReward: false,
      globalNum: 0, newIndex: 0, stockNum: 0,
    },
    partyCake: {
      cream: 0, sugar: 0, preCream: 0, preSugar: 0, curState: 0, part: 1, madeLayers: [],
      taskCounts: {}, shareGet: [0, 0], guest: 0, wrong: 0, answer: [], qaCorrect: 0,
      rewardRows: 1, mateDay: '',
    },
    /* ---- 故事 (StoryModel) ----
       StoryData = {id, partner, name, gift:-1, feedback:-1} -- gift and feedback
       START AT -1, and `story_load` reads `{stories, new_story_id}`. */
    storyBook: { list: [], newId: 0 },
    /* ---- 动态照片 (AnimPictureModel) ----
       The client's model, verbatim:
         {guide, page_num, phase, item_num, exp, exp_pic, pic_list}
       `animpicture_load` REPLACES it (convertArrayAll, and each pic_list entry's
       `pictures` is convertArray-ed). `phase` is a FLOW GATE: the client's
       `animpicture_use_item` callback is `if (e.phase >= 0) {...}`, so a reply
       without `phase` silently does nothing. */
    animPicture: {
      guide: 0,
      pageNum: 0,
      phase: 0,
      itemNum: 0,
      exp: 0,
      expPic: [],
      picList: [],
    },
    /* ---- 扭蛋活动 (CapsuleModel) ----
       The client's model, verbatim:
         {end_time, coin, pre_coin, reward_list, task_list, patch_num}
       `capsule_load` replaces it wholesale AND only arms the activity when
       `isOpen()` (now < end_time) -- so end_time === 0 makes the whole event
       inert, exactly like the wishing pool. */
    capsule: {
      endTime: 0,
      coin: 0,
      preCoin: 0,
      rewardList: [],
      taskList: [],
      patchNum: 0,
      doneTasks: [],
    },
    /* queued gift packages (item_load_select_gift / item_select_gift) */
    selectGift: {},
    notes: [],
    mails: [],
    mailSeq: 0,
    mailTutorialSent: false,
    calendar: {
      /* The client hardcodes THREE task rows, so this must always be 3 long. */
      taskList: [
        { id: 1, pro: 0, complete: 0 },
        { id: 2, pro: 0, complete: 0 },
        { id: 3, pro: 0, complete: 0 },
      ],
      claimedBeginner: [],
      month: 0,
      st: [],
      lucky: [],
      claimedSt: [],
      claimedLucky: [],
      notes: [],
    },
    tasksClaimed: [],
    flowerpot: { showIndex: 1, replaceIndex: 0, slots: [], grown: [] },
    /* ---- furniture / 庭院 (see the furniture block in handlers) ----
       Field names mirror the client's FurnitureModel exactly, because
       `furniture_load_furniture` REPLACES serverData wholesale and
       Utils.convertArrayAll only copies keys already present.

       `bench` is 10 slots: [0..4] are TOOLS, [5..9] are ITEMS, and -1 = empty
       (the client slices 0..5 and 5..10 into two separate rows). The compost
       `box_list` uses 0 for empty instead -- do not unify them. */
    furniture: {
      bench: [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
      benchLock: 0,         // bench_lock: 1 while a craft is running (client refuses edits)
      craft: null,          // 进行中的制作 {furnitureId, drawing, materials, startedAt, finishAt}
      owned: [],            // has_fur: furniture ids the player owns
      placed: [],           // put_fur: [{type, id}] currently in the courtyard
      replaceFur: [],       // replace_fur: furniture TYPEs being rotated out
      shopBought: {},       // shop id -> times bought (against FurnitureShop limit)
      shopDay: merchantDayAt(t),
      shopDailyBought: {},  // repeatable stock is replenished each local calendar day
      welfareTaken: {},     // shop id -> welfare goods taken on `welfareDay`
      welfareDay: {},       // shop id -> createDay() the welfare count belongs to
      compost: { showIndex: 1, replaceIndex: 0, boxIndex: 1, boxes: [0, 0, 0, 0, 0, 0], list: [21000] },
      pocket: { showIndex: 0, replaceIndex: 0, clover: 0 },
      tumbler: { showIndex: 0, replaceIndex: 0 },
    },
    tasks: [],
    taskList: [],
    events: [],
    handbook: { collections: [], specialtys: [] },
    createdAt: t,
    lastSeen: t,
  };
}

function makeClovers() {
  // element 0 / sprite 1 = plain growable clover; last_harvest 0 => ready now
  const out = [];
  for (let i = 0; i < CLOVER_SLOTS; i++) {
    out.push({
      clover_id: i + 1,
      element: 0,
      sprite: 1,
      last_harvest: 0,
      rebirth_span: CLOVER_REBIRTH_SPAN,
    });
  }
  return out;
}

/* ---- 存档安全层 ------------------------------------------------------------
   Why this exists: the old code did `JSON.parse(readFileSync(savePath))` inside a
   try/catch and, on failure, fell through to `defaultState()` -- a brand-new game
   with 9999 clover -- while the unreadable bytes were left in place to be
   overwritten by the next save. A truncated write (browser closing mid-write,
   phone killed, quota) therefore turned into "my save reset itself", silently and
   permanently.

   The save FORMAT and the storage key are untouched, so every existing save still
   loads: only sibling slots are added.

     save.json              primary    (browser key stays `frog.offline.save`)
     save.json.bak          last known-good primary, written before each commit
     save.json.tmp          in-flight commit, dropped once the primary is verified
     save.json.corrupt-<ts> an unreadable primary, archived BEFORE anything writes

   Commit order is tmp -> verify -> bak -> verify -> main -> verify -> drop tmp, so
   at any instant at least one complete copy exists. Load order is main -> bak ->
   native mirror -> new game, and a corrupt primary is never deleted by the loader;
   if it cannot be archived (quota) the engine refuses to overwrite it at all.
--------------------------------------------------------------------------- */
const SAVE_BAK_SUFFIX = '.bak';
const SAVE_TMP_SUFFIX = '.tmp';
const SAVE_CORRUPT_INFIX = '.corrupt-';
const SAVE_CORRUPT_KEEP = 3;

function makeSaveReport() {
  return {
    action: 'new',        // load | restore | new
    restoredFrom: null,   // main | backup | mirror
    reason: null,         // parse | shape | migrate-error (why the primary was rejected)
    corruptKept: null,    // where the rejected primary text was archived
    protectMain: false,   // primary is unreadable AND unarchived -> never overwrite
    blocked: false,       // a write was refused (version-ahead or protectMain)
    lastError: null,
    lastSaveAt: 0,
  };
}

function tsStamp() {
  return String(Date.now());
}

function readText(p) {
  try {
    if (!fs.existsSync(p)) return null;
    const t = fs.readFileSync(p, 'utf8');
    return t == null ? null : String(t);
  } catch (e) {
    return null;
  }
}

/* Write, then read back. Both hosts can fail silently -- localStorage.setItem
   throws on quota in some engines and simply does nothing in others, and Egret's
   own runtime returns false instead of throwing -- so the read-back is the only
   trustworthy signal that the bytes are actually on disk. */
function writeText(p, text) {
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
  } catch (e) { /* the browser stub has no directories */ }
  try {
    if (fs.writeFileSync(p, text) === false) return false;
  } catch (e) {
    return false;
  }
  try {
    const back = fs.readFileSync(p, 'utf8');
    return back != null && String(back) === text;
  } catch (e) {
    return false;
  }
}

function dropText(p) {
  try {
    if (typeof fs.removeFileSync === 'function') fs.removeFileSync(p);
    else if (typeof fs.unlinkSync === 'function') fs.unlinkSync(p);
  } catch (e) { /* best effort */ }
}

/* Deliberately loose: old saves (and saves written by older builds of this
   engine) may carry very few fields, and rejecting one of those would look
   exactly like the bug this layer exists to prevent. Only "not an object" and
   "none of our top-level fields" count as damage. */
const SAVE_KNOWN_FIELDS = [
  'clover', 'ticket', 'items', 'frog', 'name', 'travel', 'clovers',
  'createTime', 'account', 'uid', 'decoration', 'gacha', 'weather',
];

function parseSave(text) {
  if (text == null) return { ok: false, reason: 'missing' };
  const body = String(text).trim();
  // the browser stub hands back '{}' when neither localStorage nor the native
  // mirror has anything: that is "no save", not a damaged one.
  if (body === '' || body === '{}') return { ok: false, reason: 'missing' };
  let obj;
  try {
    obj = JSON.parse(body);
  } catch (e) {
    return { ok: false, reason: 'parse' };
  }
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return { ok: false, reason: 'shape' };
  if (!SAVE_KNOWN_FIELDS.some((k) => obj[k] !== undefined)) return { ok: false, reason: 'shape' };
  return { ok: true, value: obj };
}

function readMirrorText() {
  try {
    return typeof fs.readMirrorSave === 'function' ? (fs.readMirrorSave() || null) : null;
  } catch (e) {
    return null;
  }
}

function listCorruptSlots(savePath) {
  const prefix = path.basename(savePath) + SAVE_CORRUPT_INFIX;
  let names = [];
  try {
    if (typeof fs.listSaveSlots === 'function') {
      names = fs.listSaveSlots() || [];               // browser: slot names, no directories
    } else {
      const dir = path.dirname(savePath);
      names = fs.readdirSync(dir).map((n) => path.join(dir, n));
    }
  } catch (e) {
    return [];
  }
  return names
    .map((n) => String(n))
    .filter((n) => path.basename(n).indexOf(prefix) === 0)
    .sort()
    .reverse();
}

function pruneCorruptSlots(savePath) {
  for (const p of listCorruptSlots(savePath).slice(SAVE_CORRUPT_KEEP)) dropText(p);
}

/** Archive an unreadable primary. Returns {kept, blocked}. Shared by the loader and
    by save(), because damage can also arrive while the game is RUNNING (another
    process, another tab, a half-flushed write) -- the invariant has to hold either
    way: bytes we could not read are never overwritten before being kept. */
function archiveDamagedPrimary(savePath, text, report) {
  const prev = listCorruptSlots(savePath)[0];
  if (prev && readText(prev) === text) {
    report.corruptKept = prev;
    return { kept: prev, blocked: false };
  }
  const slot = savePath + SAVE_CORRUPT_INFIX + tsStamp();
  if (writeText(slot, text)) {
    report.corruptKept = slot;
    pruneCorruptSlots(savePath);
    return { kept: slot, blocked: false };
  }
  return { kept: null, blocked: String(text).length > 200 };
}

/** main -> backup -> native mirror; archives a rejected primary before anything writes. */
function readSaveChain(savePath, report) {
  const mainText = savePath ? readText(savePath) : null;
  const mainTry = parseSave(mainText);
  if (mainTry.ok) {
    report.action = 'load';
    report.restoredFrom = 'main';
    return mainTry.value;
  }
  if (mainTry.reason === 'missing') {
    /* No primary at all (a fresh install, or a phone whose localStorage was
       cleared): still worth asking the backup and the native mirror before
       handing out a new game -- 'missing' is exactly the case the mirror is for. */
    report.reason = null;
  } else {
    report.reason = mainTry.reason;
    /* Booting twice against the same unreadable primary must not pile up identical
       archives (and must not grow storage without bound). */
    const kept = archiveDamagedPrimary(savePath, mainText, report);
    report.protectMain = kept.blocked;
    console.error('[engine] save is unreadable (' + mainTry.reason + '), kept at '
      + (report.corruptKept || 'NOWHERE -- writes blocked'));
  }

  const bakTry = parseSave(readText(savePath + SAVE_BAK_SUFFIX));
  if (bakTry.ok) {
    report.action = 'restore';
    report.restoredFrom = 'backup';
    return bakTry.value;
  }
  const mirrorTry = parseSave(readMirrorText());
  if (mirrorTry.ok) {
    report.action = 'restore';
    report.restoredFrom = 'mirror';
    return mirrorTry.value;
  }
  report.action = 'new';
  return null;
}

function loadState(savePath) {
  let s = defaultState();
  const report = makeSaveReport();
  const raw = readSaveChain(savePath, report);
  try {
    if (raw) {
      s = Object.assign(s, raw);
      s.frog = Object.assign(defaultState().frog, raw.frog || {});
      s.decoration = Object.assign(defaultState().decoration, raw.decoration || {});
      s.items = Object.assign(defaultState().items, raw.items || {});
      if (s.frog.status === 0) s.items.bagCompleted = 0; // old returns left the bag locked
      s.drawing = Object.assign(defaultState().drawing, raw.drawing || {});
      // Older returns cleared the guest but left the invitation accepted. Preserve
      // the bag/collection while returning that orphaned state to waiting.
      if (s.drawing.state === 2 && Number(s.drawing.guest) < 0) {
        s.drawing.state = 0;
        s.drawingReturnAt = 0;
      }
      s.gacha = Object.assign(defaultState().gacha, raw.gacha || {});
      // migration: the engine used to default colorBall to 0, which the client
      // reads as "a white ball is waiting". It never granted one, so a stored 0
      // can only be that bad default -- clear it.
      if (s.gacha.colorBall === 0) s.gacha.colorBall = -1;
      s.weather = Object.assign(defaultState().weather, raw.weather || {});
      // migration: weather used to default to 0, which is outside WeatherType
      // (1..9) and has no art. Clamp a stored out-of-range value back in range.
      if (!(Number(s.weather.season) >= 1 && Number(s.weather.season) <= 4)) {
        s.weather.season = 1;
      }
      if (!(Number(s.weather.hoursType) >= 1 && Number(s.weather.hoursType) <= 4)) {
        s.weather.hoursType = 1;
      }
      if (!(Number(s.weather.weather) >= 1 && Number(s.weather.weather) <= 9)) {
        s.weather.weather = 1;
      }
      s.travel = Object.assign(defaultState().travel, raw.travel || {});
      s.furniture = Object.assign(defaultState().furniture, raw.furniture || {});
      s.furniture.compost = Object.assign(defaultState().furniture.compost, (raw.furniture || {}).compost || {});
      // Old saves started with no owned compost bin, making its entire UI invisible.
      if (!Array.isArray(s.furniture.compost.list) || !s.furniture.compost.list.length) {
        s.furniture.compost.list = [21000];
        s.furniture.compost.showIndex = 1;
      }
      // Preserve today's purchases when migrating the old lifetime-only stock ledger.
      if (!(raw.furniture || {}).shopDailyBought) {
        s.furniture.shopDay = merchantDayAt(Number(raw.lastSeen) || nowSec());
        s.furniture.shopDailyBought = Object.assign({}, s.furniture.shopBought);
      }
    }
  } catch (e) {
    console.error('[engine] save load failed, starting fresh:', e.message);
    report.action = 'new';
    report.reason = 'migrate-error';
  }
  // old saves predate the field, and a damaged one can hold anything
  if (!(Number(s.saveVersion) >= 1)) s.saveVersion = SAVE_VERSION;
  if (!Array.isArray(s.clovers) || s.clovers.length !== CLOVER_SLOTS) s.clovers = makeClovers();
  s.lastSeen = nowSec();
  s.__saveReport = report;
  return s;
}

/* ---------------------------------------------------------------- engine */

function createEngine(opts) {
  opts = opts || {};
  const savePath = opts.savePath || path.join(__dirname, '..', 'save', 'save.json');
  const verbose = opts.verbose !== false;
  const state = loadState(savePath);

  /* ---- 相册容量 (state-dependent) ------------------------------------------
     Owned「相册扩容」items = extra album pages: the client's 扩容 tip prints
     `getHouseItemCount(9000)` ("保留照片的页数+N") and its page count is derived from the
     picture list, so the HOUSE is the source of truth for the ceiling. */
  function albumExpansions() {
    const row = (state.items.house || []).find((h) => Number(h.item_id) === ALBUM_EXPAND_ITEM);
    const owned = Number(row && row.count) || 0;
    return Math.max(0, Math.min(owned, ALBUM_EXPANSION_SLOTS));
  }

  /** Pictures the album can hold: (30 + owned expansions) pages x 6 per page. */
  function albumCapacity() {
    return (ALBUM_BASE_PAGES + albumExpansions()) * ALBUM_PAGE_SIZE;
  }

  /** Grant every remaining 相册扩容 (the editor's 扩容相册到上限). */
  function grantAlbumExpansions() {
    const before = albumExpansions();
    if (!Array.isArray(state.items.house)) state.items.house = [];
    const row = state.items.house.find((h) => Number(h.item_id) === ALBUM_EXPAND_ITEM);
    if (row) row.count = Math.max(Number(row.count) || 0, ALBUM_EXPANSION_SLOTS);
    else state.items.house.push({ item_id: ALBUM_EXPAND_ITEM, count: ALBUM_EXPANSION_SLOTS });
    return {
      before, after: ALBUM_EXPANSION_SLOTS,
      pages: ALBUM_BASE_PAGES + ALBUM_EXPANSION_SLOTS,
      capacity: albumCapacity(),
    };
  }

  /* ---- 工作台制作 (state-dependent) --------------------------------------- */

  /** 图纸 -> 目标家具。
   *
   *  一张图纸对应的是一整个 **type 槽位**（例如"墙壁"），而同一 type 有很多 **风格**版本：
   *  10301 -> 1101(style2) … 1901(style10) 2001(style11) 10103(style101)。
   *  参考包往 `benchData`（= 工作台能做什么）里新增的 27 行，正好是**每种 type 里 style 最高
   *  的那一件**（2001..2027）—— 这既是"哪个风格可做"的答案，也是我们这个选择的依据。
   *  所以规则是：图纸决定 type，取该 type 下**在 benchData 里、style 最高**的那件（同 style 取 id 大的）。
   */
  const BLUEPRINT_TYPE = new Map();      // 图纸物品 id -> type
  const CRAFTABLE_BY_TYPE = new Map();   // type -> {furnitureId, style}
  const BLUEPRINT_FOR_TYPE = new Map();  // type -> 图纸物品 id
  (() => {
    const rows = (gamedata.tables && gamedata.tables.furnitureData) || {};
    const list = Array.isArray(rows) ? rows : Object.values(rows);
    const byDrawing = new Map();
    for (const v of list) {
      const fid = Number(v && v.id);
      const draw = Number(v && v.drawing);
      if (!Number.isFinite(fid) || !Number.isFinite(draw)) continue;
      if (!byDrawing.has(draw)) byDrawing.set(draw, []);
      byDrawing.get(draw).push(v);
      if (!BENCH_IDS.has(fid)) continue;                 // benchData 说了才算"能做"
      const type = Number(v.type);
      const cur = CRAFTABLE_BY_TYPE.get(type);
      const style = Number(v.style);
      if (!cur || style > cur.style || (style === cur.style && fid > cur.furnitureId)) {
        CRAFTABLE_BY_TYPE.set(type, { furnitureId: fid, style });
      }
    }
    for (const [draw, group] of byDrawing) {
      const types = new Set(group.map((v) => Number(v.type)));
      if (types.size !== 1) continue;                    // 说不清就不认这张图纸
      const type = [...types][0];
      BLUEPRINT_TYPE.set(draw, type);
      if (!BLUEPRINT_FOR_TYPE.has(type)) BLUEPRINT_FOR_TYPE.set(type, draw);
    }
  })();

  /** 【自设计】某件家具需要的材料（原版配方在服务端）。 */
  function craftMaterialsFor(furnitureId) {
    const def = FURNITURE_BY_ID.get(Number(furnitureId));
    if (!def) return null;
    const byStyle = CRAFT_MATERIALS_BY_STYLE[Number(def.style)];
    return (byStyle || CRAFT_DEFAULT_MATERIALS).map((m) => ({ item_id: m.item_id, count: m.count }));
  }

  function benchHas(itemId) {
    return (state.furniture.bench || []).indexOf(Number(itemId)) !== -1;
  }

  /** 台面上那张图纸（在 5–9 号"物品位"里）-> 将要做出的家具；没有就返回 null。 */
  function benchBlueprint() {
    const bench = state.furniture.bench || [];
    for (let i = 5; i < 10; i++) {
      const itemId = Number(bench[i]);
      if (!(itemId > 0)) continue;
      const it = ITEM_BY_ID.get(itemId);
      if (!it || it.type !== ITEM_TYPE_DRAWING) continue;
      if (!BLUEPRINT_TYPE.has(itemId)) continue;                 // 不认识的图纸
      const target = CRAFTABLE_BY_TYPE.get(BLUEPRINT_TYPE.get(itemId));
      if (!target) continue;                                     // 该 type 没有可做的（benchData 空）
      return { slot: i, itemId, furnitureId: target.furnitureId, type: BLUEPRINT_TYPE.get(itemId) };
    }
    return null;
  }

  /** 材料清单（数组里每个元素一份，"还差几份"由客户端自己算）。 */
  function craftMateList() {
    const craft = state.furniture.craft;
    if (craft && Array.isArray(craft.materials)) {
      const out = [];
      for (const m of craft.materials) for (let i = 0; i < m.count; i++) out.push(m.item_id);
      return out;
    }
    const bp = benchBlueprint();
    if (!bp) return [];
    const mats = craftMaterialsFor(bp.furnitureId) || [];
    const out = [];
    for (const m of mats) for (let i = 0; i < m.count; i++) out.push(m.item_id);
    return out;
  }

  function craftMissing() {
    const bp = benchBlueprint();
    if (!bp) return null;
    const mats = craftMaterialsFor(bp.furnitureId) || [];
    const missing = mats.filter((m) => getHaveItem(m.item_id) < m.count);
    return missing.length ? { bp, missing } : { bp, missing: [] };
  }

  /** 台面上出现图纸、且材料够 -> 开始制作（锁住工作台，材料当场扣掉）。
   *  返回 true 表示这一拍真的开工了。 */
  function maybeStartCraft() {
    if (state.furniture.craft) return false;
    const info = craftMissing();
    if (!info || info.missing.length) return false;
    const { bp } = info;
    const mats = craftMaterialsFor(bp.furnitureId) || [];
    for (const m of mats) addHouseItem(m.item_id, -m.count);
    (state.furniture.bench)[bp.slot] = -1;          // 图纸被用掉
    const now = nowSec();
    state.furniture.craft = {
      furnitureId: bp.furnitureId,
      drawing: bp.itemId,
      materials: mats,
      startedAt: now,
      finishAt: now + CRAFT_SECONDS,
    };
    state.furniture.benchLock = 1;
    save();
    return true;
  }

  /** 到点结算：家具入库、解锁工作台，并推 FurnitureFinish(21) 给客户端。 */
  function craftTick(ctx, now) {
    const craft = state.furniture.craft;
    if (!craft || now < Number(craft.finishAt || 0)) return false;
    const fid = Number(craft.furnitureId);
    state.furniture.craft = null;
    state.furniture.benchLock = 0;
    if (!Array.isArray(state.furniture.owned)) state.furniture.owned = [];
    if (state.furniture.owned.indexOf(fid) === -1) state.furniture.owned.push(fid);
    save();
    const ev = makeEvent(EV_FURNITURE_FINISH, [fid, craft.drawing || 0]);
    if (ctx) {
      ctx.push('furniture_load_furniture', handlers.furniture_load_furniture({}));
      ctx.push('item_load_items', handlers.item_load_items());
      ctx.push('notify_new_event', { event: ev });
    }
    return true;
  }

  /** GM/测试用：把某件家具的图纸+材料备齐并开始制作。 */
  function startCraftFor(furnitureId) {
    const fid = Number(furnitureId);
    const def = FURNITURE_BY_ID.get(fid);
    if (!def) return { ok: false, reason: '未知家具 id' };
    if (!BENCH_IDS.has(fid)) return { ok: false, reason: '这件家具不在工作台清单里（benchData）' };
    if (state.furniture.craft) return { ok: false, reason: '工作台正忙' };
    const type = Number(def.type);
    const target = CRAFTABLE_BY_TYPE.get(type);
    if (!target || target.furnitureId !== fid) {
      return {
        ok: false,
        reason: '图纸 10301 这类是"type 槽位"，这个 type 做出来的是 ' + (target ? target.furnitureId : '（无）'),
      };
    }
    const drawing = BLUEPRINT_FOR_TYPE.get(type);
    if (!Number.isFinite(drawing)) return { ok: false, reason: '这个 type 没有对应图纸' };
    addHouseItem(drawing, 1);                        // 图纸先备上（制作时会消耗）
    for (const m of craftMaterialsFor(fid) || []) {
      const have = getHaveItem(m.item_id);
      if (have < m.count) addHouseItem(m.item_id, m.count - have);
    }
    /* 图纸放进 5–9 号物品位（客户端的 setBenchItem 用的也是这几个位） */
    const bench = state.furniture.bench;
    let slot = -1;
    for (let i = 5; i < 10; i++) if (!(Number(bench[i]) > 0)) { slot = i; break; }
    if (slot < 0) return { ok: false, reason: '物品位满了' };
    addHouseItem(drawing, -1);
    bench[slot] = drawing;
    save();
    return maybeStartCraft() ? { ok: true } : { ok: false, reason: '材料没凑齐（不该发生，请报我）' };
  }
  const unknown = new Map();

  /* ---- items (mirrors client ItemModel) ---- */

  /** Persist + shape the reply for the three "replace other furniture" commands. */
  function finishReplace(kind, d) {
    const code = applyReplaceOther(state, kind, d);
    if (code !== -1) save();
    return { code };
  }

  /* ---- gift box (礼品盒) ---- */

  /** Total specialty SLOTS in the gift box. The client expands any count > 1
   *  into that many count-1 rows, so the cap is on the expanded slot count. */
  function giftBoxCount() {
    return (state.giftBox.specialtys || [])
      .reduce((a, s) => a + Math.max(1, Number(s.count) || 1), 0);
  }

  function addGiftSpecialty(itemId, n) {
    const cur = state.giftBox.specialtys.find((s) => s.item_id === itemId);
    if (cur) cur.count += n;
    else state.giftBox.specialtys.push({ item_id: itemId, count: n });
    return giftBoxCount();
  }

  /** `travel_load_gift` payload. Pictures carry their composed `layers` (the
   *  gift box renders them exactly like the album does). */
  function giftBoxPayload() {
    return {
      pictures: (state.giftBox.pictures || []).map(withLayers),
      specialtys: (state.giftBox.specialtys || []).map((s) => ({
        item_id: s.item_id, count: s.count,
      })),
    };
  }

  /* The furniture shop list the client renders. Each row must carry `shop_id`
     (looked up in FurnitureShopDB), `item_id` (looked up in ItemDB) and `num`
     (remaining purchases -- the client enables the buy button only when
     num > 0 and decrements it itself on success). Rows whose `has_item`
     prerequisite is not owned yet are withheld, which is exactly how the
     original chain gated them. */
  function furnitureShopList() {
    refreshMerchantDay();
    const out = [];
    for (const [shopId, row] of FURNITURE_SHOP) {
      const num = furnitureStock(row);
      if (num <= 0) continue;
      // `has_item` 0/absent = no prerequisite; otherwise it is a furniture id
      const need = Number(row.has_item) || 0;
      if (need && state.furniture.owned.indexOf(need) === -1) continue;
      out.push({ shop_id: shopId, item_id: Number(row.item_id), num });
    }
    out.sort((a, b) => {
      const oa = Number(FURNITURE_SHOP.get(a.shop_id).order) || 0;
      const ob = Number(FURNITURE_SHOP.get(b.shop_id).order) || 0;
      return oa - ob || a.shop_id - b.shop_id;
    });
    return out;
  }

  function refreshMerchantDay() {
    const day = merchantDayAt(nowSec());
    if (state.furniture.shopDay === day) return;
    state.furniture.shopDay = day;
    state.furniture.shopDailyBought = {};
    save();
  }

  function furnitureStock(row) {
    const limit = Number(row.limit);
    if (limit > 0 && !isWelfareRow(row)) return Math.max(0, limit - (state.furniture.shopBought[row.id] || 0));
    const dailyLimit = isWelfareRow(row) ? WELFARE_PER_DAY : (Number(row.shop_limit) || 1);
    return Math.max(0, dailyLimit - (state.furniture.shopDailyBought[row.id] || 0));
  }

  function merchantShop() {
    const shop_list = furnitureShopList();
    const now = nowSec(), day = merchantDayAt(now);
    const next = new Date(day * 1000);
    next.setDate(next.getDate() + 1);
    const hours = Number(process.env.FROG_SHOP_HOURS || 0);
    const start_time = hours > 0 ? day + Math.floor((24 - hours) * 1800) : day - 1;
    const end = hours > 0 ? start_time + hours * 3600 : Math.floor(next.getTime() / 1000);
    return { shop_list, start_time, leave_time: shop_list.length ? end : now - 1 };
  }

  let merchantStatusSeen;

  /** ItemModel.getHaveItem: house count plus one per bag/desk slot holding it. */
  function getHaveItem(itemId) {    let n = 0;
    const h = state.items.house.find((x) => x.item_id === itemId);
    if (h) n += h.count;
    if (state.items.bag.indexOf(itemId) !== -1) n += 1;
    if (state.items.desk.indexOf(itemId) !== -1) n += 1;
    return n;
  }

  function addHouseItem(itemId, n) {
    const cur = state.items.house.find((x) => x.item_id === itemId);
    if (cur) cur.count += n;
    else state.items.house.push({ item_id: itemId, count: n });
    // define.json's HaveItemMax = 99 is a real rule: no stack exceeds it. Only the
    // UPPER bound is clamped, because this same helper is also used to consume
    // (`addHouseItem(id, -1)`).
    const cap = Number(ORIG.haveItemMax) || 99;
    for (const row of state.items.house) {
      if (row.count > cap) row.count = cap;
    }
    state.items.house = state.items.house.filter((x) => x.count > 0);
    return getHaveItem(itemId);
  }

  /** Trim the mail list to define.json's MAIL_MAX (100), oldest first. */
  function trimMails() {
    const cap = Number(ORIG.mailMax) || 100;
    if (state.mails.length > cap) {
      state.mails.splice(0, state.mails.length - cap);
    }
  }

  /* ---- 回忆彩蛋 unlock rule (define.json MomentType) ----------------------
     MomentType = {frog_motion:1, egg_motion:2, guest:3, shop:4, egg_id:5}
     and every momentData row has a `type` plus a `param` naming its trigger:
       type 1 + param 'dokusyo_ie'/'knit'/'cut'/'sleep_2'  <- FrogMotionName values
       type 3 + param 'wugui'/'maotouying3'/'songshu'     <- a guest (Character.img)
       type 4 + param 'drummer'                            <- the merchant shop
     Types 2 (egg_motion) and 5 (egg_id) are easter-egg animations whose ids our
     engine has no source for, so they stay locked -- recorded, not faked. */
  function momentTrigger(type, param) {
    const table = (gamedata.tables && gamedata.tables.momentData) || {};
    const list = table.list || {};
    const hits = [];
    for (const k of Object.keys(list)) {
      const row = list[k];
      if (Number(row.type) !== Number(type)) continue;
      if (String(row.param) !== String(param)) continue;
      const id = Number(row.id);
      if (!state.moments) state.moments = [];
      if (state.moments.indexOf(id) === -1) {
        state.moments.push(id);
        hits.push(id);
      }
    }
    if (hits.length) {
      save();
      if (verbose) console.log(`[engine] moments unlocked by type ${type} ${param}: ${hits}`);
    }
    return hits;
  }

  /** A guest's art name, from Character.json's `img.index` ("mail_wugui" -> "wugui"). */
  function guestResName(idx) {
    const GDATA = (gamedata.tables && gamedata.tables.Character) || {};
    const rows = GDATA.data || [];
    const row = rows[idx];
    const index = row && row.img && row.img.index;
    return index ? String(index).replace(/^mail_/, '') : '';
  }

/* Advance the frog's 手工 work, lazily, the same way `refreshClovers` advances the
   clover farm when the client asks for it. The frog only works while it is AT HOME
   (status 0); each stage takes CRAFT_STAGE_SEC (OUR pacing -- the original schedule
   was server-side and is not in our snapshot). A finished 祈愿木牌 keeps its
   body/paper ids so the client can draw it, and stays in the list as a keepsake:
   the original reward for finishing one could NOT be recovered, so we invent none.
   Returns true when anything changed. */
/** A finished craft row. The two families complete at DIFFERENT states, straight
    from their own tables: `prayData.state` is [1,2,3,4] while `stampData.state` is
    [1,2,3] in every one of its 27 rows -- and the client resolves a stamp's art with
    `stampData[id].state.indexOf(stamp_state)`, which finds nothing past 3. Reading
    them with one threshold is what produced the blank seal picture. Module-level on
    purpose: pray_load_grays and the annual review both need it. */
function craftDone(kind, row) {
  const s = Number(row && row.state) || 0;
  return kind === 'stamp' ? s >= 3 : s > 3;
}

function advanceCraft(t) {
  const c = state.craft || (state.craft = { wishes: [], stamps: [], pending: [], seq: 0 });
  if (!Array.isArray(c.wishes)) c.wishes = [];
  if (!Array.isArray(c.stamps)) c.stamps = [];
  if (!Array.isArray(c.pending)) c.pending = [];
  if (typeof c.seq !== 'number') c.seq = 0;

  const T = gamedata.tables || {};
  const wishRows = T.prayData || {};
  const stampRows = T.stampData || {};
  const noteIds = Object.keys(T.prayNoteData || {});
  const wishIds = Object.keys(wishRows);
  const stampIds = Object.keys(stampRows);
  const atHome = !state.frog || state.frog.status === 0;
  let changed = false;

/** A finished 祈愿木牌 is STAMPED with a seal, and the client's detail card draws
     it like this (PrayCraftDetailRender.dataChanged):

       this.l_date.text = DateFormat.format(1000 * data.stamp_time, "YYYY.MM.DD")
       if (data.stamp && 0 != data.stamp_time) {
         var i = StampCraftDB.get(data.stamp);
         var n = i.state.indexOf(data.stamp_state);         // must be one of the table's states
         if (n >= 0) this.i_stamp.source = formatPathImage(i.pattern_pic[n]);
       }

     So the date comes from `stamp_time` -- NOT from our internal `make_time`, which
     is why the card showed NaN.NaN.NaN -- and the seal picture needs a REAL
     `stamp` id plus a `stamp_state` that exists in that stamp's own `state` list. */
  const CRAFT_STAMP_IDS = Object.keys(gamedata.tables.stampData || {}).map(Number);
  /** The highest state ANY stampData row knows (they are all [1,2,3]). */
  const CRAFT_STAMP_MAX = (() => {
    let m = 0;
    for (const row of Object.values(gamedata.tables.stampData || {})) {
      for (const v of (row && row.state) || []) m = Math.max(m, Number(v) || 0);
    }
    return m || 3;
  })();

  function stampWish(w, t) {
    w.stamp_time = t;                                  // the date the card prints
    if (!CRAFT_STAMP_IDS.length) return;
    const sid = CRAFT_STAMP_IDS[randInt(0, CRAFT_STAMP_IDS.length - 1)];
    const row = (gamedata.tables.stampData || {})[String(sid)] || {};
    const states = Array.isArray(row.state) ? row.state.map(Number) : [];
    w.stamp = sid;
    /* Middle stage of the seal's own progression, so the art exists whatever the
       row's list looks like. */
    w.stamp_state = states.length ? states[Math.min(states.length - 1, Math.floor(states.length / 2))] : 1;
  }

  for (const w of c.wishes) {
    if (w.state > 3 || t < w.make_time) continue;
    w.state += 1;
    if (w.state > 3) {
      /* The table's last stage lists the pieces that MAY be used ("102,103,104,
         105,106"), and the client draws a finished row from `body`/`paper` by
         looking each one up in PrayCraftBodyDB -- so these must be SINGLE ids, one
         picked from the list, not the raw comma string. */
      const row = wishRows[String(w.id)] || {};
      const pick = (v) => {
        const list = String(v == null ? '' : v).split(',')
          .map((s) => s.trim()).filter(Boolean);
        return list.length ? Number(list[randInt(0, list.length - 1)]) : 0;
      };
      const bodies = row.wood_body || [];
      const papers = row.paper || [];
      w.body = bodies.length ? pick(bodies[bodies.length - 1]) : 0;
      w.paper = papers.length ? pick(papers[papers.length - 1]) : 0;
      w.make_time = t;                       // finished now
      stampWish(w, t);                       // + the seal and the DATE the card shows
    } else {
      w.make_time = t + CRAFT_STAGE_SEC;
    }
    changed = true;
  }

  /* A stamp's progression is 1..CRAFT_STAMP_MAX (3): stampData's own `state` arrays
     are [1,2,3] in every one of the 27 rows, and the client picks the art with
     `stampData[id].state.indexOf(stamp_state)` -- a state of 4 indexes to -1, sets NO
     source, and the detail card comes out BLANK. So 3 is "finished" for a stamp. */
  for (const s of c.stamps) {
    if (Number(s.state) >= CRAFT_STAMP_MAX || t < s.time) continue;
    s.state = Number(s.state) + 1;
    s.time = Number(s.state) >= CRAFT_STAMP_MAX ? t : t + CRAFT_STAGE_SEC;
    changed = true;
  }

  /* Heal rows written BEFORE the two fields above existed (an existing save, or a
     wish that finished while the old build was running). Without this, the detail
     card keeps printing NaN.NaN.NaN and drawing no seal until a NEW wish is made --
     old saves would look unfixed. Persisted on the next save. */
  for (const w of c.wishes) {
    if (!craftDone('wish', w)) continue;
    const t0 = Number(w.stamp_time) || 0;
    if (t0 > 0 && Number(w.stamp) > 0 && w.stamp_state !== undefined) continue;
    if (!(t0 > 0)) w.stamp_time = Number(w.make_time) || t;
    if (!(Number(w.stamp) > 0) || w.stamp_state === undefined) {
      const keep = w.stamp_time;
      stampWish(w, keep);
      w.stamp_time = keep;
    }
    changed = true;
  }
  /* A stamp left at 4 by the old build is clamped back into the range its own table
     knows, which is also what makes its picture come back. */
  for (const s of c.stamps) {
    if (Number(s.state) > CRAFT_STAMP_MAX) { s.state = CRAFT_STAMP_MAX; changed = true; }
  }

  /* Start new work only when the previous piece is finished, so the list reads as a
     history of what the frog has been making. */
  if (atHome && wishIds.length && !c.wishes.some((w) => w.state <= 3)) {
    c.seq += 1;
    c.wishes.push({
      id: Number(wishIds[randInt(0, wishIds.length - 1)]),
      state: 1,
      body: '',
      paper: '',
      content: noteIds.length ? Number(noteIds[randInt(0, noteIds.length - 1)]) : 0,
      make_time: t + CRAFT_STAGE_SEC,
      u_id: c.seq,
    });
    changed = true;
  }
  if (atHome && stampIds.length && !c.stamps.some((s) => s.state < 3)) {
    c.seq += 1;
    c.stamps.push({
      id: Number(stampIds[randInt(0, stampIds.length - 1)]),
      state: 1,
      time: t + CRAFT_STAGE_SEC,
      u_id: c.seq,
    });
    changed = true;
  }

  /* Keep the history bounded; the client renders the whole list. */
  if (c.wishes.length > 30) c.wishes.splice(0, c.wishes.length - 30);
  if (c.stamps.length > 30) c.stamps.splice(0, c.stamps.length - 30);
  return changed;
}

/* Every postcard the player owns, as a Set of Picture-table ids.
   A card counts as owned wherever it currently sits: filed in the album, still
   waiting to be filed (`albumPending` / `albumPendingVisit`), in the recycle bin
   (`albumDeleted`, recoverable) or in the gift box -- the museum asks "do you have
   this postcard?", not "is it filed right now". */
function ownedPictureIds() {
  const box = (state && state.giftBox && state.giftBox.pictures) || [];
  const buckets = [
    (state && state.pictures) || [],
    (state && state.albumPending) || [],
    (state && state.albumPendingVisit) || [],
    (state && state.albumDeleted) || [],
    box,
  ];
  const out = new Set();
  for (const list of buckets) {
    for (const p of list || []) {
      if (p && typeof p.pic_id === 'number') out.add(p.pic_id);
    }
  }
  return out;
}

/* ------------------------------------------------ card / cake helpers */
/** The shared window value: always a future `end_time`, rolled on every load. */
function cardEnd() {
  return nowSec() + CARD_ROLL_DAYS * 86400;
}

/** museumday's window, pinned to the NEXT DAY BOUNDARY + MD_ROLL_DAYS.
    The client stores its `museumDay_popup` cookie keyed on String(end_time), so a value
    that changed on every load re-showed the invitation on every tap; rounding to the
    day keeps it stable while staying inside the int32 limit the close timer implies. */
function mdEnd() {
  const now = nowSec();
  const nextDay = now - (now % 86400) + 86400;
  return nextDay + (MD_ROLL_DAYS - 1) * 86400;
}

function scState() {
  if (!state.springCard) state.springCard = {};
  const s = state.springCard;
  if (!Array.isArray(s.tags) || s.tags.length !== 3) s.tags = [0, 0, 0];
  if (!Array.isArray(s.items)) s.items = [];
  if (!Array.isArray(s.taskItem)) s.taskItem = [];
  if (!Array.isArray(s.rewardList)) s.rewardList = [];
  return s;
}

function gcState() {
  if (!state.greetCard) state.greetCard = {};
  const s = state.greetCard;
  if (!Array.isArray(s.tags) || s.tags.length !== 3) s.tags = [0, 0, 0];
  if (!Array.isArray(s.items)) s.items = [];
  if (!Array.isArray(s.sendList)) s.sendList = [];
  if (!Array.isArray(s.getList)) s.getList = [];
  if (!Array.isArray(s.taskItem)) s.taskItem = [];
  return s;
}

function pcState() {
  if (!state.partyCake) state.partyCake = {};
  const s = state.partyCake;
  if (!Array.isArray(s.madeLayers)) s.madeLayers = [];
  if (!Array.isArray(s.shareGet) || s.shareGet.length !== 2) s.shareGet = [0, 0];
  if (!s.taskCounts || typeof s.taskCounts !== 'object') s.taskCounts = {};
  const part = Number(s.part);
  if (!(part >= 1 && part <= 5)) s.part = 1;
  const cs = Number(s.curState);
  if (!(cs >= 0 && cs <= 6)) s.curState = 0;
  return s;
}

/** `items` is an array of ROW OBJECTS ({item_id,num}) everywhere in these families. */
function cardAddItem(list, itemId, num) {
  const row = list.find((r) => Number(r.item_id) === Number(itemId));
  if (row) row.num = (Number(row.num) || 0) + num;
  else list.push({ item_id: Number(itemId), num });
}

/** A tag id weighted by the table's own `buy_weight`. */
function scPickTag() {
  if (!SC_TAGS.length) return 0;
  const total = SC_TAGS.reduce((n, t) => n + t.weight, 0);
  let roll = Math.random() * total;
  for (const t of SC_TAGS) {
    roll -= t.weight;
    if (roll <= 0) return t.id;
  }
  return SC_TAGS[SC_TAGS.length - 1].id;
}

/** 【自设计】 the share code is generated by the server; format unrecoverable. */
function cardCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < 6; i++) out += alphabet[randInt(0, alphabet.length - 1)];
  return out;
}

/* ---- 生日蛋糕: tasks are the material economy, and every one of them maps onto a
   real action this build already has (登录 / 商店购买 / 抽奖 / 分享 / 旅行). Task 4 is
   "看一次广告", which cannot exist offline; the client itself filters ids 3 and 4 out
   when the ads SDK is unsupported, so it is simply never progressed. */
function pcTaskProgress(type, amount) {
  const s = pcState();
  const row = PC_TASKS[String(type)];
  if (!row) return false;
  const total = Number(row.total) || 1;
  const cur = Number(s.taskCounts[String(type)] || 0);
  if (cur >= total) return false;
  const next = Math.min(total, cur + (amount || 1));
  s.taskCounts[String(type)] = next;
  if (next >= total) {
    /* The table's own payout lands in the PENDING counters; 领取 (get_mate) moves
       them into the spendable ones. */
    s.preCream = (s.preCream | 0) + (Number(row.cream) || 0);
    s.preSugar = (s.preSugar | 0) + (Number(row.sugar) || 0);
  }
  save();
  return next >= total;
}

/** The six task rows the view renders: it builds `cfg` from the table by `id`. */
function pcTaskRows() {
  const s = pcState();
  return Object.keys(PC_TASKS).map((k) => {
    const total = Number(PC_TASKS[k].total) || 1;
    const count = Number(s.taskCounts[k] || 0);
    return { id: Number(k), count: Math.min(count, total), is_done: count >= total ? 1 : 0 };
  });
}

function pcPayload() {
  const s = pcState();
  return {
    end_time: cardEnd(),
    cream: s.cream | 0,
    sugar: s.sugar | 0,
    pre_cream: s.preCream | 0,
    pre_sugar: s.preSugar | 0,
    cur_state: s.curState | 0,
    part: s.part | 0,                       // 1..5, never 0
    layers: s.madeLayers.slice(),               // an array of NUMBERS
    task_list: pcTaskRows(),
    share_get: s.shareGet.slice(0, 2),
  };
}

/* The quiz. `answer` must be EXACTLY three real item ids (the view loops 1..3 and
   calls ItemDB.get(...).img with no guard), and `reward` is 2 rows when the player
   got it right (that is what selects the "correct" art), else 1.

   Two things here were wrong and the player felt both:

   1) `qaCorrect` was 0-BASED while the client sends the option's 1-BASED position
      (`for (r=1; 3>=r; r++) ... cur_selete = r`). Whenever it came out 0 the
      question was UNANSWERABLE: every attempt was wrong, and because the client's
      button handler re-renders the question on a wrong answer, the only thing the
      player saw was the confirm button going grey again and again.
   2) the correct option is now the one the guest actually likes, from the same
      `taste` table the visitor gameplay reads -- the question is
      「以下哪个食物{0}看起来最喜欢？」, so a random pick made it a coin flip.

   `reward`: the reward screen is only ever reached with `cur_state == qa_reward`,
   i.e. after a CORRECT answer (a wrong one keeps the state at `qa` and re-asks), and
   the title it picks depends on `reward.length > 1`. So this list is always the
   correct-answer prize -- computing it from `cur_state === qa_reward` (the old code)
   meant it was still the SMALL prize at the one moment it was displayed, and the
   screen said 「答错了」 to a player who had just answered right. */
function pcQaPayload() {
  const s = pcState();
  if (!Array.isArray(s.answer) || s.answer.length !== 3) {
    /* One clearly favourite item plus two the guest does not care for. The id space
       must be Specialty: that is what Character.rowItemId (the taste vector) is
       aligned to, and every row is a real Item the option slot can render. */
    s.guest = randInt(0, 2);                // which neighbour is asking (0-based)
    const guest = Number(s.guest) || 0;
    const scored = PC_QA_POOL
      .map((id) => ({ id, f: guestFeeling(guest, id) }))
      .sort((a, b) => b.f - a.f);
    const favourite = scored[0];
    const rest = scored.slice(-6);                        // the least liked ones
    const others = [];
    while (others.length < 2 && rest.length) {
      const pick = rest.splice(randInt(0, rest.length - 1), 1)[0];
      if (pick.id !== favourite.id && others.indexOf(pick) === -1) others.push(pick);
    }
    const options = shuffleIds([favourite].concat(others));
    s.answer = options.map((o) => o.id);
    s.qaCorrect = options.indexOf(favourite) + 1;         // 1-BASED, like the client
  }
  return {
    guest: s.guest | 0,
    wrong: s.wrong | 0,
    answer: s.answer.slice(),
    reward: pcQaRewardRows(),
  };
}

/** Exactly what `partycake_reward_qa` grants, so the screen cannot promise one
    thing and pay another. Both rows are table rows (PartyCakeData.light_reward /
    share_reward), not invented ids. */
function pcQaRewardRows() {
  return [
    { item_id: Number(PC_LIGHT_REWARD.item_id) || 204001, count: Number(PC_LIGHT_REWARD.item_num) || 2 },
    { item_id: PC_SHARE_REWARD[0] || 14, count: 1 },
  ];
}


/* ------------------------------------------------ 博物馆冒险 helpers */
/* The client REPLACES its model on load, so `state.museumday` exists only to keep
   the run across sessions; everything the client sees is shaped in mdPayload. */
function ensureMuseumday() {
  if (!state.museumday) {
    state.museumday = {
      endTime: 0,
      compass: MD_COMPASS_START,
      inspireNum: 0,
      inspireTime: 1,             // 【自设计】>0 and already past => 鼓舞 usable now
      taskNum: 0,
      leftNum: MD_RESTARTS,
      curMuseum: 0,
      frog: 1,
      next: 1,
      descId: MD_DESC_END,
      path: [],
      items: [],
      getItems: [],
      museums: [],
      logList: [],
    };
  }
  const s = state.museumday;
  if (!Array.isArray(s.path)) s.path = [];
  if (!Array.isArray(s.items)) s.items = [];
  if (!Array.isArray(s.getItems)) s.getItems = [];
  if (!Array.isArray(s.museums)) s.museums = [];
  if (!Array.isArray(s.logList)) s.logList = [];
  return s;
}

/** A loot message for `museum`, taken from the client's own museumDayDesc rows.
    Rows 1-5 / 101-105 / 201-205 / 301-305 belong to museums 1..4 in order. */
function mdLootDesc(museumId, num, itemName) {
  /* Only 1..5 and 101..105 are "picked something up" rows (both read
     「得到了{0}个{1}」). 201..205 are flavour with NO placeholders and 301..305 name a
     specific museum + ticket, so neither may describe a generic item find. */
  const base = Number(museumId) % 2 === 0 ? 100 : 0;
  const row = MD_DESC_ROWS[String(base + randInt(1, 5))];
  if (typeof row !== 'string') return '拾获 ' + num + ' 个' + itemName;
  return row.replace('{0}', String(num)).replace('{1}', String(itemName));
}

function mdMergeItem(list, itemId, num) {
  const row = list.find((r) => Number(r.item_id) === Number(itemId));
  if (row) row.num = (Number(row.num) || 0) + num;
  else list.push({ item_id: Number(itemId), num });
}

/* A monotonic route on the client's own 7x5 board: it only ever steps right or up, so
   it cannot revisit a tile and every pair of neighbours is orthogonally adjacent,
   which is what the client's grid maths assumes. 【自设计】 */
function mdBuildPath(museumId) {
  const len = randInt(8, 16);
  const cells = [];
  let col = randInt(0, 2);
  let row = 0;
  const seen = {};
  const put = () => { seen[1 + col + MD_GRID_W * row] = 1; cells.push({ col, row }); };
  put();
  while (cells.length < len) {
    const canRight = col < MD_GRID_W - 1;
    const canUp = row < MD_GRID_H - 1;
    if (!canRight && !canUp) break;
    const goRight = canRight && (!canUp || cells.length % 2 === 1);
    if (goRight) col += 1; else row += 1;
    if (seen[1 + col + MD_GRID_W * row]) break;
    put();
  }
  return cells.map((c, i) => {
    const grid = 1 + c.col + MD_GRID_W * c.row;
    if (i === 0) return { grid, type: 0, style: 0 };                        // start
    if (i === cells.length - 1) return { grid, type: 0, style: museumId };   // the museum
    return { grid, type: 2, style: i % 2 === 1 ? 1 : 2 };                    // road tiles
  });
}

/** What a revealed tile gives. 【自设计】: the original loot table lived on the
    server. About a third of the road tiles carry a souvenir, and some carry a 罗盘
    -- which is a CURRENCY here, not a bag item (the client's own list skips it), so
    it is credited straight to `compass`. */
function mdTileLoot(s) {
  if (Math.random() < 0.2) {
    s.compass += 1;
    s.logList.push({
      desc: '捡到了 1 个罗盘', item_id: MD_COMPASS_ID, item_num: 1, time: nowSec(),
    });
  }
  if (SPECIALTY_IDS.length && Math.random() < 0.34) {
    const itemId = SPECIALTY_IDS[randInt(0, SPECIALTY_IDS.length - 1)];
    const num = Math.random() < 0.25 ? 2 : 1;
    const item = ITEM_BY_ID.get(itemId);
    mdMergeItem(s.items, itemId, num);
    s.logList.push({
      desc: mdLootDesc(s.curMuseum, num, item ? item.name : ''),
      item_id: itemId,
      item_num: num,
      time: nowSec(),
    });
  }
  if (s.logList.length > 40) s.logList.splice(0, s.logList.length - 40);
}

/** 结算 reward. 【自设计】: the museum's own ticket plus its postcards -- the
    postcards are what make the 博物馆图鉴 page light up, because its slots are keyed
    by museumData.pic_id. A leftover 罗盘 is deliberately NOT converted:
    museumDayCommon.base.v3 = 10 and mail_str.v3 (「回收剩余的罗盘」) show the
    original did convert it, but the RATE is not recoverable, so the compass simply
    carries over to the next adventure rather than inventing one. */
function mdArrivalRewards(ctx, s) {
  const ticket = MD_TICKET_IDS[s.curMuseum];
  if (ticket) {
    grantItem(ctx, ticket, 1);
    /* 301..304 are literally "…获得了1张<museum>门票", one per museum in the same order
       as the ticket items, so this line matches exactly what was just granted. */
    const line = MD_DESC_ROWS[String(300 + Number(s.curMuseum))];
    if (typeof line === 'string') {
      s.logList.push({ desc: line, item_id: ticket, item_num: 1, time: nowSec() });
    }
  }
  const rows = (gamedata.tables && gamedata.tables.museumData) || {};
  const m = rows[String(s.curMuseum)];
  const picIds = (m && Array.isArray(m.pic_id) ? m.pic_id : []).map(Number);
  for (const pic of picIds) {
    if (state.pictures.some((p) => p && p.pic_id === pic)) continue;
    if (state.albumPending.some((p) => p && p.pic_id === pic)) continue;
    state.pictureSeq = (state.pictureSeq || 0) + 1;
    state.albumPending.push({ id: state.pictureSeq, pic_id: pic, read: 0, new: 1 });
  }
}

/** Which museum this run goes to: one not finished yet, else any. 【自设计】 */
function mdPickMuseum(s) {
  const done = {};
  for (const m of s.museums) done[m.id] = 1;
  const fresh = MD_MUSEUMS.filter((id) => !done[id]);
  const pool = fresh.length ? fresh : MD_MUSEUMS;
  return pool[randInt(0, pool.length - 1)];
}

/* The 16 keys `museumday_load` must carry. `frog`/`next` are 1-based indices into
   `path`, so they are clamped to 1..path.length: out of range makes the client read
   `path[n-1].grid` of undefined and throw. `left_num` must never be -1, because the
   history page reads `-1 != left_num` to decide whether 下一座博物馆 does anything. */
function mdPayload(s) {
  const n = s.path.length;
  const clamp = (v) => Math.max(1, Math.min(Number(v) || 1, Math.max(1, n)));
  return {
    end_time: s.endTime | 0,
    start_time: 0,                        // the client never reads it
    inspire_num: s.inspireNum | 0,
    inspire_time: s.inspireTime | 0,
    museum_list: s.museums.map((m) => ({ id: m.id, desc_id: m.desc_id, time: m.time })),
    cur_museum: MD_MUSEUMS.indexOf(Number(s.curMuseum)) !== -1 ? Number(s.curMuseum) : 0,
    compass: s.compass | 0,
    task_num: Math.max(0, Math.min(8, s.taskNum | 0)),
    frog: s.curMuseum ? clamp(s.frog) : 1,
    next: s.curMuseum ? clamp(s.next) : 1,
    left_num: Math.max(0, s.leftNum | 0),
    desc_id: s.descId === 402 ? 402 : MD_DESC_END,
    pic_id: 0,                            // the client only passes it through
    items: s.items.map((i) => ({ item_id: Number(i.item_id), num: Number(i.num) || 1 })),
    get_items: s.getItems.map((i) => ({ item_id: Number(i.item_id), num: Number(i.num) || 1 })),
    log_list: s.logList.map((l) => ({
      desc: String(l.desc), item_id: Number(l.item_id),
      item_num: Number(l.item_num) || 1, time: Number(l.time) || 0,
    })),
    path: s.curMuseum
      ? s.path.map((t) => ({ grid: t.grid, type: t.type, style: t.style })) : [],
  };
}


  /* ------------------------------------------------------------- unlocks
     Granting these is what the player asked for in place of the museum adventure: the
     图鉴 (纪念品/特产) and the museum pages are driven by the SAME lists that a trip would
     fill, and the 百科 is derived from the flowers actually grown or brought home --
     `state.encyAll` overrides that derivation when everything is unlocked. */
  function unlockHandbook(ctx) {
    const cols = Object.keys(((gamedata.tables || {}).Collection) || {})
      .map(Number).filter((n) => Number.isFinite(n));
    const spes = SPECIALTY_IDS.slice();
    for (const id of cols) {
      if (state.handbook.collections.indexOf(id) === -1) state.handbook.collections.push(id);
    }
    for (const id of spes) {
      if (state.handbook.specialtys.indexOf(id) === -1) state.handbook.specialtys.push(id);
    }
    return { collections: state.handbook.collections.length, specialtys: state.handbook.specialtys.length };
  }

  /** Every museum's postcards and collectibles, so the 图鉴 pages are complete. */
  function unlockMuseum() {
    const rows = (gamedata.tables && gamedata.tables.museumData) || {};
    let pics = 0;
    let cols = 0;
    for (const key of Object.keys(rows)) {
      const m = rows[key];
      if (!m) continue;
      for (const raw of (Array.isArray(m.pic_id) ? m.pic_id : [])) {
        const pic = Number(raw);
        if (state.pictures.some((p) => p && p.pic_id === pic)) continue;
        if (state.albumPending.some((p) => p && p.pic_id === pic)) continue;
        state.pictureSeq = (state.pictureSeq || 0) + 1;
        state.pictures.push({ id: state.pictureSeq, pic_id: pic, read: 0, new: 0 });
        pics += 1;
      }
      for (const raw of String(m.collection_id == null ? '' : m.collection_id).split(',')) {
        const c = Number(String(raw).trim());
        if (!Number.isFinite(c)) continue;
        if (state.handbook.collections.indexOf(c) === -1) {
          state.handbook.collections.push(c);
          cols += 1;
        }
      }
    }
    state.museumUnlocked = true;
    return { pictures: pics, collections: cols };
  }

  /** Every furniture row the game ships, so the 家具 book is complete. */
  function unlockFurniture() {
    const rows = (gamedata.tables && gamedata.tables.furnitureData) || {};
    if (!Array.isArray(state.furniture.owned)) state.furniture.owned = [];
    let added = 0;
    for (const key of Object.keys(rows)) {
      const row = rows[key];
      const id = Number(row && (row.id !== undefined ? row.id : key));
      if (!Number.isFinite(id)) continue;
      if (state.furniture.owned.indexOf(id) === -1) {
        state.furniture.owned.push(id);
        added += 1;
      }
    }
    return { furniture: added, total: state.furniture.owned.length };
  }

  /* The client's ItemDB.get() has NO null guard, so pushing an item_update for an
     id that is not in Item.json throws inside doAddHouseItem. Keep that invariant
     in one place instead of trusting every call site. */
  function pushItemUpdate(ctx, itemId, count) {
    if (!ITEM_BY_ID.has(itemId)) {
      console.warn(`[engine] refusing item_update for unknown item id ${itemId}`);
      return false;
    }
    ctx.push('item_update', { item: { item_id: itemId, count } });
    return true;
  }

  /* Mirrors checkShopItemHideBefore: before_buy is a [kind, id] pair.
       ['shop', N] -> shop slot N must have been bought
       ['item', N] -> item N must be owned
     Only 'shop' occurs in this build's shopData, but 'item' is a real kind in the
     client, and an unrecognised kind must FAIL CLOSED rather than silently pass. */
  function shopPrereqMet(pre) {
    if (!Array.isArray(pre) || pre.length < 2) return true;
    const kind = pre[0];
    const id = pre[1];
    if (kind === 'shop') return (state.shopBought[id] || 0) > 0;
    if (kind === 'item') return getHaveItem(id) > 0;
    console.warn(`[engine] unknown before_buy kind ${JSON.stringify(kind)}`);
    return false;
  }

  /* Set only by an explicit player action (forceSaveOverwrite / importSave): it
     allows writing over a damaged primary that could not be archived. Deliberately
     a closure variable, NOT part of the state -- a persisted "I accepted the loss"
     flag would silently disable the protection in later sessions. */
  let allowMainOverwrite = false;

  /* ---- 套装/盲盒的拆包（见文件上方 GIFT_DATA 的说明）----------------------- */
  /** What is inside `itemId`, or null when it is not a package we know. */
  function packageContents(itemId) {
    const row = GIFT_DATA[String(itemId)];
    if (row && Array.isArray(row.item_id) && row.item_id.length) {
      return row.item_id.map((id, i) => ({
        item_id: Number(id),
        count: Number((row.item_num || [])[i]) || 1,
      }));
    }
    const one = (list) => (list.length ? [{ item_id: list[randInt(0, list.length - 1)], count: 1 }] : null);
    switch (Number(itemId)) {
      case 5101:
      case 5102: return one(SEED_IDS);
      case 5103: return one(FLOWER_IDS);
      case 5104: return one(MATERIAL_IDS);
      case 5105: return one(SPECIAL_MATERIAL_IDS);
      default: return null;
    }
  }

  /** Grant `count` of a purchased/gifted item. A package is OPENED immediately:
      its contents go to the house and `item_gift_open` is pushed so the player
      actually sees them (see the GIFT_DATA note). Returns the granted rows. */
  function grantItemOrPackage(ctx, itemId, count) {
    const n = Number(count) || 1;
    const contents = packageContents(itemId);
    if (!contents) {
      const have = addHouseItem(itemId, n);
      pushItemUpdate(ctx, itemId, have);
      return null;
    }
    const granted = contents.map((r) => ({ item_id: r.item_id, count: r.count * n }));
    for (const r of granted) addHouseItem(r.item_id, r.count);
    ctx.push('item_gift_open', { items: granted });
    for (const r of granted) pushItemUpdate(ctx, r.item_id, getHaveItem(r.item_id));
    if (verbose) {
      console.log(`[engine] opened package ${itemId} -> ${granted.map((g) => g.item_id + 'x' + g.count).join(', ')}`);
    }
    return granted;
  }

  function failSave(report, why, where) {
    report.lastError = why;
    report.blocked = false;
    report.failCount = (report.failCount || 0) + 1;
    console.error('[engine] save failed (' + why + ') at ' + where
      + ': the stored save is untouched, but the latest progress is NOT on disk'
      + (why === 'write-main' ? ' (a complete copy was left at ' + savePath + SAVE_TMP_SUFFIX + ')' : ''));
    try {
      if (typeof opts.onSaveError === 'function') opts.onSaveError({ why, where, report });
    } catch (e) { /* the host's warning hook must never break saving */ }
    return false;
  }

  /* tmp -> verify -> bak -> verify -> main -> verify -> drop tmp. The read-backs
     matter: localStorage.setItem can fail without throwing, so "it returned" is
     not evidence that the save landed. */
  function save() {
    const report = state.__saveReport || (state.__saveReport = makeSaveReport());
    if (Number(state.saveVersion) > SAVE_VERSION) {
      report.blocked = true;
      report.lastError = 'save-version-ahead';
      console.error('[engine] save refused: the stored save was written by a newer engine (saveVersion '
        + state.saveVersion + ' > ' + SAVE_VERSION + '). Playing on is safe, overwriting it is not.');
      return false;
    }
    if (report.protectMain) {
      report.blocked = true;
      report.lastError = 'protect-main';
      console.error('[engine] save refused: the stored save is unreadable and could not be archived, '
        + 'so overwriting it could destroy the only copy.');
      return false;
    }
    const text = JSON.stringify(state, null, 1);
    if (!writeText(savePath + SAVE_TMP_SUFFIX, text)) {
      return failSave(report, 'write-tmp', savePath + SAVE_TMP_SUFFIX);
    }
    const cur = readText(savePath);
    const curTry = parseSave(cur);
    if (cur != null && curTry.ok) {
      if (!writeText(savePath + SAVE_BAK_SUFFIX, cur)) {
        console.error('[engine] backup write failed (the save itself is still committed normally)');
      }
    } else if (cur != null && curTry.reason !== 'missing') {
      /* The stored save became unreadable while we were running (this is the
         mid-session half of the same guarantee the loader gives at boot). Keep the
         bytes first; refuse to write only if they could not be kept. */
      report.reason = curTry.reason;
      const kept = archiveDamagedPrimary(savePath, cur, report);
      console.error('[engine] stored save is unreadable (' + curTry.reason + ') and was kept at '
        + (report.corruptKept || 'NOWHERE'));
      if (kept.blocked && !allowMainOverwrite) {
        report.protectMain = true;
        return failSave(report, 'protect-main', savePath);
      }
      if (kept.blocked) {
        console.warn('[engine] overwriting an unarchivable damaged save: the player accepted this '
          + 'explicitly (import or forceSaveOverwrite)');
      }
      // the write below replaces it with a healthy save, so nothing is protected
      report.protectMain = false;
    }
    if (!writeText(savePath, text)) {
      return failSave(report, 'write-main', savePath);
    }
    dropText(savePath + SAVE_TMP_SUFFIX);
    report.blocked = false;
    report.lastError = null;
    report.lastSaveAt = nowSec();
    report.saves = (report.saves || 0) + 1;
    return true;
  }

  /* ---- clover rules (upstream: each slot regrows independently) ---- */
  function cloverStatus(slot, t) {
    const lh = slot.last_harvest;
    if (lh === -1) return 'empty';
    if (lh > 0 && lh + slot.rebirth_span > t) return 'growing';
    return 'ready';
  }

  function refreshClovers(t) {
    let changed = false;
    for (const slot of state.clovers) {
      if (slot.last_harvest > 0 && slot.last_harvest + slot.rebirth_span <= t) {
        // regrew: roll for a four-leaf clover
        slot.last_harvest = 0;
        if (Math.random() < FOUR_LEAF_CHANCE) { slot.element = 1; slot.sprite = 1; }
        else { slot.element = 0; slot.sprite = 1; }
        changed = true;
      }
    }
    return changed;
  }

  /* ------------------------------------------------------------ travel */

  // tolerant of an inverted range (e.g. min > max from bad env vars)
  const randInt = (a, b) => {
    const lo = Math.min(a, b), hi = Math.max(a, b);
    return lo + Math.floor(Math.random() * (hi - lo + 1));
  };

  function makeEvent(evtType, evtValue) {
    return { evt_type: evtType, evt_value: evtValue, evt_id: state.eventSeq++ };
  }

  /* ---- travel provisioning ------------------------------------------- */

  const isType = (id, type) => {
    const it = ITEM_BY_ID.get(id);
    return !!it && it.type === type;
  };

  /* The client's two storage UIs are BOTH slot-typed and it draws them by INDEX with
     no type check at all:
       BagItem  = {LunchBox:0, Amulet:1, Tool_1:2, Tool_2:3}
       DeskItem = {LunchBox_1:0, LunchBox_2:1, Amulet_1:2, Amulet_2:3, Tool_1..4:4..7}
     So gear has to come home to the slot it left from (see returnFrog). */
  const BAG_SLOT_TYPE = [ITEM_TYPE_LUNCHBOX, ITEM_TYPE_AMULET, ITEM_TYPE_TOOLS, ITEM_TYPE_TOOLS];
  const DESK_SLOT_TYPE = [ITEM_TYPE_LUNCHBOX, ITEM_TYPE_LUNCHBOX, ITEM_TYPE_AMULET,
    ITEM_TYPE_AMULET, ITEM_TYPE_TOOLS, ITEM_TYPE_TOOLS, ITEM_TYPE_TOOLS, ITEM_TYPE_TOOLS];

  /** Put one returning item back: its own slot, then any free slot of its type, then
      the other storage, then the house. Returns where it went. */
  function placeBack(id, want, from) {
    const tries = from === 'desk'
      ? [{ list: state.items.desk, types: DESK_SLOT_TYPE }, { list: state.items.bag, types: BAG_SLOT_TYPE }]
      : [{ list: state.items.bag, types: BAG_SLOT_TYPE }, { list: state.items.desk, types: DESK_SLOT_TYPE }];
    for (const t of tries) {
      if (Number.isInteger(want) && want >= 0 && want < t.list.length
          && t.list[want] === -1 && isType(id, t.types[want])) {
        t.list[want] = id;
        return 'slot';
      }
      for (let i = 0; i < t.list.length; i++) {
        if (t.list[i] === -1 && isType(id, t.types[i])) { t.list[i] = id; return 'slot'; }
      }
    }
    addHouseItem(id, 1);                       // both are full: it waits in the house
    return 'house';
  }

  // Repair misplaced slots from older saves before the client paints them by index.
  // Clear all wrong slots first, so swapped food/tools can return to their own kinds.
  const misplaced = [];
  for (const [from, types] of [['bag', BAG_SLOT_TYPE], ['desk', DESK_SLOT_TYPE]]) {
    const list = state.items[from];
    list.forEach((id, slot) => {
      if (id !== -1 && !isType(id, types[slot])) {
        misplaced.push({ id, slot, from });
        list[slot] = -1;
      }
    });
  }
  for (const row of misplaced) placeBack(row.id, row.slot, row.from);

  function returnsFromTrip(id) {
    const item = ITEM_BY_ID.get(id);
    // The koi-shaped jade charm (Item 1001) is the only reusable amulet.
    if (item && item.type === ITEM_TYPE_AMULET) return id === 1001;
    return !item || item.spend !== 1;
  }

  function packItem(from, d, ctx, remove) {
    const list = state.items[from];
    const types = from === 'bag' ? BAG_SLOT_TYPE : DESK_SLOT_TYPE;
    const pos = Number(d.pos) - 1;
    const id = remove ? -1 : Number(d.item_id);
    const refuse = () => {
      ctx.push('item_load_items', handlers.item_load_items());
      return { code: -1, conflict: 1 };
    };
    if (!Number.isInteger(pos) || pos < 0 || pos >= types.length
        || (!remove && !isType(id, types[pos]))) return refuse();
    const prev = list[pos];
    if (prev === id) return { code: 0, conflict: 0 };
    const owned = state.items.house.find(row => row.item_id === id);
    if (!remove && (!owned || owned.count < 1)) return refuse();
    // Moving into a slot reserves one unit; removing it returns that same unit.
    // Client addHouseItem/consumeHouseItem are stubs, so the engine owns both sides.
    list[pos] = id;
    if (prev !== -1) addHouseItem(prev, 1);
    if (!remove) addHouseItem(id, -1);
    for (const changed of [prev, id]) {
      if (changed === -1) continue;
      const row = state.items.house.find(item => item.item_id === changed);
      pushItemUpdate(ctx, changed, row ? row.count : 0);
    }
    save();
    return { code: 0, conflict: 0 };
  }

  /* Prepare a trip out of the bag AND the desk.
     The client's own BagItem enum fixes the bag layout: [LunchBox, Amulet, Tool,
     Tool]. The desk is not just a pantry either -- the game's own first-run text
     promises 「如果在桌子上放好了东西 … {0} 也会自己挑选东西出门旅行」, so whatever
     the bag is missing (an amulet, up to two tools) is picked up from the desk, and
     those items come home to their DESK slot afterwards.
     With no lunch box anywhere the frog STRAYS (放浪) -- in the reference build that
     trip brings back neither a photo nor a souvenir, so that has to be decided at
     departure, not at return.
     Consumables (spend === 1) are used up; durable gear (spend !== 1) comes home. */
  function provisionTrip() {
    let lunch = -1;
    let lunchFrom = 'none';
    const take = (arr, from) => {
      const i = arr.findIndex((id) => isType(id, ITEM_TYPE_LUNCHBOX));
      if (i < 0) return false;
      lunch = arr[i];
      arr[i] = -1;
      lunchFrom = from;
      return true;
    };
    if (!take(state.items.bag, 'bag')) take(state.items.desk, 'desk');

    /* Carry each item WITH the slot and the storage it came from. */
    const carried = [];
    state.items.bag.forEach((id, slot) => { if (id !== -1) carried.push({ slot, id, from: 'bag' }); });

    const bagTools = carried.filter((r) => isType(r.id, ITEM_TYPE_TOOLS)).length;
    const hasAmulet = carried.some((r) => isType(r.id, ITEM_TYPE_AMULET));
    const deskPick = (wantType, limit) => {
      let taken = 0;
      state.items.desk.forEach((id, slot) => {
        if (taken >= limit || id === -1 || !isType(id, wantType)) return;
        carried.push({ slot, id, from: 'desk' });
        state.items.desk[slot] = -1;           // it travels with the frog now
        taken += 1;
      });
      return taken;
    };
    if (!hasAmulet) deskPick(ITEM_TYPE_AMULET, 1);
    deskPick(ITEM_TYPE_TOOLS, Math.max(0, 2 - bagTools));

    const amuletRow = carried.find((r) => isType(r.id, ITEM_TYPE_AMULET));
    const tools = carried.filter((r) => isType(r.id, ITEM_TYPE_TOOLS)).length;
    const carryBack = carried.filter((r) => returnsFromTrip(r.id));
    state.items.bag = state.items.bag.map(() => -1);
    return {
      lunch, lunchFrom, amulet: amuletRow ? amuletRow.id : -1,
      amuletSlot: amuletRow ? amuletRow.slot : -1,
      tools, carryBack, stray: lunch === -1, at: nowSec(),
      /* The ids as well as the rows: the destination walker reads each item's
         `effects` column (便当的时长/幸运、护身符的目的地、道具的特殊路线) and does
         not care where the item came from. Old saves have no `carried` -- the
         walker then simply has no effects, exactly like an empty bag. The LUNCH is
         listed explicitly -- `take()` already emptied its slot, so the bag alone
         would silently lose the item whose HP decides the trip's length. */
      carried: (lunch > 0 ? [lunch] : []).concat(carried.map((r) => r.id)),
    };
  }

  /* Roll one trip's outcome.

     Two paths:
       (a) the DESTINATION path -- `travelMap` is present, so the frog walks the
           original area/route graph, the postcards come from the NodeEdge tags it
           actually walked, the souvenirs come from the NodeItem rows of the nodes
           it actually reached, and a reached goal adds the destination postcard.
           Everything is table-driven; see the 目的地系统 block above.
       (b) the LEGACY path -- no map file: the flat uniform roll this engine used
           before, with the original server's tuning table (Define) percentages:
             SPECIALTY_PER / BASE_PICTURE_PER / PICTURE_TOOLS_PLUSPER / *_GETMAX
     Both honour the same contract: 放浪 (a trip that left without a lunch box)
     brings back neither a photo nor a souvenir. */
  function rollTripRewards(plan) {
    const stray = !!(plan && plan.stray);
    const out = {
      clover: 0, ticket: 0, collection: -1, items: [], pictures: [], stray,
      notes: [], flags: [], area: '', goal: null, steps: 0, minutes: 0, museum: false,
    };
    if (stray) {
      out.clover = randInt(1, 2);
      return out;
    }

    const mapped = tvRollTrip(plan, {
      visitedAreas: (state.travel && state.travel.visited && state.travel.visited.areas) || {},
      ownedTags: albumOwnedTags(),
      ownedCollections: (state.handbook && state.handbook.collections) || [],
    });
    if (mapped) {
      out.clover = mapped.clover;
      out.ticket = mapped.ticket;
      out.collection = mapped.collection;
      out.items = mapped.items;
      out.pictures = mapped.pictures;
      out.notes = mapped.notes;
      out.flags = mapped.flags;
      out.area = mapped.area;
      out.goal = mapped.goal;
      out.steps = mapped.steps;
      out.minutes = mapped.minutes;
      out.museum = mapped.museum;
      /* 手工拼装的材料: one of the three 木片, rarely. OURS -- no table places these
         items and the client never mentions them (search 8501: 0 hits), so in the
         original they were a pure server grant. Without a source here the 三拼 box
         could never be used, so the frog brings one home now and then. */
      if (COMPOSE_PIECE_IDS.length && Math.random() * 100 < COMPOSE_PIECE_CHANCE) {
        out.items.push(COMPOSE_PIECE_IDS[randInt(0, COMPOSE_PIECE_IDS.length - 1)]);
      }
      const itemMax = Number(DEF('TRAVEL_ITEM_GETMAX', 10));
      while (out.items.length > itemMax) out.items.pop();
      return out;
    }

    /* ---------------- legacy uniform roll (kept as the no-map fallback) ------ */
    out.clover = randInt(1, 3);
    if (Math.random() < 0.45) out.ticket = 1;

    const itemMax = Number(DEF('TRAVEL_ITEM_GETMAX', 10));
    if (SPECIALTY_IDS.length && Math.random() * 100 < Number(DEF('SPECIALTY_PER', 60))) {
      out.items.push(SPECIALTY_IDS[randInt(0, SPECIALTY_IDS.length - 1)]);
    }
    if (COMPOSE_PIECE_IDS.length
        && Math.random() * 100 < COMPOSE_PIECE_CHANCE) {
      out.items.push(COMPOSE_PIECE_IDS[randInt(0, COMPOSE_PIECE_IDS.length - 1)]);
    }
    // one souvenir-collection for the BackHome event (evt_value[4])
    if (COLLECTION_IDS.length && Math.random() * 100 < Number(DEF('COLLECT_PER', [15])[0])) {
      out.collection = COLLECTION_IDS[randInt(0, COLLECTION_IDS.length - 1)];
    }

    const toolBonus = (defineData.maps.PICTURE_TOOLS_PLUSPER || {})[String(plan ? plan.tools : 0)] || 0;
    const per = Number(DEF('BASE_PICTURE_PER', 70)) + Number(toolBonus);
    const maxPic = Number(DEF('PICTURE_GETMAX', 4));
    if (PICTURE_IDS.length) {
      for (let i = 0; i < maxPic; i++) {
        if (Math.random() * 100 >= per) break;
        out.pictures.push(PICTURE_IDS[randInt(0, PICTURE_IDS.length - 1)]);
      }
    }
    while (out.items.length > itemMax) out.items.pop();
    return out;
  }

  /** Which postcards of each PictureTag series the player already owns (album +
      pending + gift box). 彩叶幸运草 uses exactly this to fill a gap. */
  function albumOwnedTags() {
    const owned = {};
    const add = (picId) => {
      const tag = TV_PIC_TAG[picId];
      if (!tag) return;
      if (!owned[tag]) owned[tag] = [];
      if (owned[tag].indexOf(picId) === -1) owned[tag].push(picId);
    };
    (state.pictures || []).forEach((p) => { if (p) add(Number(p.pic_id)); });
    (state.albumPending || []).forEach((p) => { if (p) add(Number(p.pic_id)); });
    (((state.giftBox || {}).pictures) || []).forEach((p) => { if (p) add(Number(p.pic_id)); });
    return owned;
  }

  /** A departure requires food in a food slot, in the bag or on the desk. */
  function tripPrepared() {
    return isType(state.items.bag[0], ITEM_TYPE_LUNCHBOX)
      || state.items.desk.slice(0, 2).some(id => isType(id, ITEM_TYPE_LUNCHBOX));
  }

  function departFrog(ctx, t) {
    if (!tripPrepared()) return null;
    state.travel.waitingForBag = false;
    // Provisions are decided (and consumed) at DEPARTURE: the stray-or-not outcome
    // depends on whether a lunch box was packed, so it cannot be deferred.
    state.travel.plan = provisionTrip();
    state.frog.status = 1;                       // 1 = away (Tabikaeru.Game.isHome)
    state.frog.motion = 0;
    state.travel.departAt = t;
    // A 放浪 (stray) trip -- one that left WITHOUT a lunch box -- comes back on
    // the table's own shorter window (FROG_DRIFTRETURNTIME 10 / _MAX 20), which
    // we previously ignored and so gave a stray the full travel window.
    const stray = !!(state.travel.plan && state.travel.plan.stray);
    let window = stray
      ? randInt(DRIFT_RETURN_MIN, DRIFT_RETURN_MAX)
      : randInt(TRAVEL_MIN_SEC, TRAVEL_MAX_SEC);
    if (!stray) {
      /* 便当 effects[HP] 决定旅行时长: Define.BASE_HP = 100 is the anchor, so a
         茄汁蛋包饭 (H_MAXTIME 72) travels 1.72x as long as a bare trip. 门票
         shortens the trip 【自设计·换算】: its only effect is AREA_DECIDE(-2). */
      const carried = (state.travel.plan && state.travel.plan.carried) || [];
      window = Math.round(window * (1 + tvPacePct(carried) / 100));
      if (tvTicketArea(carried)) window = Math.round(window * 0.6);
    }
    state.travel.returnAt = t + Math.max(20, window);
    state.travel.nextDepartAt = 0;
    state.travel.tripCount = (state.travel.tripCount || 0) + 1;
    // 扭蛋任务 5 出趟远门 ("go on a trip") -- this is an internal function, not a
    // protocol command, so the central dispatch hook cannot see it.
    capsuleTaskDone(ctx, 5);
    // 料理任务 type 5 出门旅行1次
    cookingTaskProgress(5, 1);
    /* 生日蛋糕 task 6 "聚会或是旅行" -- an internal departure, so the same reason as above. */
    pcTaskProgress(6, 1);
    save();
    // evt_value[1] > 0 => the "energy" variant of the departure message
    const ev = makeEvent(EV_GO_TRAVEL, [0, 1]);
    ctx.push('client_load_role', rolePayload());
    ctx.push('item_load_items', handlers.item_load_items());
    ctx.push('notify_new_event', { event: ev });
    return ev;
  }

  function returnFrog(ctx, t) {
    const plan = state.travel.plan || null;
    const r = rollTripRewards(plan);
    state.frog.status = 0;                       // home again
    state.items.bagCompleted = 0;
    state.clover += r.clover;
    state.ticket += r.ticket;

    /* Durable gear comes home to the SLOT — and the STORAGE — it left from. Both
       UIs are typed and the client draws them by index with no type check at all
       (BagItem = {LunchBox:0, Amulet:1, Tool_1:2, Tool_2:3}: Bag.renderItem reads
       `getBagDataList()[i]` and just paints ItemDB.get(id).img into slot i), so
       pouring a bare id list back in from slot 0 put a 水壶 in the 便当 slot and a
       纸伞 in the 护身符 slot -- exactly the reported "回家后背包里的东西不是原来
       那些". Items the frog picked up from the DESK go back to the desk.
       Numbers are still accepted: trips planned by an older build stored the ids on
       their own, and those were always bag items. */
    if (plan && plan.carryBack) {
      for (const entry of plan.carryBack) {
        const isRow = entry && typeof entry === 'object';
        const id = Number(isRow ? entry.id : entry);
        const want = isRow ? Number(entry.slot) : -1;
        const from = isRow && entry.from === 'desk' ? 'desk' : 'bag';
        if (!(id > 0) || !returnsFromTrip(id)) continue;
        // already home somewhere?
        if (state.items.bag.indexOf(id) !== -1 || state.items.desk.indexOf(id) !== -1) continue;
        placeBack(id, want, from);
      }
    }

    for (const id of r.items) {
      /* COMPOSE materials (ItemType 16, the three 木片) are 材料, NOT 特产. The
         client's 特产 list is fed by type-3 rows, so filing a wooden chip there
         would show it among the souvenirs; a material belongs in the HOUSE, which
         is also where pray_compose looks for it. */
      const meta = ITEM_BY_ID.get(id);
      if (meta && meta.type === 16) {
        addHouseItem(id, 1);
        continue;
      }
      const existing = state.specialtys.find((s) => s.item_id === id);
      if (existing) existing.count += 1;
      else state.specialtys.push({ item_id: id, count: 1 });
      // the handbook lists Specialty itemIds so the 图鉴 stops being empty
      if (state.handbook.specialtys.indexOf(id) === -1) {
        state.handbook.specialtys.push(id);
      }
    }
    if (r.collection >= 0 && state.handbook.collections.indexOf(r.collection) === -1) {
      state.handbook.collections.push(r.collection);
    }
    /* 旅行笔记: the NodeEdge rows the frog walked name up to three Note ids each.
       Only ids that exist in the client's Note table may be handed out -- its
       TravelNoteModel.travel_load_note drops any unknown id silently. */
    let newNotes = 0;
    if (r.notes && r.notes.length) {
      if (!Array.isArray(state.notes)) state.notes = [];
      r.notes.forEach((id) => {
        if (state.notes.some((n) => n && n.id === id)) return;
        state.notes.push({ id, read: 0, timestamp: nowSec() });
        newNotes += 1;
      });
    }
    /* Which areas and destinations have been seen: A_NEW_AREA (四叶草 50) pulls
       the frog towards an area it has never been to, so this has to persist. */
    if (r.area) {
      if (!state.travel.visited) state.travel.visited = { areas: {}, goals: [] };
      if (!state.travel.visited.areas) state.travel.visited.areas = {};
      state.travel.visited.areas[r.area] = (state.travel.visited.areas[r.area] || 0) + 1;
      if (!Array.isArray(state.travel.visited.goals)) state.travel.visited.goals = [];
      if (r.goal && state.travel.visited.goals.indexOf(r.goal.name) === -1) {
        state.travel.visited.goals.push(r.goal.name);
      }
      /* 省份/稀有标记 carried by the souvenirs themselves (FL_RARE, FL_<province>,
         FL_<crop>): kept so the save records what has been seen. */
      if (r.flags && r.flags.length) {
        if (!Array.isArray(state.travel.flags)) state.travel.flags = [];
        r.flags.forEach((f) => { if (state.travel.flags.indexOf(f) === -1) state.travel.flags.push(f); });
      }
    }
    for (const pic of r.pictures) {
      // `id` is a unique monotonic handle the client uses for every album
      // operation; `pic_id` is the Picture table row that decides the artwork.
      // Both must be stored -- they are different fields.
      //
      // Newly earned pictures land in the PENDING bucket, which is what
      // `album_load_new` delivers and `album_save_new` files into the album.
      // That is the client's own flow (it rebuilds newPictureInfoList from that
      // payload and shows a save action); auto-filing straight into the album
      // would leave album_save_new / album_delete_new with nothing to act on.
      if (!state.pictures.some((p) => p && p.pic_id === pic)
        && !state.albumPending.some((p) => p && p.pic_id === pic)) {
        state.pictureSeq = (state.pictureSeq || 0) + 1;
        state.albumPending.push({ id: state.pictureSeq, pic_id: pic, read: 0, new: 1 });
      }
    }

    // the frog may also bring a cut flower home for the 庭院 -- decoration.json's
    // own text says "带一枝蜡梅回家", so this is where decorations come from
    const flower = rollDecoration();
    // ...and a story for a travel partner (see rollStory)
    const story = rollStory();

    state.travel.departAt = 0;
    state.travel.returnAt = 0;
    state.travel.plan = null;
    state.travel.nextDepartAt = t + randInt(TRAVEL_IDLE_MIN, TRAVEL_IDLE_MAX);
    // track how long the trip actually took: two achievements key off it
    if (plan && plan.at) {
      const dur = Math.max(0, t - plan.at);
      if (!state.travel.minTripSec || dur < state.travel.minTripSec) state.travel.minTripSec = dur;
      if (!state.travel.maxTripSec || dur > state.travel.maxTripSec) state.travel.maxTripSec = dur;
    }
    save();

    // evt_value: [_, _, clover, ticket, CollectionId, ...itemIds]
    // NOTE [4] is a Collection id (0..61), NOT a picture id -- see README.
    const ev = makeEvent(EV_BACK_HOME, [0, 0, r.clover, r.ticket, r.collection, ...r.items]);
    ctx.push('client_load_role', rolePayload());
    ctx.push('clover_update', { clover: state.clover });
    ctx.push('item_update_ticket', { ticket: state.ticket });
    ctx.push('item_load_items', handlers.item_load_items());
    ctx.push('item_load_handbook', handlers.item_load_handbook());
    ctx.push('travel_load_gift', giftBoxPayload());
    ctx.push('notify_new_event', { event: ev });
    /* A new 旅行笔记 does not pop anything: evt_type=15 only makes the client
       re-request `travel_load_note` (Result.eventSystem case NewNote). We push the
       event AND the payload so the note list is right either way. */
    if (newNotes > 0) {
      ctx.push('travel_load_note', handlers.travel_load_note());
      ctx.push('notify_new_event', { event: makeEvent(EV_NEW_NOTE, []) });
    }
    checkAchievements(ctx);        // a trip can unlock several at once
    return ev;
    return ev;
  }

  /* Advance time-driven state. Returns pushes for the caller to broadcast. */
  function tick() {
    const t = nowSec();
    const pushes = [];
    const ctx = { push: (c, d) => pushes.push({ cmd: toWire(c), data: d }) };
    refreshClovers(t);
    // season / time-of-day / weather: only push when something actually changed
    if (refreshWeather()) ctx.push('weather_load', weatherPayload());
    if (refreshFrogMotion(t)) ctx.push('client_load_role', rolePayload());
    const away = state.frog.status === 1;
    if (!away) {
      if (!state.travel.nextDepartAt) {
        state.travel.nextDepartAt = t + randInt(TRAVEL_IDLE_MIN, TRAVEL_IDLE_MAX);
        save();
      } else if (t >= state.travel.nextDepartAt) {
        // No food, no departure; tools and amulets alone cannot start a trip.
        if (tripPrepared()) {
          departFrog(ctx, t);
        } else {
          state.travel.waitingForBag = true;
          state.travel.nextDepartAt = t
            + randInt(TRAVEL_WAIT_UNPREPARED_MIN, TRAVEL_WAIT_UNPREPARED_MAX);
          save();
        }
      }
    } else if (t >= state.travel.returnAt) {
      returnFrog(ctx, t);
    }
    tickGuest(ctx, t);
    maybeVisitor(ctx);
    maybeDrawing(ctx);
    maybeLottery(ctx);
    maybePushShareLoad(ctx);
    checkAchievements(ctx);
    /* 工作台制作到点结算（离线也算：finishAt 是绝对时间，开机后第一拍就会结算） */
    craftTick(ctx, t);
    const merchantBefore = merchantStatusSeen;
    const furniture = handlers.furniture_load_furniture();
    if (merchantBefore !== undefined && merchantBefore !== merchantStatusSeen) {
      ctx.push('furniture_load_furniture', furniture);
    }
    return pushes;
  }

  /* ------------------------------------------------------- visitors */

  /* Character.json holds the three courtyard visitors (0 困困 / 1 胖胖 / 2 跳跳),
     each with a 64-value `taste` vector aligned to Character.rowItemId -- which
     holds Specialty item ids. So how much a visitor likes a given souvenir is a
     straight table lookup, and the client turns the number into one of four
     reactions itself (>=80 delighted, >=60 pleased, >=20 indifferent, else put
     off); the observed value set is {10,15,20,30,40,75,80,99}. */
  const CHARACTER = (gamedata.tables && gamedata.tables.Character) || {};
  const GUEST_ROW_ITEM_IDS = CHARACTER.rowItemId || [];
  const GUEST_DATA = CHARACTER.data || [];

  function guestFeeling(guestId, itemId) {
    const row = GUEST_DATA[guestId];
    if (!row || !Array.isArray(row.taste)) return 0;
    const i = GUEST_ROW_ITEM_IDS.indexOf(itemId);
    if (i < 0) return 0;
    return Number(row.taste[i]) || 0;
  }

  /* Exactly the five keys the client's GuestData knows about -- its constructor
     warns AND reports an error upstream (jf_commit) for any unknown key. And
     `id: -1` is its own "no visitor" value, which is how a visit is ended. */
  function guestPayload() {
    const g = state.guest;
    if (!g) return { id: -1, confirmed: false, served: false, expire_time: 0, pos: 0 };
    return {
      id: g.id, confirmed: !!g.confirmed, served: !!g.served,
      expire_time: g.expire_time, pos: g.pos,
    };
  }

  /* Cadence per Define: roll every FRIEND_VISIT_RNDSEC with FRIEND_VISIT_RNDPER%
     chance, then a FRIEND_VISIT_COOL cooldown after they leave. A visitor is
     cleared either by expiring or by `guest_finish`. */
  function tickGuest(ctx, t) {
    if (state.guest) {
      if (t >= state.guest.expire_time) {
        state.guest = null;
        state.guestCoolUntil = t + GUEST_COOL_SEC;
        state.guestNextRollAt = 0;
        save();
        ctx.push('guest_load', guestPayload());
      }
      return;
    }
    if (!state.guestNextRollAt) {
      state.guestNextRollAt = t + GUEST_ROLL_SEC;
      save();
      return;
    }
    if (t < state.guestNextRollAt) return;
    state.guestNextRollAt = t + GUEST_ROLL_SEC;
    if (t < (state.guestCoolUntil || 0)) { save(); return; }
    if (Math.random() * 100 >= GUEST_CHANCE) { save(); return; }
    state.guest = pickGuest();
    state.guestVisits = (state.guestVisits || 0) + 1;
    if (!state.firstGuest) state.firstGuest = Number(state.guest.id) || 0;
    save();
    // 回忆彩蛋 type 3 (guest): the moment's param is the guest's art name
    // (Character.data[i].img.index minus "mail_", e.g. "wugui" = 困困).
    const gres = guestResName(state.guest.id);
    if (gres) momentTrigger(3, gres);
    ctx.push('guest_load', guestPayload());
  }

  /* 串门访客 roll: same shape as the guest roll but on its own clock, and it
     pushes `visit_load` (the client's VisitorModel binds only that). */
  function maybeVisitor(ctx) {
    const t = nowSec();
    if (state.visitor) {
      if (t >= state.visitor.expire_time) {
        state.visitor = null;
        state.visitorCoolUntil = t + VISITOR_COOL_SEC;
        state.visitorNextRollAt = 0;
        save();
        ctx.push('visit_load', visitorPayload());
      }
      return;
    }
    if (!state.visitorNextRollAt) {
      state.visitorNextRollAt = t + VISITOR_ROLL_SEC;
      save();
      return;
    }
    if (t < state.visitorNextRollAt) return;
    state.visitorNextRollAt = t + VISITOR_ROLL_SEC;
    if (t < (state.visitorCoolUntil || 0)) { save(); return; }
    if (Math.random() * 100 >= VISITOR_CHANCE) { save(); return; }
    state.visitor = pickVisitor();
    save();
    ctx.push('visit_load', visitorPayload());
  }

  /* 【自设计】 how long a fed visitor stays before leaving (seconds). Long enough for
     the client's two feedback popups, short enough that the visit still visibly ends. */
  const GUEST_FAREWELL_SEC = 20;

  function pickGuest() {
    const n = GUEST_DATA.length || 3;
    return {
      id: randInt(0, n - 1),
      confirmed: false,
      served: false,
      expire_time: nowSec() + GUEST_STAY_SEC,
      pos: randInt(0, Math.max(0, GUEST_POS_MAX - 1)),
      // internal only -- the wire payload must carry exactly the five known keys
      startAt: nowSec(),
    };
  }

  /* ---- 友情绘本 (drawing) ---------------------------------------------------
     A THIRD visitor gameplay. The client's `guest_load_drawing(e)` does
       this.data = e; this.data.pages = convertArray(e.pages);
       this.data.colls = convertArray(e.colls);
     -- i.e. the payload REPLACES the whole model, so every field of
       {state, guest, bag, pages, colls, show_coll, pen_motion} must be sent.

     The two data tables (both keyed by id, and each row names the guest it
     belongs to):
       drawingPageData    {id, guest, pic}                     -- 画页
       drawingCollectData {id, guest, page, name, desc, info,
                           position, pic, scene, show}          -- 收藏品          */
  const DRAW_PAGES = (gamedata.tables && gamedata.tables.drawingPageData) || {};
  const DRAW_COLLS = (gamedata.tables && gamedata.tables.drawingCollectData) || {};

  function drawingPayload() {
    const d = state.drawing;
    return {
      state: d.state,
      guest: d.guest,
      bag: (d.bag || []).slice(),
      pages: (d.pages || []).slice(),
      colls: (d.colls || []).slice(),
      show_coll: d.showColl || 0,
      pen_motion: d.penMotion || 'write',
    };
  }

  /** Guests that own drawing content, so an invitation always has art for it.
   *  Rows with guest === -1 are SHARED content, not a guest: treating -1 as an
   *  inviter produced invitations from a guest that does not exist (found by
   *  running it, not by reading it). */
  function drawingGuestIds() {
    const ids = new Set();
    for (const src of [DRAW_COLLS, DRAW_PAGES]) {
      for (const k of Object.keys(src)) {
        const g = Number(src[k].guest);
        if (Number.isFinite(g) && g >= 0) ids.add(g);
      }
    }
    return Array.from(ids).sort((a, b) => a - b);
  }

  /** The next collectible this guest has not given yet, or null.
   *  A row with guest === -1 is shared, so any guest may hand it over. */
  function nextCollectible(guestId) {
    for (const k of Object.keys(DRAW_COLLS)) {
      const row = DRAW_COLLS[k];
      const id = Number(row.id);
      const g = Number(row.guest);
      if (g !== guestId && g !== -1) continue;
      if ((state.drawing.colls || []).indexOf(id) === -1) return id;
    }
    return null;
  }

  /** The next drawing page this guest has not given yet, or null. */
  function nextPage(guestId) {
    for (const k of Object.keys(DRAW_PAGES)) {
      const row = DRAW_PAGES[k];
      const id = Number(row.id);
      const g = Number(row.guest);
      if (g !== guestId && g !== -1) continue;
      if ((state.drawing.pages || []).indexOf(id) === -1) return id;
    }
    return null;
  }

  /* Roll for an invitation. Gated on owning the picture book, exactly like the
     client's isOpen(): without item 7001 the whole UI is closed, so inviting
     would be a dead end. */
  function maybeDrawing(ctx) {
    const t = nowSec();
    const d = state.drawing;
    if (getHaveItem(DRAWING_BOOK_ID) <= 0) return;

    if (d.state === 3 /* lock */ && state.drawingReturnAt && t >= state.drawingReturnAt) {
      // the guest comes back with a collectible and/or a page
      const g = d.guest;
      const coll = nextCollectible(g);
      const page = nextPage(g);
      const got = [];
      if (coll !== null) { d.colls.push(coll); got.push('coll:' + coll); }
      if (page !== null) { d.pages.push(page); got.push('page:' + page); }
      if (!got.length) {
        // nothing left to give: fall through to the visit branch
        d.state = 4; // visit
        state.drawingReturnAt = t + 60;
        save();
        ctx.push('guest_load_drawing', drawingPayload());
        return;
      }
      d.state = 0;                 // invitation finished; wait for the next partner
      d.bag = (d.bag || []).map(() => -1);
      d.guest = -1;
      state.drawingReturnAt = 0;
      state.drawingNextRollAt = t + DRAWING_ROLL_SEC;
      save();
      if (verbose) console.log(`[engine] drawing trip returned ${got.join(',')}`);
      ctx.push('guest_load_drawing', drawingPayload());
      return;
    }
    if (d.state === 1 || d.state === 2 || d.state === 3 || d.state === 4) return;
    if (!state.drawingNextRollAt) {
      state.drawingNextRollAt = t + DRAWING_ROLL_SEC;
      save();
      return;
    }
    if (t < state.drawingNextRollAt) return;
    state.drawingNextRollAt = t + DRAWING_ROLL_SEC;
    if (Math.random() * 100 >= DRAWING_CHANCE) { save(); return; }
    const guests = drawingGuestIds();
    if (!guests.length) return;
    d.state = 1;                   // DrawingState.invite
    d.guest = guests[randInt(0, guests.length - 1)];
    save();
    ctx.push('guest_load_drawing', drawingPayload());
  }

  /* ---- 庭院装饰 (decoration) ---------------------------------------------
     `decoration.json` rows are CUT FLOWERS (蜡梅/木槿/桂花/丁香/建兰…), each with
     `pic: [花苞, 花朵]` -- bud and bloom -- which is what `status` selects. Their
     own descriptions say where they come from: "带一枝蜡梅回家", so the frog
     brings them home from a trip. That is the source we use; the exact original
     drop rate is not in the client, so the chance below is OUR choice. */
  const DECORATIONS = (gamedata.tables && gamedata.tables.decoration) || {};
  const DECORATION_IDS = Object.keys(DECORATIONS).map(Number)
    .filter((n) => Number.isFinite(n)).sort((a, b) => a - b);
  const DECORATION_CHANCE = Number(process.env.FROG_DECORATION_CHANCE || 35);

  function addDecoration(id, n) {
    const list = state.decoration.hasList;
    const cur = list.find((x) => x.id === id);
    if (cur) cur.num += n;
    else list.push({ id, num: n });
    return list;
  }

  /** Give the frog a flower to have brought home, if the roll allows. */
  function rollDecoration() {
    if (!DECORATION_IDS.length) return 0;
    if (Math.random() * 100 >= DECORATION_CHANCE) return 0;
    const id = DECORATION_IDS[randInt(0, DECORATION_IDS.length - 1)];
    addDecoration(id, 1);
    return id;
  }

  /* ---- 料理 (CookingModel) ------------------------------------------------
     cookingData has months 1..24 (two 12-month theme sets; the client's
     `getSelectMonth()` is `month + 12*(select-1)`), each row naming a dish
     `{month, item_id, title, task_num, pic_id, show_desc}` with task_num = 6.

     cookingTaskData has 8 rows, and two of them are impossible in a pure-local
     build: id 2 "观看1次广告" and id 8 "完成1次分享". That leaves exactly SIX
     achievable rows (1,3,4,5,6,7) for task_num = 6 -- which is the set we deal.
     The ad/share rows are never dealt, rather than dealt and left uncompletable. */
  const COOKING_DISHES = (gamedata.tables && gamedata.tables.cookingData) || {};
  const COOKING_TASKS = (gamedata.tables && gamedata.tables.cookingTaskData) || {};
  const COOKING_BLOCKED_TYPES = [2, 8];      // 广告 / 分享

  function cookingTaskRows() {
    return Object.keys(COOKING_TASKS)
      .map((k) => COOKING_TASKS[k])
      .filter((r) => COOKING_BLOCKED_TYPES.indexOf(Number(r.type)) === -1)
      .sort((a, b) => Number(a.id) - Number(b.id));
  }

  function cookingDish(month, select) {
    const key = String(month + 12 * ((select || 1) - 1));
    return COOKING_DISHES[key] || null;
  }

  /** The month key for "now", 1..12 (theme 1). */
  function currentCookingMonth() {
    return new Date(nowSec() * 1000).getMonth() + 1;
  }

  function cookingDealTasks() {
    const C = state.cooking;
    const dish = cookingDish(C.month, C.select);
    const need = Number((dish && dish.task_num) || 6);
    C.taskList = cookingTaskRows().slice(0, need).map((r) => ({
      id: Number(r.id), pro: 0, complete: false,
    }));
    C.monthPro = 0;
    C.complete = false;
    return C.taskList;
  }

  function refreshCooking() {
    const C = state.cooking;
    if (!C.month) C.month = currentCookingMonth();
    if (!C.select) C.select = 1;
    C.week = Math.floor(nowSec() / (7 * 86400));
    C.refreshTime = nowSec() + 86400;
    if (!(C.taskList || []).length) cookingDealTasks();
    // cooking task type 1 is 每周登录游戏1次 ("log in once a week")
    if (C.lastWeek === undefined) C.lastWeek = C.week;
    else if (C.lastWeek !== C.week) {
      C.lastWeek = C.week;
      cookingTaskProgress(1, 1);
    }
    return C;
  }

  /** Advance the progress of whichever dealt task has this table `type`.
   *  Returns true when that task just became completable. */
  function cookingTaskProgress(type, amount) {
    const C = state.cooking;
    if (!C || !(C.taskList || []).length) return false;
    for (const row of C.taskList) {
      const def = COOKING_TASKS[String(row.id)];
      if (!def || Number(def.type) !== Number(type)) continue;
      if (row.complete) return false;
      if (row.pro >= Number(def.state)) return false;   // already at target
      row.pro = Math.min(Number(def.state), (row.pro || 0) + amount);
      save();
      return row.pro >= Number(def.state);
    }
    return false;
  }

  /* ---- 扭蛋活动 (CapsuleModel) -------------------------------------------
     capsuleData.json is the whole event:
       fast_consume : 30                     cost of fast-finishing a task
       reward       : {reward_id -> {id (ITEM id), num, type}}   30 entries, types 1/2/3
       num_reward   : thresholds 3/7/12 -> a bonus item
       task_list    : 8 real in-game actions ("采摘花草", "喂个小伙伴" ...)
     The client's `capsule_twist` has NO payload: the server draws and answers
     `{reward_id}`; the client then does `coin--` and pushes it onto
     `reward_list` itself. `reward_list.length >= 16` is only the red-dot rule. */
  /* ---- 动态照片 (AnimPictureModel) ---------------------------------------
     animpictureData is `{base_info, list, pic_map}`:
       base_info = {album_id: 9002, album_num: 4, page_id: 9001}
       list[slot] = {id, phase_list:[{layer, phase, spine}], pic_list:[...]}
       pic_map    = {pictureId -> slot}   -- ONLY 3 entries (100, 104, 2000),
     i.e. only those three postcards can be turned into a moving photo, and
     `phase_list.length == 1` means there is nothing to animate (phase 0). */
  /* ---- 故事 (StoryModel) ---------------------------------------------------
     story.json = `{const:{friend_choice_percent:25}, story:[25 rows
     {storyid, name, desc, icon, type}]}`. The `const` row is the original's own
     tuning value, so the partner-finds-a-story chance uses it rather than an
     invented number. A story row is an INSTANCE ({id, partner, name, gift,
     feedback}) referencing a table row by name. */
  const STORY_TABLE = ((gamedata.tables && gamedata.tables.story) || {}).story || [];
  const STORY_CHOICE_PERCENT = Number(
    (((gamedata.tables && gamedata.tables.story) || {}).const || {}).friend_choice_percent
    || 25);

  function rollStory() {
    if (!STORY_TABLE.length) return 0;
    if (Math.random() * 100 >= STORY_CHOICE_PERCENT) return 0;
    const book = state.storyBook || (state.storyBook = { list: [], newId: 0 });
    const row = STORY_TABLE[randInt(0, STORY_TABLE.length - 1)];
    book.seq = (book.seq || 0) + 1;
    const id = book.seq;
    book.list.push({
      id,
      partner: randInt(0, 2),          // 困困 / 胖胖 / 跳跳
      name: row.name,
      storyid: Number(row.storyid) || 0,
      gift: -1,                        // -1 = nothing given yet
      feedback: -1,
    });
    book.newId = id;
    return id;
  }

  const ANIM = (gamedata.tables && gamedata.tables.animpictureData) || {};
  const ANIM_LIST = ANIM.list || {};
  const ANIM_PIC_MAP = ANIM.pic_map || {};
  const ANIM_BASE = ANIM.base_info || {};

  function animPayload() {
    const A = state.animPicture;
    return {
      guide: A.guide || 0,
      page_num: A.pageNum || 0,
      phase: A.phase || 0,
      item_num: A.itemNum || 0,
      exp: A.exp || 0,
      exp_pic: (A.expPic || []).slice(),
      pic_list: (A.picList || []).map((p) => ({
        id: p.id,
        put_num: p.putNum || 0,
        pictures: (p.pictures || []).slice(),
      })),
    };
  }

  /** The phase a slot starts at: 0 when it has a single phase_list entry. */
  function animStartPhase(slotId) {
    const row = ANIM_LIST[String(slotId)];
    if (!row || !Array.isArray(row.phase_list)) return 0;
    return row.phase_list.length === 1 ? 0 : 1;
  }

  /** How many phases a slot walks through (table phases are 1-based). */
  function animPhaseCount(slotId) {
    const row = ANIM_LIST[String(slotId)];
    if (!row || !Array.isArray(row.phase_list)) return 0;
    return row.phase_list.reduce((a, p) => Math.max(a, Number(p.phase) || 0), 0);
  }

  const CAPSULE = (gamedata.tables && gamedata.tables.capsuleData) || {};
  const CAPSULE_REWARD = CAPSULE.reward || {};
  const CAPSULE_NUM_REWARD = CAPSULE.num_reward || {};
  const CAPSULE_TASKS = CAPSULE.task_list || {};
  const CAPSULE_FAST_COST = Number(CAPSULE.fast_consume || 30);
  /* Which command completes which 扭蛋 task, from capsuleData.task_list's own
     descriptions:
       1 采摘花草      <- clover_harvest
       2 准备个食物    <- putting food in the bag / desk / gift box
       3 花点三叶草    <- spending clover anywhere
       4 一次分享      <- SHARING, which this offline build cannot do. Left out
                          on purpose: that task simply never completes, and it is
                          not silently faked.
       5 出趟远门      <- departTrip (called by provisionTrip)
       6 喂个小伙伴    <- guest_serve
       7 花点兑换券    <- item_gacha (costs tickets)
       8 保存一张照片  <- album_save_new */
  const CAPSULE_TASK_FOR = {
    clover_harvest: 1,
    item_putin_bag: 2,
    item_putin_desk: 2,
    travel_bag_to_gift: 2,
    item_buy: 3,
    furniture_buy_shop: 3,
    wishingpool_wish: 3,
    departTrip: 5,
    guest_serve: 6,
    item_gacha: 7,
    album_save_new: 8,
  };

  /* 料理 tasks, same idea and same command sources -- but these carry PROGRESS,
     so the map gives a (type, amount) pair. Types come from cookingTaskData:
       1 每周登录游戏1次      3 喂养1次串门的小伙伴   4 累计获得80株三叶草
       5 出门旅行1次          6 获得1张照片           7 抽奖后兑换1次奖品
     Types 2 (观看广告) and 8 (分享) are unachievable offline and are never
     dealt, so they have no entry here either. */
  const COOKING_TASK_FOR = {
    clover_harvest: [4, 1],        // 累计获得三叶草 -- one per harvest
    item_putin_bag: null,          // no cooking task for these, kept explicit
    guest_serve: [3, 1],           // 喂养1次小伙伴
    departTrip: [5, 1],            // 出门旅行1次
    album_save_new: [6, 1],        // 获得1张照片
    item_redeem_prize: [7, 1],     // 抽奖后兑换1次奖品
  };
  const CAPSULE_DAYS = Number(process.env.FROG_CAPSULE_DAYS || 3650);
  const CAPSULE_START_COIN = Number(process.env.FROG_CAPSULE_COIN || 5);

  /** The tasks the client should DISPLAY, i.e. dealt and not yet finished, in deal
   *  order. The client's `task_list` is an array of IDS with no completion flag, so
   *  a finished task simply leaves the list, and `capsule_fast_task`'s 1-based
   *  `index` addresses THIS list (not the raw state array). */
  function capsuleOpenTasks() {
    return (state.capsule.taskList || []).filter((t) => !t.complete);
  }

  function capsulePayload() {
    const C = state.capsule;
    return {
      end_time: C.endTime || 0,
      coin: C.coin || 0,
      pre_coin: C.preCoin || 0,
      /* BOTH of these are arrays of IDS, not of objects. Read off the client:
           CapsuleUtils.getTaskCfg(id)  -> capsuleData.get("task_list")[id.toString()]
           CapsuleView.update()         -> getTaskCfg(this.data.task_list[0]).name
           CapsuleView.update()         -> capsuleData.get("reward")[reward.toString()]
         so an entry that is an object stringifies to "[object Object]", the table
         lookup misses, and `.name` throws "Cannot read properties of undefined" --
         which the client turns into Reload.JSError, i.e. 呱呱，吃坏肚子了. The
         client has NO completion flag on a task, so a finished task must simply
         LEAVE the list (the server decides that; the UI only shows the first two). */
      reward_list: (C.rewardList || []).map((r) => Number(r)),
      task_list: capsuleOpenTasks().map((t) => Number(t.id)),
      patch_num: C.patchNum || 0,
    };
  }

  /** Open the event. `isOpen()` is `now < end_time`, so 0 would disable it.
   *  The starting allowance is granted ONCE, behind a flag -- inferring it from
   *  `coin === 0` meant spending your last coin instantly re-granted the whole
   *  allowance (a unit test caught that). */
  function refreshCapsule(t) {
    const C = state.capsule;
    C.endTime = t + CAPSULE_DAYS * 86400;
    if (!C.started) {
      C.started = 1;
      C.coin = (C.coin || 0) + CAPSULE_START_COIN;  // OUR allowance (not recovered)
      // `patch_num` is the number of task slots still to be dealt, and the client
      // only ever calls `capsule_patch` when `patch_num > 0`
      // (`0 == task_list.length && patch_num > 0`). Nothing else ever set it, so
      // the task board stayed EMPTY FOREVER and `capsule_patch` was unreachable.
      // capsuleData has no "how many to deal" field, so the count is OUR choice.
      C.patchNum = Object.keys(CAPSULE_TASKS).length;
    }
    return C;
  }

  /** Deal tasks into the empty slots. `patch_num` is the remaining slot count. */
  function capsulePatch() {
    const C = state.capsule;
    const dealt = new Set((C.taskList || []).map((t) => Number(t.id)));
    const room = Math.max(0, (C.patchNum || 0));
    const out = [];
    for (const k of Object.keys(CAPSULE_TASKS).sort((a, b) => Number(a) - Number(b))) {
      if (out.length >= room) break;
      const id = Number(CAPSULE_TASKS[k].id);
      if (dealt.has(id)) continue;
      out.push({ id, name: CAPSULE_TASKS[k].name, desc: CAPSULE_TASKS[k].desc, complete: false });
      dealt.add(id);
    }
    C.taskList = (C.taskList || []).concat(out);
    C.patchNum = Math.max(0, (C.patchNum || 0) - out.length);
    return out;
  }

  /** Mark a dealt capsule task done. Called from the gameplay site it describes,
   *  which is how these tasks work: task_list ids are real actions. */
  function capsuleTaskDone(ctx, taskId) {
    const C = state.capsule;
    if (!C || !C.endTime) return false;
    const slot = (C.taskList || []).find((t) => Number(t.id) === Number(taskId));
    if (!slot || slot.complete) return false;
    slot.complete = true;
    if (!C.doneTasks) C.doneTasks = [];
    if (C.doneTasks.indexOf(Number(taskId)) === -1) C.doneTasks.push(Number(taskId));
    save();
    if (ctx) ctx.push('capsule_load_task', { task_list: capsulePayload().task_list });
    return true;
  }

  /** Award the threshold bonuses when reward_list crosses 3 / 7 / 12. */
  function capsuleThresholdBonuses(ctx) {
    const C = state.capsule;
    const n = (C.rewardList || []).length;
    const got = [];
    for (const k of Object.keys(CAPSULE_NUM_REWARD)) {
      const row = CAPSULE_NUM_REWARD[k];
      const need = Number(row.num || k);
      if (n >= need && Number(row.item_id) > 0) {
        const key = 'thr' + need;
        if (!C[key]) {
          C[key] = 1;
          addHouseItem(Number(row.item_id), Number(row.item_num) || 1);
          pushItemUpdate(ctx, Number(row.item_id), getHaveItem(Number(row.item_id)));
          got.push({ need, item_id: Number(row.item_id), n: Number(row.item_num) || 1 });
        }
      }
    }
    return got;
  }

  /* ---- 许愿池 (WishingPoolModel) -----------------------------------------
     Every entry the client renders is {id, num, limit} where `id` is the ITEM
     granted (it becomes `item_id` in the reward), `num` its count and `limit`
     the remaining stock. The client decrements `limit` itself after a
     successful wish, so the server has to do the real bookkeeping. */
  function wishPoolItems() {
    const W = state.wishingPool;
    if (!W.items || !W.items.length) {
      // Our prize list: real Items only, so the client's ItemDB lookup cannot
      // throw, each with a stock limit. Chosen by us, not recovered.
      const specials = SPECIALTY_IDS.slice(0, 8);
      W.items = [];
      for (let i = 0; i < specials.length; i++) {
        W.items.push({ id: specials[i], num: 1, limit: 3 });
      }
      const four = DEF('FourLeafCloverID', 1000);
      if (ITEM_BY_ID.has(four)) W.items.push({ id: four, num: 1, limit: 1 });
      /* 博物馆门票 (Item 1017..1021). 【自设计·来源】: in the live game these were
         handed out by 博物馆冒险 (museumday), which this build keeps switched OFF
         -- so with no source at all the whole museum branch of the destination
         system would be dead content. They are spend=1 (one visit each), so the
         pool keeps a small stock of three per museum. Every id is a real Item row
         (the client looks it up), and the pool's list is ours anyway. */
      TV_MUSEUM_TICKETS.forEach((id) => {
        if (ITEM_BY_ID.has(id)) W.items.push({ id, num: 1, limit: 3 });
      });
    }
    return W.items;
  }

  /** Open the pool and top the coins up (once per day). */
  function refreshWishingPool(t) {
    const W = state.wishingPool;
    W.endTime = t + WISH_POOL_DAYS * 86400;
    wishPoolItems();
    const day = Math.floor(t / 86400);
    if (W.lastGrantDay !== day) {
      W.lastGrantDay = day;
      W.coin = Math.min(WISH_POOL_COIN_MAX, (W.coin || 0) + WISH_POOL_COINS_PER_DAY);
    }
    return W;
  }

  /* ---- 抽奖 / 邻里美食交流 (LotteryModel) ----------------------------------
     A neighbour (困困/胖胖/跳跳/嘟嘟, from lotteryData.select_list) is deciding
     what to bring someone. You help by picking items; the result is scored 0..5
     and the client renders the matching line from lotteryData.settle_desc, plus
     lotteryData.extra_desc[guest][score] for the bonus item.

     RECONSTRUCTION, clearly labelled: the scoring rule lived on the server. We
     draw a hidden "wanted" set of LOTTERY_PICKS item ids when the phase starts,
     the score is the size of the intersection with the player's picks, and
     right_flag is the per-pick boolean the client ticks off. That is what makes
     settle_desc/extra_desc's 0..5 keys meaningful; the exact original set is
     not recoverable. */
  const LOTTERY_TABLE = (gamedata.tables && gamedata.tables.lotteryData) || {};
  const LOTTERY_SELECT = LOTTERY_TABLE.select_list || {};

  /** Items the player may offer: real Specialty rows, so every pick is grantable
      and every right_flag entry points at something that exists. Specialty is
      also the id space Character.rowItemId (the `taste` table) is aligned to. */
  function lotteryItemPool() {
    return SPECIALTY_IDS.slice();
  }

  /** Fisher-Yates over a copy. */
  function shuffleIds(arr) {
    const out = arr.slice();
    for (let i = out.length - 1; i > 0; i--) {
      const j = randInt(0, i);
      const t = out[i]; out[i] = out[j]; out[j] = t;
    }
    return out;
  }

  function lotteryPayload() {
    const L = state.lottery;
    return {
      last_phase: L.lastPhase || 0,
      phase: L.phase || 0,
      state: L.state || 0,
      select_list: (L.selectList || []).slice(),
      answer: (L.answer || []).slice(),
      extra_item: {
        item_id: (L.extraItem && L.extraItem.item_id) || 0,
        count: (L.extraItem && L.extraItem.count) || 0,
      },
      right_flag: (L.rightFlag || []).slice(),
      egg_num: L.eggNum || 0,
      reward: (L.reward || []).slice(),
    };
  }

  /** Start a fresh round: pick the helper guest and the hidden wanted set.
   *
   *  The wanted set is not arbitrary: it is the guest's own favourites, read from
   *  Character.json's `taste` vector -- the SAME table the visitor gameplay uses,
   *  and the only place the game says which souvenir a neighbour likes. That makes
   *  the round a real question ("which 5 would 困困 like?") instead of a coin flip,
   *  and makes settle_desc/extra_desc's 0..5 scoring reachable in both directions. */
  function startLotteryPhase() {
    const pool = lotteryItemPool();
    const L = state.lottery;
    L.lastPhase = L.phase || 0;
    L.phase = ((L.phase || 0) % LOTTERY_PHASES) + 1;
    L.state = LOTTERY_STATE.Open;
    L.answer = [];
    L.rightFlag = [];
    L.reward = [];
    L.extraItem = { item_id: 0, count: 0 };
    L.eggNum = 0;
    /* 0-based on purpose: the client reads its name array and its
       `neighbor_emote_<guest>_0_png` with this index. */
    L.guest = L.phase - 1;

    const liked = [];
    const disliked = [];
    for (const id of pool) {
      const f = guestFeeling(L.guest, id);
      if (f >= 60) liked.push(id);                 // >=60 = 「pleased」or better
      else if (f > 0 && f < 20) disliked.push(id); // <20 = 「put off」
    }
    /* Fall back to the whole pool if the taste table is missing/odd, so a round is
       always playable. */
    const wantFrom = liked.length >= LOTTERY_PICKS ? liked : pool;
    const want = [];
    while (want.length < Math.min(LOTTERY_PICKS, wantFrom.length)) {
      const id = wantFrom[randInt(0, wantFrom.length - 1)];
      if (want.indexOf(id) === -1) want.push(id);
    }
    const decoyFrom = disliked.filter((id) => want.indexOf(id) === -1);
    const decoyPool = decoyFrom.length >= (LOTTERY_OPTIONS - want.length)
      ? decoyFrom : pool.filter((id) => want.indexOf(id) === -1);
    const decoys = [];
    const wantDecoys = Math.min(LOTTERY_OPTIONS - want.length, decoyPool.length);
    while (decoys.length < wantDecoys) {
      const id = decoyPool[randInt(0, decoyPool.length - 1)];
      if (decoys.indexOf(id) === -1) decoys.push(id);
    }
    L.want = want;                      // INTERNAL: never sent to the client
    /* The order must NOT leak the answer: shuffling keeps the liked items from
       always sitting in the first five slots (which the client renders in order). */
    L.selectList = shuffleIds(want.concat(decoys));
    return L;
  }

  function maybeLottery(ctx) {
    const t = nowSec();
    const L = state.lottery;
    // a round is live until it is confirmed; do not overwrite it
    if (L.phase && L.state !== LOTTERY_STATE.Open) return;
    if (!state.lotteryNextRollAt) {
      state.lotteryNextRollAt = t + LOTTERY_ROLL_SEC;
      save();
      return;
    }
    if (t < state.lotteryNextRollAt) return;
    state.lotteryNextRollAt = t + LOTTERY_ROLL_SEC;
    if (Math.random() * 100 >= LOTTERY_CHANCE) { save(); return; }
    startLotteryPhase();
    save();
    ctx.push('lottery_load', lotteryPayload());
  }

  /* ---- 串门访客 (VisitorModel / VisitorData) --------------------------------
     This is a SECOND, SEPARATE gameplay from the 邻居 guest above: the client's
     GameplayModel lists both "邻居" (GuestData) and "串门" (VisitorData).

     VisitorData's field set (read from main.min.js -- an unknown key in the
     payload makes the client log a merge warning, and a MISSING key is left at
     its default, so all of these must be sent):
       partner, name, title, expire_time, city, food, first, gift{item_id,count}, carpet
     `city` is "<province>_<city>" and the client splits it on "_".
     Data comes from visitors.json:
       provinceList[<province>] = {ID, DisplayName, Province, Icon, FlowerName,
                                   FlowerIcon, FlowerDescribe, OtherGiftID,
                                   CountFloor, CountUpper}
     `OtherGiftID` is the repeat-visit gift id: 100000 = clover, 100001 = ticket.
     `CountFloor`/`CountUpper` bound its count.
     A FIRST visit to a province instead earns that province's flower (the client
     pushes the province into its own acquireList, and `visit_load.acquire` is
     what makes it stick across sessions). */
  const VISITOR_TABLE = ((gamedata.tables && gamedata.tables.visitors) || {}).provinceList || {};
  const VISITOR_PROVINCES = Object.keys(VISITOR_TABLE);

  const GIFT_CLOVER_ID = 100000;
  const GIFT_TICKET_ID = 100001;

  function visitorPayload() {
    const v = state.visitor;
    const out = { acquire: (state.acquireProvinces || []).slice() };
    if (v) {
      out.visitor = {
        partner: v.partner || 0,
        name: v.name || '',
        title: v.title || 0,
        expire_time: v.expire_time || 0,
        city: v.city || '',
        food: v.food || 0,
        first: !!v.first,
        gift: { item_id: v.gift ? v.gift.item_id : 0, count: v.gift ? v.gift.count : 0 },
        carpet: v.carpet || 0,
      };
    }
    return out;
  }

  function pickVisitor() {
    const prov = VISITOR_PROVINCES[randInt(0, VISITOR_PROVINCES.length - 1)];
    const row = VISITOR_TABLE[prov] || {};
    const first = (state.acquireProvinces || []).indexOf(prov) === -1;
    const lo = Number(row.CountFloor) || 1;
    const hi = Math.max(lo, Number(row.CountUpper) || lo);
    const giftId = Number(row.OtherGiftID) || GIFT_CLOVER_ID;
    // the client only reads `gift` when first === false, but the field is part of
    // VisitorData's fixed shape so it always has to be present
    const gift = first
      ? { item_id: giftId, count: randInt(lo, hi) }
      : { item_id: giftId, count: randInt(lo, hi) };
    return {
      province: prov,
      partner: 0,
      name: prov,
      title: Number(row.ID) || 0,
      expire_time: nowSec() + VISITOR_STAY_SEC,
      city: prov,
      food: randInt(0, Math.max(0, VISITOR_FOOD_MAX - 1)),
      first,
      gift,
      carpet: 0,
    };
  }

  /* Roll a thank-you gift.
     Weights come from Define (NORMAL normally, RARE when the visitor was
     delighted, i.e. feeling >= 80), and so do the bonuses.
     The CLOVER amount now follows the original's own formula, recovered from the
     Japanese binary's decompile:

         gain = (int)( cloverPow * ((100 + taste) / 100)
                       * (activeTime / 1800) * debuff / 15 )

     -- so a better-liked souvenir and a longer-staying visitor both pay more,
     which our previous flat "+20" completely ignored. `debuff` is the
     FRIEND_ITEM_DEBUFF decay for repeat feeding (0.6 / 0.75 / 0.9).
     HONEST GAP: `cloverPow` is a per-visitor field whose VALUES we could not read
     out of the binary, so the constant below is a placeholder chosen to give
     sensible magnitudes -- it is ours, not the original's. */
  const GUEST_CLOVER_POW = Number(process.env.FROG_GUEST_CLOVER_POW || 150);

  function rollGuestGift(feeling, ctx, activeSec) {
    const maps = defineData.maps || {};
    const rare = feeling >= 80;
    const w = (rare ? maps.FRIEND_GIFTPER_RARE : maps.FRIEND_GIFTPER_NORMAL)
      || { Clover: 80, FourClover: 18, Ticket: 2 };
    const roll = Math.random() * 100;
    let acc = Number(w.Clover) || 0;
    let got = 'clover';
    if (roll >= acc) {
      acc += Number(w.FourClover) || 0;
      got = roll < acc ? 'four_leaf' : 'ticket';
    }

    let clover = 0;
    let ticket = 0;
    if (got === 'four_leaf') {
      const count = addHouseItem(FOUR_LEAF_CLOVER_ID, 1);
      save();
      pushItemUpdate(ctx, FOUR_LEAF_CLOVER_ID, count);
    } else if (got === 'ticket') {
      ticket = 1;
    } else {
      // the original's formula
      const tier = Math.min((state.guestFeeds || 0), 2);
      const debuff = (defineData.maps.FRIEND_ITEM_DEBUFF || [0.6, 0.75, 0.9])[tier];
      const active = Math.max(0, Math.min(1800, Number(activeSec) || 0));
      clover = Math.floor(
        GUEST_CLOVER_POW * ((100 + feeling) / 100) * (active / 1800)
        * (Number(debuff) || 1) / 15);
    }
    // the bonus that Define DOES specify, on top of the category reward
    clover += Number(DEF('FRIEND_GIFTBOUNUS_CLOVER', 0));
    const maxBonusTickets = Number(DEF('FRIEND_GIFTBOUNUS_TICKET_MAX', 3));
    if ((state.guestBonusTickets || 0) < maxBonusTickets) {
      ticket += Number(DEF('FRIEND_GIFTBOUNUS_TICKET', 0));
      state.guestBonusTickets = (state.guestBonusTickets || 0) + 1;
    }

    if (clover) {
      state.clover += clover;
      ctx.push('clover_update', { clover: state.clover });
    }
    if (ticket) {
      state.ticket += ticket;
      ctx.push('item_update_ticket', { ticket: state.ticket });
    }
    save();
    return { got, clover, ticket, feeling, rare };
  }

  /* ------------------------------------------------------- raffle */

  /* Roll a ball rank using the original server's weights (Define.PrizeBalls).
     Returns 0..5 only -- Prize.Rank.FURNITURE is 6 and has no Prize row. */
  function rollPrizeRank() {
    const w = (defineData.maps && defineData.maps.PrizeBalls)
      || { White: 40, Blue: 25, Purple: 22, Green: 9, Red: 3, Gold: 1 };
    const order = ['White', 'Blue', 'Purple', 'Green', 'Red', 'Gold'];
    const total = order.reduce((n, k) => n + (Number(w[k]) || 0), 0);
    if (!total) return 0;
    let roll = Math.random() * total;
    for (let i = 0; i < order.length; i++) {
      roll -= Number(w[order[i]]) || 0;
      if (roll < 0) return i;
    }
    return 0;
  }

  /* ---------------------------------------------------------- mail */

  /* Every mail MUST carry `resource` -- with ads_id and share_id, on which the
     client reads .length -- and `pictures`, also read as an array.
     revice_mails() and checkMailItemType() dereference both unconditionally, so a
     mail missing either throws. */
  function makeMail(o) {
    state.mailSeq = (state.mailSeq || 0) + 1;
    return {
      id: state.mailSeq,
      type: o.type || 3,                 // 3 = Mail.EvtId.Gift
      title: o.title || '',
      message: o.message || '',
      senderCharaId: o.senderCharaId != null ? o.senderCharaId : -1,
      auto_open: false,
      expire: 0,
      read: false,
      opened: false,
      resource: {
        clover_point: o.clover || 0,
        ticket: o.ticket || 0,
        reward_gacha: o.gacha || 0,
        ads_id: '',
        share_id: '',
      },
      items: o.items || [],
      pictures: o.pictures || [],
    };
  }

  /* Deliver the two tutorial gifts once, straight from the game's own template
     (MailEvent.json in config.eab: 500 clover, then 1x the four-leaf-clover item;
     mailEvt 3 = Gift). This is real table data, not an invention. */
  function ensureTutorialMails() {
    if (state.mailTutorialSent) return;
    state.mailTutorialSent = true;
    const tpl = (gamedata.tables && gamedata.tables.MailEvent) || [];
    for (const t of tpl) {
      const itemId = Number(t.itemId);
      const stock = Number(t.itemStock) || 0;
      state.mails.push(makeMail({
        type: Number(t.mailEvt) || 3,
        title: t.title || '',
        message: t.message || '',
        senderCharaId: t.senderCharaId != null ? Number(t.senderCharaId) : -1,
        clover: Number(t.CloverPoint) || 0,
        ticket: Number(t.ticket) || 0,
        items: (itemId >= 0 && stock > 0) ? [{ item_id: itemId, count: stock }] : [],
      }));
    }
    trimMails();          // define.json MAIL_MAX
    save();
  }

  /* Opening is needResponse:false, and the client's own resource/item helpers are
     empty stubs, so the entire grant has to happen here -- then the mail is
     dropped, which the client also does locally. */
  function openMail(ctx, id) {
    const i = state.mails.findIndex((m) => m && m.id === id);
    if (i < 0) return false;
    const mail = state.mails[i];
    const res = mail.resource || {};
    if (Number(res.clover_point) > 0) {
      state.clover += Number(res.clover_point);
      ctx.push('clover_update', { clover: state.clover });
    }
    if (Number(res.ticket) > 0) {
      state.ticket += Number(res.ticket);
      ctx.push('item_update_ticket', { ticket: state.ticket });
    }
    if (Number(res.reward_gacha) > 0) {
      // a free raffle ball: reward_raffle() asks the server for one whenever
      // colorBall is -1, so arming the ball is what makes it claimable
      state.gacha.colorBall = rollPrizeRank();
    }
    for (const it of (mail.items || [])) {
      const itemId = Number(it.item_id);
      const count = addHouseItem(itemId, Number(it.count) || 1);
      pushItemUpdate(ctx, itemId, count);
    }
    state.mails.splice(i, 1);
    save();
    ctx.push('mail_load', state.mails);
    return true;
  }

  /* ------------------------------------------------ 年度总结 (annual review) */

  /* The review pages (AnnualReviewStartPage / ChatPage / FinishPage) build their
     whole script from 17 payload fields, and they do it with plain `t.foo`
     comparisons -- so a missing field does not throw, it prints "undefined" all
     over the review. `annual_load` used to answer `{is_share:true}` and nothing
     else, which is exactly what the player saw.
     Sources, all of them the local save:
       travel_num   state.travel.tripCount        login_day   createDay()
       create_time  state.createTime              page_num    album pages
       pic_num      photos in the album           stamp_num   (no stamp state -> 0)
       wish_num     wishes granted                fur_num     furniture owned
       note_num     notes                         spe_num     specialities
       col_num      collections                   first_col   first collection id
       story_num    stories                       first_story first story id
       visit_num    guests that ever arrived      first_guest first guest id
       clover       clover EARNED (state.cloverEarned, not the current balance)
       theme        which persona art (1..12) the FinishPage shows
     Fields the engine genuinely has no data for report 0 on purpose: the client
     has a "you have none of those" line for each of them, so 0 reads as an honest
     "none yet" rather than as a broken page.

     `theme` is OUR CHOICE: the live service picked a persona. It is derived from
     the save so it is stable across restarts instead of changing every open. */
  function annualPayload() {
    const photos = (state.pictures || []).length;
    const pages = ((state.animPicture && state.animPicture.picList) || []).length;
    const cols = (state.handbook && state.handbook.collections) || [];
    const spes = (state.specialtys || []);
    const stories = ((state.storyBook && state.storyBook.list) || []);
    const theme = ((createDay() + (state.travel.tripCount || 0)) % 12) + 1;
    /* 手工品 = the frog's own crafts, counted the same way pray_load_grays counts
       them (a row is finished at state > 3, see advanceCraft). The client's line is
       「一个人在家的时候，小青蛙也有在认真做手工，一共雕刻了{0}个印章，完成了{0}个祈愿物。」
       -- and this payload used to answer `stamp_num: 0` with a comment claiming no
       stamp book existed, plus a `wish_num` read off the WISHING POOL (a different
       feature: coins and wishes spent at the pool), so the annual review always said
       「可惜没有雕刻过印章，祈愿物都没有」 no matter how much the frog had made. */
    const craft = state.craft || {};
    const finished = (list, kind) => (list || []).filter((r) => craftDone(kind, r)).length;
    return {
      is_share: true,                 // sharing is impossible offline; keep the dot off
      create_time: Number(state.createTime) || nowSec(),
      login_day: createDay(),
      travel_num: Number(state.travel.tripCount) || 0,
      pic_num: photos,
      page_num: pages,
      stamp_num: finished(craft.stamps, 'stamp'),
      wish_num: finished(craft.wishes, 'wish'),
      fur_num: (state.furniture.owned || []).length,
      note_num: (state.notes || []).length,
      spe_num: spes.length,
      col_num: cols.length,
      first_col: cols.length ? Number(cols[0].id || cols[0]) : 0,
      story_num: stories.length,
      first_story: stories.length ? Number(stories[0].id || stories[0]) : 0,
      visit_num: Number(state.guestVisits) || 0,
      first_guest: Number(state.firstGuest) || 0,
      clover: Number(state.cloverEarned) || 0,
      theme,
    };
  }

  /* ------------------------------------------------- 分享 / 广告 (adsmgr) */

  /* What the client does with each of these, read off AdsModel and the views:
   *
   *   req_share(1)   AdsPopView / AdsVideoView        -> the DAILY gift
   *   req_share(2)   AdsGiftView  (AdsGiftSkin)       -> one gift, client counts it
   *   req_share(3)   RaffleView   (extra raffle roll) -> LotteryModel.onGetExtraItem()
   *   req_share(4)   FurnitureAdsView / furniture     -> the good is the REWARD,
   *                  welfare goods; n(true) already    already granted by
   *                  ran requestBuy                     furniture_buy_shop
   *   req_share(5)   ShopView free order              -> the good is granted by
   *                                                     adsmgr_shop_free
   * and, on code 0, the client toasts "叮咚~邮箱有动静" for 1/2/3 -- i.e. the
   * reward arrives AS MAIL. So that is where it is delivered here.
   *
   * The LIVE amounts are not recoverable (the service decided them). What is
   * grounded is the mechanism (mail) and the daily cadence; the amounts below are
   * OUR DESIGN and are labelled as such.
   */
  const ADS_DAILY_CLOVER = 30;         // our choice, same figure the calendar uses
  const ADS_GIFT_PER_DAY = 1;

  /** Local date key (YYYY*10000 + MM*100 + DD). Local, not UTC: the client's own
   *  calendar and day counters read the device clock (see CalendarView), so the
   *  server must agree with what the player's calendar shows. */
  function dayKey() {
    const d = new Date(nowSec() * 1000);
    return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
  }
  /** Unix seconds of the next local midnight -- AdsModel.getGiftLeftTime(). */
  function nextLocalMidnight() {
    const d = new Date(nowSec() * 1000);
    d.setHours(24, 0, 0, 0);
    return Math.floor(d.getTime() / 1000);
  }
  function ensureAdsState() {
    if (!state.ads) {
      state.ads = { day: 0, popDay: 0, popRefusedDay: 0, giftGet: 0 };
    }
    if (state.ads.day !== dayKey()) {
      state.ads.day = dayKey();
      state.ads.giftGet = 0;
    }
    return state.ads;
  }

  /** The daily ad/share gift. Lands in the mailbox, exactly as the client's own
   *  "邮箱有动静" toast promises, and the clover is credited by openMail. */
  function deliverAdsGift(ctx, title) {
    const m = makeMail({
      type: 3,                                   // Mail.EvtId.Gift
      title: title || '分享奖励',
      message: '谢谢你的帮忙，这是小小的心意。',
      clover: ADS_DAILY_CLOVER,
      senderCharaId: -1,
    });
    state.mails.push(m);
    trimMails();
    save();
    ctx.push('notify_new_mail', { mail: m });
    ctx.push('mail_load', state.mails);
    return m;
  }

  /* ---- 分享明信片的奖励 ----------------------------------------------------
     The postcard's share sheet shows 「分享可得 N 三叶草」 and gets N from
     `ShareModel.rewardData[pic.id]`, which is filled ONLY by the pushed
     `share_load`:

       share_load(e)   { for (pic of e.pic_list) this.rewardData[pic.id] = pic.clover }
       updateShare()   { this.shareClover = GetShareReward(pic.id);
                         this.groupShare.visible = this.btn_share.visible && null != this.shareClover }
       req_get_reward(id, 1) { if (rewardData[id] == null) RETURN;   // <- silently does NOTHING
                               send("share_get_reward", {id, is_get:1}) }

     We answered `share_load` with `pic_list: []` -- and the client never even SENDS
     share_load (it registers it with addProtocolCallback, i.e. push-only), so the
     handler was dead code, rewardData stayed empty, and the reward simply vanished
     with no error: 「点了没反应，奖励收不到」. Hence: push it (see tick) and answer
     the claim.

     【自设计】 the per-photo amount: the live service decided it and it is not in our
     snapshot. One claim per photo, ever. */
  const SHARE_PHOTO_CLOVER = 20;
  const SHARE_PHOTO_PUSH_MAX = 60;

  function shareClaimedMap() {
    if (!state.shareClaimed || typeof state.shareClaimed !== 'object') state.shareClaimed = {};
    return state.shareClaimed;
  }

  /** Photos whose share reward is still unclaimed, newest first. */
  function sharePicList() {
    const claimed = shareClaimedMap();
    const out = [];
    const list = state.pictures || [];
    for (let i = list.length - 1; i >= 0 && out.length < SHARE_PHOTO_PUSH_MAX; i--) {
      const p = list[i];
      if (p && typeof p.id === 'number' && !claimed[p.id]) {
        out.push({ id: p.id, clover: SHARE_PHOTO_CLOVER });
      }
    }
    return out;
  }

  /** Push `share_load` when the album grew (the client cannot ask for it itself). */
  function maybePushShareLoad(ctx) {
    const count = (state.pictures || []).length;
    if (state.sharePushedFor === count) return;
    state.sharePushedFor = count;
    ctx.push('share_load', { pic_list: sharePicList() });
  }

  function adsPayload(ctx) {
    const a = ensureAdsState();
    const today = dayKey();
    /* item_id must exist in ItemDB -- AdsGiftView does ItemDB.get(item_id) and
       formatPathImage() on the result; 200000 is the Item table's 三叶草
       (type 14 RESOURCE), the same row the calendar uses. */
    return {
      can_pop: a.popDay !== today && a.popRefusedDay !== today,
      can_banner: false,                  // no banner ads exist offline
      day_left: a.popDay !== today ? 1 : 0,
      gift_id: 1,
      gift_time: nextLocalMidnight(),
      gift_can_get: ADS_GIFT_PER_DAY,
      gift_get: Math.min(a.giftGet, ADS_GIFT_PER_DAY),
      item_list: [{ item_id: ITEM_CLOVER_RES, num: ADS_DAILY_CLOVER, is_sp: false }],
    };
  }

  /* ------------------------------------------------------- 充值 (recharge) */

  /* RechargeView has three pages: 商城/田地/礼包.
   *   * 商城 (RechargeMerchPage) renders RechargeModel.merchData, whose rows carry
   *     a remote `image` URL and an `open_url` (RES.getResByUrl). That is an
   *     ONLINE storefront: with no network there is nothing to show, and the view
   *     itself hides the tab when merchData is empty, so we leave it empty rather
   *     than render broken tiles.
   *   * 田地 (RechargeFieldPage) renders `data.field` rows of
   *     {id, grow, total}; RechargeFieldItem looks the row's `id` up in
   *     rechargeDB (6 real packs, 400/1000/1800/2800/150/300 clover) to label the
   *     price art, and shows ceil(grow) as the boost multiplier.
   *   * 礼包 (RechargeGiftPage) renders `data.sack` rows {id, goods, price}.
   *
   * There is NO payment channel offline, so nothing can actually be bought. The
   * offline build therefore grants the pack directly (see recharge_ready_pay) and
   * says so, instead of showing a button that silently does nothing. */
  function ensureRechargeState() {
    if (!state.recharge) {
      state.recharge = { water: 0, change: 0, field: [], sack: [], paidCount: {} };
    }
    return state.recharge;
  }

  /** The pack rows the 田地 page renders. `grow` starts at 0 and `total` is the
   *  target multiplier; with no live promo to grow them, they are marked ready so
   *  the page is usable instead of showing six dead "growing" plots. */
  function rechargeField() {
    const r = ensureRechargeState();
    const packs = (gamedata.tables && gamedata.tables.recharge) || [];
    const known = new Set(packs.map((p) => Number(p.id)));
    r.field = (r.field || []).filter((row) => row && known.has(Number(row.id)));
    for (const p of packs) {
      const id = Number(p.id);
      if (!r.field.some((row) => Number(row.id) === id)) {
        r.field.push({ id, grow: 1, total: 1 });
      }
    }
    return r.field;
  }

  function rechargePayload(ctx) {
    const r = ensureRechargeState();
    rechargeField();                       // keep `field` in sync with the real packs
    return {
      water: Number(r.water) || 0,
      change: Number(r.change) || 0,
      field: r.field,
      sack: r.sack || [],
    };
  }

  /* What a purchase delivers. The live server pushed a TravelEvent of type
     TimerEvent.Type.Recharge (12) whose evt_id is the pack id and whose evt_value
     is [clover, itemId, count, ...]; the client then credits clover and items
     itself via its TimerEvent handler. Because the client's own addClover /
     addHouseItem are EMPTY STUBS, the engine has to credit as well. */
  function deliverRechargePack(ctx, packId) {
    const pack = ((gamedata.tables && gamedata.tables.recharge) || [])
      .find((p) => Number(p.id) === Number(packId));
    if (!pack) return false;
    const r = ensureRechargeState();
    const clover = Number(pack.count) || 0;
    state.clover += clover;
    r.paidCount[packId] = (r.paidCount[packId] || 0) + 1;
    // the pack is consumed from the field, the client does the same on this event
    r.field = (r.field || []).filter((row) => Number(row.id) !== Number(packId));
    /* Deliver the event the live server sent after a verified payment. It goes
       out BOTH as a push and into the queue client_load_events drains, because
       the client only runs its TimerEvent.Type.Recharge branch while disposing
       its event list (NetworkControl.eventsDispose) -- a push alone may not be
       consumed. The client's own addClover/addHouseItem are empty stubs, so
       crediting here cannot double-count. */
    const ev = makeEvent(12, [clover]);
    if (!Array.isArray(state.pendingEvents)) state.pendingEvents = [];
    state.pendingEvents.push(ev);
    save();
    ctx.push('clover_update', { clover: state.clover });
    ctx.push('recharge_load', rechargePayload(ctx));
    ctx.push('notify_new_event', { event: ev });
    if (verbose) {
      console.log(`[engine] recharge pack ${packId} (${pack.money}元 list) `
        + `-> +${clover} clover, delivered free (offline build, no payment channel)`);
    }
    return true;
  }

  /* -------------------------------------------------------- calendar */

  /* The lucky / special-day SCHEDULE is not recoverable -- it was decided by the
     live server -- so the schedule below is OUR DESIGN and is marked as such.
     What IS grounded:
       * the day rows carry an item_id used only for the icon, and the Item table
         names 200000 = 三叶草 and 200001 = 兑奖券 (both type 14 RESOURCE, which the
         client folds into the currency counters rather than the inventory);
       * the client's own task copy says "累计30三叶草", which is where 30 comes from.
     The ticket amount is our choice. */
  const CALENDAR_ST_CLOVER = 30;
  const CALENDAR_LUCKY_TICKETS = 1;
  const ITEM_CLOVER_RES = 200000;
  const ITEM_TICKET_RES = 200001;

  function createDay() {
    const created = Number(state.createTime) || nowSec();
    return Math.max(1, Math.floor((nowSec() - created) / 86400) + 1);
  }
  function curMonth() { return new Date(nowSec() * 1000).getMonth() + 1; }
  function curDayOfMonth() { return new Date(nowSec() * 1000).getDate(); }
  /** Days in the CURRENT month, local time -- the same frame the client's own
   *  CalendarModel.getMonthMaxDay() uses. Day 0 of the next month is the last day
   *  of this one. */
  function curMonthMaxDay() {
    const d = new Date(nowSec() * 1000);
    return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  }

  function ensureCalendarMonth() {
    const m = curMonth();
    const maxDay = curMonthMaxDay();
    /* Regenerate when the month changes OR when the stored schedule does not cover
       the whole month. The old version stopped at 28 (and cached on the month
       number alone), so on any 29/30/31-day month the last three days had no
       reward entry and therefore NO ICON AT ALL -- the calendar looked like it
       ended on the 28th, and the client's own claim check (which is keyed by
       day-of-month) could never fire for those days either. */
    const covered = state.calendar.st.length + state.calendar.lucky.length;
    if (state.calendar.month === m && covered === maxDay) return;
    state.calendar.month = m;
    state.calendar.claimedLucky = [];
    state.calendar.claimedSt = [];
    const st = [];
    const lucky = [];
    for (let d = 1; d <= maxDay; d++) {
      // every day of the month carries a reward, as the original's own month art
      // did (every cell had an icon); the every-7th-day ticket is our design
      if (d % 7 === 0) lucky.push({ day: d, item_id: ITEM_TICKET_RES });
      else st.push({ day: d, item_id: ITEM_CLOVER_RES });
    }
    state.calendar.st = st;
    state.calendar.lucky = lucky;
    save();
  }

  /* ------------------------------------------------------ achievements */

  /* Turn one Achieve.json `info` string into a predicate. Returning null means the
     rule is NOT implemented on purpose -- museum "典藏" counts (82-85), the
     city-photo map (81), flowerpot bloom stages (73/74/79/80), the anniversary
     badge (87) and the item-unlocked specials (900-902). Those simply never
     unlock, which is honest; faking them would not be. */
  function buildRule(info) {
    let m;
    if (info === '（默认）') return () => true;
    if ((m = /^旅行达到(\d+)次$/.exec(info))) {
      const n = Number(m[1]);
      return (s) => (s.travel.tripCount || 0) >= n;
    }
    if ((m = /^登录达到(\d+)天$/.exec(info))) {
      const n = Number(m[1]);
      return () => createDay() >= n;
    }
    if ((m = /^拥有超过(\d+)万棵三叶草$/.exec(info))) {
      const n = Number(m[1]) * 10000;
      return (s) => s.clover > n;
    }
    if ((m = /^抽奖(\d+)次以上$/.exec(info))) {
      const n = Number(m[1]);
      return (s) => (s.gachaCount || 0) >= n;
    }
    if ((m = /^获得(\d+)种纪念品$/.exec(info))) {
      const n = Number(m[1]);
      return (s) => ((s.handbook && s.handbook.collections) || []).length >= n;
    }
    if ((m = /^获得(\d+)种特产$/.exec(info))) {
      const n = Number(m[1]);
      return (s) => ((s.handbook && s.handbook.specialtys) || []).length >= n;
    }
    if (info === '获得所有特产食材') {
      return (s) => FARM_SPECIALTY_IDS.length > 0
        && FARM_SPECIALTY_IDS.every((id) => ((s.handbook && s.handbook.specialtys) || []).indexOf(id) !== -1);
    }
    if ((m = /^(.+?)超过(\d+)个$/.exec(info))) {
      // resolved against the real Item table; no ids hard-coded. Rows whose label
      // matches no item (蜜柑, 桃子 -- cut from this build) stay unimplemented.
      const itemId = resolveItemByName(m[1]);
      const n = Number(m[2]);
      if (itemId === undefined) return null;
      return () => getHaveItem(itemId) >= n;
    }
    if (info === '出发不到30分钟就回家') {
      return (s) => Number(s.travel.minTripSec) > 0 && Number(s.travel.minTripSec) < 1800;
    }
    if (info === '出发超过24小时还没回家') {
      return (s) => Number(s.travel.maxTripSec) >= 86400;
    }
    if (info === '六一期间登录') {
      return () => {
        const d = new Date(nowSec() * 1000);
        return (d.getMonth() + 1) === 6 && d.getDate() === 1;
      };
    }
    return null;
  }

  const ACHIEVE_RULES = ((gamedata.tables && gamedata.tables.Achieve) || []).map((a) => ({
    id: Number(a.id),
    name: a.name,
    info: a.info,
    special: Number(a.is_special) || 0,
    test: Number(a.is_special) ? null : buildRule(String(a.info || '')),
  }));

  /* Grow frog.achieves. The client raises its toast purely because the array got
     longer, so appending + pushing client_load_role is the whole mechanism.
     NOTE ON `achieves_time`: it is an EXPIRY time, not an earned time. The client
     reads it as `isAchieveExpire(id) -> achieveTime[id] ? now >= achieveTime[id] : false`,
     so recording WHEN a title was earned makes `now >= earned` true immediately and
     every title is instantly "expired" -- which is why the 称号 list showed nothing
     but the client's own "??????" placeholder, and why the title popup showed a
     stale one (getUseAchieveID() returns -1 for an expired id). Offline there is no
     reason for a title to lapse, and the client treats a MISSING entry as
     never-expiring, so we deliberately record no expiry at all. */
  function checkAchievements(ctx) {
    let gained = 0;
    for (const r of ACHIEVE_RULES) {
      if (!r.test || state.achieves.indexOf(r.id) !== -1) continue;
      let ok = false;
      try { ok = !!r.test(state); } catch (e) { ok = false; }
      if (!ok) continue;
      state.achieves.push(r.id);
      state.curAchieve = r.id;
      gained++;
      if (verbose) console.log(`[engine] achievement unlocked: ${r.id} ${r.name}`);
    }
    if (gained) {
      save();
      ctx.push('client_load_role', rolePayload());
    }
    return gained;
  }

  /* ------------------------------------------------------------ tasks */

  /* taskData holds four tables: task_list (30 tasks: count = goal, num = reward
     quantity, reward_id = an Item id -- 200000 is 三叶草), list_map (67 checklist
     rows), list_type (6 plans, each with parallel target[]/reward[] arrays) and
     task_type (the 6 groups).
     HONEST LIMIT: which game action advances which task lived on the live server
     and is not recoverable (the spec flags this as its lowest-confidence item).
     We therefore advance only the mappings we can justify, and leave the rest at
     0 rather than inventing progress. */
  const TASK_TABLE = (gamedata.tables && gamedata.tables.taskData) || {};
  const TASKS = TASK_TABLE.task_list || {};
  const LIST_TYPE = TASK_TABLE.list_type || {};
  /* `task_load` carries TWO different id spaces, and mixing them up CRASHES the
     client:
       tasks -> task_list ids (30 rows: 1, 2, 101, ...)
       list  -> list_map  ids (67 rows: 101, 102, 201, ...)
     The client's updateRedot -> getCompleteListNum does
       var t = TaskDB.get("list_map"); for (n in dataList) { var r = t[n]; r.type ... }
     so every id in `list` MUST be a list_map key. We used to send the task_list
     ids there, so `t[n]` was undefined for ids 1/2/... and `r.type` threw
     `TypeError: Cannot read properties of undefined (reading 'type')` inside
     task_load -> updateRedot. The client turns any such error into the
     "呱呱，吃坏肚子了，快重启一下游戏！" modal and reloads, so the error repeated
     forever and the game could not be entered. */
  const LIST_MAP = TASK_TABLE.list_map || {};
  const LIST_IDS = Object.keys(LIST_MAP)
    .map(Number).filter((n) => Number.isFinite(n)).sort((a, b) => a - b);

  /* Progress for a task, from counters we actually keep.
     type 1 = 旅行  -> trips taken
     type 2 = 旅行笔记 -> notes collected (pictures stand in for notes here) */
  function taskProgress(t) {
    const type = Number(t && t.type);
    if (type === 1) return Number(state.travel.tripCount) || 0;
    if (type === 2) return (state.pictures || []).length;
    return 0;                        // unmapped on purpose -- see the note above
  }

  function taskRows() {
    const rows = [];
    for (const k of Object.keys(TASKS)) {
      const t = TASKS[k];
      const id = Number(t.id);
      rows.push({
        id,
        is_reward: (state.tasksClaimed || []).indexOf(id) !== -1 ? 1 : 0,
        _pro: taskProgress(t),
        _count: Number(t.count) || 0,
      });
    }
    rows.sort((a, b) => a.id - b.id);
    return rows;
  }

  /** One `list_map` row's progress toward its own `count`. */
  function listProgress(row) {
    const type = Number(row && row.type);
    if (type === 1) return Number(state.travel.tripCount) || 0;
    if (type === 2) return (state.pictures || []).length;
    return 0;                        // unmapped on purpose -- see the note above
  }

  /** The `list` half of task_load: list_map ids with their progress. */
  function listRows() {
    return LIST_IDS.map((id) => ({
      id,
      pro: listProgress(LIST_MAP[String(id)]),
    }));
  }

  /* ---- 累计计划奖励 (list_type) ------------------------------------------------
     The task panel is the 「伴蛙前行」 button (skin icon_task_92_96, red dot
     GUIDE_TASK). It has TWO reward systems:
       * task_list rows  -> task_get_reward      (was already implemented)
       * list_type tiers -> task_get_list_reward (was NOT implemented AT ALL -- the
         handler simply did not exist, and a comment claimed that was deliberate)

     The client's `TaskModel.req_list_reward(type, i)` sends `id = 100*type + (i+1)`
     and its callback only acts on `0 == code`. With no handler the engine answered
     `{}` and the button did NOTHING -- the reported 「「伴蛙前行」的奖励点不下去，
     没法收到」.

     A plan's progress is the client's OWN definition (getCompleteListNum): how many
     list_map rows OF THAT TYPE have reached their own `count`. Claimed tiers are
     remembered per type, so each tier pays exactly once. */
  function listTypeProgress(type) {
    let n = 0;
    for (const id of LIST_IDS) {
      const row = LIST_MAP[String(id)];
      if (!row || Number(row.type) !== Number(type)) continue;
      if (listProgress(row) >= (Number(row.count) || 0)) n += 1;
    }
    return n;
  }

  function claimedTiers(type) {
    const m = state.taskTiers || (state.taskTiers = {});
    return Number(m[String(type)]) || 0;
  }

  /** GuideTaskModel.dataReward is keyed by plan TYPE, not the encoded claim id. */
  function listClaimRows() {
    const out = [];
    for (const k of Object.keys(LIST_TYPE)) {
      const type = Number(k);
      const done = claimedTiers(type);
      out.push({ id: type, pro: done });
    }
    out.sort((a, b) => a.id - b.id);
    return out;
  }

  /* id encodes the plan: 100 * type + (tier + 1) */
  function listRewardRow(id) {
    const type = Math.floor(Number(id) / 100);
    const tier = (Number(id) % 100) - 1;
    const plan = LIST_TYPE[String(type)];
    if (!plan || tier < 0) return null;
    const target = (plan.target || [])[tier];
    const reward = (plan.reward || [])[tier];
    if (target === undefined || reward === undefined) return null;
    return { type, tier, target: Number(target), rewardId: Number(reward) };
  }

  /* Grant `n` of an item. Item ids 200000/200001 are the RESOURCE currencies the
     client folds into its counters, so route those through the currency fields. */
  function grantItem(ctx, itemId, n) {
    if (itemId === ITEM_CLOVER_RES) {
      state.clover += n;
      ctx.push('clover_update', { clover: state.clover });
      return true;
    }
    if (itemId === ITEM_TICKET_RES) {
      state.ticket += n;
      ctx.push('item_update_ticket', { ticket: state.ticket });
      return true;
    }
    const count = addHouseItem(itemId, n);
    return pushItemUpdate(ctx, itemId, count);
  }

  /* ---- flowerpot ---------------------------------------------------- */

  /* flowerpotData has ONE pot (23001 陶瓷花盆) whose pos_list has two entries, so
     the pot has two planting slots. Each plant has three growth pictures, which is
     what the client's `stage` 1..3 maps onto -- and the spec confirms `stage >= 3`
     is the only harvestable state.

     Harvest identity comes from the plant: flowers match Item type 14/sub_type 6
     by their full variety name, vegetables/fruits match type 3 by species name.
     Picking from all farm specialities can turn a tulip into milk or rice. */
  const FP_TABLE = (gamedata.tables && gamedata.tables.flowerpotData) || {};
  const FP_POTS = FP_TABLE.flowerpot || {};
  const FLOWERPOT_ID = Number(Object.keys(FP_POTS)[0] || 23001);
  const FLOWERPOT_SLOTS = (((FP_POTS[String(FLOWERPOT_ID)] || {}).pos_list) || []).length || 2;
  const FLOWER_PLANTS = Object.keys(FP_TABLE.plant || {});
  const PLANT_HARVEST = new Map(FLOWER_PLANTS.map((id) => {
    const name = FP_TABLE.plant[id].name;
    const flower = gamedata.items.find((item) => item.type === 14
      && Number(item.sub_type) === 6 && item.name === name);
    const crop = gamedata.items.find((item) => item.type === 3
      && item.name === name.split('·')[0]);
    return [Number(id), flower || crop];
  }));
  /* Growth timing is not in any table we can read, so this is our choice:
     three stages over FROG_PLANT_SEC (default 10 minutes total). */
  const PLANT_STAGE_SEC = Number(process.env.FROG_PLANT_STAGE_SEC || 200);

  function plantList() {
    return (state.flowerpot.slots || []).map((s, i) => ({
      type: 1,
      index: i + 1,
      id: s.id,
      stage: s.stage,
    }));
  }

  /* The client has NO "plant" command -- the whole cycle is server-driven -- so a
     free slot is re-seeded here. Growth is by elapsed time. */
  function refreshFlowerpot(t) {
    if (!state.flowerpot.slots || state.flowerpot.slots.length !== FLOWERPOT_SLOTS) {
      state.flowerpot.slots = [];
      for (let i = 0; i < FLOWERPOT_SLOTS; i++) {
        state.flowerpot.slots.push({ id: 0, stage: 0, plantedAt: 0 });
      }
    }
    let changed = false;
    for (const s of state.flowerpot.slots) {
      if (!s.id) {
        if (FLOWER_PLANTS.length) {
          s.id = Number(FLOWER_PLANTS[randInt(0, FLOWER_PLANTS.length - 1)]);
          s.stage = 1;
          s.plantedAt = t;
          changed = true;
        }
        continue;
      }
      const want = Math.min(3, 1 + Math.floor((t - (s.plantedAt || t)) / PLANT_STAGE_SEC));
      if (want !== s.stage) { s.stage = want; changed = true; }
    }
    if (changed) save();
    return changed;
  }

  /* ----------------------------------------------------- encyclopedia */

  /* encyclopedia.json = `desc` (species x numbered text lines: taxonomy, habit,
     origin, 花语) + `list` (238 picture rows keyed by
     long_id = id*10000 + sub_id*100 + pic_id, where pic_id indexes
     主图/成长1-3/插花...).

     A plant id and a long_id LOOK like the same number (2010101 vs 1010101), but
     they are different id spaces: long_id's last digits are the PICTURE index, not
     the variant, so subtracting a constant is wrong. The reliable link is the NAME
     -- plant "角堇·火龙果" is encyclopedia name "角堇" + sub_name "火龙果". That
     resolves 32 of the 35 plants; 葡风 (grape hyacinth) has no entry at all. */
  const ENC = (gamedata.tables && gamedata.tables.encyclopedia) || {};
  const ENC_ROWS = Object.keys(ENC.list || {}).map((k) => ENC.list[k]);
  const ENC_BY_NAME = new Map(ENC_ROWS.map((e) => [`${e.name}\u00b7${e.sub_name}`, e]));

  function encyclopediaRowForPlant(plantId) {
    const table = ((gamedata.tables || {}).flowerpotData || {}).plant || {};
    const p = table[String(plantId)];
    return p ? ENC_BY_NAME.get(p.name) : undefined;
  }

  /* The flowers the frog brings home are `decoration` rows, and their `icon` is the very
     same string as the encyclopedia row for that species + variant (decoration 10011
     角堇·火龙果 carries icon_chahua_zhongzhi_jiaojin_1, which is exactly what
     encyclopedia 1010101 uses). The rows even ship a `desc_handbook`. So a flower from a
     trip unlocks its 百科 entry just like one grown in the pot -- without this, a player
     who only travelled saw every entry as 未收集. */
  function encyclopediaRowForDecoration(decId) {
    const d = DECORATIONS[String(decId)];
    if (!d || !d.icon) return undefined;
    const rows = ENC.list || {};
    for (const k of Object.keys(rows)) {
      const row = rows[k];
      if (!row) continue;
      if (row.icon === d.icon || row.pic_img === d.icon) return row;
    }
    return undefined;
  }

  /* ---------------------------------------------------------- 百科 (encyclopedia)
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

    /* One entry per UNLOCKED species, showing: the variety the player last looked at
       (the client sends its long_id on encyclopedia_set_show_sub, so the server could
       only ever remember one), else the variety the player actually HAS, else the
       species' first row in the table.
       Only unlocked species are listed: EncyView pads the grid up to 12 empty slots and
       greys out a tab that has nothing in it, i.e. a short list is the normal case. */
    const picked = Number(state.encyclopediaShow);
    const unlockedIds = {};
    for (const e of unlocked) unlockedIds[e.longId] = true;
    const show_sub = [];
    for (const id of ids) {
      if (!has[String(id)]) continue;
      const mine = ENC_ENTRIES.filter((e) => Number(e.row.id) === id);
      const owned = mine.filter((e) => unlockedIds[e.longId]);
      const chosen = mine.find((e) => e.longId === picked) || owned[0] || mine[0];
      if (chosen) show_sub.push({ id, sub_id: chosen.longId });
    }
    return { unlock_list, unlock_desc, show_sub };
  }

  /* ------------------------------------------------------- handlers */
  /* Each returns the response object for that command (or undefined to skip). */

  // Client settings. guideStep MUST be one of the GuideStep string values or the
  // client silently rewrites it to "GetAward" and drags the player into the
  // server-driven tutorial, which never completes offline.
  //
  // 'New' is the CLIENT'S OWN default (SettingsInfo's constructor sets
  // guideStep = GuideStep.New), and that is where a brand-new account belongs:
  // 欢迎页 -> 起名 -> 采三叶草 -> 进屋/开店/买工具/背包 -> 领奖 -> Complete.
  // Every one of those steps is client-side except the GetAward pair
  // (tutorial_step_*), which the engine implements below. This only affects a
  // FRESH save: an existing save has its own persisted guideStep ('Complete',
  // echoed back from the client) and is untouched.
  //
  // Why it matters beyond the tutorial itself: the MainOut view hides the four
  // event buttons (博物馆冒险 / 生日蛋糕 / 春节贺卡 / 祝福贺卡) and the activity
  // red dot while guideStep != 'Complete' (see updateMuseumDay / updatePartyCake /
  // updateSpringCard / updateGreetCard), so a save that never finishes the guide
  // never sees those features at all.
  function clientSettings() {
    return {
      guideStep: 'New',
      bgSound: 1,
      effectSound: 1,
      hasAchieve: false,
      hasOpenAttributeView: true,
      hasEnteredRaffle: true,
      hasOpenedDesk: true,
      hasBuyTool: true,
      hasFriendVisit: true,
      achieveList: [],
      guideVisitor: true,
      guideVisitorGift: true,
      guideStory: true,
      guideStoryGift: true,
      hasOpenedNote: true,
      guideNote: true,
      guideHandCraft: true,
      guideSlidePicture: true,
      guideFurniture: 99,
      guideAnnualReview: true,
      guideFurnitureNotice: true,
      guideDrawing: 99,
      noticeDrawing: 0,
      guideCamera: true,
    };
  }

  // Role payload. The client never *sends* client.load_role - the server pushes it.
  function rolePayload() {
    return {
      uid: state.uid,
      res: { clover_point: state.clover, ticket: state.ticket },
      settings: {
        client: JSON.stringify(Object.assign(clientSettings(), state.settings || {})),
        push_switch: 0,
        rank_switch: 0,
      },
      misc: {
        picture_cnt: state.pictures.length,
        wx_push_reward: false,
        wx_my_reward: true,
        create_time: state.createTime,
      },
      frog: {
        name: state.name,
        cur_achieve: state.curAchieve,
        achieves: state.achieves,
        /* ALWAYS EMPTY on purpose: see checkAchievements(). This field is an EXPIRY
           list, and any entry makes the client treat that title as already expired
           (it lists nothing but question marks and reports no current title). An
           absent entry means "never expires", which is what an offline game wants.
           Old saves may still carry earns-time entries from before this fix, so
           the field is filtered out rather than merely not written. */
        achieves_time: [],
        status: state.frog.status,
        motion: state.frog.motion,
        icon: state.frog.icon,
        pic_show: state.frog.picShow,
        today_step: state.frog.todayStep,
        decoration: state.decoration.hasList,
        taobao_data: state.frog.taobaoData,
      },
      gacha: { color_ball: state.gacha.colorBall },
    };
  }

  // Weather/season. The season key is season + "" + hours_type and must map to an
  // existing resource group: default.res.json only defines season11..season44.
  function weatherPayload() {
    return {
      season: state.weather.season,
      hours_type: state.weather.hoursType,
      weather: state.weather.weather,
    };
  }

  /* Season and time-of-day TOGETHER pick the courtyard artwork (the client keys it
     as season + "" + hours_type, and the pack defines exactly season11..season44).
     Driving both from the real clock is what makes the garden change between
     spring/summer/autumn/winter and day/evening/night. Enum values are the game's
     own (Define: Season spring1..winter4, HoursType day1..late_night4).
     These use the LOCAL clock on purpose. They used to read UTC fields, which for
     a UTC+8 player selected the wrong season near a month boundary and, far more
     visibly, rendered the night courtyard during the local afternoon -- the
     player's own wall clock is what the artwork is supposed to reflect. */
  function seasonNow() {
    const m = new Date(nowSec() * 1000).getMonth() + 1;
    if (m >= 3 && m <= 5) return 1;        // spring
    if (m >= 6 && m <= 8) return 2;        // summer
    if (m >= 9 && m <= 11) return 3;       // autumn
    return 4;                              // winter
  }

  function hoursTypeNow() {
    const h = new Date(nowSec() * 1000).getHours();
    if (h >= 6 && h < 18) return 1;        // day
    if (h >= 18 && h < 21) return 2;       // evening
    if (h >= 21) return 3;                 // night
    return 4;                              // late night (0..5)
  }

  /* The live service decided the weather and that schedule is not recoverable, so
     we pin a VALID enum value -- WeatherType runs 1..9 and the old default of 0 was
     outside it -- and vary it deterministically by day so it is not always the
     same. This model is ours, not the original's. */
  function weatherNow() {
    const d = new Date(nowSec() * 1000);
    return ((d.getFullYear() * 372 + (d.getMonth() + 1) * 31 + d.getDate()) % 9) + 1;
  }

  /** @returns true when the season/hours/weather actually changed. */
  function refreshWeather() {
    const s = seasonNow();
    const ht = hoursTypeNow();
    const w = weatherNow();
    if (state.weather.season === s && state.weather.hoursType === ht
        && state.weather.weather === w) {
      return false;
    }
    state.weather.season = s;
    state.weather.hoursType = ht;
    state.weather.weather = w;
    save();
    return true;
  }

  /* The frog's at-home activity. Frogpattern is a SERVER-side table -- the client
     only ever defines it and never reads it -- listing activity tokens across
     FrogPatternMax = 3 patterns, and FrogMotionNum maps each token to the motion
     index the client looks up in FrogMotionName (0 dokusyo_ie reading at the bed,
     1 inemuri_ie dozing, 2 hikki_ie writing at the desk, 3 sagyou_ie making things,
     4 syokuzi_ie eating; 5..13 are other animations and isFrogSleep() covers
     10..13). Walking the sequence is what makes the frog do different things while
     it waits at home instead of standing still. */
  const FROGPATTERN = (defineData.maps && defineData.maps.Frogpattern) || {};
  const FROGMOTIONNUM = (defineData.maps && defineData.maps.FrogMotionNum) || {};
  /* How long one at-home activity lasts. Not recoverable from any table, so this
     is our choice; override with FROG_MOTION_SEC. */
  const FROG_MOTION_SEC = Number(process.env.FROG_MOTION_SEC || 45);

  function refreshFrogMotion(t) {
    if (state.frog.status !== 0) return false;          // only while at home
    if (t < (state.frog.motionNextAt || 0)) return false;
    const keys = Object.keys(FROGPATTERN);
    if (!keys.length) return false;

    if (state.frog.motionPattern == null) {
      const max = Math.max(1, Number(DEF('FrogPatternMax', 3)));
      state.frog.motionPattern = Math.floor(Math.random() * max);
      state.frog.motionStep = 0;
    }
    const seq = FROGPATTERN[String(state.frog.motionPattern)] || FROGPATTERN[keys[0]];
    if (!Array.isArray(seq) || !seq.length) return false;

    state.frog.motionStep = ((state.frog.motionStep || 0) + 1) % seq.length;
    const token = seq[state.frog.motionStep];
    state.frog.motion = Number(FROGMOTIONNUM[token]) || 0;
    state.frog.motionNextAt = t + FROG_MOTION_SEC;
    save();
    // 回忆彩蛋 type 1 (frog_motion): the moment's param IS a FrogMotionName value
    // ('dokusyo_ie', 'knit', 'cut', 'sleep_2' ...), so the current motion name
    // decides which moment this unlocks.
    const motionName = (defineData.maps && defineData.maps.FrogMotionName || {})[String(state.frog.motion)];
    if (motionName) momentTrigger(1, motionName);
    return true;
  }

  /* ------------------------------------------------- save editor (GM) */
  /* The client ships a hidden GM console (enable via showGM:true in
     gameConfig.json). It posts free-form text as client_gm and shows whatever
     we return in `info`, so this doubles as the in-game save editor. */
  const GM_HELP = [
    'state - 查看存档摘要',
    'add_clover N / set_clover N',
    'add_ticket N / set_ticket N',
    'set_name 名字',
    'add_item ID [N] - 放 N 个物品进家',
    'add_specialty ID [N] - 加特产',
    'add_picture ID - 加明信片',
    'unlock_pictures - 解锁全部明信片',
    'unlock_all - 解锁全部图鉴(纪念品/特产) + 博物馆图鉴 + 全部百科',
    'unlock_museum - 只解锁博物馆图鉴（大冒险已关闭，用它代替）',
    'all_furniture - 获得全部家具',
    'expand_album - 扩容相册到上限（拿到全部「相册扩容」，页数 30 → '
      + (ALBUM_BASE_PAGES + ALBUM_EXPANSION_SLOTS) + '，可放 '
      + ((ALBUM_BASE_PAGES + ALBUM_EXPANSION_SLOTS) * ALBUM_PAGE_SIZE) + ' 张）',
    'album_state - 看相册用量（张数/容量/待归档/回收站）',
    'bench_state - 看工作台（是否锁定/台面图纸/还差什么材料）',
    'craft_start 家具ID - 开始制作（图纸+材料一并备齐，制作中工作台锁定）',
    'craft_finish - 立刻完成当前制作',
    'file_pending - 把"新照片"全部归档进相册（容量 '
      + ((ALBUM_BASE_PAGES + ALBUM_EXPANSION_SLOTS) * ALBUM_PAGE_SIZE) + ' 张）',
    'harvest_all / clear_clovers - 三叶草地全熟 / 全清',
    'set_status N - 青蛙状态 0在家 1旅行 2待机 3聚会',
    'travel_now / come_home - 立刻出门 / 立刻回家',
    'put_bag 格号 ID / put_desk 格号 ID / clear_bag / clear_desk',
    'reset_save - 重置存档',
  ].join(' | ');

  function gmCommand(line, ctx) {
    const parts = line.split(/\s+/).filter(Boolean);
    const cmd = (parts.shift() || '').toLowerCase();
    const arg = (i, dflt) => {
      const v = Number(parts[i]);
      return Number.isFinite(v) ? v : dflt;
    };
    const ok = (info) => ({ succeed: true, info: info || '' });
    const bad = (info) => ({ succeed: false, info: info || '' });

    // push refreshed world state so the change is visible without a reload
    const refresh = () => {
      ctx.push('client_load_role', rolePayload());
      ctx.push('clover_update', { clover: state.clover });
      ctx.push('item_update_ticket', { ticket: state.ticket });
      ctx.push('item_load_items', handlers.item_load_items());
      ctx.push('clover_load_clovers', state.clovers);
      ctx.push('travel_load_gift', giftBoxPayload());
      /* The 图鉴 / 百科 / 家具 / 博物馆图鉴 / 相册 pages read their own MODEL, and those
         models are filled only by their `*_load` command -- the views do not re-request
         when they are opened (EncyView.childrenCreated sends nothing at all). Pushing
         the same payloads the client gets at login is what makes an edit show up
         immediately; without it the player had to restart the game, which is exactly
         what was reported. */
      ctx.push('item_load_handbook', handlers.item_load_handbook());
      ctx.push('encyclopedia_load', encyclopediaPayload());
      ctx.push('furniture_load_furniture', handlers.furniture_load_furniture({}));
      ctx.push('museum_load', handlers.museum_load());
      ctx.push('album_load_all', handlers.album_load_all());
      /* ...and the `layers` behind every one of those entries. album_load_all only
         carries {id, pic_id, for_ads, visit} -- a card is DRAWING from its layers, so
         without this push the newly added cards are blank/transparent until the next
         login (login fills them from album_load, which does carry layers). */
      ctx.push('album_load_by_id_list', handlers.album_load_by_id_list({
        id_list: state.pictures.map((p) => p.id),
      }));
      ctx.push('album_load_recover', handlers.album_load_recover());
    };

    switch (cmd) {
      case '':
      case 'help':
        return ok(GM_HELP);

      case 'state': {
        const bag = state.items.bag.filter((x) => x !== -1).length;
        const desk = state.items.desk.filter((x) => x !== -1).length;
        return ok('uid=' + state.uid + ' 名字=' + state.name +
          ' 三叶草=' + state.clover + ' 抽奖券=' + state.ticket +
          ' 状态=' + state.frog.status + ' 明信片=' + state.pictures.length +
          ' 特产=' + state.specialtys.length + ' 家里物品=' + state.items.house.length +
          ' 行李=' + bag + '/4 桌子=' + desk + '/8 出行次数=' + (state.travel.tripCount || 0));
      }

      case 'add_clover': state.clover += arg(0, 10); save(); refresh(); return ok('三叶草=' + state.clover);
      case 'set_clover': state.clover = Math.max(0, arg(0, 0)); save(); refresh(); return ok('三叶草=' + state.clover);
      case 'add_ticket': state.ticket += arg(0, 1); save(); refresh(); return ok('抽奖券=' + state.ticket);
      case 'set_ticket': state.ticket = Math.max(0, arg(0, 0)); save(); refresh(); return ok('抽奖券=' + state.ticket);

      case 'set_name': {
        const name = parts.join(' ').trim();
        if (!name) return bad('用法: set_name 名字');
        state.name = name;
        save(); refresh();
        return ok('名字=' + state.name);
      }

      case 'add_item': {
        const id = arg(0, -1);
        if (id < 0) return bad('用法: add_item ID [数量]');
        const n = arg(1, 1);
        const cur = state.items.house.find((h) => h.item_id === id);
        if (cur) cur.count += n; else state.items.house.push({ item_id: id, count: n });
        save(); refresh();
        return ok('家里已有 ' + id + ' x' + (cur ? cur.count : n));
      }

      case 'add_specialty': {
        const id = arg(0, -1);
        if (id < 0) return bad('用法: add_specialty ID [数量]');
        const n = arg(1, 1);
        const cur = state.specialtys.find((s) => s.item_id === id);
        if (cur) cur.count += n; else state.specialtys.push({ item_id: id, count: n });
        save(); refresh();
        return ok('特产 ' + id + ' x' + (cur ? cur.count : n));
      }

      case 'add_picture': {
        /* The argument is a Picture-table id, so it goes into `pic_id` (see the note in
           unlock_pictures); the album handle is allocated separately. */
        const picId = arg(0, -1);
        if (picId < 0) return bad('用法: add_picture ID');
        if (!state.pictures.some((p) => p && p.pic_id === picId)) {
          state.pictureSeq = (state.pictureSeq || 0) + 1;
          state.pictures.push({ id: state.pictureSeq, pic_id: picId, read: 0, new: 1 });
        }
        save(); refresh();
        return ok('明信片 ' + id + '，共 ' + state.pictures.length + ' 张');
      }

      /* 解锁全部图鉴与百科 (and the museum, which is the replacement for 大冒险). */
      case 'unlock_all': {
        const h = unlockHandbook(ctx);
        const m = unlockMuseum();
        state.encyAll = true;
        save(); refresh();
        return ok('图鉴：纪念品 ' + h.collections + ' / 特产 ' + h.specialtys
          + '；博物馆新增明信片 ' + m.pictures + ' 张、藏品 ' + m.collections
          + ' 件；百科已全部解锁');
      }

      /* 获得全部家具 */
      case 'all_furniture': {
        const f = unlockFurniture();
        save(); refresh();
        return ok('家具已全部解锁：新增 ' + f.furniture + ' 件，共 ' + f.total + ' 件');
      }

      /* 扩容相册到上限: the shop sells ALBUM_EXPANSION_SLOTS「相册扩容」(item 9000) in a
         chained set, and the client's 扩容 tip + page count both read that item count --
         so the editor grants the real items instead of keeping a private page number. */
      case 'expand_album': {
        const g = grantAlbumExpansions();
        save(); refresh();
        pushItemUpdate(ctx, ALBUM_EXPAND_ITEM, g.after);
        return ok('相册扩容 ' + g.before + ' → ' + g.after + ' 件；页数 ' + g.pages
          + ' 页，可放 ' + g.capacity + ' 张（当前 ' + state.pictures.length + ' 张）');
      }

      case 'album_state': {
        const pages = ALBUM_BASE_PAGES + albumExpansions();
        return ok('相册：' + state.pictures.length + ' 张 / 可放 ' + albumCapacity()
          + '（' + pages + ' 页 x ' + ALBUM_PAGE_SIZE + '）；扩容已拥有 '
          + albumExpansions() + '/' + ALBUM_EXPANSION_SLOTS
          + '；待归档 ' + ((state.albumPending || []).length + (state.albumPendingVisit || []).length)
          + ' 张；回收站 ' + ((state.albumDeleted || []).length) + ' 张');
      }

      /* 工作台制作（图纸 -> 家具）。三条命令：看状态 / 开始 / 立即完成。 */
      case 'bench_state': {
        const craft = state.furniture.craft;
        const bp = benchBlueprint();
        const info = craft
          ? ('制作中：家具 ' + craft.furnitureId + '（图纸 ' + craft.drawing + '），还剩 '
             + Math.max(0, Math.ceil((craft.finishAt - nowSec()) / 60)) + ' 分钟')
          : (bp ? ('台面有图纸 ' + bp.itemId + '（家具 ' + bp.furnitureId + '）'
                   + (craftMissing().missing.length
                     ? '，材料还差 ' + craftMissing().missing.map((m) => m.item_id + 'x' + m.count).join(',')
                     : '，材料齐了就自动开工'))
                : '台面没有图纸（把图纸放进 5–9 号物品位）');
        return ok('工作台：' + (state.furniture.benchLock ? '锁定' : '空闲') + '；' + info
          + '；可制作 ' + BENCH_IDS.size + ' 种（benchData）');
      }

      case 'craft_start': {
        const id = arg(0, -1);
        if (id < 0) return bad('用法: craft_start 家具ID（图纸与材料会一并备齐）');
        const r = startCraftFor(id);
        if (!r.ok) return bad('没能开工：' + r.reason);
        save(); refresh();
        const craft = state.furniture.craft;
        return ok('开工：家具 ' + craft.furnitureId + '，材料 '
          + craft.materials.map((m) => m.item_id + 'x' + m.count).join(', ')
          + '，' + Math.round(CRAFT_SECONDS / 60) + ' 分钟后完成（工作台已锁定）');
      }

      case 'craft_finish': {
        if (!state.furniture.craft) return bad('工作台现在没有在做的活');
        const fid = state.furniture.craft.furnitureId;
        state.furniture.craft.finishAt = nowSec() - 1;
        const done = craftTick(ctx, nowSec());
        save(); refresh();
        return ok(done ? ('已完成：家具 ' + fid + ' 已入库（共 ' + (state.furniture.owned || []).length + ' 件）')
          : '结算失败');
      }

      case 'unlock_museum': {
        const m = unlockMuseum();
        save(); refresh();
        return ok('博物馆图鉴：新增明信片 ' + m.pictures + ' 张、藏品 ' + m.collections + ' 件');
      }

      case 'unlock_pictures': {
        /* A full unlock puts ~351 photos in, far past the 30-page base, so grant the
           相册扩容 set first -- otherwise the engine would immediately consider the
           album "full" and every later trip photo would be swallowed by code 75. */
        const grew = grantAlbumExpansions();
        let added = 0;
        for (const picId of PICTURE_IDS) {
          /* `id` is the album's own unique handle; `pic_id` is the Picture-table row
             that selects the artwork. Pushing only `id` (as this used to) left
             `pic_id` undefined, so `withLayers()` found no composition and every card
             rendered blank -- and opening one then threw. */
          if (state.pictures.some((p) => p && p.pic_id === picId)) continue;
          if (state.albumPending.some((p) => p && p.pic_id === picId)) continue;
          state.pictureSeq = (state.pictureSeq || 0) + 1;
          state.pictures.push({ id: state.pictureSeq, pic_id: Number(picId), read: 0, new: 1 });
          added++;
        }
        save(); refresh();
        if (grew.before !== grew.after) pushItemUpdate(ctx, ALBUM_EXPAND_ITEM, grew.after);
        return ok('新增 ' + added + ' 张，共 ' + state.pictures.length + ' 张（相册总量 '
          + PICTURE_IDS.length + '；相册已扩容到 ' + grew.pages + ' 页 / 可放 ' + grew.capacity + ' 张）');
      }

      /* Newly earned postcards sit in the PENDING bucket (相册的"新照片") until
         filed with album_save_new in the album UI. This is the escape hatch: if
         the player cannot find that UI, the photos are not stranded -- and the
         album cap still applies, so it cannot be used to overflow the album. */
      case 'file_pending': {
        const pend = state.albumPending || [];
        const visit = state.albumPendingVisit || [];
        let filed = 0;
        let full = 0;
        for (const list of [pend, visit]) {
          while (list.length) {
            if (state.pictures.length >= albumCapacity()) { full = list.length; break; }
            state.pictures.push(list.shift());
            filed++;
          }
        }
        save(); refresh();
        return ok('已归档 ' + filed + ' 张，相册 ' + state.pictures.length + '/' + albumCapacity()
          + '（' + (ALBUM_BASE_PAGES + albumExpansions()) + ' 页）'
          + (full ? '，还有 ' + full + ' 张因相册已满未归档（可用 expand_album 扩容）' : ''));
      }

      case 'harvest_all':
        for (const s of state.clovers) { s.last_harvest = 0; s.element = 0; s.sprite = 1; }
        save(); refresh();
        return ok('三叶草地已全部成熟');

      case 'clear_clovers':
        for (const s of state.clovers) s.last_harvest = -1;
        save(); refresh();
        return ok('三叶草地已清空');

      case 'set_status': {
        const v = arg(0, -1);
        if (v < 0 || v > 3) return bad('用法: set_status 0..3 (0在家 1旅行 2待机 3聚会)');
        state.frog.status = v;
        save(); refresh();
        return ok('青蛙状态=' + v);
      }

      case 'travel_now':
        if (state.frog.status === 1) return bad('青蛙已经出门了');
        if (!departFrog(ctx, nowSec())) return bad('请先在背包或桌子上准备食物');
        return ok('青蛙已出门');

      case 'come_home':
        returnFrog(ctx, nowSec());
        return ok('青蛙已回家');

      case 'put_bag': {
        const pos = arg(0, -1), id = arg(1, -1);
        if (pos < 1 || pos > state.items.bag.length || id < 0) return bad('用法: put_bag 1..4 ID');
        state.items.bag[pos - 1] = id; save(); refresh();
        return ok('行李第 ' + pos + ' 格 = ' + id);
      }
      case 'put_desk': {
        const pos = arg(0, -1), id = arg(1, -1);
        if (pos < 1 || pos > state.items.desk.length || id < 0) return bad('用法: put_desk 1..8 ID');
        state.items.desk[pos - 1] = id; save(); refresh();
        return ok('桌子第 ' + pos + ' 格 = ' + id);
      }
      case 'clear_bag':
        state.items.bag = state.items.bag.map(() => -1); save(); refresh(); return ok('行李已清空');
      case 'clear_desk':
        state.items.desk = state.items.desk.map(() => -1); save(); refresh(); return ok('桌子已清空');

      /* the client's own full_craft sends these in pairs */
      case 'add_stamp_new':
      case 'add_wish_new':
        return ok('true');
      case 'save_stamp_new':
      case 'save_wish_new':
        return ok('true');

      case 'reset_save': {
        const fresh = defaultState();
        for (const k of Object.keys(state)) delete state[k];
        Object.assign(state, fresh, { clovers: makeClovers() });
        save(); refresh();
        return ok('存档已重置（建议执行 reload）');
      }

      default:
        return bad('未知指令: ' + cmd + ' — 输入 help 查看全部指令');
    }
  }

  const handlers = {
    /* --- handshake --- */
    client_hello: () => ({ timestamp: nowSec() }),

    hall_gen_token: (d) => {
      state.account = d.account || state.account;
      return { code: 0, token: 'offline-' + state.account };
    },

    hall_login: (d) => {
      if (d && d.token) state.account = String(d.token).replace(/^offline-/, '') || state.account;
      return { code: 0, account: state.account };
    },

    hall_reconnect: () => ({ code: 0, account: state.account }),

    hall_enter_game: (d, ctx) => {
      refreshClovers(nowSec());
      refreshWeather();                 // real season / time-of-day before first push
      ensureTutorialMails();
      /* 大冒险 is off, and it was the only way to earn museum postcards -- so the museum
         图鉴 is unlocked instead (once; `museumUnlocked` records it). */
      if (!MUSEUM_DAY_ENABLED && !state.museumUnlocked) unlockMuseum();
      /* 生日蛋糕 task 1 「登录游戏」 counts a session, not every command. */
      pcTaskProgress(1, 1);
      save();
      // Role + weather first: client_load_role seeds uid/clientSettings and the
      // season key must be known before the client loads its seasonal assets.
      ctx.push('client_load_role', rolePayload());
      ctx.push('weather_load', weatherPayload());
      // Then the rest of the world state, built from the same handlers.
      for (const name of BOOT_PUSH) {
        const fn = handlers[name];
        if (typeof fn !== 'function') continue;
        const payload = fn({}, ctx);
        if (payload !== undefined) ctx.push(name, payload);
      }
      return { code: 0 };
    },

    hall_leave_game: () => ({}),

    /* --- role --- */
    client_load_role: () => rolePayload(),

    // response is ignored by the client's callback, but must arrive
    client_load_all_info: () => ({ code: 0 }),

    /* NOTE: `client_load_decorate` was ALSO defined here, earlier and more
       crudely. A duplicate handler key is not an error in JS -- the last one
       wins -- so having two was a latent trap (the same shape of bug that hid
       `lottery_load` behind a stub). There is now a unit test that rejects
       duplicate handler keys; it found this one. The surviving definition is the
       one that returns COPIES rather than live state references. */

    /* The client NEVER sends `client_set_name` on its own. UserModel.setName()
       first asks the price (`client_rename_cost`), shows a confirm box when it is
       > 0, and only then renames. The guide's FIRST naming uses the same pair of
       commands, so with no handler for the price BOTH were dead ends: the callback
       never fired, no confirm box ever appeared, and the naming guide never
       advanced -- a brand-new account could not be named at all. The client reads
       `n.clover` from this reply. */
    client_rename_cost: () => ({ clover: state.renamed ? RENAME_CLOVER : 0 }),

    client_set_name: (d) => {
      /* Client-side this is `getName()` after the reply, so keep it a string. */
      const name = String(d && d.name != null ? d.name : '');
      if (!name) return { code: 5 };              // 5 = 参数非法 (in errcode.json)
      const cost = state.renamed ? RENAME_CLOVER : 0;
      /* The client checks this itself before sending, so a shortage here means the
         two sides disagree; 61 (资源不足) is in errcode.json and therefore SHOWS. */
      if (state.clover < cost) return { code: 61 };
      state.name = name;
      if (cost > 0) state.clover = Math.max(0, state.clover - cost);
      /* Charged from here on. Deliberately NOT returned as `lucky`: the guide
         answers a truthy second field with "等会记得到邮箱来领取小礼物", and we
         would then owe a mail we never send. */
      state.renamed = true;
      save();
      return { code: 0 };
    },

    /* --- clover / currency --- */
    clover_load_clovers: () => {
      if (refreshClovers(nowSec())) save();
      return state.clovers;
    },

    clover_harvest: (d, ctx) => {
      const id = Number(d.clover_id);
      const slot = state.clovers[id - 1];
      if (!slot) return { code: 1 };
      const t = nowSec();
      if (cloverStatus(slot, t) !== 'ready') return { code: 2 };

      /* Mirrors the client's harvestClover():
           0 == element -> UserModel.addClover(1)
           1 == element -> ItemModel.addHouseItem(Define.FourLeafCloverID, 1)
           2 == element -> ItemModel.addHouseItem(sprite, 1)
         addClover AND addHouseItem are both empty stubs in the client, so every
         branch has to be delivered as a push. Previously we always paid +1 clover
         and cleared the slot, which silently turned a four-leaf clover into an
         ordinary one. */
      const element = slot.element;
      const sprite = slot.sprite;
      slot.last_harvest = t;
      slot.rebirth_span = rollCloverRebirth();
      slot.element = 0;
      slot.sprite = 1;

      let granted;
      if (element === 1) {
        granted = 'four_leaf';
        const count = addHouseItem(FOUR_LEAF_CLOVER_ID, 1);
        save();
        pushItemUpdate(ctx, FOUR_LEAF_CLOVER_ID, count);
      } else if (element === 2) {
        granted = 'sprite';
        const count = addHouseItem(sprite, 1);
        save();
        pushItemUpdate(ctx, sprite, count);
      } else {
        granted = 'clover';
        state.clover += 1;
        save();
        ctx.push('clover_update', { clover: state.clover });
      }

      // The reply's clover_id is what lets the client drop the entry from its
      // pending-harvest list (harvestClover compares e.clover_id); without it the
      // resend timer would keep re-sending forever.
      return { code: 0, clover: state.clover, clover_id: id, granted };
    },

    clover_harvest_resend: () => ({ code: 0 }),

    /* --- items --- */
    item_load_items: () => ({
      house: state.items.house,
      bag: state.items.bag,
      desk: state.items.desk,
      bag_completed: state.items.bagCompleted,
      bag_conflict: state.items.bagConflict,
      desk_conflict: state.items.deskConflict,
      gacha: { color_ball: state.gacha.colorBall },
    }),

    /* ItemModel stores this in purchasedMap, and the client keys that map by
       SHOP SLOT id (buyItem does purchasedMap[shopId]++, isShopItemBuyLimit
       reads purchasedMap[shopId], getShopItemBuynums reads purchasedMap[e]).
       The field is named item_id but carries the slot id. */
    item_load_shop_info: () => ({
      purchased: Object.keys(state.shopBought)
        .filter((k) => state.shopBought[k] > 0)
        .map((k) => ({ item_id: Number(k), count: state.shopBought[k] })),
    }),
    item_load_handbook: () => ({
      collections: state.handbook.collections,
      specialtys: state.handbook.specialtys,
    }),
    /* The client's queue is built from `list`: check_select_gift() pops
       selectGiftList[0] and shows GiftSelectView(row.num, row.items), and
       req_select_gift() then sends item_select_gift(index_list) and shows the granted
       package from THAT reply's `items`. We used to answer with `items` here too, so
       the queue stayed empty for the wrong reason -- the key. (Audited: nothing in this
       build QUEUES a package; our events hand items over directly or by mail, so the
       list is normally empty anyway. A slot, if one ever exists, is now delivered in the
       shape the client reads.) */
    item_load_select_gift: () => ({
      list: Object.keys(state.selectGift).map((k) => {
        const slot = state.selectGift[k];
        return {
          num: Math.max(1, Number(slot.num) || 1),
          items: [{ item_id: Number(slot.item_id), count: Number(slot.count) || 0 }],
        };
      }),
    }),

    /* --- packing: typed slots and real inventory transfers --- */
    item_putin_bag: (d, ctx) => packItem('bag', d, ctx, false),
    item_takeout_bag: (d, ctx) => packItem('bag', d, ctx, true),
    item_putin_desk: (d, ctx) => packItem('desk', d, ctx, false),
    item_takeout_desk: (d, ctx) => packItem('desk', d, ctx, true),

    /* 行囊「准备完成 / 锁定」按钮 —— the client's ONLY trip trigger.
       ItemModel.setBagLock(e) sends this with the single positional param `completed`
       (ProtocolList: item_set_bag_completed:[["completed"],!1] -- no session callback),
       and ItemModel.item_load_items reads the authoritative value back into `bagLock`
       (`this.bagLock = e.bag_completed || false`). BagView.lock() refuses to lock unless
       a lunch box sits in the bag's LunchBox slot, then advances the tutorial step
       locally -- so this command is also what ends 新手引导 的"准备行李"。
       Until now our engine had NO handler for it: the tap was silently dropped and the
       frog only ever left on the idle timer, so "准备完成" did nothing.
       Semantics here: record the lock, echo it authoritatively, and DEPART immediately
       when the bag/desk actually has provisions (the idle timer stays as a fallback for
       players who never touch the button). Unlocking before departure is allowed. */
    item_set_bag_completed: (d, ctx) => {
      const completed = d.completed === true || Number(d.completed) > 0;
      if (completed && state.frog.status !== 1 && !tripPrepared()) {
        state.items.bagCompleted = 0;
        state.travel.waitingForBag = true;
        save();
        ctx.push('item_load_items', handlers.item_load_items());
        return { code: -1 };
      }
      const wasCompleted = state.items.bagCompleted ? 1 : 0;
      state.items.bagCompleted = completed ? 1 : 0;
      save();
      const depart = completed && !wasCompleted && state.frog.status !== 1 && tripPrepared();
      /* departFrog already pushes item_load_items (and client_load_role); pushing here
         too would send the same payload twice. */
      if (depart) departFrog(ctx, nowSec());
      else ctx.push('item_load_items', handlers.item_load_items());
      return { code: 0 };
    },

    /* Mirrors RoleModel.buyItem (which sends ONLY shop_id).
       The client deducts the clover optimistically before sending, so every
       rejection here has to push an authoritative clover_update to undo that
       local deduction. On success we must push item_update: the client's
       ItemModel.addHouseItem() is an empty stub, so without the push the
       purchase never shows up in the house. */
    /* Gift codes are a promotional feature whose codes were issued by the live
       service, so offline there is nothing valid to accept. The client treats
       code 200 as success (`if (200 == e.code)`) and anything else as an error it
       looks up in MessageModel.getErrorInfo, falling back to "礼包码无效".
       Returning 200 for everything would be a lie, so refuse -- and note the 200
       convention here for whoever implements real codes later. */
    item_use_gift_code: () => ({ code: -1 }),

    item_buy: (d, ctx) => {
      const shopId = Number(d.shop_id);
      const slot = SHOP_BY_ID.get(shopId);
      const refuse = (code, reason) => {
        ctx.push('clover_update', { clover: state.clover });
        return { code, reason };
      };
      if (!slot) return refuse(-1, 'unknown shop slot');
      const bought = state.shopBought[shopId] || 0;
      const it = ITEM_BY_ID.get(slot.itemId);
      if (slot.limit > 0) {
        if (bought >= slot.limit) return refuse(-2, 'buy limit reached');
        // client rule: durable goods (spend != 1) with an ownership cap also
        // block once you already own own_num of them
        if (it && it.spend !== 1 && it.own_num > 0
            && getHaveItem(slot.itemId) >= it.own_num) {
          return refuse(-2, 'already own the maximum');
        }
      }
      // before_buy is a [kind, id] PAIR: ['shop', 22] means "shop slot 22 must
      // have been bought first", which is what chains the album-expansion series
      // (22 -> 23 -> 24 -> ...) and 工具 -> 材料.
      if (!shopPrereqMet(slot.before_buy)) {
        return refuse(-3, 'prerequisite not met');
      }
      if (state.clover < slot.price) return refuse(-4, 'not enough clover');

      state.clover -= slot.price;
      state.shopBought[shopId] = bought + 1;
      /* 套装/盲盒 is opened on the spot, everything else goes to the house. */
      grantItemOrPackage(ctx, slot.itemId, 1);
      /* 生日蛋糕 task 2 「商店买买买」 */
      pcTaskProgress(2, 1);
      save();
      ctx.push('clover_update', { clover: state.clover });
      return { code: 0 };
    },

    /* ---- raffle (ふくびき) ------------------------------------------------
       Flow read off RaffleView:
         raffle()  -> consumeTicket(Define.RAFFEL_NEEDTICKETS = 5), which only
                      TESTS affordability, then sends item_gacha{is_reward:false}
         reply     -> ItemModel.item_gacha does gachaColorBall = e.ticket, i.e.
                      the reply's `ticket` field carries the BALL RANK
         reward    -> the result switch: rank 0 (White) is a TICKET prize (count
                      = Prize.stock, always 1 here); ranks 1..5 open PrizeSelector
                      over the Prize rows of that rank
         both end  -> item_redeem_prize{prize_id}, which is needResponse:false, so
                      the grant must happen here with no reply at all
       addTicket / addHouseItem are EMPTY stubs, so nothing is ever credited
       unless we push item_update_ticket / item_update ourselves. */
    item_gacha: (d, ctx) => {
      const isReward = !!(d && d.is_reward);
      const pending = state.gacha.colorBall;
      // Re-announce the ball we already rolled instead of charging a second time:
      // reward_raffle() re-sends with is_reward:true when it still has a ball.
      if (isReward && pending >= 0) return { ticket: pending };

      const cost = Number(DEF('RAFFEL_NEEDTICKETS', 5));
      if (state.ticket < cost) return { ticket: -1 };
      if (!isReward) {
        state.ticket -= cost;
        state.gachaCount = (state.gachaCount || 0) + 1;   // for "抽奖20次以上"
      }

      const rank = rollPrizeRank();
      state.gacha.colorBall = rank;
      /* 生日蛋糕 task 3 「商店抽奖一次」 */
      pcTaskProgress(3, 1);
      save();
      ctx.push('item_update_ticket', { ticket: state.ticket });
      return { ticket: rank };
    },

    item_redeem_prize: (d, ctx) => {
      const row = PRIZE_BY_ID.get(Number(d && d.prize_id));
      if (!row) return undefined;
      const stock = Number(row.stock) || 1;
      const itemId = Number(row.itemId);
      if (itemId < 0 || Number(row.rank) === 0) {
        // the pure-ticket prize: the client shows stock as the ticket count
        state.ticket += stock;
        ctx.push('item_update_ticket', { ticket: state.ticket });
      } else {
        const count = addHouseItem(itemId, stock);
        pushItemUpdate(ctx, itemId, count);
      }
      state.gacha.colorBall = -1;          // matches cleanGachaColorBall()
      save();
      return undefined;                    // needResponse:false
    },

    /* --- travel --- */
    /* The client builds these rows itself from its own config table; the reply
       only needs the three per-note fields, and every id must exist in the Note
       table or the row is unusable. */
    travel_load_note: () => ({
      note_list: state.notes.map((n) => ({
        id: n.id, read: n.read || 0, timestamp: n.timestamp || 0,
      })),
    }),
    travel_load_gift: () => giftBoxPayload(),

    /* ---------------- gift box (礼品盒) transfers ----------------------------

       The gift box is a HOLDING AREA SEPARATE FROM THE ALBUM. The client has two
       independent models: TravelModel.pictureInfoList (the album, filled by
       `album_load`) and GiftBoxModel.pictureList / .specialityList (filled ONLY
       by `travel_load_gift`). It was a real bug here to hand the album to the
       gift box: the gift box then showed every filed postcard, and acting on one
       corrupted the album.

       Contracts read from main.min.js:
         travel_gift_to_bag(item_id)        gift box specialty -> house inventory
         travel_bag_to_gift(item_id)        house -> gift box   (code 102 = box full)
         travel_album_to_gift(picture_id)   album -> gift box
         travel_gift_to_album(picture_id)   gift box -> album  (code 101 = album full)
         travel_gift_delete_album(id)       drop a gift-box picture
         travel_read_note(id)               mark a note read (needResponse FALSE)
         item_select_gift(index_list)       claim a queued gift package

       Codes 101/102 are not guesses: the client branches on exactly those two
       (`101 == a.code` -> "相册满了，要删除一张照片继续保存吗?",
        `102 == s.code` -> "礼品盒满了，要更换保存的特产的吗？"), so returning
       anything else would silently do nothing. Caps come from the original
       server's own table: Define.ALBUM_MAX = 60, Define.SPECIALTY_MAX = 100. */
    travel_gift_to_bag: (d, ctx) => {
      const itemId = Number(d && d.item_id);
      const slot = state.giftBox.specialtys.findIndex((s) => s.item_id === itemId);
      /* 42 (物品不足) rather than -1: this callback is
         `function(i,n){ var r = getErrorInfo(i.code); if (!r || 0 == r.code) {...move...} }`,
         so a code the table LACKS reads as SUCCESS and the client performs the move
         locally while we do nothing -- the specialty leaves the gift box in the UI
         and comes back on the next push. 42 is in errcode.json, so the branch is
         correctly taken as a failure. */
      if (slot === -1) return { code: 42 };
      state.giftBox.specialtys.splice(slot, 1);
      addHouseItem(itemId, 1);
      save();
      ctx.push('item_load_items', handlers.item_load_items());
      pushItemUpdate(ctx, itemId, getHaveItem(itemId));
      return { code: 0 };
    },

    travel_bag_to_gift: (d, ctx) => {
      const itemId = Number(d && d.item_id);
      /* Codes must exist in the client's errcode.json (preload.eab). Its callers
         are written `var s = getErrorInfo(o.code); if (s && 0 != s.code) {...error...}
         else {...move...}` -- an UNKNOWN code makes getErrorInfo return undefined,
         `s &&` fails, and the client walks the SUCCESS branch while we did nothing:
         the item appears to move and then snaps back on the next push. */
      if (!ITEM_BY_ID.has(itemId)) return { code: 5 };   // 5 = 参数非法
      if (getHaveItem(itemId) <= 0) return { code: 42 };  // 42 = 物品不足
      if (giftBoxCount() >= SPECIALTY_MAX) return { code: 102 };  // 礼品盒满了
      addHouseItem(itemId, -1);
      addGiftSpecialty(itemId, 1);
      save();
      pushItemUpdate(ctx, itemId, getHaveItem(itemId));
      return { code: 0 };
    },

    travel_album_to_gift: (d) => {
      const picId = Number(d && d.picture_id);
      const i = state.pictures.findIndex((p) => p.id === picId);
      if (i === -1) return { code: 74 };   // 74 = 删除错误的照片id
      const pic = state.pictures.splice(i, 1)[0];
      state.giftBox.pictures.push(pic);
      save();
      return { code: 0 };
    },

    travel_gift_to_album: (d) => {
      const picId = Number(d && d.picture_id);
      const i = state.giftBox.pictures.findIndex((p) => p.id === picId);
      if (i === -1) return { code: 74 };   // 74 = 删除错误的照片id
      if (state.pictures.length >= albumCapacity()) return { code: 101 };  // 相册满了
      const pic = state.giftBox.pictures.splice(i, 1)[0];
      state.pictures.push(pic);
      save();
      return { code: 0 };
    },

    travel_gift_delete_album: (d) => {
      const id = Number(d && d.id);
      const i = state.giftBox.pictures.findIndex((p) => p.id === id);
      if (i === -1) return { code: 74 };   // 74 = 删除错误的照片id
      state.giftBox.pictures.splice(i, 1);
      save();
      return { code: 0 };
    },

    /* needResponse FALSE: the client marks its notes read itself and does not
       read the reply, so the payload only has to be accepted. */
    travel_read_note: (d) => {
      const ids = Array.isArray(d && d.id) ? d.id : [d && d.id];
      for (const raw of ids) {
        const n = state.notes.find((x) => x.id === Number(raw));
        if (n) n.read = 1;
      }
      save();
      return undefined;
    },

    /* The client shifts selectGiftList and shows a package view from reply.items
       (each {item_id, count}); an empty items list just closes that dialog. */
    item_select_gift: (d, ctx) => {
      const wanted = Array.isArray(d && d.index_list) ? d.index_list : [];
      const out = [];
      for (const raw of wanted) {
        const slot = state.selectGift[Number(raw)];
        if (!slot) continue;
        const before = getHaveItem(slot.item_id);
        addHouseItem(slot.item_id, slot.count);
        const after = getHaveItem(slot.item_id);
        pushItemUpdate(ctx, slot.item_id, after);
        // Report what was ACTUALLY credited, not what was asked for: the stack
        // cap (HaveItemMax 99) can swallow part of a grant, and the client shows
        // this number as the reward.
        out.push({ item_id: slot.item_id, count: Math.max(0, after - before) });
        delete state.selectGift[Number(raw)];
      }
      if (out.length) save();
      return { items: out };
    },

    /* `start` MUST be echoed: the client places each picture at start+n-1, so
       answering with a hard-coded 1 misplaces every page but the first. And the
       album renders from the model cache -- opening it does NOT request the list
       -- so boot has to deliver a populated album_load or the album stays empty
       forever. (Rendering additionally needs per-picture `layers`, which the
       client does not compose itself; see README.) */
    album_load: (d) => ({
      pictures: state.pictures.map(withLayers),
      total: state.pictures.length,
      start: Number((d && d.start) || 1),
    }),
    /* `total` is ignored by the client here -- it uses id_list.length. Note this
       id_list holds OBJECTS, whereas album_load_by_id_list's id_list is a plain
       array of numbers; same name, different shape. */
    album_load_all: () => ({
      id_list: state.pictures.map((p) => ({
        id: p.id, pic_id: p.pic_id, for_ads: 0, visit: 0,
      })),
    }),
    /* Push-only (the client never sends it). has_ads/is_share must be false or the
       client pops a WeChat share dialog, which is impossible offline.

       The client REBUILDS both of its pending lists from this payload:
         for pic in e.pictures: pic.for_ads ? newAdsPictureInfoList : newPictureInfoList
         for pic in e.visted_pic: pic.visit = true; newPictureInfoList.push(pic)
       so every entry must carry `for_ads` (we never set it: no ads) and pictures
       coming from a visit must arrive in `visted_pic` instead. */
    album_load_new: () => ({
      pictures: (state.albumPending || []).map((p) => Object.assign(withLayers(p), { for_ads: 0 })),
      visted_pic: (state.albumPendingVisit || []).map((p) => Object.assign(withLayers(p), { for_ads: 0 })),
      has_ads: false,
      is_share: false,
    }),

    /* ---------------- album management (契约逐条来自 main.min.js) -------------

       The client keeps FOUR picture buckets, and this is what each command feeds:
         pictureInfoList        the album               <- album_load / _all / _by_id_list
         newPictureInfoList     pending, not yet filed  <- album_load_new
         deletePictureInfoList  the recycle bin         <- album_load_recover
         newAdsPictureInfoList  ad-earned (we have none, so it stays empty)

       Codes that the client actually branches on:
         album_save_new : 0  = filed into the album (client moves it itself)
                          **75 = album full** -> the client DROPS the pending entry
         album_recover  : 0  = recovered
         album_delete   : 0  = deleted
       `album_delete_new` is fire-and-forget: the client removes the row locally
       BEFORE sending, so the server must not re-add it. */
    album_load_by_id_list: (d) => {
      const ids = Array.isArray(d && d.id_list) ? d.id_list : [];
      // NOTE: unlike album_load_all, THIS id_list is a plain array of numbers.
      //
      // And the REPLY is read as `pic_list`, not `pictures`:
      //     album_load_by_id_list = function (e) {
      //       if (e && e.pic_list) { group pic_list by id;
      //                              entry.layers = group.shift().layers }
      //       dispatch(updateAlbumContent) }
      // Sending `pictures` made that whole branch a no-op, so a card added by an album
      // command had no `layers` and rendered as an EMPTY/TRANSPARENT slot -- until the
      // next login, which fills the album page by page from album_load (that one does
      // carry layers). Same class of bug as the 百科 payload: right data, wrong key.
      const want = ids.map(Number);
      return {
        pic_list: state.pictures
          .filter((p) => want.indexOf(p.id) !== -1)
          .map(withLayers),
      };
    },

    album_load_recover: () => ({
      pictures: (state.albumDeleted || []).map(withLayers),
      total: (state.albumDeleted || []).length,
    }),

    album_delete: (d) => {
      const id = Number(d && d.id);
      const i = state.pictures.findIndex((p) => p.id === id);
      /* 74/75/76 are the album's own codes in errcode.json. Every one of these
         three callbacks is written `o && 0 == o.code && (...)` -- with -1
         getErrorInfo returns undefined and the WHOLE branch is skipped, so the
         row stayed on screen and the button "did nothing". */
      if (i === -1) return { code: 74 };   // 74 = 删除错误的照片id
      const pic = state.pictures.splice(i, 1)[0];
      if (!state.albumDeleted) state.albumDeleted = [];
      state.albumDeleted.push(pic);
      save();
      return { code: 0 };
    },

    album_recover: (d) => {
      const id = Number(d && d.id);
      const bin = state.albumDeleted || [];
      const i = bin.findIndex((p) => p.id === id);
      if (i === -1) return { code: 75 };   // 75 = 保存错误的新照片id
      if (state.pictures.length >= albumCapacity()) return { code: 101 };
      state.pictures.push(bin.splice(i, 1)[0]);
      save();
      return { code: 0 };
    },

    album_save_new: (d) => {
      const id = Number(d && d.id);
      const pend = state.albumPending || [];
      const i = pend.findIndex((p) => p.id === id);
      if (i === -1) return { code: 76 };   // 76 = 删除错误的新照片id
      if (state.pictures.length >= albumCapacity()) {
        // 75 is the code the client treats as "album full": it drops the pending
        // row WITHOUT filing it, so returning anything else would leave the row
        // stuck on screen forever.
        pend.splice(i, 1);
        save();
        return { code: 75 };
      }
      state.pictures.push(pend.splice(i, 1)[0]);
      save();
      return { code: 0 };
    },

    album_delete_new: (d) => {
      const id = Number(d && d.id);
      for (const key of ['albumPending', 'albumPendingVisit']) {
        const list = state[key] || [];
        const i = list.findIndex((p) => p.id === id);
        if (i !== -1) {
          list.splice(i, 1);
          save();
          break;
        }
      }
      // the client has already removed the row locally; there is no reply to read
      return undefined;
    },

    /* --- misc boot loads: well-formed empties --- */
    /* `furniture_load_*` handlers REPLACE the model object wholesale
       (furnitureData = e), and Utils.convertArrayAll only copies keys that are
       already present -- so every push must carry the FULL field set, or the
       client dereferences undefined and throws.

       Field sets below come from the furniture spec (each cited there):
         load_furniture : shop{start_time,leave_time,shop_list}, mood, bench_lock,
                          bench[10], put_fur, has_fur, mate_list, replace_fur
         load_flowerpot : show_list, list, plant_list   (all three required)
         load_compost   : show_index, replace_index, state, box_index, box_list[6]
         load_pocket    : show_index, replace_index, list, clover
         load_tumbler   : show_index, replace_index, tumbler_list
       Also: load_tumbler entries WITHOUT `layers` silently skip the whole draw
       branch -- it does not throw, it just draws nothing. */
    furniture_load_furniture: (d) => {
      // Offline schedule: present while stocked; repeatable goods restock tomorrow.
      // FROG_SHOP_HOURS optionally narrows the daily window.
      const now = nowSec();
      const shop = merchantShop();
      merchantStatusSeen = state.furniture.shopDay + '/' + (shop.start_time < now && now < shop.leave_time);
      return {
        shop,
        mood: 0,
        bench_lock: state.furniture.benchLock ? 1 : 0,
        bench: (state.furniture.bench || []).slice(0, 10),
        replace_fur: state.furniture.replaceFur || [],
        put_fur: state.furniture.placed || [],
        has_fur: state.furniture.owned || [],
        mate_list: craftMateList(),
        fur_list: [],
        tumbler_list: [],
      };
    },
    furniture_load_flowerpot: () => {
      refreshFlowerpot(nowSec());
      return {
        // show_list is the owned pots, keyed by type/id
        show_list: [{ type: 1, id: FLOWERPOT_ID }],
        list: [],
        plant_list: plantList(),
      };
    },

    /* Reply shape is EXACT: {item_list:[{item_id, num}]} -- the field must be
       named `num`, and there is NO code. Without item_list the client neither
       clears the slot nor runs its callback. `type`/`index` are 1-based. */
    furniture_flowerpot_harvest: (d, ctx) => {
      const index = Number(d && d.index);
      if (Number(d && d.type) !== 1 || !Number.isInteger(index)) return {};
      const slot = (state.flowerpot.slots || [])[index - 1];
      if (!slot || !slot.id) return {};
      if (slot.stage < 3) return {};            // only stage >= 3 is harvestable
      const grownPlant = slot.id;
      const produce = PLANT_HARVEST.get(Number(grownPlant));
      if (!produce) return {};                 // keep unknown plants intact
      const itemId = produce.id;
      const num = 1 + (Math.random() < 0.3 ? 1 : 0);
      // record the species so the 图鉴 (encyclopedia) fills up as you garden
      if (!state.flowerpot.grown) state.flowerpot.grown = [];
      if (state.flowerpot.grown.indexOf(grownPlant) === -1) {
        state.flowerpot.grown.push(grownPlant);
      }
      slot.id = 0;
      slot.stage = 0;
      slot.plantedAt = 0;
      addHouseItem(itemId, num);
      if (produce.type === 3 && state.handbook.specialtys.indexOf(itemId) === -1) {
        state.handbook.specialtys.push(itemId);
      }
      save();
      const count = getHaveItem(itemId);
      // addHouseItem is a stub client-side, so push the inventory too
      ctx.push('item_update', { item: { item_id: itemId, count } });
      ctx.push('item_load_handbook', handlers.item_load_handbook());
      // update_flowerpot() has NO event binding in the client (and
      // furniture_load_compost even dispatches the wrong event), so a full role
      // push is what actually redraws the pot.
      ctx.push('client_load_role', rolePayload());
      return { item_list: [{ item_id: itemId, num }] };
    },
    furniture_load_compost: () => ({
      show_index: state.furniture.compost.showIndex,
      replace_index: state.furniture.compost.replaceIndex,
      state: 0,
      box_index: state.furniture.compost.boxIndex,
      box_list: (state.furniture.compost.boxes || []).slice(0, 6),
      compost_list: state.furniture.compost.list || [],
    }),
    furniture_load_pocket: () => ({
      show_index: state.furniture.pocket.showIndex,
      replace_index: state.furniture.pocket.replaceIndex,
      list: [],
      clover: state.furniture.pocket.clover,
    }),
    furniture_load_tumbler: () => ({
      show_index: state.furniture.tumbler.showIndex,
      replace_index: state.furniture.tumbler.replaceIndex,
      tumbler_list: [],
    }),

    /* ================= furniture actions (contracts read from main.min.js) ====

       All of these are `code`-driven: the CLIENT mutates its own model on
       success and does NOT expect a state push, so the only job here is to
       validate, mutate the authoritative state, and answer with the right code.
       Getting the code WRONG is silent: the client just skips its model update,
       so the UI stops responding with no error anywhere.

         furniture_putin_bench / takeout_bench   code 0 = ok
         furniture_putin_box  / takeout_box      code 0 = ok
         furniture_replace_fur                   code 1 = now hidden, 0 = now shown
         furniture_replace_tumbler/compost/pocket code 1 = now hidden, 0 = now shown
         furniture_buy_shop                      code 0 = ok
         furniture_pocket_get                    code 0 = ok
    */

    /* bench: wire index 1..5 = tools (slots 0..4), 6..10 = items (slots 5..9);
       slot -1 = empty. The declared wire parameter is `pos` (the client calls
       send("furniture_putin_bench", cb, e+1, t)), which the handler used to read
       as `index` -- so placing anything on the bench always failed. The client
       updates its own `bench` array on code 0. */
    furniture_putin_bench: (d, ctx) => {
      /* 制作中工作台是锁的：客户端自己也挡（isLockBench() -> "咱们不许动"），
         服务端照样要拒，码用 errcode 表里真实存在的 6（非法操作）。 */
      if (state.furniture.benchLock) return { code: 6 };
      const slot = benchSlotFor(posOf(d));
      const id = Number(d && d.id);
      if (slot < 0) return { code: -1 };
      const it = ITEM_BY_ID.get(id);
      if (!it || getHaveItem(id) <= 0) return { code: -1 };
      const prev = state.furniture.bench[slot];
      if (prev > 0) addHouseItem(prev, 1);     // give the displaced one back
      addHouseItem(id, -1);                    // consume the one being placed
      state.furniture.bench[slot] = id;
      /* 图纸进台面之后：材料够就自动开工（原版也是服务端看着台面决定、再推 FurnitureFinish） */
      const started = maybeStartCraft();
      save();
      ctx.push('furniture_load_furniture', handlers.furniture_load_furniture({}));
      return started ? { code: 0, crafting: 1 } : { code: 0 };
    },

    furniture_takeout_bench: (d, ctx) => {
      if (state.furniture.benchLock) return { code: 6 };
      const slot = benchSlotFor(posOf(d));
      if (slot < 0) return { code: -1 };
      const id = state.furniture.bench[slot];
      if (id <= 0) return { code: -1 };
      state.furniture.bench[slot] = -1;
      addHouseItem(id, 1);
      save();
      ctx.push('furniture_load_furniture', handlers.furniture_load_furniture({}));
      return { code: 0 };
    },

    /* compost box: wire index is 1-BASED, but the slot value is 0 when empty
       (NOT -1 like the bench). Items are consumed from / returned to the house
       inventory exactly like the bench. Declared wire name is `pos`. */
    furniture_putin_box: (d) => {
      const index = posOf(d);
      if (!(index >= 1 && index <= 6)) return { code: -1 };
      const id = Number(d && d.id);
      if (!ITEM_BY_ID.has(id) || getHaveItem(id) <= 0) return { code: -1 };
      const prev = state.furniture.compost.boxes[index - 1];
      if (prev > 0) addHouseItem(prev, 1);
      addHouseItem(id, -1);
      state.furniture.compost.boxes[index - 1] = id;
      save();
      return { code: 0 };
    },

    furniture_takeout_box: (d) => {
      const index = posOf(d);
      if (!(index >= 1 && index <= 6)) return { code: -1 };
      const id = state.furniture.compost.boxes[index - 1];
      if (id <= 0) return { code: -1 };
      state.furniture.compost.boxes[index - 1] = 0;
      addHouseItem(id, 1);
      save();
      return { code: 0 };
    },

    /* The pocket stores clover and the CLIENT zeroes its own copy on success --
       it never touches the player's clover total, because addClover() is an
       empty stub. So the server must credit the clovers AND push clover_update,
       or the stored clover is destroyed on collection. */
    furniture_pocket_get: (d, ctx) => {
      const n = state.furniture.pocket.clover || 0;
      if (n > 0) {
        state.clover += n;
        state.furniture.pocket.clover = 0;
        save();
        ctx.push('clover_update', { clover: state.clover });
        ctx.push('furniture_load_pocket', handlers.furniture_load_pocket());
      }
      return { code: 0 };
    },

    /* replace_fur takes a FURNITURE id and answers with a code the client turns
       into "rotate this type out" (1) or "put this type in" (0). The client then
       rebuilds put_fur itself. */
    furniture_replace_fur: (d) => {
      const id = Number(d && d.id);
      const def = FURNITURE_BY_ID.get(id);
      if (!def) return { code: -1 };
      const type = Number(def.type);
      const showing = state.furniture.placed.find((p) => p.type === type);
      state.furniture.placed = state.furniture.placed.filter((p) => p.type !== type);
      if (showing && showing.id === id) {
        // was showing this exact one -> rotate the TYPE out
        state.furniture.replaceFur = state.furniture.replaceFur.filter((t) => t !== type);
        save();
        return { code: 1 };
      }
      state.furniture.placed.push({ type, id });
      if (state.furniture.replaceFur.indexOf(type) === -1) {
        state.furniture.replaceFur.push(type);
      }
      save();
      return { code: 0 };
    },

    /* tumbler / compost / pocket all share one shape: payload is index+1
       (1-based), code 1 = hide, code 0 = show, and the client sets BOTH
       show_index and replace_index from it. */
    furniture_replace_tumbler: (d) => finishReplace('tumbler', d),
    furniture_replace_compost: (d) => finishReplace('compost', d),
    furniture_replace_pocket: (d) => finishReplace('pocket', d),

    /* Payload is the SHOP id (FurnitureShopDB row), not the item id. The client
       deducts the clovers and adds the item locally, so the server has to do the
       real bookkeeping and push the authoritative clover count. `has_item` is the
       furniture id that must already be owned (the shop's unlock chain), and
       `limit` caps how many times a row may be bought. */
    furniture_buy_shop: (d, ctx) => {
      const shopId = shopIdOf(d);
      const row = FURNITURE_SHOP.get(shopId);
      if (!row) return { code: -1 };
      const bought = state.furniture.shopBought[shopId] || 0;
      const welfare = isWelfareRow(row);
      /* A welfare row's `limit` is 0 (= unrestricted for the client); the old
         `|| 1` made it a single, permanent purchase. Offer it once per day
         instead, tracked separately from the paid chain. */
      const shop = merchantShop();
      if (!(shop.start_time < nowSec() && nowSec() < shop.leave_time)) return { code: -1 };
      const boughtToday = state.furniture.shopDailyBought[shopId] || 0;
      const limit = Number(row.limit) || (welfare ? WELFARE_PER_DAY : Number(row.shop_limit) || 1);
      if (furnitureStock(row) <= 0) return { code: -1 };
      if (row.has_item && state.furniture.owned.indexOf(Number(row.has_item)) === -1) {
        return { code: -1 };
      }
      /* Welfare goods are NOT paid for -- see FURNITURE_TYPE_WELFARE. */
      const price = welfare ? 0 : (Number(row.price) || 0);
      if (state.clover < price) return { code: -1 };
      const itemId = Number(row.item_id);
      state.clover -= price;
      state.furniture.shopBought[shopId] = bought + 1;
      state.furniture.shopDailyBought[shopId] = boughtToday + 1;
      if (welfare) {
        if (!state.furniture.welfareTaken) state.furniture.welfareTaken = {};
        if (!state.furniture.welfareDay) state.furniture.welfareDay = {};
        state.furniture.welfareDay[shopId] = createDay();
        state.furniture.welfareTaken[shopId] = boughtToday + 1;
      }
      /* These rows sell PACKAGES too (item_id 5001/5002/5101 = 工具套装/材料套装/种子盲盒,
         see GIFT_DATA). A box is opened on the spot rather than handed over: the
         client has no way to ask us to open one, so an unopened box would be a dead
         item -- which is exactly what players reported. */
      const box = packageContents(itemId);
      if (box) {
        save();
        if (price > 0) ctx.push('clover_update', { clover: state.clover });
        grantItemOrPackage(ctx, itemId, 1);
        if (verbose) console.log(`[engine] shop row ${shopId} was a package (${itemId}); opened it`);
      } else {
        addHouseItem(itemId, 1);
        // a furniture piece is also "owned" so the shop chain and the replace UI
        // can see it
        if (FURNITURE_BY_ID.has(itemId) && state.furniture.owned.indexOf(itemId) === -1) {
          state.furniture.owned.push(itemId);
        }
        save();
        if (price > 0) ctx.push('clover_update', { clover: state.clover });
        pushItemUpdate(ctx, itemId, getHaveItem(itemId));
      }
      // 回忆彩蛋 type 4 (shop): param "drummer" is 嘟嘟, the merchant
      momentTrigger(4, 'drummer');
      ctx.push('furniture_load_furniture', handlers.furniture_load_furniture());
      if (verbose) {
        console.log(`[engine] furniture_buy_shop ${shopId} -> item ${itemId} `
          + `for ${price} clover (${bought + 1}/${limit})${welfare ? ' [welfare]' : ''}`);
      }
      return { code: 0 };
    },

    /* ---------------- 友情绘本 (guest_* / DrawingModel) ----------------------
       `guest_load_drawing` REPLACES the client model wholesale, so the payload
       must carry the FULL field set (see drawingPayload()).

       The state machine uses the client's own enum values:
         wait 0 / invite 1 / accept 2 / lock 3 / visit 4
       and BOTH accept and reject go through the SAME command, told apart only by
       the boolean payload -- so the server has to read it. */
    guest_load_drawing: () => drawingPayload(),

    /* The declared wire parameter is `is_accept`, and the client sends the BOOLEAN
       itself: request_accept_invit sends (..., true) and request_reject_invit
       sends (..., false). The handler used to read d.accept / d.id, neither of
       which is ever present, so `accepted` was always false -- meaning ACCEPTING
       an invitation was silently treated as REJECTING it (the drawing guest never
       arrived, and the roll timer was re-armed instead). */
    guest_accept_invit: (d, ctx) => {
      const flag = firstDefined(d, ['is_accept', 'accept']);
      const accepted = flag === undefined ? true : !!flag;
      const cur = state.drawing;
      if (accepted) {
        if (cur.state !== 1 || drawingGuestIds().indexOf(Number(cur.guest)) === -1) {
          return { code: -1 };                 // no invitation to accept
        }
        cur.state = 2;                       // DrawingState.accept
      } else {
        cur.state = 0;                       // DrawingState.wait
        cur.guest = -1;
        cur.bag = (cur.bag || []).map(() => -1);
        state.drawingNextRollAt = nowSec() + DRAWING_ROLL_SEC;
      }
      save();
      ctx.push('guest_load_drawing', drawingPayload());
      return { code: 0 };
    },

    /* Toggles accept<->lock. The client only sends this from `lockBag`
       (state==accept) or `unlockBag` (state==lock), so the current state decides
       the direction -- there is no flag on the wire. Starting the trip is what
       arms the return timer. */
    guest_lock_bag: (d, ctx) => {
      const cur = state.drawing;
      if (cur.state === 2) {
        cur.state = 3;                       // lock
        state.drawingReturnAt = nowSec() + DRAWING_TRIP_SEC;
      } else if (cur.state === 3) {
        cur.state = 2;                       // unlock
        state.drawingReturnAt = 0;
      } else {
        return { code: -1 };
      }
      save();
      ctx.push('guest_load_drawing', drawingPayload());
      return { code: 0 };
    },

    /* `pos` is 1-BASED on the wire (the client sends index+1). Items are consumed
       from / returned to the house inventory, exactly like the bench. */
    guest_putin_bag: (d, ctx) => {
      const pos = Number(d && d.pos);
      const id = Number(d && d.id);
      const bag = state.drawing.bag || [];
      if (!(pos >= 1 && pos <= bag.length)) return { code: -1 };
      if (state.drawing.state !== 2) return { code: -1 };   // only while packing
      if (!ITEM_BY_ID.has(id) || getHaveItem(id) <= 0) return { code: -1 };
      const prev = bag[pos - 1];
      if (prev > 0) addHouseItem(prev, 1);
      addHouseItem(id, -1);
      bag[pos - 1] = id;
      save();
      pushItemUpdate(ctx, id, getHaveItem(id));
      return { code: 0 };
    },

    guest_takeout_bag: (d, ctx) => {
      const pos = Number(d && d.pos);
      const bag = state.drawing.bag || [];
      if (!(pos >= 1 && pos <= bag.length)) return { code: -1 };
      const id = bag[pos - 1];
      if (id <= 0) return { code: -1 };
      bag[pos - 1] = -1;
      addHouseItem(id, 1);
      save();
      pushItemUpdate(ctx, id, getHaveItem(id));
      return { code: 0 };
    },

    guest_load: () => guestPayload(),

    /* ---------------- 抽奖 / 邻里美食交流 (lottery_*) ------------------------
       `lottery_load` only applies its payload `if (e.phase)`, so a falsy phase
       makes the client ignore everything -- including `state` -- silently. */
    lottery_load: () => lotteryPayload(),

    /* The client gates the whole reveal on BOTH keys existing:
         i.open_item && i.extra_item && (show reward view)
       so an answer missing either one does nothing at all. */
    lottery_open: (d, ctx) => {
      const L = state.lottery;
      if (!L.phase) startLotteryPhase();
      // the opening gift: a small clover purse, then the extra item
      const open = { item_id: GIFT_CLOVER_ID, count: randInt(2, 5) };
      const extraId = lotteryItemPool().length
        ? lotteryItemPool()[randInt(0, lotteryItemPool().length - 1)] : 0;
      const extra = extraId ? { item_id: extraId, count: 1 } : { item_id: 0, count: 0 };
      if (extraId) addHouseItem(extraId, 1);

      state.clover = Math.min(DEF('CloverMax', 999999), state.clover + open.count);
      L.state = LOTTERY_STATE.Select;
      L.extraItem = extra;
      L.answer = [];
      L.rightFlag = [];
      save();
      ctx.push('clover_update', { clover: state.clover });
      if (extraId) pushItemUpdate(ctx, extraId, getHaveItem(extraId));
      if (verbose) {
        console.log(`[engine] lottery_open -> ${open.count} clover, extra ${extraId}`);
      }
      return { open_item: open, extra_item: extra };
    },

    /* Payload is the player's pick list. The client reads only `code` here and
       then displays the settlement, so the score must be pushed as `right_flag`
       (per pick) for the client to tick the picks off. */
    lottery_select: (d, ctx) => {
      const L = state.lottery;
      const picks = Array.isArray(d && d.list) ? d.list.map(Number) : [];
      const want = L.want || [];
      L.answer = picks.slice();
      L.rightFlag = picks.map((id) => (want.indexOf(id) !== -1 ? 1 : 0));
      const score = L.rightFlag.reduce((a, b) => a + (b ? 1 : 0), 0);
      // settle_desc / extra_desc are both keyed 0..5, so the score is clamped there
      const maxScore = Math.max(0, Math.min(5, LOTTERY_PICKS));
      L.score = Math.max(0, Math.min(maxScore, score));
      L.state = LOTTERY_STATE.Complete;
      save();
      ctx.push('lottery_load', lotteryPayload());
      if (verbose) console.log(`[engine] lottery_select score=${L.score}`);
      return { code: 0 };
    },

    /* Collect: pay the reward for the finished round and go back to Open. */
    lottery_confirm_reward: (d, ctx) => {
      const L = state.lottery;
      const score = Number(L.score || 0);
      const reward = [];
      // a bigger score pays more; the amounts are OUR choice (the original table
      // for this lives on the dead server), the SHAPE is the client's
      const clover = score * 3;
      const ticket = score >= 4 ? 1 : 0;
      if (clover > 0) {
        state.clover = Math.min(DEF('CloverMax', 999999), state.clover + clover);
        ctx.push('clover_update', { clover: state.clover });
        reward.push({ item_id: GIFT_CLOVER_ID, count: clover });
      }
      if (ticket > 0) {
        state.ticket = Math.min(DEF('TicketMax', 999), state.ticket + ticket);
        ctx.push('item_update_ticket', { ticket: state.ticket });
        reward.push({ item_id: GIFT_TICKET_ID, count: ticket });
      }
      state.lottery = {
        lastPhase: L.phase || 0,
        phase: L.phase || 0,
        state: LOTTERY_STATE.Open,
        selectList: [],
        answer: [],
        extraItem: { item_id: 0, count: 0 },
        rightFlag: [],
        eggNum: 0,
        reward,
      };
      state.lotteryNextRollAt = nowSec() + LOTTERY_ROLL_SEC;
      save();
      ctx.push('lottery_load', lotteryPayload());
      if (verbose) console.log(`[engine] lottery_confirm_reward score=${score} -> ${clover} clover, ${ticket} ticket`);
      return { code: 0 };
    },

    /* guest_confirm / guest_serve / guest_finish / guest_set_expire_time are all
       needResponse:false -- the client acts locally and expects no reply, so the
       server must push any resulting state itself. */
    guest_confirm: (d, ctx) => {
      const g = state.guest;
      if (g && Number(d.id) === g.id) {
        g.confirmed = true;              // and every later push must keep saying so,
        save();                          // or the client re-raises the notice bar
        ctx.push('guest_load', guestPayload());
      }
      return undefined;
    },

    /* Serving only accepts a Specialty (type 3). The visit's `feeling` is a table
       lookup into Character.taste, which is what picks the NORMAL vs RARE reward
       weights -- that is the whole point of the taste vectors. */
    guest_serve: (d, ctx) => {
      const g = state.guest;
      if (!g) return undefined;
      /* The wire carries {id, item_id} (send("guest_serve", null, guestId, item)).
         Only one guest is present at a time, so `id` is redundant -- but ignoring
         it meant a stale request could feed whoever happens to be here now, so
         check it when the client supplies one. */
      const gid = Number(firstDefined(d, ['id']));
      if (gid && Number(g.id) !== gid) return undefined;
      const itemId = Number(firstDefined(d, ['item_id']));
      const it = ITEM_BY_ID.get(itemId);
      if (!it || it.type !== ITEM_TYPE_SPECIALTY) return undefined;
      if (getHaveItem(itemId) <= 0) return undefined;

      if (g.served) return undefined;          // never pay for the same visit twice
      addHouseItem(itemId, -1);
      const feeling = guestFeeling(g.id, itemId);
      const active = nowSec() - (g.startAt || nowSec());
      const gift = rollGuestGift(feeling, ctx, active);
      state.guestFeeds = (state.guestFeeds || 0) + 1;
      g.served = true;
      /* The visitor still LEAVES after being fed, but not instantly: the client runs
         `sendGuestServed(e); friendFeedBack(e);` back to back, and friendFeedBack reads
         `getGuestData().id` to look the friend up in the Character table
         (`data.find(e => e.id === id)`) -- with id already -1 that lookup returns
         undefined and `o.taste[a]` throws 「呱呱吃坏肚子了」. Against the networked
         server the clearing push simply arrived later; we keep them for a short
         farewell window so the same sequence stays valid. tickGuest clears them when
         expire_time passes. */
      g.expire_time = nowSec() + GUEST_FAREWELL_SEC;
      state.guestBonusTickets = 0;
      state.guestCoolUntil = nowSec() + GUEST_FAREWELL_SEC + GUEST_COOL_SEC;
      state.guestNextRollAt = 0;
      save();
      ctx.push('item_load_items', handlers.item_load_items());
      ctx.push('guest_load', guestPayload());
      if (verbose) {
        console.log(`[engine] guest ${g.id} served ${itemId} feeling=${feeling} `
          + `-> ${gift.got} (rare=${gift.rare})`);
      }
      return undefined;
    },

    guest_finish: (d, ctx) => {
      if (!state.guest) return undefined;
      state.guest = null;
      state.guestBonusTickets = 0;
      state.guestCoolUntil = nowSec() + GUEST_COOL_SEC;
      state.guestNextRollAt = 0;
      save();
      ctx.push('guest_load', guestPayload());
      return undefined;
    },

    /* The client only sends this while expire_time is still 0, so honour it once
       and otherwise keep the server's own schedule. */
    guest_set_expire_time: (d) => {
      const g = state.guest;
      if (g && !g.expire_time) {
        g.expire_time = Number(d.time) || (nowSec() + GUEST_STAY_SEC);
        save();
      }
      return undefined;
    },
    /* mail_load pushes an ARRAY, not {mails: []}: the client does
       revice_mails(Utils.convertArray(e)).
       The MAIL_MAX cap is enforced HERE as well as at the push site, so the
       invariant holds no matter which code path appended the mail. */
    mail_load: () => {
      trimMails();
      return state.mails;
    },
    /* `start` MUST be echoed -- the client writes mailInfoList[n + e.start - 1].
       This is request/response ONLY: the handler reads start/count off its SECOND
       argument, so pushing it would throw on undefined.start. */
    mail_load_mails: (d) => {
      const start = Number((d && d.start) || 1);
      const count = Number((d && d.count) || 5);
      return {
        mails: state.mails.slice(start - 1, start - 1 + count),
        total: state.mails.length,
        start,
      };
    },
    mail_open: (d, ctx) => { openMail(ctx, Number(d && d.id)); return undefined; },
    mail_read: (d, ctx) => {
      const m = state.mails.find((x) => x && x.id === Number(d && d.id));
      if (m) { m.read = true; save(); ctx.push('mail_load', state.mails); }
      return undefined;
    },
    // the SDK bridge sends this; the handler is empty, so an empty object is right
    mail_ejoy_active_code: () => ({}),
    /* task_load: `tasks` carries each task's claimed flag and `list` the progress.
       `pro` only moves for the mappings we can justify (see taskProgress); the
       rest stay at 0 rather than inventing progress. */
    task_load: () => {
      const rows = taskRows();
      return {
        /* `pro` is what the client's updateRedot compares against task_list[id].count
           (`0 == r.is_reward && r.pro >= l.count`), so without it the task red dots
           and progress bars never light up. */
        tasks: rows.map((r) => ({ id: r.id, is_reward: r.is_reward, pro: r._pro })),
        // NOTE: list_map ids, NOT task ids -- see the comment on LIST_MAP.
        list: listRows(),
      };
    },

    task_load_list: () => ({ reward: listClaimRows() }),

    /* One tier of a cumulative plan (是日清单 / 当周计划 / …). `id` is the client's
       own encoding: 100 * type + (tier 1-based). Paying is gated on the plan's own
       progress. A duplicate request resynchronizes the UI without a reward popup. */
    task_get_list_reward: (d, ctx) => {
      const id = Number(firstDefined(d, ['id']));
      if (!Number.isFinite(id) || id <= 0) return { code: -1 };
      const type = Math.floor(id / 100);
      const tier = id % 100;
      const plan = LIST_TYPE[String(type)];
      if (!plan || tier < 1) return { code: -1 };
      const target = Number((plan.target || [])[tier - 1]);
      const rewardId = Number((plan.reward || [])[tier - 1]);
      if (!Number.isFinite(target) || !Number.isFinite(rewardId)) return { code: -1 };
      if (claimedTiers(type) >= tier) {
        ctx.push('task_load_list', handlers.task_load_list());
        return { code: 1 };                                    // already paid
      }
      if (listTypeProgress(type) < target) return { code: -1 };    // not earned yet
      const m = state.taskTiers || (state.taskTiers = {});
      m[String(type)] = Math.max(Number(m[String(type)]) || 0, tier);
      grantItem(ctx, rewardId, Number((plan.reward_num || [])[tier - 1]) || 1);
      save();
      ctx.push('task_load', handlers.task_load());
      ctx.push('task_load_list', handlers.task_load_list());
      if (verbose) console.log(`[engine] task plan ${type} tier ${tier} -> item ${rewardId}`);
      return { code: 0 };
    },

    /* Pays task_list[id].num copies of task_list[id].reward_id -- real table data.
       Gated on progress, so it cannot be farmed. is_reward flips so the client's
       red dot can clear, and the rows are re-pushed. */
    task_get_reward: (d, ctx) => {
      const id = Number(d && d.id);
      const t = TASKS[String(id)];
      if (!t) return { code: -1 };
      if ((state.tasksClaimed || []).indexOf(id) !== -1) return { code: 0 };
      if (taskProgress(t) < (Number(t.count) || 0)) return { code: -1 };
      state.tasksClaimed.push(id);
      grantItem(ctx, Number(t.reward_id), Number(t.num) || 1);
      save();
      ctx.push('task_load', handlers.task_load());
      return { code: 0 };
    },
    // season group names that exist in default.res.json are season11..season44,
    // so season/hours_type must both stay within 1..4 (key = season + "" + hours_type)
    weather_load: () => weatherPayload(),
    /* 串门访客. `visit_load` was a `() => ({})` stub before, and the client's
       handler is `e.visitor && (...)` / `e.acquire && (...)`, so an empty object
       meant NO VISITOR EVER APPEARED and the province collection stayed empty. */
    visit_load: () => visitorPayload(),

    /* needResponse FALSE: the client fires this, then does its own local update
       and never reads a reply. So the reward MUST be pushed from here.
       The client branches on `first`:
         first  -> pushes this province into its own acquireList (the flower)
         else   -> addClover(gift.count) for item 100000,
                   addTicket(gift.count) for item 100001
       and addClover / addTicket are BOTH EMPTY STUBS in the client, so without
       the push the visitor's present would be silently lost. */
    visit_open: (d, ctx) => {
      const v = state.visitor;
      if (!v) return undefined;
      if (v.first) {
        if (!state.acquireProvinces) state.acquireProvinces = [];
        if (state.acquireProvinces.indexOf(v.province) === -1) {
          state.acquireProvinces.push(v.province);
        }
      } else {
        const id = Number(v.gift && v.gift.item_id);
        const n = Number((v.gift && v.gift.count) || 0);
        if (n > 0) {
          if (id === GIFT_TICKET_ID) {
            const cap = DEF('TicketMax', 999);
            state.ticket = Math.min(cap, state.ticket + n);
            ctx.push('item_update_ticket', { ticket: state.ticket });
          } else if (id === GIFT_CLOVER_ID) {
            const cap = DEF('CloverMax', 999999);
            state.clover = Math.min(cap, state.clover + n);
            ctx.push('clover_update', { clover: state.clover });
          }
        }
      }
      state.visitor = null;
      state.visitorCoolUntil = nowSec() + VISITOR_COOL_SEC;
      state.visitorNextRollAt = 0;
      save();
      ctx.push('visit_load', visitorPayload());
      return undefined;
    },

    /* needResponse false. The client rolls a random carpet 1..8 itself when the
       loaded one is <= 0 and reports it here, so this is a plain record. */
    visit_set_carpet: (d) => {
      const v = state.visitor;
      if (v) {
        const id = Number(d && d.id);
        if (id >= 1) { v.carpet = id; save(); }
      }
      return undefined;
    },

    visit_set_expire_time: (d) => {
      const v = state.visitor;
      if (v && !v.expire_time) {
        v.expire_time = Number(d && d.time) || (nowSec() + VISITOR_STAY_SEC);
        save();
      }
      return undefined;
    },
    client_load_events: () => {
      const q = Array.isArray(state.pendingEvents) ? state.pendingEvents : [];
      state.pendingEvents = [];
      return q;
    },
    client_notice: () => ({}),
    client_load_publicity: () => ({ id_list: [] }),
    // story_load USED TO BE HERE as `() => ({ stories: [], new_story_id: 0 })`.
    // Correct shape, but it meant no story ever appeared; the real one is below.
    encyclopedia_load: () => encyclopediaPayload(),

    /* The reply here is ignored by the client (its callback is null), so this only
       records which variety the player is looking at. */
    encyclopedia_set_show_sub: (d) => {
      if (d && d.long_id != null) {
        state.encyclopediaShow = Number(d.long_id);
        save();
      }
      return undefined;
    },
    /* NOTE: `lottery_load` used to sit here as `() => ({})`. A duplicate handler
       key is NOT an error in JS -- the LAST one silently wins -- so that stub
       was shadowing the real implementation defined above and the whole lottery
       looked unimplemented. There is now a unit test that rejects duplicate
       handler keys outright. */
    rank_load: () => ({ info: [], me: null }),
    rank_get_intro: () => ({}),
    /* ---------------- 新手引导 (tutorial_*) ---------------------------------

       This was a real STALL BUG for a brand-new save. The client's guide does:

         case GuideStep.GetAward:
           show(new GuideAwardView(function () {
             send("tutorial_step_open_door");                 // fire-and-forget
             send("tutorial_step_open_door_q", function (i) {
               if (i.ok) {
                 send("tutorial_step_ask_award");             // fire-and-forget
                 send("tutorial_step_ask_award_q", function (i) {
                   if (i.ok) setClientSettings("guideStep", getNextGuideStep(t));
                   else checkGuide();                          // re-enter, forever
                 });
               } else checkGuide();
             });
           }));

       -- i.e. the guide ADVANCES ONLY IF the server answers `{ok: true}` to BOTH
       `_q` queries. With no handler at all the reply was `{}`, `i.ok` was
       undefined, the step never advanced and `checkGuide()` re-entered the award
       view indefinitely. A fresh player could not finish the tutorial.

       The two non-`_q` commands are needResponse:false notifications. */
    tutorial_step_open_door: () => {
      const g = state.guide || (state.guide = { doorOpened: false, awardGiven: false, steps: [] });
      g.doorOpened = true;
      if (g.steps.indexOf('open_door') === -1) g.steps.push('open_door');
      save();
      return undefined;                 // needResponse:false
    },

    tutorial_step_open_door_q: () => {
      const g = state.guide || (state.guide = { doorOpened: false, awardGiven: false, steps: [] });
      g.doorOpened = true;
      if (g.steps.indexOf('open_door_q') === -1) g.steps.push('open_door_q');
      save();
      return { ok: true };              // `i.ok` is what advances the guide
    },

    /* The starter award. GuideAwardView renders three lines of copy and NO item
       list -- and its copy is still the untranslated keys ("新手指引完成，领取
       奖励描述1/2/3") -- so the award contents were entirely server-side and are
       not recoverable from the client. This set is OUR choice, labelled as such:
       it is granted exactly once, and pushed, because addClover/addHouseItem are
       empty stubs on the client. */
    tutorial_step_ask_award: (d, ctx) => {
      const g = state.guide || (state.guide = { doorOpened: false, awardGiven: false, steps: [] });
      if (!g.awardGiven) {
        g.awardGiven = true;
        g.steps.push('ask_award');
        const clover = 200;
        state.clover = Math.min(DEF('CloverMax', 999999), state.clover + clover);
        ctx.push('clover_update', { clover: state.clover });
        const ticket = 1;
        state.ticket = Math.min(DEF('TicketMax', 999), state.ticket + ticket);
        ctx.push('item_update_ticket', { ticket: state.ticket });
        save();
        if (verbose) console.log(`[engine] tutorial award: +${clover} clover, +${ticket} ticket`);
      } else {
        save();
      }
      return undefined;                 // needResponse:false
    },

    tutorial_step_ask_award_q: () => {
      const g = state.guide || (state.guide = { doorOpened: false, awardGiven: false, steps: [] });
      if (g.steps.indexOf('ask_award_q') === -1) g.steps.push('ask_award_q');
      save();
      return { ok: true };              // `i.ok` is what advances the guide
    },

    /* 料理. `cooking_load_cooking` assigns the whole serverData, so every field
       must be sent; a task row is {id, pro, complete}. */
    cooking_load_cooking: () => {
      const C = refreshCooking();
      save();
      return {
        month: C.month,
        month_pro: C.monthPro || 0,
        week: C.week || 0,
        complete: !!C.complete,
        select: C.select || 1,
        refresh_time: C.refreshTime || 0,
        task_list: (C.taskList || []).map((t) => ({
          id: t.id, pro: t.pro || 0, complete: !!t.complete,
        })),
      };
    },

    /* Payload is the theme index. The client sets its own `select` on code 0. */
    cooking_select: (d, ctx) => {
      const C = refreshCooking();
      const sel = Number(d && d.index);
      if (!(sel >= 1)) return { code: -1 };
      if (sel === Number(C.select)) return { code: 0 };
      C.select = sel;
      cookingDealTasks();          // a new theme means a new month and a new set
      save();
      ctx.push('cooking_load_cooking', handlers.cooking_load_cooking());
      return { code: 0 };
    },

    /* Payload is the task id; the client marks it complete and bumps month_pro
       itself on code 0. Only a task whose progress reached the table's `state`
       may be claimed -- otherwise the client's red dot and ours would disagree. */
    cooking_complete_task: (d) => {
      const C = refreshCooking();
      const id = Number(d && d.id);
      const row = (C.taskList || []).find((t) => Number(t.id) === id);
      if (!row || row.complete) return { code: -1 };
      const def = COOKING_TASKS[String(id)];
      if (!def || Number(row.pro || 0) < Number(def.state)) return { code: -1 };
      row.complete = true;
      C.monthPro = (C.monthPro || 0) + 1;
      /* 鼓舞 (museumday): the client's own explainer says 「每吃8个饼干就会积攒1次鼓舞」
         (museumDayCommon.inspire.v1 = 8), so completing a dish is what fills the
         counter. Without this the 鼓舞 button could only ever show its "0 次鼓舞"
         explainer -- functional, but a feature nobody could ever use. */
      const s = ensureMuseumday();
      s.cookies = (s.cookies | 0) + 1;
      if (s.cookies >= MD_INSPIRE_PER) {
        s.cookies -= MD_INSPIRE_PER;
        s.inspireNum = (s.inspireNum | 0) + 1;
      }
      save();
      return { code: 0 };
    },

    /* Payload is the task id; the reply REPLACES that row in the client's list. */
    cooking_refresh_task: (d) => {
      const C = refreshCooking();
      const id = Number(d && d.id);
      const i = (C.taskList || []).findIndex((t) => Number(t.id) === id);
      if (i === -1) return { task: null };
      const used = (C.taskList || []).map((t) => Number(t.id));
      const alt = cookingTaskRows().find((r) => used.indexOf(Number(r.id)) === -1);
      const next = alt
        ? { id: Number(alt.id), pro: 0, complete: false }
        : { id, pro: 0, complete: false };
      C.taskList[i] = next;
      save();
      return { task: { id: next.id, pro: next.pro, complete: next.complete } };
    },

    /* The finish line: every dealt task must be complete. The dish item comes
       from cookingData[month].item_id, which is the table's own value. */
    cooking_start_cooking: (d, ctx) => {
      const C = refreshCooking();
      if (C.complete) return { code: -1 };
      const list = C.taskList || [];
      if (!list.length || list.some((t) => !t.complete)) return { code: -1 };
      const dish = cookingDish(C.month, C.select);
      if (!dish) return { code: -1 };
      const itemId = Number(dish.item_id);
      C.complete = true;
      save();
      if (ITEM_BY_ID.has(itemId)) {
        addHouseItem(itemId, 1);
        pushItemUpdate(ctx, itemId, getHaveItem(itemId));
      }
      if (verbose) {
        console.log(`[engine] cooking done month=${C.month} -> item ${itemId} (${dish.title})`);
      }
      return { code: 0 };
    },

    /* 观看广告 / 分享: a pure-local build has neither, so both are REFUSED
       explicitly instead of pretending. Task types 2 and 8 are consequently
       never dealt (see COOKING_BLOCKED_TYPES), so nothing is left stuck. */
    cooking_look_ad: () => ({ code: -1 }),
    cooking_share: () => ({ code: -1 }),

    /* 扭蛋活动. `capsule_load` replaces the client model AND is the only thing
       that arms the activity, and only `if (isOpen())` -- i.e. while
       `now < end_time`. So end_time = 0 silently disables the whole event. */
    capsule_load: () => {
      const C = refreshCapsule(nowSec());
      if (!(C.taskList || []).length && (C.patchNum || 0) > 0) capsulePatch();
      save();
      return capsulePayload();
    },

    /* NO payload: the server draws. `reward_id > 0` is the only signal the client
       reads; it then does coin-- and reward_list.push itself, so the ITEM has to
       be granted and pushed here. */
    capsule_twist: (d, ctx) => {
      const C = refreshCapsule(nowSec());
      if ((C.coin || 0) <= 0) return { reward_id: 0 };
      const pool = Object.keys(CAPSULE_REWARD)
        .map((k) => Number(CAPSULE_REWARD[k].reward_id))
        .filter((n) => Number.isFinite(n));
      if (!pool.length) return { reward_id: 0 };
      const rid = pool[randInt(0, pool.length - 1)];
      const row = CAPSULE_REWARD[String(rid)];
      C.coin -= 1;
      if (!C.rewardList) C.rewardList = [];
      C.rewardList.push(rid);
      const itemId = Number(row.id);
      const n = Number(row.num) || 1;
      if (itemId === GIFT_TICKET_ID || (ITEM_BY_ID.get(itemId) || {}).type === 14) {
        // type-14 items are currencies the client folds into counters, and it
        // never grants them itself
        if (itemId === GIFT_TICKET_ID || itemId === 200001) {
          state.ticket = Math.min(DEF('TicketMax', 999), state.ticket + n);
          ctx.push('item_update_ticket', { ticket: state.ticket });
        } else {
          state.clover = Math.min(DEF('CloverMax', 999999), state.clover + n);
          ctx.push('clover_update', { clover: state.clover });
        }
      } else if (ITEM_BY_ID.has(itemId)) {
        addHouseItem(itemId, n);
        pushItemUpdate(ctx, itemId, getHaveItem(itemId));
      }
      const bonuses = capsuleThresholdBonuses(ctx);
      save();
      ctx.push('capsule_load_coin', { coin: C.coin, pre_coin: C.preCoin || 0 });
      if (verbose) {
        console.log(`[engine] capsule_twist -> reward ${rid} (item ${itemId} x${n})`
          + (bonuses.length ? ` bonuses ${JSON.stringify(bonuses)}` : ''));
      }
      return { reward_id: rid };
    },

    /* NO payload. Deals tasks into the free slots. The reply is the full task
       list -- which is also exactly the NEWLY dealt rows, because the client
       only ever calls this when its own list is empty
       (`if (0 == task_list.length && patch_num > 0) req_patch()`), and it does
       `patch_num -= reply.task_list.length`, so returning the whole list on a
       later patch would drive patch_num negative. */
    capsule_patch: () => {
      refreshCapsule(nowSec());
      const dealt = capsulePatch();
      save();
      // IDS, not rows: the client assigns this straight to data.task_list and then
      // looks each entry up in capsuleData by `entry.toString()`.
      return { task_list: dealt.map((t) => Number(t.id)) };
    },

    /* `index` is 1-BASED (the client sends index+1) and addresses the DISPLAYED
       list, which excludes finished tasks. Finishing early costs `fast_consume`
       coins -- the value is the table's own. */
    capsule_fast_task: (d, ctx) => {
      const C = refreshCapsule(nowSec());
      const idx = Number(d && d.index);
      const slot = capsuleOpenTasks()[idx - 1];
      if (!slot) return { code: -1 };
      if (slot.complete) return { code: -1 };
      if ((C.coin || 0) < CAPSULE_FAST_COST) return { code: -1 };
      C.coin -= CAPSULE_FAST_COST;
      slot.complete = true;
      save();
      ctx.push('capsule_load_coin', { coin: C.coin, pre_coin: C.preCoin || 0 });
      ctx.push('capsule_load_task', { task_list: capsulePayload().task_list });
      return { code: 0 };
    },

    /* NO payload. Moves the pending `pre_coin` into the spendable `coin`, which
       the client mirrors on code 0. */
    capsule_get_coin: (d, ctx) => {
      const C = refreshCapsule(nowSec());
      C.coin = (C.coin || 0) + (C.preCoin || 0);
      C.preCoin = 0;
      save();
      ctx.push('capsule_load_coin', { coin: C.coin, pre_coin: C.preCoin });
      return { code: 0 };
    },

    /* 庭院装饰. Payload is {has_list, put_id, status}; the client's handler is
       `this.decorationList = convertArray(e.has_list)` plus the other two. */
    client_load_decorate: () => ({
      has_list: (state.decoration.hasList || []).map((d) => ({ id: d.id, num: d.num })),
      put_id: state.decoration.putId || 0,
      status: state.decoration.status || 0,
    }),

    /* Payload is the decoration id to put on display. The client mirrors the
       server exactly on success:
         * one unit of the PREVIOUSLY displayed entry is consumed (the old flower
           is used up), and the entry is dropped when it hits 0,
         * put_id becomes the new id,
         * status becomes 1 (blooming -- `pic[0]` is 花苞, `pic[1]` is 花朵).
       NOTE: the newly placed one is NOT decremented by the client, so neither do
       we -- mirroring the client is what keeps the two in sync. */
    client_change_decorate: (d) => {
      const id = Number(d && d.id);
      if (!DECORATIONS[String(id)]) return { code: -1 };
      const D = state.decoration;
      const have = (D.hasList || []).find((x) => x.id === id);
      if (!have || have.num <= 0) return { code: -1 };
      const prev = (D.hasList || []).find((x) => x.id === D.putId);
      if (prev && D.putId && D.putId !== id) {
        prev.num -= 1;
        if (prev.num <= 0) {
          D.hasList = D.hasList.filter((x) => x !== prev);
        }
      }
      D.putId = id;
      D.status = 1;
      save();
      return { code: 0 };
    },

    /* 许愿池. This used to be `() => ({end_time: 0})`, and the client's
       `isOpen()` is `now < end_time` -- so the pool was permanently closed and
       the wish button could never be used. */
    wishingpool_load: () => {
      const W = refreshWishingPool(nowSec());
      save();
      return {
        end_time: W.endTime,
        coin: W.coin,
        items: W.items.map((i) => ({ id: i.id, num: i.num, limit: i.limit })),
      };
    },

    /* NO payload: the server draws. The client reads only `id` -- and only acts
       when `id > 0` -- then decrements its own coin and that entry's `limit`, and
       renders `[{item_id: o.id, count: o.num}]`. So the item has to be credited
       HERE (addHouseItem is pushed, not called by the client). */
    wishingpool_wish: (d, ctx) => {
      const W = refreshWishingPool(nowSec());
      const avail = W.items.filter((i) => i.limit > 0);
      if (!avail.length || (W.coin || 0) <= 0) {
        save();
        return { id: 0 };          // 0 means "nothing happened" to the client
      }
      W.coin -= 1;
      W.wishes = (W.wishes || 0) + 1;      // 许愿池自己的计数（年度总结的 wish_num 读的是手工祈愿物，不是这个）
      const pick = avail[randInt(0, avail.length - 1)];
      pick.limit -= 1;
      addHouseItem(pick.id, pick.num);
      save();
      pushItemUpdate(ctx, pick.id, getHaveItem(pick.id));
      if (verbose) {
        console.log(`[engine] wishingpool_wish -> item ${pick.id} x${pick.num} `
          + `(coin left ${W.coin}, limit left ${pick.limit})`);
      }
      return { id: pick.id };
    },

    /* calendar_load: `task_list` MUST be exactly three entries -- the client
       hardcodes three rows of copy (watch an ad / share, 累计30三叶草, 商店抽奖兑换).
       `new_flag` is indexed by createDay-1, and the client sets
       new_flag[N-1] = 1 after a successful claim, so 1 means CLAIMED. */
    calendar_load: () => {
      ensureCalendarMonth();
      const day = createDay();
      const flags = [];
      for (let i = 0; i < day; i++) {
        flags.push(state.calendar.claimedBeginner.indexOf(i + 1) !== -1 ? 1 : 0);
      }
      return {
        new_flag: flags,
        task_list: state.calendar.taskList.slice(0, 3),
        lucky_days: state.calendar.lucky,
        st_days: state.calendar.st,
      };
    },

    /* The newcomer reward comes straight from calendarData.beginner (7 days, real
       item ids and note ids). The client sends no day, so the server decides from
       createDay and answers {day: N}. */
    calendar_get_beginer_reward: (d, ctx) => {
      const day = Math.min(createDay(), 7);
      const table = (gamedata.tables.calendarData || {}).beginner || {};
      const row = table[String(day)];
      if (row && state.calendar.claimedBeginner.indexOf(day) === -1) {
        state.calendar.claimedBeginner.push(day);
        const itemId = Number(row.item_id);
        const count = addHouseItem(itemId, Number(row.num) || 1);
        pushItemUpdate(ctx, itemId, count);
        save();
      }
      return { day };
    },

    calendar_get_code_reward: (d, ctx) => {
      const day = Number(d && d.day);
      const table = (gamedata.tables.calendarData || {}).beginner || {};
      const row = table[String(day)];
      if (row && state.calendar.claimedBeginner.indexOf(day) === -1) {
        state.calendar.claimedBeginner.push(day);
        const itemId = Number(row.item_id);
        const count = addHouseItem(itemId, Number(row.num) || 1);
        pushItemUpdate(ctx, itemId, count);
        save();
      }
      return { day };
    },

    /* These two take NO parameters at all -- verified against the client's own
       send sites -- so the server has to judge by its own idea of today. */
    calendar_get_st_reward: (d, ctx) => {
      ensureCalendarMonth();
      const today = curDayOfMonth();
      if (!state.calendar.st.some((e) => e.day === today)) return { code: -1 };
      if (state.calendar.claimedSt.indexOf(today) !== -1) return { code: 0 };
      state.calendar.claimedSt.push(today);
      state.clover += CALENDAR_ST_CLOVER;
      save();
      ctx.push('clover_update', { clover: state.clover });
      return { code: 0 };
    },

    calendar_get_luck_reward: (d, ctx) => {
      ensureCalendarMonth();
      const today = curDayOfMonth();
      if (!state.calendar.lucky.some((e) => e.day === today)) return { code: -1 };
      if (state.calendar.claimedLucky.indexOf(today) !== -1) return { code: 0 };
      state.calendar.claimedLucky.push(today);
      state.ticket += CALENDAR_LUCKY_TICKETS;
      save();
      ctx.push('item_update_ticket', { ticket: state.ticket });
      return { code: 0 };
    },

    /* Indexed by day-1; the values are calendarData.note keys (the newcomer tips). */
    calendar_load_note: () => {
      const day = createDay();
      const table = (gamedata.tables.calendarData || {}).beginner || {};
      const list = [];
      for (let i = 0; i < day; i++) {
        const row = table[String(i + 1)];
        list.push(row ? row.note_id : 0);
      }
      return { list };
    },

    calendar_task_update: (d, ctx) => {
      /* The client sends this with NO parameters (`calendar_task_update:[[],!0]`) and
         reads the reply as `e.task`, then does `data.task_list[e.task.id-1] = e.task`.
         We used to read `d.task` -- which never arrives -- and answer undefined, so the
         whole call was a no-op. Answer with the task row that is in progress. */
      const t = d && d.task;
      if (t && t.id != null) {
        const i = Number(t.id) - 1;
        if (i >= 0 && i < state.calendar.taskList.length) {
          state.calendar.taskList[i] = {
            id: Number(t.id),
            pro: Number(t.pro) || 0,
            complete: Number(t.complete) || 0,
          };
          save();
        }
      }
      const rows = state.calendar.taskList || [];
      const next = rows.find((x) => x && !x.complete) || rows[0];
      if (!next) return undefined;
      return {
        task: { id: Number(next.id), pro: Number(next.pro) || 0, complete: Number(next.complete) || 0 },
      };
    },

    /* ---------------- 动态照片 (animpicture_*) -------------------------------

       `animpicture_load` REPLACES the whole model (convertArrayAll, and each
       pic_list entry's `pictures` is convertArray-ed), so every field must be
       sent. The other eight mirror into the client's own data on code 0 -- and
       the client's arithmetic is exact, so the server has to do the SAME thing:

         use_item      : `if (e.phase >= 0)` is a GATE. `phase` MUST be present
                         and >= 0 or the whole command silently does nothing.
                         On phase 0 the page is finished: item_num++ and every
                         `exp_pic` goes back to the album.
         open_album(i) : put_num++ and an empty PictureInfo appended
         select_pic(id): album picture -> a new page (only the 3 pic_map ids
                         qualify); phase = (phase_list.length == 1 ? 0 : 1)
         *_add_pic     : album picture -> that slot
         *_remove_pic  : slot -> album (when the flag is falsey)
         guide/get_item: guide++ / item_num = 0 */
    animpicture_load: () => animPayload(),

    animpicture_guide: (d, ctx) => {
      const A = state.animPicture;
      A.guide = (A.guide || 0) + 1;
      save();
      ctx.push('animpicture_load', animPayload());
      return { code: 0 };
    },

    /* The client sets `item_num = 0` itself; the page it just finished is
       recorded server-side so the count is right after a reload. */
    animpicture_get_item: (d, ctx) => {
      const A = state.animPicture;
      if (A.itemNum > 0) {
        A.collected = (A.collected || 0) + A.itemNum;
        A.itemNum = 0;
        save();
        ctx.push('animpicture_load', animPayload());
      }
      return { code: 0 };
    },

    /* Payload is an ALBUM picture id. Only ids present in animpictureData's
       pic_map can become a moving photo (there are just three). */
    animpicture_select_pic: (d, ctx) => {
      const A = state.animPicture;
      const picId = Number(d && d.id);
      const i = (state.pictures || []).findIndex((p) => p.id === picId);
      if (i === -1) return { code: -1 };
      const slot = ANIM_PIC_MAP[String(state.pictures[i].pic_id)];
      if (slot === undefined) return { code: -1 };
      const pic = state.pictures.splice(i, 1)[0];
      A.phase = animStartPhase(slot);
      A.exp = 0;
      A.picList.push({ id: Number(slot), putNum: 0, pictures: [] });
      A.lastPic = pic;                 // kept so a removal can return it
      save();
      ctx.push('animpicture_load', animPayload());
      return { code: 0 };
    },

    /* index is 1-BASED on the wire. */
    animpicture_open_album: (d, ctx) => {
      const A = state.animPicture;
      const idx = Number(d && d.index);
      const page = (A.picList || [])[idx - 1];
      if (!page) return { code: -1 };
      if ((page.putNum || 0) >= animPhaseCount(page.id)) return { code: -1 };
      page.putNum = (page.putNum || 0) + 1;
      page.pictures.push({ id: 0, pic_id: 0, layers: [] });
      save();
      ctx.push('animpicture_load', animPayload());
      return { code: 0 };
    },

    /* Declared wire params are (anim_index, pic_index, pic_uid) and the client
       calls send("animpicture_album_add_pic", cb, e+1, t+1, uid) -- page index and
       slot both 1-based, plus the picture's uid. The handler read index/slot/id,
       none of which exist on the wire, so putting a photo into a moving-photo page
       always failed with code -1. */
    animpicture_album_add_pic: (d, ctx) => {
      const A = state.animPicture;
      const animIndex = Number(firstDefined(d, ['anim_index', 'index']));
      const picIndex = Number(firstDefined(d, ['pic_index', 'slot']));
      const picId = Number(firstDefined(d, ['pic_uid', 'id']));
      const page = (A.picList || [])[animIndex - 1];
      const slot = picIndex - 1;
      if (!page || !(slot >= 0)) return { code: -1 };
      const i = (state.pictures || []).findIndex((p) => p.id === picId);
      if (i === -1) return { code: -1 };
      const pic = state.pictures.splice(i, 1)[0];
      while (page.pictures.length <= slot) page.pictures.push({ id: 0, pic_id: 0, layers: [] });
      page.pictures[slot] = pic;
      save();
      ctx.push('animpicture_load', animPayload());
      return { code: 0 };
    },

    /* Declared params (anim_index, pic_index, is_delete). The client returns the
       picture to the album only when that flag is falsey. */
    animpicture_album_remove_pic: (d, ctx) => {
      const A = state.animPicture;
      const animIndex = Number(firstDefined(d, ['anim_index', 'index']));
      const picIndex = Number(firstDefined(d, ['pic_index', 'slot']));
      const page = (A.picList || [])[animIndex - 1];
      const slot = picIndex - 1;
      if (!page || !page.pictures[slot]) return { code: -1 };
      const pic = page.pictures[slot];
      const keep = !!firstDefined(d, ['is_delete', 'flag']);
      if (!keep && pic && pic.id) state.pictures.push(pic);
      page.pictures[slot] = { id: 0, pic_id: 0, layers: [] };
      save();
      ctx.push('animpicture_load', animPayload());
      return { code: 0 };
    },

    /* Removes a WHOLE page; the declared flag is `is_delete`, and a falsey value
       returns its photos to the album. */
    animpicture_remove_pic: (d, ctx) => {
      const A = state.animPicture;
      const idx = Number(firstDefined(d, ['index']));
      const page = (A.picList || [])[idx - 1];
      if (!page) return { code: -1 };
      const keep = !!firstDefined(d, ['is_delete', 'flag']);
      if (!keep) {
        for (const pic of page.pictures || []) {
          if (pic && pic.id) state.pictures.push(pic);
        }
        if (A.lastPic && A.lastPic.id) state.pictures.push(A.lastPic);
        A.lastPic = null;
      }
      A.picList.splice(idx - 1, 1);
      save();
      ctx.push('animpicture_load', animPayload());
      return { code: 0 };
    },

    /* THE GATE: the client reads `e.phase` and does nothing unless it is >= 0.
       Advancing the phase is the page's progress; reaching 0 again finishes the
       page, which is when the client bumps item_num and returns exp_pic. */
    animpicture_use_item: (d, ctx) => {
      const A = state.animPicture;
      const page = (A.picList || [])[A.workingIndex || 0];
      const total = page ? animPhaseCount(page.id) : 0;
      let phase = Number(A.phase || 0);
      if (total > 0 && phase < total) {
        phase += 1;
        if (phase >= total) phase = 0;      // page finished -> back to 0
      } else {
        phase = 0;
      }
      A.phase = phase;
      if (phase === 0) {
        A.itemNum = (A.itemNum || 0) + 1;
        A.exp = 0;
        // the client pushes every exp_pic back into the album itself
        A.expPic = [];
      }
      save();
      ctx.push('animpicture_load', animPayload());
      return { phase };                      // never undefined: it is the gate
    },

    /* ---------------- 故事 (story_*) ---------------------------------------

       StoryData = {id, partner, name, gift:-1, feedback:-1}. All three of these
       commands are needResponse:FALSE -- the client mirrors them locally:
         sendGift        : `-1 == story.gift && consumeHouseItem(t,1)` then
                           `story.gift = t` and send("story_send_gift", null, id, t)
         readNewStory    : `newStoryID = 0` then send("story_read_new_story")
         feedback_gift   : sent from the mail's "是否感谢他的赠礼？" confirm
       There is no reply to read, so no field can gate anything -- but the
       authoritative state still has to move, or a reload would disagree. */
    story_load: () => ({
      stories: (state.storyBook.list || []).map((s) => ({
        id: s.id,
        partner: s.partner || 0,
        name: s.name || '',
        gift: s.gift === undefined ? -1 : s.gift,
        feedback: s.feedback === undefined ? -1 : s.feedback,
      })),
      new_story_id: state.storyBook.newId || 0,
    }),

    story_send_gift: (d, ctx) => {
      const id = Number(d && d.id);
      const itemId = Number(d && d.gift);
      const row = (state.storyBook.list || []).find((s) => s.id === id);
      if (!row) return undefined;
      // only one gift per story, and only if you actually have the item
      if (row.gift !== -1 && row.gift !== undefined) return undefined;
      if (!ITEM_BY_ID.has(itemId) || getHaveItem(itemId) <= 0) return undefined;
      addHouseItem(itemId, -1);        // the client consumed it locally too
      row.gift = itemId;
      save();
      ctx.push('item_load_items', handlers.item_load_items());
      ctx.push('item_update', { item: { item_id: itemId, count: getHaveItem(itemId) } });
      return undefined;                // needResponse:false
    },

    story_read_new_story: () => {
      state.storyBook.newId = 0;
      save();
      return undefined;
    },

    story_feedback_gift: (d) => {
      const id = Number(d && d.id);
      const row = (state.storyBook.list || []).find((s) => s.id === id);
      if (row) {
        row.feedback = 1;
        save();
      }
      return undefined;
    },

    /* 回忆彩蛋. This used to be `() => ({ list: [] })`, and the client's
       `misc_moment_load` only ever ADDS ids to its has_map -- so an empty list
       meant no moment was ever unlocked. */
    misc_moment_load: () => ({ list: (state.moments || []).slice() }),

    /* Payload is the moment id. The client sets `has_map[id] = true` itself on
       code 0. The id must be a real momentData row or the client has art/copy it
       cannot resolve. */
    misc_moment_unlock: (d) => {
      const id = Number(d && d.id);
      const table = (gamedata.tables && gamedata.tables.momentData) || {};
      const row = (table.list || {})[String(id)];
      if (!row) return { code: -1 };
      if (!state.moments) state.moments = [];
      if (state.moments.indexOf(id) === -1) {
        state.moments.push(id);
        save();
      }
      return { code: 0 };
    },

    other_load_touch: () => ({ cur: 0, list: [] }),
    share_load: () => ({ pic_list: sharePicList() }),

    /* Claiming a postcard's share reward (see the note on sharePicList). The client
       only sends this when its own rewardData still holds the photo, so a duplicate
       is impossible from the UI -- but a reload mid-flow can repeat it, hence the
       one-claim-per-photo guard. The reward rides a gift mail, exactly like the other
       share/ad rewards: on code 0 the client toasts 「叮咚~邮箱有动静」. */
    share_get_reward: (d, ctx) => {
      const id = Number(firstDefined(d, ['id']));
      const claimed = shareClaimedMap();
      if (claimed[id]) return { code: 0 };              // idempotent: answer 0, pay once
      if (!(state.pictures || []).some((p) => Number(p.id) === id)) {
        return { code: -1, reason: 'unknown picture' };
      }
      claimed[id] = 1;
      const m = makeMail({
        type: 3,                                        // Mail.EvtId.Gift
        title: '分享奖励',
        message: '谢谢你帮呱呱分享明信片，这是小小的心意。',
        clover: SHARE_PHOTO_CLOVER,
        senderCharaId: -1,
      });
      state.mails.push(m);
      trimMails();
      save();
      ctx.push('notify_new_mail', { mail: m });
      ctx.push('mail_load', state.mails);
      ctx.push('share_load', { pic_list: sharePicList() });
      return { code: 0 };
    },

    /* ------------------------------------------------------------ 博物馆图鉴
       The museum LIST is rendered from the LOCAL table, not from us:
         MuseumListView.update() walks MuseumDB.list() and keeps rows with
         `switch == 1` (江西省博物馆 / 山东博物馆 / 南越王博物院 / 吴文化博物馆;
         山西博物院 is the 5th row with switch == 0), then ENRICHES each row from
         our `museum_list` matched by id:
             pic_list:    i[o.id] ? i[o.id].pic_list    : []
             collections: i[o.id] ? i[o.id].collections : []
       The DETAIL page (MuseumPage.dataChanged) then asks, slot by slot, whether a
       slot's id is in those arrays:
             pic slot i:  pic_id[i]         in pic_list   -> show art, else hide
             col slot i:  collection_id[i]  in collections -> show item, else "?"
       So all we ever have to answer is "which of this museum's postcards and
       collectibles does the player own?". Everything else (names, ticket art,
       descriptions, slot ids) is already in the client.
       We used to answer `{museum_list: []}`, which left every slot grey.

       We deliberately do NOT filter by `switch`: the local table decides which
       museums are visible, we only report ownership. That way a table update that
       opens 山西博物院 starts working without an engine change. */
    museum_load: () => {
      const rows = (gamedata.tables && gamedata.tables.museumData) || {};
      const owned = ownedPictureIds();
      const cols = (state.handbook && state.handbook.collections) || [];
      const list = [];
      for (const key of Object.keys(rows)) {
        const m = rows[key];
        if (!m) continue;
        const picIds = (Array.isArray(m.pic_id) ? m.pic_id : []).map(Number);
        const colIds = String(m.collection_id == null ? '' : m.collection_id)
          .split(',')
          .map((v) => Number(v.trim()))
          .filter((v) => !Number.isNaN(v));
        list.push({
          id: Number(m.id),
          pic_list: picIds.filter((p) => owned.has(p)),
          collections: colIds.filter((c) => cols.indexOf(c) !== -1),
        });
      }
      return { museum_list: list };
    },

    /* 手工拼装 -- see the CRAFT_* constants for what is recovered and what is ours.
       The client's whole 手工 window is fed by this one command:
         wishs / stamps : the craft history (each row carries the fields the client
                          renders -- see the `craft` note in defaultState)
         wish_new       : the freshest FINISHED wish, read as `{make_time, u_id}`
                          (the client stores `u_id` in a cookie, so re-sending the
                          same one does not re-raise the red dot)
         stamp_new      : same idea, but the field is `time`, not `make_time`
         boxes          : finished crafts to pop up; each entry is an ITEM ID
                          (`ItemDB.get(id)` + "获得物品，已放入" + ItemPutDesc[type]) */
    pray_load_grays: () => {
      if (advanceCraft(nowSec())) save();
      const c = state.craft || {};
      const wishes = (c.wishes || []).slice();
      const stamps = (c.stamps || []).slice();
      const done = (list) => list.filter((r) => r.state > 3);
      const doneStamps = (list) => list.filter((r) => craftDone('stamp', r));
      const newestWish = done(wishes).sort((a, b) => b.make_time - a.make_time)[0];
      const newestStamp = doneStamps(stamps).sort((a, b) => b.time - a.time)[0];
      return {
        wishs: wishes,
        stamps,
        boxes: (c.pending || []).slice(),
        wish_new: newestWish
          ? { make_time: newestWish.make_time, u_id: newestWish.u_id } : false,
        stamp_new: newestStamp
          ? { time: newestStamp.time, u_id: newestStamp.u_id } : false,
      };
    },

    /* 三拼: one of each COMPOSE material -> one amulet. BoxCraftView only calls this
       once all three sub_type counts are above zero, so a shortage here means the
       two sides disagree; the codes below are all in the client's errcode.json. */
    pray_compose: (d) => {
      const id = Number(firstDefined(d, ['id']));
      if (id !== COMPOSE_RECIPE_ID) return { code: 5 };        // 5 = 参数非法
      for (const piece of COMPOSE_PIECE_IDS) {
        if (getHaveItem(piece) <= 0) return { code: 42 };      // 42 = 物品不足
      }
      for (const piece of COMPOSE_PIECE_IDS) addHouseItem(piece, -1);
      addHouseItem(COMPOSE_AMULET_ID, 1);
      save();
      /* The client walks this as a list of ITEM IDS and builds its own
         `{item_id, count:1}` reward rows. */
      return { item_list: [COMPOSE_AMULET_ID] };
    },

    /* needResponse:false -- the client clears its own list, then tells us.
       `boxes` is an inbox: the player has already been shown (and credited) the
       items, so this only decides whether the popup can fire again next boot. */
    pray_confirm_make_box: () => {
      const c = state.craft || (state.craft = { wishes: [], stamps: [], pending: [], seq: 0 });
      if (c.pending && c.pending.length) {
        c.pending = [];
        save();
      }
      return undefined;
    },

    // animpicture_load USED TO BE HERE as `() => ({ pic_list: [] })`. The real
    // implementation is above; being the LAST definition, the stub shadowed it
    // (5th time the duplicate-handler test has caught this exact mistake).
    // pray_load_grays USED TO LIVE HERE TOO, with exactly the same problem: the real
    // implementation (祈愿木牌 / 印章 / 三箱) is above, and this stub would have
    // shadowed it. Removed -- the duplicate-handler test caught it again.
    easteregg_load: () => ({ egg_list: [] }),
    /* =============================================== 春节贺卡 (springcard)
       Every command in this family gates on a value the client reads straight out of
       the reply, and the callbacks test `0 == code` -- never getErrorInfo -- so a
       missing field is a SILENT dead button. Hence: `buy` must return a real
       `tags_id`, `send` a `box_id > 0`, `share_tags` a non-empty `share_code`. */
    springcard_load: () => {
      const s = scState();
      return {
        end_time: cardEnd(),
        card_info: { bg: s.bg | 0, bless: s.bless | 0, tags: s.tags.slice(0, 3) },
        task_harvest: s.taskHarvest | 0,
        buy_num: s.buyNum | 0,
        can_buy_num: SC_TAGS.length ? 3 : 0,       // 【自设计】 how many slots the shop shows
        share_num: s.shareNum | 0,
        share_get: s.shareGet | 0,
        box_id: s.boxId | 0,                      // 0 / 200009 / 200010 only
        share_code: String(s.shareCode || ''),
        items: s.items.map((i) => ({ item_id: Number(i.item_id), num: Number(i.num) || 0 })),
        task_item: s.taskItem.slice(),            // tag IDS
        reward_list: s.rewardList.map((i) => ({ item_id: Number(i.item_id), num: Number(i.num) || 0 })),
        global_num: s.globalNum | 0,
      };
    },

    springcard_load_count: () => ({
      count: Math.max(0, SC_SHARE_LIMIT - (scState().shareGet | 0)),
    }),

    /* 买贴纸: priced by the table's own tags_price, tag drawn by its buy_weight. */
    springcard_buy: (d, ctx) => {
      const s = scState();
      if (state.clover < SC_TAGS_PRICE) return { code: 61 };
      const tagId = scPickTag();
      if (!tagId) return { code: 6 };
      state.clover -= SC_TAGS_PRICE;
      s.buyNum = (s.buyNum | 0) + 1;
      cardAddItem(s.items, tagId, 1);
      save();
      ctx.push('clover_update', { clover: state.clover });
      return { tags_id: tagId };
    },

    springcard_change_bg: (d) => {
      const s = scState();
      const id = Number(firstDefined(d, ['id']));
      if (SC_BG_IDS.indexOf(id) === -1) return { code: 5 };
      s.bg = id;
      save();
      return { code: 0 };
    },

    springcard_change_bless: (d) => {
      const s = scState();
      const id = Number(firstDefined(d, ['id']));
      if (SC_BLESS_IDS.indexOf(id) === -1) return { code: 5 };
      s.bless = id;
      save();
      return { code: 0 };
    },

    /* `pos` is 1-BASED on the wire: the client sends `viewIndex + 1` and then writes
       `card_info.tags[viewIndex]` itself, plus `changeItems(id, -1)` to spend the tag. */
    springcard_put_tags: (d) => {
      const s = scState();
      const pos = Number(firstDefined(d, ['pos']));
      const id = Number(firstDefined(d, ['id']));
      const idx = pos - 1;
      if (!(idx >= 0 && idx <= 2)) return { code: 5 };
      if (SC_TAGS.length && SC_TAGS.map((t) => t.id).indexOf(id) === -1) return { code: 5 };
      s.tags[idx] = id;
      save();
      return { code: 0 };
    },

    /* 寄卡片. The box size rule is 【自设计】: all three slots filled = the big box. */
    springcard_send: () => {
      const s = scState();
      const filled = s.tags.filter((t) => Number(t) > 0).length;
      s.boxId = filled >= 3 ? SC_BIG_BOX : SC_SMALL_BOX;
      save();
      return { box_id: s.boxId };
    },

    /* 开盒. `num` decides EVERYTHING: 0 means `id` is a key into the table's
       `bless_box` (7..15) and the client shows that blessing instead of an item. */
    springcard_get_reward: (d, ctx) => {
      const s = scState();
      const big = Number(s.boxId) === SC_BIG_BOX;
      s.boxId = 0;
      s.tags = [0, 0, 0];
      s.bg = 0;
      s.bless = 0;
      if (!big) {
        const keys = SC_BLESS_BOX_KEYS.length ? SC_BLESS_BOX_KEYS : [7];
        const id = keys[randInt(0, keys.length - 1)];
        save();
        return { id, num: 0 };
      }
      /* A real item: it must exist in Item.json AND the engine has to grant it --
         the client only renders the reward row. */
      const itemId = SC_STICKER_BAG;
      cardAddItem(s.rewardList, itemId, 1);
      grantItem(ctx, itemId, 1);
      save();
      return { id: itemId, num: 1 };
    },

    springcard_get_task_reward: (d, ctx) => {
      const s = scState();
      for (const id of s.taskItem) grantItem(ctx, Number(id), 1);
      s.taskItem = [];
      save();
      return { code: 0 };
    },

    /* The client needs a NON-EMPTY `share_code` and immediately chains
       `springcard_get_task_reward` off it. 【自设计】 format. */
    springcard_share_tags: (d) => {
      const s = scState();
      s.shareCode = cardCode();
      s.shareNum = (s.shareNum | 0) + 1;
      save();
      return { share_code: s.shareCode };
    },

    /* 兑换码换贴纸. The client itself caps this at tags_share_limit per day. */
    springcard_get_share_tags: (d) => {
      const s = scState();
      if ((s.shareGet | 0) >= SC_SHARE_LIMIT) return { code: 1 };
      const id = scPickTag();
      if (!id) return { code: 1 };
      s.shareGet = (s.shareGet | 0) + 1;
      cardAddItem(s.items, id, 1);
      save();
      return { tags_id: id };
    },

    /* Declared in ProtocolList but never sent by this build; kept so it cannot
       answer `{}` to a future client that does send it. */
    springcard_get_task_item: () => ({ list: scState().taskItem.slice() }),

    /* =============================================== 祝福贺卡 (greetcard) */
    greetcard_load: () => {
      const s = gcState();
      return {
        end_time: cardEnd(),
        card_info: { bg: s.bg | 0, bless: s.bless | 0, tags: s.tags.slice(0, 3) },
        send_list: s.sendList.map((c) => ({
          bg: Number(c.bg) || 0, bless: Number(c.bless) || 0,
          tags: (c.tags || [0, 0, 0]).slice(0, 3).map(Number),
        })),
        get_list: s.getList.map((c) => ({
          name: String(c.name || ''), bg: Number(c.bg) || 0, bless: Number(c.bless) || 0,
          tags: (c.tags || [0, 0, 0]).slice(0, 3).map(Number), gift: Number(c.gift) || 0,
        })),
        items: s.items.map((i) => ({ item_id: Number(i.item_id), num: Number(i.num) || 0 })),
        task_login: !!s.taskLogin,
        task_share: !!s.taskShare,
        task_item: s.taskItem.slice(),            // tag IDS
        can_reward: !!s.canReward,
        global_num: s.globalNum | 0,
        new_index: s.newIndex | 0,                // 1-based into get_list, 0 = none
        stock_num: s.stockNum | 0,
      };
    },

    greetcard_load_count: () => ({
      count: Math.max(0, GC_BG_PRICE.length - (gcState().stockNum | 0)),
    }),

    /* 买背景: price walks `bg_price` by how many batches were already bought. */
    greetcard_buy: (d, ctx) => {
      const s = gcState();
      const id = Number(firstDefined(d, ['id']));
      if (id <= 0) return { code: 5 };
      const price = Number(GC_BG_PRICE[Math.min(s.stockNum | 0, GC_BG_PRICE.length - 1)]) || 100;
      if (state.clover < price) return { code: 61 };
      state.clover -= price;
      cardAddItem(s.items, id, 1);
      save();
      ctx.push('clover_update', { clover: state.clover });
      return { code: 0 };
    },

    greetcard_change_bg: (d) => {
      const s = gcState();
      const id = Number(firstDefined(d, ['id']));
      if (GC_BG_IDS.indexOf(id) === -1) return { code: 5 };
      s.bg = id;
      save();
      return { code: 0 };
    },

    greetcard_change_bless: (d) => {
      const s = gcState();
      const id = Number(firstDefined(d, ['id']));
      if (GC_BLESS_IDS.indexOf(id) === -1) return { code: 5 };
      s.bless = id;
      save();
      return { code: 0 };
    },

    greetcard_put_tags: (d) => {
      const s = gcState();
      const pos = Number(firstDefined(d, ['pos']));
      const id = Number(firstDefined(d, ['id']));
      const idx = pos - 1;
      if (!(idx >= 0 && idx <= 2)) return { code: 5 };
      if (GC_TAGS.length && GC_TAGS.indexOf(id) === -1) return { code: 5 };
      s.tags[idx] = id;
      save();
      return { code: 0 };
    },

    /* 寄出. The client pushes the card into its own send_list and clears card_info,
       then starts showing the history button. */
    greetcard_send: () => {
      const s = gcState();
      s.sendList.push({ bg: s.bg | 0, bless: s.bless | 0, tags: s.tags.slice(0, 3) });
      s.tags = [0, 0, 0];
      s.bg = 0;
      s.bless = 0;
      s.canReward = true;                       // its own callback sets this too
      save();
      return { code: 0 };
    },

    /* The reward is a LIST OF ITEM IDS (the view builds {item_id,count} rows itself)
       and `list.length` is read with no guard, so it must always be an array. */
    greetcard_get_reward: (d, ctx) => {
      const s = gcState();
      if (!s.canReward) return { code: 0, list: [] };
      const id = GC_SEND_SELECT[randInt(0, GC_SEND_SELECT.length - 1)];
      s.canReward = false;
      cardAddItem(s.items, id, 1);
      grantItem(ctx, id, 1);
      save();
      return { code: 0, list: [id] };
    },

    greetcard_get_task_item: () => ({ list: gcState().taskItem.slice() }),

    greetcard_get_task_reward: (d, ctx) => {
      const s = gcState();
      for (const id of s.taskItem) grantItem(ctx, Number(id), 1);
      s.taskItem = [];
      save();
      return { code: 0 };
    },

    /* 采购: the client increments its own stock_num and drops every bg item
       (`item_id < 100`) from its list, so we mirror both. */
    greetcard_stock: () => {
      const s = gcState();
      s.stockNum = (s.stockNum | 0) + 1;
      s.items = s.items.filter((i) => Number(i.item_id) >= 100);
      save();
      return { code: 0 };
    },

    /* needResponse:false -- answering one of these would be dispatched as a push and
       logged as an unknown protocol. They are player-side bookkeeping. */
    greetcard_read_new: () => {
      const s = gcState();
      s.newIndex = 0;
      save();
      return undefined;
    },
    greetcard_send_gift: (d) => {
      const s = gcState();
      const index = Number(firstDefined(d, ['index']));      // 1-based
      const gift = Number(firstDefined(d, ['gift'])) || 0;
      const row = s.getList[index - 1];
      if (row) row.gift = gift;
      save();
      return undefined;
    },
    greetcard_feedback_gift: () => undefined,

    /* =============================================== 生日蛋糕 (partycake) */
    partycake_load: () => pcPayload(),

    partycake_load_mate: () => {
      const s = pcState();
      return { pre_cream: s.preCream | 0, pre_sugar: s.preSugar | 0 };
    },

    /* Pushed per row: the client writes straight into `task_list[task.id-1]`. */
    partycake_load_task: () => {
      const rows = pcTaskRows();
      return { task: rows[0] || { id: 1, count: 0, is_done: 0 } };
    },

    /* Both sent (when cur_state is qa/qa_reward) and pushed. */
    partycake_load_qa: () => pcQaPayload(),

    /* 领取邻居送来的材料: the pending counters become spendable. */
    partycake_get_mate: (d, ctx) => {
      const s = pcState();
      s.cream = (s.cream | 0) + (s.preCream | 0);
      s.sugar = (s.sugar | 0) + (s.preSugar | 0);
      s.preCream = 0;
      s.preSugar = 0;
      save();
      ctx.push('partycake_load_mate', { pre_cream: 0, pre_sugar: 0 });
      return { code: 0 };
    },

    /* 做一层. Materials come from the table's own layer row; the client pre-checks
       them too (「材料不够了~」) and deducts locally when the state changes. */
    partycake_make: (d) => {
      const s = pcState();
      if (Number(s.curState) !== 0) return { code: 6 };
      const part = (PC_TABLE.cake || {})[String(s.part)] || {};
      const row = (part.layers || {})[String(Number(firstDefined(d, ['layer'])))] ;
      if (!row) return { code: 5 };
      if (s.madeLayers.indexOf(Number(row.layer)) !== -1) return { code: 6 };
      if ((s.cream | 0) < (Number(row.cream) || 0) || (s.sugar | 0) < (Number(row.sugar) || 0)) {
        return { code: 61 };
      }
      s.cream -= Number(row.cream) || 0;
      s.sugar -= Number(row.sugar) || 0;
      s.madeLayers.push(Number(row.layer));
      s.curState = 1;
      save();
      return { state: 1 };
    },

    /* 开礼物: the next step is the quiz, except on the last part where the candle
       comes first. 【自设计】 the qa-vs-light assignment is a reconstruction (the spec
       says so explicitly): quiz after each part, candle at the end. */
    partycake_reward_make: () => {
      const s = pcState();
      s.curState = Number(s.part) >= 5 ? 4 : 2;
      if (s.curState === 2) {
        s.answer = null;                        // a fresh question
        s.wrong = 0;
      }
      save();
      return { state: s.curState };
    },

    /* The quiz. `index` is the chosen option (1-BASED -- the view loops 1..3 and
       stores that counter in `cur_selete`); the client then reads its own
       `cur_state` to decide between "try again" and the reward screen. The pushed
       `partycake_load_qa` refreshes `wrong`/`answer`/`reward` so a retry shows the
       「再次回答」 title and the reward rows can never disagree with what
       `partycake_reward_qa` pays out. */
    partycake_answer: (d, ctx) => {
      const s = pcState();
      pcQaPayload();                            // make sure a question exists
      const index = Number(firstDefined(d, ['index']));
      const right = index === Number(s.qaCorrect);
      s.curState = right ? 3 : 2;
      if (!right) s.wrong = 1;
      save();
      ctx.push('partycake_load_qa', pcQaPayload());
      return { state: s.curState };
    },

    /* Claiming the quiz reward ends the part: the client then calls checkMakePart()
       itself, which advances `part` once every layer is built. The payout is
       EXACTLY the two rows `pcQaPayload().reward` advertises. */
    partycake_reward_qa: (d, ctx) => {
      const s = pcState();
      for (const row of pcQaRewardRows()) {
        grantItem(ctx, Number(row.item_id), Number(row.count) || 1);
      }
      s.curState = 0;
      s.answer = null;
      s.wrong = 0;
      const part = (PC_TABLE.cake || {})[String(s.part)] || {};
      const need = Object.keys(part.layers || {}).length;
      if (need && s.madeLayers.length >= need) {
        s.part = Math.min(5, Number(s.part) + 1);
        s.madeLayers = [];
      }
      save();
      return { state: 0 };
    },

    partycake_light: () => {
      const s = pcState();
      if (Number(s.curState) !== 4) return { code: 6 };
      s.curState = 5;
      save();
      return { state: 5 };
    },

    partycake_reward_light: (d, ctx) => {
      const s = pcState();
      for (const id of PC_SHARE_REWARD.slice(0, 1)) grantItem(ctx, id, 1);
      grantItem(ctx, Number(PC_LIGHT_REWARD.item_id), Number(PC_LIGHT_REWARD.item_num) || 1);
      s.curState = 6;
      save();
      return { state: 6 };
    },

    /* `index` is 1-BASED: the client tests `share_get[index-1]` before sending, so an
       already-claimed slot must not rebate -- answer code 0 but change nothing. */
    partycake_reward_share: (d, ctx) => {
      const s = pcState();
      const index = Number(firstDefined(d, ['index']));
      if (!(index >= 1 && index <= PC_SHARE_REWARD.length)) return { code: 5 };
      if (Number(s.shareGet[index - 1]) === 1) return { code: 0 };
      grantItem(ctx, PC_SHARE_REWARD[index - 1], 1);
      s.shareGet[index - 1] = 1;
      save();
      return { code: 0 };
    },
    // `cooking_load_cooking` USED TO BE HERE as `() => ({ task_list: [] })`, and
    // being the LAST definition it silently shadowed the real implementation
    // above. Removed -- the duplicate-handler test found it (4th time this class
    // of bug has been caught by that test).
    adsmgr_load: (d, ctx) => adsPayload(ctx),

    /* ---- 分享 / 广告 ------------------------------------------------------
       Every one of these used to be MISSING, so `req_share` got no reply at all
       and the client's callback never ran: the buttons that show 「分享拿福利」
       (share_btn3_png in ShopAdsSkin / FurnitureAdsSkin) and 分享游戏 simply did
       nothing when tapped. Under the channel the client actually runs as
       (ChannelType.Test) those buttons are not wired to the WeChat SDK at all --
       they call straight through to these commands -- so answering them is the
       whole fix. */
    adsmgr_share: (d, ctx) => {
      const type = Number(firstDefined(d, ['ads_type'])) || 0;
      const a = ensureAdsState();
      const today = dayKey();
      /* 生日蛋糕 task 5 「完成一次分享」 -- whichever share this is, it counts. */
      pcTaskProgress(5, 1);
      switch (type) {
        case 1: {
          // the daily pop-up / ad-video gift: once per day, delivered as mail
          if (a.popDay === today) return { code: -2, reason: 'already claimed today' };
          a.popDay = today;
          deliverAdsGift(ctx, '每日分享奖励');
          save();
          return { code: 0 };
        }
        case 2: {
          // AdsGiftView: the client's own on_get_gift() counts these, and the
          // toast promises mail, so grant the mail and let the client count it
          if (a.giftGet >= ADS_GIFT_PER_DAY) return { code: -2, reason: 'daily gift limit' };
          a.giftGet += 1;
          deliverAdsGift(ctx, '分享奖励');
          save();
          return { code: 0 };
        }
        case 3:
          // a free extra raffle roll: LotteryModel.onGetExtraItem() does the work
          // client-side, and reward_raffle() asks the server for a ball when
          // colorBall is -1, so arming one is what makes it claimable
          if (state.gacha.colorBall < 0) state.gacha.colorBall = rollPrizeRank();
          save();
          return { code: 0 };
        case 4:
          // furniture welfare goods: n(true) already ran requestBuy, which is the
          // grant; this call is the share report and needs only an ack
          return { code: 0 };
        case 5:
          // shop free order: adsmgr_shop_free carries the grant
          return { code: 0 };
        default:
          return { code: -1, reason: 'unknown ads_type' };
      }
    },

    /* Fire-and-forget (needResponse false): the client reports that a share
       happened for `ads_id` (e.g. 'frog_back') and expects nothing back. The mail
       that carried the share_id was already accepted client-side, and its own
       helper methods are empty stubs, so the reward has to be credited here or it
       is lost. */
    adsmgr_share_ads: (d, ctx) => {
      const adsId = String(firstDefined(d, ['ads_id']) || '');
      if (!adsId) return undefined;
      const a = ensureAdsState();
      if (a.lastShareAds === adsId && a.lastShareAdsDay === dayKey()) {
        return undefined;                     // one reward per id per day
      }
      a.lastShareAds = adsId;
      a.lastShareAdsDay = dayKey();
      deliverAdsGift(ctx, `${adsId} 分享奖励`);
      return undefined;
    },

    adsmgr_refuse: (d, ctx) => {
      const a = ensureAdsState();
      a.popRefusedDay = dayKey();             // the client sets can_pop=false itself
      save();
      return { code: 0 };
    },

    /* ShopView.buy: item_buy answered is_free, and the player then completed the
       share/ad step. The purchase is completed HERE (the client's ItemModel
       helpers are stubs) and any clover the client already deducted locally is
       pushed back. No shop row is free in the shipped data and the live service's
       random 免单 cannot be recovered, so nothing marks a slot free on its own --
       this handler exists so the flow works correctly if one ever is. */
    adsmgr_shop_free: (d, ctx) => {
      const pend = state.pendingFreeBuy;
      if (!pend || !pend.shopId) return { code: -1, reason: 'no pending free order' };
      const slot = SHOP_BY_ID.get(Number(pend.shopId));
      state.pendingFreeBuy = null;
      if (!slot) return { code: -1 };
      // the client deducted the price locally before sending item_buy
      state.clover += Number(slot.price) || 0;
      const count = addHouseItem(slot.itemId, 1);
      state.shopBought[Number(pend.shopId)] = (state.shopBought[Number(pend.shopId)] || 0) + 1;
      save();
      ctx.push('clover_update', { clover: state.clover });
      pushItemUpdate(ctx, slot.itemId, count);
      return { code: 0 };
    },

    /* ---- 充值 -------------------------------------------------------------
       recharge_load used to answer {sack: [], field: []}, so the 田地 page had no
       rows at all and every 充值 button looked broken. */
    recharge_load: (d, ctx) => rechargePayload(ctx),
    recharge_load_gift: () => ({ gift: [] }),
    recharge_update_num: (d, ctx) => {
      const r = ensureRechargeState();
      return { water: Number(r.water) || 0, change: Number(r.change) || 0 };
    },
    /* 浇水: the reply is dispatched verbatim as RechargeEventType.FIELD_WATERED
       and the page only uses it to fire the sprinkler animation, then re-reads
       `field`, so the field itself is what must be pushed. */
    recharge_water: (d, ctx) => {
      const r = ensureRechargeState();
      if (r.water <= 0) return { code: -1, reason: 'no water' };
      r.water -= 1;
      for (const row of rechargeField()) {
        if (Number(row.grow) < Number(row.total)) row.grow = Number(row.total);
      }
      save();
      ctx.push('recharge_load', rechargePayload(ctx));
      return { code: 0, field: r.field, water: r.water };
    },
    recharge_change: (d, ctx) => {
      const r = ensureRechargeState();
      save();
      ctx.push('recharge_load', rechargePayload(ctx));
      return { code: 0, field: r.field, change: r.change };
    },
    /* The client never sends this in the shipped build (ProtocolList declares it,
       the SDK integration is gone), but it is exactly the "this pack was paid,
       deliver it" step, so the offline shell calls it when the player taps a pack:
       see BaseChannel.pay() in __probe.js. */
    recharge_ready_pay: (d, ctx) => {
      const id = Number(firstDefined(d, ['id']));
      if (!deliverRechargePack(ctx, id)) return { code: -1, reason: 'unknown pack' };
      return { code: 0 };
    },
    recharge_cancel_pay: (d) => {
      const id = Number(firstDefined(d, ['id']));
      if (id) state.rechargeCancelId = id;
      return undefined;                       // needResponse false
    },
    // annual_load: the client's AnnualReviewModel.updateRedot() raises a red dot
    // whenever `is_share` is falsy. Sharing goes through WeChat, which an offline
    // build cannot do, so an actionable dot there would be a dead end -- report it
    // as already shared and leave the dot off.
    annual_load: () => annualPayload(),
    annual_share: () => ({ code: 0 }),
    /* ======================================================== 博物馆冒险
       Spec: work/spec/museumday.md (every claim below is quoted from the client
       with byte offsets there). The three things that make this family dangerous,
       all of them verified in that spec:

       1. The window is PURELY payload-driven: `getActivityTime()` returns
          `data.end_time > 0 ? [1, data.end_time] : [0, 0]`, and `start_time` has no
          reader at all; no date range is hardcoded in the bundle. So a future
          `end_time` = permanently open. We roll `now + 20 days` on every load
          instead of a far-future constant because the client arms a close timer of
          `1000 * (end_time - now + 1)`, which overflows int32 past ~24.8 days.
       2. `museumday_load` REPLACES the model (`this.data = Utils.convertArrayAll(e)`,
          @300427) -- it is a filter, not a merge, so every key the model's other
          methods touch must be present. Returning just `{end_time: <future>}` makes
          `checkRedot()` read `data.path.length` of undefined and throw
          "Cannot read properties of undefined" -> the client's onerror shows
          「呱呱吃坏肚子了」 and reloads, forever. Hence all 16 keys below.
       3. Four arrays are ARRAYS OF ROW OBJECTS, never arrays of ids:
          path:[{grid,type,style}], museum_list:[{id,desc_id,time}],
          items/get_items:[{item_id,num}], log_list:[{desc,item_id,item_num,time}].

       【自设计】 = our value, the original's rule was server-side and is NOT in our
       snapshot: the route shape and tile loot, one-step-per-compass, the 2 restarts
       per adventure, `inspire_time`, and the arrival reward. Marked in dist/README. */
    museumday_load: (d, ctx) => {
      const s = ensureMuseumday();
      /* 大冒险暂时关掉了（玩家反馈"太麻烦"，改为开放博物馆图鉴）。`end_time` is the
         whole switch for the client -- see mdPayload -- so returning 0 hides the entry
         and stops it arming its activity timer. The implementation below is intact:
         set MUSEUM_DAY_ENABLED back to true to bring the event back. */
      s.endTime = MUSEUM_DAY_ENABLED ? mdEnd() : 0;
      save();
      return mdPayload(s);
    },

    /* 换一条新路线. `left_num` must NOT be -1: the history page's "next museum"
       check is `-1 != left_num`, so -1 makes the button do nothing at all. */
    museumday_refresh: (d, ctx) => {
      const s = ensureMuseumday();
      s.leftNum = Math.max(0, (s.leftNum | 0) - 1);
      if (!s.curMuseum) s.curMuseum = mdPickMuseum(s);
      s.path = mdBuildPath(s.curMuseum);
      s.frog = 1;
      s.next = 1;
      s.items = [];
      s.descId = MD_DESC_END;
      save();
      ctx.push('museumday_info', { compass: s.compass | 0, task_num: s.taskNum | 0 });
      return { left_num: s.leftNum };
    },

    /* One compass reveals one tile. `next` MUST differ from the current value: the
       caller indexes `path[next-1].grid`, so returning the same number walks off the
       array and throws (the crash loop again). The compass count is NOT in this
       reply -- the client does not decrement it -- so it goes out as a push. */
    museumday_random_compass: (d, ctx) => {
      const s = ensureMuseumday();
      if (!s.curMuseum || s.compass <= 0) return { code: 61 };   // 61 资源不足
      if (s.next >= s.path.length) return { code: 6 };            // 6 非法操作
      s.compass -= 1;
      s.next += 1;
      s.frog = s.next;
      mdTileLoot(s);
      save();
      ctx.push('museumday_info', { compass: s.compass | 0, task_num: s.taskNum | 0 });
      /* `inspire` is an OVERWRITE of data.inspire_num, so it must carry the real
         value or the cookie counter turns into "undefined". */
      return { next: s.next, inspire: s.inspireNum | 0 };
    },

    /* Not sent by this client build at all (dirCompass() is dead code) -- defined so
       it cannot answer `{}` if a future build does send it. */
    museumday_dir_compass: () => ({ next: 0, inspire: 0 }),
    museumday_load_path: () => ({ path: [] }),

    /* 鼓舞: one cookie-power advances a tile. The client decrements its own
       `inspire_num`, so we must decrement ours but NOT push the number back (that
       would double-count); the next `museumday_load` re-syncs it. */
    museumday_inspire: (d, ctx) => {
      const s = ensureMuseumday();
      if (s.inspireNum <= 0) return { code: 61 };
      if (!s.curMuseum || s.next >= s.path.length) return { code: 6 };
      s.inspireNum -= 1;
      s.next += 1;
      s.frog = s.next;
      mdTileLoot(s);
      save();
      return { next: s.next };
    },

    /* The pending loot becomes collected loot. It MUST be moved out of `items`:
       leaving it there makes the next `museumday_load` still report a non-empty
       `items`, so `updateRewards()` pops the gift again and sends `get_items` again
       -- an infinite loop. */
    museumday_get_items: (d, ctx) => {
      const s = ensureMuseumday();
      for (const it of s.items) {
        if (Number(it.item_id) === MD_COMPASS_ID) continue;   // 罗盘 is the compass itself
        grantItem(ctx, Number(it.item_id), Number(it.num) || 1);
        mdMergeItem(s.getItems, Number(it.item_id), Number(it.num) || 1);
      }
      s.items = [];
      save();
      return { code: 0 };
    },

    /* 结算: the adventure is over. Grants the museum's own rewards, then returns the
       player to the history page with `cur_museum = 0`. */
    museumday_arrive: (d, ctx) => {
      const s = ensureMuseumday();
      if (s.curMuseum) {
        mdArrivalRewards(ctx, s);
        s.museums.push({
          id: s.curMuseum,
          desc_id: MD_DESC_END,
          time: nowSec(),
        });
      }
      s.curMuseum = 0;
      s.path = [];
      s.items = [];
      s.frog = 1;
      s.next = 1;
      s.leftNum = 0;
      s.loot = [];
      save();
      ctx.push('museumday_load', mdPayload(s));
      return { code: 0 };
    },

    /* 开始/重新开始一次冒险 for a museum id (0 = pick one automatically). */
    museumday_start_advance: (d, ctx) => {
      const s = ensureMuseumday();
      const idx = Math.max(0, Math.min(MD_RESTART_PRICE.length - 1,
        s.museums.length - MD_MUSEUMS.length + 1));
      const price = MD_RESTART_PRICE[idx] || 0;
      if (state.clover < price) return { code: 61 };              // 61 资源不足
      let id = Number(firstDefined(d, ['id'])) || 0;
      if (MD_MUSEUMS.indexOf(id) === -1) id = mdPickMuseum(s);
      if (!id) return { code: 6 };
      state.clover -= price;
      s.curMuseum = id;
      s.path = mdBuildPath(id);
      s.frog = 1;
      s.next = 1;
      s.items = [];
      s.loot = [];
      s.leftNum = MD_RESTARTS;                                    // 【自设计】
      s.descId = MD_DESC_END;
      save();
      /* The client's own `consumeClover` only *checks*, it never subtracts, so the
         new balance has to be pushed. */
      ctx.push('clover_update', { clover: state.clover });
      return { code: 0 };
    },

    /* Push-only (needResponse false): the client never requests it. Two fields are
       enough because this one assigns field by field instead of replacing `data`. */
    museumday_info: () => {
      const s = ensureMuseumday();
      return { compass: s.compass | 0, task_num: s.taskNum | 0 };
    },
    item_gift_open: () => ({}),
    clover_notice_get: () => ({ clover: 0, reason: '' }),
    notify_reload: () => undefined,

    /* ------------------------------------------------ save editor (GM) */
    /* The client ships a hidden GM console (enable with showGM:true in
       gameConfig.json). It posts free-form text here as client_gm and prints
       whatever we return in `info`, so this doubles as the in-game save editor. */
    client_gm: (d, ctx) => gmCommand(String(d.cmd || '').trim(), ctx),

    /* --- fire and forget acks (client never waits) --- */
    /* The client sends its WHOLE settings object here on every change
       (`setClientSettings` -> send("client_set_client", null, JSON.stringify(...))),
       and it also merges whatever we push back into its own copy, key by key
       (`for (k of Object.keys(parsed)) this.clientSettings[k] = parsed[k]`).
       Ignoring this call and then pushing our defaults back -- which is what used to
       happen -- meant the client's own bookkeeping was wiped on every
       client_load_role push. The visible symptom: `achieveList` (the ids whose
       "获得称号" popup has already been shown) reset to [] every time, so
       checkNewAchieve() re-announced the OLDEST un-announced title over and over
       instead of the newly earned one. Same class of bug for `hasAchieve`, the
       one-time "first title" guide, which therefore fired every time as well.
       So: remember what the client tells us, and echo it back. */
    client_set_client: (d) => {
      const raw = firstDefined(d, ['client']);
      if (typeof raw !== 'string' || !raw) return undefined;
      let parsed = null;
      try { parsed = JSON.parse(raw); } catch (e) { return undefined; }
      if (!parsed || typeof parsed !== 'object') return undefined;
      /* `guideStep` is ONE-WAY. The client sends it as it advances the tutorial
         (New -> Named -> PrepareGatherClover -> ... -> Complete), and it also
         OVERWRITES its own copy from whatever we echo in `client_load_role`
         (`for (k of Object.keys(parsed)) this.clientSettings[k] = parsed[k]`).
         So an echo that is one step behind -- which happens whenever we push a
         role update before the client's `client_set_client` for the step it just
         finished arrives -- makes the client WALK THE GUIDE BACKWARDS, and the
         player is asked to name the frog again. Keep the furthest step we have ever
         been told and never echo anything earlier. */
      const incoming = parsed.guideStep;
      if (typeof incoming === 'string') {
        const prev = (state.settings && state.settings.guideStep) || '';
        if (guideStepRank(prev) > guideStepRank(incoming)) parsed.guideStep = prev;
      }
      state.settings = Object.assign({}, state.settings || {}, parsed);
      save();
      return undefined;
    },
    client_set_lang: () => undefined,
    client_set_client_envinfo: () => undefined,
    client_set_achieve: () => undefined,
    client_set_icon: () => undefined,
    client_set_pic_show: () => undefined,
    client_set_ads: () => undefined,
    client_set_channel: () => undefined,
    client_set_channel_id: () => undefined,
    client_switch_push: () => ({}),
    client_switch_rank: () => ({ rank_switch: 0 }),
    client_add_push_id: () => undefined,
    client_user_action: () => undefined,
    client_confirm_event: () => undefined,
  };

  /**
   * @param {string} cmdWire  e.g. "client.load_role" or "client_load_role"
   * @param {object} data
   * @returns {{reply?: object, handled: boolean, pushes: Array<{cmd:string,data:object}>}}
   */
  function dispatch(cmdWire, data) {
    const cmd = canon(cmdWire);
    const def = protocol[cmd];
    const pushes = [];
    const ctx = { push: (c, d) => pushes.push({ cmd: toWire(c), data: d }) };
    const h = handlers[cmd];
    if (!h) {
      unknown.set(cmd, (unknown.get(cmd) || 0) + 1);
      if (verbose) console.log(`[engine] UNKNOWN ${cmd} ${JSON.stringify(data || {})}`);
      return {
        reply: def && def.needResponse ? {} : undefined,
        handled: false,
        pushes,
      };
    }
    let reply;
    try {
      reply = h(data || {}, ctx);
    } catch (e) {
      console.error(`[engine] handler ${cmd} threw:`, e && e.stack || e);
      reply = def && def.needResponse ? {} : undefined;
    }
    if (reply === undefined && def && def.needResponse) reply = {};
    // 扭蛋任务 are real in-game actions ("采摘花草", "喂个小伙伴" ...), so they are
    // ticked off centrally here rather than by editing seven handler bodies.
    // `capsuleTaskDone` no-ops unless the event is open and that task is dealt.
    const taskId = CAPSULE_TASK_FOR[cmd];
    // Only a SUCCESS ticks a task off. "no code at all" counts as success (many
    // handlers are push-only), but any non-zero code -- including the -1
    // refusals -- must not, or a refused action would still complete the task.
    const okReply = !reply || reply.code === undefined || Number(reply.code) === 0;
    const okReply2 = !reply || reply.code === undefined || Number(reply.code) === 0;
    if (taskId && okReply) {
      try { capsuleTaskDone(ctx, taskId); } catch (e) { /* never break a command */ }
    }
    const cookTask = COOKING_TASK_FOR[cmd];
    if (cookTask && okReply2) {
      try { cookingTaskProgress(cookTask[0], cookTask[1]); } catch (e) { /* ditto */ }
    }
    return { reply, handled: true, pushes };
  }

  /* Whole-save export/import: the player's frog should survive clearing browser
     storage or moving to another machine. */
  function exportSave() {
    return JSON.parse(JSON.stringify(state));
  }

  /* An explicit import is a deliberate overwrite: the new content replaces the
     old file, but the old file is still archived first by save()'s backup step.
     The safety flags are rebuilt from scratch so an inherited `protectMain`
     cannot block the very import the player just asked for. */
  function importSave(obj) {
    if (!obj || typeof obj !== 'object') throw new Error('bad save payload');
    const fresh = defaultState();
    for (const k of Object.keys(state)) delete state[k];
    Object.assign(state, fresh, obj);
    state.frog = Object.assign(fresh.frog, obj.frog || {});
    state.decoration = Object.assign(fresh.decoration, obj.decoration || {});
    state.items = Object.assign(fresh.items, obj.items || {});
    state.gacha = Object.assign(fresh.gacha, obj.gacha || {});
    state.weather = Object.assign(fresh.weather, obj.weather || {});
    state.travel = Object.assign(fresh.travel, obj.travel || {});
    if (!Array.isArray(state.clovers) || state.clovers.length !== CLOVER_SLOTS) state.clovers = makeClovers();
    state.__saveReport = makeSaveReport();
    state.__saveReport.action = 'import';
    state.__saveReport.restoredFrom = 'import';
    allowMainOverwrite = true;      // the player is deliberately replacing the file
    const ok = save();
    state.__saveReport.imported = ok;
    return ok;
  }

  return {
    state,
    dispatch,
    tick,
    save,
    exportSave,
    importSave,
    /* Where the save lives and how it is doing -- the shell shows this, because
       the failure modes this layer guards against are all silent by nature. */
    saveInfo: () => ({
      path: savePath,
      backup: savePath + SAVE_BAK_SUFFIX,
      pending: savePath + SAVE_TMP_SUFFIX,
      corrupt: listCorruptSlots(savePath),
      version: SAVE_VERSION,
      report: state.__saveReport,
    }),
    /* Escape hatch for the unarchivable-corrupt case: the player (or the editor
       panel) can look at __saveReport.corruptKept first and then deliberately
       accept losing the unreadable bytes. */
    forceSaveOverwrite: () => {
      const r = state.__saveReport || (state.__saveReport = makeSaveReport());
      r.protectMain = false;
      allowMainOverwrite = true;
      state.saveVersion = SAVE_VERSION;
      return save();
    },
    unknownReport: () => Array.from(unknown.entries()).sort((a, b) => b[1] - a[1]),
  };
}

module.exports = { createEngine, canon, toWire, nowSec, defaultState, makeClovers, CLOVER_SLOTS };
