"""Build the com.frog.offline release, retaining the verified old native shell.

FROG_UPGRADE_FROM must point to the old com.frog.offline APK. Native shell sources
are absent from this slim repository, so preserve its DEX/resources byte for byte.
Only manifest versions and assets/game change. Never recreate an upgrade identity.
"""
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import _toolchain
from verify_apk_upgrade import inspect_apk

ROOT = Path(__file__).resolve().parents[2]


def patch_versions(manifest, version_code, version_name):
    """Change only version values in AXML, keeping all offsets/resources intact.

The new name must fit the old string slot. Refuse unsupported encodings/lengths
rather than corrupting the manifest. aapt2 validates the result during inspection.
"""
    data = bytearray(manifest)
    strings, positions = [], []
    off = struct.unpack_from('<H', data, 2)[0]
    seen = set()
    while off < len(data):
        kind, header, size = struct.unpack_from('<HHI', data, off)
        if size < header or off + size > len(data):
            raise ValueError('Invalid AXML chunk')
        if kind == 1:
            count, styles, flags, start = struct.unpack_from('<IIII', data, off + 8)
            if styles or flags & 256:
                raise ValueError('Expected an unstyled UTF-16 manifest string pool')
            for i in range(count):
                pos = off + start + struct.unpack_from('<I', data, off + header + 4*i)[0]
                length = struct.unpack_from('<H', data, pos)[0]
                if length & 32768:
                    raise ValueError('Long manifest strings unsupported')
                strings.append(bytes(data[pos+2:pos+2+length*2]).decode('utf-16-le'))
                positions.append((pos, length))
        elif kind == 0x102:
            tag = struct.unpack_from('<I', data, off + 20)[0]
            if strings[tag] == 'manifest':
                start, stride, count = struct.unpack_from('<HHH', data, off + 24)
                for i in range(count):
                    pos = off + 16 + start + stride*i
                    ns, name, raw = struct.unpack_from('<III', data, pos)
                    if ns == 0xffffffff or strings[ns] != 'http://schemas.android.com/apk/res/android':
                        continue
                    field = strings[name]
                    if field == 'versionCode':
                        if data[pos+15] != 0x10:
                            raise ValueError('versionCode must be a decimal integer')
                        struct.pack_into('<I', data, pos+16, version_code)
                        seen.add(field)
                    elif field == 'versionName':
                        if data[pos+15] != 3:
                            raise ValueError('versionName must be a string')
                        idx = struct.unpack_from('<I', data, pos+16)[0]
                        if raw not in (idx, 0xffffffff):
                            raise ValueError('Unexpected raw versionName')
                        textpos, oldlen = positions[idx]
                        encoded = version_name.encode('utf-16-le')
                        if len(encoded) > oldlen*2:
                            raise ValueError('Version name does not fit the old manifest slot')
                        struct.pack_into('<H', data, textpos, len(encoded)//2)
                        data[textpos+2:textpos+2+oldlen*2] = encoded.ljust(oldlen*2, b'\0')
                        seen.add(field)
        off += size
    if seen != {'versionName', 'versionCode'}:
        raise ValueError('Missing manifest versions')
    return bytes(data)


def main():
    config = json.loads((ROOT/'work/release.json').read_text(encoding='utf8'))
    baseline = os.environ.get('FROG_UPGRADE_FROM')
    if not baseline:
        raise SystemExit('Set FROG_UPGRADE_FROM to the original com.frog.offline APK.')
    baseline = Path(baseline).resolve()
    old = inspect_apk(baseline)
    if (old['package'] != config['applicationId'] or
        old['signer_sha256'] != [config['signerSha256']] or
        config['storageUrl'] not in old['webview_urls'] or
        old['storage_key'] != config['storageKey']):
        raise SystemExit('Baseline identity does not match work/release.json; refusing to build.')
    if old['versionCode'] >= config['versionCode']:
        raise SystemExit('Release versionCode must exceed the baseline versionCode.')
    web = ROOT/'work/run/web'
    if not (web/'resource').is_dir():
        raise SystemExit('Missing local game resources.')
    key = Path(os.environ.get('FROG_SIGNING_KEY') or ROOT/'dist/offline-signing-key.pk8').resolve()
    cert = Path(os.environ.get('FROG_SIGNING_CERT') or ROOT/'dist/offline-signing-cert.pem').resolve()
    out = ROOT/('dist/TravelFrog-offline-'+config['versionName']+'.apk')
    if out.resolve() == baseline:
        raise SystemExit('Keep the baseline APK separate from the output file.')
    with tempfile.TemporaryDirectory(prefix='frog-release-') as folder:
        stage = Path(folder)
        native = {}
        with zipfile.ZipFile(baseline) as src:
            for name in src.namelist():
                if name.endswith('/') or name.startswith(('assets/', 'META-INF/')):
                    continue
                if name == 'AndroidManifest.xml':
                    continue
                if not (name == 'resources.arsc' or name.startswith('res/') or re.fullmatch(r'classes\d*\.dex', name)):
                    raise ValueError('Unexpected native payload: '+name)
                native[name] = src.read(name)
            manifest = patch_versions(src.read('AndroidManifest.xml'), config['versionCode'], config['versionName'])
        assets = {p.relative_to(web).as_posix(): p for p in web.rglob('*')
                  if p.is_file() and not p.name.endswith(('.clean','.orig','.bak')) and p.name != '__captest.html'}
        with zipfile.ZipFile(stage/'unsigned.apk', 'w', zipfile.ZIP_DEFLATED) as dst:
            dst.writestr('AndroidManifest.xml', manifest)
            for name, data in native.items():
                dst.writestr(name, data, compress_type=zipfile.ZIP_STORED if name == 'resources.arsc' else zipfile.ZIP_DEFLATED)
            for name, path in sorted(assets.items()):
                dst.write(path, 'assets/game/'+name)
        subprocess.run([_toolchain.build_tool('zipalign'), '-f', '4', str(stage/'unsigned.apk'), str(stage/'aligned.apk')], check=True)
        subprocess.run([_toolchain.build_tool('zipalign'), '-c', '4', str(stage/'aligned.apk')], check=True)
        signer = str(Path(_toolchain.build_tools_dir())/'lib/apksigner.jar')
        subprocess.run([_toolchain.java(), '-jar', signer, 'sign', '--key', str(key), '--cert', str(cert),
                        '--v1-signing-enabled', 'true', '--v2-signing-enabled', 'true', '--v4-signing-enabled', 'false',
                        '--out', str(stage/'signed.apk'), str(stage/'aligned.apk')], check=True)
        new = inspect_apk(stage/'signed.apk')
        if new['versionCode'] != config['versionCode'] or new['versionName'] != config['versionName']:
            raise ValueError('Manifest version verification failed')
        for field in ('package', 'signer_sha256', 'webview_urls', 'storage_key'):
            if new[field] != old[field]:
                raise ValueError('Upgrade identity changed: '+field)
        with zipfile.ZipFile(stage/'signed.apk') as result:
            for name, data in native.items():
                if result.read(name) != data:
                    raise ValueError('Native shell changed: '+name)
            for name, path in assets.items():
                if result.read('assets/game/'+name) != path.read_bytes():
                    raise ValueError('Asset mismatch: '+name)
        import shutil
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(stage/'signed.apk', out)
        report = dict(identity=new, apk=out.name, sha256=hashlib.sha256(out.read_bytes()).hexdigest(),
                      native_files_preserved=len(native), assets_verified=len(assets),
                      baseline_sha256=hashlib.sha256(baseline.read_bytes()).hexdigest())
        (ROOT/'work/logs').mkdir(exist_ok=True)
        (ROOT/'work/logs/release-build-report.json').write_text(json.dumps(report,indent=2),encoding='utf8')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
