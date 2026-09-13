#!/usr/bin/env python3
"""Temporary markers around the syncComplete -> loginCallback chain."""
MAIN = r"H:\AI\frog\work\run\web\js\main.min.js"
d = open(MAIN, encoding="utf8").read()

OLD = "this.setSyncComplete(),this.closeLoginTimeout(),this.slineDownload(),Music.updateBGVolume(),this.loginCallback();break"
NEW = ("this.setSyncComplete(),this.closeLoginTimeout(),"
       "console.log('[offline] syncComplete chain reached'),"
       "this.slineDownload(),Music.updateBGVolume(),"
       "console.log('[offline] invoking loginCallback'),"
       "this.loginCallback(),"
       "console.log('[offline] loginCallback returned');break")

if "[offline] syncComplete chain reached" in d:
    print("markers already present")
elif OLD in d:
    open(MAIN, "w", encoding="utf8").write(d.replace(OLD, NEW))
    print("markers inserted (1 site)")
else:
    print("anchor not found; dumping neighbourhood")
    i = d.find("this.loginCallback()")
    print(repr(d[max(0, i - 320):i + 60]))
