"""Synchronize the visible save-panel version with work/release.json."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    version = json.loads((ROOT/'work/release.json').read_text(encoding='utf-8'))['versionName']
    path = ROOT/'work/run/web/__probe.js'
    source = path.read_text(encoding='utf-8')
    updated, count = re.subn(r"var BUILD_STAMP = [^;]+;",
                            lambda _: 'var BUILD_STAMP = '+json.dumps(version)+';', source)
    if count != 1:
        raise ValueError('Expected exactly one visible build version')
    if updated != source:
        path.write_text(updated, encoding='utf-8')
    print('Visible release version:', version)


if __name__ == '__main__':
    main()
