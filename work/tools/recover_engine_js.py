"""
Recover a pristine work/run/engine/index.js out of the bundled engine.

tools/bundle_engine.py embeds the engine body VERBATIM:
    engine_src = strip_module_wrapper(read(ENGINE/index.js))
    ... define('./index.js', function (module, exports) {  <engine_src>  })
so the pre-corruption source is still recoverable byte-for-byte from
work/run/web/__offline-engine.js.

strip_module_wrapper removes the trailing `module.exports = ...;` line, which we
put back.
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
BUNDLE = os.path.join(ROOT, 'web', '__offline-engine.js')
OUT = os.path.join(HERE, 'index.recovered.js')

t = open(BUNDLE, encoding='utf-8').read()

m = re.search(r"define\('\./index',\s*function\s*\(module,\s*exports,\s*require\)\s*\{\n", t)
if not m:
    raise SystemExit('index module not found in bundle')
start = m.end()

# The engine module is the LAST thing in the bundle; it is closed by the
# generator's own "  });" followed by the FrogEngine binding.
tail = re.search(r"\n\s*\}\);\s*\n\s*global\.FrogEngine\s*=", t[start:])
if not tail:
    raise SystemExit('could not find the end of the index module')
body = t[start:start + tail.start()]
print('recovered body chars: %d' % len(body))
print('first line: %r' % body.splitlines()[0])
print('last 2 lines: %r' % body.splitlines()[-2:])

# strip_module_wrapper dropped the trailing module.exports line; restore it.
if 'module.exports' not in body[-400:]:
    body = body.rstrip() + "\n\nmodule.exports = { dispatch, createState, loadState, saveState, snapshot };\n"

open(OUT, 'w', encoding='utf-8', newline='') .write(body)
print('wrote %s' % OUT)
print('first line: %r' % body.splitlines()[0])
print('last 3 lines: %r' % body.splitlines()[-3:])
