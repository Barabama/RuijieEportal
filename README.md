# 锐捷校园网网页认证脚本

FZU Ruijie ePortal Web Authentication Tool

提供了基于Python和Shell的脚本, 锐捷认证现在要求Post请求加密后的密码, RSA加密依赖`gmp`实现.
Python空间需求大于40MB.

## 特别声明

- 本程序仅为自动化登录脚本, 不涉及任何破解盗版信息.
- 仅供学习交流, 严禁用于商业用途, 请于24小时内删除.
- 禁止将本站资源进行任何形式的出售, 产生的一切后果由侵权者自负!

## 使用说明

### Python (推荐: 统一 CLI `rjeportal.py`)

统一 CLI 提供 `login / logout / status` 三个子命令, 默认不区分网卡, 仅在多网卡场景用 `--interface` 绑定源 IP.

```shell
cd RuijieEportal/src
pip install requests            # 只需 requests, RSA 用内置 pow() 无需 gmpy2

# 检查状态
python rjeportal.py status

# 登录 (默认 RSA 加密, 自动探测拦截并完成认证)
python rjeportal.py login -u $USER -p $PASSWORD

# 登录并保存配置 (之后可直接 python rjeportal.py login)
python rjeportal.py login -u $USER -p $PASSWORD -s

# 用已保存的配置登录
python rjeportal.py login

# 登出
python rjeportal.py logout

# 多网卡场景绑定源 IP (例如本机有线/无线路由同时在线时)
python rjeportal.py login -u $USER -p $PASSWORD --interface 192.168.5.117
```

### Python (经典脚本, 已归档)

旧版 `main.py` (面向端口直连门户获取 queryString 的实现) 已移入 [archived/](./archived/), 仅作参考.
新版统一 CLI `rjeportal.py` 功能更全: 自动探测外网拦截、修复在线检测、`--interface` 多网卡绑定、gmpy2 可选(内置 pow 回退).

### 根目录 main.py 薄包装

仓库根目录的 `main.py` 只是 `src/rjeportal.py` 的入口转发, 方便直接调用:

```shell
python main.py status
python main.py login -u $USER -p $PASSWORD
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
