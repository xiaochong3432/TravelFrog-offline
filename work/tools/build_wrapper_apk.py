#!/usr/bin/env python3
"""Build the clean offline wrapper APK.

What this produces
------------------
A small APK that contains ONLY:
    AndroidManifest.xml, resources.arsc, res/**, classes.dex, assets/game/**

and none of the original channel machinery (no Oppo game service, no gosdk, no
Alibaba SecurityGuard, no ad SDKs, no push, no native libraries). The game is
plain H5, so a WebView plus a loopback HTTP server over assets/game is all it
needs -- see MainActivity/AssetServer.

The original APK is covered by the same signing key and a lower versionCode, so
this installs as an upgrade over it.

Hmm -- that upgrade trick is gone on purpose. This APK now ships under its OWN
package name (com.frog.offline) instead of the original
com.ali.croak.nearme.gamecenter. Claiming the official package while signing with
our own key is what got the previous build flagged as an unofficial / repackaged
app by OEM security scanning (vivo: "非官方应用", repeated verification prompts,
forced into 保险箱). We cannot fix that by signing -- we do not have Lingxi's
private key -- so we stop claiming to be them. See AndroidManifest.xml.

Toolchain (auto-detected, see work/tools/_toolchain.py):
    aapt2, d8      <- Android build-tools      ($ANDROID_HOME/build-tools/<ver>, 或 <repo>/work/bt/android-14)
    javac          <- OpenJDK 17               ($JAVA_HOME, 或 <repo>/work/jdk)
    android.jar    <- Android platform         ($ANDROID_HOME/platforms/<ver>/android.jar, 或 <repo>/work/plat/android-11)

Usage: python build_wrapper_apk.py
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os
import shutil
import subprocess
import sys
import time
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_apk import Entry, write_zip, log  # noqa: E402
import _toolchain  # noqa: E402

ROOT = str(PROJECT_ROOT)
APP = os.path.join(ROOT, "work", "app")
BUILD = os.path.join(ROOT, "work", "build", "wrapper")
WEB = os.path.join(ROOT, "work", "run", "web")
BASE_APK = os.path.join(ROOT, "base.apk")

AAPT2 = _toolchain.build_tool("aapt2")
D8 = _toolchain.build_tool("d8")
JAVAC = _toolchain.javac()
JAVA_HOME = _toolchain.java_home()
ANDROID_JAR = _toolchain.android_jar()

MIN_SDK = "21"
TARGET_SDK = "30"

# assets that exist in the working tree but must not ship
EXCLUDE_SUFFIX = (".clean", ".orig", ".bak")
EXCLUDE_NAMES = {"__captest.html"}

# the launcher icon is lifted from the original APK (it is the game's own art)
ICON_SRC = "res/drawable-xxxhdpi/icon2.png"


def log(*a):
    """Log safely on a GBK console: never die because a tool emitted a character
    the console codepage cannot represent."""
    enc = getattr(sys.stdout, "encoding", None) or "utf-8"
    parts = []
    for x in a:
        s = str(x)
        parts.append(s.encode(enc, "replace").decode(enc, "replace"))
    print(*parts, flush=True)


def run(cmd, **kw):
    log("  $ " + " ".join(str(c) for c in cmd))
    # Force the JVM tools to speak English UTF-8; otherwise javac/d8 emit
    # localized text in the console codepage (GBK here) which then decodes as
    # mojibake and blows up when we print it.
    env = dict(os.environ)
    env["JAVA_TOOL_OPTIONS"] = "-Duser.language=en -Duser.country=US -Dfile.encoding=UTF-8"
    # d8.bat is a batch wrapper that shells out to %JAVA_HOME%\bin\java
    env["JAVA_HOME"] = JAVA_HOME
    env["PATH"] = os.path.join(JAVA_HOME, "bin") + os.pathsep + env.get("PATH", "")
    kw.setdefault("env", env)
    p = subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace", **kw)
    for stream in (p.stdout, p.stderr):
        if stream and stream.strip():
            for line in stream.rstrip().splitlines():
                if line.startswith("Picked up JAVA_TOOL_OPTIONS"):
                    continue
                log("    " + line)
    if p.returncode != 0:
        raise SystemExit(f"command failed ({p.returncode})")
    return p


def stage_icon():
    dst_dir = os.path.join(APP, "res", "mipmap-xxxhdpi")
    os.makedirs(dst_dir, exist_ok=True)
    dst = os.path.join(dst_dir, "ic_launcher.png")
    z = zipfile.ZipFile(BASE_APK)
    data = z.read(ICON_SRC)
    with open(dst, "wb") as f:
        f.write(data)
    log(f"    {ICON_SRC} -> res/mipmap-xxxhdpi/ic_launcher.png ({len(data):,} bytes)")


def collect_web():
    """assets/game/** from work/run/web/**, deflated."""
    out = {}
    now = time.localtime()
    for dp, _dns, fns in os.walk(WEB):
        for fn in fns:
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, WEB).replace("\\", "/")
            if rel.endswith(EXCLUDE_SUFFIX) or rel in EXCLUDE_NAMES:
                continue
            with open(full, "rb") as f:
                data = f.read()
            out["assets/game/" + rel] = Entry("assets/game/" + rel, data, 8, now, 0, 0)
    return out


def main():
    missing = [(name, path) for name, path in
               (("aapt2", AAPT2), ("d8", D8), ("javac", JAVAC), ("android.jar", ANDROID_JAR))
               if not path or not os.path.exists(path)]
    if missing:
        log("ERROR: Android 工具链不完整，缺少：")
        for name, path in missing:
            log("   %-12s %s" % (name, path or "(未找到)"))
        log("")
        log("用一个现成的 SDK/JDK 指给它即可（任选其一）：")
        log("   set ANDROID_HOME=<你的 Android SDK 根>        # build-tools 与 platforms/android.jar 都从它找")
        log("   set JAVA_HOME=<你的 JDK 17>")
        log("   set FROG_ANDROID_BUILD_TOOLS=<含 aapt2/d8 的目录>")
        log("   set FROG_ANDROID_JAR=<android.jar 的完整路径>")
        log("也可以按仓库默认布局放在 <仓库根>/work/{bt,jdk,plat}/ 下（该目录不入库）。")
        return 1

    os.makedirs(BUILD, exist_ok=True)
    for sub in ("classes", "dex"):
        shutil.rmtree(os.path.join(BUILD, sub), ignore_errors=True)

    log("[1/6] staging resources (launcher icon from the original APK)")
    stage_icon()

    log("[2/6] aapt2 compile")
    res_zip = os.path.join(BUILD, "res.zip")
    if os.path.exists(res_zip):
        os.remove(res_zip)
    run([AAPT2, "compile", "--dir", os.path.join(APP, "res"), "-o", res_zip])

    log("[3/6] aapt2 link")
    base_apk = os.path.join(BUILD, "base.apk")
    if os.path.exists(base_apk):
        os.remove(base_apk)
    run([AAPT2, "link", "-o", base_apk,
         "-I", ANDROID_JAR,
         "--manifest", os.path.join(APP, "AndroidManifest.xml"),
         "--min-sdk-version", MIN_SDK,
         "--target-sdk-version", TARGET_SDK,
         "--no-version-vectors",
         res_zip])

    log("[4/6] javac")
    classes = os.path.join(BUILD, "classes")
    os.makedirs(classes, exist_ok=True)
    srcs = [os.path.join(APP, "src", "com", "frog", "offline", f)
            for f in ("AssetServer.java", "MainActivity.java")]
    run([JAVAC, "-nowarn", "-encoding", "UTF-8", "-source", "8", "-target", "8",
         "-classpath", ANDROID_JAR, "-d", classes] + srcs)

    log("[5/6] d8 (dex)")
    dex_dir = os.path.join(BUILD, "dex")
    os.makedirs(dex_dir, exist_ok=True)
    class_files = []
    for dp, _dns, fns in os.walk(classes):
        class_files += [os.path.join(dp, f) for f in fns if f.endswith(".class")]
    run([D8, "--lib", ANDROID_JAR, "--min-api", MIN_SDK,
         "--output", dex_dir] + class_files)

    log("[6/6] assembling the APK")
    z = zipfile.ZipFile(base_apk)
    entries = []
    for i in z.infolist():
        if i.is_dir():
            continue
        entries.append(Entry(i.filename, z.read(i.filename), i.compress_type,
                             i.date_time, i.external_attr, i.create_system))
    z.close()
    log("    from aapt2: " + ", ".join(e.name for e in entries))

    dex_path = os.path.join(dex_dir, "classes.dex")
    with open(dex_path, "rb") as f:
        dex = f.read()
    now = time.localtime()
    entries.append(Entry("classes.dex", dex, 8, now, 0, 0))
    log(f"    classes.dex {len(dex):,} bytes")

    web = collect_web()
    entries.extend(sorted(web.values(), key=lambda e: e.name))
    log(f"    assets/game: {len(web)} files, "
        f"{sum(len(e.data) for e in web.values())/1048576:.1f} MB raw")

    out = os.path.join(BUILD, "TravelFrog-wrapper-unsigned.apk")
    write_zip(entries, out)
    log(f"    -> {out} ({os.path.getsize(out)/1048576:.1f} MB)")

    # sanity: every asset must be readable back out of the produced zip
    zz = zipfile.ZipFile(out)
    bad = []
    for i in zz.infolist():
        try:
            zz.read(i.filename)
        except Exception as ex:
            bad.append((i.filename, str(ex)))
    log(f"    read-back: {len(zz.infolist())} entries, {len(bad)} failures")
    for n, e in bad[:5]:
        log(f"      {n}: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
