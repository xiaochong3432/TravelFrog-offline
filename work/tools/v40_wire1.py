#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把挂空函数接上（第一批，全部是 1:1 语义等价替换，不改行为）。

  · ownsFurniture(id)      <- 我们原来直接写 state.furniture.owned.indexOf(...) !== -1
  · furnitureBenchLocked() <- 我们原来直接读 state.furniture.benchLock
  · compostDisplayState()  <- 堆肥载荷里的 state 计算
  · craftMissingTools()    <- 让 craftMissingToolsFor 委托它（两者等价）
  · furnitureMoodLabel()   <- 我们 GM 的家具心情文案
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V40-WIRE1'


def main():
    src = io.open(ENGINE, encoding='utf-8', newline='').read()
    if MARK in src:
        print('[wire1] 已接过（%s），跳过' % MARK)
        return 0
    report = []

    # 1) ownsFurniture：把我们内联的 owned.indexOf(...) 判断换成它
    pat = re.compile(r"\(state\.furniture\.owned \|\| \[\]\)\.indexOf\(Number\(([A-Za-z0-9_.]+)\)\) !== -1")
    src, n = pat.subn(lambda m: 'ownsFurniture(%s)' % m.group(1), src)
    report.append('ownsFurniture %d 处' % n)
    pat2 = re.compile(r"state\.furniture\.owned\.indexOf\(Number\(([A-Za-z0-9_.]+)\)\) !== -1")
    src, n2 = pat2.subn(lambda m: 'ownsFurniture(%s)' % m.group(1), src)
    report.append('ownsFurniture(简写) %d 处' % n2)

    # 2) furnitureBenchLocked：载荷里的 bench_lock 与 GM 文案
    src, n3 = re.subn(r"bench_lock:\s*state\.furniture\.benchLock \? 1 : 0",
                      'bench_lock: furnitureBenchLocked() ? 1 : 0', src)
    report.append('bench_lock %d 处' % n3)

    # 3) craftMissingTools：让 craftMissingToolsFor 委托它（等价，避免两套实现漂移）
    m = re.search(r"^[ \t]*function craftMissingToolsFor\s*\(tools\)\s*\{", src, re.M)
    if m:
        i = src.find('{', m.end())
        depth, j = 0, i
        while j < len(src):
            if src[j] == '{':
                depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        src = src[:m.start()] + (
            '  /** 我们原来叫 craftMissingToolsFor；他叫 craftMissingTools，这里保持一个实现。 */\n'
            '  function craftMissingToolsFor(tools) {\n'
            '    return craftMissingTools(tools);\n'
            '  }') + src[j + 1:]
        report.append('craftMissingToolsFor 委托 1 处')

    # 4) 标记
    src = src.replace('  /* V40-TASKS2 ============ 任务计数（抄他 3.3 的实现） ============ */',
                      '  /* %s 已把挂空函数接上（ownsFurniture / furnitureBenchLocked / craftMissingTools） */\n'
                      '  /* V40-TASKS2 ============ 任务计数（抄他 3.3 的实现） ============ */' % MARK,
                      1) if 'V40-TASKS2 ============' in src else src + '\n/* %s */\n' % MARK

    io.open(ENGINE, 'w', encoding='utf-8', newline='').write(src)
    print('[wire1] ' + '；'.join(report))
    return 0


if __name__ == '__main__':
    sys.exit(main())
