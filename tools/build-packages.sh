#!/bin/sh
# Build rjeportal, luci-app-rjeportal and the luci-app-nettask fork as IPKs
# with an ImmortalWrt SDK for ramips/mt7621 (Xiaomi R3G, mipsel_24kc).
#
# Usage (run inside WSL/Linux):
#   sh tools/build-packages.sh [SDK_DIR]
#
# SDK_DIR defaults to $RJEPORTAL_SDK or ~/immortalwrt-sdk-24.10.6-ramips-mt7621_*.
# Output IPKs are copied to build/ipk/ in this repository.
set -eu

# WSL inherits the Windows PATH, which contains ':' and spaces. OpenWrt's
# Makefiles expand prerequisites through the shell, so keep a clean PATH.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$REPO/build/ipk

SDK=${1:-${RJEPORTAL_SDK:-}}
if [ -z "$SDK" ]; then
    for candidate in "$HOME"/immortalwrt-sdk-24.10.6-ramips-mt7621_*; do
        [ -d "$candidate" ] && SDK=$candidate && break
    done
fi
[ -n "$SDK" ] && [ -f "$SDK/rules.mk" ] || {
    echo "error: ImmortalWrt SDK not found; pass its path as the first argument" >&2
    exit 1
}

LOG=$SDK/rjeportal-build.log
DEST=$SDK/package

# luci-app-nettask is a separate repository and may be absent in a fresh
# clone of this repository (it is ignored here). Build it only when present.
PACKAGES="rjeportal luci-app-rjeportal"
[ -d "$REPO/luci-app-nettask" ] && PACKAGES="$PACKAGES luci-app-nettask"

for pkg in $PACKAGES; do
    rm -rf "$DEST/$pkg"
    mkdir -p "$DEST/$pkg"
done

rsync -a --delete "$REPO/package/rjeportal/" "$DEST/rjeportal/"
rsync -a --delete "$REPO/package/luci-app-rjeportal/" "$DEST/luci-app-rjeportal/"
case " $PACKAGES " in
    *" luci-app-nettask "*)
        rsync -a --delete --exclude .git --exclude .github --exclude png \
            "$REPO/luci-app-nettask/" "$DEST/luci-app-nettask/"
        ;;
esac

cd "$SDK"
cp .config .config.before-rjeportal 2>/dev/null || true

make defconfig >"$LOG.defconfig" 2>&1 || { tail -60 "$LOG.defconfig"; exit 1; }
grep -E '^CONFIG_TARGET_(ramips|ramips_mt7621)=y' .config

for pkg in $PACKAGES; do
    make "package/$pkg/compile" V=s -j"$(nproc)" >"$LOG.$pkg" 2>&1 || {
        echo "=== FAILED: $pkg ==="
        tail -80 "$LOG.$pkg"
        exit 1
    }
done

rm -rf "$OUT"
mkdir -p "$OUT"
for pkg in $PACKAGES; do
    find bin/packages -name "${pkg}_*.ipk" -exec cp {} "$OUT"/ \;
done

echo "=== IPKS ==="
ls -l "$OUT"
sha256sum "$OUT"/*.ipk
