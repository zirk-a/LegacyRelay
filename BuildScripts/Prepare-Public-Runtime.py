#!/usr/bin/env python3
import json
import os
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXT = ROOT / 'External'
FRAMEWORKS = EXT / 'Engine' / 'Frameworks'
RELEASE = '0.16.0'
API = 'https://api.github.com/repos/minh-ton/reynard-browser/releases/tags/' + RELEASE


def fail(message):
    raise SystemExit('FAIL=REYNARD_PUBLIC_RUNTIME: ' + message)


def fetch_asset(name, destination):
    request = urllib.request.Request(API, headers={'User-Agent': 'LegacyRelay-Build'})
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            data = json.load(response)
    except Exception as error:
        fail('Cannot retrieve official Reynard release: ' + str(error))
    options = [a for a in data.get('assets', []) if a.get('name') == name]
    if len(options) != 1:
        fail('Required official asset not present in release ' + RELEASE + ': ' + name)
    asset = options[0]
    expected = asset.get('size')
    if not isinstance(expected, int) or expected < 1000000:
        fail('Invalid official release asset size for ' + name)
    request = urllib.request.Request(asset['browser_download_url'], headers={'User-Agent': 'LegacyRelay-Build'})
    try:
        with urllib.request.urlopen(request, timeout=100) as response, open(destination, 'wb') as output:
            shutil.copyfileobj(response, output, length=1024 * 1024)
    except Exception as error:
        fail('Download of ' + name + ' failed: ' + str(error))
    if destination.stat().st_size != expected:
        fail('Incomplete official release download for ' + name)


def app_files(archive):
    names = archive.namelist()
    apps = sorted(set(name.split('/')[1] for name in names if name.startswith('Payload/') and name.count('/') >= 2 and name.split('/')[1].endswith('.app')))
    if len(apps) != 1:
        fail('Cannot identify the single app in official Reynard release')
    prefix = 'Payload/' + apps[0] + '/'
    return prefix, [x for x in names if x.startswith(prefix) and not x.endswith('/')]


def write_member(archive, member, destination):
    if not member or '..' in Path(member).parts:
        fail('Unsafe member path')
    if archive.getinfo(member).file_size > 1600000000:
        fail('Unexpected oversized official release member')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with archive.open(member) as source, open(destination, 'wb') as output:
        shutil.copyfileobj(source, output, 1024 * 1024)
    if destination.stat().st_size != archive.getinfo(member).file_size:
        fail('Incomplete file extraction')
    mode = (archive.getinfo(member).external_attr >> 16) & 0o777
    if mode:
        destination.chmod(mode)
    elif destination.name in ('GeckoView', 'XUL', 'Reynard Helper', 'ts_ptrace_jit') or destination.suffix == '.dylib':
        destination.chmod(0o755)


def stage(archive_path, variant, want_engine):
    with zipfile.ZipFile(archive_path) as archive:
        bad = archive.testzip()
        if bad is not None:
            fail('Corrupted archive member: ' + bad)
        prefix, names = app_files(archive)
        if want_engine:
            extracted = 0
            for name in names:
                path = name[len(prefix):]
                if path.startswith('Frameworks/'):
                    relative = path[len('Frameworks/'):]
                    write_member(archive, name, FRAMEWORKS / relative)
                    extracted += 1
            if extracted < 5:
                fail('Official Reynard asset does not contain Gecko runtime frameworks')
            header = FRAMEWORKS / 'GeckoView.framework' / 'Headers' / 'IOSBootstrap.h'
            if header.is_file():
                dest = EXT / 'GeckoHeaders' / 'IOSBootstrap.h'
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(header, dest)
        helper_start = 'PlugIns/Reynard Helper.appex/'
        helper_dest = EXT / variant / 'PlugIns' / 'Reynard Helper.appex'
        count = 0
        for name in names:
            relative = name[len(prefix):]
            if relative.startswith(helper_start):
                write_member(archive, name, helper_dest / relative[len(helper_start):])
                count += 1
        if count == 0:
            fail('Official release has no Reynard Helper.appex for ' + variant)
        if variant == 'trollstore':
            ptrace = prefix + 'ts_ptrace_jit'
            if ptrace not in names:
                fail('Official TrollStore release has no ts_ptrace_jit')
            dest = EXT / 'trollstore' / 'ts_ptrace_jit'
            write_member(archive, ptrace, dest)
            dest.chmod(0o755)


