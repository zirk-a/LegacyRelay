#!/bin/bash
set -euo pipefail
candidates=()
if [ -n "${DEVELOPER_DIR:-}" ]; then
  candidates+=("$DEVELOPER_DIR")
else
  candidates+=("/Applications/Xcode-13.4.1.app/Contents/Developer")
  current="$(xcode-select -p 2>/dev/null || true)"
  if [ -n "$current" ]; then candidates+=("$current"); fi
  candidates+=("/Applications/Xcode.app/Contents/Developer")
  for app in /Applications/Xcode-*.app /Applications/Xcode_*.app; do
    [ -d "$app" ] && candidates+=("$app/Contents/Developer")
  done
fi
selected=''
for candidate in "${candidates[@]}"; do
  [ -d "$candidate/Platforms/iPhoneOS.platform/Developer/SDKs" ] || continue
  export DEVELOPER_DIR="$candidate"
  sdk="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
  if [ -n "$sdk" ] && [ -d "$sdk" ]; then
    selected="$candidate"
    break
  fi
done
if [ -z "$selected" ]; then
  echo 'FAIL=IPHONEOS_SDK_NOT_FOUND' >&2
  echo 'Install a full Xcode with an iPhoneOS SDK, then set DEVELOPER_DIR to its Contents/Developer directory.' >&2
  exit 18
fi
echo "DEVELOPER_DIR=$DEVELOPER_DIR"
echo "IPHONEOS_SDK=$sdk"
