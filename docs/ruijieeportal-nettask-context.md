# RuijieEportal + NetTask 扩展方案上下文

> 用途：在新会话中恢复“OpenWrt 锐捷认证、NetTask 扩展模块、LuCI 界面和 R3G 量产固件”的讨论。
>
> 记录日期：2026-09-04
>
> 主项目：`RuijieEportal` Git 仓库

## 1. 当前总目标

希望将校园网锐捷 ePortal 认证做成适用于 ImmortalWrt/OpenWrt 的软件包，并最终用于小米 R3G 量产固件。

目标功能：

- `status`：判断已联网、需要认证、网络不可达等状态；
- `login`：执行 ePortal 登录；
- `logout`：执行 ePortal 登出；
- 看门狗：认证失效或网络恢复后自动登录；
- LuCI 页面：配置账号、密码、门户 IP、探测地址和看门狗；
- GitHub Actions：自动构建不同架构的软件包；
- ImmortalWrt 固件：预装 UA3F、Nikki/Mihomo、认证包及常用管理工具。

推荐的软件职责：

```text
rjeportal
  负责 ePortal 协议、RSA 加密、status/login/logout、看门狗、UCI 配置

luci-app-rjeportal
  负责 LuCI 状态页、配置页、登录/登出按钮和看门狗控制

luci-app-nettask fork
  负责通用 Shell 任务；可增加 RuijieEportal 快捷入口，但不要复制认证协议
```

核心原则：

> NetTask 可以调用 `rjeportal`，但不要在 NetTask 中重新实现 curl、queryString、RSA 和 ePortal 登录逻辑。

## 2. 主仓库状态

本文记录的是方案演进过程中的阶段性快照，不是当前分支状态的权威说明。当前代码和构建入口应以仓库中的 `package/`、`.github/workflows/` 和实际提交历史为准。

说明：

- `UA3F/` 是独立的上游 Git 仓库，不应作为普通文件提交到主仓库；
- `package/` 已纳入主仓库的 OpenWrt 软件包布局；
- 本地实验配置和运行数据应放在忽略目录中，不应提交。

## 3. 当前代理测试结论

当前拓扑：

```text
LAN 客户端
  -> Nikki/Mihomo 透明代理
  -> UA3F SOCKS5 127.0.0.1:1080（TCP 规则使用）
  -> DIRECT
```

当前使用的 YAML：

```text
ua3f-nikki-tproxy-cn.yaml
```

核心内容：

```yaml
redir-port: 7891
tproxy-port: 7892

proxies:
  - name: ua3f
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

重要含义：

- `udp_mode` 决定 UDP 是否被 Nikki 捕获；
- `NETWORK,udp,DIRECT` 决定 UDP 进入 Mihomo 后采用 DIRECT；
- `udp: true/false` 只有在规则选择 `ua3f` 时才有明显作用；
- 当前 TCP 会进入 `ua3f`，UDP 最终 DIRECT；
- 当前没有配置远端代理节点，所以 TCP/UDP 最终大概率共用校园网出口，但中间处理路径不同。

已经确认，在：

```sh
uci set nikki.proxy.router_proxy='0'
uci set nikki.proxy.lan_proxy='1'
uci commit nikki
```

的情况下，以下 LOL 测试都能正常拉起：

```text
TCP redirect + UDP disabled
TCP redirect + UDP tproxy
TCP tproxy + UDP tproxy
```

测试时：

```text
Desync = 关闭
```

此前出现过：

```text
reject loopback connection to ...
```

关闭 `router_proxy` 后该问题消失。结论是：路由器自身的 UA3F/Mihomo 出站流量被 Nikki 再次捕获，形成了代理回环。当前应继续保持 `router_proxy=0`。

目前还出现过：

```text
[TCP] dial ua3f ... --> ...:6881 error: context deadline exceeded
```

这通常可能是 BT/P2P、游戏平台后台或其他程序访问远端 6881 端口失败，不能单凭该 warning 判断 LOL 或 Nikki 失败。可以在 LAN 客户端确认来源。

## 4. TCP/UDP 接管方式的定义

```text
TCP redirect + UDP disabled
  TCP 通过 Nikki Redirect，UDP 完全绕过 Nikki

TCP redirect + UDP tproxy
  TCP 通过 Redirect，UDP 通过 TPROXY

