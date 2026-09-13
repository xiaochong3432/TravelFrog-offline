#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""端口策略测试（存档不会因为"换端口"而变成空档）。

为什么单独测这个：玩家报的"PC 上偶尔会重置存档重新开始"，根因不是存档文件坏了，
而是启动器以前用 pick_port() 在 8080 被占时**悄悄换到 8081/8082...** —— 浏览器按
origin（**含端口**）隔离 localStorage，换个端口就是打开另一个空存档。所以现在的
策略必须满足："宁可停下来说清楚，也不悄悄换地址"。

这里直接用假的 port_is_free / our_server_on 驱动 choose_port()，不启动任何服务，
所以结果是确定的，也不占端口。

    python work/tools/test_port_policy.py
"""
import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.abspath(os.path.join(HERE, "..", "..", "dist"))
assert os.path.isfile(os.path.join(DIST, "play_frog.py")), DIST

spec = importlib.util.spec_from_file_location("play_frog", os.path.join(DIST, "play_frog.py"))
pf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pf)

# 让 last-port.txt 写到临时目录，别动玩家真正的 dist
tmp = tempfile.mkdtemp(prefix="frog-port-")
pf.HERE = tmp

problems = []

# 原始实现（scenario() 会替换掉它们，最后要还原）
REAL_FREE = pf.port_is_free
REAL_OURS = pf.our_server_on


def check(cond, msg):
    if not cond:
        problems.append(msg)


def scenario(free, ours, remember, preferred=8080):
    """free/ours: 端口号集合；remember: 记在文件里的端口（或 None）"""
    pf.port_is_free = lambda p: p in free
    pf.our_server_on = lambda p, timeout=0.8: p in ours
    try:
        os.remove(os.path.join(tmp, pf.REMEMBER_FILE))
    except OSError:
        pass
    if remember is not None:
        with open(os.path.join(tmp, pf.REMEMBER_FILE), "w", encoding="utf-8") as f:
            f.write(str(remember))
    return pf.choose_port(preferred)


# 1) 全新安装，首选端口空闲 -> 就用它
port, how = scenario({8080}, set(), None)
check(port == 8080 and how == "preferred", f"空闲时应直接用 8080，得到 {port}/{how}")

# 2) 8080 上是**我们自己**的服务 -> 复用（不重复启动、也不换端口）
port, how = scenario(set(), {8080}, None)
check(port == 8080 and how == "reuse", f"应在 8080 上复用已有服务，得到 {port}/{how}")

# 3) 8080 被外来程序占用，也没记住别的端口 -> 停下来（**绝不能悄悄换端口**）
port, how = scenario(set(), set(), None)
check(port is None and how == "busy", f"无可沿用时必须返回 busy，得到 {port}/{how}")

# 4) 8080 被占，但上次用的是 8081（空闲）-> 沿用 8081，地址与存档位置不变
port, how = scenario({8081}, set(), 8081)
check(port == 8081 and how == "remembered", f"应沿用记下的 8081，得到 {port}/{how}")

# 5) 8080 被占，记下的 8081 上正是我们的服务 -> 复用它
port, how = scenario(set(), {8081}, 8081)
check(port == 8081 and how == "reuse-remembered", f"应复用 8081 上的服务，得到 {port}/{how}")

# 6) 8080 与记下的 8081 都被占 -> 仍然停下来说清楚
port, how = scenario(set(), set(), 8081)
check(port is None and how == "busy", f"两个都被占时应 busy，得到 {port}/{how}")

# 7) 记下的就是首选端口且被外来占用 -> 不自我循环，直接 busy
port, how = scenario(set(), set(), 8080)
check(port is None and how == "busy", f"记下的端口等于首选且被占时应 busy，得到 {port}/{how}")

# 8) last-port.txt 里是垃圾/越界 -> 当作没有记录
for junk in ("", "abc", "0", "99999", "-1"):
    with open(os.path.join(tmp, pf.REMEMBER_FILE), "w", encoding="utf-8") as f:
        f.write(junk)
    check(pf.remembered_port() is None, f"last-port.txt={junk!r} 应被忽略")

# 9) remember_port 能写回并读出一致
pf.remember_port(8123)
check(pf.remembered_port() == 8123, "remember_port/remembered_port 应往返一致")

# 10) 首选端口空闲时，即使记着别的端口也优先用首选（地址回到玩家书签上的那个）
port, how = scenario({8080, 8081}, set(), 8081)
check(port == 8080 and how == "preferred", f"首选空闲时应回到 8080，得到 {port}/{how}")

# 11) 真的开一个监听，确认 port_is_free 的判断与系统一致（防止测试自己骗自己）
#     用固定区间里第一个空闲端口，而不是 bind(0) 拿到的临时端口：Windows 在刚关闭
#     的临时端口上会有一小段保留期，那属于系统行为，不是这个函数的契约。
import socket
pf.port_is_free = REAL_FREE
pf.our_server_on = REAL_OURS
held = None
for candidate in range(8137, 8160):
    if pf.port_is_free(candidate):
        held = candidate
        break
check(held is not None, "8137-8160 之间应能找到空闲端口")
if held is not None:
    srv = socket.socket()
    srv.bind(("127.0.0.1", held))
    srv.listen(1)
    check(pf.port_is_free(held) is False, f"被占用的 {held} 不该被判为空闲")
    srv.close()
    check(pf.port_is_free(held) is True, f"关闭后 {held} 应判为空闲")

shutil.rmtree(tmp, ignore_errors=True)

if problems:
    print("FAIL: %d 个问题" % len(problems))
    for p in problems:
        print("  - " + p)
    sys.exit(1)
print("PASS: 端口策略 11 项检查通过（不悄悄换端口 = 不悄悄换存档）")
