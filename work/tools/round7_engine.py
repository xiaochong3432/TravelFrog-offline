#!/usr/bin/env python3
"""Round 7 engine work:

  #3 the 大冒险 (museum adventure) is switched OFF at the player's request, and the museum
     图鉴 is unlocked instead -- it was the only way to earn those postcards, so dropping
     the event without this would leave the 图鉴 permanently empty.
  #5 two new save-editor commands: `unlock_all` (图鉴 + 百科 + 博物馆) and `all_furniture`.
     The 百科 also gets a state flag so "unlock everything" can override the
     grown/brought-home derivation.
"""
import io

P = r"H:\AI\frog\work\run\engine\index.js"
src = io.open(P, encoding="utf-8").read()
edits = []


def sub(old, new, label):
    global src
    n = src.count(old)
    assert n == 1, "%s: expected 1 match, found %d" % (label, n)
    src = src.replace(old, new)
    edits.append(label)


# ---------------------------------------------------------------- #3a: window closed
sub("""    museumday_load: (d, ctx) => {
      const s = ensureMuseumday();
      s.endTime = mdEnd();
      save();
      return mdPayload(s);
    },""",
    """    museumday_load: (d, ctx) => {
      const s = ensureMuseumday();
      /* 大冒险暂时关掉了（玩家反馈"太麻烦"，改为开放博物馆图鉴）。`end_time` is the
         whole switch for the client -- see mdPayload -- so returning 0 hides the entry
         and stops it arming its activity timer. The implementation below is intact:
         set MUSEUM_DAY_ENABLED back to true to bring the event back. */
      s.endTime = MUSEUM_DAY_ENABLED ? mdEnd() : 0;
      save();
      return mdPayload(s);
    },""",
    "museumday window follows the enable flag")

sub("""const MD_MUSEUMS = [1, 2, 3, 4];""",
    """/* 大冒险 (museum adventure) master switch. The player asked for it to go away for now
   and for the museum 图鉴 to be unlocked instead; flipping this to true restores it. */
const MUSEUM_DAY_ENABLED = false;
const MD_MUSEUMS = [1, 2, 3, 4];""",
    "MUSEUM_DAY_ENABLED flag")

# --------------------------------------------------- #3b / #5: unlocks + editor commands
sub("""  /* The client's ItemDB.get() has NO null guard, so pushing an item_update for an""",
    """  /* ------------------------------------------------------------- unlocks
     Granting these is what the player asked for in place of the museum adventure: the
     图鉴 (纪念品/特产) and the museum pages are driven by the SAME lists that a trip would
     fill, and the 百科 is derived from the flowers actually grown or brought home --
     `state.encyAll` overrides that derivation when everything is unlocked. */
  function unlockHandbook(ctx) {
    const cols = Object.keys(((gamedata.tables || {}).Collection) || {})
      .map(Number).filter((n) => Number.isFinite(n));
    const spes = SPECIALTY_IDS.slice();
    for (const id of cols) {
      if (state.handbook.collections.indexOf(id) === -1) state.handbook.collections.push(id);
    }
    for (const id of spes) {
      if (state.handbook.specialtys.indexOf(id) === -1) state.handbook.specialtys.push(id);
    }
    return { collections: state.handbook.collections.length, specialtys: state.handbook.specialtys.length };
  }

  /** Every museum's postcards and collectibles, so the 图鉴 pages are complete. */
  function unlockMuseum() {
    const rows = (gamedata.tables && gamedata.tables.museumData) || {};
    let pics = 0;
    let cols = 0;
    for (const key of Object.keys(rows)) {
      const m = rows[key];
      if (!m) continue;
      for (const raw of (Array.isArray(m.pic_id) ? m.pic_id : [])) {
        const pic = Number(raw);
        if (state.pictures.some((p) => p && p.pic_id === pic)) continue;
        if (state.albumPending.some((p) => p && p.pic_id === pic)) continue;
        state.pictureSeq = (state.pictureSeq || 0) + 1;
        state.pictures.push({ id: state.pictureSeq, pic_id: pic, read: 0, new: 0 });
        pics += 1;
      }
      for (const raw of String(m.collection_id == null ? '' : m.collection_id).split(',')) {
        const c = Number(String(raw).trim());
        if (!Number.isFinite(c)) continue;
        if (state.handbook.collections.indexOf(c) === -1) {
          state.handbook.collections.push(c);
          cols += 1;
        }
      }
    }
    state.museumUnlocked = true;
    return { pictures: pics, collections: cols };
  }

  /** Every furniture row the game ships, so the 家具 book is complete. */
  function unlockFurniture() {
    const rows = (gamedata.tables && gamedata.tables.furnitureData) || {};
    if (!Array.isArray(state.furniture.owned)) state.furniture.owned = [];
    let added = 0;
    for (const key of Object.keys(rows)) {
      const row = rows[key];
      const id = Number(row && (row.id !== undefined ? row.id : key));
      if (!Number.isFinite(id)) continue;
      if (state.furniture.owned.indexOf(id) === -1) {
        state.furniture.owned.push(id);
        added += 1;
      }
    }
    return { furniture: added, total: state.furniture.owned.length };
  }

  /* The client's ItemDB.get() has NO null guard, so pushing an item_update for an""",
    "unlock helpers")

