下面是一份可直接复制到新 AI 会话中的上下文总结。内容以当前仓库的 `docs/opwrt初始化脚本.md`、`docs/无限制校园网路由器.md` 和已有实践为基础，优先采用**手工部署方案**，适合现在急着制作一台小米 R3G 路由器。

---

# 小米 R3G + ImmortalWrt + UA3F + Nikki + RuijieEportal 手工部署上下文

## 一、目标

在小米 R3G/MT7621 上安装 ImmortalWrt 24.10.6，使路由器：

```text
校园 Wi-Fi STA 上联
        ↓
锐捷 ePortal 认证
        ↓
R3G NAT
        ↓
LAN 内多台设备共享网络
```

主要软件：

```text
XMiR-Patcher       获取小米路由器 SSH 权限
Breed              备份分区、刷写和恢复固件
ImmortalWrt        路由器系统
UA3F               HTTP/S 流量特征重写、可选 SOCKS5/TPROXY
Nikki/Mihomo       透明代理及 UA3F 出站代理链
RuijieEportal      锐捷 ePortal 认证脚本
luci-app-nettask   可选的脚本管理和开机/断网执行工具
```

当前优先级是先使用手工方案完成一台可用路由器，不等待完整 `luci-app-rjeportal` 集成。

---

## 二、重要设备和版本信息

目标设备：

```text
小米 R3G
SoC：MediaTek MT7621
常见架构：mipsel_24kc
```

建议固定版本：

```text
ImmortalWrt：24.10.6
UA3F：v3.6.0 发布版 IPK
Nikki：使用官方安装脚本
RuijieEportal：main 分支
```

R3G 上执行：

```sh
grep DISTRIB_ARCH /etc/openwrt_release
cat /etc/openwrt_release
uname -a
cat /proc/cpuinfo
```

R3G 通常应使用：

```text
mipsel_24kc
```

不要将 `mips_24kc`、ARM 或 AArch64 的二进制放到 R3G 上。

---

# 三、刷机前准备

## 3.1 需要准备的文件

在电脑上准备：

```text
ImmortalWrt 24.10.6 R3G/MT7621 固件
breed-mt7621-xiaomi-r3g.bin
XMiR-Patcher
网线
备份文件保存目录
```

建议初次操作时只连接：

```text
电脑 ↔ 网线 ↔ R3G
R3G ↔ 电源
```

先完成 SSH、备份和刷机，再连接校园 Wi-Fi。

---

## 3.2 使用 Xiaomi Patcher 获取 SSH

可以使用：

```text
XMiR-Patcher
项目：longzheng268/Xiaomi-Router-patcher
```

用途：

- 针对部分小米路由器固件执行破解；
- 开启 SSH；
- 获取 root shell；
- 为后续备份和刷 Breed 做准备。

注意：

1. 不同小米固件版本、硬件版本和地区版本可能需要不同的 Patcher 流程。
2. 不要盲目使用其他型号的 Patcher 参数。
3. 获取 SSH 后，建议先通过网线连接路由器。
4. 常见官方系统管理地址是：

```text
192.168.31.1
```

尝试登录：

```sh
ssh root@192.168.31.1
```

如果地址不同，以电脑实际获得的网关地址为准。

---

# 四、备份原厂系统和关键分区

这是最重要的步骤之一。不要在没有备份的情况下刷 Breed 或固件。

## 4.1 记录设备信息

SSH 进入原厂系统后执行：

```sh
uname -a
cat /proc/cpuinfo
cat /proc/mtd
ip addr
ip route
```

将输出保存到电脑，尤其是：

```sh
cat /proc/mtd
```

后续所有分区操作都应以当前设备显示结果为准，不能直接照抄其他教程中的 `mtd0`、`mtd1` 或 `Bootloader`。

---

## 4.2 备份全部 MTD 分区

在路由器上执行：

```sh
mkdir -p /tmp/r3g-backup
cat /proc/mtd > /tmp/r3g-backup/proc-mtd.txt

for dev in /dev/mtdblock*; do
    [ -e "$dev" ] || continue
    name=$(basename "$dev")
    dd if="$dev" of="/tmp/r3g-backup/$name.bin" bs=64K
done

sha256sum /tmp/r3g-backup/* > /tmp/r3g-backup/SHA256SUMS
ls -lh /tmp/r3g-backup
```

