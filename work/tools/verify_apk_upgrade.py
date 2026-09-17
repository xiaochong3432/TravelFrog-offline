"""Inspect an APK or check static upgrade prerequisites against an actual old APK.

Usage: python work/tools/verify_apk_upgrade.py OLD.apk [NEW.apk]
Requires the Android SDK and JDK located by _toolchain. Does not install apps.
Passing these checks does not replace an on-device save-retention test.
"""
import argparse
import json
import re
import subprocess
import zipfile
from pathlib import Path
from urllib.parse import urlsplit

import _toolchain


def inspect_apk(apk):
    aapt = _toolchain.build_tool('aapt2')
    java = _toolchain.java()
    bt = _toolchain.build_tools_dir()
    if not (aapt and java and bt):
        raise RuntimeError('Set ANDROID_HOME and JAVA_HOME to the installed toolchain.')
    signature = subprocess.check_output([
        java, '-jar', str(Path(bt) / 'lib/apksigner.jar'),
        'verify', '--print-certs', str(apk),
    ], text=True, encoding='utf-8')
    certs = sorted(set(re.findall(r'Signer #\d+ certificate SHA-256 digest: ([0-9a-f]+)', signature)))
    if not certs:
        raise RuntimeError('No verified signer certificate found.')
    badging = subprocess.check_output([aapt, 'dump', 'badging', str(apk)], text=True, encoding='utf-8')
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
    if not package:
        raise RuntimeError('Cannot read package/version metadata.')
    urls = set()
    storage_key = None
    with zipfile.ZipFile(apk) as archive:
        for name in archive.namelist():
            if re.fullmatch(r'classes\d*\.dex', name):
                urls.update(x.decode('ascii') for x in re.findall(
                    rb'(?:file:///android_asset/|http://127\.0\.0\.1:\d+/?)[A-Za-z0-9_./-]*', archive.read(name)))
            if name in ('assets/__probe.js', 'assets/__offline-engine.js',
                        'assets/game/__probe.js', 'assets/game/__offline-engine.js'):
                if b'frog.offline.save' in archive.read(name):
                    storage_key = 'frog.offline.save'
    origins = {'file:///android_asset' if url.startswith('file:') else
               '{}://{}'.format(urlsplit(url).scheme, urlsplit(url).netloc) for url in urls}
    return dict(package=package[1], versionCode=int(package[2]), versionName=package[3],
                signer_sha256=certs, webview_urls=sorted(urls), webview_origins=sorted(origins),
                storage_key=storage_key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('old', type=Path)
    parser.add_argument('new', type=Path, nargs='?')
    args = parser.parse_args()
    old = inspect_apk(args.old)
    report = {'old': old}
    errors = []
    if args.new:
        new = inspect_apk(args.new)
        report['new'] = new
        for field in ('package', 'signer_sha256', 'webview_origins', 'storage_key'):
            if not old[field] or not new[field] or old[field] != new[field]:
                errors.append(field + ' differs or is unverified')
        if new['versionCode'] <= old['versionCode']:
            errors.append('versionCode must increase')
        report['static_upgrade_checks_passed'] = not errors
        report['errors'] = errors
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
