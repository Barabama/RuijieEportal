#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# rjeportal.py - Ruijie ePortal 校园网认证统一 CLI
#
# 用法:
#   python rjeportal.py status                    # 检查网络状态
#   python rjeportal.py login -u 学号 -p 密码     # 登录 (默认 RSA 加密)
#   python rjeportal.py login                     # 用已保存的配置登录
#   python rjeportal.py login --save              # 登录并保存配置
#   python rjeportal.py logout                    # 登出
#
# 可选参数:
#   --interface IP   绑定源 IP (多网卡/路由器特殊场景才需要)
#   --portal IP      认证门户地址 (默认 172.16.0.46)
#   --no-encrypt     明文密码提交 (部分学校不需要 RSA)
#
# 依赖: requests (RSA 用 Python 内置 pow(), 无需 gmpy2)

import argparse
import json
import logging
import os
import re
import sys
from urllib.parse import urlparse, parse_qs

import requests
from requests.adapters import HTTPAdapter

DEFAULT_PORTAL = "172.16.0.46"
# HTTP 204 连通性探测地址: 在线时返回 204, 未认证时被 NAS 拦截跳转
ONLINE_URL = "http://connect.rom.miui.com/generate_204"
CONFIG_PATH = os.path.join(os.path.expanduser("~"), ".rjeportal.json")

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("rjeportal")


class SourceAdapter(HTTPAdapter):
    """把 socket 绑定到指定源 IP, 用于多网卡场景."""

    def __init__(self, source_ip, *args, **kwargs):
        self.source_ip = source_ip
        super().__init__(*args, **kwargs)

    def init_poolmanager(self, *args, **kwargs):
        kwargs["source_address"] = (self.source_ip, 0)
        super().init_poolmanager(*args, **kwargs)

    def proxy_manager_for(self, *args, **kwargs):
        kwargs["source_address"] = (self.source_ip, 0)
        return super().proxy_manager_for(*args, **kwargs)


def make_session(interface=None) -> requests.Session:
    s = requests.Session()
    if interface:
        s.mount("http://", SourceAdapter(interface))
        s.mount("https://", SourceAdapter(interface))
    s.headers.update(
        {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36 Edg/112.0.0.0",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,"
            "image/apng,*/*;q=0.8",
        }
    )
    return s


def encrypt_password(secret: str, rsa_e: str, rsa_n: str) -> str:
    """RSA 加密密码 (教科书式, 无填充). Python 内置 pow 即可, 无需 gmpy2."""
    secret_int = int.from_bytes(secret.encode(), "big")
    encrypted = pow(secret_int, int(rsa_e, 16), int(rsa_n, 16))
    hexstr = format(int(encrypted), "x")
    mod_bytes = (len(rsa_n) + 1) // 2
    return hexstr.rjust(mod_bytes * 2, "0")


def extract_query_string(text: str) -> str:
    """从拦截页中提取 eportal index.jsp 的 queryString."""
    for pattern in (r"location\.href='([^']+)'", r"href='([^']+)'"):
        m = re.search(pattern, text)
        if m and "index.jsp" in m.group(1):
            return urlparse(m.group(1)).query
    return ""


def check_status(s: requests.Session, portal: str):
    """探测网络状态. 返回 (online, query_string)."""
    try:
        resp = s.get(ONLINE_URL, allow_redirects=False, timeout=8, verify=False)
    except requests.RequestException:
        return False, ""
    if resp.status_code == 204:
        return True, ""
    # 被拦截: 尝试提取 queryString
    qs = extract_query_string(resp.text)
    if not qs:
        # 有些 NAS 用 302 跳转而非内嵌脚本
        loc = resp.headers.get("Location", "")
        if "index.jsp" in loc:
            qs = urlparse(loc).query
    return False, qs


def do_status(args) -> int:
    s = make_session(args.interface)
    online, qs = check_status(s, args.portal)
    if online:
        print("online")
        return 0
    print("offline" if not qs else f"offline (need login, got queryString: {qs[:60]}...)")
    return 1