重点保存：

```text
Bootloader/u-boot 分区
Breed 之前的 bootloader 分区
factory 分区
EEPROM/ART/calibration 等校准分区
firmware 分区
/proc/mtd
SHA256SUMS
```

如果系统没有 `/dev/mtdblock*`，先检查：

```sh
ls -l /dev/mtd*
command -v nanddump
```

也可以使用系统提供的 `nanddump` 或其他 MTD 读取工具，但目标必须是保存原始分区数据。

---

## 4.3 将备份复制到电脑

不要只把备份留在 `/tmp`，因为重启后可能丢失。

路由器上的 Dropbear 没有 /usr/libexec/sftp-server，Windows 新版 scp 默认使用 SFTP 模式，所以需要加大写 -O，强制使用传统 SCP 协议

在电脑上执行：

```sh
scp -r -O root@192.168.31.1:/tmp/r3g-backup .
```

然后在电脑上再次计算校验：

```sh
sha256sum r3g-backup/*
```

备份文件可能包含：

```text
MAC 地址
无线校准数据
设备唯一信息
```

不要将备份上传到公开仓库。

---

# 五、下载和刷入 Breed

## 5.1 获取 Breed

R3G 常用文件：

```text
breed-mt7621-xiaomi-r3g.bin
```

来源：

```text
Breed 官方站点或可信镜像
```

下载到电脑后先计算校验：

```sh
sha256sum breed-mt7621-xiaomi-r3g.bin
```

再上传到路由器：

```sh
scp -O breed-mt7621-xiaomi-r3g.bin root@192.168.31.1:/tmp/
```

---

## 5.2 确认 bootloader 分区

在路由器上再次执行：

```sh
cat /proc/mtd
grep -iE 'u-boot|bootloader|breed' /proc/mtd
```

只有确认当前设备确实存在对应分区后，才能执行刷写。

常见示例：

```sh
mtd -r write /tmp/breed-mt7621-xiaomi-r3g.bin Bootloader
```

但是：

> `Bootloader` 只是常见分区名称，必须以当前设备 `/proc/mtd` 的实际标签为准。

刷写时：

- 不要断电；
- 不要拔网线；
- 不要关闭 SSH；
- 不要重复执行刷写命令；
- 不要把 Breed 写入 `factory`、`firmware` 或其他错误分区。

设备重启后，按照 R3G 对应方法进入 Breed：

```text
断电
按住复位键
上电
保持一段时间
通过网线访问 Breed 页面
```

具体进入时间和地址以 Breed 页面、设备指示灯及实际硬件为准。

---

## 5.3 在 Breed 中再次备份

进入 Breed 后，第一件事仍然是备份：

```text
Bootloader
Factory
EEPROM/校准数据
完整闪存
Breed 环境
```

将 Breed 页面显示的分区名称、大小与之前保存的 `/proc/mtd` 对照。

---

# 六、通过 Breed 刷入 ImmortalWrt

## 6.1 刷写前检查

确认：

```text
已经保存 SSH 阶段备份
已经保存 Breed 阶段备份
固件确实适用于 Xiaomi R3G/MT7621
版本为 ImmortalWrt 24.10.6
不会覆盖 Breed
不会将固件写入 bootloader
```

如果固件是自行编译的，应确认目标：

```text
Target：ramips
Subtarget：mt7621
Profile：Xiaomi Mi Router 3G 或正确的 MT7621 设备
```

---

## 6.2 Breed 刷固件

在 Breed Web 页面上传与 R3G 匹配的 ImmortalWrt 固件。

刷写前检查：

```text
文件名
文件大小
SHA256
设备 Profile
分区布局
是否保留 Breed
```

刷写后：

- 等待设备自动重启；
- 不要断电；
- 不要强制刷新页面；
- 不要在未确认完成前重复刷写。

首次进入 ImmortalWrt 通常使用：

```text
192.168.1.1
```

SSH：

```sh
ssh root@192.168.1.1
```

首次登录后立即设置 root 密码：

```sh
passwd
```

检查系统：

