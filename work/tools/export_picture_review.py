"""Export full-resolution postcards and a local before/after review gallery.

--reference-dir accepts an existing export with manifest.jsonl, retaining its
filenames, companions and random scenery choices for a fair visual comparison.
No resources or reference photos are modified. Outputs stay outside git.
"""
import argparse
import hashlib
import html
import json
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from picture_art import CANVAS, FRIEND_SUFFIXES, compose_layers, load_image
from build_picture_layers import TABLES, IMAGES

FOCUS = {1003, 107, 108, 202, 203, 204, 206, 207}


class ReferenceChoices:
    def __init__(self, seed, names):
        self.rng = random.Random(seed)
        self.names = names

    def choice(self, candidates):
        for name in self.names:
            match = next((p for p in candidates if p.name == name), None)
            if match is not None:
                return match
        return self.rng.choice(candidates)


def render(parts):
    image = Image.new('RGBA', CANVAS)
    for part in parts:
        layer = load_image(str(part['path']))
        if part.get('size'):
            layer = layer.resize(tuple(part['size']), Image.Resampling.LANCZOS)
        image.alpha_composite(layer, (part['x'], part['y']))
    return image.convert('RGB')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--reference-dir', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    rows = {r['id']: r for r in json.loads((TABLES/'Picture.json').read_text(encoding='utf8'))}
    index = {c: {p.stem.lower(): p for p in sorted((IMAGES/'Picture'/c).glob('*.png'))}
             for c in ('Normal', 'Tools', 'Goal', 'Unique')}
    if args.reference_dir:
        requests = [json.loads(line) for line in
                    (args.reference_dir/'manifest.jsonl').read_text(encoding='utf8').splitlines()]
    else:
        requests = []
        for row in rows.values():
            slots = [i for i, pose in enumerate(row.get('travelerPose', [])) if pose]
            if row.get('frogPose_s') or not slots:
                slots.append(None)
            for slot in slots:
                suffix = FRIEND_SUFFIXES[slot] if slot is not None else 'solo'
                requests.append(dict(id=row['id'], traveler_index=slot,
                                     file='%s/%s_%s__%s.png' % (row['type'], row['id'], row['name'], suffix)))
    manifest, skipped, cards, contact = [], [], [], []
    for request in requests:
        row = rows[request['id']]
        relative = Path(request['file'].replace('\\', '/'))
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Invalid reference filename')
        slot = request.get('traveler_index') if request.get('traveler', True) else None
        rng = ReferenceChoices(row['id'], request.get('layers', []))
        try:
            parts = compose_layers(row, index, rng, slot)
            image = render(parts)
        except ValueError as error:
            skipped.append(dict(id=row['id'], reason=str(error)))
            continue
        target = output/'after'/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target, 'PNG')
        entry = dict(id=row['id'], file=relative.as_posix(), traveler_index=slot,
                     pixels_sha256=hashlib.sha256(image.tobytes()).hexdigest(),
                     layers=[dict(file=p['path'].relative_to(IMAGES).as_posix(), x=p['x'], y=p['y'],
                                  size=p.get('size'), role=p.get('role')) for p in parts])
        before = None
        if args.reference_dir:
            source = args.reference_dir/relative
            before = Image.open(source).convert('RGB')
            before_target = output/'before'/relative
            before_target.parent.mkdir(parents=True, exist_ok=True)
            before.save(before_target, 'PNG')
            entry['changed_pixels'] = int(np.any(np.asarray(before) != np.asarray(image), axis=2).sum())
        manifest.append(entry)
        label = html.escape(relative.name)
        src = html.escape(relative.as_posix(), quote=True)
        delta = entry.get('changed_pixels', 0)
        cards.append('<article data-name="%s" data-changed="%s" data-focus="%s"><h2>%s</h2>'
                     '<p>%s</p><div class="pair">%s<figure><figcaption>本次修订</figcaption>'
                     '<a href="after/%s"><img loading="lazy" src="after/%s"></a></figure></div></article>' %
                     (label.lower(), int(delta > 0), int(row['id'] in FOCUS), label,
                      ('变化像素：%d / 175000' % delta) if before else '',
                      ('<figure><figcaption>旧项目导出</figcaption><img loading="lazy" src="before/%s"></figure>' % src) if before else '',
                      src, src))
        if row['id'] in FOCUS:
            sheet = Image.new('RGB', (1000, 375), 'white')
            if before:
                sheet.paste(before, (0, 25))
            sheet.paste(image, (500, 25))
            draw = ImageDraw.Draw(sheet)
            draw.text((5, 5), 'BEFORE  '+relative.name, fill='black')
            draw.text((505, 5), 'AFTER  '+relative.name, fill='black')
            comparison = output/'comparisons'/relative
            comparison.parent.mkdir(parents=True, exist_ok=True)
            sheet.save(comparison)
            if row['id'] not in {pid for pid, _ in contact}:
                contact.append((row['id'], sheet))
    if contact:
        overview = Image.new('RGB', (1000, 375*len(contact)), 'white')
        for i, (_, sheet) in enumerate(contact):
            overview.paste(sheet, (0, i*375))
        overview.save(output/'重点前后对照.png')
    page = '''<!doctype html><meta charset="utf-8"><title>旅行照片修订验收</title>
<style>body{font:16px system-ui;background:#eee;color:#222;margin:20px}header{position:sticky;top:0;background:#fff;padding:14px;box-shadow:0 2px 8px #bbb}h1{font-size:22px;margin:0 0 10px}h2{font-size:16px}article{padding:10px;background:white;margin:16px 0;max-width:1040px}.pair{display:flex;flex-wrap:wrap;gap:10px}figure{margin:0}img{width:500px;height:350px;max-width:100%;object-fit:contain}input{padding:6px}label{margin-left:14px}</style>
<header><h1>旅行照片修订验收</h1><input id="search" placeholder="输入编号或文件名，如 1003">
<label><input id="focus" type="checkbox" checked>只看本轮重点</label><label><input id="changed" type="checkbox">只看有变化</label>
<p>左边为旧项目导出，右边为本次修订。点击右图可查看 500 × 350 原图；画面摆位仍需人工验收。</p></header>
''' + '\n'.join(cards) + '''<script>function filter(){document.querySelectorAll('article').forEach(a=>{a.hidden=(!a.dataset.name.includes(search.value.toLowerCase()))||(focusBox.checked&&a.dataset.focus!=='1')||(changed.checked&&a.dataset.changed!=='1')})}const search=document.getElementById('search'),focusBox=document.getElementById('focus'),changed=document.getElementById('changed');[search,focusBox,changed].forEach(e=>e.addEventListener('input',filter));filter();</script>'''
    (output/'index.html').write_text(page, encoding='utf8')
    (output/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf8')
    (output/'skipped.json').write_text(json.dumps(skipped, ensure_ascii=False, indent=2), encoding='utf8')
    changed = [m for m in manifest if m.get('changed_pixels')]
    print(json.dumps(dict(exported=len(manifest), changed=len(changed),
                          changed_ids=sorted({m['id'] for m in changed}), skipped=skipped), ensure_ascii=False))


if __name__ == '__main__':
    main()
