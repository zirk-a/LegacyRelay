#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
EXT="$HERE/External"
REYNARD="$EXT/Reynard"
VARIANT="${1:-both}"
case "$VARIANT" in sideload|trollstore|both) ;; *) echo 'Usage: Prepare-Dependencies.sh [sideload|trollstore|both]' >&2; exit 2;; esac
. "$HERE/BuildScripts/Select-Xcode.sh"
for tool in git xcodebuild xcrun python3 rustup cargo zip codesign; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing build tool: $tool" >&2; exit 3; }
done
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos --find clang)"
ADDON="$EXT/Addons/uaswitcher-1.4.102.xpi"
if [ ! -s "$ADDON" ]; then
  mkdir -p "$(dirname "$ADDON")"
  ADDON_PATH="$ADDON" python3 - <<'PYEND'
import json,os,urllib.request,zipfile
api='https://addons.mozilla.org/api/v5/addons/addon/uaswitcher/versions/?page_size=50'
with urllib.request.urlopen(api,timeout=30) as res:
    data=json.load(res)
found=next((v for v in data['results'] if v['version']=='1.4.102'),None)
if found is None or not found.get('file',{}).get('url'):
    raise SystemExit('User-Agent Switcher 1.4.102 unavailable from Mozilla Add-ons API')
url=found['file']['url']
path=os.environ['ADDON_PATH']
with urllib.request.urlopen(url,timeout=90) as res, open(path+'.part','wb') as output:
    while chunk:=res.read(1048576): output.write(chunk)
with zipfile.ZipFile(path+'.part') as archive:
    if archive.testzip() is not None or 'manifest.json' not in archive.namelist():
        raise SystemExit('Invalid User-Agent Switcher XPI')
os.replace(path+'.part',path)
PYEND
fi
python3 "$HERE/BuildScripts/Prepare-Public-Runtime.py" "$VARIANT"
mkdir -p "$EXT/CompatInclude/xpc" "$EXT/GeckoHeaders" "$EXT/LinkObjects" "$EXT/RPPairing"
cat > "$EXT/CompatInclude/xpc/xpc.h" <<'HEADER'
#ifndef LEGACYRELAY_XPC_COMPAT_H
#define LEGACYRELAY_XPC_COMPAT_H
typedef struct xpc_object_s *xpc_object_t;
typedef const struct xpc_type_s *xpc_type_t;
typedef struct xpc_connection_s *xpc_connection_t;
#endif
HEADER
SWIFTC="$(xcrun --find swiftc)"
if ! printf 'import GeckoView\n' | "$SWIFTC" -typecheck - \
  -target arm64-apple-ios13.0 -sdk "$SDK" \
  -F "$EXT/Engine/Frameworks" \
  -Xcc "-I$EXT/CompatInclude" \
  -Xcc -Wno-error=non-modular-include-in-framework-module; then
  echo 'FAIL=PUBLIC_GECKOVIEW_COMPILER_MODULE_INCOMPATIBLE' >&2
  echo 'The public Reynard binary SDK is incompatible with this Xcode toolchain.' >&2
  exit 13
fi
if [ "$VARIANT" != trollstore ]; then
  IDEVICE="$REYNARD/support/idevice"
  if [ ! -f "$EXT/RPPairing/libidevice_ffi.a" ]; then
    [ -d "$IDEVICE/.git" ] || git clone --recursive https://github.com/jkcoxson/idevice.git "$IDEVICE"
    rustup target add aarch64-apple-ios
    ( cd "$IDEVICE/ffi"; CARGO_TARGET_DIR="$IDEVICE/target" cargo build --release --target aarch64-apple-ios --no-default-features --features full,ring )
    cp "$IDEVICE/target/aarch64-apple-ios/release/libidevice_ffi.a" "$EXT/RPPairing/libidevice_ffi.a"
    rm -rf "$IDEVICE/target"
  fi
  JIT="$REYNARD/browser/Reynard/JIT"
  names=(JITEnabler JITSupport JITUtils JITErrors Utils)
  for name in "${names[@]}"; do
    case "$name" in
      JITEnabler|JITErrors) source="$JIT/$name.m" ;;
      JITSupport|JITUtils) source="$JIT/RPPairing/$name.m" ;;
      Utils) source="$REYNARD/browser/Reynard/Shared/Utils.m" ;;
    esac
    [ -s "$source" ] || { echo "Missing source: $source" >&2; exit 12; }
    if [ ! -s "$EXT/LinkObjects/$name.o" ]; then
      "$CC" -c -arch arm64 -miphoneos-version-min=13.0 -isysroot "$SDK" \
        -fobjc-arc -fmodules -Wno-error=non-modular-include-in-framework-module \
        -I"$JIT" -I"$JIT/RPPairing" -I"$REYNARD/browser/Reynard/Shared" \
        -I"$EXT/GeckoHeaders" -I"$EXT/CompatInclude" "$source" -o "$EXT/LinkObjects/$name.o"
    fi
  done
fi
printf 'Dependencies prepared for %s\n' "$VARIANT"