```sh
cat /etc/openwrt_release
uname -a
ip addr
ip route
```

---

# 七、基础联网配置

先通过 LuCI 页面或命令行将 R3G 的无线配置为 STA，连接校园 Wi-Fi。

需要配置：

```text
校园 Wi-Fi SSID
校园 Wi-Fi 密码
无线接口模式：STA/Client
LAN 地址
DHCP
默认路由
DNS
```

确认上联已经获取地址：

```sh
ip addr
ip route
iwinfo
```

确认有默认路由：

```sh
ip route
```

确认路由器本身可以联网：

```sh
ping -c 3 223.5.5.5
nslookup example.com
```

如果使用透明代理，建议将路由器自身流量排除在 Nikki 代理之外：

```text
router_proxy=0
lan_proxy=1
```

原因是路由器自身的 UA3F/Mihomo 出站流量被再次捕获时，可能出现：

```text
reject loopback connection
代理回环
连接超时
```

---

# 八、安装基础软件包

进入路由器 SSH 后：

```sh
opkg update
```

安装常用工具：

```sh
opkg install \
    curl \
    unzip \
    luci-app-ttyd \
    luci-i18n-ttyd-zh-cn \
    luci-app-argon-config \
    luci-i18n-argon-config-zh-cn
```

如果仓库中的中文语言包不存在，应以当前 ImmortalWrt 版本实际包名为准。

确认 curl：

```sh
command -v curl
curl --version
```

RuijieEportal 认证脚本应优先使用 `curl`，不要只使用 OpenWrt 自带的 `uclient-fetch`。

---

# 九、安装 UA3F

## 9.1 安装依赖

```sh
opkg update

opkg install \
    luci-compat \
    ipset \
    iptables-nft \
    iptables-mod-tproxy \
    iptables-mod-extra \
    iptables-mod-ipopt \
    iptables-mod-nfqueue \
    iptables-mod-conntrack-extra \
    kmod-nf-conntrack-netlink \
    kmod-nft-queue \
    kmod-nft-tproxy \
    kmod-tun \
    kmod-sched-bpf
```

不同固件版本的包名可能不同。安装失败时，不要强行混用其他版本的内核模块，应先检查：

```sh
opkg list | grep -E 'tproxy|nfqueue|conntrack|sched-bpf'
```

---

## 9.2 安装 UA3F v3.6.0

确认架构：

```sh
grep DISTRIB_ARCH /etc/openwrt_release
```

R3G 通常使用：

```text
mipsel_24kc
```

下载并安装：

```sh
wget https://gh-proxy.com/github.com/SunBK201/UA3F/releases/download/v3.6.0/ua3f_3.6.0-r1_mipsel_24kc.ipk \
    -O /tmp/ua3f.ipk

opkg install /tmp/ua3f.ipk
```

检查安装：

```sh
command -v ua3f
ua3f --help
```

启动：

```sh
service ua3f start
```

如果存在 UCI 配置：

```sh
uci set ua3f.enabled.enabled=1
uci commit ua3f
service ua3f enable
service ua3f restart
```

---

## 9.3 UA3F 手工 SOCKS5 配置

当前方案可以先使用 UA3F 的 SOCKS5 模式，不配置：

```text
Desync
TTL 固定
IPID
复杂 L3 rewrite
```

例如：

```sh
ua3f \
    --server-mode SOCKS5 \
    --bind-address 127.0.0.1 \
    --port 1080
```

实际参数以当前安装版本的帮助信息为准：

```sh
ua3f --help
```

如果使用 LuCI 页面，也可以在：

```text
服务 → UA3F
```

中配置 SOCKS5。

建议先验证 UA3F 能正常监听：

```sh
netstat -lnpt 2>/dev/null | grep 1080
```

或：

```sh
ss -lnpt 2>/dev/null | grep 1080
```

---

# 十、安装 Nikki/Mihomo

安装官方 Nikki：

```sh
wget -O - \
  https://gh-proxy.com/github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/install.sh \
  | ash
```

安装完成后重新登录 LuCI，或重新加载环境。

检查：

```sh
command -v nikki
/etc/init.d/nikki status
```

---

## 10.1 Nikki 配置思路

