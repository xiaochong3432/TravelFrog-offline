#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0 收尾：把 4 个字段补进**默认存档**（之前只做了老档回填，新档里没有）。

  · craft.workClockAt        他手工品工作时钟的时间戳
  · drawingQueued            绘本邀约是否已排队
  · drawingRestUntil         伙伴回家后的休息截止
  · selectedAchieve          当前选中的成就

做法：在默认 state 字面量里就地加字段（锚点唯一性校验，找不到就报错不写）。
"""
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V40-SAVEFIELDS2'


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[sf2] 锚点没找到：%s\n%s' % (label, old[:160]))
    if n > 1:
        raise SystemExit('[sf2] 锚点出现 %d 次：%s' % (n, label))
    return text.replace(old, new, 1)


def main():
    src = io.open(ENGINE, encoding='utf-8', newline='').read()
    if MARK in src:
        print('[sf2] 已补过（%s），跳过' % MARK)
        return 0
    done = []

    # craft.workClockAt
    for anchor in ('craft: { wishes: [], stamps: [], pending: [], seq: 0 }',
                   'craft: { wishes: [], stamps: [], pending: [], seq: 0,'):
        if src.count(anchor) == 1:
            src = src.replace(anchor, 'craft: { wishes: [], stamps: [], pending: [], seq: 0, workClockAt: 0 }'
                              if anchor.endswith('}') else
                              anchor + ' workClockAt: 0', 1)
            done.append('craft.workClockAt')
            break

    # drawingQueued / drawingRestUntil / selectedAchieve：
    #   实测这三个字段写进默认存档后，会被引擎启动时的深拷贝变成 `{}`（false/0/null 都变空对象），
    #   而它们属于他那些**我们没并的模块**（绘本排队、成就选择），我们的代码一处都不读，
    #   所以这里**不写默认值**，免得在新档里留下错类型的字段。

    io.open(ENGINE, 'w', encoding='utf-8', newline='').write(src)
    print('[sf2] 已补入默认存档：%s' % (done or '（没找到任何锚点）'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
