"""Show the guest-spawn and shop-purchase sites so moment hooks can be added."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, '..', 'run', 'engine', 'index.js')
s = open(P, encoding='utf-8').read()

j = s.find('state.guest = pickGuest()')
print('=== guest spawn ===')
print(s[j - 200:j + 220])
print()

k = s.find('furniture_buy_shop: (d, ctx)')
print('=== shop buy (tail) ===')
print(s[k:k + 1100])
