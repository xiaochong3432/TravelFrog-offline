"""Build game postcard layers from the reviewed photo composition rules."""
import json
import random
from pathlib import Path
from picture_art import compose_layers

ROOT = Path(__file__).resolve().parents[1] / 'run'
TABLES = ROOT / 'engine/data/tables'
IMAGES = ROOT / 'web/resource/China/images'
OUT = ROOT / 'engine/data/picture-layers.json'

def build():
    resources = json.loads((TABLES / 'resources.json').read_text(encoding='utf8'))
    pictures = json.loads((TABLES / 'Picture.json').read_text(encoding='utf8'))
    resource_ids = {}
    for rid, name in sorted(resources.items(), key=lambda item: int(item[0])):
        resource_ids.setdefault(name.lower(), int(rid))
    index = {category: {p.stem.lower(): p for p in sorted((IMAGES / 'Picture' / category).glob('*.png'))}
             for category in ('Goal', 'Unique', 'Normal', 'Tools')}
    def make(row, slot=None):
        result = []
        for part in compose_layers(row, index, random.Random(row['id']), slot):
            name = part['path'].relative_to(IMAGES).with_suffix('').as_posix().lower()
            if name not in resource_ids: raise ValueError('Artwork absent from ResourcesDB: ' + name)
            layer = {'layer': [resource_ids[name], part['x'], part['y']]}
            if part.get('size'): layer['size'] = list(part['size'])
            if part.get('role'): layer['role'] = part['role']
            result.append(layer)
        return result
    output, skipped = {}, []
    for row in pictures:
        try:
            # Legacy saves retain only pic_id, with no companion selection.
            # Offline reconstruction uses the first configured slot consistently;
            # it does not claim to recover the original server's random choice.
            slot = next((i for i, logical in enumerate(row.get('travelerPose', [])) if logical), None)
            rec = {'name': row['name'], 'type': row['type'], 'layers': make(row, slot)}
            output[str(row['id'])] = rec
        except ValueError as error: skipped.append((row['id'], str(error)))
    print('Built %d/%d postcard recipes' % (len(output), len(pictures)))
    for pid, reason in skipped: print('  Skipped %s: %s' % (pid, reason))
    expected = {2033, 2035, 2039, 2040, 2041, 2042, 2075, 2076}
    unexpected = {pid for pid, _ in skipped} - expected
    if unexpected: raise RuntimeError('Unexpected unresolved photo templates: ' + str(sorted(unexpected)))
    OUT.write_text(json.dumps(output, ensure_ascii=False, separators=(',', ':')), encoding='utf8')

if __name__ == '__main__': build()
