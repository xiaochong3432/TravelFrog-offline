"""Resolve postcard artwork using the reviewed photo-export rules.

Ported from the companion photo-export workspace. QW is the frog; BH/CW/YHC
are different companions, never interchangeable frog variants. The placement
rules are shared with the layer builder so exported and in-game photos agree.
"""
from __future__ import annotations
import random
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from PIL import Image
from functools import lru_cache
import photo_layout

CANVAS = (500, 350)
ROLE_SUFFIXES = ("bh", "cw", "qw", "yhc")
FRIEND_SUFFIXES = ("bh", "cw", "yhc")

@lru_cache(maxsize=2048)
def load_image(path):
    with Image.open(path) as image:
        return image.convert('RGBA')

def compose_layers(record, index, rng, traveler_index=None):
    """Ordered PNG placements; never split/reinsert characters after composition.

    Solo poses use their own position. Some companion PNGs already contain both
    frog and companion (notably the flower-viewing stump); draw them only once.
    """
    result = []
    category = record['type']

    def scenery(name, resolver):
        path = resolver(name)
        if path is None:
            raise ValueError('Missing scenery: ' + name)
        image = load_image(str(path))
        size = None
        if path.stem.lower().startswith('sky') and image.height < CANVAS[1]:
            size = (image.width, CANVAS[1])
            image = image.resize(size, Image.Resampling.LANCZOS)
        x, y = photo_layout.scenery_position(record['id'], path.stem, image)
        result.append(dict(path=path, x=x, y=y, size=size))

    def pose(logical, suffix, pos):
        if not logical:
            return
        path = _pose_group(logical, category, index).get(suffix)
        if path is None:
            raise ValueError('Missing character: ' + logical + '/' + suffix)
        image = load_image(str(path))
        x, y = (0, 0) if image.size == CANVAS else (
            round((CANVAS[0] - image.width) / 2 + pos.get('x', 0)),
            round((CANVAS[1] - image.height) / 2 - pos.get('y', 0)))
        # The stump is painted into these role sprites and is cut at its bottom.
        # Anchor that cut to the photo edge, not to a strip of visible grass.
        if record['id'] in (202, 203, 204):
            y = CANVAS[1] - image.height
        # In the yellow trumpet-flower scene the shared frog sprite's feet were
        # above the supporting branch. The companion has a separate h pose.
        if record['id'] == 206 and suffix == 'qw':
            y += 16
        result.append(dict(path=path, x=x, y=y, role=suffix))

    for name in record.get('backImage', []):
        scenery(name, lambda n: _resolve_background(n, category, index, rng))
    solo = traveler_index is None and bool(record.get('frogPose_s'))
    frog = (record.get('frogPose_s' if solo else 'frogPose', ''), 'qw',
            record.get('frogPos_s' if solo else 'frogPos', {}))
    friend = None
    if traveler_index is not None:
        logical = record.get('travelerPose', [])[traveler_index]
        if not logical:
            raise ValueError('No companion in this slot')
        friend = (logical, FRIEND_SUFFIXES[traveler_index], record['travelerPos'][traveler_index])
    if friend and record['id'] in FROG_ON_TOP_IDS:
        pose(*friend)
        pose(*frog)
    else:
        pose(*frog)
        if friend:
            pose(*friend)
    for name in record.get('frontImage', []):
        scenery(name, lambda n: _resolve_front(n, category, index))
    return result

FROG_ON_TOP_IDS = {
    2003,  # guangzhou1
    2007,  # tianjin1
    2018,  # guangzhou2
    2020,  # guilin2
    2023,  # hangzhou3
    2024,  # suzhou2
    2077,  # chengdu5
    2078,  # hainan5
    2119,  # bwg_shanxi1
    2126,  # jilin1
    2148,  # guangzhou4
    105,   # back_n_branch1
    109,   # back_n_field1
    107,   # back_n_bamboo1
    108,   # back_n_bamboo2
}


def _strip_prefix(value: str, prefix: str) -> str:
    return value[len(prefix) :] if value.startswith(prefix) else value


def _category_order(category: str) -> List[str]:
    return [category] + [name for name in ("Normal", "Tools", "Goal", "Unique") if name != category]


def _group_images(paths: Dict[str, Path], prefix: str) -> Dict[str, Path]:
    """Find role variants for a logical pose prefix."""
    prefix = prefix.lower()
    found: Dict[str, Path] = {}
    for stem, path in paths.items():
        for suffix in ROLE_SUFFIXES:
            if stem == f"{prefix}_{suffix}" or stem == f"{prefix}{suffix}":
                found[suffix] = path
            # Fenglingmu uses pose_bh_h / pose_bh_z.
            if stem.startswith(f"{prefix}_pose_{suffix}_"):
                found[suffix] = path
            if stem == f"{prefix}_pose_{suffix}":
                found[suffix] = path
    return found


GOAL_ALIASES = {
    "shanghai": "SH",
    "beijing": "BJ", "chengdu": "CD", "chongqing": "CQ", "fujian": "FJ",
    "guangzhou": "GZ", "guilin": "GL", "hangzhou": "HZ", "suzhou": "SZ",
    "tianjin": "TJ", "wuhan": "WH", "xian": "XA", "xianggang": "XG",
    "yunnan": "YN", "jiangxi": "JX", "jiangmen": "JM", "jiuquan": "JQ",
    "liaoning": "LN", "lasa": "LS", "luoyang": "LY", "ningxia": "NX",
    "qingdao": "QD", "zhangjiajie": "ZJJ", "anhui": "AH", "guizhou": "GUIZ",
    "hainan": "HN", "haerbin": "HEB",
    "aomen": "g_aomen", "hebei": "g_hebei", "jilin": "g_jilin",
    "qinghai": "g_qinghai", "shanxi": "g_shanxi",
}