TCP tproxy + UDP tproxy
  TCP 和 UDP 都通过 Nikki TPROXY
```

“TCP/UDP 接管方式更统一”只指最后一种模式在内核接管层面都使用 TPROXY，不代表：

- TCP 和 UDP 都经过 UA3F；
- TCP 和 UDP 都使用同一个远程代理；
- TCP 和 UDP 一定具有完全相同的出口路径。

## 5. UA3F 版本和当前源码

目标固定版本：

```text
UA3F v3.6.0
```

归档地址：

```text
https://github.com/SunBK201/UA3F/archive/refs/tags/v3.6.0.tar.gz
```

此前下载归档 SHA256：

```text
067664cf78e2bdb7855e474903da1755d28bee511b5e70b5751d6dc677788bd5
```

当前本地 `UA3F/` checkout 是上游较新的分支状态，显示为：

```text
v3.6.0-2-g23923d4
```

量产时应使用精确 v3.6.0 归档或固定 commit，不要依赖 master。

UA3F v3.6.0 支持：

```text
SOCKS5
TPROXY
REDIRECT
NFQUEUE
Desync
L3 rewrite（TTL、IPID、TCP timestamp、TCP window）
```

组合方案中建议：

```text
Nikki = TPROXY
UA3F  = SOCKS5 127.0.0.1:1080
```

不要让 Nikki 和 UA3F 同时对同一批 LAN 流量使用 TPROXY。

UA3F 当前 OpenWrt 包的源码位置：

```text
UA3F/openwrt/Makefile
```

当前包名是：

```text
ua3f
```

v3.6.0 的 OpenWrt 包已经自带 LuCI 文件，不存在必须单独安装的 `luci-app-ua3f`。

UA3F 当前 Makefile 声明的主要依赖包括：

```text
luci-compat
ipset
iptables
iptables-mod-tproxy
iptables-mod-extra
iptables-mod-ipopt
iptables-mod-nfqueue
iptables-mod-conntrack-extra
kmod-nf-conntrack-netlink
```

虽然主方案不再使用旧版手写 iptables 规则，但这些包可以作为 UA3F 包依赖保留。

## 6. Nikki 版本和当前源码

目标固定版本：

```text
Nikki v1.26.1
```

归档地址：

```text
https://github.com/nikkinikki-org/OpenWrt-nikki/archive/refs/tags/v1.26.1.tar.gz
```

此前下载归档 SHA256：

```text
693e99982c85a72f0594ae45a1e341e3a25ac1d9f8920b0ea87ba3f321cc5f74
```

源码包包含：

```text
mihomo-meta/
nikki/
luci-app-nikki/
```

ImmortalWrt 本地包位置：

```text
~/projects/immortalwrt/package/nikki/
├── mihomo-meta/
├── nikki/
└── luci-app-nikki/
```

Nikki v1.26.1 的关键依赖：

```text
ca-bundle
curl
yq
firewall4
ip-full
kmod-inet-diag
kmod-nft-socket
kmod-nft-tproxy
kmod-tun
kmod-dummy
mihomo
```

其中 `mihomo` 由 `mihomo-meta` 提供。

Nikki 默认 UCI 配置中有：

```text
nikki.proxy.router_proxy=1
nikki.proxy.lan_proxy=1
nikki.proxy.tcp_mode=redirect
nikki.proxy.udp_mode=tun
```

当前实验应显式配置：

```sh
uci set nikki.proxy.router_proxy='0'
uci set nikki.proxy.lan_proxy='1'
```

TCP/UDP 接管模式按测试矩阵逐项改变，不要同时混合 TUN、TPROXY、远程 UDP 代理和 Desync。

Nikki 默认使用：

```text
redir-port 7891
tproxy-port 7892
tun device nikki
DNS listen 1053
```

`router_proxy=0` 是解决当前 UA3F/Mihomo 出站回环的关键设置。

## 7. rjeportal OpenWrt 包当前原型

主项目新增：

```text
package/rjeportal/
├── Makefile
├── LICENSE
└── files/
    ├── encrypt_mipsel_24kc
    ├── rjeportal
    ├── rjeportal.config
    ├── rjeportal.init
    └── rjeportal.sh
