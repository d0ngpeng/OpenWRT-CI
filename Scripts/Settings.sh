#!/bin/bash
#在 $GITHUB_WORKSPACE/wrt 下执行（工作流已 cd 进去）

set -e

#WiFi 密码只从仓库 Secret 传进来，漏传时用兜底值，别让固件变成开放网络
WRT_WORD="${WRT_WORD:-12345678}"
WRT_SSID="${WRT_SSID:-ImmortalWrt}"

#=====================================================================
#LuCI 默认主题 / 默认地址提示 / 编译日期
#=====================================================================
#feeds 的 luci collection 里默认还是 bootstrap
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} + || true

#固件刷写页上的地址提示
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} + || true

#概览页显示编译日期
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} + || true

#=====================================================================
#WIFI 默认名称/密码
#25.12 的无线配置由 wifi-scripts 里的 mac80211.uc 生成，改它里面的兜底值。
#（qualcommax 没有 board.d 的 wireless defaults，所以这里 100% 生效）
#=====================================================================
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_UC" ]; then
	sed -i "s/|| \"ImmortalWrt\"/|| \"$WRT_SSID\"/" "$WIFI_UC"
	sed -i "s/\${defaults?.key || \"\"}/\${defaults?.key || \"$WRT_WORD\"}/" "$WIFI_UC"
	#2.4G/5G 默认加密从 none 改成 WPA2-PSK，避免刷完是个开放网络
	sed -i "s/encryption = 'none';/encryption = 'psk2';/" "$WIFI_UC"
fi

#=====================================================================
#默认 IP 与主机名
#只替换 config_generate 里 lan 的兜底地址，别的网段不要动
#=====================================================================
CFG_FILE="./package/base-files/files/bin/config_generate"
if [ -f "$CFG_FILE" ]; then
	sed -i "s/\"192\.168\.1\.1\"/\"$WRT_IP\"/g" "$CFG_FILE"
	sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"
fi

#=====================================================================
#基础包
#=====================================================================
{
	echo "CONFIG_PACKAGE_luci=y"
	echo "CONFIG_LUCI_LANG_zh_Hans=y"
	echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y"
	echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y"
} >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#=====================================================================
#高通平台调整
#=====================================================================
if [[ $WRT_TARGET == *"QUALCOMMAX"* ]]; then
	#NSS 固件版本：nss_packages 的 qca-nss-ecm/qca-nss-drv 是 12.5 的代码
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config

	#ipq60xx 是 1G 内存 + 最多三 radio，Q6 必须用 512M 预留，
	#否则会出现只有 2.4G、5G 起不来
	if grep -q '^CONFIG_TARGET_qualcommax_ipq60xx=y' ./.config; then
		echo "CONFIG_ATH11K_MEM_PROFILE_512M=y" >> ./.config
	fi
fi

#=====================================================================
#不再统一加 -mcpu/-march 自定义优化：
#NSS 驱动、ath11k、内核模块跟工具链强相关，默认编译参数最稳。
#=====================================================================
