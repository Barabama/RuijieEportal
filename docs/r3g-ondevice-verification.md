# R3G 真机验证记录

本文记录在小米 R3G（ImmortalWrt 24.10.6，ramips/mt7621）上安装并验证
`rjeportal`、`luci-app-rjeportal` 和 `luci-app-nettask` 三个 IPK 的结果。

记录日期：2026-10-21。

## 1. 环境

| 项目 | 值 |
| --- | --- |
| 固件 | ImmortalWrt 24.10.6 r33869-cf234f8de6d5 |
| 内核 | Linux 6.6.133 |
| 架构 | `mipsel_24kc`，`TARGET_ramips_mt7621` |
| LAN | `192.168.101.1/24` |
| 上联 | `wan` DHCP，校园网地址 `10.132.199.146/16` |
| 认证门户 | `172.16.0.46` |
| 同时运行 | ua3f 3.6.0-r1（TPROXY）、nikki 1.26.1（`enabled=0`） |

`ua3f` 与 Nikki 的当前组合属于已验证的稳定配置，本次部署未做改动。

## 2. 构建

```sh
sh tools/build-packages.sh [SDK_PATH]
```

需要与目标固件版本一致的 ImmortalWrt SDK。脚本会关闭 SDK 默认的
multi-profile / all-profiles，只保留 `xiaomi_mi-router-3g`，然后编译三个包并把
IPK 复制到 `build/ipk/`（该目录不纳入版本控制）。

两个环境相关注意事项：

- 在 WSL 中构建要先清掉 Windows PATH。WSL 会把带空格和冒号的 Windows 路径混入
  `PATH`，OpenWrt 的 Makefile 会因此报 `multiple target patterns` 直接失败。
- SDK 首次构建会下载源码包；`sources.openwrt.org` 可用，`www.openssl.org` 很慢，
  会让 `prereq` 长时间停在 `openssl-3.0.19.tar.gz`。

## 3. 安装与验证方式

```sh
opkg install /tmp/ipk/rjeportal_*.ipk
opkg install /tmp/ipk/luci-app-rjeportal_*.ipk
opkg install --force-reinstall /tmp/ipk/luci-app-nettask_*.ipk
```

真机验证使用三种手段：

1. **真实校园网**：直接执行 `/usr/bin/rjeportal status|login|logout`。
2. **本地假门户**：`tools/fake_eportal_lan.py` 复用
   `package/rjeportal/tests/fake_eportal.py` 的状态机，监听 LAN 地址供路由器访问。
   需要时在路由器上把 `PORTAL_IP`/`STATUS_URL` 指向该地址，用 `USERINDEX_FILE`
   指定临时会话文件，从而在不接触校园网的情况下覆盖 `captive → login → online →
   logout` 全流程。
3. **LuCI 页面**：在路由器本机 `curl` 登录 `uhttpd` 后抓取页面，检查 HTTP 状态与
   关键字段。

> 只有 `core` 需要假门户。`/usr/bin/rjeportal` 和 `/etc/init.d/rjeportal` 里写死的
> 安装路径无法重定向，所以真机全流程用真实门户验证。

## 4. 本次修复的问题

### 4.1 `rjeportal.init` 缺少 `EXTRA_COMMANDS`，看门狗不可用

OpenWrt 的 `/etc/rc.common` 只会分发 `ALL_COMMANDS` 中列出的动作，未声明
`EXTRA_COMMANDS` 时 `watchdog_start/stop/status` 会退化成打印用法。这一缺陷在
单元测试里看不出（测试直接调用函数），只在设备上暴露。已补上声明并加测。

注意 `sh /etc/init.d/<name> <cmd>` 不经过 `rc.common`，不能用来验证子命令。

### 4.2 `status.lua` 触发 `luci.util.pcdata` 弃用警告

LuCI 24.10 已把 `pcdata` 移到 `luci.xml`；旧的 `luci.util` 入口每次调用都会
`perror()`，状态页刷新一次就写一条 syslog。已优先使用 `luci.xml.pcdata`，并用
`pcall` 保留旧版本回退。

### 4.3 NetTask 模板 CRLF 导致高级功能页 500

`luci-app-nettask` 独立仓库没有 `.gitattributes`，Windows Git 以 CRLF 检出
`luasrc/view/cbi/*.htm`，LuCI 模板编译器报
`unfinished string near '"'`，`/admin/system/NetTask/trontabs` 返回 500。已添加与
主仓库一致的 `* text=auto eol=lf` 并重新检出。

这三处都需要在 IPK 版本号上递增才能让 opkg 真正升级：`rjeportal` →
`0.2.0-r5`，`luci-app-rjeportal` → `0.1.0-r3`。

## 5. 验证结果

### 5.1 认证闭环（安装后的包，真实校园网）

未认证状态由校园网自助服务取消无感认证并下线后取得：

```text
/usr/bin/rjeportal status   -> captive (rc=1)
/usr/bin/rjeportal login    -> {"result":"success",...} (rc=0)
/usr/bin/rjeportal status   -> online  (rc=0)
curl generate_204           -> 204
/usr/bin/rjeportal logout   -> {"result":"success","message":"下线成功！"} (rc=0)
/usr/bin/rjeportal status   -> captive (rc=1)
```

会话文件登录后生成（权限 600），登出成功后删除。

补充观察：这次用于制造未认证状态的实验环境是宿舍区有线 WAN。只把 `ifdown wan`
断开 15 秒或 45 秒都不会让 NAS 释放会话，重新 `ifup` 后仍是 `online`，因此“断网”
不能替代“下线”。

### 5.2 看门狗与重连

临时把 `check_interval` 降到 10 秒，启动看门狗后执行 `logout`：

```text
logread: rjeportal: watchdog started
logread: rjeportal: network state: captive; attempting login
logread: rjeportal: login succeeded (attempt 1)
logread: rjeportal: watchdog login verified
```

约 30 秒内 `status` 回到 `online`，`generate_204` 恢复 204。验证后
`check_interval` 已恢复为 60 秒。

### 5.3 重启后自愈

`enabled=1`、`/etc/rc.d/S99rjeportal` 存在的情况下重启路由器：

```text
watchdog_status -> running
status          -> online
logread         -> watchdog started / captive / login succeeded (attempt 1)
```

### 5.4 LuCI

```text
/admin/services/rjeportal/status   -> 200，显示 Online、Watchdog running
/admin/services/rjeportal/config   -> 200，账号、门户 IP、看门狗参数正常
/admin/system/NetTask/commonly     -> 200
/admin/system/NetTask/trontabs     -> 200
```

状态页显示的 `stop → start` 与 `start_delay=30` 与 reboot 日志中的时间差一致。

## 6. 遗留

- `rjeportal` 仍固定 `PKGARCH:=mipsel_24kc` 并依赖 `@TARGET_ramips_mt7621`。
  要覆盖其他架构，需要把加密二进制改成按 `DISTRIB_ARCH` 选择安装。
- 设备上旧的手工部署（`/root/RuijieEportal-main` + NetTask 定时登录）已被
  `rjeportal` 包取代；`nettask.main.word`/`network` 已置 0，避免两套机制同时登录。
- 明文凭据只应存在于 `/etc/config/rjeportal`（权限 600）。本次清理了设备上遗留的
  `word.sh` 与 NetTask 备份文件中包含的明文密码。