def main():
    variant = sys.argv[1] if len(sys.argv) > 1 else 'both'
    if variant not in ('both', 'sideload', 'trollstore'):
        fail('Invalid build variant')
    order = ['sideload', 'trollstore'] if variant == 'both' else [variant]
    for current in order:
        engine_missing = not (FRAMEWORKS / 'GeckoView.framework' / 'GeckoView').is_file() or not (FRAMEWORKS / 'XUL').is_file()
        helper_missing = not (EXT / current / 'PlugIns' / 'Reynard Helper.appex' / 'Reynard Helper').is_file()
        ptrace_missing = current == 'trollstore' and not (EXT / 'trollstore' / 'ts_ptrace_jit').is_file()
        if not (engine_missing or helper_missing or ptrace_missing):
            continue
        asset_name = 'Reynard.ipa' if current == 'sideload' else 'Reynard-TrollStore.tipa'
        print('PUBLIC_ENGINE=' + RELEASE + ' ASSET=' + asset_name, flush=True)
        with tempfile.TemporaryDirectory(prefix='reynard-public-', dir=str(ROOT)) as temporary:
            path = Path(temporary) / asset_name
            fetch_asset(asset_name, path)
            stage(path, current, engine_missing)
    # The public release is a runtime, not a compiler SDK. Use the locally
    # prepared GeckoView development interface, or the checked-in SDK files.
    sdk = ROOT / 'BuildSupport' / 'GeckoSDK'
    local_sdk = Path(os.environ.get('LEGACYRELAY_GECKO_SDK',
        str(Path.home() / 'Downloads/LegacyRelay-ReynardSDK-0.16.0/DevelopedGeckoView.framework')))
    if not (sdk / 'Modules/module.modulemap').is_file() or not (sdk / 'Headers/IOSBootstrap.h').is_file():
        if not (local_sdk / 'Modules/module.modulemap').is_file() or not (local_sdk / 'Headers/IOSBootstrap.h').is_file():
            fail('GeckoView compiler SDK is missing. Set LEGACYRELAY_GECKO_SDK to a matching DevelopedGeckoView.framework path.')
        for component in ('Headers', 'Modules'):
            shutil.copytree(local_sdk / component, sdk / component, dirs_exist_ok=True)
    compiled = FRAMEWORKS / 'GeckoView.framework'
    if not compiled.is_file() and not compiled.is_dir():
        fail('GeckoView runtime framework is missing')
    for component in ('Headers', 'Modules'):
        shutil.copytree(sdk / component, compiled / component, dirs_exist_ok=True)
    (EXT / 'GeckoHeaders').mkdir(parents=True, exist_ok=True)
    shutil.copy2(sdk / 'Headers' / 'IOSBootstrap.h', EXT / 'GeckoHeaders' / 'IOSBootstrap.h')
    required = [
        FRAMEWORKS / 'GeckoView.framework' / 'GeckoView',
        FRAMEWORKS / 'GeckoView.framework' / 'Modules' / 'module.modulemap',
        FRAMEWORKS / 'XUL',
        EXT / 'GeckoHeaders' / 'IOSBootstrap.h',
    ]
    for suffix in ('libmozglue', 'libnss3', 'libfreebl3', 'libsoftokn3',
                   'liblgpllibs', 'libmozavcodec', 'libmozavutil',
                   'libgkcodecs', 'libmozinference'):
        required.append(FRAMEWORKS / (suffix + '.dylib'))
    for current in order:
        required.append(EXT / current / 'PlugIns' / 'Reynard Helper.appex' / 'Reynard Helper')
    if 'trollstore' in order:
        required.append(EXT / 'trollstore' / 'ts_ptrace_jit')
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file() or path.stat().st_size == 0]
    if missing:
        fail('Public release does not provide the required compiler/runtime files: ' + ', '.join(missing))
    print('PUBLIC_RUNTIME=READY', flush=True)


if __name__ == '__main__':
    main()
