"""Verify the SHIPPED APK carries the lottery subsystem, that the shadowing stub
is GONE, and that all earlier work survives. Nonsense CONTROL must be ABSENT.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('lottery handlers (each must be exactly 1):')
for c in ['lottery_load', 'lottery_open', 'lottery_select', 'lottery_confirm_reward']:
    print('  %-26s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('lotteryPayload helper', 'function lotteryPayload'),
    ('startLotteryPhase helper', 'function startLotteryPhase'),
    ('maybeLottery roll', 'function maybeLottery'),
    ('LOTTERY_TABLE from table', 'tables.lotteryData'),
    ('LOTTERY_PICKS 5', 'LOTTERY_PICKS = 5'),
    ('shadowing stub REMOVED (must be 0)', 'lottery_load: () => ({})'),
    ('drawing handlers kept', 'guest_load_drawing: ('),
    ('visitor kept', 'visit_open: ('),
    ('album recover kept', 'album_load_recover: ('),
    ('giftBoxPayload kept', 'function giftBoxPayload'),
    ('furniture_buy_shop kept', 'furniture_buy_shop: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-36s %d' % (label, src.count(needle)))

print()
print('  %-36s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
