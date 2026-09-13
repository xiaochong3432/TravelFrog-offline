#!/usr/bin/env python3
import re
s = open(r"H:\AI\frog\work\run\engine\protocol.js", encoding="utf8").read()
keys = ["client_confirm_event", "item_set_bag_completed", "album_to_gift", "travel_read_note",
        "travel_gift_to_album", "travel_album_to_gift", "item_takeout_bag", "item_putin_bag",
        "item_takeout_desk", "item_putin_desk", "notify_reward", "mail_open", "mail_read",
        "album_load", "item_load_items", "client_load_events", "item_load_handbook",
        "album_load_all", "album_load_by_id_list", "album_load_new", "album_load_recover",
        "album_save_new", "album_delete_new", "album_delete", "album_recover",
        "travel_load_note", "travel_load_gift", "travel_bag_to_gift", "travel_gift_to_bag",
        "travel_gift_delete_album"]
for k in keys:
    m = re.search('"' + k + '":\\s*\\{(.*?)\\n \\}', s, re.S)
    print("%-26s => %s" % (k, " ".join(m.group(1).split()) if m else "NOT FOUND"))
