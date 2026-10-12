#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0（第三批）：访客/剧情/标签类辅助函数（他 3.3 有、我们缺的）。

并入：
  · `tripCarries(plan, itemId)`      —— 这次旅行有没有带某件道具
  · `nextGuestRollAt(t)`             —— 下一次摇访客的时间（他的 8–10 小时随机区间）
  · `normalizeVisitorFood(food)`     —— 把访客食物归一到合法 id
  · `furnitureMoodLabel(mood)`       —— 心境编号 -> 中文标签（面板/调试用）
  · 常量 `VISITOR_ACTION_LIST` / `VISITOR_FOOD_IDS` / `GUEST_ROLL_MIN_SEC` / `GUEST_ROLL_MAX_SEC`

一个**有意的接线**：`tickGuest` 改用 `nextGuestRollAt(t)`。
  · 设了 `FROG_GUEST_ROLL_MIN` / `FROG_GUEST_ROLL_MAX`（他那边用的就是 `FROG_GUEST_ROLL`）-> 走他的随机区间；
  · 没设 -> 仍然是我们 V3.6 起就定下的"每 60 秒摇一次"（`GUEST_ROLL_SEC`），玩家体验不变。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V40-VISITOR-GAP'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[visitor] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[visitor] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


CONSTS = """/* __MARK__ ============ 访客食物 / 访客摇号（他的口径） ============ */

const VISITOR_ACTION_LIST = ((gamedata.tables || {}).visitors || {}).actionList || {};
const VISITOR_FOOD_IDS = Object.keys(VISITOR_ACTION_LIST).map(Number)
  .filter((n) => Number.isFinite(n)).sort((a, b) => a - b);
/* 他的访客摇号区间：8–10 小时。我们默认仍用 GUEST_ROLL_SEC（60 秒一拍），
   只有显式设了 MIN/MAX（或 FROG_GUEST_ROLL）才走他的随机区间。 */
const GUEST_ROLL_MIN_SEC = Number(process.env.FROG_GUEST_ROLL_MIN
  || (process.env.FROG_GUEST_ROLL_MIN || process.env.FROG_GUEST_ROLL_MAX
    ? process.env.FROG_GUEST_ROLL : 0) || 0);
const GUEST_ROLL_MAX_SEC = Number(process.env.FROG_GUEST_ROLL_MAX
  || (process.env.FROG_GUEST_ROLL_MIN || process.env.FROG_GUEST_ROLL_MAX
    ? process.env.FROG_GUEST_ROLL : 0) || 0);

""".replace('__MARK__', MARK)

INNER = """  /* __MARK__ ================= 访客 / 剧情辅助（依赖 state） ================= */

  /** 这次旅行有没有带某件道具（他的命名）。 */
  function tripCarries(plan, itemId) {
    return !!(plan && Array.isArray(plan.carried)
      && plan.carried.some((id) => Number(id) === Number(itemId)));
  }

  /** 下一次摇访客的时间：设了 MIN/MAX 走他的随机区间，否则用我们的一分钟节奏。 */
  function nextGuestRollAt(t) {
    const at = Number(t) || nowSec();
    if (GUEST_ROLL_MIN_SEC > 0 || GUEST_ROLL_MAX_SEC > 0) {
      const min = Math.max(60, GUEST_ROLL_MIN_SEC || 8 * 3600);
      const max = Math.max(min, GUEST_ROLL_MAX_SEC || min);
      return at + randInt(min, max);
    }
    return at + GUEST_ROLL_SEC;
  }

  /** 把访客食物归一到合法 id（他的命名）。 */
  function normalizeVisitorFood(food) {
    const id = Number(food);
    if (VISITOR_FOOD_IDS.indexOf(id) >= 0) return id;
    return VISITOR_FOOD_IDS.length ? Number(VISITOR_FOOD_IDS[0]) : 0;
  }

  /** 心境编号 -> 中文标签（他的命名；面板与调试用）。 */
  function furnitureMoodLabel(mood) {
    return ({
      1: '非常开心', 2: '开心', 3: '平静', 4: '生气', 5: '非常生气',
    })[Number(mood)] || '未知';
  }

""".replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[visitor] 已并入过（%s），跳过' % MARK)
        return 0

    src = sub_once(src, '/* ---------------------------------------------------------------- engine */',
                   CONSTS + '/* ---------------------------------------------------------------- engine */', 'consts')
    src = sub_once(src, '  /* V40-MISC-GAP ============ 他 3.3 的辅助函数（薄封装，行为等价） ============ */',
                   INNER + '  /* V40-MISC-GAP ============ 他 3.3 的辅助函数（薄封装，行为等价） ============ */',
                   'inner')

    # 接线：换天/冷却后的下一次摇号走 nextGuestRollAt
    n = src.count('state.guestNextRollAt = t + GUEST_ROLL_SEC;')
    if n == 0:
        raise SystemExit('[visitor] 没找到 guestNextRollAt 的赋值')
    src = src.replace('state.guestNextRollAt = t + GUEST_ROLL_SEC;',
                      'state.guestNextRollAt = nextGuestRollAt(t);')
    print('[visitor] guestNextRollAt 接线 %d 处' % n)

    write(ENGINE, src)
    print('[visitor] 已补 4 个辅助函数 + 3 个常量（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
