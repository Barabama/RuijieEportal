#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CORE=$ROOT/files/rjeportal.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' 0 HUP INT TERM

cat > "$TMP/fake-curl" <<'EOF'
#!/bin/sh
set -eu
headers=
body=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -D) headers=$2; shift 2 ;;
        -o) body=$2; shift 2 ;;
        -w) shift 2 ;;
        *) shift ;;
    esac
done

case "${RJE_TEST_MODE:-}" in
    unreachable)
        exit 7
        ;;
    online)
        [ -z "$headers" ] || : > "$headers"
        [ -z "$body" ] || : > "$body"
        printf '204'
        ;;
    captive)
        printf '%s\n' 'Location: http://172.16.0.46/eportal/index.jsp?mac=aa:bb:cc:dd:ee:ff&nasip=172.16.0.1' > "$headers"
        : > "$body"
        printf '302'
        ;;
    unknown)
        printf '%s\n' 'Content-Type: text/plain' > "$headers"
        printf '%s\n' 'not a portal response' > "$body"
        printf '200'
        ;;
    *)
        exit 8
        ;;
esac
EOF
chmod +x "$TMP/fake-curl"

check_state() {
    mode=$1
    expected_rc=$2
    expected_state=$3
    set +e
    output=$(RJEPORTAL_CURL="$TMP/fake-curl" RJE_TEST_MODE="$mode" \
        STATUS_URL=http://probe.invalid/generate_204 sh "$CORE" status 2>"$TMP/stderr")
    rc=$?
    set -e
    [ "$rc" -eq "$expected_rc" ] || {
        echo "status $mode: expected rc=$expected_rc, got rc=$rc" >&2
        cat "$TMP/stderr" >&2
        exit 1
    }
    [ "$output" = "$expected_state" ] || {
        echo "status $mode: expected $expected_state, got $output" >&2
        exit 1
    }
}

check_state online 0 online
check_state captive 1 captive
check_state unknown 3 unknown
check_state unreachable 2 unreachable
printf '%s\n' 'rjeportal status contract: ok'