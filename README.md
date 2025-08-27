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
apt install python3 python3-pip
pip3 install requests gmpy2
```

- 运行脚本

手动修改`main.py`中的校园IP.

```shell
# login
python main.py login -u $USER -p $PASSWORD -e -c
# logout
python main.py logout
```

### Shell

- 编译`encrypt.c`为`encrypt_x86`

```shell
# compile c for x86
gcc encrypt.c -o encrypt -lgmp
```

- 交叉编译`encrypt.c`为`encrypt_mipsle`

```shell
sudo apt install m4
cd /home/username/
wget xxx-sdk-xxx-ramips-mt7621_gcc-x.x.x_musl.Linux-x86_64.tar.gz
tar -xvf xxx-sdk-xxx-ramips-mt7621_gcc-x.x.x_musl.Linux-x86_64.tar.gz
sudo passwd root
su
export STAGING_DIR=/home/username/xxx-sdk-xxx-ramips-mt7621_gcc-x.x.x_musl/staging_dir/toolchain-mipsel-_24kc_gcc-x.x.x_musl
export PATH=$PATH:$STAGING_DIR/bin

wget https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz
cd /home/username/gmp-6.3.0/
./configure --host=mipsel-openwrt-linux --prefix=/usr/local/mipsel-gmp --enable-static --disable-shared
make clean && make -j$(nproc) && make install
```

- 运行脚本

手动修改`web_hust.sh`中的校园IP和加密文件路径.

```shell
# login
bash ./web_hust.sh $username $password
# logout
bash ./web_hust.sh logout 
```

## 结果

- Python在x86 (Windows/Linux) 和mipsle (OpenWRT) 上测均试通过.
- Shell在x86 (Windows/Linux) 在上测试通过.
- Shell在mipsle (OpenWRT) 上无法使用`encrypt`, 原因是缺少`ld.so.1`.

## 改进(已解决)

- 解决mipsle (OpenWRT) 无法加密密码的问题.

## 更多

[基于OpenWRT路由器的校园网突破设备限制实践总结](docs/校园网路由器.md)

## 参考引用

- [SWUOSA/ruijie-authentication: 西南大学校园网自动登录脚本, 基于Python](https://github.com/SWUOSA/ruijie-authentication)
- [ehxu/Ruijie_JMU: 锐捷 ePortal Web 认证自动登录脚本 (Linux & Windows) ](https://github.com/ehxu/Ruijie_JMU)
- [callmeliwen/RuijiePortalLoginTool: 集美大学锐捷 ePortal Web 认证自动登录脚本](https://github.com/callmeliwen/RuijiePortalLoginTool)

