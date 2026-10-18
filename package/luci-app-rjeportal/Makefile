include $(TOPDIR)/rules.mk

LUCI_TITLE:=Ruijie ePortal Authenticator
LUCI_DEPENDS:=+rjeportal +luci-compat
LUCI_PKGARCH:=all

PKG_VERSION:=0.1.0
PKG_RELEASE:=2
PKG_MAINTAINER:=Barabama <barabama@qq.com>
PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE

include $(TOPDIR)/feeds/luci/luci.mk

# The application is intentionally implemented with legacy-compatible Lua CBI
# models. luci.mk installs files below luasrc/ and root/ using the LuCI 24.10
# package layout.


# call BuildPackage - OpenWrt buildroot signature