# encyclopedia: honour the flag
sub("""  function encyclopediaPayload() {
    const grown = (state.flowerpot.grown || []).map(""",
    """  function encyclopediaPayload() {
    /* `unlock_all` sets this: report every species in the table instead of deriving the
       list from what the player happened to grow or bring home. */
    if (state.encyAll) {
      const ids = ENC_ROWS.map((e) => Number(e.id)).filter((n) => Number.isFinite(n));
      const uniq = ids.filter((v, i) => ids.indexOf(v) === i).sort((a, b) => a - b);
      return {
        unlock_list: uniq,
        unlock_desc: uniq.map((id) => ({
          id,
          list: Object.keys((ENC.desc || {})[String(id)] || {}).map(Number)
            .filter((n) => !isNaN(n)),
        })),
        show_sub: ENC_ROWS.map((e) => ({ id: Number(e.id), sub_id: Number(e.sub_id) }))
          .filter((v, i, arr) => arr.findIndex((x) => x.id === v.id) === i),
      };
    }
    const grown = (state.flowerpot.grown || []).map(""",
    "encyclopediaPayload honours encyAll")

# GM commands
sub("""      case 'unlock_pictures': {""",
    """      /* 解锁全部图鉴与百科 (and the museum, which is the replacement for 大冒险). */
      case 'unlock_all': {
        const h = unlockHandbook(ctx);
        const m = unlockMuseum();
        state.encyAll = true;
        save(); refresh();
        return ok('图鉴：纪念品 ' + h.collections + ' / 特产 ' + h.specialtys
          + '；博物馆新增明信片 ' + m.pictures + ' 张、藏品 ' + m.collections
          + ' 件；百科已全部解锁');
      }

      /* 获得全部家具 */
      case 'all_furniture': {
        const f = unlockFurniture();
        save(); refresh();
        return ok('家具已全部解锁：新增 ' + f.furniture + ' 件，共 ' + f.total + ' 件');
      }

      case 'unlock_museum': {
        const m = unlockMuseum();
        save(); refresh();
        return ok('博物馆图鉴：新增明信片 ' + m.pictures + ' 张、藏品 ' + m.collections + ' 件');
      }

      case 'unlock_pictures': {""",
    "three new editor commands")

sub("""    'unlock_pictures - 解锁全部明信片',""",
    """    'unlock_pictures - 解锁全部明信片',
    'unlock_all - 解锁全部图鉴(纪念品/特产) + 博物馆图鉴 + 全部百科',
    'unlock_museum - 只解锁博物馆图鉴（大冒险已关闭，用它代替）',
    'all_furniture - 获得全部家具',""",
    "GM help entries")

# auto-apply the museum unlock once, since the event that used to grant it is off
sub("""      ensureTutorialMails();
      /* 生日蛋糕 task 1 「登录游戏」 counts a session, not every command. */
      pcTaskProgress(1, 1);""",
    """      ensureTutorialMails();
      /* 大冒险 is off, and it was the only way to earn museum postcards -- so the museum
         图鉴 is unlocked instead (once; `museumUnlocked` records it). */
      if (!MUSEUM_DAY_ENABLED && !state.museumUnlocked) unlockMuseum();
      /* 生日蛋糕 task 1 「登录游戏」 counts a session, not every command. */
      pcTaskProgress(1, 1);""",
    "museum unlock on boot while the event is off")

io.open(P, "w", encoding="utf-8").write(src)
print("applied:", ", ".join(edits))
