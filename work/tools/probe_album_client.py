"""Album subsystem: protocol signatures + how the pending / recycle lists fill."""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### protocol table entries for album_* / item_update*')
print('=' * 78)
m = re.search(r'album_delete:\[', src)
if m:
    print(src[m.start() - 400:m.start() + 900].replace('\n', ' '))
print()

for pat, win, limit in [
    (r'newPictureInfoList\.push', 420, 2),
    (r'newPictureInfoList\s*=', 420, 2),
    (r'album_load_new', 460, 3),
    (r'album_load_recover', 420, 2),
    (r'album_load_by_id_list', 420, 2),
    (r'deletePictureInfoList', 380, 2),
]:
    print('=' * 78)
    print('### %s' % pat)
    print('=' * 78)
    n = 0
    seen = set()
    for mm in re.finditer(pat, src):
        seg = src[max(0, mm.start() - win):mm.start() + win].replace('\n', ' ')
        if seg[:50] in seen:
            continue
        seen.add(seg[:50])
        print(seg)
        print('-' * 40)
        n += 1
        if n >= limit:
            break
    if n == 0:
        print('  (no match)')
    print()
