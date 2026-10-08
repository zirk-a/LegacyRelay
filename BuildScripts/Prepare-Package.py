#!/usr/bin/env python3
"""Apply per-variant bundle metadata before iOS code signing."""
import os
import plistlib
import re
import sys
from pathlib import Path


def fail(message):
    raise SystemExit('FAIL=PACKAGE_METADATA: ' + message)


def read(path):
    raw = path.read_bytes()
    obj = plistlib.loads(raw)
    if not isinstance(obj, dict):
        fail('Invalid property list: ' + str(path))
    return obj, plistlib.FMT_BINARY if raw.startswith(b'bplist00') else plistlib.FMT_XML


def save(path, obj, fmt):
    path.write_bytes(plistlib.dumps(obj, fmt=fmt, sort_keys=False))


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ('sideload', 'trollstore'):
        fail('Usage: Prepare-Package.py <staged app> <sideload|trollstore>')
    app = Path(sys.argv[1])
    variant = sys.argv[2]
    app_plist = app / 'Info.plist'
    helper_plist = app / 'PlugIns' / 'Reynard Helper.appex' / 'Info.plist'
    if not app_plist.is_file() or not helper_plist.is_file():
        fail('App or helper Info.plist is missing')
    app_info, app_format = read(app_plist)
    helper_info, helper_format = read(helper_plist)
    scenes = app_info.get('UIApplicationSceneManifest', {})
    configurations = scenes.get('UISceneConfigurations', {}) if isinstance(scenes,dict) else {}
    roles = configurations.get('UIWindowSceneSessionRoleApplication', [])
    if not roles or not isinstance(roles[0],dict) or roles[0].get('UISceneDelegateClassName') != 'LegacyRelay.SceneDelegate':
        fail('Expected SceneDelegate is absent from compiled app')
    setting = 'LEGACYRELAY_BUNDLE_ID'
    default = 'com.legacyrelay.app'
    app_id = os.environ.get(setting, default)
    if len(app_id) > 200 or not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)+', app_id):
        fail('Invalid application bundle identifier in ' + setting)
    app_info['CFBundleIdentifier'] = app_id
    app_info['CFBundleDisplayName'] = 'LegacyRelay'
    app_info['CFBundleName'] = 'LegacyRelay'
    if variant == 'trollstore':
        app_info['TSRootBinaries'] = ['ts_ptrace_jit']
    else:
        app_info.pop('TSRootBinaries', None)
    original_helper_id = helper_info.get('CFBundleIdentifier')
    if variant == 'sideload':
        helper_id = app_id + '.Helper'
        helper_info['CFBundleIdentifier'] = helper_id
    else:
        helper_id = original_helper_id
        if helper_id != 'com.minh-ton.Reynard.Helper':
            fail('Unexpected public TrollStore helper identifier; review before changing helper identity')
    save(app_plist, app_info, app_format)
    save(helper_plist, helper_info, helper_format)
    print('PACKAGE_VARIANT=' + variant)
    print('APP_BUNDLE_ID=' + app_id)
    print('HELPER_BUNDLE_ID=' + str(helper_id))
    print('SCENE_MANIFEST=PASS')


if __name__ == '__main__':
    main()
