import zipfile, re
z = zipfile.ZipFile(r"H:\AI\frog\dist\TravelFrog-offline.apk")
dex = z.read("classes.dex")
for needle in [b"readMirrorSave", b"mirrorSave", b"18080", b"save-mirror.json", b"frog.local"]:
    print(f"  {needle.decode():20s} {'present' if needle in dex else 'ABSENT'}")
# the fixed-port value is compiled into the bytecode as an int constant; confirm the
# string form is at least referenced via the asset-server log line
print("  asset server log str:", b"asset server on 127.0.0.1:" in dex)
