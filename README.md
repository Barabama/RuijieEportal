# 锐捷校园网网页认证脚本

FZU Ruijie ePortal Web Authentication Tool

提供了基于Python和Shell的脚本, 锐捷认证现在要求Post请求加密后的密码, RSA加密依赖`gmp`实现.
Python空间需求大于40MB.

## 特别声明

- 本程序仅为自动化登录脚本, 不涉及任何破解盗版信息.
- 仅供学习交流, 严禁用于商业用途, 请于24小时内删除.
- 禁止将本站资源进行任何形式的出售, 产生的一切后果由侵权者自负!

## 使用说明

### Python

- 安装Python3, 并安装依赖库`requests`, `gmpy2`

```shell
# Ubuntu
sudo apt update && sudo apt install python3 python3-pip
pip3 install requests gmpy2

# Openwrt
opkg update && opkg install python3 python3-pip python3-requests python3-gmpy2
```

- 复制源码并解压

```shell
wget https://gh-proxy.com/https://github.com/Barabama/RuijieEportal/archive/refs/heads/main.zip
unzip main.zip
mv RuijieEportal-main RuijieEportal
rm main.zip
chmod -R 777 RuijieEportal
```

- 手动修改`src/main.py`中的校园IP.

```python
class Authenticator:
    def __init__(self):
        self.ip = "172.16.0.46"  # Change to your school's IP
```

- 运行脚本

```shell
cd RujieEportal/src
# login
python main.py login -u $USER -p $PASSWORD -e -c
# logout
python main.py logout
```

### Shell

- 复制源码并解压

```shell
wget https://gh-proxy.com/https://github.com/Barabama/RuijieEportal/archive/refs/heads/main.zip
unzip main.zip
mv RuijieEportal-main RuijieEportal
rm main.zip
chmod -R 777 RuijieEportal
```

- 手动修改`src/web_hust.sh`中的校园IP和加密文件路径.

```shell
# src/web_hust.sh
IP="172.16.0.46" # Change to your school's IP
ENCRYPTION="../dist/encrypt_mipsel" # Change to your encryption path
```

- 运行脚本

```shell
cd RujieEportal/src
# login
bash ./web_hust.sh $USER $PASSWORD
# logout
bash ./web_hust.sh logout 
```

如果[dist/](./dist/)中没有目标平台编译文件, 请自行编译, [#更多详情](docs/无限制校园网路由器.md)

## 结果

- Python脚本在x86(Windows/Linux)和mipsle(OpenWRT)上测均试通过.
- Shell脚本在x86(Windows/Linux)和mipsle(OpenWRT)上测均试通过.

## 更多

[基于OpenWRT路由器的校园网突破设备限制实践总结](docs/无限制校园网路由器.md)

## 参考引用

- [SWUOSA/ruijie-authentication: 西南大学校园网自动登录脚本, 基于Python](https://github.com/SWUOSA/ruijie-authentication)
- [ehxu/Ruijie_JMU: 锐捷 ePortal Web 认证自动登录脚本 (Linux & Windows) ](https://github.com/ehxu/Ruijie_JMU)
- [callmeliwen/RuijiePortalLoginTool: 集美大学锐捷 ePortal Web 认证自动登录脚本](https://github.com/callmeliwen/RuijiePortalLoginTool)
