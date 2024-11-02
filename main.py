
# -*- coding: utf-8 -*-
# main.py

import re
import sys
from urllib.parse import urlparse, parse_qs
import requests
import gmpy2


def _encrypt_password(secret: str, rsa_e: int, rsa_n: int) -> str:
    secret_int = int.from_bytes(secret.encode(), "big")
    encrypted_int = gmpy2.powmod(secret_int, rsa_e, rsa_n)
    return hex(encrypted_int)[2:]


class Authenticator:

    def __init__(self):
        self.ip = "59.77.227.53"  # Change to your school's IP
        self.url = f"http://{self.ip}"
        self.session = requests.Session()
        self.session.headers = {
            "Host": self.ip,
            "Origin": self.url,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36 Edg/112.0.0.0",
        }

    def is_online(self) -> bool:
        resp = self.session.get(self.url)
        return "success" in resp.url

    def logout(self) -> dict:
        resp_head = self.session.head(f"{self.url}/eportal/redirectortosuccess.jsp")
        print(resp_head)
        match = re.search(r"userIndex=(.+?)&", resp_head.text)
        if not match:
            return {"result": "error", "message": "userIndex not found"}
        resp = self.session.post(f"{self.url}/eportal/InterFace.do?method=logout",
                                 data={"userIndex": match.group(1)})
        return resp.json()

    def login(self, user: str, passwd: str) -> dict:
        redirect_text = self.session.get(f"{self.url}/eportal/index.jsp").text
        print(redirect_text)
        match = re.search(r"redirectUrl=(.+?)&", redirect_text)
        if not match:
            return {"result": "error", "message": "redirectUrl not found"}
        query_str = urlparse(match.group(1)).query

        # Get RSA public key
        page_info = self.session.post(f"{self.url}/eportal/InterFace.do?method=pageInfo",
                                      data={"queryString": query_str}).json()
        print(page_info)
        rsa_e = int(page_info["publicKeyExponent"], 16)
        rsa_n = int(page_info["publicKeyModulus"], 16)

        # Encrypt password
        secret = f"{passwd}>{parse_qs(query_str)['mac']}"
        encrypted_pwd = _encrypt_password(secret, rsa_e, rsa_n)

        resp = self.session.post(f"{self.url}/eportal/InterFace.do?method=login",
                                 data={"userId": user,
                                       "password": encrypted_pwd,
                                       "service": "",
                                       "queryString": query_str,
                                       "operatorPwd": "",
                                       "operatorUserId": "",
                                       "validcode": "",
                                       "passwordEncrypt": "true", })

        return resp.json()


if __name__ == "__main__":
    auth = Authenticator()
    if len(sys.argv) == 2 and sys.argv[1] == "logout":
        print(auth.logout())
    elif len(sys.argv) != 3:
        print("Usage: python main.py <username> <password>")
        print("If you want to logout, use: python main.py logout")
        sys.exit(1)
    elif auth.is_online():
        print("You are already online!")
        sys.exit(0)
    else:
        print(auth.login(sys.argv[1], sys.argv[2]))
