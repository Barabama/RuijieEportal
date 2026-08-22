# 锐捷校园网网页认证工具

这是一个用于锐捷 ePortal 网页认证的命令行工具。它会访问一个外部网址触发校园网认证页面，获取认证参数，使用 RSA 加密密码，然后提交登录请求。

## 获取项目

使用 Git：

```shell
git clone https://github.com/Barabama/RuijieEportal.git
cd RuijieEportal
```

也可以在 GitHub 页面选择 **Code → Download ZIP**，解压后进入项目目录。后面的命令都假设当前目录是项目根目录。

## 先选一种用法

| 使用场景 | 推荐入口 | 说明 |
| --- | --- | --- |
| Windows、Linux 普通主机 | `python main.py` | 只需要 Python 和 `requests` |
| OpenWrt/ImmortalWrt 路由器 | `bash main.sh` | 需要 `curl` 和对应架构的加密二进制 |
| 本机同时连接多个网络 | Python CLI + `--interface` | 指定认证流量使用的源 IP |
| 修改认证协议或重新编译二进制 | 开发者章节 | 普通使用者不需要阅读 |

以下命令默认认证门户地址为 `172.16.0.46`。如果你的学校使用其他地址，可以通过参数或环境变量覆盖。

## 使用前准备

1. 设备已经连接到需要网页认证的校园网。
2. 你拥有该校园网的账号和密码。
3. 认证门户确实使用锐捷 ePortal，并且可以访问校园认证页面。

本工具只自动化已有的网页认证流程，请遵守学校网络管理规定。

## Python：普通主机

### 安装依赖

在项目根目录执行：

```shell
# Windows
py -m pip install -r requirements.txt

# Linux
python3 -m pip install -r requirements.txt
```

RSA 加密使用 Python 内置的 `pow()`，不需要安装 `gmpy2`。

### 检查状态

```shell
python main.py status
```

输出 `online` 表示当前网络已经可以直接访问外网。未认证时会输出 `offline` 或认证参数提示。

### 登录

```shell
python main.py login -u YOUR_USERNAME -p YOUR_PASSWORD
```

默认会对密码进行 RSA 加密。如果学校要求提交明文密码，可以使用：

```shell
python main.py login -u YOUR_USERNAME -p YOUR_PASSWORD --no-encrypt
```

注意：`-p` 后面的密码可能会出现在本机进程列表或 Shell 历史中，不要在多人共用的机器上直接暴露密码。

### 保存配置后登录

```shell
python main.py login -u YOUR_USERNAME -p YOUR_PASSWORD --save
python main.py login
```

配置保存在用户目录下的 `.rjeportal.json` 中，当前包含账号和密码，请根据本机权限保护该文件。

### 登出

```shell
python main.py logout
```

### 多网卡指定出口

如果电脑同时连接 Wi-Fi 和有线网络，认证请求可能会走错网卡。使用有线网卡的源 IP 绑定认证流量：

```shell
python main.py login \
  -u YOUR_USERNAME \
  -p YOUR_PASSWORD \
  --interface 192.168.5.117
```

`--interface` 接受本机网卡的 IP，不是网卡名称。

### 使用其他认证门户

```shell
python main.py status --portal 172.16.0.46
python main.py login -u YOUR_USERNAME -p YOUR_PASSWORD --portal 172.16.0.46
```

## OpenWrt：路由器

Shell 版本适合没有完整 Python 环境的 OpenWrt/ImmortalWrt 路由器。请保留项目的目录结构：

```text
RuijieEportal/
├── dist/                 # 预编译的加密二进制
└── main.sh               # Shell CLI
```

### 安装依赖

你的路由器需要 `curl`。OpenWrt 自带的 `uclient-fetch` 对该认证接口的 POST 请求兼容性不足，可能导致 `pageInfo` 返回空内容或登录时报“用户名不能为空”。

```shell
opkg update
opkg install curl
```

### 检查状态并登录

```shell
cd RuijieEportal
chmod +x main.sh

sh main.sh status
sh main.sh login YOUR_USERNAME YOUR_PASSWORD
```

### 登出

```shell
sh main.sh logout
```

脚本会根据 `/etc/openwrt_release` 中的 `DISTRIB_ARCH` 自动选择 `dist/` 下的加密二进制。通常不需要手动设置 `ENCRYPTION`。