```

安装路径：

```text
/usr/bin/rjeportal
/usr/libexec/rjeportal/rjeportal.sh
/usr/libexec/rjeportal/encrypt_mipsel_24kc
/etc/config/rjeportal
/etc/init.d/rjeportal
```

当前配置：

```uci
config rjeportal 'main'
    option enabled '0'
    option portal_ip '172.16.0.46'
    option status_url 'http://connect.rom.miui.com/generate_204'
    option username ''
    option password ''
    option start_delay '30'
    option retry '3'
    option retry_delay '15'
    option userindex_file '/tmp/rjeportal_userindex'
```

当前原型特点：

- 只面向 `ramips/mt7621`；
- 固定安装 MIPS 小端 `encrypt_mipsel_24kc`；
- 账号密码保存于 UCI 配置；
- 包安装时尝试保护配置文件权限；
- 支持命令行 `status/login/logout`；
- init 目前主要负责开机延迟登录和失败重试；
- 还不是持续运行、状态持久化完善的看门狗；
- 还没有 LuCI 页面。

已经做过：

- Shell 语法检查；
- mock ePortal 的 status/login/logout 测试；
- ImmortalWrt package metadata 检查；
- `package/rjeportal/prepare` 阶段检查。

后续需要改进：

1. 状态输出改为机器可读；
2. 明确区分 `online`、`captive`、`unreachable`、`login_failed`；
3. 将登录锁、失败退避和冷却时间放入核心看门狗；
4. 让 `rjeportal login` 默认读取 UCI，而不是将密码放在命令行；
5. 增加 JSON 或 ubus 接口供 LuCI 使用；
6. 将包改造成多架构构建方式；
7. 将认证核心源码设置为唯一来源，避免 `src/rjeportal.sh` 与包内副本漂移。

## 8. NetTask 本地仓库和 PR #7

本地目录：

```text
luci-app-nettask/
```

上游：

```text
https://github.com/lucikap/luci-app-nettask
```

当前本地 main：

```text
5236afd Update ping.sh（某些op不能运行bash，要改为sh）
```

已经 fetch 的未合并 PR：

```text
PR #7
commit 12177dc fix: 修复目录结构和模板路径问题
```

PR 地址：

```text
https://github.com/lucikap/luci-app-nettask/pull/7
```

PR #7 主要修复：

```text
controller/ -> luasrc/controller/
model/      -> luasrc/model/cbi/
view/       -> luasrc/view/cbi/
etc/        -> root/etc/
```

同时将 Makefile 改为标准 LuCI 构建方式：

```make
include $(TOPDIR)/feeds/luci/luci.mk
```

但 PR #7 目前有：

```make
LUCI_DEPENDS:=+luci-lib-fs +luci-compat
```

当前 ImmortalWrt 24.10 feeds 搜索不到：

```bash
./scripts/feeds search luci-lib-fs
```

所以接下来需要：

- 验证 PR #7 是否能编译；
- 可能删除 `luci-lib-fs` 依赖；
- 保留 `luci-compat` 或改用当前 LuCI 文件 API；
- 不要直接使用上游 main 的旧目录结构。

当前上游 main 目录仍是旧结构：

```text
luci-app-nettask/luci-app-nettask/
├── controller/
├── model/
├── view/
└── etc/
```

PR #7 的目录更适合作为 fork 基础。

## 9. NetTask 当前能力和风险

当前功能：

- 立即执行脚本；
- 开机执行脚本；
- 定时执行脚本；
- 物理按键触发；
- 断网触发；
- 上传自定义脚本；
- LuCI 编辑脚本。

当前网络检测脚本：

```sh
ping -c 4 -W 3 8.8.8.8
```

失败后执行：

```text
/etc/nettask/network.sh
```

默认 `network.sh` 基本为空。

因此 NetTask 当前不能直接作为锐捷认证看门狗，因为 ping 失败无法区分：

```text
Wi-Fi 没连接
默认路由没出现
DNS 异常
校园网已连接但未认证
认证门户不可达
认证账号密码错误
Nikki/Mihomo 异常
```

还需要审查：

```text
pgrep -f ... | xargs kill -9
```

这可能误杀进程。

其他风险：

- LuCI 直接编辑和执行 Shell；
- 多处使用未加 `-q` 的 `uci get`；
- 定时任务写入和清理较粗糙；
- 物理 reset 按键脚本会替换原脚本；
- 输入校验较少；
- 需要检查脚本命令注入、日志和权限问题。

因此建议：先吸收 PR #7 解决目录结构和构建问题，再增加 Ruijie 集成；不要一开始全面重写 NetTask。

## 10. 推荐的扩展架构

推荐最终拥有三个包：

```text
rjeportal
luci-app-rjeportal
luci-app-nettask（你的 fork）
```

### rjeportal

负责：

- ePortal 协议；
- RSA 加密；
- status/login/logout；
- 账号和密码 UCI 配置；
- 看门狗；
- 日志；
- procd 服务；
- 结构化状态输出。

### luci-app-rjeportal

负责：

- 服务 -> Ruijie ePortal 页面；
- 状态显示；
- 登录/登出按钮；
- 账号配置；
- 看门狗配置和状态；
- 调用固定的 rjeportal 后端接口。

### luci-app-nettask fork

负责：

- 通用脚本管理；
- 立即、开机、定时、断网、按键任务；
- RuijieEportal 快捷入口或预置任务；
- 不复制 ePortal 认证代码。

若希望减少包数量，可以把 LuCI 页面放入 NetTask fork，但后端仍然应调用 `/usr/bin/rjeportal`。

## 11. 看门狗设计

推荐的状态流程：

```text
启动
  |
