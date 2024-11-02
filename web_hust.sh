#!/bin/bash
# web_hust.sh

# Constants
IP="59.77.227.53"
EPORTAL_URL="http://$IP/eportal"
STATUS_URL="http://connect.rom.miui.com/generate_204"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36 Edg/112.0.0.0"

# Check if online
check_online() {
  resp_code=$(curl -s -I -m 10 -o /dev/null -s -w "%{http_code}" "$STATUS_URL")
  if [ "$resp_code" = "204" ]; then
    echo "You are already online!"
    exit 0
  fi
}

# Handle logout requests
logout_user() {
  resp_header=$(curl -s -A "$UA" -I "$EPORTAL_URL/redirectortosuccess.jsp")
  user_index=$(echo "$resp_header" | grep -o 'userIndex=.*')
  echo "userIndex: $user_index"
  logout_result=$(curl -s -A "$UA" -d "userIndex=$user_index" "$EPORTAL_URL/InterFace.do?method=logout")
  echo "$logout_result"
}

# Handle login requests
login_user() {
  redirect_url=$(curl -s "$STATUS_URL" | awk -F \' '{print $2}')
  # echo "redirect_url: $redirect_url"

  query_string=$(echo "$redirect_url" | awk -F \? '{print $2}')
  query_string=$(echo "$query_string" | sed 's/&/%2526/g; s/=/&%253D/g')
  # echo "query_string: $query_string"

  # Get RSA public key
  resp=$(curl -s -A "$UA" -d "queryString=$query_string" "$EPORTAL_URL/InterFace.do?method=pageInfo")
  rsa_e=$(echo "$resp" | awk -F '"publicKeyExponent":"' '{print $2}' | awk -F '"' '{print $1}')
  rsa_n=$(echo "$resp" | awk -F '"publicKeyModulus":"' '{print $2}' | awk -F '"' '{print $1}')
  # echo "rsa_e: $rsa_e, rsa_n: $rsa_n"

  # Encrypt password
  mac=$(echo "$redirect_url" | awk -F 'mac=' '{print $2}' | awk -F '&' '{print $1}')
  password=$(./rsa_encrypt "$2\>$mac" "$rsa_e" "$rsa_n")
  # echo "password: $password"

  auth_result=$(
    curl -s -A "$UA" \
      -e "$redirect_url" \
      -d "userId=$1&password=$password&service=&queryString=$query_string&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=true" \
      -H "Host: $IP" \
      -H "Origin: http://$IP" \
      -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" \
      -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
      "$EPORTAL_URL/InterFace.do?method=login"
  )
  echo "$auth_result"
}

# Main
if [ "$1" = "logout" ]; then
  logout_user
  exit 0
fi

if [ "$#" -ne "2" ]; then
  echo 'Usage: ./web_hust.sh <username> <password>'
  echo 'If you want to logout, use: ./web_hust.sh logout'
  exit 1
fi

# check_online

login_user "$1" "$2"
