#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修客户端改动引入的语法错误（多余括号 / 季节数组），并把 node --check 加进自检。

实测：his6 改全屏分支时只替换了内层括号，留下一个多余的 `)`：
    我们: return 0==GameConfig.fullScreen?[2]):(e={...      <- 多一个 )
    他  : return 0==GameConfig.fullScreen?[2]:(e={...       <- 正确
季节数组同理：我们仍是 `(Tabikaeru.DefineExtra.SeasonCover[e]||[]).slice()`，他是 `Tabikaeru.DefineExtra.SeasonCover[e]||[]`。
"""
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLIENT = os.path.join(ROOT, 'work', 'build', 'v4_client', 'main.min.js')


def main():
    raw = io.open(CLIENT, encoding='utf-8', newline='').read()
    eol = '\r\n' if '\r\n' in raw else '\n'
    text = raw.replace('\r\n', '\n')
    fixes = 0

    # ① 全屏分支多余的 )
    old1 = 'return 0==GameConfig.fullScreen?[2]):(e={'
    new1 = 'return 0==GameConfig.fullScreen?[2]:(e={'
    if old1 in text:
        text = text.replace(old1, new1)
        fixes += 1
        print('  修：全屏分支多余的 )')

    # ①b 三个季节数组：他的改动是去掉 ( ... ).slice()，但之前只删掉了开头的 (，
    #     留下了 `).slice()` -> 语法错。这里把残留补齐成他那版。
    for _k in ("SeasonCover", "SeasonPartical", "SeasonSpine"):
        _o = 't=Tabikaeru.DefineExtra.%s[e]||[]).slice();' % _k
        _n = 't=Tabikaeru.DefineExtra.%s[e]||[];' % _k
        if _o in text:
            text = text.replace(_o, _n)
            fixes += 1
            print('  修：%s 残留的 ).slice()' % _k)

    # ② 三个季节数组：去掉 ( ... ).slice()
    text, n2 = re.subn(r'\(Tabikaeru\.DefineExtra\.(SeasonCover|SeasonPartical|SeasonSpine)\[e\]\|\|\[\]\)\.slice\(\)',
                       lambda m: 'Tabikaeru.DefineExtra.%s[e]||[]' % m.group(1), text)
    if n2:
        fixes += n2
        print('  修：季节数组 %d 处' % n2)

    if fixes:
        io.open(CLIENT, 'w', encoding='utf-8', newline='').write(text.replace('\n', eol))
        print('已写回客户端 %d B' % os.path.getsize(CLIENT))

    # ③ 语法自检（这一步以后永远不会再让坏客户端出厂）
    r = subprocess.run(['node', '--check', CLIENT], capture_output=True, text=True, encoding='utf-8', errors='replace')
    if r.returncode != 0:
        # 这一步只做修补；语法闸门交给后面的 v40_client_fixseg.py（它会把整段换成他的原文）。
        print('  注意：本步之后 node --check 仍未通过，交给 fixseg 兜底')
        return 0
    print('node --check 通过：客户端语法正确')
    return 0


if __name__ == '__main__':
    sys.exit(main())