等待 LAN/WAN/STA、默认路由和 DNS
  |
执行 rjeportal status
  |
  +-- online
  |     |
  |     +-- 等待下一轮
  |
  +-- unreachable
  |     |
  |     +-- 不登录，等待下一轮
  |
  +-- captive
        |
        +-- 执行 login
                |
                +-- 成功：再次 status
                |
                +-- 失败：记录日志并退避
```

必须具备：

- 单实例锁；
- LuCI 手动登录和看门狗互斥；
- 最大重试次数；
- 失败冷却时间；
- 网络未就绪时不登录；
- 登录后再次确认在线；
- 不在日志打印密码；
- `logger -t rjeportal`；
- 可查询的最后状态和计数器。

建议用 procd 管理长期看门狗，NetTask 只提供快捷开关或入口。

建议状态至少有：

```text
online
captive
unreachable
login_failed
unknown
```

当前 rjeportal 原型的 `enabled/start_delay/retry/retry_delay` 只能作为基础，不能视为最终看门狗实现。

## 12. LuCI 页面设计

建议页面入口：

```text
服务 -> Ruijie ePortal
```

页面区域：

### 状态

```text
当前状态
门户 IP
最后检测时间
最后登录时间
最后错误
连续失败次数
看门狗运行状态
```

按钮：

```text
刷新
登录
登出
启动/停止看门狗
```

### 账号配置

```text
用户名
密码
门户 IP
状态探测 URL
```

配置存储：

```text
/etc/config/rjeportal
```

权限：

```text
600
```

### 看门狗配置

```text
启用
检测间隔
启动延迟
失败重试次数
失败冷却时间
```

LuCI 后端不要执行任意用户输入的命令，只允许固定操作，例如：

```text
status
login
logout
watchdog_status
watchdog_start
watchdog_stop
save_config
```

## 13. ImmortalWrt WSL 环境

WSL：

```text
Ubuntu-24.04
```

ImmortalWrt：

```text
~/projects/immortalwrt
```

当前源码描述：

```text
分支：openwrt-24.10
版本：v24.10.6-119-g99ca94091f
```

注意：这不是精确 `v24.10.6` tag，而是 v24.10 分支后续 commit。量产需要决定：

- 切换到精确 `v24.10.6` tag；或
- 固定并记录 `99ca94091f` 完整 commit。

已经执行：

```bash
./scripts/feeds update -a
./scripts/feeds install -a
```

当前 ImmortalWrt 已加入本地包：

```text
~/projects/immortalwrt/package/UA3F/
~/projects/immortalwrt/package/nikki/
~/projects/immortalwrt/package/rjeportal/
```

当前 metadata 已识别：

```text
ua3f
nikki
mihomo-meta
luci-app-nikki
rjeportal
```

当前 `.config` 仍然是 x86_64 默认配置：

```text
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
```

尚未切换到 R3G。

R3G 目标：

```text
ramips/mt7621/xiaomi_mi-router-3g
```

源码中的设备定义：

```text
DEVICE_MODEL := Mi Router 3G
IMAGE_SIZE := 124416k
SUPPORTED_DEVICES += R3G mir3g xiaomi,mir3g
```

后续要先在 `make menuconfig` 中选择：

```text
Target System  -> MediaTek Ralink MIPS
Subtarget      -> MT7621 based boards
Target Profile -> Xiaomi Mi Router 3G
```

## 14. 推荐的量产包

目标固件可以饱和式包含：

```text
ua3f
nikki
mihomo-meta
luci-app-nikki
rjeportal
```

管理工具：

```text
curl
libcurl
ca-bundle
yq
unzip
ip-full
firewall4
nftables-json

