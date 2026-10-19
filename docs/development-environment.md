# 开发环境迁移

本文用于把开发工作区从一台电脑迁移到另一台电脑。主仓库只跟踪 `rjeportal` 和 `luci-app-rjeportal`；`luci-app-nettask` 与 `UA3F` 是两个独立 Git 仓库，按设计被主仓库忽略。

## 推荐方式：复制整个工作区

如果旧电脑仍可用，直接复制整个 `RuijieEportal` 目录，并确保包含隐藏的 `.git` 目录。这样会保留主仓库和两个独立仓库的本地分支、提交和未跟踪文件。

迁移后在两台电脑上分别检查：

```sh
git status
git -C luci-app-nettask status
git -C UA3F status
```

## 重新克隆

### 1. 主仓库

```sh
git clone https://github.com/Barabama/RuijieEportal.git
cd RuijieEportal
```

### 2. NetTask fork

```sh
git clone --branch rjeportal-integration \
  https://github.com/Barabama/luci-app-nettask.git \
  luci-app-nettask
```

该分支包含标准 LuCI 包目录扁平化、NetTask init 脚本以及 cron/ping 修正。

### 3. UA3F 上游源码

```sh
git clone https://github.com/SunBK201/UA3F.git UA3F
git -C UA3F checkout 23923d4dd813a5e15c2d896acf30bcb357f42fd1
```

这里固定到当前验证过的提交，避免上游分支变化影响构建结果。

## 目录约定

```text
RuijieEportal/
├── package/
│   ├── rjeportal/
│   └── luci-app-rjeportal/
├── luci-app-nettask/   # 独立 Git 仓库，主仓库忽略
├── UA3F/               # 独立 Git 仓库，主仓库忽略
├── docs/
└── dist/
```

不要把 `UA3F/` 或 `luci-app-nettask/` 用 `git add -f` 加进主仓库。它们应继续作为独立仓库维护；如果以后需要一条命令克隆全部组件，再评估是否改成 Git submodule。

## Windows 行尾

仓库通过 `.gitattributes` 强制文本文件使用 LF，二进制文件保持原样。即使 Windows Git 设置了 `core.autocrlf=true`，Shell、Lua、Makefile 和配置文件也不会被转换成 CRLF。

首次迁移后建议检查：

```sh
git ls-files --eol | head
```

Shell 和 Lua 文件应显示 `i/lf w/lf`。如果旧工作区已经产生 CRLF，可以在确认没有本地改动后重新检出文件：

```sh
git add --renormalize .
git checkout -- .
```

## 本地验证

在 Linux 或 WSL 中运行：

```sh
sh -n package/rjeportal/files/rjeportal
sh -n package/rjeportal/files/rjeportal.sh
sh -n package/rjeportal/files/rjeportal.init

PYTHONDONTWRITEBYTECODE=1 \
  python3 package/rjeportal/tests/test-integration.py
sh package/rjeportal/tests/test-status.sh
PYTHONDONTWRITEBYTECODE=1 \
  python3 package/rjeportal/tests/test-interface.py
```

集成测试只访问 `127.0.0.1` 上的 fake ePortal，不会连接校园网，也不会占用宿舍区认证设备位。

## 构建说明

`package/rjeportal` 当前面向 `ramips/mt7621` 和 `mipsel_24kc`。正式 IPK 应在与 R3G 固件版本匹配的 ImmortalWrt SDK 中构建；x86 虚拟机只用于 LuCI 页面和包布局验证，不能替代 R3G 目标包的编译。

## 凭据和配置

- 真实账号、密码、MAC、Wi-Fi 信息只保存在设备本地。
- 不提交 `.claude/`、`config/`、Python 缓存或本地构建目录。
- 如果曾把真实凭据写入 Git 或 CI 文件，应立即轮换凭据；仅删除当前文件不能清除历史记录。