def _goal_pose_prefix(logical: str, paths: Dict[str, Path]) -> str:
    base = _strip_prefix(_strip_prefix(logical, "pose_"), "rnd_")
    base = {"shifen": "TWSF", "kengding": "TWKD", "jingan": "TWJA",
            "lanyu": "TWLY", "tiandeng": "TWTD", "zuinandian": "TWZND"}.get(base, base)
    exact = _group_images(paths, base)
    if exact:
        return base
    if base == "gz_alone":
        return "GZ_alone"
    if base == "ld_guqin":
        return "ld_guqin"
    if base.startswith("bwg_"):
        match = re.fullmatch(r"bwg_([a-z]+)(\d*)", base)
        museum = {"jiangxi": "JX", "nanyuewang": "NYW", "shandong": "SD", "shanxi": "SX", "wuwenhua": "WWH"}
        if match:
            city, number = match.groups()
            return "BWG_" + museum.get(city, city.upper()) + number
    if base.startswith("tw_"):
        return {"tw_jingan": "TWJA", "tw_lanyu": "TWLY", "tw_tiandeng": "TWTD", "tw_zuinandian": "TWZND", "tw_shifen": "TWSF", "tw_kending": "TWKD"}.get(base, base)
    match = re.match(r"^(?:g_)?([a-z]+?)(\d+)$", base)
    if match:
        city, number = match.groups()
        return GOAL_ALIASES.get(city, city).upper() + number
    match = re.match(r"^([a-z]+)_(\d+)$", base)
    if match:
        city, number = match.groups()
        return GOAL_ALIASES.get(city, city).upper() + number
    return base


def _pose_group(logical: str, category: str, index: Dict[str, Dict[str, Path]]) -> Dict[str, Path]:
    base = _strip_prefix(logical, "rnd_")
    pose_base = _strip_prefix(base, "pose_")
    # Explicit resource families; never substitute a different species.
    if pose_base == "gz_alone":
        return {"qw": index["Goal"]["gz_alone"]}
    if re.fullmatch(r"(?:wet|dry|fuza)[0-3]", pose_base):
        family = pose_base.rstrip("0123")
        companion = {"wet": "yhc", "dry": "cw", "fuza": "bh"}[family]
        return {"qw": index["Tools"][pose_base], companion: index["Tools"][family + "_" + companion]}
    if pose_base in ("fenglingmu_h", "fenglingmu_z"):
        variant = pose_base[-1]
        return {s: index["Normal"]["fenglingmu_pose_" + s + ("_" + variant if s in ("bh", "cw") else "")] for s in ROLE_SUFFIXES}
    for source in _category_order(category):
        paths = index[source]
        compact = re.sub(r"_(\d+)$", r"\1", pose_base)
        for candidate in (pose_base, compact, "u_" + pose_base):
            group = _group_images(paths, candidate)
            if group:
                return group
        if source == "Goal":
            group = _group_images(paths, _goal_pose_prefix(base, paths))
        else:
            pose_base = _strip_prefix(base, "pose_")
            # The logical data name for these families omits the literal "_pose".
            if pose_base in ("chuisihaitang", "chuisihaitang_mt", "fenglingmu_h", "fenglingmu_z"):
                group = _group_images(paths, pose_base + "_pose")
            else:
                group = _group_images(paths, pose_base)
                # Some files use a role suffix without an underscore, e.g. beach1_2qw.
                if not group:
                    for suffix in ROLE_SUFFIXES:
                        candidates = [p for stem, p in paths.items() if stem.startswith(pose_base.lower()) and stem.endswith(suffix)]
                        if candidates:
                            group[suffix] = sorted(candidates, key=lambda p: len(p.stem))[0]
        if group:
            return group
    return {}


def _resolve_background(name: str, category: str, index: Dict[str, Dict[str, Path]], rng: random.Random) -> Optional[Path]:
    if name.startswith("mumianhua_mid_"):
        name = name.replace("mumianhua_mid_", "mumianhua_xyn_mid")
    logical = _strip_prefix(_strip_prefix(name, "back_"), "rnd_").lower()
    for source in _category_order(category):
        paths = index[source]
        if name.startswith("rnd_"):
            candidates = [p for stem, p in paths.items() if stem.startswith(logical)]
            if candidates:
                return rng.choice(sorted(candidates, key=lambda p: p.name))
        direct = paths.get(logical)
        if direct:
            return direct
        candidates = [p for stem, p in paths.items() if stem.startswith(logical)]
        if candidates:
            return sorted(candidates, key=lambda p: len(p.stem))[0]
    return None


def _resolve_front(name: str, category: str, index: Dict[str, Dict[str, Path]]) -> Optional[Path]:
    if name.startswith("mumianhua_front_"):
        name = name.replace("mumianhua_front_", "mumianhua_xyn_front")
    for source in _category_order(category):
        paths = index[source]
        direct = paths.get(name.lower())
        if direct:
            return direct
        candidates = [p for stem, p in paths.items() if stem.startswith(name.lower())]
        if candidates:
            return sorted(candidates, key=lambda p: len(p.stem))[0]
    return None
