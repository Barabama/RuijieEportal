#!/bin/bash
# web_hust.sh

# Constants
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36 Edg/112.0.0.0"
IP="59.77.227.53"
EPORTAL_URL="http://$IP/eportal"
STATUS_URL="http://connect.rom.miui.com/generate_204"

# Check if online
check_online() {
  resp_code=$(curl -s -I -m 10 -o /dev/null -s -w "%{http_code}" "$STATUS_URL")
  if [ "$resp_code" = "204" ]; then
    echo "You are already online!"
    exit 0
  fi
}

hex2dec() {
    local hex
    hex=$(echo -n "$1" | tr '[:lower:]' '[:upper:]')
    echo "obase=10; ibase=16; $hex" | bc
}

# Encrypt password using RSA
encrypt_password() {
    local secret
    local rsa_e
    local rsa_n
    
    secret=$(echo -n "$1" | xxd -p | tr -d '\n')
    secret=$(hex2dec "$secret")
    rsa_e=$(hex2dec "$2")
    rsa_n=$(hex2dec "$3")
    encrypted=$(echo "ibase=10; ($secret ^ $rsa_e) % $rsa_n" | bc)
    # encrypted=$(printf "%x" "$encrypted")
    echo "$encrypted" | xargs printf "%02x"
}

# Handle logout requests
logout_user() {
  user_index=$(curl -s -A "$USER_AGENT" -I "$EPORTAL_URL/redirectortosuccess.jsp" | grep -o 'userIndex=.*')
  logout_result=$(curl -s -A "$USER_AGENT" -d "userIndex=$user_index" "$EPORTAL_URL/InterFace.do?method=logout")
  echo "$logout_result"
}

# Handle login requests
login_user() {
  login_page_url=$(curl -s "$STATUS_URL" | awk -F \' '{print $2}')
  # echo "login_page_url: $login_page_url"

  login_url="$EPORTAL_URL/InterFace.do?method=login"
  # echo "login_url: $login_url"

  query_string=$(echo "$login_page_url" | awk -F \? '{print $2}')
  query_string=$(echo "$query_string" | sed 's/&/%2526/g; s/=/&%253D/g')
  # echo "query_string: $query_string"

  # Get RSA public Key
  resp=$(curl -s -A "$USER_AGENT" -d "queryString=$query_string" "$EPORTAL_URL/InterFace.do?method=pageInfo")
  rsa_e=$(echo "$resp" | awk -F '"publicKeyExponent":"' '{print $2}' | awk -F '"' '{print $1}')
  rsa_n=$(echo "$resp" | awk -F '"publicKeyModulus":"' '{print $2}' | awk -F '"' '{print $1}')
  # echo "rsa_e: $rsa_e, rsa_n: $rsa_n"

  # Encrypt password
  mac=$(echo "$login_page_url" | awk -F 'mac=' '{print $2}' | awk -F '&' '{print $1}')
  secret="$2>$mac"
  echo "$secret"
  password=$(encrypt_password "$secret" "$rsa_e" "$rsa_n")

  auth_result=$(
    curl -s -A "$USER_AGENT" \
      -e "$login_page_url" \
      -b "EPORTAL_COOKIE_DOMAIN=; \
        EPORTAL_COOKIE_SERVER=; \
        EPORTAL_COOKIE_SERVER_NAME=; \
        EPORTAL_COOKIE_OPERATORPWD=; \
        EPORTAL_COOKIE_USERNAME=; \
        EPORTAL_COOKIE_PASSWORD=; \
        EPORTAL_AUTO_LAND=; \
        EPORTAL_USER_GROUP=%E7%A0%94%E7%A9%B6%E7%94%9F%E7%BB%84" \
      -d "userId=$1&password=$password&service=&queryString=$query_string&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=true" \
      -H "Host: $IP" \
      -H "Origin: http://$IP" \
      -H "Referer: $login_page_url" \
      -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" \
      -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
      "$login_url"
  )
  echo "auth_result: $auth_result"
}

# Main
if [ "$1" = "logout" ]; then
  logout_user
  exit 0
fi

if [ "$#" -ne "2" ]; then
  echo "Usage: ./WebHust.sh username password"
  echo "Example: ./WebHust.sh 2024102416 12345678"
  echo "If you want to logout, use: ./WebHust.sh logout"
  exit 1
fi

# check_online

login_user "$1" "$2"