#!/bin/sh
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
set -eu
: "${PROJECT_DIR:?Missing PROJECT_DIR}"
: "${TARGET_BUILD_DIR:?Missing TARGET_BUILD_DIR}"
: "${FULL_PRODUCT_NAME:?Missing FULL_PRODUCT_NAME}"

case "${LEGACYRELAY_VARIANT:-}" in
  sideload|trollstore) ;;
  *) echo 'error: Unsupported LegacyRelay variant' >&2; exit 3 ;;
esac

APP="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
EXT="$PROJECT_DIR/External"
VARIANT="$LEGACYRELAY_VARIANT"
[ -d "$APP" ] || { echo 'error: Xcode app bundle not found' >&2; exit 4; }

mkdir -p "$APP/Frameworks" "$APP/PlugIns"
lr_apfs_copy_ditto "$EXT/Engine/Frameworks" "$APP/Frameworks"
lr_apfs_copy_ditto "$EXT/$VARIANT/PlugIns/Reynard Helper.appex" "$APP/PlugIns/Reynard Helper.appex"
if [ "$VARIANT" = trollstore ]; then
  lr_apfs_copy_ditto "$EXT/trollstore/ts_ptrace_jit" "$APP/ts_ptrace_jit"
  chmod 0755 "$APP/ts_ptrace_jit"
fi

echo "LegacyRelay: embedded the $VARIANT runtime in the Xcode app product."