def do_login(args) -> int:
    # 已在线则直接跳过 (但 --save 仍保存配置)
    s = make_session(args.interface)
    online, qs = check_status(s, args.portal)
    if online:
        if args.save:
            save_config(args.username, args.password, args.encrypt, args.portal)
            log.info("Already online. Config saved to %s", CONFIG_PATH)
        else:
            log.info("Already online, nothing to do.")
        return 0
    if not qs:
        log.error("Failed to trigger interception (no queryString). "
                  "Ensure you are on a network managed by this portal.")
        return 1

    eportal = f"http://{args.portal}/eportal"

    # 拉取 RSA 公钥
    page_info = s.post(
        f"{eportal}/InterFace.do?method=pageInfo",
        data={"queryString": qs},
        timeout=10, verify=False,
    ).json()
    rsa_e = page_info["publicKeyExponent"]
    rsa_n = page_info["publicKeyModulus"]

    # 组装并加密密码: secret = password>MAC
    mac = parse_qs(qs).get("mac", [""])[0]
    secret = f"{args.password}>{mac}"
    password = (
        encrypt_password(secret, rsa_e, rsa_n)
        if args.encrypt else args.password
    )

    data = {
        "userId": args.username,
        "password": password,
        "service": "",
        "queryString": qs,
        "operatorPwd": "",
        "operatorUserId": "",
        "validcode": "",
        "passwordEncrypt": "true" if args.encrypt else "false",
    }
    resp = s.post(
        f"{eportal}/InterFace.do?method=login",
        data=data,
        headers={
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Referer": f"{eportal}/index.jsp?{qs}",
        },
        timeout=15, verify=False,
    )
    res = resp.json()
    log.info(f"LoginResult: {json.dumps(res, ensure_ascii=False)}")

    if res.get("result") == "success":
        if args.save:
            save_config(args.username, args.password, args.encrypt, args.portal)
            log.info("Config saved to %s", CONFIG_PATH)
        return 0
    log.error("Login failed: %s", res.get("message", res))
    return 1


def do_logout(args) -> int:
    s = make_session(args.interface)
    eportal = f"http://{args.portal}/eportal"

    resp = s.get(f"{eportal}/redirectortosuccess.jsp", timeout=10, verify=False)
    m = re.search(r"userIndex=([^&]+)", resp.url)
    if not m:
        log.info("Already logged out (no userIndex found).")
        return 0

    res = s.post(
        f"{eportal}/InterFace.do?method=logout",
        data={"userIndex": m.group(1)},
        timeout=10, verify=False,
    ).json()
    log.info(f"LogoutResult: {json.dumps(res, ensure_ascii=False)}")
    return 0 if res.get("result") == "success" else 1


def save_config(username, password, encrypt, portal):
    cfg = {
        "username": username,
        "password": password,
        "encrypt": encrypt,
        "portal": portal,
    }
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=4)


def load_config():
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return None


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Ruijie ePortal campus network authentication CLI",
        epilog="示例:\n"
               "  python rjeportal.py login -u 学号 -p 密码\n"
               "  python rjeportal.py login            # 用保存的配置\n"
               "  python rjeportal.py logout\n"
               "  python rjeportal.py status\n"
               "  python rjeportal.py login -u U -p P --interface 192.168.5.117",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("action", choices=["login", "logout", "status"],
                        help="login / logout / status")

    g = parser.add_argument_group("通用选项")
    g.add_argument("--interface", help="绑定源 IP (多网卡场景才需要, 如 --interface 192.168.5.117)")
    g.add_argument("--portal", default=DEFAULT_PORTAL, help=f"认证门户 IP (默认 {DEFAULT_PORTAL})")

    lg = parser.add_argument_group("登录选项")
    lg.add_argument("-u", "--username", help="用户名")
    lg.add_argument("-p", "--password", help="密码")
    lg.add_argument("-e", "--encrypt", action="store_true",
                    default=True, help="RSA 加密密码 (默认开启)")
    lg.add_argument("--no-encrypt", dest="encrypt", action="store_false",
                    help="明文密码提交")
    lg.add_argument("-s", "--save", action="store_true", help="登录成功后保存配置")

    parser.set_defaults(encrypt=True)
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)

    if args.action == "status":
        return do_status(args)

    if args.action == "logout":
        return do_logout(args)

    # login: 未提供用户名/密码时尝试加载配置
    if not args.username or not args.password:
        cfg = load_config()
        if not cfg:
            log.warning("未提供用户名/密码且无已保存配置. 用法见 --help.")
            return 2
        args.username = cfg["username"]
        args.password = cfg["password"]
        args.encrypt = cfg.get("encrypt", True)
        args.portal = cfg.get("portal", args.portal)
        log.info("Loaded config from %s", CONFIG_PATH)

    return do_login(args)


if __name__ == "__main__":
    sys.exit(main())
