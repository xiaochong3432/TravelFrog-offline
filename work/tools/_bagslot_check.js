#!/usr/bin/env node
'use strict';
/**
 * 取证脚本（不属于发行物，跑完自删临时文件）：
 *   1) 用**当前** work/run/engine/index.js 跑一次「出门 -> 回家」，打印行囊 4 格；
 *   2) 把同一份源码的两个片段替换成建议补丁，写成 index.js 的同目录临时副本，
 *      再跑同样的流程，打印行囊 4 格；
 *   3) 证明：现状会把道具塞进 0/1 号格（便当/护身符格），补丁后回到原来的道具格。
 *
 *   node work/tools/_bagslot_check.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = path.join(ROOT, 'work', 'run', 'engine', 'index.js');
/* 临时副本放在引擎同目录，这样 './data/gamedata.json' 这类相对 require 还能解析 */
const PATCHED = path.join(ROOT, 'work', 'run', 'engine', '__bagslot_patchcheck.tmp.js');

const SLOT = ['0=LunchBox(便当)', '1=Amulet(护身符)', '2=Tool_1(道具)', '3=Tool_2(道具)'];

function newEngine(mod) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-bagslot-'));
  const savePath = path.join(dir, 'save.json');
  const engine = mod.createEngine({ savePath, verbose: false });
  return { engine, dir };
}

function trip(engine, bag, desk) {
  engine.state.items.bag = bag.slice();
  engine.state.items.desk = desk.slice();
  engine.state.frog.status = 0;
  engine.state.travel.nextDepartAt = 1;
  engine.tick();
  const afterDepart = {
    status: engine.state.frog.status,
    bag: engine.state.items.bag.slice(),
    plan: engine.state.travel.plan && {
      lunch: engine.state.travel.plan.lunch,
      carryBack: JSON.parse(JSON.stringify(engine.state.travel.plan.carryBack || [])),
    },
  };
  engine.state.travel.returnAt = 1;
  engine.tick();
  return { afterDepart, afterReturn: engine.state.items.bag.slice() };
}

function label(bag) {
  return bag.map((id, i) => SLOT[i] + '=' + id).join('  ');
}

/* ---------------- 1) 现状 ---------------- */
const origMod = require(ENGINE);
const o = newEngine(origMod);
const rOrig = trip(o.engine, [3, -1, 2002, 2003], [3, 4, -1, -1, 2000, -1, -1, -1]);
console.log('=== 现状 (work/run/engine/index.js) ===');
console.log('行李摆好     : ' + label([3, -1, 2002, 2003]) + '   (便当3 / 水壶2002 / 纸伞2003)');
console.log('出门后       : ' + label(rOrig.afterDepart.bag)
  + '  plan.lunch=' + rOrig.afterDepart.plan.lunch
  + ' carryBack=' + JSON.stringify(rOrig.afterDepart.plan.carryBack));
console.log('回家后       : ' + label(rOrig.afterReturn));
const origMisplaced = rOrig.afterReturn[0] !== -1 || rOrig.afterReturn[1] !== -1;
console.log('判定         : ' + (origMisplaced
  ? '道具被塞进了 0/1 号格（便当格/护身符格）—— 复现玩家反馈'
  : '没有复现'));
fs.rmSync(o.dir, { recursive: true, force: true });

/* ---------------- 2) 打补丁的副本 ---------------- */
const src = fs.readFileSync(ENGINE, 'utf8');

const OLD_PROVISION = `    const carried = state.items.bag.filter((id) => id !== -1);
    const amulet = carried.find((id) => isType(id, ITEM_TYPE_AMULET));
    const tools = carried.filter((id) => isType(id, ITEM_TYPE_TOOLS)).length;
    const carryBack = carried.filter((id) => {
      const it = ITEM_BY_ID.get(id);
      return !it || it.spend !== 1;            // keep durable gear
    });`;

