"""Compile the upstream android-apk sources with the installed SDK, without Gradle downloads.

No application or web sources are rewritten. Values normally supplied by AGP are
read from app/build.gradle and injected into the temporary manifest.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SDK = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or ROOT / 'android-sdk').absolute()
JAVA = Path(os.environ.get('FROG_JAVA_HOME') or os.environ.get('JAVA_HOME') or ROOT / 'work/jdk').absolute()
BT = Path(os.environ.get('FROG_ANDROID_BUILD_TOOLS') or SDK / 'build-tools/35.0.0')
JAR = Path(os.environ.get('FROG_ANDROID_JAR') or SDK / 'platforms/android-35/android.jar')
SOURCE = ROOT / 'android-apk/app/src/main'
KEY = Path(os.environ.get('FROG_SIGNING_KEY') or ROOT / 'dist/offline-signing-key.pk8')
CERT = Path(os.environ.get('FROG_SIGNING_CERT') or ROOT / 'dist/offline-signing-cert.pem')
EXE = '.exe' if os.name == 'nt' else ''
env = dict(os.environ, JAVA_HOME=str(JAVA))
env['PATH'] = str(JAVA / 'bin') + os.pathsep + env.get('PATH', '')
env['JAVA_TOOL_OPTIONS'] = '-Duser.language=en -Dfile.encoding=UTF-8'

def run(args):
    print('RUN:', ' '.join(str(x) for x in args), flush=True)
    subprocess.run([str(x) for x in args], env=env, check=True)

gradle = (ROOT / 'android-apk/app/build.gradle').read_text(encoding='utf-8')
def value(key):
    return re.search(r'\b' + key + r'\s+["\x27]?([\w.\-]+)', gradle).group(1)

OUT = ROOT / ('dist/TravelFrog-offline-' + value('versionName') + '-dev.apk')
OUT.parent.mkdir(parents=True, exist_ok=True)
for needed in [JAR, JAVA / ('bin/javac' + EXE), BT / ('aapt2' + EXE), KEY, CERT]:
    if not needed.is_file():
        raise SystemExit('Missing build input: ' + str(needed) + '. See android-apk/README.md; never generate a replacement upgrade key.')
if not (ROOT / 'work/run/web/resource').is_dir():
    raise SystemExit('Missing game resources: see android-apk/README.md')
with tempfile.TemporaryDirectory(prefix='frog-android-') as temp:
    stage = Path(temp)
    shutil.copytree(SOURCE, stage / 'src')
    manifest = stage / 'src/AndroidManifest.xml'
    ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
    tree = ET.parse(manifest)
    tree.getroot().set('package', value('applicationId'))
    for key in ['versionCode', 'versionName']:
        tree.getroot().set('{http://schemas.android.com/apk/res/android}' + key, value(key))
    tree.write(manifest, encoding='utf-8', xml_declaration=True)
    run([BT / ('aapt2' + EXE), 'compile', '--dir', stage / 'src/res', '-o', stage / 'res.zip'])
    run([BT / ('aapt2' + EXE), 'link', '-o', stage / 'unsigned.apk', '-I', JAR,
         '--manifest', manifest, '--min-sdk-version', value('minSdk'),
         '--target-sdk-version', value('targetSdk'), stage / 'res.zip'])
    (stage / 'classes').mkdir()
    (stage / 'dex').mkdir()
    run([JAVA / ('bin/javac' + EXE), '-encoding', 'UTF-8', '-source', '8', '-target', '8',
         '-classpath', JAR, '-d', stage / 'classes', *sorted((stage / 'src/java').rglob('*.java'))])
    run([BT / ('d8.bat' if os.name == 'nt' else 'd8'), '--lib', JAR, '--min-api', value('minSdk'), '--output', stage / 'dex',
         *sorted((stage / 'classes').rglob('*.class'))])
    web = ROOT / 'work/run/web'
    with zipfile.ZipFile(stage / 'unsigned.apk', 'a', zipfile.ZIP_DEFLATED) as z:
        z.write(stage / 'dex/classes.dex', 'classes.dex')
        for p in sorted(web.rglob('*')):
            if p.is_file():
                z.write(p, 'assets/' + p.relative_to(web).as_posix())
    run([BT / ('zipalign' + EXE), '-f', '4', stage / 'unsigned.apk', stage / 'aligned.apk'])
    shutil.copy2(KEY, stage / 'offline-signing-key.pk8')
    shutil.copy2(CERT, stage / 'offline-signing-cert.pem')
    run([JAVA / ('bin/java' + EXE), '-jar', BT / 'lib/apksigner.jar', 'sign',
         '--key', stage / 'offline-signing-key.pk8', '--cert', stage / 'offline-signing-cert.pem',
         '--v1-signing-enabled', 'true', '--v2-signing-enabled', 'true',
         '--v4-signing-enabled', 'false', '--out', stage / 'signed.apk', stage / 'aligned.apk'])
    run([JAVA / ('bin/java' + EXE), '-jar', BT / 'lib/apksigner.jar', 'verify', '--verbose', '--print-certs', stage / 'signed.apk'])
    run([BT / ('aapt2' + EXE), 'dump', 'badging', stage / 'signed.apk'])
    with zipfile.ZipFile(stage / 'signed.apk') as z:
        count = 0
        for p in web.rglob('*'):
            if p.is_file():
                assert z.read('assets/' + p.relative_to(web).as_posix()) == p.read_bytes(), str(p)
                count += 1
        print('All asset bytes verified:', count, flush=True)
    shutil.copy2(stage / 'signed.apk', OUT)
    report = {'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip(),
              'package': value('applicationId'), 'versionName': value('versionName'),
              'versionCode': int(value('versionCode')),
              'apk': OUT.name, 'size': OUT.stat().st_size,
              'sha256': hashlib.sha256(OUT.read_bytes()).hexdigest(), 'assets_verified': count,
              'source_modifications': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip()), 'builder': 'Android SDK aapt2/javac/d8/apksigner'}
    (ROOT / 'work/logs').mkdir(parents=True, exist_ok=True)
    (ROOT / 'work/logs/android-build-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)