Nikki 用于运行 Mihomo/Clash 透明代理，并将流量转给本机 UA3F SOCKS5。

配置文件示例：

```yaml
mixed-port: 7890
redir-port: 7891
tproxy-port: 7892

ipv6: false
mode: rule

proxies:
  - name: "ua3f"
    type: socks5
    server: 127.0.0.1
    port: 1080
    udp: false

rules:
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - NETWORK,udp,DIRECT
  - MATCH,ua3f
```

含义：

```text
内网地址：DIRECT
UDP：DIRECT
其他 TCP：转到本机 UA3F SOCKS5
```

当前仓库中对应的实验文件：

```text
ua3f-nikki-tproxy-cn.yaml
```

可以通过 Nikki LuCI 页面上传并选择该配置。

---

## 10.2 Nikki 重要设置

当前经验中：

```text
不要代理路由器自身流量
LAN 流量可以代理
router_proxy=0
lan_proxy=1
```

避免：

```text
Nikki 捕获自身出站流量
自身流量再次进入 UA3F
代理连接回到自己
出现 loopback/reject/timeout
```

启动后检查：

```sh
/etc/init.d/nikki restart
logread | grep -i nikki
netstat -lnpt 2>/dev/null | grep -E '7890|7891|7892'
```

如果启用透明代理，需要根据实际模式选择：

```text
REDIR
TPROXY
```

并确认相应内核模块已安装。

---

# 十一、安装 RuijieEportal 手工版本

## 11.1 下载项目

当前手工方式：

```sh
cd /root

wget https://gh-proxy.com/github.com/Barabama/RuijieEportal/archive/refs/heads/main.zip \
    -O /tmp/main.zip

unzip /tmp/main.zip -d /root
```

解压后目录通常为：

```text
/root/RuijieEportal-main
```

建议改成固定目录：

```sh
mv /root/RuijieEportal-main /root/RuijieEportal
```

删除临时压缩包：

```sh
rm -f /tmp/main.zip
```

检查目录：

```sh
find /root/RuijieEportal -maxdepth 2 -type f | sort
```

预期至少包含：

```text
/root/RuijieEportal/main.sh
/root/RuijieEportal/src/rjeportal.sh
/root/RuijieEportal/dist/encrypt_mipsel_24kc
```

赋予权限：

```sh
chmod +x /root/RuijieEportal/main.sh
chmod +x /root/RuijieEportal/src/rjeportal.sh
chmod +x /root/RuijieEportal/dist/encrypt_mipsel_24kc
```

确认架构：

```sh
grep DISTRIB_ARCH /etc/openwrt_release
file /root/RuijieEportal/dist/encrypt_mipsel_24kc
```

---

## 11.2 设置认证参数

默认门户地址通常是：

```text
172.16.0.46
```

如果学校使用其他地址，可临时设置：

```sh
export PORTAL_IP=172.16.0.46
```

如果自动识别加密程序失败，可手动指定：

```sh
export ENCRYPTION=/root/RuijieEportal/dist/encrypt_mipsel_24kc
```

---

## 11.3 查看认证状态

进入脚本目录：

```sh
cd /root/RuijieEportal/src
```

查看状态：

```sh
sh rjeportal.sh status
```

可能结果：

```text
online
captive
unreachable
unknown
```

含义：

```text
online       已联网
captive      被门户拦截，需要认证
unreachable  网络不可达
unknown      探测结果不明确
```

---

## 11.4 手动登录

旧版手工脚本通常使用：

```sh
sh /root/RuijieEportal/main.sh login 用户名 密码
```

或者：

```sh
cd /root/RuijieEportal/src
sh rjeportal.sh login 用户名 密码
```

示例：

```sh
sh /root/RuijieEportal/main.sh login YOUR_USERNAME YOUR_PASSWORD
```

注意：

- 不要把真实账号密码提交到 Git；
- 不要把真实账号密码写入公开文档；
- 不要在截图中暴露密码；
- 登录后立即检查状态。

```sh
sh /root/RuijieEportal/main.sh status
```

当前仓库新版核心包的 CLI 已逐步改为从 UCI 或 stdin 读取密码，因此未来切换到 `rjeportal` IPK 后，命令接口可能与旧版 `main.sh login 用户名 密码` 不同。手工部署时应以设备上实际下载版本的帮助信息为准：

