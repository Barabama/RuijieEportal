#!/bin/sh
# rjeportal.sh - Ruijie ePortal authenticator for OpenWrt.
#
# This script intentionally uses only POSIX shell and curl so it can run on
# ImmortalWrt without Python, Bash, GMP, or gmpy2.

PATH=/usr/sbin:/usr/bin:/sbin:/bin

PORTAL_IP=${PORTAL_IP:-172.16.0.46}
EPORTAL_URL=${EPORTAL_URL:-http://$PORTAL_IP/eportal}
STATUS_URL=${STATUS_URL:-http://connect.rom.miui.com/generate_204}
USERINDEX_FILE=${USERINDEX_FILE:-/tmp/rjeportal_userindex}
ENCRYPTION=${ENCRYPTION:-/usr/libexec/rjeportal/encrypt_mipsel_24kc}
CURL=${RJEPORTAL_CURL:-curl}
TIMEOUT=${RJEPORTAL_TIMEOUT:-15}
UA=${RJEPORTAL_UA:-Mozilla/5.0\ (Windows\ NT\ 10.0;\ Win64;\ x64)\ AppleWebKit/537.36\ (KHTML,\ like\ Gecko)\ Chrome/112.0.0.0\ Safari/537.36\ Edg/112.0.0.0}

TMP_DIR=$(mktemp -d /tmp/rjeportal.XXXXXX 2>/dev/null) || {
    echo "rjeportal: cannot create private temporary directory" >&2
    exit 1
}
TMP_PREFIX=$TMP_DIR/rjeportal

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup 0 HUP INT TERM

need_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "rjeportal: required command not found: $1" >&2
        return 1
    }
}

curl_get() {
    # --noproxy avoids accidentally sending the captive-portal handshake into
    # an explicitly configured application proxy. Transparent proxy rules are
    # still controlled by the router's firewall/Nikki configuration.
    "$CURL" -sS -A "$UA" --noproxy '*' --connect-timeout 5 --max-time "$TIMEOUT" "$@"
}

