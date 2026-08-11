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

- 手动修改`src/rjeportal.sh`中的校园IP和加密文件路径 (自动检测 curl/wget).

```shell
# src/rjeportal.sh
IP="172.16.0.46" # Change to your school's IP
ENCRYPTION="$SCRIPT_DIR/../dist/encrypt_mipsel" # 通常无需手动改, 脚本会自动识别架构
# 也可用环境变量覆盖, 例如 ENCRYPTION=/path/to/encrypt sh rjeportal.sh login ...
```

> **自动识别**: `rjeportal.sh` 会根据系统架构自动选择 `dist/` 下对应二进制
> (读取 `/etc/openwrt_release` 的 `DISTRIB_ARCH`, 回退 `uname -m`):
> `mipsel_*`→encrypt_mipsel, `aarch64`→encrypt_aarch64, `x86_64`→encrypt_x86.
> 仅当识别失败或需指定自定义路径时才需手动设置 `ENCRYPTION`.

- **路由器(OpenWrt)上务必安装 curl**: eportal 的 POST 接口对 OpenWrt 自带 uclient-fetch 解析不可靠, 需 `opkg install curl` (实测 uclient-fetch 下 pageInfo 返回空、login 报"用户名不能为空").
- 运行脚本

```shell
cd RujieEportal/src
chmod +x rjeportal.sh
# 登录
sh ./rjeportal.sh login $USER $PASSWORD
# 登出
sh ./rjeportal.sh logout
# 状态
sh ./rjeportal.sh status
```

### 编译 encrypt 二进制 (libtommath 版, 无需 GMP)

`src/encrypt.c` 基于 **libtommath** (vendored: `src/tommath.c` + 头文件), 不需要 GMP 交叉编译.
交叉编译只需一个 musl 工具链, 单命令:

```shell
# 以 mipsel 为例 (工具链从 https://musl.cc 下载)
curl -sL -o tc.tgz https://musl.cc/mipsel-linux-musl-cross.tgz && tar -xzf tc.tgz
./mipsel-linux-musl-cross/bin/mipsel-linux-musl-gcc -static -O2 -no-pie -march=24kc -o dist/encrypt_mipsel_24kc src/encrypt.c src/tommath.c

# x86_64 / aarch64 同理, 换对应工具链
# 本地一键构建全部架构: bash build_all.sh
```

**GitHub Actions 自动化**: [`.github/workflows/build-encrypt.yml`](.github/workflows/build-encrypt.yml) 已配置
在 `src/encrypt.c` / `src/tommath*` 变更或 tag 时自动交叉编译 10 个架构文件,
跑 qemu 冒烟测试(校验输出与基准向量逐字节一致)并上传 artifact / 附加到 Release.

#### dist/ 架构命名 (与 OpenWrt 包架构名一致)

| 二进制 | 对应 OpenWrt 架构 | 说明 |
| --- | --- | --- |
| `encrypt_x86_64` | x86_64 | 软路由/PC |
| `encrypt_aarch64_cortex-a53/a72/a76/generic` | 对应 aarch64 内核 | 同一二进制(ISA 固定), 按 ipk 命名拷贝 |
| `encrypt_arm_cortex-a7_neon-vfpv4` | arm_cortex-a7_neon-vfpv4 | 需 VFPv4+NEON |
| `encrypt_arm_cortex-a15_neon-vfpv4` | arm_cortex-a15_neon-vfpv4 | 需 VFPv4+NEON |
| `encrypt_arm_cortex-a9_vfpv3-d16` | arm_cortex-a9_vfpv3-d16 | 仅 VFPv3 |
| `encrypt_mipsel_24kc` | mipsel_24kc | MIPS 小端 |
| `encrypt_mips_24kc` | mips_24kc | MIPS 大端 |

> 注意: ARMv7 三种 FPU 变体**不通用** (neon-vfpv4 二进制无法在仅 vfpv3-d16 的 a9 上运行), 须精确匹配.
> `rjeportal.sh` 已按 `/etc/openwrt_release` 的 `DISTRIB_ARCH` 自动识别并选择对应文件.

## 结果

- Python脚本在x86(Windows/Linux)和mipsle(OpenWRT)上测均试通过.
- Shell脚本在x86(Windows/Linux)和mipsle(OpenWRT)上测均试通过.

## 更多

[基于OpenWRT路由器的校园网突破设备限制实践总结](docs/无限制校园网路由器.md)

## 参考引用

- [SWUOSA/ruijie-authentication: 西南大学校园网自动登录脚本, 基于Python](https://github.com/SWUOSA/ruijie-authentication)
- [ehxu/Ruijie_JMU: 锐捷 ePortal Web 认证自动登录脚本 (Linux & Windows)](https://github.com/ehxu/Ruijie_JMU)
- [callmeliwen/RuijiePortalLoginTool: 集美大学锐捷 ePortal Web 认证自动登录脚本](https://github.com/callmeliwen/RuijiePortalLoginTool)
