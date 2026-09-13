import struct
d = open(r"H:\AI\frog\base.apk","rb").read()
i = d.rfind(b"PK\x05\x06")
cd_off = struct.unpack_from("<I", d, i+16)[0]
print("cd_offset", cd_off)
print("16 bytes before cd:", d[cd_off-16:cd_off])
print("has APK Sig Block 42 magic:", d[cd_off-16:cd_off] == b"APK Sig Block 42")
