#!/usr/bin/env python3
"""Create the TrollStore signing entitlements matching the staged app identity."""
import plistlib
import re
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit('FAIL=TS_ENTITLEMENTS_ARGUMENTS')
template, info, destination = map(Path, sys.argv[1:])
rights = plistlib.loads(template.read_bytes())
app = plistlib.loads(info.read_bytes())
bundle_id = app.get('CFBundleIdentifier', '')
if not isinstance(bundle_id, str) or not re.fullmatch(r'[a-zA-Z][a-zA-Z0-9-]*(?:\.[a-zA-Z0-9-]+)+', bundle_id):
    raise SystemExit('FAIL=TS_INVALID_BUNDLE_ID')
required = ('platform-application','com.apple.private.persona-mgmt',
            'com.apple.private.security.no-sandbox',
            'com.apple.developer.kernel.extended-virtual-addressing',
            'com.apple.security.iokit-user-client-class')
if any(not rights.get(key) for key in required):
    raise SystemExit('FAIL=TS_PRIVATE_REYNARD_ENTITLEMENTS_MISSING')
rights['application-identifier'] = bundle_id
destination.write_bytes(plistlib.dumps(rights,fmt=plistlib.FMT_XML,sort_keys=False))
print('TS_PRIVATE_REYNARD_ENTITLEMENTS=PASS')
print('TS_ENTITLEMENTS_APP_ID=' + bundle_id)
