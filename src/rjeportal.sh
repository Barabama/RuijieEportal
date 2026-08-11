#!/bin/bash
# rjeportal.sh - Ruijie ePortal 校园网认证 Shell 脚本 (路由器友好)
#
# 用法:
#   sh rjeportal.sh login <用户名> <密码>     # 登录 (RSA 加密)
#   sh rjeportal.sh logout                    # 登出
#   sh rjeportal.sh status                    # 检查状态
#
# 依赖:
#   - HTTP 客户端: curl 优先, 回退 wget (兼容 OpenWrt uclient-fetch)
#   - RSA 加密: 需要编译好的 encrypt 二进制 (见 dist/), 路径可用 ENCRYPTION 环境变量覆盖
#   - eportal 的 login 接口不要求 cookie, 故无需 cookie 管理
#
# 注意: uclient-fetch 不支持 -I/-S/-b/-c/-w/--data-urlencode.
#       logout 依赖登录时保存的 userIndex (默认 /tmp/rjeportal_userindex).

# ===== 配置区 =====
IP="${PORTAL_IP:-172.16.0.46}"            # 认证门户 IP (可用环境变量 PORTAL_IP 覆盖)
EPORTAL_URL="http://$IP/eportal"
STATUS_URL="${STATUS_URL:-http://connect.rom.miui.com/generate_204}"  # 204 探测地址
USERINDEX_FILE="${USERINDEX_FILE:-/tmp/rjeportal_userindex}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36 Edg/112.0.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ----- 自动识别加密二进制: 按系统架构选择 dist/ 下对应文件 -----
# 优先级: 环境变量 ENCRYPTION > 自动识别 > 默认 mipsel_24kc
detect_arch() {
    # OpenWrt/ImmortalWrt 提供最可靠架构信息 (含完整名, 如 aarch64_cortex-a53 / mipsel_24kc)
    local arch
    arch=$(sed -n "s/^DISTRIB_ARCH='\([^']*\)'/\1/p" /etc/openwrt_release 2>/dev/null)
    [ -z "$arch" ] && arch=$(uname -m 2>/dev/null)
    echo "$arch"
}

detect_encryption() {
    local d="$SCRIPT_DIR/../dist"
    case "$(detect_arch)" in
        x86_64|amd64)                     echo "$d/encrypt_x86_64" ;;

        # AArch64: 一份二进制兼容全 cortex, 按完整架构名取对应文件
        aarch64_cortex-a53)               echo "$d/encrypt_aarch64_cortex-a53" ;;
        aarch64_cortex-a72)               echo "$d/encrypt_aarch64_cortex-a72" ;;
        aarch64_cortex-a76)               echo "$d/encrypt_aarch64_cortex-a76" ;;
        aarch64_generic|aarch64*|arm64*)  echo "$d/encrypt_aarch64_generic" ;;

        # ARMv7 32位: FPU 不同必须精确匹配, 未知 arm* 回退最常用的 a7
        arm_cortex-a7_neon-vfpv4)         echo "$d/encrypt_arm_cortex-a7_neon-vfpv4" ;;
        arm_cortex-a15_neon-vfpv4)        echo "$d/encrypt_arm_cortex-a15_neon-vfpv4" ;;
        arm_cortex-a9_vfpv3-d16)          echo "$d/encrypt_arm_cortex-a9_vfpv3-d16" ;;
        arm*)                             echo "$d/encrypt_arm_cortex-a7_neon-vfpv4" ;;

        # MIPS 24Kc: 大小端各一
        mipsel*)                          echo "$d/encrypt_mipsel_24kc" ;;
        mips_24kc)                        echo "$d/encrypt_mips_24kc" ;;
        # uname -m 对 mips 只报 "mips" 不分大小端; 绝大多数 mips 路由器是小端
        mips|mips*)                       echo "$d/encrypt_mipsel_24kc" ;;

        *)                                echo "" ;;   # 未知架构 (如 i386/armv6l), 需手动指定
    esac
}

if [ -z "${ENCRYPTION:-}" ]; then
    ENCRYPTION="$(detect_encryption)"
    if [ -z "$ENCRYPTION" ]; then
        echo "Warning: 无法自动识别架构($(detect_arch)), 回退默认 mipsel_24kc. 可用 ENCRYPTION=/path/to/encrypt 覆盖." >&2
        ENCRYPTION="$SCRIPT_DIR/../dist/encrypt_mipsel_24kc"
    fi
    if [ ! -x "$ENCRYPTION" ]; then
        echo "Warning: 加密二进制不存在或不可执行: $ENCRYPTION" >&2
        echo "         请设置 ENCRYPTION 环境变量, 或参照 README 交叉编译." >&2
    fi
fi
# ==================

# ----- 下载工具封装: 统一 get/post, 同时支持 curl 和 wget(uclient-fetch) -----
# http_post <data> <url>   # data 需已 URL 编码 (见 urlencode)
if command -v curl >/dev/null 2>&1; then
    http_get()    { curl -s -A "$UA" -L --max-time 10 "$@"; }
    http_post()   { curl -s -A "$UA" -d "$1" --max-time 10 "$2"; }
