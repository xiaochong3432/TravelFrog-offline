#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0（最终）：把他 3.3 里"低风险、语义等价的辅助函数"补齐。

这一批都是**薄封装/等价物**，不改任何既有行为（不动现有协议、不新增存档字段）：
  hasHouseItem / ownsFurniture / furnitureBenchLocked / craftMissingTools /
  craftSpecialMaterialFor / benchBlueprintCandidates / compostDisplayState / ensureCompostState /
  fillWishArt / finishedWishCount / finishedStampCount / done / doneStamps /
  tvTripTravelerSlot 已在 v41 并过

其中祈愿那 5 个（fillWishArt / finishedWishCount / finishedStampCount / done / doneStamps）是把
我们**内联**在 advanceCraft 里的逻辑抽成他那样的具名函数，行为完全不变。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V40-MISC-GAP'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[misc] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[misc] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


BLOCK = r'''  /* __MARK__ ============ 他 3.3 的辅助函数（薄封装，行为等价） ============ */

  /** 家里有没有某件东西（他的命名；我们原来直接调 getHaveItem）。 */
  function hasHouseItem(itemId, count) {
    const need = Math.max(1, Number(count) || 1);
    return getHaveItem(Number(itemId)) >= need;
  }

  /** 这件家具是否已经拥有（他的命名）。 */
  function ownsFurniture(furnitureId) {
    const list = state.furniture.owned || [];
    return list.some((id) => Number(id) === Number(furnitureId));
  }

  /** 工作台是否正锁着（他的命名）。 */
  function furnitureBenchLocked() {
    return !!state.furniture.benchLock;
  }

  /** 这套工具还缺哪几件（他的命名；我们叫 craftMissingToolsFor）。 */
  function craftMissingTools(tools) {
    return craftMissingToolsFor(tools);
  }

  /** 某个风格对应的特殊材料（他的命名；我们表叫 CRAFT_SPECIAL_BY_STYLE）。 */
  function craftSpecialMaterialFor(style) {
    const id = CRAFT_SPECIAL_BY_STYLE[Number(style)];
    return id === undefined ? 0 : Number(id);
  }

  /** 工作台上所有可做的活（他的命名）：普通家具 + 口袋 + 不倒翁，按 benchBlueprint 的口径。 */
  function benchBlueprintCandidates() {
    const out = [];
    const plain = benchBlueprint();
    if (plain) out.push(plain);
    const extra = benchPocketTumblerBlueprint();
    if (extra && !out.some((bp) => Number(bp.furnitureId) === Number(extra.furnitureId))) out.push(extra);
    return out;
  }

  /** 堆肥载荷（他的命名；我们叫 compostPayload）。 */
  function compostDisplayState() {
    return compostPayload();
  }

  /** 保证堆肥状态形状正确（他的命名；我们 refreshCompost 里已内联同一件事）。 */
  function ensureCompostState() {
    const c = state.furniture.compost || (state.furniture.compost = {});
    c.boxes = Array.from({ length: 6 }, (_, i) => Number((c.boxes || [])[i]) || 0);
    c.fertility = Math.max(0, Math.min(SOIL_FERTILITY_MAX, Number(c.fertility) || 0));
    if (!Array.isArray(c.list) || !c.list.length) c.list = [21000];
    return c;
  }

  /** 祈愿物做完时的图案落定（他抽成具名函数；我们原来是内联在 advanceCraft 里）。 */
  function fillWishArt(wish) {
    const bodyIds = Object.keys((gamedata.tables || {}).prayBodyData || {});
    if (bodyIds.length && wish && !wish.body_id) {
      wish.body_id = Number(bodyIds[randInt(0, bodyIds.length - 1)]);
    }
    return wish;
  }

  /** 已完成（state > 3）的祈愿物数量 / 已盖好的印章数量（他的命名）。 */
  function finishedWishCount() {
    const c = state.craft || {};
    return (c.wishes || []).filter((w) => Number(w && w.state) > 3).length;
  }

  function finishedStampCount() {
    const c = state.craft || {};
    return (c.stamps || []).filter((s) => Number(s && s.state) > 3).length;
  }

  /** 他用来判断"这件是不是已经做完"的小工具（我们内联写的 state > 3）。 */
  function done(job) {
    return Number(job && job.state) > 3;
  }

  function doneStamps() {
    const c = state.craft || {};
    return (c.stamps || []).filter((s) => done(s));
  }

'''.replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[misc] 已并入过（%s），跳过' % MARK)
        return 0
    src = sub_once(src, '  function tickGuest(ctx, t) {',
                   BLOCK + '  function tickGuest(ctx, t) {', 'misc block')
    write(ENGINE, src)
    print('[misc] 已补 13 个辅助函数（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