```sh
sh /root/RuijieEportal/main.sh
sh /root/RuijieEportal/src/rjeportal.sh
```

---

## 11.5 登出

```sh
sh /root/RuijieEportal/main.sh logout
```

或：

```sh
cd /root/RuijieEportal/src
sh rjeportal.sh logout
```

登录状态文件通常位于：

```text
/tmp/rjeportal_userindex
```

设备重启后 `/tmp` 中的文件可能丢失，重新登录即可。

---

# 十二、安装 NetTask

NetTask 是可选组件，用来执行：

```text
立即执行脚本
开机执行脚本
定时执行脚本
按键执行脚本
断网触发脚本
```

旧版安装方式：

```sh
wget https://gh-proxy.com/github.com/lucikap/luci-app-nettask/blob/main/luci-app-nettask_2.0.0-1_all.ipk \
    -O /tmp/luci-app-nettask.ipk

opkg install /tmp/luci-app-nettask.ipk
```

但是要注意：

> GitHub 的 `blob` 地址通常返回网页 HTML，而不是 IPK 文件。若下载后安装提示包格式错误，应改用真正的 Release 下载地址、Raw 地址或先在电脑上下载再上传到路由器。

安装后检查：

```sh
opkg list-installed | grep nettask
ls -la /etc/nettask
```

---

# 十三、NetTask 脚本配置

## 13.1 `/etc/nettask/word.sh`

用于登录校园网：

```sh
#!/bin/sh

# 真实账号密码只保存在路由器本地
sh /root/RuijieEportal/main.sh login YOUR_USERNAME YOUR_PASSWORD

exit 0
```

设置权限：

```sh
chmod 700 /etc/nettask/word.sh
```

如果脚本版本支持无参数登录，则改为对应的新命令。

---

## 13.2 `/etc/nettask/duan.sh`

示例：

```sh
#!/bin/sh

# 重启无线
# wifi

# 重启网络
# /etc/init.d/network restart

# 测试 HTTP 请求
# curl "http://example.invalid/health"

# 清理内存
echo 1 > /proc/sys/vm/drop_caches

# 执行认证脚本
sh /etc/nettask/word.sh

exit 0
```

注意：

- 所有命令放在 `exit 0` 之前；
- 不要使用 `return 0` 代替脚本退出；
- 先手工测试每条命令，再加入开机脚本；
- 不要在脚本中写入公开账号密码。

---

## 13.3 `/etc/nettask/network.sh`

开机或网络事件执行：

```sh
#!/bin/sh

sh /etc/nettask/duan.sh

exit 0
```

设置权限：

```sh
chmod 700 /etc/nettask/*.sh
```

---

## 13.4 启用 NetTask

根据 NetTask LuCI 页面配置：

```text
开机执行：启用
断网执行：按需启用
计划任务：按需启用
按键触发：谨慎启用
```

手工执行测试：

```sh
sh /etc/nettask/word.sh
sh /etc/nettask/network.sh
```

查看日志：

```sh
logread | tail -100
ps | grep -E 'nettask|rjeportal'
```

---

# 十四、推荐启动顺序

启动顺序应为：

```text
系统启动
    ↓
无线 STA 连接校园 Wi-Fi
    ↓
获取校园网侧 IP
    ↓
默认路由和 DNS 就绪
    ↓
启动 UA3F
    ↓
启动 Nikki/Mihomo
    ↓
等待代理和网络稳定
    ↓
执行 RuijieEportal status
    ↓
如果 captive，执行 login
```

手工启动示例：

```sh
service ua3f start
/etc/init.d/nikki start

sleep 30

ip route
sh /root/RuijieEportal/main.sh status
sh /root/RuijieEportal/main.sh login YOUR_USERNAME YOUR_PASSWORD
sh /root/RuijieEportal/main.sh status
```

如果使用 NetTask：

```sh
sh /etc/nettask/word.sh
```

不要在无线 STA 尚未连接、没有默认路由时立即登录。

---

# 十五、验证清单

## 15.1 系统和架构

