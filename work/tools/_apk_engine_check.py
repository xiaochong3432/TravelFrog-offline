import zipfile
z = zipfile.ZipFile(r"H:\AI\frog\dist\TravelFrog-offline.apk")
eng = z.read("assets/game/__offline-engine.js")
print(f"  __offline-engine.js {len(eng):,} bytes")
for probe in [b"Frogpattern", b"friendly", b"encyclopediaPayload", b"furniture_flowerpot_harvest", b"task_get_reward", b"checkAchievements", b"rollGuestGift", b"define.json"]:
    print(f"    {probe.decode():32s} {'present' if probe in eng else 'ABSENT'}")
print(f"  index.html {z.getinfo('assets/game/index.html').file_size:,} bytes")
