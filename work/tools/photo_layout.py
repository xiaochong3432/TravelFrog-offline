"""Scenery placement for layered travel-photo templates.

The client renders a photo by pasting every layer as a bitmap at an absolute
top-left position inside a 500x350 frame (``Tabikaeru.getPictureTexture`` in
``main.min.js``: ``bitmap.x = layer[1]; bitmap.y = layer[2]``).  Those
coordinates came from the service; ``Picture.json`` only carries the layer
*names*, the character offsets and the front/back split.  The service table is
not part of the client package, so the scenery coordinates are reconstructed
here.

Reconstruction rules, in order of precedence:

1. ``SCENERY_POSITIONS[record_id][piece]`` - reviewed coordinates for a scene.
2. A layer whose artwork is already registered on a full 500x350 canvas is
   pasted at the canvas origin.
3. Artwork that is cut off by its own border must be flush with that border:
   ground bands sit on the canvas bottom, stalks and trunks that run out of the
   top of the crop are anchored to the top edge, wide backdrops are centred in
   the frame.  This is what the original layer rectangles look like once they
   are cut out of the master illustration.

Everything that stays ambiguous after those rules is listed explicitly in
``SCENERY_POSITIONS`` with the reviewed value.
"""

from __future__ import annotations

from typing import Dict, Tuple

import numpy as np
from PIL import Image

CANVAS: Tuple[int, int] = (500, 350)

Position = Tuple[int, int]


