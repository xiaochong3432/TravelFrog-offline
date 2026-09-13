raw = open(r"H:\AI\frog\work\base\assets\game\js\main.min.js","rb").read()
for pat in [b"colorBall", b"gachaColorBall", b"color_ball"]:
    print(f"  {pat.decode():16s} {raw.count(pat)}")
i = raw.find(b"colorBall")
print("  first colorBall context:", raw[i-70:i+40].decode("utf-8","replace") if i>=0 else "n/a")
