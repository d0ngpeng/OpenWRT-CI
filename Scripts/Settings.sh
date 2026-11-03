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
#旁路由模式（WRT_MODE=bypass）：
#设备接在现有网络里，自己的默认路由/DNS 指向现有主路由，
#并关掉本机 DHCP，避免和主路由抢着发地址。
#用 uci-defaults 做，首次启动（factory 刷完）时执行。
#=====================================================================
if [ "$WRT_MODE" = "bypass" ]; then
	WRT_GW="${WRT_GW:-10.25.0.1}"
	mkdir -p ./package/base-files/files/etc/uci-defaults
	cat > ./package/base-files/files/etc/uci-defaults/99-bypass <<EOS
#!/bin/sh
#旁路由：上行和 DNS 走现有主路由，本机不发 DHCP/RA
uci -q set network.lan.gateway='$WRT_GW'
uci -q set network.lan.dns='$WRT_GW'
uci -q set dhcp.lan.ignore='1'
uci -q set dhcp.lan.ra='disabled'
uci -q set dhcp.lan.dhcpv6='disabled'
uci -q set dhcp.lan.ndp='disabled'
uci -q commit network
uci -q commit dhcp
exit 0
EOS
	chmod 0755 ./package/base-files/files/etc/uci-defaults/99-bypass
fi

#=====================================================================
#无线默认值修正（首次启动执行一次）：
#1) 5G 射频的 default_channel 由 wifi-detect.uc 从硬件能力探测，AX6600 的 phy0
#   会落到 100（5500MHz，DFS/RADAR），hostapd 在 AP 模式下直接拒绝：
#   "Frequency 5500 (primary) not allowed for AP mode, flags: RADAR"。
#2) 2.4G 默认 ch1，在密集住宅区同信道邻区极多（实测 33 个、占用 59%），改 ch6。
#3) 5G 的 dtim_period=1，降低省电客户端的唤醒抖动（游戏延迟更稳）。
#4) disassoc_low_ack=0，避免丢几个 ACK 就把客户端踢下线。
#5) 2.4G 单独 SSID（后缀 -2G），避免客户端在没有 band steering 时停在 2.4G。
#=====================================================================
mkdir -p ./package/base-files/files/etc/uci-defaults
cat > ./package/base-files/files/etc/uci-defaults/99-wifi-tuning <<'EOS'
#!/bin/sh
#无线默认值修正：DFS 信道 / 2.4G 信道 / dtim / low_ack / 2.4G 独立 SSID
for s in $(uci show wireless 2>/dev/null | sed -n "s/^wireless\.\([^.=]*\)=wifi-device$/\1/p"); do
	band="$(uci -q get wireless.$s.band)"
	ch="$(uci -q get wireless.$s.channel)"
	if [ "$band" = "5g" ]; then
		case "$ch" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140|144)
				uci -q set wireless.$s.channel='149'
				;;
		esac
	elif [ "$band" = "2g" ] && [ "$ch" = "1" ]; then
		uci -q set wireless.$s.channel='6'
	fi
done
for i in $(uci show wireless 2>/dev/null | sed -n "s/^wireless\.\([^.=]*\)=wifi-iface$/\1/p"); do
	uci -q set wireless.$i.disassoc_low_ack='0'
	dev="$(uci -q get wireless.$i.device)"
	if [ "$(uci -q get wireless.$dev.band)" = "5g" ]; then
		uci -q set wireless.$i.dtim_period='1'
	elif [ "$(uci -q get wireless.$dev.band)" = "2g" ]; then
		ssid="$(uci -q get wireless.$i.ssid)"
		case "$ssid" in
			*-2G|"") ;;
			*) uci -q set wireless.$i.ssid="$ssid-2G" ;;
		esac
	fi
