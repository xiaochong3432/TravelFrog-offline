import zipfile
z = zipfile.ZipFile(r"H:\AI\frog\base.apk")
open(r"H:\AI\frog\work\build\AndroidManifest.xml","wb").write(z.read("AndroidManifest.xml"))
print("extracted", z.getinfo("AndroidManifest.xml").file_size, "bytes")