extract_query() {
    url=$1
    case "$url" in
        *index.jsp\?*)
            qs=${url#*index.jsp?}
            qs=${qs%%#*}
            printf '%s\n' "$qs"
            return 0
            ;;
    esac
    return 1
}

extract_location() {
    sed -n 's/^[Ll]ocation:[[:space:]]*\([^[:space:]][^[:space:]]*\).*/\1/p' "$1" | head -n 1
}

extract_query_from_body() {
    # Support the two common ePortal forms: location.href='...' and href='...'.
    sed -n \
        -e "s/.*location\.href=['\"]\([^'\"]*index\.jsp?[^'\"]*\)['\"].*/\1/p" \
        -e "s/.*href=['\"]\([^'\"]*index\.jsp?[^'\"]*\)['\"].*/\1/p" "$1" | head -n 1
}

probe() {
    rm -f "$TMP_PREFIX.body" "$TMP_PREFIX.headers"
    code=$(curl_get -D "$TMP_PREFIX.headers" -o "$TMP_PREFIX.body" -w '%{http_code}' "$STATUS_URL") || {
        # A transport/DNS/TLS failure is not the same as an unauthenticated
        # captive portal. Keep this distinction for the watchdog and LuCI.
        echo unreachable
        return 2
    }
    if [ "$code" = 204 ]; then
        echo online
        return 0
    fi

    # Only classify a response as captive when it contains an ePortal
    # index.jsp query. Other reachable responses have an unknown meaning.
    location=$(extract_location "$TMP_PREFIX.headers")
    if [ -n "$location" ] && extract_query "$location" >/dev/null 2>&1; then
        echo captive
        return 1
    fi
    redirect_url=$(extract_query_from_body "$TMP_PREFIX.body")
    if [ -n "$redirect_url" ] && extract_query "$redirect_url" >/dev/null 2>&1; then
        echo captive
        return 1
    fi

    echo unknown
    return 3
}

get_querystring() {
    rm -f "$TMP_PREFIX.body" "$TMP_PREFIX.headers"
    curl_get -D "$TMP_PREFIX.headers" -o "$TMP_PREFIX.body" "$STATUS_URL" >/dev/null || {
        echo "rjeportal: failed to request connectivity probe" >&2
        return 1
    }

    location=$(extract_location "$TMP_PREFIX.headers")
    if [ -n "$location" ]; then
        query=$(extract_query "$location") || query=
        [ -n "$query" ] && {
            printf '%s\n' "$query"
            return 0
        }
    fi

    redirect_url=$(extract_query_from_body "$TMP_PREFIX.body")
    [ -n "$redirect_url" ] || return 1
    extract_query "$redirect_url"
}

get_mac() {
    # queryString is a URL query. Splitting on '&' avoids GNU sed extensions
    # and works with BusyBox sed on OpenWrt.
    printf '%s\n' "$1" | tr '&' '\n' | sed -n 's/^mac=//p' | head -n 1
}

save_user_index() {
    index_tmp=$(mktemp "${USERINDEX_FILE}.XXXXXX") || return 1
    umask 077
    printf '%s\n' "$1" > "$index_tmp" || {
        rm -f "$index_tmp"
        return 1
    }
    mv -f "$index_tmp" "$USERINDEX_FILE" || {
        rm -f "$index_tmp"
        return 1
    }
}

login_user() {
    user=$1
    pass=$2

    query_string=$(get_querystring) || {
        echo "rjeportal: unable to obtain ePortal queryString" >&2
        return 1
    }
    [ -n "$query_string" ] || {
        echo "rjeportal: ePortal queryString is empty" >&2
        return 1
    }
    page_info=$(curl_get \
        -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
        --data-urlencode "queryString=$query_string" \
        "$EPORTAL_URL/InterFace.do?method=pageInfo") || {
        echo "rjeportal: pageInfo request failed" >&2
        return 1
    }

    rsa_e=$(printf '%s\n' "$page_info" | sed -n 's/.*"publicKeyExponent":"\([^"]*\)".*/\1/p')
    rsa_n=$(printf '%s\n' "$page_info" | sed -n 's/.*"publicKeyModulus":"\([^"]*\)".*/\1/p')
    [ -n "$rsa_e" ] && [ -n "$rsa_n" ] || {
        echo "rjeportal: pageInfo did not return an RSA public key" >&2
        return 1
    }

    [ -x "$ENCRYPTION" ] || {
        echo "rjeportal: encryption binary is missing or not executable: $ENCRYPTION" >&2
        return 1
    }
    mac=$(get_mac "$query_string")
    [ -n "$mac" ] || {
        echo "rjeportal: queryString does not contain mac" >&2
        return 1
    }

    encrypted_password=$($ENCRYPTION "$pass>$mac" "$rsa_e" "$rsa_n") || {
        echo "rjeportal: password encryption failed" >&2
        return 1
    }
    [ -n "$encrypted_password" ] || {
        echo "rjeportal: password encryption returned an empty value" >&2
        return 1
    }

    auth=$(curl_get \
        -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
        --data-urlencode "userId=$user" \
        --data "password=$encrypted_password" \
        --data-urlencode "queryString=$query_string" \
        --data 'passwordEncrypt=true' \
        --data 'service=' \
        --data 'operatorPwd=' \
        --data 'operatorUserId=' \
        --data 'validcode=' \
        "$EPORTAL_URL/InterFace.do?method=login") || {
        echo "rjeportal: login request failed" >&2
        return 1
    }

    printf '%s\n' "$auth"
    printf '%s\n' "$auth" | grep -q '"result"[[:space:]]*:[[:space:]]*"success"' || {
        echo "rjeportal: login failed" >&2
        return 1
    }

    user_index=$(printf '%s\n' "$auth" | sed -n 's/.*"userIndex":"\([^"]*\)".*/\1/p')
    if [ -n "$user_index" ]; then
        save_user_index "$user_index" || {
            echo "rjeportal: failed to save login session" >&2
            return 1
        }
    fi
    return 0
}

logout_user() {
    user_index=
    if [ -f "$USERINDEX_FILE" ]; then
        user_index=$(cat "$USERINDEX_FILE")
    fi

    if [ -z "$user_index" ]; then
        rm -f "$TMP_PREFIX.body" "$TMP_PREFIX.headers"
        curl_get -D "$TMP_PREFIX.headers" -o /dev/null \
            "$EPORTAL_URL/redirectortosuccess.jsp" >/dev/null 2>&1 || true
        location=$(extract_location "$TMP_PREFIX.headers")
        [ -n "$location" ] && user_index=$(printf '%s\n' "$location" | sed -n 's/.*userIndex=\([^&[:space:]]*\).*/\1/p')
    fi

    [ -n "$user_index" ] || {
        echo "rjeportal: no saved userIndex; already logged out or never logged in"
        return 0
    }

    auth=$(curl_get \
        -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
        --data-urlencode "userIndex=$user_index" \
        "$EPORTAL_URL/InterFace.do?method=logout") || {
        echo "rjeportal: logout request failed" >&2
        return 1
    }
    printf '%s\n' "$auth"
    printf '%s\n' "$auth" | grep -q '"result"[[:space:]]*:[[:space:]]*"success"' || return 1
    rm -f "$USERINDEX_FILE"
    return 0
}

need_command "$CURL" || exit 1

case "${1:-}" in
    status)
        [ "$#" -eq 1 ] || {
            echo 'Usage: rjeportal status|login <username> <password>|logout' >&2
            exit 2
        }
        probe
        ;;
    login)
        # Credentials are supplied on stdin by the privileged wrapper, never
        # as command-line arguments (which may be visible in process listings).
        [ "$#" -eq 1 ] || {
            echo 'Usage: rjeportal login' >&2
            exit 2
        }
        user=
        pass=
        IFS= read -r user || {
            echo 'rjeportal: username was not supplied' >&2
            exit 2
        }
        IFS= read -r pass || {
            echo 'rjeportal: password was not supplied' >&2
            exit 2
        }
        [ -n "$user" ] || {
            echo 'rjeportal: username is empty' >&2
            exit 2
        }
        [ -n "$pass" ] || {
            echo 'rjeportal: password is empty' >&2
            exit 2
        }
        state=$(probe 2>/dev/null)
        case "$state" in
            online)
                echo 'rjeportal: already online'
                exit 0
                ;;
            captive)
                ;;
            unreachable)
                echo 'rjeportal: network is unreachable; login was not attempted' >&2
                exit 2
                ;;
            *)
                echo "rjeportal: connectivity state is ${state:-unknown}; login was not attempted" >&2
                exit 3
                ;;
        esac
        login_user "$user" "$pass"
        ;;
    logout)
        [ "$#" -eq 1 ] || {
            echo 'Usage: rjeportal logout' >&2
            exit 2
        }
        logout_user
        ;;
    *)
        echo 'Usage: rjeportal status|login <username> <password>|logout' >&2
        exit 2
        ;;
esac
