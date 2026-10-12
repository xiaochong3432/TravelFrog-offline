#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.5：
  ① 取消"开局白送博物馆图鉴/明信片"（做成开关 AUTO_UNLOCK_MUSEUM，默认关；
     面板的「解锁博物馆图鉴」按钮 = 引擎里的 unlock_museum，调的是同一个函数，可完整代替）；
  ② 指令台新增 `clear_furniture`（删除所有家具，不做按钮）。
     "所有家具"要连带处理两处按设计会自动补回来的东西：
       · loadState 每次都把 27 件 style===1 的"素风格"家具并回 owned；
       · furniture_load_furniture 的 put_fur 无条件注入同一批（房间皮肤自带）。
     所以命令会置 state.furniture.plainDefaultsOff = true，上面两处都跳过；
     `all_furniture` 会把它清回去，家具就照旧回来。
"""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parents[2]
ENGINE = ROOT / "work/build/v4_engine/index.js"

eng = ENGINE.read_bytes().decode("utf-8")
edits = []

# ---------------------------------------------------------------- ① 开局不再自动解锁博物馆
edits.append((
    "AUTO_UNLOCK_MUSEUM 常量",
    "const MUSEUM_DAY_ENABLED = false;",
    """const MUSEUM_DAY_ENABLED = false;
/* 开局是否白送「博物馆图鉴 + 博物馆明信片」。
   2026-09-19 玩家要求取消：博物馆内容本来就能正常玩出来（门票在许愿池换，博物馆行程
   必定带回该馆目的地照，纪念品/典藏则随旅行回来），开局直接送等于把这段进度跳掉。
   需要补的时候用存档编辑器的「解锁博物馆图鉴」按钮、或指令台 `unlock_museum` —— 两者调的
   都是下面的 unlockMuseum()，效果与旧的开局自动解锁**完全一致**。改 true 即恢复旧行为。 */
const AUTO_UNLOCK_MUSEUM = false;"""))

edits.append((
    "登录时的自动解锁改为受开关控制",
    """      /* 大冒险 is off, and it was the only way to earn museum postcards -- so the museum
         图鉴 is unlocked instead (once; `museumUnlocked` records it). */
      if (!MUSEUM_DAY_ENABLED && !state.museumUnlocked) unlockMuseum();""",
    """      /* 大冒险 is off；博物馆图鉴**不再**开局白送（见 AUTO_UNLOCK_MUSEUM 的说明），
         需要时由面板的「解锁博物馆图鉴」按钮 / 指令台 `unlock_museum` 手动补。 */
      if (AUTO_UNLOCK_MUSEUM && !MUSEUM_DAY_ENABLED && !state.museumUnlocked) unlockMuseum();"""))

# ---------------------------------------------------------------- ② 删除所有家具
edits.append((
    "gm 帮助清单加一行",
    "    'all_furniture - 获得全部家具',",
    """    'all_furniture - 获得全部家具',
        'clear_furniture - 删除所有家具（清空持有与场内摆放；素风格默认家具也不再自动补回）',"""))

edits.append((
    "all_furniture 清掉删除标记",
    """      case 'all_furniture': {
        const f = unlockFurniture();""",
    """      case 'all_furniture': {
        /* `clear_furniture` 会置 plainDefaultsOff 让"素风格默认家具"不再自动回来；
           既然这里要"获得全部家具"，把标记清掉，一切照旧。 */
        state.furniture.plainDefaultsOff = false;
        const f = unlockFurniture();"""))

edits.append((
    "新增 clear_furniture",
    """      case 'unlock_museum': {""",
    """      /* 删除所有家具（指令台用，不做按钮）。
         清三处：持有 `owned`、场内摆放 `placed`、轮换中的 `replaceFur`。
         另外置 `plainDefaultsOff`：素风格(style===1)那 27 件是
           · defaultState 给新档的默认持有，· loadState 每次读档都并回 owned，
           · furniture_load_furniture 的 put_fur 还会无条件注入给客户端画房间
         —— 不标记的话删完一重启就回来，房间里也还看得见。工作台上的材料/图纸不动。 */
      case 'clear_furniture': {
        const F = state.furniture;
        const hadOwned = (F.owned || []).length;
        const hadPlaced = (F.placed || []).length;
        F.owned = [];
        F.placed = [];
        F.replaceFur = [];
        F.plainDefaultsOff = true;
        save(); refresh();
        return ok('家具：已删除 ' + hadOwned + ' 件（含场内摆放 ' + hadPlaced
          + ' 处）；素风格默认家具也不再自动补回（用 all_furniture 可全部恢复）');
      }

      case 'unlock_museum': {"""))

edits.append((
    "loadState 尊重 plainDefaultsOff",
    """      s.furniture.owned = Array.from(new Set([
        ...(Array.isArray(s.furniture.owned) ? s.furniture.owned : []), ...PLAIN_FURNITURE_IDS,
      ]));""",
    """      /* `clear_furniture` 置了 plainDefaultsOff 就不要再把素风格默认家具并回来 */
      if (!s.furniture.plainDefaultsOff) {
        s.furniture.owned = Array.from(new Set([
          ...(Array.isArray(s.furniture.owned) ? s.furniture.owned : []), ...PLAIN_FURNITURE_IDS,
        ]));
      }"""))

edits.append((
    "导入存档路径也尊重 plainDefaultsOff",
    """    state.furniture.owned = Array.from(new Set([
      ...(Array.isArray(state.furniture.owned) ? state.furniture.owned : []), ...PLAIN_FURNITURE_IDS,
    ]));""",
    """    /* 导入存档同理：`clear_furniture` 之后的档不该被重新塞回素风格默认家具 */
    if (!state.furniture.plainDefaultsOff) {
      state.furniture.owned = Array.from(new Set([
        ...(Array.isArray(state.furniture.owned) ? state.furniture.owned : []), ...PLAIN_FURNITURE_IDS,
      ]));
    }"""))

edits.append((
    "put_fur 尊重 plainDefaultsOff",
    """        put_fur: Array.from(new Map([
          ...Array.from(FURNITURE_BY_ID.values()).filter(r => Number(r.style) === 1)
            .map(r => [Number(r.type), { type: Number(r.type), id: Number(r.id) }]),
          ...(state.furniture.placed || []).map(r => [r.type, r]),
        ]).values()),""",
    """        /* 素风格那批是"房间皮肤自带"的默认家具；`clear_furniture` 之后要真的空场，
           所以这个注入也要跳过（否则房间里照样看得见 27 件）。 */
        put_fur: Array.from(new Map([
          ...(state.furniture.plainDefaultsOff ? []
            : Array.from(FURNITURE_BY_ID.values()).filter(r => Number(r.style) === 1)
              .map(r => [Number(r.type), { type: Number(r.type), id: Number(r.id) }])),
          ...(state.furniture.placed || []).map(r => [r.type, r]),
        ]).values()),"""))

for name, old, new in edits:
    n = eng.count(old)
    if n != 1:
        sys.exit("引擎锚点【%s】出现 %d 次" % (name, n))
    eng = eng.replace(old, new, 1)
    print("引擎已改：", name)

ENGINE.write_text(eng, encoding="utf-8", newline="")
print("写出 %s（%d 行）" % (ENGINE.relative_to(ROOT), len(eng.split("\n"))))
