#!/bin/bash
lr_apfs_copy_ditto() (
    [ "$#" -eq 2 ] || return 85
    src="$1"
    dst="$2"
    if [ -d "$src" ] && [ ! -L "$src" ]; then
        [ ! -e "$dst" ] || [ -d "$dst" ] || return 85
        /bin/mkdir -p "$dst" || return
        /bin/cp -c -pR "$src/." "$dst/" || return
    elif [ -f "$src" ] && [ ! -L "$src" ]; then
        /bin/mkdir -p "$(/usr/bin/dirname "$dst")" || return
        /bin/cp -c -p "$src" "$dst" || return
    else
        return 85
    fi
)
lr_sign_nested_macho() {
  local binary="$1"
  if /usr/bin/codesign --verify --strict "$binary" >/dev/null 2>&1; then
    echo "NESTED_VALID_SIGNATURE_REUSED=${binary##*/}"
    return 0
  fi
  if [ "${binary##*/}" = XUL ]; then
    echo 'FAIL=XUL_SIGNATURE_INVALID_NO_LARGE_RESIGN' >&2
    return 1
  fi
  /usr/bin/codesign --force --sign - --timestamp=none "$binary" || return
  /usr/bin/codesign --verify --strict "$binary"
}
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT="$PROJECT_DIR/LegacyRelay.xcodeproj"
OUTPUT="$PROJECT_DIR/BuildProducts"
DERIVED="$PROJECT_DIR/DerivedData"
VARIANT="${1:-both}"
case "$VARIANT" in sideload|trollstore|both) ;; *) echo 'Usage: ./Build.command [sideload|trollstore|both]' >&2; exit 2 ;; esac
for tool in xcodebuild xcrun ditto codesign zip unzip python3 file; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing macOS tool: $tool" >&2; exit 3; }
done
. "$PROJECT_DIR/BuildScripts/Select-Xcode.sh"
[ -s "$PROJECT/project.pbxproj" ] || { echo 'FAIL=NO_XCODE_PROJECT' >&2; exit 4; }
mkdir -p "$OUTPUT"
required=(
  "$PROJECT_DIR/External/Engine/Frameworks/XUL"
  "$PROJECT_DIR/External/Engine/Frameworks/GeckoView.framework/GeckoView"
  "$PROJECT_DIR/External/Engine/Frameworks/GeckoView.framework/Modules/module.modulemap"
  "$PROJECT_DIR/External/GeckoHeaders/IOSBootstrap.h"
  "$PROJECT_DIR/External/Addons/uaswitcher-1.4.102.xpi"
)
case "$VARIANT" in
  sideload) required+=("$PROJECT_DIR/External/RPPairing/libidevice_ffi.a" "$PROJECT_DIR/External/LinkObjects/JITEnabler.o") ;;
  trollstore) required+=("$PROJECT_DIR/External/trollstore/ts_ptrace_jit") ;;
  both) required+=("$PROJECT_DIR/External/trollstore/ts_ptrace_jit" "$PROJECT_DIR/External/RPPairing/libidevice_ffi.a" "$PROJECT_DIR/External/LinkObjects/JITEnabler.o") ;;
esac
prepare=0
for input in "${required[@]}"; do [ -s "$input" ] || prepare=1; done
if [ "$prepare" -eq 1 ]; then
  "$PROJECT_DIR/BuildScripts/Prepare-Dependencies.sh" "$VARIANT"
fi
if [ "$VARIANT" = both ]; then
  variants=(sideload trollstore)
else
  variants=("$VARIANT")
fi
for check_variant in "${variants[@]}"; do
  PROJECT_DIR="$PROJECT_DIR" LEGACYRELAY_VARIANT="$check_variant" "$PROJECT_DIR/BuildScripts/Check-Xcode-Inputs.sh"
done

ACTIVE_TEMP=''
cleanup() {
  if [ -n "$ACTIVE_TEMP" ] && [[ "$ACTIVE_TEMP" == "$OUTPUT"/.bundle.* ]] && [ -d "$ACTIVE_TEMP" ]; then
    rm -rf "$ACTIVE_TEMP"
  fi
}
trap cleanup EXIT

