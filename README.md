# OpenWRT-CI —— 京东云 AX6600（GWRT V2 同源 NSS 版）

云编译京东云 AX6600（雅典娜 / `RE-CS-02` / IPQ6010 + QCN9074 三 radio）固件。

**源码换成 `laipeng668/immortalwrt @ openwrt-25.12`** —— 这条线才是带满血 QCA NSS 的 ImmortalWrt，
GWRT V2（京东云深度定制版）就是基于它做的。原来的 `VIKINGYFY/immortalwrt` 没有 nss 相关 feed，
编译出来是**纯软转发**，不是 GWRT 那套。

## 编译出来的东西

| 项目 | 值 |
| --- | --- |
| 设备 | 京东云 AX6600（`jdcloud_re-cs-02`） |
| 源码 | `laipeng668/immortalwrt` / `openwrt-25.12` |
| 内核 | 6.18（`CONFIG_TESTING_KERNEL`） |
| NSS | `nss-firmware-ipq60xx` 12.5 + `qca-nss-dp` / `drv` / `ecm` / `crypto`，并且显式打开了 `NSS_DRV_*_ENABLE`（不开这些开关，client 模块会被 Kconfig 隐藏，编出来是纯软转发） |
| WiFi | ath11k，`ATH11K_MEM_PROFILE_512M`（三 radio 必须） |
| 蓝牙/LED | `luci-app-athena-led`（雅典娜灯控） |
| 主题 | argon（`openwrt-25.12` 分支，apk 兼容） |
| 默认地址 | `http://10.25.0.1`，root 无密码 |
| 默认 WiFi | `PENG-ROUTER` / `dong3peng2` |

## ⚠️ 刷机前提（照 GWRT 的硬要求）

1. **必须是 12M Kernel 分区表**的机器。6M 分区表强刷上去红灯不开机，只能拆机编程器救。
2. **先升级新版 u-boot**，再刷固件，顺序别反。
3. 进 u-boot Web 刷 `*factory.bin`，然后进 LuCI 用 sysupgrade 刷 `*squashfs-sysupgrade.bin`，
   **不要勾选保留配置**。
4. 5.2G HE160 走 DFS-CAC，开机后要等 60 秒左右才出 WiFi，不是坏了。

> 12M 分区表 / u-boot / GPT 在 GWRT 网盘：<https://p.godsun.pro>（需要 GitHub 登录）。

## 怎么触发编译

- 手动：`Actions` → `QCA-ALL` → `Run workflow`。
  可选填 `PACKAGE`（追加 `.config` 行）或勾选 `TEST`（只出配置文件，不编译）。
- 自动：每天 `Auto-Clean` 跑完后自动编一次（`workflow_run`）。
- 产物：`Releases` 里的 `IPQ60XX-WIFI-YES_<源码>-<分支>_<时间>`，
  同时会传一份 Actions artifact（保留 5 天），Release 挂了也能下。
- `Auto-Clean` 默认保留最近 3 个 Release，某天编译失败时还能刷回上一个好固件。

## 想改的地方

| 想改什么 | 改哪里 |
| --- | --- |
| 机型 / 内核 / NSS 版本 / ath11k 内存 | `Config/IPQ60XX-WIFI-YES.txt` |
| 插件增删 | `Config/GENERAL.txt` |
| 第三方包来源 | `Scripts/Packages.sh` |
| 主题、IP、主机名、WiFi、密码 | `.github/workflows/QCA-ALL.yml` 的 `with:` |
| 编译流程 / 缓存 / Release 说明 | `.github/workflows/WRT-CORE.yml` |

另外 `OWRT-ALL.yml`（MTK / Rockchip / x86）还保留着，用的是 `VIKINGYFY/immortalwrt owrt` 分支，
跟 AX6600 这条线互不影响；不需要可以只留 `QCA-ALL`。

## 关于 GWRT 版本选择

GWRT 现在有两个方向：

- **V2 · 京东云深度定制版**（推荐，最稳）：ImmortalWrt main-nss 底座 + NSS + 三 radio + 代理全家桶，
  页面还是原版 LuCI。本仓库就是按这个底座来的。
- **V3 · v9 仪表盘重建版**：在 V2 上重写了 LuCI 页面（端口映射双主题、iframe 弹窗、容器管理重写），
  玩法更多但改动面大、边界 bug 也多。喜欢那套界面可以单独把主题加进来
  （<https://github.com/rothdren-lion/gwrt-theme>，纯主题包，`integrate.sh` 集成），不用换整套固件。

GWRT 固件本体只在网盘发成品、没有公开源码，所以「自己编」= 用它的底座
（`laipeng668/immortalwrt`）+ 需要的缝合物，也就是这个仓库在做的事。