kmod-nft-tproxy
kmod-nft-queue
kmod-nft-socket
kmod-inet-diag
kmod-dummy
kmod-tun
kmod-sched-bpf

ipset
iptables-nft
iptables-mod-tproxy
iptables-mod-extra
iptables-mod-ipopt
iptables-mod-nfqueue
iptables-mod-conntrack-extra
kmod-nf-conntrack-netlink

luci-compat
luci-app-ttyd
luci-i18n-ttyd-zh-cn
luci-theme-argon
luci-app-argon-config
luci-i18n-argon-config-zh-cn
filebrowser
luci-app-filebrowser
luci-i18n-filebrowser-zh-cn
```

不加入当前主方案：

```text
kmod-rkp-ipid
UA2F
手写旧版 iptables 规则
ShellCrash
Python 认证环境
GMP/GMPY2
luci-app-nettask（是否加入量产待定）
```

说明：

- `luci-theme-argon` 是主题本体，不能只写 `argon`；
- `ua3f` 当前包已经包含 LuCI，不要误写成不存在的 `luci-app-ua3f`；
- `nikki` 需要 Mihomo provider，建议选择 `mihomo-meta`；
- `filebrowser` 和 `luci-app-filebrowser` 建议一起选择；
- `firewall4` 会依赖 `nftables-json`；
- 旧 iptables 包可以因为 UA3F 依赖保留，但不再作为手写规则运行时依赖。

## 15. GitHub Actions 构建设计

建议分两类工作流。

### 包构建

```text
build-packages.yml
  下载对应 ImmortalWrt SDK
  放入 rjeportal、luci-app-rjeportal、NetTask fork
  构建 ipk
  检查 shell/lua
  检查 ELF 架构
  上传软件包
```

输出示例：

```text
rjeportal_0.x.x-1_mipsel_24kc.ipk
luci-app-rjeportal_0.x.x-1_all.ipk
luci-app-nettask_2.x.x-1_all.ipk
```

`rjeportal` 含架构相关加密程序，需要按架构构建；LuCI 包通常是 `all`。

### 固件构建

```text
build-firmware.yml
  固定 ImmortalWrt commit/tag
  固定 UA3F v3.6.0
  固定 Nikki v1.26.1
  加入所有必要包
  生成 R3G image
  上传 sha256
```

GitHub Actions 可以测试：

- Shell 语法；
- Lua 基础检查；
- OpenWrt package build；
- 加密程序交叉编译；
- ELF 架构；
- mock ePortal；
- 包依赖。

GitHub Actions 无法替代真实校园网测试。真实测试必须在 R3G 上进行：

- status/login/logout；
- 开机认证；
- 认证过期；
- STA 重连；
- LOL 多 LAN 双排；
- 三角洲；
- 燕云十六声；
- UDP/TCP 模式；
- CPU、内存、延迟、掉线和长期封禁观察。

## 16. 重要命令

### ImmortalWrt 包搜索

```bash
cd ~/projects/immortalwrt

./scripts/feeds search PACKAGE_NAME
```

注意：该命令主要搜索 feeds，不一定搜索源码树核心包或本地包。

搜索整个源码树：

```bash
grep -R -n \
  -E '^define (Package|KernelPackage)/PACKAGE_NAME$' \
  package feeds
