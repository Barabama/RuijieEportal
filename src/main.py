#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# main.py

import argparse
import json
import logging
import os
import re
from urllib.parse import urlparse, parse_qs

import requests
import gmpy2

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")


def _encrypt_password(secret: str, rsa_e: str, rsa_n: str) -> str:
    secret_int = int.from_bytes(secret.encode(), "big")
    encrypted_int = gmpy2.powmod(secret_int, int(rsa_e, 16), int(rsa_n, 16))
    return hex(encrypted_int)[2:]


class Authenticator:

    def __init__(self):
        self.ip = "172.16.0.46"  # Change to your school's IP
        self.url = f"http://{self.ip}"
        self.eportal_url = f"{self.url}/eportal"
        self.cfg = os.path.join(os.getcwd(), "config.json")
        self.session = requests.Session()
        self.session.headers = {
            "Host": self.ip,
            "Origin": self.url,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36 Edg/112.0.0.0",
        }

    def __del__(self):
        self.session.close()

    def is_online(self) -> bool:
        resp = self.session.get(self.url)
        return "success" in resp.url

    def logout(self) -> dict:
        resp = self.session.get(f"{self.eportal_url}/redirectortosuccess.jsp")
        logging.info(f"redirectURL: {resp.url}")

        if match := re.search(r"userIndex=([^&]+)", resp.url):
            user_idx = match.group(1)
            logging.info(f"userIndex: {user_idx}")
        else:
            raise RuntimeError(f"Dismatch userIndex in {resp.url}")

        resp = self.session.post(f"{self.eportal_url}/InterFace.do?method=logout",
                                 data={"userIndex": user_idx})
        return resp.json()

    def login(self, username: str, password: str, encrypt: bool) -> dict:
        redirect_text = self.session.get(self.url).text
        logging.info(f"redirectText: {redirect_text}")

        if match := re.search(r"href='([^']+)", redirect_text):
            redirect_url = match.group(1)
            logging.info(f"redirectURL: {redirect_url}")
        else:
            raise RuntimeError(f"Dismatch redirectURL in {redirect_text}")

        self.session.headers["Referer"] = redirect_url
        query_str = urlparse(redirect_url).query
        logging.info(f"querySring: {query_str}")

        # Get RSA public key
        page_info = self.session.post(f"{self.eportal_url}/InterFace.do?method=pageInfo",
                                      data={"queryString": query_str}).json()
        self.session.cookies.get_dict()
        rsa_e = page_info["publicKeyExponent"]
        rsa_n = page_info["publicKeyModulus"]
        logging.debug(f"rsaE: {rsa_e}, rsaN: {rsa_n}")

        # Encrypt password
        secret = f"{password}>{parse_qs(query_str)['mac'][0]}"
        logging.debug(f"secret: {secret}")
        password = _encrypt_password(secret, rsa_e, rsa_n) if encrypt else password
        logging.debug(f"password: {password}")

        resp = self.session.post(
            f"{self.eportal_url}/InterFace.do?method=login",
            data={"userId": username, "password": password, "service": "",
                  "queryString": query_str, "operatorPwd": "", "operatorUserId": "",
                  "validcode": "", "passwordEncrypt": "true" if encrypt else "false"}
        )
        res = resp.json()
        res["password"] = password
        return res

    def save_config(self, username: str, password: str, encrypt: bool):
        config = {"username": username, "password": password, "encrypt": encrypt}
        with open(self.cfg, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=4)

    def load_config(self):
        if not os.path.exists(self.cfg):
            return
        with open(self.cfg, "r", encoding="utf-8") as f:
            return json.load(f)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Eportal Web Authenticator")
    parser.add_argument("action", choices=["login", "logout"], help="login or logout")
    parser.add_argument("-u", "--username", help="user name for login")
    parser.add_argument("-p", "--password", help="password for login")
    parser.add_argument("-e", "--encrypt", action="store_true", help="encrypt password")
    parser.add_argument("-c", "--cachecfg", action="store_true", help="save configuration to file")
    args = parser.parse_args()
    auth = Authenticator()

    if args.action == "logout":
        logging.info(f"LogoutResult: {auth.logout()}")

    elif auth.is_online():
        logging.info("You are already online!")

    elif args.action == "login":
        if not args.username or not args.password:
            if config := auth.load_config():
                logging.info("Loaded configuration from config.json")
                logging.info(f"LoginResult: {auth.login(**config)}")
            else:
                logging.warning("No configuration found.")
                logging.info("Usage: python main.py login -u <username> -p <password> -c")

        else:
            res = auth.login(args.username, args.password, args.encrypt)
            logging.info(f"LoginResult: {res}")
            if res["result"] == "success" and args.cachecfg:
                logging.info("Saved configuration to config.json")
                config = {"username": args.username, "password": res["password"],
                          "encrypt": args.encrypt}
                auth.save_config(**config)

    else:
        logging.error("Invalid action. Use 'login' or 'logout'.")