```sh
cat /etc/openwrt_release
uname -a
grep DISTRIB_ARCH /etc/openwrt_release
```

## 15.2 网络

```sh
ip addr
ip route
iwinfo
ping -c 3 223.5.5.5
nslookup example.com
```

## 15.3 UA3F

```sh
command -v ua3f
ua3f --help
service ua3f status
netstat -lnpt 2>/dev/null | grep 1080
```

## 15.4 Nikki

```sh
/etc/init.d/nikki status
logread | grep -i nikki
netstat -lnpt 2>/dev/null | grep -E '7890|7891|7892'
```

## 15.5 RuijieEportal

```sh
command -v curl
curl --version
ls -l /root/RuijieEportal/dist/
sh /root/RuijieEportal/main.sh status
```

如果需要测试登录：

```sh
sh /root/RuijieEportal/main.sh login YOUR_USERNAME YOUR_PASSWORD
sh /root/RuijieEportal/main.sh status
```

## 15.6 LAN 客户端

检查：

```text
是否获得 DHCP 地址
是否能访问路由器管理页面
DNS 是否正常
HTTPS 是否正常
多个设备是否能同时联网
重启后 STA 是否自动连接
重启后是否自动认证
认证失效后是否能重新登录
```

---

# 十六、常见故障

## 16.1 `opkg update` 失败

检查：

```sh
cat /etc/config/network
ip route
ping -c 3 223.5.5.5
nslookup downloads.immortalwrt.org
```

可能原因：

```text
STA 没连接
没有默认路由
DNS 不通
Nikki 错误代理了路由器自身流量
校园网尚未认证
```

---

## 16.2 下载 GitHub 文件得到 HTML

例如：

```sh
wget https://github.com/.../blob/main/file.ipk -O /tmp/file.ipk
```

可能下载的是 GitHub 网页，而不是文件。

检查：

```sh
file /tmp/file.ipk
head -c 100 /tmp/file.ipk
```

如果看到 HTML，应改用：

```text
Release 下载地址
raw.githubusercontent.com 地址
可信镜像
电脑下载后 scp 上传
```

---

## 16.3 RuijieEportal 没有认证参数

认证脚本不是直接访问门户 IP，而是通过访问探测地址触发校园网门户拦截。

检查：

```sh
ip route
curl -I http://connect.rom.miui.com/generate_204
```

确认：

```text
STA 已连接
路由器有校园网侧 IP
默认路由正确
浏览器访问外部 HTTP 确实跳转 ePortal
PORTAL_IP 设置正确
```

---

## 16.4 `pageInfo` 为空或用户名不能为空

优先确认使用 curl：

```sh
command -v curl
curl --version
```

不要只使用：

```text
uclient-fetch
wget
```

因为旧版脚本需要 curl 的：

```text
HTTP Header 处理
POST 参数处理
状态码处理
URL 编码
```

---

## 16.5 代理回环

如果日志出现：

```text
reject loopback connection
context deadline exceeded
```

检查 Nikki 是否代理路由器自身：

```text
router_proxy=0
lan_proxy=1
```

同时确认：

```text
UA3F 监听 127.0.0.1:1080
Nikki 连接本机 UA3F
Nikki 不再次捕获自身出站连接
```

---

## 16.6 重启后认证失败

常见原因：

```text
STA 尚未连接
默认路由尚未生成
DNS 尚未就绪
UA3F 尚未启动
Nikki 尚未启动
系统时间错误
认证命令执行过早
/tmp 登录状态文件丢失
```

可增加等待：

```sh
sleep 30
ip route
sh /root/RuijieEportal/main.sh status
```

---

# 十七、当前 LuCI 集成项目状态

仓库中已经有以下原型：

```text
package/rjeportal/
package/luci-app-rjeportal/
luci-app-nettask/
```

设计原则：

```text
rjeportal
  保存认证协议、RSA、curl、status/login/logout/watchdog

luci-app-rjeportal
  只负责 LuCI 页面和调用固定 CLI

luci-app-nettask
  只负责通用 Shell 任务，不复制认证协议
```

当前独立 LuCI 应用已完成基础页面和依赖设计，但完整 SDK 编译、真实 R3G 测试和稳定性验证仍未全部完成。