```

查看构建系统识别的包：

```bash
grep -m1 -A15 '^Package: rjeportal$' tmp/.packageinfo
grep -m1 -A15 '^Package: ua3f$' tmp/.packageinfo
grep -m1 -A15 '^Package: nikki$' tmp/.packageinfo
grep -m1 -A15 '^Package: mihomo-meta$' tmp/.packageinfo
```

### NetTask

```powershell
git -C luci-app-nettask status --short
git -C luci-app-nettask log --oneline --decorate -5
git -C luci-app-nettask show --stat pr-7
```

### 主项目

```powershell
git status --short
git log --oneline --decorate -5
```

## 17. 新会话开场白

新会话可以直接发送：

> 请读取 `docs/ruijieeportal-nettask-context.md`。继续实现 NetTask fork 的 RuijieEportal 集成。先以 PR #7 为基础检查标准 LuCI 目录结构和 `luci-lib-fs` 依赖，再决定是新增 `luci-app-rjeportal` 还是把页面集成到 NetTask。认证协议必须保持在 `rjeportal` 核心包中，不能复制到 NetTask。

推荐的新会话工作顺序：

```text
1. 检查并采用 PR #7 目录结构
2. 修正 NetTask 的 LuCI 依赖
3. 让 fork 在 ImmortalWrt 24.10 编译通过
4. 完善 rjeportal 机器可读状态和 watchdog
5. 设计 LuCI 页面
6. 将页面接到 rjeportal 后端
7. 加入 GitHub Actions
8. 再接入 R3G 量产固件
```

## 18. 2026-09-05 断网后续实现快照

已继续完成以下阶段性实现，工作区没有重置：

### NetTask fork

`luci-app-nettask` 已基于 PR #7 commit `12177dc` 建立 `rjeportal-integration` 分支，并将可编译包目录扁平化为仓库根目录：

```text
luci-app-nettask/
├── Makefile
├── luasrc/
└── root/
```

当前 Makefile 使用：

```make
include $(TOPDIR)/feeds/luci/luci.mk
LUCI_DEPENDS:=+luci-compat
LUCI_PKGARCH:=all
```

已经移除 `luci-lib-fs` 依赖，并将高级页面从 `luci.fs`/`luci.tools.webadmin` 迁移到 `nixio.fs`，显式加载 `nixio`。同时修复了部分 NetTask 自身问题：

- 上传文件名限制为安全 `.sh` basename；
- 删除上传文件和试运行路径使用固定目录及 shell quoting；
- cron 只删除自己的唯一标记行，并校验 cron 字段；
- `ping.sh`、NetTask init 增加 PID 文件和 stop/reload；
- 原有 `pgrep | xargs kill` 的立即执行路径改为 PID 文件；
- 认证协议没有复制到 NetTask。

### rjeportal 核心包

`package/rjeportal` 当前原型已经增加：

- 机器可读状态：`online`、`captive`、`unreachable`、`unknown`；
- `rjeportal login` 无参数读取 UCI 账号密码，并通过 stdin 交给核心脚本；
- 登录/登出操作锁；
- `watchdog_status`、`watchdog_start`、`watchdog_stop`；
- 看门狗检测间隔和失败冷却时间；
- session 文件路径校验及原子写入；
- 不再打印完整 queryString；
- `PKGARCH:=mipsel_24kc` 保留为 R3G 当前目标包。

认证协议、queryString、RSA 和 curl 仍只位于：

```text
package/rjeportal/files/rjeportal.sh
```

### 独立 LuCI 页面

已经新增：

```text
package/luci-app-rjeportal/
```

页面调用固定的 `/usr/bin/rjeportal` 子命令，不实现认证协议：

- 状态页：status、login、logout、watchdog 控制；
- 配置页：账号、密码、门户 IP、探测 URL、启动及重试参数；
- RPC ACL：只允许读取/写入 `rjeportal` UCI 配置；
- 依赖：`+rjeportal +luci-compat`，没有 `luci-lib-fs`。

### 已执行验证

```text
Shell syntax: pass
rjeportal interface contract test: pass
rjeportal status mock test: pass
Lua 5.1 syntax check: pass
ImmortalWrt 24.10 package metadata: pass
ImmortalWrt 24.10 package prepare: pass
```

当前 WSL ImmortalWrt 源码树为 `openwrt-24.10` commit `99ca94091f`。完整 package compile 尚未完成：该本地 x86_64 工具链缓存缺少 `ld-musl-*.so`，失败发生在 toolchain 包准备阶段，不是三个包的 Makefile/prepare 阶段。

### 后续优先级

1. 在完整 SDK 或干净 ImmortalWrt 工具链上构建三个 ipk；
2. 在 R3G 上安装并测试 `rjeportal status/login/logout`；
3. 测试认证过期、STA 重连和 watchdog；
4. 再决定是否把 NetTask 的 Ruijie 快捷入口作为独立扩展加入；
5. 最后将 `package/rjeportal/files/rjeportal.sh` 与 `src/rjeportal.sh` 收敛为单一源码来源。
