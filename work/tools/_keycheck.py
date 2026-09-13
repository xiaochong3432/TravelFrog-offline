from cryptography.hazmat.primitives import serialization
d = open(r"H:\AI\frog\dist\offline-signing-key.pem","rb").read()
print("header:", d.split(b"\n")[0])
try:
    k = serialization.load_pem_private_key(d, password=None)
    print("loaded:", type(k).__name__, getattr(k, "key_size", ""))
    der = k.private_bytes(serialization.Encoding.DER,
                          serialization.PrivateFormat.PKCS8,
                          serialization.NoEncryption())
    print("pkcs8 der len:", len(der))
    open(r"H:\AI\frog\dist\offline-signing-key.pk8","wb").write(der)
    print("wrote dist\\offline-signing-key.pk8")
except Exception as e:
    print("load failed:", type(e).__name__, e)