const NEW_PROVISION = `    const carried = [];
    state.items.bag.forEach((id, slot) => {
      if (id !== -1) carried.push({ slot, id });
    });
    const amulet = carried.find((c) => isType(c.id, ITEM_TYPE_AMULET));
    const tools = carried.filter((c) => isType(c.id, ITEM_TYPE_TOOLS)).length;
    const carryBack = carried.filter((c) => {
      const it = ITEM_BY_ID.get(c.id);
      return !it || it.spend !== 1;            // keep durable gear
    });`;

const OLD_AMULET = `      lunch, lunchFrom, amulet: amulet === undefined ? -1 : amulet,`;
const NEW_AMULET = `      lunch, lunchFrom, amulet: amulet === undefined ? -1 : amulet.id,`;

const OLD_RETURN = `    if (plan && plan.carryBack) {
      for (const id of plan.carryBack) {
        const slot = state.items.bag.indexOf(-1);
        if (slot === -1) break;
        state.items.bag[slot] = id;
      }
    }`;

const NEW_RETURN = `    const BAG_SLOT_TYPE = [ITEM_TYPE_LUNCHBOX, ITEM_TYPE_AMULET, ITEM_TYPE_TOOLS, ITEM_TYPE_TOOLS];
    if (plan && plan.carryBack) {
      for (const entry of plan.carryBack) {
        const id = (entry && typeof entry === 'object') ? entry.id : entry;
        const want = (entry && typeof entry === 'object') ? entry.slot : -1;
        let slot = (want >= 0 && want < state.items.bag.length
                    && state.items.bag[want] === -1) ? want : -1;
        if (slot < 0) {
          const type = isType(id, ITEM_TYPE_LUNCHBOX) ? ITEM_TYPE_LUNCHBOX
            : isType(id, ITEM_TYPE_AMULET) ? ITEM_TYPE_AMULET
              : isType(id, ITEM_TYPE_TOOLS) ? ITEM_TYPE_TOOLS : -1;
          for (let i = 0; i < state.items.bag.length; i++) {
            if (state.items.bag[i] === -1 && BAG_SLOT_TYPE[i] === type) { slot = i; break; }
          }
        }
        if (slot < 0) { addHouseItem(id, 1); continue; }
        state.items.bag[slot] = id;
      }
    }`;

let patched = src;
for (const [from, to] of [[OLD_PROVISION, NEW_PROVISION], [OLD_AMULET, NEW_AMULET], [OLD_RETURN, NEW_RETURN]]) {
  if (patched.indexOf(from) < 0) {
    console.log('PATCH ANCHOR NOT FOUND:\n' + from.split('\n')[0]);
    process.exit(1);
  }
  patched = patched.replace(from, to);
}
fs.writeFileSync(PATCHED, patched);

const patchedMod = require(PATCHED);
const p = newEngine(patchedMod);
const rPatch = trip(p.engine, [3, -1, 2002, 2003], [3, 4, -1, -1, 2000, -1, -1, -1]);
console.log('');
console.log('=== 打了建议补丁的副本 ===');
console.log('行李摆好     : ' + label([3, -1, 2002, 2003]));
console.log('出门后       : ' + label(rPatch.afterDepart.bag)
  + '  plan.lunch=' + rPatch.afterDepart.plan.lunch
  + ' carryBack=' + JSON.stringify(rPatch.afterDepart.plan.carryBack));
console.log('回家后       : ' + label(rPatch.afterReturn));
console.log('判定         : ' + ((rPatch.afterReturn[0] === -1 && rPatch.afterReturn[1] === -1
  && rPatch.afterReturn[2] === 2002 && rPatch.afterReturn[3] === 2003)
  ? '道具回到原来的 2/3 号格，0/1 号（便当/护身符）保持空 —— 修好了'
  : '结果仍不对'));
fs.rmSync(p.dir, { recursive: true, force: true });

/* 补丁副本里 plan.carryBack 是对象数组：确认它不会写出 string "[object Object]" */
fs.rmSync(PATCHED, { force: true });
console.log('');
console.log('临时副本已删除：' + PATCHED);
