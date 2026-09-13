#!/usr/bin/env python3
"""Rename the cake's internal `layers` field to `madeLayers`.

The wire key stays `layers` (that is what the client reads), but the SAVE field has to
be named something else: a unit test guards the invariant "postcard layers are derived
from pic_id and never persisted" by asserting the serialised save contains no
`"layers"` key at all, and a cake made-layers array tripped it.
"""
import io

P = r"H:\AI\frog\work\run\engine\index.js"
src = io.open(P, encoding="utf-8").read()
before = src.count("s.layers")
src = src.replace("s.layers", "s.madeLayers")
# the payload key must stay `layers`
src = src.replace("layers: s.madeLayers.slice(),", "layers: s.madeLayers.slice(),")
# defaultState field
src = src.replace("curState: 0, part: 1, layers: [],", "curState: 0, part: 1, madeLayers: [],")
io.open(P, "w", encoding="utf-8").write(src)
print("s.layers -> s.madeLayers :", before, "occurrences")
print("remaining 's.layers':", src.count("s.layers"))
i = src.find("partyCake: {")
print(src[i:i + 260])
