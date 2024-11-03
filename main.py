#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# main.py

import re
import sys
from urllib.parse import urlparse, parse_qs
import requests
import gmpy2


def _encrypt_password(secret: str, rsa_e: str, rsa_n: str) -> str:
    secret_int = int.from_bytes(secret.encode(), "big")
    encrypted_int = gmpy2.powmod(secret_int, int(rsa_e, 16), int(rsa_n, 16))
    return hex(encrypted_int)[2:]


class Authenticator:

    def __init__(self):
        self.ip = "59.77.227.227"  # Change to your school's IP
        self.url = f"http://{self.ip}"
        self.eportal_url = f"{self.url}/eportal"
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
        resp = self.session.get(f"{self.eportal_url}/redirectortosuccess.jsp")
        # print(f"redirectURL: {resp.url}")
        user_index = re.search(r"userIndex=([^&]+)", resp.url).group(1)
        # print(f"userIndex: {user_index}")
        resp = self.session.post(f"{self.eportal_url}/InterFace.do?method=logout",
                                 data={"userIndex": user_index})
        return resp.json()

    def login(self, user: str, passwd: str) -> dict:
        redirect_text = self.session.get(self.url).text
        # print(f"redirectText: {redirect_text}")
        redirect_url = re.search(r"href='([^']+)", redirect_text).group(1)
        # print(f"redirectURL: {redirect_url}")
        self.session.headers["Referer"] = redirect_url
        query_str = urlparse(redirect_url).query
        # print(f"querySring: {query_str}")
        # Get RSA public key
        page_info = self.session.post(f"{self.eportal_url}/InterFace.do?method=pageInfo",
                                      data={"queryString": query_str}).json()
        self.session.cookies.get_dict()
        rsa_e = page_info["publicKeyExponent"]
        rsa_n = page_info["publicKeyModulus"]
        # print(f"rsaE: {rsa_e}, rsaN: {rsa_n}")
        # Encrypt password
        secret = f"{passwd}>{parse_qs(query_str)['mac'][0]}"
        # print(f"secret: {secret}")
        password = _encrypt_password(secret, rsa_e, rsa_n)
        # password = passwd # Password Unencrypted
        # print(f"password: {password}")
        resp = self.session.post(f"{self.eportal_url}/InterFace.do?method=login",
                                 data={"userId": user,
                                       "password": password,
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

    auth.session.close()
