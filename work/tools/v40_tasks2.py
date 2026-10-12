#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0（任务组·修正版）：把他 3.3 的任务相关代码**原样抄进来并接线**。

抄的内容（逐字照搬他的实现）：
  · blueprintTaskId(itemId)      图纸 -> 学习任务号（他引擎里也没有调用点，照抄保持 API 一致）
  · blueprintTaskProgress(id)    任务实际进度（手上有图纸或已做出家具都算完成）
  · markTripTaskProgress(plan, r) 旅行结算记任务（食物->目的地清单、材料、道具）
  · task_client_pro 协议          客户端打点 Map / NoteFriend

**接线（照他的调用点一一对应）**：
  1. `blueprintTaskProgress` -> 接进我们的 `taskProgress(t)`（他的调用点就在同名的进度函数里）
  2. `markTripTaskProgress`  -> 接在回家结算 `const r = state.travel.rewards || rollTripRewards(plan);` 之后
     （这正是他引擎里的位置：`const r = ...; markTripTaskProgress(plan, r);`）
  3. `task_client_pro`       -> 插到真正的协议表里（紧接 task_load 之前）
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V40-TASKS2'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[tasks2] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[tasks2] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


TOPLEVEL = """  /* __MARK__ 顶层的任务计数（v37 那份被插在嵌套作用域里，顶层调用者看不到它们）。 */

  function taskCounter(id) {
    return Math.max(0, Number((state.taskCounters || {})[String(id)]) || 0);
  }

  function addTaskCounter(id, amount) {
    const n = Math.max(0, Number(amount) || 0);
    if (!n) return;
    if (!state.taskCounters || typeof state.taskCounters !== 'object') state.taskCounters = {};
    state.taskCounters[String(id)] = taskCounter(id) + n;
  }

  function completeTaskCounter(id) {
    if (taskCounter(id) < 1) addTaskCounter(id, 1);
  }

""".replace('__MARK__', MARK)

FUNCS = """  /* __MARK__ ============ 任务计数（抄他 3.3 的实现） ============ */

  function blueprintTaskId(itemId) {
    const id = Number(itemId);
    if (id >= 10301 && id <= 10327) return id - 9699;
    if (id === 10401) return 629;
    if (id === 10501) return 630;
    return 0;
  }

  function blueprintTaskProgress(id) {
    const n = Number(id);
    let blueprint = 0;
    if (n >= 602 && n <= 628) blueprint = 10300 + (n - 601);
    else if (n === 629) blueprint = 10401;
    else if (n === 630) blueprint = 10501;
    if (blueprint && hasHouseItem(blueprint)) return 1;
    /* A blueprint is consumed when work starts; owning the finished furniture
       still proves that the corresponding learning task was completed. */
    if (n >= 602 && n <= 628) {
      const type = n - 601;
      const target = CRAFTABLE_BY_TYPE.get(type);
      if (target && state.furniture.owned.indexOf(Number(target.furnitureId)) !== -1) return 1;
    }
    return taskCounter(id);
  }

  function markTripTaskProgress(plan, reward) {
    if (!plan || !reward || reward.stray) return;
    if (reward.goal) completeTaskCounter(102);
    if (reward.area) completeTaskCounter(103);

    /* These five rows are the original food -> destination checklist. The
       destination must be reached with the matching food, not merely bought. */
    const foodAreas = {
      408: ['A_WSOUTH', 'A_WNORTH', 'A_WSOUTH2'],
      409: ['A_EAST', 'A_TAIWAN'],
      410: ['A_SOUTH', 'A_SOUTH2', 'A_EAST'],
      411: ['A_NORTH', 'A_ENORTH'],
    };
    const foodIds = { 408: 4, 409: 5, 410: 15, 411: 16, 412: 33 };
    for (const id of Object.keys(foodIds)) {
      const taskId = Number(id);
      if (!tripCarries(plan, foodIds[taskId])) continue;
      const areas = foodAreas[taskId];
      if (!areas || areas.indexOf(String(reward.area)) !== -1 || taskId === 412) {
        completeTaskCounter(taskId);
      }
    }

    if (reward.museum) completeTaskCounter(501);
    /* A returned specialty/material is one count toward「合适的材料带回家」. */
    const materialCount = (reward.items || []).filter((id) => {
      const item = ITEM_BY_ID.get(Number(id));
      return item && (item.type === ITEM_TYPE_SPECIALTY || item.type === 10 || item.type === 11);
    }).length;
    if (materialCount) addTaskCounter(601, materialCount);
    if (tripCarries(plan, 1)) completeTaskCounter(205);
    if (tripCarries(plan, 2)) completeTaskCounter(302);
    if (tripCarries(plan, 3)) completeTaskCounter(303);
  }

""".replace('__MARK__', MARK)

HANDLER = """    /* 【并入他 3.3】客户端打点：看过地图 / 加过笔友，各记一次任务。 */
    task_client_pro: (d) => {
      const param = String(firstDefined(d, ['param']) || '');
      if (param === 'Map') completeTaskCounter(103);
      if (param === 'NoteFriend') completeTaskCounter(306);
      save();
      return undefined;
    },
"""


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[tasks2] 已并入过（%s），跳过' % MARK)
        return 0

    # 1) 三个函数：放进"辅助函数区"（跟着已有的 V40-PRAY-STORY 标记后面）
    src = sub_once(src,
                   '  /* V40-PRAY-STORY ============ 祈愿分层 / 剧情查找 / 邀约 ============ */',
                   TOPLEVEL + FUNCS + '  /* V40-PRAY-STORY ============ 祈愿分层 / 剧情查找 / 邀约 ============ */',
                   'task funcs')

    # 2) 接线①：任务进度函数（他的调用点）
    src = sub_once(
        src,
        "  function taskProgress(t) {\n"
        "    const type = Number(t && t.type);\n"
        "    if (type === 1) return Number(state.travel.tripCount) || 0;\n"
        "    if (type === 2) return (state.pictures || []).length;\n"
        "    return 0;                        // unmapped on purpose -- see the note above\n"
        "  }",
        "  function taskProgress(t) {\n"
        "    /* 【并入他 3.3】他的进度是**按任务 id** 算的：602..630 是「图纸/学会做它」这一类，\n"
        "       看手上有没有图纸、或有没有已经把这件家具做出来；再与他自己的计数取大者。 */\n"
        "    const taskId = Number(t && t.id);\n"
        "    if (taskId >= 602 && taskId <= 630) {\n"
        "      return Math.max(taskCounter(taskId), blueprintTaskProgress(taskId));\n"
        "    }\n"
        "    const type = Number(t && t.type);\n"
        "    if (type === 1) return Number(state.travel.tripCount) || 0;\n"
        "    if (type === 2) return (state.pictures || []).length;\n"
        "    return 0;                        // unmapped on purpose -- see the note above\n"
        "  }",
        'taskProgress wiring')

    # 3) 接线②：回家结算（他的调用点）
    src = sub_once(
        src,
        "    const r = state.travel.rewards || rollTripRewards(plan);",
        "    const r = state.travel.rewards || rollTripRewards(plan);\n"
        "    /* 【并入他 3.3】他就是在这一行后面记任务的。 */\n"
        "    markTripTaskProgress(plan, r);",
        'return-home wiring')

    # 4) 协议：紧接 task_load 之前（真正的协议表）
    src = sub_once(src, '    task_load: () => {', HANDLER + '    task_load: () => {', 'handler')

    write(ENGINE, src)
    print('[tasks2] 已抄入 3 个函数 + task_client_pro，并接了两处调用点（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
