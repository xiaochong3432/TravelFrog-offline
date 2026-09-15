# -*- coding: utf-8 -*-
"""Locate the external toolchain (JDK, Android build-tools, platform jar, browser)
without hardcoding one machine's layout.

Resolution order, first hit wins:

  JDK / java        $FROG_JAVA_HOME, $JAVA_HOME, <repo>/work/jdk/*, PATH
  Android build-tools  $FROG_ANDROID_BUILD_TOOLS, $ANDROID_BUILD_TOOLS,
                       $ANDROID_HOME/build-tools/*, $ANDROID_SDK_ROOT/build-tools/*,
                       <repo>/work/bt/*, PATH
  android.jar       $FROG_ANDROID_JAR, $ANDROID_JAR, $ANDROID_HOME/platforms/*/android.jar,
                    <repo>/work/plat/*/android.jar
  browser (Edge/Chrome)  $FROG_BROWSER, common install paths per OS, PATH

Everything is optional: callers print what is missing and how to point at it.
"""
import glob
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # <repo>/work/tools -> <repo>

EXE = '.exe' if os.name == 'nt' else ''
BAT = '.bat' if os.name == 'nt' else ''


def _first(paths):
    for p in paths:
        if p and os.path.exists(p):
            return p
    return None


def _glob_first(patterns):
    for pat in patterns:
        hits = sorted(glob.glob(pat))
        if hits:
            return hits[-1]          # newest version sorts last
    return None


def java_home():
    cands = [os.environ.get('FROG_JAVA_HOME'), os.environ.get('JAVA_HOME')]
    cands += sorted(glob.glob(os.path.join(ROOT, 'work', 'jdk', '*')))
    cands += sorted(glob.glob(os.path.join(ROOT, 'work', 'jre', '*')))
    for c in cands:
        if c and os.path.exists(os.path.join(c, 'bin', 'java' + EXE)):
            return c
    return None


def java():
    jh = java_home()
    if jh:
        p = os.path.join(jh, 'bin', 'java' + EXE)
        if os.path.exists(p):
            return p
    return shutil.which('java')


def javac():
    jh = java_home()
    if jh:
        p = os.path.join(jh, 'bin', 'javac' + EXE)
        if os.path.exists(p):
            return p
    return shutil.which('javac')


def build_tools_dir():
    cands = [os.environ.get('FROG_ANDROID_BUILD_TOOLS'),
             os.environ.get('ANDROID_BUILD_TOOLS')]
    for env in ('ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_SDK'):
        base = os.environ.get(env)
        if base:
            cands += sorted(glob.glob(os.path.join(base, 'build-tools', '*')), reverse=True)
    cands += sorted(glob.glob(os.path.join(ROOT, 'work', 'bt', 'android-*')), reverse=True)
    for c in cands:
        if c and os.path.isdir(c):
            return c
    return None


def build_tool(name):
    """name: aapt2 / zipalign / apksigner / d8 (extension added per platform)."""
    d = build_tools_dir()
    if d:
        for suffix in (EXE, BAT, ''):
            p = os.path.join(d, name + suffix)
            if os.path.exists(p):
                return p
    return shutil.which(name)


def apksigner_jar():
    d = build_tools_dir()
    if d:
        p = os.path.join(d, 'lib', 'apksigner.jar')
        if os.path.exists(p):
            return p
    return None


def android_jar():
    cands = [os.environ.get('FROG_ANDROID_JAR'), os.environ.get('ANDROID_JAR')]
    for env in ('ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_SDK'):
        base = os.environ.get(env)
        if base:
            cands += sorted(glob.glob(os.path.join(base, 'platforms', '*', 'android.jar')),
                            reverse=True)
    cands += sorted(glob.glob(os.path.join(ROOT, 'work', 'plat', '*', 'android.jar')),
                    reverse=True)
    return _first(cands)


BROWSER_CANDIDATES = {
    'nt': [
        r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
        r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    ],
    'posix': [
        '/usr/bin/microsoft-edge', '/usr/bin/microsoft-edge-stable',
        '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable',
        '/usr/bin/chromium', '/usr/bin/chromium-browser',
        '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    ],
}


def browser():
    env = os.environ.get('FROG_BROWSER')
    if env and os.path.exists(env):
        return env
    key = 'nt' if os.name == 'nt' else 'posix'
    hit = _first(BROWSER_CANDIDATES[key])
    if hit:
        return hit
    for name in ('msedge', 'microsoft-edge', 'google-chrome', 'chromium', 'chrome'):
        hit = shutil.which(name)
        if hit:
            return hit
    return None


def missing_report():
    """Short text a packaging script can print when something is absent."""
    lines = []
    if not java():
        lines.append('  java        : 未找到 —— 设置 JAVA_HOME 或 FROG_JAVA_HOME')
    if not build_tools_dir():
        lines.append('  build-tools : 未找到 —— 设置 ANDROID_HOME 或 FROG_ANDROID_BUILD_TOOLS')
    if not android_jar():
        lines.append('  android.jar : 未找到 —— 设置 ANDROID_HOME 或 FROG_ANDROID_JAR')
    return '\n'.join(lines)
