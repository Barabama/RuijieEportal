#!/bin/sh
# rjeportal.sh - legacy CLI adapter for manual deployments.
#
# The implementation lives in package/rjeportal/files/rjeportal.sh. This file
# keeps the historical interface used by main.sh and
# docs/无限制校园网路由器.md:
#
#   sh rjeportal.sh status
#   sh rjeportal.sh login <username> <password>
#   sh rjeportal.sh logout
#
# On an OpenWrt router prefer installing the rjeportal IPK: it adds a UCI
# config, a watchdog and the LuCI page.
#
# Environment overrides are passed through to the core: PORTAL_IP, STATUS_URL,
# USERINDEX_FILE and ENCRYPTION. ENCRYPTION is auto-detected from
# /etc/openwrt_release against the prebuilt binaries in dist/.
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
CORE="$SCRIPT_DIR/../package/rjeportal/files/rjeportal.sh"

[ -f "$CORE" ] || {
    echo "rjeportal: core not found: $CORE" >&2
    exit 1
}

usage() {
    echo 'Usage: sh rjeportal.sh {login <username> <password>|logout|status}' >&2
    exit 1
}

detect_arch() {
    arch=$(sed -n "s/^DISTRIB_ARCH='\([^']*\)'/\1/p" /etc/openwrt_release 2>/dev/null)
    [ -n "$arch" ] || arch=$(uname -m 2>/dev/null)
    printf '%s\n' "$arch"
}

# Map the OpenWrt architecture name to the prebuilt binary in dist/.
detect_encryption() {
    d="$SCRIPT_DIR/../dist"
    case "$(detect_arch)" in
        x86_64|amd64)                     echo "$d/encrypt_x86_64" ;;

        aarch64_cortex-a53)               echo "$d/encrypt_aarch64_cortex-a53" ;;
        aarch64_cortex-a72)               echo "$d/encrypt_aarch64_cortex-a72" ;;
        aarch64_cortex-a76)               echo "$d/encrypt_aarch64_cortex-a76" ;;
        aarch64_generic|aarch64*|arm64*)  echo "$d/encrypt_aarch64_generic" ;;

        arm_cortex-a7_neon-vfpv4)         echo "$d/encrypt_arm_cortex-a7_neon-vfpv4" ;;
        arm_cortex-a15_neon-vfpv4)        echo "$d/encrypt_arm_cortex-a15_neon-vfpv4" ;;
        arm_cortex-a9_vfpv3-d16)          echo "$d/encrypt_arm_cortex-a9_vfpv3-d16" ;;
        arm*)                             echo "$d/encrypt_arm_cortex-a7_neon-vfpv4" ;;

        mipsel*)                          echo "$d/encrypt_mipsel_24kc" ;;
        mips_24kc)                        echo "$d/encrypt_mips_24kc" ;;
        mips|mips*)                       echo "$d/encrypt_mipsel_24kc" ;;

        *)                                echo "" ;;
    esac
}

if [ -z "${ENCRYPTION:-}" ]; then
    ENCRYPTION=$(detect_encryption)
    if [ -z "$ENCRYPTION" ]; then
        echo "Warning: unknown architecture $(detect_arch); falling back to mipsel_24kc." >&2
        ENCRYPTION="$SCRIPT_DIR/../dist/encrypt_mipsel_24kc"
    fi
    if [ ! -x "$ENCRYPTION" ]; then
        echo "Warning: encryption binary missing or not executable: $ENCRYPTION" >&2
        echo "         Set ENCRYPTION=/path/to/encrypt or see the README." >&2
    fi
    export ENCRYPTION
fi

case "${1:-}" in
    status)
        [ "$#" -eq 1 ] || usage
        state=$(sh "$CORE" status)
        # Keep the historical online/offline contract on stdout and put the
        # more precise reason on stderr.
        case "$state" in
            online)
                printf 'online\n'
                exit 0
                ;;
            captive)
                printf 'offline\n'
                exit 1
                ;;
            unreachable)
                printf 'offline\n'
                echo "rjeportal: network unreachable (probe failed)" >&2
                exit 1
                ;;
            *)
                printf 'offline\n'
                echo "rjeportal: probe returned ${state:-unknown}" >&2
                exit 1
                ;;
        esac
        ;;
    logout)
        [ "$#" -eq 1 ] || usage
        exec sh "$CORE" logout
        ;;
    login)
        [ "$#" -eq 3 ] || usage
        # Credentials travel through stdin so they do not appear in `ps`.
        printf '%s\n%s\n' "$2" "$3" | sh "$CORE" login
        exit $?
        ;;
    *)
        usage
        ;;
esac
