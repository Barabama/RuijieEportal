include $(TOPDIR)/rules.mk

PKG_NAME:=rjeportal
PKG_VERSION:=0.2.0
PKG_RELEASE:=5
PKGARCH:=mipsel_24kc

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Barabama <barabama@qq.com>

include $(INCLUDE_DIR)/package.mk

define Package/rjeportal
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Ruijie ePortal campus network authenticator
  URL:=https://github.com/Barabama/RuijieEportal
  DEPENDS:=@TARGET_ramips_mt7621 +curl +ca-bundle
endef

define Package/rjeportal/description
  Shell-based Ruijie ePortal authenticator for Xiaomi Mi Router 3G.
  The account and password are configured on the router and are not
  embedded in the firmware image.
endef

define Package/rjeportal/conffiles
/etc/config/rjeportal
endef

define Package/rjeportal/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || chmod 600 /etc/config/rjeportal
exit 0
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/rjeportal/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/rjeportal.config $(1)/etc/config/rjeportal
	chmod 600 $(1)/etc/config/rjeportal

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/rjeportal.init $(1)/etc/init.d/rjeportal

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/rjeportal $(1)/usr/bin/rjeportal

	$(INSTALL_DIR) $(1)/usr/libexec/rjeportal
	$(INSTALL_BIN) ./files/rjeportal.sh $(1)/usr/libexec/rjeportal/rjeportal.sh
	$(INSTALL_BIN) ./files/encrypt_mipsel_24kc $(1)/usr/libexec/rjeportal/encrypt_mipsel_24kc
endef

$(eval $(call BuildPackage,rjeportal))