done
uci -q commit wireless
exit 0
EOS
chmod 0755 ./package/base-files/files/etc/uci-defaults/99-wifi-tuning

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

	#AX6600 端口对调：2.5G（dp5 / qca8081）改叫 lan4 进 LAN，
	#原 lan1（dp1）改叫 wan 当上行，lan2/lan3/lan4 依次前移成 lan1/lan2/lan3。
	#netdev 名字来自 DTS 的 label，board.d 的 ucidef_set_interfaces_lan_wan
	#（"lan1 lan2 lan3 lan4" "wan"）不用动，角色自然跟着走。
	DTS_CS02="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs-02.dts"
	#用 dp1 的当前 label 判断是否已换过，保证反复执行不会又换回去
	if [ -f "$DTS_CS02" ] && grep -A3 '&dp1 {' "$DTS_CS02" | grep -q 'label = "lan1"'; then
		sed -i \
			-e 's/label = "lan1"/label = "__p1"/' \
			-e 's/label = "lan2"/label = "__p2"/' \
			-e 's/label = "lan3"/label = "__p3"/' \
			-e 's/label = "lan4"/label = "__p4"/' \
			-e 's/label = "wan"/label = "__p5"/' \
			-e 's/label = "__p1"/label = "wan"/' \
			-e 's/label = "__p2"/label = "lan1"/' \
			-e 's/label = "__p3"/label = "lan2"/' \
			-e 's/label = "__p4"/label = "lan3"/' \
			-e 's/label = "__p5"/label = "lan4"/' \
			"$DTS_CS02"
		#校验：dp1 必须是 wan，dp5 必须是 lan4
		if ! grep -A3 '&dp1 {' "$DTS_CS02" | grep -q 'label = "wan"' ||
		   ! grep -A4 '&dp5 {' "$DTS_CS02" | grep -q 'label = "lan4"'; then
			echo "ERROR: AX6600 DTS 端口对调失败（dp1 应为 wan，dp5 应为 lan4）"
			exit 1
		fi
	fi

	#Docker 的 data-root 必须落在真实文件系统上：
	#OpenWrt 的 / 是 overlayfs（lower=/rom，upper=/overlay/upper 在 f2fs 上），
	#dockerman 默认 data-root=/opt/docker 因此建在 overlayfs 上，Docker/containerd
	#的 overlay2 再叠一层 overlay 会被内核拒绝（mount: invalid argument）。
	#启动 dockerd 之前把 /opt/docker bind 到 f2fs 上的真实目录即可。
	if grep -q '^CONFIG_PACKAGE_dockerd=y' ./.config; then
		cat > "./package/base-files/files/etc/init.d/docker_data" <<'EOS'
#!/bin/sh /etc/rc.common
#把 docker 的 data-root 放到真实文件系统上，避免 overlay 套 overlay。
#OpenWrt 的 / 是 overlayfs，upperdir=/overlay/upper（f2fs）。
START=98

boot() {
	start
}

#在目标文件系统上试挂一次 overlay，确认内核允许
ovl_test() {
	local t=/overlay/upper/.docker_ovl_test
	rm -rf "$t"
	mkdir -p "$t/lower" "$t/upper" "$t/work" "$t/merged" || return 1
	if mount -t overlay overlay \
		-o "lowerdir=$t/lower,upperdir=$t/upper,workdir=$t/work" "$t/merged"; then
		umount "$t/merged" 2>/dev/null
		rm -rf "$t"
		return 0
	fi
	rm -rf "$t"
	return 1
}

log() {
	logger -t docker_data "$*"
}

start() {
	local cur
	cur=$(awk '$2 == "/opt/docker" { print $1" "$3 }' /proc/mounts)
	log "entry: /opt/docker mounted as: ${cur:-none}"

	[ -d /opt/docker ] || mkdir -p /opt/docker

	#不管谁先挂了 /opt/docker（首启实测会被挂成 overlay），先卸掉重挂
	if [ -n "$cur" ]; then
		umount /opt/docker 2>/dev/null || umount -l /opt/docker 2>/dev/null
	fi

	if [ -d /overlay/upper ]; then
		mkdir -p /overlay/upper/opt/docker
		if mount --bind /overlay/upper/opt/docker /opt/docker && ovl_test; then
			log "ok: /opt/docker -> f2fs (/overlay/upper/opt/docker), now: $(awk '$2 == "/opt/docker" { print $1" "$3 }' /proc/mounts)"
			return 0
		fi
		umount /opt/docker 2>/dev/null
	fi

	#兜底：overlay 用不了就用 vfs 驱动，至少容器能建起来（慢、占空间）
	logger -t docker_data "warn: overlay 在 /opt/docker 上不可用，回退 storage-driver=vfs"
	uci -q set dockerd.globals.storage_driver='vfs'
	uci -q commit dockerd
	return 0
}
EOS
		chmod 0755 "./package/base-files/files/etc/init.d/docker_data"
	fi
fi

#=====================================================================
#不再统一加 -mcpu/-march 自定义优化：
#NSS 驱动、ath11k、内核模块跟工具链强相关，默认编译参数最稳。
#=====================================================================