如果自动识别失败，可以手动指定：

```shell
ENCRYPTION=/path/to/encrypt_mipsel_24kc \
  sh main.sh login YOUR_USERNAME YOUR_PASSWORD
```

## 常见问题

### 状态是 offline，但没有 queryString

脚本需要先访问外部探测地址触发网关拦截。如果没有得到认证参数，通常是以下原因之一：

- 当前网络不是该 ePortal 管理的网络；
- 认证门户地址配置错误；
- 当前网络已经通过其他方式认证；
- 外部探测地址被本地代理、防火墙或 DNS 拦截。

先确认浏览器访问普通外网网址时是否会跳转到认证页面，再检查 `--portal` 或 `PORTAL_IP` 配置。

### 已经在线，登录没有执行

这是正常行为。工具会先检查网络状态，已经在线时直接返回成功，不会重复提交登录请求。

### 多网卡时认证了错误的网络

Python 使用 `--interface` 指定源 IP：

```shell
python main.py login -u YOUR_USERNAME -p YOUR_PASSWORD --interface YOUR_SOURCE_IP
```

Shell 版本不单独绑定网卡，它使用系统当前路由表选择出口。

### 路由器提示二进制不存在或不可执行

检查路由器架构和对应文件：

```shell
grep DISTRIB_ARCH /etc/openwrt_release
uname -m
ls -l ../dist/
```

如果文件存在但仍不能执行，通常是架构、大小端或 ARM 浮点 ABI 不匹配。可以使用 `ENCRYPTION=/path/to/correct-binary` 临时覆盖自动选择结果。

## 开发者：重新编译加密二进制

普通用户不需要重新编译。项目已经提供 `dist/` 下的预编译文件。

`src/encrypt.c` 使用 vendored 的 libtommath 实现 RSA 模幂运算，不依赖 GMP。可以在本地执行：

```shell
bash build_all.sh
```

GitHub Actions 工作流位于 `.github/workflows/build-encrypt.yml`，负责：

- 使用 GitHub Release 中的 musl 交叉编译工具链；
- 构建主流 OpenWrt 架构；
- 使用 QEMU 执行冒烟测试；
- 将二进制上传为构建产物。

### 支持的二进制架构

| 文件 | OpenWrt 架构 | 备注 |
| --- | --- | --- |
| `encrypt_x86_64` | `x86_64` | 软路由和普通 64 位 PC |
| `encrypt_aarch64_cortex-a53` | `aarch64_cortex-a53` | AArch64 |
| `encrypt_aarch64_cortex-a72` | `aarch64_cortex-a72` | AArch64 |
| `encrypt_aarch64_cortex-a76` | `aarch64_cortex-a76` | AArch64 |
| `encrypt_aarch64_generic` | `aarch64_generic` | AArch64 通用版本 |
| `encrypt_arm_cortex-a7_neon-vfpv4` | `arm_cortex-a7_neon-vfpv4` | ARMv7 + NEON |
| `encrypt_arm_cortex-a15_neon-vfpv4` | `arm_cortex-a15_neon-vfpv4` | ARMv7 + NEON |
| `encrypt_arm_cortex-a9_vfpv3-d16` | `arm_cortex-a9_vfpv3-d16` | ARMv7 + VFPv3 |
| `encrypt_mipsel_24kc` | `mipsel_24kc` | MIPS 小端 |
| `encrypt_mips_24kc` | `mips_24kc` | MIPS 大端 |

ARMv7 的不同浮点 ABI 不能随意混用。AArch64 的几个文件内容相同，只是按 OpenWrt 架构名分别提供。

## 旧版本和实践记录

- 旧版 Python/Shell 脚本：[`archived/`](./archived/)
- OpenWrt 路由器实践记录：[`docs/无限制校园网路由器.md`](./docs/无限制校园网路由器.md)

旧脚本仅供参考，日常使用请优先选择根目录 `main.py` 或 `main.sh`。

## 参考

- [SWUOSA/ruijie-authentication](https://github.com/SWUOSA/ruijie-authentication)
- [ehxu/Ruijie_JMU](https://github.com/ehxu/Ruijie_JMU)
- [callmeliwen/RuijiePortalLoginTool](https://github.com/callmeliwen/RuijiePortalLoginTool)
