#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0：补上他 3.3 进度模型用的 16 个存档字段（老档缺失时回填默认值）。

默认值全部取自**跑他的引擎导出的新档**（不是猜的）：
  calendar.rewardVersion=5 / flowerpot.plantingVersion=2 / travel.scheduleVersion=1 /
  furniture.compost.fermenting=null / fertilizerLoads=[] / moodReplaceCount=0 /
  moodReplaceThreshold=0 / moodRecoverAutoFurniture=0 / craft.workClockAt=0 /
  drawingQueued=false / drawingRestUntil=0 / selectedAchieve=null /
  travel.lastCheckAt=0 / lastCheckRoll=null / preparingUntil=0 / furniture.shopStockDay=0

插入点：读档里 `if (Number(s.saveVersion) < SAVE_VERSION) …` 之后（那里正好在归一化老档）。
只补 undefined 的字段，已有值一律不动 —— 不会破坏任何现存存档。
"""
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V40-SAVEFIELDS'

ANCHOR = '  if (Number(s.saveVersion) < SAVE_VERSION) s.saveVersion = SAVE_VERSION;'

BLOCK = """  /* %s 【抄他 3.3】他的进度模型用的字段：老档缺失就回填默认值（已有值不动）。
     默认值取自跑他的引擎导出的新档。 */
  {
    const HIS_DEFAULTS = [
      ['calendar', 'rewardVersion', 5],
      ['flowerpot', 'plantingVersion', 2],
      ['travel', 'scheduleVersion', 1],
      ['travel', 'lastCheckAt', 0],
      ['travel', 'lastCheckRoll', null],
      ['travel', 'preparingUntil', 0],
      ['furniture', 'shopStockDay', 0],
      ['selectedAchieve', null, undefined],
      ['drawingQueued', false, undefined],
      ['drawingRestUntil', 0, undefined],
    ];
    for (const row of HIS_DEFAULTS) {
      const [a, b, value] = row;
      if (b === undefined) {
        if (s[a] === undefined) s[a] = value;
      } else {
        if (!s[a] || typeof s[a] !== 'object') s[a] = {};
        if (s[a][b] === undefined) s[a][b] = value;
      }
    }
    if (s.furniture && typeof s.furniture === 'object') {
      if (s.furniture.moodReplaceCount === undefined) s.furniture.moodReplaceCount = 0;
      if (s.furniture.moodReplaceThreshold === undefined) s.furniture.moodReplaceThreshold = 0;
      if (s.furniture.moodRecoverAutoFurniture === undefined) s.furniture.moodRecoverAutoFurniture = 0;
      if (s.furniture.compost && typeof s.furniture.compost === 'object') {
        if (s.furniture.compost.fermenting === undefined) s.furniture.compost.fermenting = null;
        if (s.furniture.compost.fertilizerLoads === undefined) s.furniture.compost.fertilizerLoads = [];
      }
    }
    if (s.craft && typeof s.craft === 'object'
      && Number.isFinite(Number(s.craft.finishAt)) && (s.craft.workClockAt === undefined)) {
      s.craft.workClockAt = 0;
    }
  }

""".replace('__MARK__', MARK)


def main():
    src = io.open(ENGINE, encoding='utf-8', newline='').read()
    if MARK in src:
        print('[savefields] 已并入过（%s），跳过' % MARK)
        return 0
    if ANCHOR not in src:
        raise SystemExit('[savefields] 找不到读档迁移锚点')
    src = src.replace(ANCHOR, ANCHOR + '\n' + BLOCK, 1)
    io.open(ENGINE, 'w', encoding='utf-8', newline='').write(src)
    print('[savefields] 已补 16 个字段的回填（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
