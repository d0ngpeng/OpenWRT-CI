#!/bin/bash
#在 $GITHUB_WORKSPACE/wrt/package 下执行

PKG_PATH="$GITHUB_WORKSPACE/wrt/package/"

#=====================================================================
#预置 HomeProxy 规则数据（feeds 自带 luci-app-homeproxy，路径先探测）
#拉不到就保留包内自带规则，不影响编译
#=====================================================================
HP_PATH=""
while IFS= read -r HP_DIR; do
	if [ -d "$HP_DIR/root/etc/homeproxy/resources" ]; then
		HP_PATH="$(cd "$HP_DIR/root/etc/homeproxy" && pwd)"
		break
	fi
done < <(find . ../feeds/luci -maxdepth 5 -type d -name "*homeproxy*" 2>/dev/null || true)

if [ -n "$HP_PATH" ]; then
	HP_RULE="surge"

	rm -rf ./$HP_RULE/
	rm -rf "$HP_PATH"/resources/*

	if git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" ./$HP_RULE/ 2>/dev/null; then
		(
			cd ./$HP_RULE/ || exit 1
			RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*" | head -n 1)
			echo "$RES_VER" | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
			awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
			sed 's/^\.//g' direct.txt > china_list.txt
			sed 's/^\.//g' gfw.txt > gfw_list.txt
			#文件名必须和 homeproxy 期望的一致，否则规则加载会失败
			mv -f ./{china_ip4,china_ip6,china_list,gfw_list}.{ver,txt} "$HP_PATH/resources/"
		)
		rm -rf ./$HP_RULE/
		echo "homeproxy 规则已预置"
	else
		echo "homeproxy 规则拉取失败，保留包内默认"
	fi
fi

#=====================================================================
#Tailscale：asvow 的 LuCI 包自带 /etc/config/tailscale 和 /etc/init.d/tailscale
#（带 exit node / subnet routes 那套完整参数），feeds 里的 tailscale 包也装
#同样两个文件，apk 会报 "trying to overwrite ... owned by tailscale"，整个
#package/install 阶段失败——表现为 make world 失败但日志里没有 ERROR 行。
#让 feeds 的包只提供 tailscaled 二进制，配置和服务脚本交给 LuCI 包。
#=====================================================================
TS_MK="../feeds/packages/net/tailscale/Makefile"
if [ -f "$TS_MK" ]; then
	sed -i \
		-e '/tailscale\.init \$(1)\/etc\/init\.d\/tailscale/d' \
		-e '/tailscale\.conf \$(1)\/etc\/config\/tailscale/d' \
		-e '\#^/etc/config/tailscale$#d' \
		"$TS_MK"
	#改不动就直接失败：否则要等一个多小时编到 install 阶段才炸
	if grep -q 'etc/config/tailscale\|etc/init\.d/tailscale' "$TS_MK"; then
		echo "tailscale 去重失败：$TS_MK 里仍有安装 /etc/config/tailscale 的规则"
		exit 1
	fi
	echo "tailscale 与 luci-app-tailscale 的配置文件冲突已处理"
fi

#=====================================================================
#修改 argon 主题字体和颜色
#=====================================================================
ARGON_DIR=$(find . -maxdepth 2 -type d -name "luci-app-argon-config" 2>/dev/null | head -n 1 || true)
if [ -n "$ARGON_DIR" ] && [ -d ./luci-theme-argon ]; then
	sed -i '/font-weight:/ {/!important/! s/\(font-weight:\s*\)[^;]*;/\1normal;/}' $(find ./luci-theme-argon -type f -iname "*.css" 2>/dev/null) 2>/dev/null || true
	sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/" "$ARGON_DIR/root/etc/config/argon" 2>/dev/null || true
	echo "theme-argon 已调整"
fi

#=====================================================================
#雅典娜 LED 脚本需要可执行权限，否则开机不亮/不生效
#=====================================================================
ATHENA_DIR=$(find . -maxdepth 2 -type d -name "luci-app-athena-led" 2>/dev/null | head -n 1 || true)
if [ -n "$ATHENA_DIR" ]; then
	chmod +x "$ATHENA_DIR"/root/etc/init.d/athena_led "$ATHENA_DIR"/root/usr/sbin/athena-led 2>/dev/null || true
	echo "athena-led 权限已修复"
fi

#=====================================================================
#NSS 相关不用再手改启动顺序：
#nss-packages 里 qca-nss-drv 是 START=94、qca-nss-ecm 是 START=96，
#顺序本来就是对的，乱改反而会和驱动加载时序打架。
#=====================================================================

cd "$PKG_PATH" || exit 0
echo "包处理完成"