else
    http_get()    { wget -q -U "$UA" -O - -T 10 "$@"; }
    http_post()   { wget -q -U "$UA" -O - -T 10 --post-data "$1" "$2"; }
fi

# ----- URL 编码: 供 queryString 作为表单值使用 (uclient-fetch 无 --data-urlencode) -----
urlencode() {
    echo "$1" | sed 's/%/%25/g; s/&/%26/g; s/=/%3D/g; s/ /%20/g'
}

# ----- 状态检测: 在线时 204 地址返回空体, 未认证时被拦截返回 HTML -----
check_status() {
    body=$(http_get "$STATUS_URL" 2>/dev/null)
    if [ -z "$body" ]; then
        echo "online"
        return 0
    else
        echo "offline"
        return 1
    fi
}

# ----- 触发拦截, 提取 eportal index.jsp 的 queryString -----
get_querystring() {
    html=$(http_get "$STATUS_URL")
    # 两种常见拦截格式: location.href='...' 或 href='...'
    redirect_url=$(echo "$html" | grep -o "location.href='[^']*" | head -1 | sed "s/location.href='//")
    [ -z "$redirect_url" ] && redirect_url=$(echo "$html" | grep -o "href='[^']*" | head -1 | sed "s/href='//")
    [ -z "$redirect_url" ] && return 1
    echo "$redirect_url" | sed -n 's/.*index.jsp?//p'
}

login_user() {
    local user="$1" pass="$2"

    qs=$(get_querystring)
    [ -z "$qs" ] && { echo "Failed to get queryString (already online?)."; return 1; }
    echo "queryString: $qs"

    # 拉取 RSA 公钥
    page_info=$(http_post "queryString=$(urlencode "$qs")" "$EPORTAL_URL/InterFace.do?method=pageInfo")
    rsa_e=$(echo "$page_info" | sed -n 's/.*"publicKeyExponent":"\([^"]*\)".*/\1/p')
    rsa_n=$(echo "$page_info" | sed -n 's/.*"publicKeyModulus":"\([^"]*\)".*/\1/p')
    [ -z "$rsa_n" ] && { echo "Failed to get public key."; return 1; }

    # RSA 加密: secret = password>MAC
    mac=$(echo "$qs" | sed -n 's/.*\bmac=\([^&]*\).*/\1/p')
    password=$($ENCRYPTION "$pass>$mac" "$rsa_e" "$rsa_n")
    [ -z "$password" ] && { echo "Encryption failed: $ENCRYPTION"; return 1; }

    auth=$(http_post "userId=$(urlencode "$user")&password=$password&queryString=$(urlencode "$qs")&passwordEncrypt=true&service=&operatorPwd=&operatorUserId=&validcode=" \
        "$EPORTAL_URL/InterFace.do?method=login")
    echo "$auth"

    # 保存 userIndex 供 logout 使用
    ui=$(echo "$auth" | sed -n 's/.*"userIndex":"\([^"]*\)".*/\1/p')
    [ -n "$ui" ] && echo "$ui" > "$USERINDEX_FILE" && echo "saved userIndex -> $USERINDEX_FILE"
}

logout_user() {
    local user_index=""

    # 1. 优先用登录时保存的 userIndex
    [ -f "$USERINDEX_FILE" ] && user_index=$(cat "$USERINDEX_FILE")

    # 2. curl 可用时, 尝试从 redirectortosuccess.jsp 重定向头拿 userIndex
    if [ -z "$user_index" ] && command -v curl >/dev/null 2>&1; then
        headers=$(curl -s -I --max-time 10 "$EPORTAL_URL/redirectortosuccess.jsp")
        user_index=$(echo "$headers" | grep -o 'userIndex=[^&]*' | head -1 | cut -d '=' -f 2)
    fi

    if [ -z "$user_index" ]; then
        echo "No saved userIndex (run login first) or already logged out."
        return 0
    fi

    echo "userIndex: $user_index"
    http_post "userIndex=$user_index" "$EPORTAL_URL/InterFace.do?method=logout"
    rm -f "$USERINDEX_FILE"
}

# ===== 主入口: 仅直接运行时执行, 被 source 时只导出函数供复用 =====
if [ "$(basename "$0")" = "rjeportal.sh" ]; then
case "$1" in
    logout)
        logout_user ;;
    status)
        check_status ;;
    login)
        [ "$#" -ne "3" ] && { echo 'Usage: sh rjeportal.sh login <username> <password>'; exit 1; }
        if [ "$(check_status)" = "online" ]; then
            echo "You are already online!"
        else
            login_user "$2" "$3"
        fi
        ;;
    *)
        echo 'Usage: sh rjeportal.sh {login <用户名> <密码>|logout|status}'
        exit 1 ;;
esac
fi
