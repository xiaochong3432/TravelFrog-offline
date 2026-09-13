import zipfile
z = zipfile.ZipFile(r"H:\AI\frog\base.apk")
tot = sum(i.file_size for i in z.infolist() if i.filename.startswith("assets/game/"))
lib = sum(i.file_size for i in z.infolist() if i.filename.startswith("lib/"))
print(f"assets/game uncompressed: {tot/1048576:.1f} MB")
print(f"lib/**        uncompressed: {lib/1048576:.1f} MB")
