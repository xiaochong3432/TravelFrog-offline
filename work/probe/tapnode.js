/* Tap the first usable node matching window.__FIND (set by a previous --step eval).
   Optional window.__FIND_INDEX picks a specific hit. Returns what it tapped. */
const keys = window.__FIND || [];
const hits = window.__egretFind(keys).filter((h) =>
  h.vis !== false && h.x !== null && h.w > 0 && h.h > 0);
if (!hits.length) return JSON.stringify({ error: 'no tappable hit', keys, all: window.__egretFind(keys) }, null, 1);

const idx = (typeof window.__FIND_INDEX === 'number') ? window.__FIND_INDEX : 0;
const t = hits[Math.min(idx, hits.length - 1)];
const cx = Math.round(t.x + t.w / 2);
const cy = Math.round(t.y + t.h / 2);
const res = window.__egretTap(cx, cy);
return JSON.stringify({
  tapped: t.cls.slice(0, 50), name: t.name, rect: [t.x, t.y, t.w, t.h], at: [cx, cy],
  candidates: hits.length, res,
}, null, 1);
