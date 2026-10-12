#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补上他客户端剩下的两处：季节数组不再 .slice()、全屏分支简化。"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLIENT = os.path.join(ROOT, 'work', 'build', 'v4_client', 'main.min.js')

EDITS = [
    ('t=(Tabikaeru.DefineExtra.SeasonCover[e]||[]).slice();',
     't=Tabikaeru.DefineExtra.SeasonCover[e]||[];'),
    ('t=(Tabikaeru.DefineExtra.SeasonPartical[e]||[]).slice();',
     't=Tabikaeru.DefineExtra.SeasonPartical[e]||[];'),
    ('t=(Tabikaeru.DefineExtra.SeasonSpine[e]||[]).slice();',
     't=Tabikaeru.DefineExtra.SeasonSpine[e]||[];'),
    # 全屏分支：他去掉"顺便改舞台尺寸并广播 uiresize"的那一串，直接返回 [2]
    ('return 0==GameConfig.fullScreen?(t.stageWidth=this.stage.stageWidth,'
     't.stageHeight=this.stage.stageHeight,this.stage.dispatchEventWith("uiresize"),[2])',
     'return 0==GameConfig.fullScreen?[2]'),
]


def main():
    raw = io.open(CLIENT, encoding='utf-8', newline='').read()
    eol = '\r\n' if '\r\n' in raw else '\n'
    text = raw.replace('\r\n', '\n')
    done = 0
    problems = []
    for old, new in EDITS:
        if old in text and text.count(old) >= 1:
            text = text.replace(old, new)
            done += 1
            print('  应用: %s' % old[:60])
        elif new in text:
            print('  已是: %s' % new[:60])
        else:
            problems.append(old[:70])
    if done:
        io.open(CLIENT, 'w', encoding='utf-8', newline='').write(text.replace('\n', eol))
        print('已写回客户端 %d B（改了 %d 处）' % (os.path.getsize(CLIENT), done))
    if problems:
        print('未命中: %s' % problems)
    return 0


if __name__ == '__main__':
    sys.exit(main())
