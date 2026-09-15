from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
from cryptography.hazmat.primitives import serialization
d = open(str(PROJECT_ROOT) + "/dist/offline-signing-key.pem","rb").read()
print("header:", d.split(b"\n")[0])
try:
    k = serialization.load_pem_private_key(d, password=None)
    print("loaded:", type(k).__name__, getattr(k, "key_size", ""))
    der = k.private_bytes(serialization.Encoding.DER,
                          serialization.PrivateFormat.PKCS8,
                          serialization.NoEncryption())
    print("pkcs8 der len:", len(der))
    open(str(PROJECT_ROOT) + "/dist/offline-signing-key.pk8","wb").write(der)
    print("wrote dist\\offline-signing-key.pk8")
except Exception as e:
    print("load failed:", type(e).__name__, e)
