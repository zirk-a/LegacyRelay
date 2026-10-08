#!/usr/bin/env python3
"""Check the generated archive's scene and extension identifiers."""
import os
import plistlib
import sys
import zipfile
from pathlib import Path


def fail(message):
    raise SystemExit('FAIL=PACKAGE_VERIFY: ' + message)


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ('sideload', 'trollstore'):
        fail('Usage: Verify-Package.py <archive> <variant>')
    path = Path(sys.argv[1]); variant = sys.argv[2]
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad:
            fail('Damaged archive member ' + bad)
        apps = {m.split('/')[1] for m in z.namelist()
                if m.startswith('Payload/') and len(m.split('/')) >= 3 and m.split('/')[1].endswith('.app')}
        if len(apps) != 1:
            fail('Expected exactly one app bundle')
        prefix = 'Payload/' + next(iter(apps)) + '/'
        app = plistlib.loads(z.read(prefix + 'Info.plist'))
        helper = plistlib.loads(z.read(prefix + 'PlugIns/Reynard Helper.appex/Info.plist'))
        scene = app.get('UIApplicationSceneManifest', {})
        roles = scene.get('UISceneConfigurations', {}).get('UIWindowSceneSessionRoleApplication', [])
        if not roles or roles[0].get('UISceneDelegateClassName') != 'LegacyRelay.SceneDelegate':
            fail('Scene delegate is not registered')
        if app.get('CFBundleDisplayName') != 'LegacyRelay' or app.get('CFBundleName') != 'LegacyRelay':
            fail('Visible app name must be LegacyRelay')
        app_id = app.get('CFBundleIdentifier', '')
        helper_id = helper.get('CFBundleIdentifier', '')
        expected = os.environ.get('LEGACYRELAY_BUNDLE_ID', 'com.legacyrelay.app')
        if app_id != expected:
            fail('App ID is not expected for ' + variant)
        if variant == 'sideload' and helper_id != app_id + '.Helper':
            fail('Sideload helper ID must have the parent ID prefix')
        if variant == 'trollstore' and helper_id != 'com.minh-ton.Reynard.Helper':
            fail('TrollStore helper ID must preserve official helper identity')
        if variant == 'trollstore' and app.get('TSRootBinaries') != ['ts_ptrace_jit']:
            fail('TrollStore must declare its root JIT helper')
        if variant == 'sideload' and 'TSRootBinaries' in app:
            fail('Sideload must not include TrollStore root helper declaration')
        for member in (prefix + 'LegacyRelay', prefix + 'Frameworks/XUL',
                       prefix + 'Frameworks/GeckoView.framework/GeckoView',
                       prefix + 'PlugIns/Reynard Helper.appex/Reynard Helper'):
            if member not in z.namelist():
                fail('Missing executable ' + member)
        if variant == 'trollstore' and prefix + 'ts_ptrace_jit' not in z.namelist():
            fail('Missing TrollStore JIT')
        print('PACKAGE_ARCHIVE_CHECK=' + variant + ':PASS')
        print('PACKAGE_APP_ID=' + app_id)
        print('PACKAGE_HELPER_ID=' + helper_id)


if __name__ == '__main__':
    main()
