#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 系统 2+3：口袋（挂兜）与不倒翁（并入「他做的 3.3」）

他的做法（源码 + 运行时实测）：
  · 两张配方表都在客户端数据里：`PocketData`（成品挂兜）、`TumblerData` + `TumblerPathData`
    （不倒翁外观：`bg = bdw_<n>_base`，眼睛图层是 `bdw_eye_<n>`）。
  · 台面 5–9 号位里放**绳 11102** = 做口袋，放**果子 11001** = 不倒翁；再放一件
    **特殊材料**（10101..10108 之一）就做它的专属款，否则做基础款。
  · 口袋基材 = 粗布 10005 + 灯芯草 10004 + 毛边纸 10006（各 1），工具 knife/needle；
    不倒翁基材 = 松木 10001 + 毛边纸 10006（各 1），工具 brush/knife；
    工具用 5 个变体（10201/10211/10221 等）里任意一个都算。
  · 做完：口袋进 `furniture.pocket.list`（id 去重），不倒翁进 `furniture.tumbler.list`
    （带 `layers`）；两者都**不算家具**（不进 `furniture.owned`）。

本补丁是**纯新增**：家具那条路（我们的 style 配方 + `maybeStartCraft`）原样不动，
他的"27 个 type 基材表 / 手工品按动作计时"留给后续的「制作模型」阶段。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V37-POCKET-TUMBLER'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[pocket] 锚点没找到：%s\n%s' % (label, old[:220]))
    if n > 1:
        raise SystemExit('[pocket] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


CONSTS = '''/* %s 【并入他 3.3】口袋（挂兜）与不倒翁：
   两张配方表与外观数据都来自客户端表（PocketData / TumblerData / TumblerPathData）。
   台面 5–9 号位放绳 11102 做口袋、放果子 11001 做不倒翁；再放一件特殊材料就做专属款。 */
const POCKET_BLUEPRINT_ID = 10601;
const POCKET_ROPE_ID = 11102;
const POCKET_TOOLS = ['knife', 'needle'];
const POCKET_BASE_MATERIALS = [
  { item_id: 10005, count: 1 },      // 粗布
  { item_id: 10004, count: 1 },      // 灯芯草
  { item_id: 10006, count: 1 },      // 毛边纸
];
const POCKET_DATA = new Map(Object.entries(gamedata.tables.pocketData || {})
  .map(([id, row]) => [Number(id), row]));
const POCKET_RECIPE_OUTPUTS = {
  common: [22011, 22012, 22013],     // 三种绳编挂兜
  special: new Map([
    [10103, [22021]],                // 棕榈叶 -> 雨林挂兜
    [10104, [22031]],                // 海螺贝 -> 海洋挂兜
  ]),
};
const TUMBLER_BLUEPRINT_ID = 10401;
const TUMBLER_FRUIT_ID = 11001;
const TUMBLER_TOOLS = ['brush', 'knife'];
const TUMBLER_BASE_MATERIALS = [
  { item_id: 10001, count: 1 },      // 松木
  { item_id: 10006, count: 1 },      // 毛边纸
];
const TUMBLER_DATA = new Map((gamedata.tables.tumblerData || [])
  .map((row) => [Number(row.id), row]));
const TUMBLER_PATH_DATA = new Map((gamedata.tables.tumblerPathData || [])
  .map((row) => [Number(row.id), row]));
const TUMBLER_RECIPE_OUTPUTS = {
  common: [20011, 20021, 20031, 20041],   // 胡桃、尖栗、兰栗、橡子
  special: new Map([
    [10101, [20111]],                // 岩纹石 -> 石头
    [10105, [20121]],                // 紫檀木 -> 蹴鞠
    [10104, [20151]],                // 海螺贝 -> 海螺
    [10107, [20131, 20141, 20171]],  // 秋芦荻 -> 南瓜、丑橘、萝卜
  ]),
};
/* 特殊材料 <-> 风格（客户端 CRAFT_SPECIAL_BY_STYLE 的反查；后面「制作模型」阶段会用到） */
const CRAFT_SPECIAL_BY_STYLE = {
  2: 10101, 3: 10102, 4: 10103, 5: 10104, 6: 10105, 7: 10106, 8: 10107, 9: 10108,
  10: 10102, 11: 10108,
};
const CRAFT_STYLE_BY_SPECIAL = new Map(
  Object.entries(CRAFT_SPECIAL_BY_STYLE).map(([style, itemId]) => [Number(itemId), Number(style)]));
const CRAFT_TOOL_VARIANTS = {
  saw: [10201, 10211, 10221], brush: [10202, 10212, 10222], hammer: [10203, 10213, 10223],
  needle: [10204, 10214, 10224], knife: [10205, 10215, 10225],
};
const CRAFT_TOOL_NAMES = { saw: '锯子', brush: '毛刷', hammer: '锤子', needle: '棒针', knife: '小刀' };
''' % MARK

FUNCS = '''  /* %s ---------- 口袋 / 不倒翁：工作台候选与开工 ---------- */
  function craftMissingToolsFor(requirements) {
    const tools = (state.furniture.bench || []).slice(0, 5).map(Number);
    return (requirements || []).filter((tool) => !tools.some((id) =>
      (CRAFT_TOOL_VARIANTS[tool] || []).includes(id)));
  }

  /** 不倒翁外观：`TumblerData.bg = bdw_<n>_base`，眼睛图层取 `bdw_eye_<n>`。 */
  function tumblerAppearance(tumblerId) {
    const def = TUMBLER_DATA.get(Number(tumblerId));
    const match = String((def && def.bg) || '').match(/^bdw_(\\d+)_base$/);
    if (!match) return null;
    const eye = Array.from(TUMBLER_PATH_DATA.values())
      .find((part) => String(part.res) === 'bdw_eye_' + match[1]);
    if (!eye) return null;
    return { id: Number(tumblerId), layers: [{ layer: [Number(eye.id), 0, 0, 0, 0] }] };
  }

  /** 这条配方占的是哪个台面位（结算与替换时要清掉它）。 */
  function craftRecipeSlot(bp) {
    if (!bp) return -1;
    if (Number.isInteger(bp.specialSlot)) return bp.specialSlot;
    if (bp.kind === 'tumbler') {
      return bp.tumblerSpecialSlot >= 0 ? bp.tumblerSpecialSlot : bp.tumblerFruitSlot;
    }
    if (bp.kind === 'pocket') {
      return bp.pocketSpecialSlot >= 0 ? bp.pocketSpecialSlot : bp.pocketRopeSlot;
    }
    return -1;
  }

  /** 台面 5–9 号位里的"特殊材料"选择器（谁在台面上就做谁的专属款，他的做法）。 */
  function benchSpecialSelectors() {
    const bench = state.furniture.bench || [];
    const selectors = [];
    for (let i = 5; i < 10; i += 1) {
      const itemId = Number(bench[i]);
      if (itemId > 0 && CRAFT_STYLE_BY_SPECIAL.has(itemId)) selectors.push({ slot: i, itemId });
    }
    return selectors;
  }

  /** 台面上有没有可做的口袋/不倒翁（绳/果子 + 可选特殊材料 + 对应图纸在背包里）。 */
  function benchPocketTumblerBlueprint(furnitureId, benchSlot) {
    const bench = state.furniture.bench || [];
    const selectors = benchSpecialSelectors();
    const candidates = [];
    const fruitSlot = bench.findIndex((id, i) => i >= 5 && Number(id) === TUMBLER_FRUIT_ID);
    if (fruitSlot >= 0 && getHaveItem(TUMBLER_BLUEPRINT_ID) > 0) {
      const matching = selectors.filter((s) => TUMBLER_RECIPE_OUTPUTS.special.has(s.itemId));
      const recipes = selectors.length
        ? matching.map((s) => ({ slot: s.slot, outputs: TUMBLER_RECIPE_OUTPUTS.special.get(s.itemId) || [] }))
        : [{ slot: -1, outputs: TUMBLER_RECIPE_OUTPUTS.common }];
      for (const recipe of recipes) {
        for (const id of recipe.outputs) {
          if (!TUMBLER_DATA.has(Number(id))) continue;
          candidates.push({
            kind: 'tumbler', itemId: TUMBLER_BLUEPRINT_ID, furnitureId: Number(id), type: 0, style: 0,
            tumblerFruitSlot: fruitSlot, tumblerSpecialSlot: recipe.slot,
          });
        }
      }
    }
    const ropeSlot = bench.findIndex((id, i) => i >= 5 && Number(id) === POCKET_ROPE_ID);
    if (ropeSlot >= 0 && getHaveItem(POCKET_BLUEPRINT_ID) > 0) {
      const matching = selectors.filter((s) => POCKET_RECIPE_OUTPUTS.special.has(s.itemId));
      const recipes = selectors.length
        ? matching.map((s) => ({ slot: s.slot, outputs: POCKET_RECIPE_OUTPUTS.special.get(s.itemId) || [] }))
        : [{ slot: -1, outputs: POCKET_RECIPE_OUTPUTS.common }];
      for (const recipe of recipes) {
        for (const id of recipe.outputs) {
          if (!POCKET_DATA.has(Number(id))) continue;
          candidates.push({
            kind: 'pocket', itemId: POCKET_BLUEPRINT_ID, furnitureId: Number(id), type: 0, style: 0,
            pocketRopeSlot: ropeSlot, pocketSpecialSlot: recipe.slot,
          });
        }
      }
    }
    const targetId = Number(furnitureId) || 0;
    const slot = Number(benchSlot);
    return candidates.find((c) => (!(targetId > 0) || c.furnitureId === targetId)
      && (!(slot >= 0) || craftRecipeSlot(c) === slot)) || null;
  }

  function startCraftFromBench(startedAt, furnitureId, benchSlot) {
    if (state.furniture.craft || furnitureMoodBlocked()) return false;
    const bp = benchPocketTumblerBlueprint(furnitureId, benchSlot);
    if (!bp) return false;
    const info = craftMissing(bp);
    if (!info || info.missing.length || (info.missingTools || []).length) return false;
    const now = Number(startedAt) > 0 ? Number(startedAt) : nowSec();
    const bench = state.furniture.bench;
    if (bp.kind === 'tumbler') {
      const appearance = tumblerAppearance(bp.furnitureId);
      if (!appearance) return false;
      for (const m of TUMBLER_BASE_MATERIALS) addHouseItem(m.item_id, -m.count);
      bench[bp.tumblerFruitSlot] = -1;
      if (bp.tumblerSpecialSlot >= 0) bench[bp.tumblerSpecialSlot] = -1;
      state.furniture.craft = {
        kind: 'tumbler', furnitureId: bp.furnitureId, drawing: TUMBLER_BLUEPRINT_ID,
        materials: TUMBLER_BASE_MATERIALS.map((m) => ({ ...m })), tumbler: appearance,
        startedAt: now, finishAt: now + CRAFT_SECONDS,
      };
    } else {
      for (const m of POCKET_BASE_MATERIALS) addHouseItem(m.item_id, -m.count);
      bench[bp.pocketRopeSlot] = -1;
      if (bp.pocketSpecialSlot >= 0) bench[bp.pocketSpecialSlot] = -1;
      state.furniture.craft = {
        kind: 'pocket', furnitureId: bp.furnitureId, drawing: POCKET_BLUEPRINT_ID,
        materials: POCKET_BASE_MATERIALS.map((m) => ({ ...m })),
        startedAt: now, finishAt: now + CRAFT_SECONDS,
      };
    }
    state.furniture.benchLock = 1;
    save();
    return true;
  }

''' % MARK


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[pocket] 已并入过（%s），跳过' % MARK)
        return 0

    # ---------------------------------------------------------------- 常量
    src = sub_once(
        src,
        'const CRAFT_SECONDS = Math.max(5, Number(process.env.FROG_CRAFT_SEC || 15 * 60));',
        'const CRAFT_SECONDS = Math.max(5, Number(process.env.FROG_CRAFT_SEC || 15 * 60));\n\n' + CONSTS,
        'craft constants')

    # ---------------------------------------------------------------- 存档位
    src = sub_once(src, '      pocket: { showIndex: 0, replaceIndex: 0, clover: 0 },',
                   '      pocket: { showIndex: 0, replaceIndex: 0, clover: 0, list: [] },',
                   'pocket default')
    src = sub_once(src, '      tumbler: { showIndex: 0, replaceIndex: 0 },',
                   '      tumbler: { showIndex: 0, replaceIndex: 0, list: [] },',
                   'tumbler default')

    # ---------------------------------------------------------------- 函数
    src = sub_once(src, '  function benchBlueprint() {', FUNCS + '  function benchBlueprint(furnitureId, benchSlot) {',
                   'helpers before benchBlueprint')

    src = sub_once(
        src,
        '  function benchBlueprint(furnitureId, benchSlot) {\n'
        '    const bench = state.furniture.bench || [];',
        '  function benchBlueprint(furnitureId, benchSlot) {\n'
        '    /* 【并入他 3.3】先看台面上有没有"绳/果子 + 特殊材料"这样的口袋/不倒翁配方。 */\n'
        '    const extra = benchPocketTumblerBlueprint(furnitureId, benchSlot);\n'
        '    if (extra) return extra;\n'
        '    const bench = state.furniture.bench || [];',
        'benchBlueprint extra first')

    src = sub_once(
        src,
        '  function craftMissing() {\n'
        '    const bp = benchBlueprint();\n'
        '    if (!bp) return null;\n'
        '    const mats = craftMaterialsFor(bp.furnitureId) || [];\n'
        '    const missing = mats.filter((m) => getHaveItem(m.item_id) < m.count);\n'
        '    return missing.length ? { bp, missing } : { bp, missing: [] };\n'
        '  }',
        '  function craftMissing(blueprint) {\n'
        '    const bp = blueprint || benchBlueprint();\n'
        '    if (!bp) return null;\n'
        '    /* 【并入他 3.3】口袋/不倒翁有自己的基材与工具。 */\n'
        '    if (bp.kind === \'tumbler\') {\n'
        '      const missing = TUMBLER_BASE_MATERIALS.filter((m) => getHaveItem(m.item_id) < m.count);\n'
        '      return { bp, missing, missingTools: craftMissingToolsFor(TUMBLER_TOOLS) };\n'
        '    }\n'
        '    if (bp.kind === \'pocket\') {\n'
        '      const missing = POCKET_BASE_MATERIALS.filter((m) => getHaveItem(m.item_id) < m.count);\n'
        '      return { bp, missing, missingTools: craftMissingToolsFor(POCKET_TOOLS) };\n'
        '    }\n'
        '    const mats = craftMaterialsFor(bp.furnitureId) || [];\n'
        '    const missing = mats.filter((m) => getHaveItem(m.item_id) < m.count);\n'
        '    return missing.length ? { bp, missing, missingTools: [] } : { bp, missing: [], missingTools: [] };\n'
        '  }',
        'craftMissing kinds')

    # ---------------------------------------------------------------- 台面开工入口
    src = sub_once(
        src,
        '      /* 图纸进台面之后：材料够就自动开工（原版也是服务端看着台面决定、再推 FurnitureFinish） */\n'
        '      const started = maybeStartCraft();',
        '      /* 图纸进台面之后：材料够就自动开工（原版也是服务端看着台面决定、再推 FurnitureFinish）\n'
        '         【并入他 3.3】台面上若是口袋/不倒翁配方（绳 11102 / 果子 11001），走他那条开工路径。 */\n'
        '      const extraBp = benchPocketTumblerBlueprint();\n'
        '      const started = extraBp\n'
        '        ? startCraftFromBench(nowSec(), extraBp.furnitureId, craftRecipeSlot(extraBp))\n'
        '        : maybeStartCraft();',
        'putin_bench hook')

    # ---------------------------------------------------------------- 结算
    src = sub_once(
        src,
        '  function craftTick(ctx, now) {\n'
        '    const craft = state.furniture.craft;\n'
        '    if (!craft || now < Number(craft.finishAt || 0)) return false;\n'
        '    const fid = Number(craft.furnitureId);\n'
        '    state.furniture.craft = null;\n'
        '    state.furniture.benchLock = 0;\n'
        '    if (!Array.isArray(state.furniture.owned)) state.furniture.owned = [];\n'
        '    if (state.furniture.owned.indexOf(fid) === -1) state.furniture.owned.push(fid);\n'
        '    /* 【并入他的 V3】做出一件家具 = 安抚一次。 */\n'
        '    sootheFurnitureMood(FURNITURE_CRAFT_RELIEF, \'craft\');\n'
        '    save();',
        '  function craftTick(ctx, now) {\n'
        '    const craft = state.furniture.craft;\n'
        '    if (!craft || now < Number(craft.finishAt || 0)) return false;\n'
        '    const fid = Number(craft.furnitureId);\n'
        '    state.furniture.craft = null;\n'
        '    state.furniture.benchLock = 0;\n'
        '    /* 【并入他的 V3】做出一件东西 = 安抚一次。 */\n'
        '    sootheFurnitureMood(FURNITURE_CRAFT_RELIEF, \'craft\');\n'
        '    /* 【并入他 3.3】口袋/不倒翁不进家具收藏，进各自的列表。 */\n'
        '    if (craft.kind === \'tumbler\') {\n'
        '      if (!Array.isArray(state.furniture.tumbler.list)) state.furniture.tumbler.list = [];\n'
        '      const entry = craft.tumbler || tumblerAppearance(fid);\n'
        '      if (entry) state.furniture.tumbler.list.push(entry);\n'
        '      save();\n'
        '      if (ctx) {\n'
        '        ctx.push(\'furniture_load_furniture\', handlers.furniture_load_furniture({}));\n'
        '        ctx.push(\'furniture_load_tumbler\', handlers.furniture_load_tumbler());\n'
        '        ctx.push(\'item_load_items\', handlers.item_load_items());\n'
        '      }\n'
        '      return true;\n'
        '    }\n'
        '    if (craft.kind === \'pocket\') {\n'
        '      if (!Array.isArray(state.furniture.pocket.list)) state.furniture.pocket.list = [];\n'
        '      if (state.furniture.pocket.list.indexOf(fid) === -1) state.furniture.pocket.list.push(fid);\n'
        '      save();\n'
        '      if (ctx) {\n'
        '        ctx.push(\'furniture_load_furniture\', handlers.furniture_load_furniture({}));\n'
        '        ctx.push(\'furniture_load_pocket\', handlers.furniture_load_pocket());\n'
        '        ctx.push(\'item_load_items\', handlers.item_load_items());\n'
        '      }\n'
        '      return true;\n'
        '    }\n'
        '    if (!Array.isArray(state.furniture.owned)) state.furniture.owned = [];\n'
        '    if (state.furniture.owned.indexOf(fid) === -1) state.furniture.owned.push(fid);\n'
        '    save();',
        'craftTick kinds')

    # ---------------------------------------------------------------- 载荷
    src = sub_once(
        src,
        '    furniture_load_pocket: () => ({\n'
        '      show_index: state.furniture.pocket.showIndex,\n'
        '      replace_index: state.furniture.pocket.replaceIndex,\n'
        '      list: [],\n'
        '      clover: state.furniture.pocket.clover,\n'
        '    }),',
        '    /* 【并入他 3.3】口袋/不倒翁的真正载荷（原来这里写死空列表）。 */\n'
        '    furniture_load_pocket: () => ({\n'
        '      show_index: state.furniture.pocket.showIndex,\n'
        '      replace_index: state.furniture.pocket.replaceIndex,\n'
        '      list: (state.furniture.pocket.list || []).filter((id) => POCKET_DATA.has(Number(id))),\n'
        '      clover: state.furniture.pocket.clover,\n'
        '    }),',
        'pocket payload')

    src = sub_once(
        src,
        '    furniture_load_tumbler: () => ({\n'
        '      show_index: state.furniture.tumbler.showIndex,\n'
        '      replace_index: state.furniture.tumbler.replaceIndex,\n'
        '      tumbler_list: [],\n'
        '    }),',
        '    furniture_load_tumbler: () => ({\n'
        '      show_index: state.furniture.tumbler.showIndex,\n'
        '      replace_index: state.furniture.tumbler.replaceIndex,\n'
        '      tumbler_list: (state.furniture.tumbler.list || []).map((entry) => ({\n'
        '        id: Number(entry.id),\n'
        '        layers: (entry.layers || []).map((layer) => ({ layer: layer.layer.slice() })),\n'
        '      })),\n'
        '    }),',
        'tumbler payload')

    # 替换时要校验 index 在列表范围内（他的做法）
    src = sub_once(
        src,
        "    furniture_replace_pocket: (d) => finishReplace('pocket', d),",
        '    furniture_replace_pocket: (d) => {\n'
        '      const index = Number(d && d.index);\n'
        '      const count = (state.furniture.pocket.list || []).filter((id) => POCKET_DATA.has(Number(id))).length;\n'
        '      if (!Number.isInteger(index) || index < 1 || index > count) return { code: -1 };\n'
        '      return finishReplace(\'pocket\', d);\n'
        '    },',
        'replace pocket validation')

    # ---------------------------------------------------------------- 老档补齐
    src = sub_once(
        src,
        '      s.furniture.compost.fertility = Math.max(0, Math.min(SOIL_FERTILITY_MAX,\n'
        '        Math.floor(Number(s.furniture.compost.fertility) || 0)));',
        '      s.furniture.compost.fertility = Math.max(0, Math.min(SOIL_FERTILITY_MAX,\n'
        '        Math.floor(Number(s.furniture.compost.fertility) || 0)));\n'
        '      /* 【并入他 3.3】老档没有口袋/不倒翁列表：补空数组；已有的列表过滤掉表里不存在的 id。 */\n'
        '      if (!Array.isArray(s.furniture.pocket.list)) s.furniture.pocket.list = [];\n'
        '      s.furniture.pocket.list = s.furniture.pocket.list\n'
        '        .map((id) => Number(id)).filter((id) => POCKET_DATA.has(id));\n'
        '      s.furniture.pocket.clover = Math.max(0, Math.floor(Number(s.furniture.pocket.clover) || 0));\n'
        '      if (!Array.isArray(s.furniture.tumbler.list)) s.furniture.tumbler.list = [];\n'
        '      s.furniture.tumbler.list = s.furniture.tumbler.list\n'
        '        .map((entry) => (entry && typeof entry === \'object\'\n'
        '          ? { id: Number(entry.id), layers: Array.isArray(entry.layers) ? entry.layers : [] }\n'
        '          : { id: Number(entry), layers: [] }))\n'
        '        .filter((entry) => TUMBLER_DATA.has(Number(entry.id)));',
        'old save pocket/tumbler backfill')

    write(ENGINE, src)
    print('[pocket] 引擎已改：口袋(绳 11102/10601) + 不倒翁(果子 11001/10401) 可做、可收藏（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
