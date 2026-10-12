#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 客户端：让嘟嘟商店的两行图纸补行（8053 / 8054）真的能显示和购买。

背景（实测）：
  · 引擎那边我们把「不倒翁图鉴 10401」「挂兜手工制作 10601」两条出售行补在空闲 id
    8053/8054 上（官方行的 8035/8036 已被南瓜豆沙糕/酥圈圈占用）；
  · 但客户端渲染商店时会**丢掉它自己表里没有的 shop_id**：
        this.shopItems = this.shopItems.filter(function (r) { return !!t.get(r.shop_id) })
    而客户端的表在加密包 `config.eab` 的 `furnitureShopData_json` 里，里面没有这两行
    → 玩家看到的货架上少两格，就算看到了也点不动（requestBuy 里 `n && ...` 直接短路）。

做法：只往客户端那张表里补两行（字段与 8035/8036 对齐，价格/限购与引擎一致），
      不碰客户端代码。为了不破坏客户端能加载的包，本脚本自带三道闸：
        1) 先证明编码器对这个文件**解码->重编码字节完全一致**（eab_encode 的 --roundtrip 门槛）；
        2) 只替换 furnitureShopData_json 这一个 blob，其余 blob 必须逐字节不变；
        3) 写回后**重新解码**，确认 61 张表里只有这一张变了、且两行确实在。
      任何一道不过就直接失败退出，不写文件。

用法：
    python work/tools/v37_client_shop_rows.py
    FROG_CONFIG_EAB=... python work/tools/v37_client_shop_rows.py
"""

import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import eab_decrypt as E      # noqa: E402
import eab_encode as EE      # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
EAB = os.environ.get('FROG_CONFIG_EAB') or os.path.join(
    ROOT, 'work', 'build', 'v4_payload', 'resource', 'China', 'eab', 'config.eab')
TABLE = 'furnitureShopData_json'

# 与引擎 v37_merchant_stars.py 的 MERCHANT_SPECIAL_ROWS 对齐（价格/限购/名称/说明一致）
ROWS = [
    {'id': 8053, 'item_id': 10401, 'name': '不倒翁图鉴', 'info': '不倒翁家具制作图纸',
     'price': 500, 'limit': 1, 'order': 151, 'type': 8},
    {'id': 8054, 'item_id': 10601, 'name': '挂兜手工制作', 'info': '挂兜制作图纸',
     'price': 500, 'limit': 1, 'order': 151, 'type': 8},
]


def fail(msg):
    print('[client-shop] 失败：%s' % msg)
    raise SystemExit(1)


def main():
    if not os.path.exists(EAB):
        fail('找不到 %s' % EAB)
    original = io.open(EAB, 'rb').read()

    # ---- 闸 1：编码器对这个文件必须字节可逆
    entries, blobs = EE.load_entries(EAB)
    if EE.build(entries, blobs) != original:
        fail('解码->重编码不是字节一致，按仓库约定不能动这个包')

    names = [e['n'] for e in entries]
    if TABLE not in names:
        fail('%s 里没有 %s' % (EAB, TABLE))
    idx = names.index(TABLE)

    table = json.loads(blobs[idx].decode('utf-8'))
    if not isinstance(table, dict):
        fail('%s 不是字典（%s）' % (TABLE, type(table).__name__))

    have = [r for r in ROWS if str(r['id']) in table]
    if len(have) == len(ROWS):
        print('[client-shop] 两行已经在客户端表里，跳过')
        return 0

    # 以 8035/8036 为模板把字段补齐（客户端要 has_item/limit/order/price/shop_limit/sign/type）
    template = table.get('8035') or table.get('8036')
    if not template:
        fail('找不到可用于对齐字段的模板行（8035/8036）')

    for row in ROWS:
        new_row = dict(template)
        new_row.update({
            'id': int(row['id']), 'item_id': int(row['item_id']),
            'name': row['name'], 'info': row['info'],
            'price': int(row['price']), 'limit': int(row['limit']),
            'order': int(row['order']), 'type': int(row['type']),
        })
        table[str(row['id'])] = new_row

    # ---- 闸 2：只换这一个 blob
    new_blob = json.dumps(table, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    new_blobs = list(blobs)
    new_blobs[idx] = new_blob
    for i, (a, b) in enumerate(zip(blobs, new_blobs)):
        if i != idx and a != b:
            fail('blob #%d (%s) 被意外改动' % (i, names[i]))
    if len(new_blobs) != len(blobs):
        fail('blob 数量变了')

    packed = EE.build(entries, new_blobs)

    # ---- 闸 3：临时写一份再解码核对
    tmp = EAB + '.tmp-check'
    io.open(tmp, 'wb').write(packed)
    try:
        ent2, blobs2 = EE.load_entries(tmp)
        changed = [names[i] for i in range(len(names)) if blobs2[i] != blobs[i]]
        if changed != [TABLE]:
            fail('重新解码后变化的表不对：%s' % changed)
        table2 = json.loads(blobs2[names.index(TABLE)].decode('utf-8'))
        for row in ROWS:
            got = table2.get(str(row['id']))
            if not got:
                fail('重新解码后 %s 丢了' % row['id'])
            if int(got['price']) != int(row['price']) or int(got['item_id']) != int(row['item_id']):
                fail('%s 的价格/物品不对：%s' % (row['id'], got))
        if len(table2) != len(table) :
            fail('表行数不对：%d -> %d' % (len(table), len(table2)))
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)

    io.open(EAB, 'wb').write(packed)
    print('[client-shop] 已往客户端 %s 补 2 行：8053(10401 不倒翁图鉴) / 8054(10601 挂兜手工制作)'
          '；包 %d -> %d 字节，其余 60 张表逐字节未变' % (TABLE, len(original), len(packed)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
