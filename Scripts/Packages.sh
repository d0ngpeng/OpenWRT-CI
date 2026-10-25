#!/bin/bash
#在 $GITHUB_WORKSPACE/wrt/package 下执行

set -u

#删掉 feeds 里可能存在的同名/别名包，避免重复定义
DELETE_OLD_PACKAGE() {
	local NAME DIR
	for NAME in "$@"; do
		[ -n "$NAME" ] || continue
		while IFS= read -r DIR; do
			[ -n "$DIR" ] || continue
			rm -rf "$DIR"
			echo "deleted: $DIR"
		done < <(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "$NAME" 2>/dev/null)
	done
}

#安装/更新第三方软件包
#用法：UPDATE_PACKAGE "包名" "仓库" "分支" ["pkg"|"name"] ["旧名字列表"]
#  pkg  —— 大杂烩仓库，只把名字匹配的子目录抠出来
#  name —— 把仓库目录按包名放置
#  默认 —— 把整个仓库放到 ./<仓库名>
#克隆失败/抠不到包时一律保留 feeds 里的原包，不会像以前那样先删后拉、拉挂了包就没了。
UPDATE_PACKAGE() {
	local PKG_NAME="$1"
	local PKG_REPO="$2"
	local PKG_BRANCH="$3"
	local PKG_SPECIAL="${4:-}"
	local CUSTOM_NAMES=()
	local REPO_NAME
	REPO_NAME=$(echo "$PKG_REPO" | cut -d '/' -f 2)

	[ -n "${5:-}" ] && read -r -a CUSTOM_NAMES <<< "$5"
	CUSTOM_NAMES=("$PKG_NAME" "${CUSTOM_NAMES[@]}")

	echo " "
	echo "==> $PKG_NAME  ($PKG_REPO @ $PKG_BRANCH)"

	local TMP_DIR=".clone-tmp-$REPO_NAME"
	rm -rf "$TMP_DIR"
	local OK=0
	for i in 1 2 3; do
		if git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git" "$TMP_DIR" 2>/dev/null; then
			OK=1
			break
		fi
		rm -rf "$TMP_DIR"
		sleep $((i * 3))
	done

	if [ "$OK" != "1" ]; then
		echo "!!! $PKG_REPO 克隆失败，跳过（保留 feeds 原包）"
		return 1
	fi

	if [ "$PKG_SPECIAL" = "pkg" ]; then
		#先抠包，确认抠到了再删旧包
		local EXTRACT_DIR=".extract-$REPO_NAME"
		rm -rf "$EXTRACT_DIR"
		mkdir -p "$EXTRACT_DIR"
		find "./$TMP_DIR"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} "$EXTRACT_DIR"/ \; 2>/dev/null

		if [ -z "$(ls -A "$EXTRACT_DIR" 2>/dev/null)" ]; then
			echo "!!! 在 $PKG_REPO 里没找到 $PKG_NAME，跳过（保留 feeds 原包）"
			rm -rf "$TMP_DIR" "$EXTRACT_DIR"
			return 1
		fi

		DELETE_OLD_PACKAGE "${CUSTOM_NAMES[@]}"
		mv -f "$EXTRACT_DIR"/* ./
		rm -rf "$TMP_DIR" "$EXTRACT_DIR"
	elif [ "$PKG_SPECIAL" = "name" ]; then
		DELETE_OLD_PACKAGE "${CUSTOM_NAMES[@]}"
		rm -rf "./$PKG_NAME"
		mv -f "$TMP_DIR" "./$PKG_NAME"
	else
		DELETE_OLD_PACKAGE "${CUSTOM_NAMES[@]}"
		rm -rf "./$REPO_NAME"
		mv -f "$TMP_DIR" "./$REPO_NAME"
	fi
}

#主题：用 sbwml 的 25.12 分支（带 luci-app-argon-config，feeds 里的版本偏旧）
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12" "" "luci-theme-argon luci-app-argon-config"

#京东云雅典娜 LED 控制（AX6600 灯效，源码树里没有这个包）
UPDATE_PACKAGE "luci-app-athena-led" "NONGFAH/luci-app-athena-led" "main"

#OpenClash：用上游 dev 分支（feeds 里的 luci-app-openclash 就是它的镜像，要先删掉避免重名）
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg" "luci-app-openclash"

#Tailscale LuCI（feeds 里叫 luci-app-tailscale-community，这里用 asvow 版）
UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

#以下默认不启用（体积/依赖会明显变大），要用的取消注释，
#并在 Config/GENERAL.txt 里加对应的 CONFIG_PACKAGE_xxx=y
#homeproxy / nikki / passwall 三个都带 sing-box，同时开必撞包，只留一个
#UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
#UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg" "luci-app-passwall"
#这两个仓库里本体和 LuCI 是分开的两个目录，必须用 pkg 模式整体抠出来
#UPDATE_PACKAGE "alist" "sbwml/luci-app-alist" "main" "pkg" "luci-app-alist alist"
#UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "pkg" "luci-app-mosdns mosdns v2dat"
#京东云玩游戏加速
#UPDATE_PACKAGE "gecoosac" "laipeng668/luci-app-gecoosac" "main" "pkg" "luci-app-gecoosac gecoosac"

#非 immortalwrt 源才需要补 wwan 包
if [[ $WRT_REPO != *"immortalwrt"* ]]; then
	UPDATE_PACKAGE "qmi-wwan" "immortalwrt/wwan-packages" "master" "pkg"
fi

echo " "
echo "第三方包处理完成"
