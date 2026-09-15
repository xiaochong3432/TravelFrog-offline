#!/usr/bin/env python3
"""Fix two real bugs found by reading the client.

BUG 1 -- 喂特产给小伙伴 -> 吃坏肚子 (infinite reload).
   The client's feed handler is:
       t.travelModel.sendGuestServed(e);   // sends guest_serve
       t.friendFeedBack(e);                // reads getGuestData().id
   and friendFeedBack does `getFriendTaste(getGuestData().id, itemId)` whose body is
       var o = CharaDB.src.data.find(function (e) { return e.id === t; });
       return { friend: o, feeling: o.taste[a] };
   With the ORIGINAL networked server the `guest_load{id:-1}` push arrived long after
   friendFeedBack had run, so the id was still 0..2. Our in-page engine answers
   SYNCHRONOUSLY and cleared the visitor inside guest_serve, so the client looked up
   id -1, `find` returned undefined and `o.taste[a]` threw -> the global onerror shows
   「呱呱吃坏肚子了」 and reloads.
   Fix: keep the visitor present with `served = true` and a short farewell window; the
   existing tickGuest already clears a guest whose expire_time has passed, so the
   semantics ("they leave once fed") stay, only the timing matches a network push.

BUG 3 -- 解锁全部明信片之后相册全是白的，点开吃坏肚子.
   `unlock_pictures` (and `add_picture`) pushed `{id, read, new}` with NO `pic_id`.
   `pic_id` is the Picture-table row that selects the ARTWORK -- `withLayers()` looks it
   up as `pictureLayers[String(p.pic_id)]`, so a row without it renders blank -- and the
   album handle `id` must stay unique, not be the Picture-table id.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

P = str(PROJECT_ROOT) + "/work/run/engine/index.js"
src = io.open(P, encoding="utf-8").read()
edits = []


def sub(old, new, label):
    global src
    n = src.count(old)
    assert n == 1, "%s: expected 1 match, found %d" % (label, n)
    src = src.replace(old, new)
    edits.append(label)


# ---------------------------------------------------------------- BUG 1
sub("""      addHouseItem(itemId, -1);
      const feeling = guestFeeling(g.id, itemId);
      const active = nowSec() - (g.startAt || nowSec());""",
    """      if (g.served) return undefined;          // never pay for the same visit twice
      addHouseItem(itemId, -1);
      const feeling = guestFeeling(g.id, itemId);
      const active = nowSec() - (g.startAt || nowSec());""",
    "guest_serve: refuse a second feeding")

sub("""      state.guestFeeds = (state.guestFeeds || 0) + 1;
      g.served = true;
      // the visitor leaves after being served
      state.guest = null;
      state.guestBonusTickets = 0;
      state.guestCoolUntil = nowSec() + GUEST_COOL_SEC;
      state.guestNextRollAt = 0;
      save();""",
    """      state.guestFeeds = (state.guestFeeds || 0) + 1;
      g.served = true;
      /* The visitor still LEAVES after being fed, but not instantly: the client runs
         `sendGuestServed(e); friendFeedBack(e);` back to back, and friendFeedBack reads
         `getGuestData().id` to look the friend up in the Character table
         (`data.find(e => e.id === id)`) -- with id already -1 that lookup returns
         undefined and `o.taste[a]` throws 「呱呱吃坏肚子了」. Against the networked
         server the clearing push simply arrived later; we keep them for a short
         farewell window so the same sequence stays valid. tickGuest clears them when
         expire_time passes. */
      g.expire_time = nowSec() + GUEST_FAREWELL_SEC;
      state.guestBonusTickets = 0;
      state.guestCoolUntil = nowSec() + GUEST_FAREWELL_SEC + GUEST_COOL_SEC;
      state.guestNextRollAt = 0;
      save();""",
    "guest_serve: farewell window instead of clearing instantly")

# the constant
sub("""  function pickGuest() {""",
    """  /* 【自设计】 how long a fed visitor stays before leaving (seconds). Long enough for
     the client's two feedback popups, short enough that the visit still visibly ends. */
  const GUEST_FAREWELL_SEC = 20;

  function pickGuest() {""",
    "GUEST_FAREWELL_SEC constant")

# ---------------------------------------------------------------- BUG 3
sub("""      case 'unlock_pictures': {
        let added = 0;
        for (const id of PICTURE_IDS) {
          if (!state.pictures.some((p) => p && p.id === id)) { state.pictures.push({ id, read: 0, new: 1 }); added++; }
        }""",
    """      case 'unlock_pictures': {
        let added = 0;
        for (const picId of PICTURE_IDS) {
          /* `id` is the album's own unique handle; `pic_id` is the Picture-table row
             that selects the artwork. Pushing only `id` (as this used to) left
             `pic_id` undefined, so `withLayers()` found no composition and every card
             rendered blank -- and opening one then threw. */
          if (state.pictures.some((p) => p && p.pic_id === picId)) continue;
          if (state.albumPending.some((p) => p && p.pic_id === picId)) continue;
          state.pictureSeq = (state.pictureSeq || 0) + 1;
          state.pictures.push({ id: state.pictureSeq, pic_id: Number(picId), read: 0, new: 1 });
          added++;
        }""",
    "unlock_pictures: real pic_id + unique handle")

sub("""      case 'add_picture': {
        const id = arg(0, -1);
        if (id < 0) return bad('用法: add_picture ID');
        if (!state.pictures.some((p) => p && p.id === id)) state.pictures.push({ id, read: 0, new: 1 });""",
    """      case 'add_picture': {
        /* The argument is a Picture-table id, so it goes into `pic_id` (see the note in
           unlock_pictures); the album handle is allocated separately. */
        const picId = arg(0, -1);
        if (picId < 0) return bad('用法: add_picture ID');
        if (!state.pictures.some((p) => p && p.pic_id === picId)) {
          state.pictureSeq = (state.pictureSeq || 0) + 1;
          state.pictures.push({ id: state.pictureSeq, pic_id: picId, read: 0, new: 1 });
        }""",
    "add_picture: real pic_id + unique handle")

io.open(P, "w", encoding="utf-8").write(src)
print("applied:", ", ".join(edits))
