"""Relocate the animpicture helper block to MODULE level (it was landing inside
the state object literal) and drop the invented item-id helper."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import sys

P = str(PROJECT_ROOT) + "/work/run/engine/index.js"
s = open(P, encoding='utf-8').read()

START = '  /* ---- 动态照片 (AnimPictureModel) ---'
ENDMARK = '  function animPushItemUpdate(ctx) {'
i = s.find(START)
j = s.find(ENDMARK)
if i < 0 or j < 0:
    print('markers not found', i, j)
    sys.exit(1)
k = s.find('\n  }\n', j)
if k < 0:
    print('end not found')
    sys.exit(1)
k += len('\n  }\n')

NEW = '''  /* ---- 动态照片 (AnimPictureModel) ---------------------------------------
     animpictureData is `{base_info, list, pic_map}`:
       base_info = {album_id: 9002, album_num: 4, page_id: 9001}
       list[slot] = {id, phase_list:[{layer, phase, spine}], pic_list:[...]}
       pic_map    = {pictureId -> slot}   -- ONLY 3 entries (100, 104, 2000),
     i.e. only those three postcards can be turned into a moving photo, and
     `phase_list.length == 1` means there is nothing to animate (phase 0). */
  const ANIM = (gamedata.tables && gamedata.tables.animpictureData) || {};
  const ANIM_LIST = ANIM.list || {};
  const ANIM_PIC_MAP = ANIM.pic_map || {};
  const ANIM_BASE = ANIM.base_info || {};

  function animPayload() {
    const A = state.animPicture;
    return {
      guide: A.guide || 0,
      page_num: A.pageNum || 0,
      phase: A.phase || 0,
      item_num: A.itemNum || 0,
      exp: A.exp || 0,
      exp_pic: (A.expPic || []).slice(),
      pic_list: (A.picList || []).map((p) => ({
        id: p.id,
        put_num: p.putNum || 0,
        pictures: (p.pictures || []).slice(),
      })),
    };
  }

  /** The phase a slot starts at: 0 when it has a single phase_list entry. */
  function animStartPhase(slotId) {
    const row = ANIM_LIST[String(slotId)];
    if (!row || !Array.isArray(row.phase_list)) return 0;
    return row.phase_list.length === 1 ? 0 : 1;
  }

  /** How many phases a slot walks through (table phases are 1-based). */
  function animPhaseCount(slotId) {
    const row = ANIM_LIST[String(slotId)];
    if (!row || !Array.isArray(row.phase_list)) return 0;
    return row.phase_list.reduce((a, p) => Math.max(a, Number(p.phase) || 0), 0);
  }

'''

s2 = s[:i] + s[k:]
anchor = '  const CAPSULE = (gamedata.tables && gamedata.tables.capsuleData) || {};'
a = s2.find(anchor)
if a < 0:
    print('anchor not found')
    sys.exit(1)
s3 = s2[:a] + NEW + s2[a:]
open(P, 'w', encoding='utf-8', newline='').write(s3)
print('done; file %d chars' % len(s3))