因此，如果当前目标是“尽快制作一台能用的路由器”，建议：

```text
现在：使用手工方法部署
以后：再安装和测试 luci-app-rjeportal
```

不要为了等待 LuCI 页面而延迟硬件部署。

---

# 十八、给新 AI 会话的工作要求

请继续基于以下上下文工作：

1. 先阅读：

```text
docs/ruijieeportal-nettask-context.md
docs/opwrt初始化脚本.md
docs/无限制校园网路由器.md
```

2. 当前优先目标不是等待完整 LuCI 集成，而是完善一套可靠的 Xiaomi R3G 手工部署流程。
3. 不要重置当前工作区，不要删除已有未提交修改。
4. 认证协议只能位于：

```text
rjeportal 核心包
src/rjeportal.sh
package/rjeportal/files/rjeportal.sh
```

5. NetTask 不得复制：

```text
curl 请求逻辑
queryString 解析
RSA 加密
ePortal 登录协议
```

6. 如果继续做 LuCI：

```text
优先单独使用 luci-app-rjeportal
不要把认证协议复制到 NetTask
不依赖 luci-lib-fs
使用 nixio.fs 或兼容的标准 LuCI API
```

7. 如果进行真实部署测试，应优先验证：

```text
SSH 获取
MTD 备份
Breed 备份
ImmortalWrt 启动
STA 上联
opkg update
UA3F
Nikki
router_proxy=0
RuijieEportal status
RuijieEportal login
重启自动认证
认证过期重新认证
```

8. 所有账号、密码、MAC、factory/EEPROM 备份都只能保存在本地，不得提交 Git 或公开发布。

---

## 最简急用流程

如果现在只想尽快做出一台设备，可以按这个顺序：

```text
1. XMiR-Patcher 获取 SSH
2. SSH 记录 /proc/mtd
3. 备份全部 /dev/mtdblock*
4. scp 备份到电脑
5. 刷入 Breed
6. 在 Breed 中再次备份
7. Breed 刷 ImmortalWrt 24.10.6
8. 设置 root 密码
9. 配置 STA 连接校园 Wi-Fi
10. opkg update
11. 安装 curl、unzip、LuCI 工具
12. 安装 UA3F 及依赖
13. 安装 Nikki
14. 上传并选择 UA3F-Nikki 配置
15. 设置不代理路由器自身流量
16. 下载 RuijieEportal
17. 执行 status
18. 执行 login
19. 在 NetTask 中配置开机认证
20. 重启验证
```

当前建议：

> 先按手工方式部署一台可用 R3G；`luci-app-rjeportal` 等后续稳定后，再作为管理界面升级安装。

```
opkg update
opkg install \
    curl unzip \
    luci-app-ttyd luci-i18n-ttyd-zh-cn \
    luci-app-argon-config luci-i18n-argon-config-zh-cn \

# ua3f
opkg install \
  luci-compat \
  ipset \
  iptables-nft \
  iptables-mod-tproxy \
  iptables-mod-extra \
  iptables-mod-ipopt \
  iptables-mod-nfqueue \
  iptables-mod-conntrack-extra \
  kmod-nf-conntrack-netlink \
  kmod-nft-queue \
  kmod-nft-tproxy \
  kmod-tun \
  kmod-sched-bpf \
wget https://gh-proxy.com/github.com/SunBK201/UA3F/releases/download/v3.6.0/ua3f_3.6.0-r1_mipsel_24kc.ipk -O /tmp/ua3f.ipk && opkg install /tmp/ua3f.ipk


# nikki
wget -O - https://gh-proxy.com/github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/install.sh | ash


# rjeportal main
wget https://gh-proxy.com/github.com/Barabama/RuijieEportal/archive/refs/heads/main.zip -O /tmp/main.zip && unzip /tmp/main.zip -d ~

# nettask
wget https://gh-proxy.com/github.com/lucikap/luci-app-nettask/blob/main/luci-app-nettask_2.0.0-1_all.ipk -O /tmp/luci-app-nettask.ipk && opkg install /tmp/luci-app-nettask.ipk
```

# 启动执行

sh /etc/nettask/word.sh

# 登录校园网

sh /root/RuijieEportal-main/main.sh login
