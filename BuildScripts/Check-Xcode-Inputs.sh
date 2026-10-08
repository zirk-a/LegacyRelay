#!/bin/sh
set -eu
: "${PROJECT_DIR:?Missing project directory}"
EXT="$PROJECT_DIR/External"
VARIANT="${LEGACYRELAY_VARIANT:-}"
case "$VARIANT" in sideload|trollstore) ;; *) echo 'Unknown build variant' >&2; exit 2;; esac
check() { [ -s "$EXT/$1" ] || { echo "Missing dependency: External/$1" >&2; exit 3; }; }
check Engine/DDIManager.swift
check Engine/Frameworks/GeckoView.framework/GeckoView
check Engine/Frameworks/GeckoView.framework/Modules/module.modulemap
check Engine/Frameworks/XUL
for library in libmozglue libnss3 libfreebl3 libsoftokn3 liblgpllibs libmozavcodec libmozavutil libgkcodecs libmozinference; do
  check "Engine/Frameworks/$library.dylib"
done
check GeckoHeaders/IOSBootstrap.h
check Addons/uaswitcher-1.4.102.xpi
check CompatInclude/xpc/xpc.h
check "$VARIANT/PlugIns/Reynard Helper.appex/Reynard Helper"
if [ "$VARIANT" = sideload ]; then
  for obj in JITEnabler JITSupport JITUtils JITErrors Utils; do check "LinkObjects/$obj.o"; done
  check RPPairing/libidevice_ffi.a
  check Reynard/browser/Reynard/JIT/JITEnabler.h
else
  check trollstore/ts_ptrace_jit
fi
