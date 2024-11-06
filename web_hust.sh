#!/bin/bash
# web_hust.sh

# Constants
IP="59.77.227.227" # Change to your school's IP
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
  # echo "respHeader: $resp_header"
  user_index=$(echo "$resp_header" | grep -o 'userIndex=[^&]*' | cut -d '=' -f 2)
  # echo "userIndex: $user_index"
  logout_result=$(curl -s -A "$UA" -d "userIndex=$user_index" "$EPORTAL_URL/InterFace.do?method=logout")
  echo "$logout_result"
}

# Handle login requests
login_user() {
  redirect_url=$(curl -s -L "$STATUS_URL" | grep -o "href='[^']*" | cut -d "'" -f 2)
  # echo "redirectURL: $redirect_url"
  query_string=$(echo "$redirect_url" | grep -o "index.jsp?[^']*" | cut -d '?' -f 2)
  query_string=$(echo "$query_string" | sed -e 's/=/%253D/g; s/&/%2526/g')
  # echo "queryString: $query_string"

  # Get RSA public key
  page_info=$(curl -s -A "$UA" -c cookies.txt \
    -d "queryString=$query_string" "$EPORTAL_URL/InterFace.do?method=pageInfo")
  rsa_e=$(echo "$page_info" | grep -o '"publicKeyExponent":"[^"]*' | cut -d '"' -f 4)
  rsa_n=$(echo "$page_info" | grep -o '"publicKeyModulus":"[^"]*' | cut -d '"' -f 4)
  # echo "rsa_e: $rsa_e, rsa_n: $rsa_n"

  # Encrypt password
  mac=$(echo "$redirect_url" | grep -o '&mac=[^&]*' | cut -d '=' -f 2)
  # echo "secret: $2>$mac"
  password=$(./encrypt "$2>$mac" "$rsa_e" "$rsa_n")
  # password=$2 # Password Unencrypted
  # echo "password: $password"

  auth_result=$(
    curl -s -A "$UA" \
      -b cookies.txt \
      -e "$redirect_url" \
      -d "userId=$1" \
      -d "password=$password" \
      -d "queryString=$query_string" \
      -d "passwordEncrypt=true" \
      -d "service=&operatorPwd=&operatorUserId=&validcode=" \
      -H "Host: $IP" \
      -H "Origin: http://$IP" \
      -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" \
      -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
      "$EPORTAL_URL/InterFace.do?method=login"
  )
  rm -f cookies.txt
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

check_online

login_user "$1" "$2"
