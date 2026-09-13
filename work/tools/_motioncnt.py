import re
raw = open(r"H:\AI\frog\work\base\assets\game\js\main.min.js","rb").read()
for pat in [b"FrogMotionName", b"FrogMotionNum", b"FrogMotionPos", b"FrogMotionStrike", b"getFrogMotion", b"frogMotion", b"FrogPatternMax"]:
    print(f"  {pat.decode():20s} {raw.count(pat)}")