def _centered(size: Tuple[int, int]) -> Position:
    return ((CANVAS[0] - size[0]) // 2, (CANVAS[1] - size[1]) // 2)


def auto_position(image: Image.Image) -> Position:
    """Place a layer using the border-flush rules described in the module doc."""
    width, height = image.size
    if (width, height) == CANVAS:
        return 0, 0
    box = image.getbbox() or (0, 0, width, height)
    alpha = np.asarray(image.convert("RGBA").split()[3])
    # A border is "cut" when artwork is clipped there rather than merely
    # touching it with a few soft pixels (foliage, shadows, feathered edges).
    hard = {
        "top": float((alpha[0, :] > 40).mean()) >= 0.35,
        "bottom": float((alpha[-1, :] > 40).mean()) >= 0.35,
        "left": float((alpha[:, 0] > 40).mean()) >= 0.35,
        "right": float((alpha[:, -1] > 40).mean()) >= 0.35,
    }
    left_cut = box[0] == 0
    right_cut = box[2] == width
    top_cut = box[1] == 0
    bottom_cut = box[3] == height

    if left_cut and right_cut and width > CANVAS[0]:
        x = (CANVAS[0] - width) // 2
    elif left_cut and (hard["left"] or not right_cut):
        x = 0
    elif right_cut and hard["right"]:
        x = CANVAS[0] - width
    elif left_cut and right_cut:
        x = (CANVAS[0] - width) // 2
    elif left_cut:
        x = 0
    elif right_cut:
        x = CANVAS[0] - width
    else:
        x = (CANVAS[0] - width) // 2

    if top_cut and bottom_cut and height > CANVAS[1]:
        y = 0
    elif bottom_cut and hard["bottom"]:
        y = CANVAS[1] - height
    elif top_cut and hard["top"]:
        y = 0
    elif top_cut and bottom_cut:
        y = 0 if height >= CANVAS[1] else (CANVAS[1] - height) // 2
    elif bottom_cut:
        y = CANVAS[1] - height
    elif top_cut:
        y = 0
    else:
        y = (CANVAS[1] - height) // 2
    return x, y


# Reviewed coordinates, keyed by picture template id and layer file stem.
# Only layers whose border evidence is ambiguous need an entry: everything else
# is resolved by auto_position().
SCENERY_POSITIONS: Dict[int, Dict[str, Position]] = {
    # back_n_roof1: the pine stands behind the roof line, the canopy piece is
    # flush with the left edge of the frame so its cut side stays invisible.
    100: {
        "cloud01": (-10, -70),
        "bird": (50, 38),
        "mou_back03": (0, 190),
        "tree01": (79, 54),
        "tree02": (0, 0),
        "roof01": (-754, 267),
    },
    # The 1254px roof strip carries the whole tiled roof; the frame-sized
    # window of that artwork starts at x=754 (`roof02.png` is that exact
    # window, pixel for pixel), so the strip is offset instead of centred.
    # Vertically the ridge's top surface (strip row 9) is put on the line the
    # characters' feet already sit on, otherwise they float above the ridge and
    # the dark bottom edge of the mou_back03 water band shows through.
    # back_n_roof2: same roof, characters on the left, branches framing below.
    101: {
        "cloud01": (-10, -70),
        "mou_back03": (0, 190),
        "roof01": (-754, 275),
        "tree04": (-150, 252),
        "tree03": (400, 152),
        "flower03": (-275, 4),
    },
    # Foreground flower clusters frame the seated characters at the left and
    # bottom-right edges. Their cut stems extend past the crop, not into midair.
    207: {
        "fenglingmu_z_back": (-300, 0),
        "fenglingmu_z_mid_1": (0, -2),
        "fenglingmu_z_mid_2": (0, 38),
        "fenglingmu_z_front_1": (0, 99),
        "fenglingmu_z_front_2": (0, 198),
        "fenglingmu_z_front_3": (285, 290),
        "fenglingmu_z_front_4": (-35, 242),
        "fenglingmu_yushui": (-100, 57),
    },
    # back_n_fenglingmu_h: `fenglingmu_h_mid_2` is the branch the two
    # characters sit on. Auto rules parked it at y=133, which left the frog and
    # the lizard hanging in the air underneath it; y=230 puts the branch top
    # exactly on their feet line (frog feet y=283, lizard feet y=303).
    206: {
        "fenglingmu_h_mid_1": (-85, 10),
        "fenglingmu_h_mid_2": (0, 230),
        "fenglingmu_h_front_2": (-350, 198),
    },
    # Beaches: the sea sits above the railing, the sand below it carries the
    # characters (their configured foot line is y=298..307).
    102: {
        "sea01": (0, 120),
        "sea02": (0, 120),
        "mou_back01": (0, 112),
        "mou_back02": (0, 112),
        "mou_back03": (0, 30),
        "rail01": (-187, 153),
    },
    103: {
        "sea01": (0, 120),
        "mou_back01": (0, 112),
        "mou_mid": (-85, 105),
        "rail01": (-187, 153),
    },
    104: {
        "sea01": (0, 120),
        "sea02": (0, 120),
        "mou_back01": (0, 112),
        "mou_back02": (0, 112),
        "mou_back03": (0, 30),
        "flower01": (-153, 192),
        "earth": (0, 262),
        "flower02": (0, 307),
    },
    # back_n_branch1 / branch2
    105: {
        "branch_back01": (0, -19),
        "branch_back03": (0, 0),
        "branch_mid": (0, 0),
        "leaf01": (330, 60),
    },
    106: {
        "branch_back02": (0, -19),
        "branch_back03": (0, 0),
        "branch_mid": (0, 0),
        "firefly": (0, 0),
        "leaf02": (120, 120),
    },
    # back_n_bamboo1 / bamboo2: stalks run out of the frame top and are hidden
    # by the soil band at the bottom.
    107: {
        "bamboo_mid01": (266, 0),
        "soil01_1": (0, 212),
        "bbshot_mid01_2": (340, 148),
        "bbshot_mid01_1": (105, 86),
        "bbshot_front01": (368, 116),
        "bamboo_front01": (-35, 0),
    },
    108: {
        "bamboo_mid02": (285, 0),
        "soil02_2": (0, 209),
        "soil02_1": (0, 165),
        "bbshot_mid02_2": (348, 160),
        "bbshot_mid02_1": (115, 100),
        "rain": (-250, 0),
        "bbshot_front02": (371, 128),
        "bamboo_front02": (-25, 0),
    },
    # back_n_field1 / field2
    109: {"wood": (-104, 228)},
    110: {"wood": (-104, 228)},
    # Leaf showers keep the frame the leaf atlas was authored for.
    111: {"leaf_03": (-197, 0)},
    112: {"leaf_03": (-197, 0)},
    113: {"leaf_04": (-197, -100)},
    114: {"leaf_04": (-197, -100)},
    # back_n_tulou1 / tulou2
    116: {"tulou1": (-170, 0), "tulou_fore": (194, 326)},
    117: {"tulou2": (-175, 0), "tulou_fore": (194, 326)},
    # back_n_pipa / shizi
    118: {"pipa_fore": (-153, -90)},
    119: {"shizi_fore": (-62, -107)},
    # back_n_lamei1..4: the 798px plum panorama is centred in the frame.
    120: {"lamei_day": (-149, 0)},
    121: {"lamei_night": (-149, 0)},
    122: {"lamei_day": (-149, 0)},
    123: {"lamei_night": (-149, 0)},
    # back_n_ibis: the 500x850 illustration is shown from its top edge.
    126: {"ibis": (0, 0), "ibis_leaf": (0, 20)},
    # Rime scenes use 1000px backdrops that are centred in the frame.
    127: {"rime_back": (-250, 0), "rime_mid_1": (-250, 0), "rime_mid_2": (-250, 0)},
    128: {"rime_back": (-250, 0), "rime_mid_1": (-250, 0)},
    129: {"rime_back": (-250, 0), "rime_mid_2": (-250, 0)},
    # Wisteria pergola
    201: {
        "lanhuateng_back": (-250, 0),
        "lanhuateng_mid": (-250, 0),
        "lanhuateng_rail_pt": (-115, 0),
        "lanhuateng_front": (-250, 0),
    },
    # Separate the hanging foreground branches instead of stacking every
    # cropped branch at x=0. Keep the central stump and its sight line clear.
    202: {"chuisihaitang_front_4": (290, 0), "chuisihaitang_front_2": (-80, 0)},
    203: {"chuisihaitang_front_3": (250, 0), "chuisihaitang_front_2": (-80, 0)},
    204: {"chuisihaitang_front_3": (250, 0), "chuisihaitang_front_2": (-80, 0)},
    3201: {
        "lanhuateng_back": (-250, 0),
        "lanhuateng_mid": (-250, 0),
        "lanhuateng_front": (-250, 0),
    },
    # A panoramic goal backdrop is centred so the composition stays balanced.
    2004: {"g_guilin1": (-23, -17)},
    # Tools rain set: the backdrops are full canvas, and the listed front layer
    # is the umbrella the frog actually holds, so it has to register with the
    # character sprite instead of drifting to the water below the branch.
    # 1000 holds a lily pad on a stick: the pole tip (sprite 75,28) pokes into
    # the pad's underside, the pad clears the eyes.
    1000: {"wet0_1": (222, 102)},
    # 1001/1002 retain the previous reviewed placement. 1003 below has a distinct
    # silhouette and needs its own rim registration.
    1001: {"wet1_1": (176, 77)},
    1002: {"wet2_1": (173, 76)},
    # Match the outer cloth's lower rim to the inner canopy's upper rim.
    # Sharing the sprite origin puts the cap across the middle of the lining.
    1003: {"wet3_1": (174, 78)},
    1008: {"dry_fw": (258, 0)},
    1009: {"dry_fw": (258, 0)},
    1010: {"dry_fw": (258, 0)},
    1011: {"dry_fw": (258, 0)},
}


def scenery_position(record_id: int, stem: str, image: Image.Image) -> Position:
    """Return the top-left canvas position for one scenery layer."""
    known = SCENERY_POSITIONS.get(record_id, {})
    key = stem.lower()
    if key in known:
        return known[key]
    return auto_position(image)