build_variant() {
  local variant="$1" scheme file ent app_dir app_path tmp staged jit gecko extension extension_ent nested count
  if [ "$variant" = trollstore ]; then
    scheme=LegacyRelay-TrollStore
    file=LegacyRelay-TrollStore.tipa
    ent="$PROJECT_DIR/Configurations/TrollStore.entitlements"
  else
    scheme=LegacyRelay-Sideload
    file=LegacyRelay-Sideload.ipa
    ent=''
  fi
  local args=(-project "$PROJECT" -scheme "$scheme" -configuration Release -sdk iphoneos \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO)
  xcodebuild "${args[@]}" build
  app_dir="$(xcodebuild "${args[@]}" -showBuildSettings | awk -F ' = ' '$1 ~ /^[[:space:]]*TARGET_BUILD_DIR$/ {print $2; exit}')"
  [ -n "$app_dir" ] || { echo 'FAIL=XCODE_PRODUCT_PATH_MISSING' >&2; exit 5; }
  app_path="$app_dir/LegacyRelay.app"
  [ -s "$app_path/LegacyRelay" ] || { echo 'FAIL=XCODE_APP_MISSING' >&2; exit 5; }
  for required_file in Frameworks/GeckoView.framework/GeckoView Frameworks/XUL 'PlugIns/Reynard Helper.appex/Reynard Helper'; do
    [ -s "$app_path/$required_file" ] || { echo "FAIL=EMBEDDED_RUNTIME_MISSING:$required_file" >&2; exit 6; }
  done
  if [ "$variant" = trollstore ]; then
    [ -s "$app_path/ts_ptrace_jit" ] || { echo 'FAIL=TROLLSTORE_JIT_MISSING' >&2; exit 6; }
  fi
  tmp="$(mktemp -d "$OUTPUT/.bundle.XXXXXXXX")"
  ACTIVE_TEMP="$tmp"
  mkdir -p "$tmp/Payload"
  staged="$tmp/Payload/LegacyRelay.app"
  lr_apfs_copy_ditto "$app_path" "$staged"
  cp "$PROJECT_DIR/External/Addons/uaswitcher-1.4.102.xpi" "$staged/uaswitcher-1.4.102.xpi"
  bridge_src="$PROJECT_DIR/Resources/extensions/legacyrelay-cookie-session"
  [ -f "$bridge_src/manifest.json" ] && [ -f "$bridge_src/background.js" ] && [ -f "$bridge_src/content.js" ] || { echo 'FAIL=BUILTIN_BRIDGE_MISSING' >&2; exit 7; }
  mkdir -p "$staged/extensions/legacyrelay-cookie-session"
  cp "$bridge_src/manifest.json" "$bridge_src/background.js" "$bridge_src/content.js" "$staged/extensions/legacyrelay-cookie-session/"
  helper_bridge="$staged/PlugIns/Reynard Helper.appex/extensions/legacyrelay-cookie-session"
  [ -d "$staged/PlugIns/Reynard Helper.appex" ] || { echo 'FAIL=GECKO_HELPER_BUNDLE_MISSING' >&2; exit 7; }
  mkdir -p "$helper_bridge"
  cp "$bridge_src/manifest.json" "$bridge_src/background.js" "$bridge_src/content.js" "$helper_bridge/"
  python3 - "$staged" "$PROJECT_DIR" <<'PY_GECKO_BUILTIN'
from pathlib import Path
import hashlib,json,shutil,sys
staged=Path(sys.argv[1])
project=Path(sys.argv[2])
src=project/'Resources/extensions/legacyrelay-cookie-session'
gecko=staged/'Frameworks/GeckoView.framework/Frameworks'
module=gecko/'modules/GeckoViewWebExtension.sys.mjs'
if not module.is_file():
    raise SystemExit('STOP=GECKO_EXTENSION_MODULE_NOT_STAGED')
reader='const isIOSReaderViewResource =\n      uri.spec === "resource://app/extensions/readerview/";'
ours='const isIOSLegacyRelaySessionResource =\n      uri.spec === "resource://app/extensions/legacyrelay-cookie-session/";'
s=module.read_text()
checks=[
('if (!isAndroidResource && !isIOSReaderViewResource) {',
 'if (!isAndroidResource && !isIOSReaderViewResource && !isIOSLegacyRelaySessionResource) {'),
('if (!isIOSReaderViewResource && uri.fileName !== "") {',
 'if (!isIOSReaderViewResource && !isIOSLegacyRelaySessionResource && uri.fileName !== "") {')]
if ours in s and all(after in s for _,after in checks):
    print('GECKO_IOS_BUILTIN_ALLOWLIST=ALREADY_STAGED')
else:
    if s.count(reader)!=1 or any(s.count(before)!=1 for before,_ in checks) or 'isIOSLegacyRelaySessionResource' in s:
        raise SystemExit('STOP=GECKO_BUILTIN_VALIDATOR_UNEXPECTED')
    s=s.replace(reader,reader+'\n    '+ours,1)
    for before,after in checks:
        s=s.replace(before,after,1)
    module.write_text(s)
    print('GECKO_IOS_BUILTIN_ALLOWLIST=PATCHED_IN_STAGED_FRAMEWORK')
dest=gecko/'extensions/legacyrelay-cookie-session'
if dest.exists() and any(p.is_symlink() for p in [dest]+list(dest.iterdir())):
    raise SystemExit('STOP=UNEXPECTED_STAGED_EXTENSION_SYMLINK')
dest.mkdir(parents=True,exist_ok=True)
for n in ('manifest.json','background.js','content.js'):
    inp=src/n
    if not inp.is_file() or inp.is_symlink():
        raise SystemExit('STOP=BRIDGE_SOURCE_MISSING:'+n)
    shutil.copy2(inp,dest/n)
manifest=json.loads((dest/'manifest.json').read_text())
if (manifest.get('browser_specific_settings') or {}).get('gecko',{}).get('id')!='legacyrelay-cookie-session-v4@local':
    raise SystemExit('STOP=BRIDGE_ADDON_ID_CHANGED')
assert ours in module.read_text()
print('GECKO_IOS_BUILTIN_RESOURCES=GECKOVIEW_FRAMEWORK')
print('GECKO_MODULE_SHA256='+hashlib.sha256(module.read_bytes()).hexdigest())
PY_GECKO_BUILTIN
  python3 "$PROJECT_DIR/BuildScripts/Prepare-Package.py" "$staged" "$variant"

  if [ "$variant" = trollstore ]; then
    ent="$tmp/trollstore.entitlements"
    python3 "$PROJECT_DIR/BuildScripts/Prepare-TrollStore-Entitlements.py" \
      "$PROJECT_DIR/Configurations/TrollStore.entitlements" "$staged/Info.plist" "$ent"
    jit="$staged/ts_ptrace_jit"
    gecko="$staged/Frameworks/GeckoView.framework"
    extension="$staged/PlugIns/Reynard Helper.appex"
    extension_ent="$tmp/helper.entitlements"
    [ -s "$jit" ] && [ -s "$gecko/GeckoView" ] && [ -s "$extension/Reynard Helper" ] || {
      echo 'FAIL=TROLLSTORE_EMBEDDED_EXECUTABLE_MISSING' >&2; exit 7;
    }
    if ! codesign --verify "$jit" >/dev/null 2>&1; then
      codesign --force --sign - --timestamp=none --entitlements "$ent" "$jit" || {
        echo 'FAIL=TROLLSTORE_JIT_SIGN' >&2; exit 7;
      }
    fi
    codesign --verify "$jit" || { echo 'FAIL=TROLLSTORE_JIT_VERIFY' >&2; exit 7; }
    echo 'TROLLSTORE_JIT_SIGNATURE=PASS'

    count=0
    while IFS= read -r -d '' nested; do
      if /usr/bin/file -b "$nested" | /usr/bin/grep -q 'Mach-O'; then
        lr_sign_nested_macho "$nested" || {
          echo "FAIL=GECKO_BINARY_SIGN:$nested" >&2; exit 7;
        }
        count=$((count+1))
      fi
    done < <(find "$staged/Frameworks" -type f -print0)
    echo "GECKO_MACHO_SIGN_COUNT=$count"
    codesign --force --sign - --timestamp=none "$gecko" || { echo 'FAIL=GECKOVIEW_FRAMEWORK_SIGN' >&2; exit 7; }

    if [ -s "$extension/Reynard Helper" ]; then
      codesign -d --entitlements :- "$extension" > "$extension_ent" 2>/dev/null || true
      if [ -s "$extension_ent" ] && /usr/bin/plutil -lint "$extension_ent" >/dev/null 2>&1; then
        codesign --force --sign - --timestamp=none --entitlements "$extension_ent" "$extension" || {
          echo 'FAIL=GECKO_HELPER_SIGN' >&2; exit 7;
        }
      else
        codesign --force --sign - --timestamp=none --entitlements "$ent" "$extension" || {
          echo 'FAIL=GECKO_HELPER_SIGN' >&2; exit 7;
        }
      fi
    fi
    codesign --verify "$extension" || { echo 'FAIL=GECKO_HELPER_VERIFY' >&2; exit 7; }
    codesign --force --sign - --timestamp=none --entitlements "$ent" "$staged" || {
      echo 'FAIL=TROLLSTORE_APP_SIGN' >&2; exit 7;
    }
    codesign --verify --deep --strict "$staged" || { echo 'FAIL=TROLLSTORE_APP_VERIFY' >&2; exit 7; }
    echo 'TROLLSTORE_PACKAGE_SIGNATURES=PASS'
  else
    gecko="$staged/Frameworks/GeckoView.framework"
    extension="$staged/PlugIns/Reynard Helper.appex"
    [ -s "$extension/Reynard Helper" ] && [ -s "$gecko/GeckoView" ] || {
      echo 'FAIL=SIDELOAD_SIGNING_INPUT_MISSING' >&2; exit 7;
    }
    count=0
    while IFS= read -r -d '' nested; do
      if /usr/bin/file -b "$nested" | /usr/bin/grep -q 'Mach-O'; then
        lr_sign_nested_macho "$nested" || {
          echo "FAIL=SIDELOAD_NESTED_BINARY_SIGN:$nested" >&2; exit 7;
        }
        count=$((count+1))
      fi
    done < <(find "$staged/Frameworks" -type f -print0)
    echo "SIDELOAD_NESTED_MACHO_SIGNED=$count"
    codesign --force --sign - --timestamp=none "$gecko" || { echo 'FAIL=SIDELOAD_GECKOVIEW_SIGN' >&2; exit 7; }
    codesign --force --sign - --timestamp=none "$extension" || { echo 'FAIL=SIDELOAD_HELPER_SIGN' >&2; exit 7; }
    codesign --verify --strict "$extension" || { echo 'FAIL=SIDELOAD_HELPER_VERIFY' >&2; exit 7; }
    echo 'SIDELOAD_HELPER_ARCHIVE_SIGNED=PASS'
    echo 'SIDELOAD_INSTALLER_RESIGN=STILL_REQUIRED'
  fi

  rm -f "$OUTPUT/$file.part"
  (cd "$tmp" && zip -qry "$OUTPUT/$file.part" Payload)
  unzip -tq "$OUTPUT/$file.part" >/dev/null
  python3 "$PROJECT_DIR/BuildScripts/Verify-Package.py" "$OUTPUT/$file.part" "$variant"
  mv -f "$OUTPUT/$file.part" "$OUTPUT/$file"
  rm -rf "$tmp"
  ACTIVE_TEMP=''
  echo "BUILT=$OUTPUT/$file"
}
for variant in "${variants[@]}"; do build_variant "$variant"; done
