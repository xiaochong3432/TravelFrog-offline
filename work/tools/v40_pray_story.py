#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0（第四批）：祈愿分层 / 剧情查找 / 邀约（他 3.3 有、我们缺的顶层函数）。

并入（都是纯函数，不改既有行为）：
  · validPrayLayer / pickPrayLayer / choosePrayLayer —— 祈愿物的"身体/图案"分层挑选
  · storyClientId / findStory —— 剧情表 id 与本地剧情簿的查找
  · leaveDrawingInvitation —— 访客离开时留下"友情绘本"邀约（冷却 + 概率 + 指定或随机伙伴）

另外顺带修正上一份缺口清单的两处误报：
  `loadAt` 与 `rememberLocal` 是他函数内部的**局部闭包**（分别属于堆肥装载与他自己的
  照片挑选流程），不是顶层 API —— 我们这边的等价逻辑已在 `refreshCompost` / `tvPhotos` 里，
  不需要、也不应该造一个同名全局函数。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V40-PRAY-STORY'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[pray] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[pray] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


BLOCK = """  /* __MARK__ ============ 祈愿分层 / 剧情查找 / 邀约 ============ */

  /** 这个 id 是不是合法的祈愿"层"（身体/图案表里有它）。 */
  function validPrayLayer(id) {
    const n = Number(id);
    return Number.isFinite(n) && !!((gamedata.tables.prayBodyData || {})[String(n)]);
  }

  /** 把 "1,2,3" 这样的层列表拆开、只留下合法的那些。 */
  function pickPrayLayer(v) {
    return String(v == null ? '' : v).split(',')
      .map((s) => Number(String(s).trim()))
      .filter((n) => validPrayLayer(n));
  }

  /** 从多组候选层里挑一层：从最后一组往前找，找到就随机取一个（他的口径）。 */
  function choosePrayLayer(parts) {
    const rows = Array.isArray(parts) ? parts.slice().reverse() : [];
    for (const raw of rows) {
      const list = pickPrayLayer(raw);
      if (list.length) return list[randInt(0, list.length - 1)];
    }
    return 0;
  }

  /** 剧情在客户端那边用的 id：优先 storyid，其次 id。 */
  function storyClientId(story) {
    const tableId = Number(story && story.storyid);
    return tableId > 0 ? tableId : Number(story && story.id) || 0;
  }

  /** 在本地剧情簿里找一条剧情（按内部 id 或客户端 id 都认）。 */
  function findStory(id) {
    const wanted = Number(id);
    const list = (state.storyBook && state.storyBook.list) || [];
    return list.find((story) => Number(story.id) === wanted || storyClientId(story) === wanted);
  }

  /** 访客离开时留下"友情绘本"邀约：冷却到点 + 按概率 + 指定或随机一位伙伴。 */
  function leaveDrawingInvitation(guestId, t) {
    const d = state.drawing;
    if (!d || (d.state !== 0 && d.state !== undefined && d.state !== null)) return false;
    const at = Number(t || nowSec());
    if (Number(state.drawingNextRollAt) > at) return false;
    state.drawingNextRollAt = at + DRAWING_CHECK_COOLDOWN_SEC;
    if (Math.random() * 100 >= DRAWING_CHANCE) return false;
    const guests = drawingGuestIds();
    if (!guests.length) return false;
    let guest = Number(guestId);
    if (guests.indexOf(guest) === -1) guest = guests[randInt(0, guests.length - 1)];
    d.state = 1;
    d.guest = guest;
    d.bag = Array.isArray(d.bag) ? d.bag.map(() => -1) : [-1, -1, -1, -1];
    d.invitationAccepted = false;
    return true;
  }

""".replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[pray] 已并入过（%s），跳过' % MARK)
        return 0
    src = sub_once(src, '  /* V40-VISITOR-GAP ================= 访客 / 剧情辅助（依赖 state） ================= */',
                   BLOCK + '  /* V40-VISITOR-GAP ================= 访客 / 剧情辅助（依赖 state） ================= */',
                   'pray block')
    write(ENGINE, src)
    print('[pray] 已补 6 个函数（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
