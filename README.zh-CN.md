# openwrt-hilink-3ginfo

[Русский](README.md) · [English](README.en.md) · **中文**

用于在 **OpenWrt 25（apk）** 上通过 [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) 面板监控 **华为 E3372（HiLink）** USB 调制解调器的安装脚本。

在干净的系统上运行一次即可：安装驱动和依赖、添加 4IceG 软件源、安装面板，并（可选）自动为你配置调制解调器的网络接口。

## 为什么需要它

在 HiLink 模式下，华为 E3372 表现为一块 USB 网卡：它自身完成 NAT，并在 `192.168.8.1` 上提供 Web 管理界面。3ginfo 面板读取其数据（运营商、LTE、RSSI/RSRP/SINR/RSRQ 等）不是通过 AT 指令，而是通过 HTTP 请求访问调制解调器的 API。这需要一组特定的软件包——本脚本负责部署它们，并规避常见的坑。

## 环境要求

- 使用 **apk** 包管理器的 OpenWrt 25.x（本脚本不适用于基于 opkg 的固件）。
- 运行时路由器需可访问互联网（通过调制解调器或其他上行链路）——需下载软件包和软件源密钥。
- 处于 HiLink 模式（USB VID `12d1`）、已插入并被系统识别的华为 E3372。

## 脚本做了什么

1. 安装 USB 与网络驱动：`usbutils`、`usb-modeswitch`、`kmod-usb-*`、`kmod-usb-net-cdc-ether`、`kmod-usb-net-rndis`。
2. 安装 **GNU wget（`wget-ssl`）** 和 `sms-tool`。
3. 校验 `/usr/bin/wget` 确为 GNU 版本而非 BusyBox（必要时修复 alternatives 软链接）。
4. 添加 [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) apk 软件源及其签名密钥。
5. 安装 `luci-app-3ginfo-lite`，询问（`y/n`）是否安装面板的俄语语言包，并将调制解调器地址 `192.168.8.1` 写入面板配置。
6. *（可选，需确认）* 通过 USB VID `12d1` 找到调制解调器的网络接口，创建 `interface LTE_Huawei_3372`（proto dhcp），将其加入 `wan` 防火墙区域并绑定到面板。
7. *（可选，需确认）* 重启路由器。

两个可选步骤都会请求确认——不会在无提示的情况下改动 network/firewall 或执行重启。

## 安装

命令需在**路由器上**（通过 SSH）执行，而不是在你的电脑上：

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-hilink-3ginfo/main/setup-hilink-3ginfo.sh
sh setup-hilink-3ginfo.sh
```

安装完成后，在 LuCI 中打开 **Modem → 3ginfo-lite** 并刷新 Modem(s) 标签页（Ctrl+F5）——数据应会显示出来。

## 卸载

要移除脚本安装的所有内容，请使用卸载脚本。在路由器上：

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-hilink-3ginfo/main/uninstall-hilink-3ginfo.sh
sh uninstall-hilink-3ginfo.sh
```

它会移除面板、4IceG 软件源及其密钥、`LTE_Huawei_3372` 接口及其防火墙规则，以及 3ginfo 配置，然后询问是否重启。

**特意保留**（属于系统级组件，移除它们可能导致路由器或其他外设无法工作）：USB 驱动 `kmod-usb-*`、`usbutils`、`usb-modeswitch`，以及 `wget-ssl` 和 `sms-tool`。脚本会提示这一点；如需移除，请仅手动且谨慎地进行。

## 手动配置接口

脚本可以全自动完成，但如果你跳过了自动配置，可手动创建调制解调器接口：

```sh
# 在以下命令的输出中找到调制解调器接口（通常为 eth2）：  ip a  /  logread | grep cdc_ether
uci set network.LTE_Huawei_3372=interface
uci set network.LTE_Huawei_3372.proto='dhcp'
uci set network.LTE_Huawei_3372.device='eth2'      # 替换为你自己的
uci commit network

# 加入 wan 防火墙区域（用以下命令确认区域索引：uci show firewall | grep name=\'wan\'）
uci add_list firewall.@zone[1].network='LTE_Huawei_3372'
uci commit firewall

/etc/init.d/network restart
/etc/init.d/firewall restart
```

然后在面板（**3ginfo-lite → 配置**）中选择 Interface `LTE_Huawei_3372`；调制解调器地址 `192.168.8.1` 已由脚本设置好。

## HiLink 已知限制

这些是 HiLink 模式本身的特性，而非脚本问题——无法通过配置解决：

- **无法进行频段锁定（modemband）和从 LuCI 收发短信。** HiLink 没有串行 AT 端口，而这两项功能都依赖 AT 指令。短信仍可通过调制解调器的 Web 界面 `http://192.168.8.1` 使用。
- **TAC / 频段 / EARFCN 字段可能为空**——E3372 的 API 不提供这些数据。
- **“运营商网络注册问题”提示为误报。** 面板尝试用 AT 指令（`AT+CREG?`）读取注册状态，而 HiLink 没有该端口，字段保持为空——因此出现该警告。它不影响实际运行：只要能识别运营商且有流量，注册就是正常的。点击 Dismiss 即可。

## 故障排查

```sh
wget --version | head -1                    # 必须是 "GNU Wget ..."（而非 BusyBox）
lsusb                                        # 应列出 Huawei ... 12d1:14dc
ip route                                     # 默认路由经由 192.168.8.1 dev <调制解调器接口>
ifstatus LTE_Huawei_3372 | grep l3_device    # 调制解调器接口
```

如果面板为空，而 `wget --version` 显示为 BusyBox——请安装 `wget-ssl` 并检查 `/usr/bin/wget` 的 alternatives 软链接。这是最常见的原因。

> **提示：** 系统大版本升级后，请检查 `wget --version`。若 apk 将 `/usr/bin/wget` 切回 BusyBox，面板会变空——原因相同。

## 致谢

本项目只是一个安装器。所有繁重的工作都由 **[4IceG](https://github.com/4IceG)** 的项目完成：

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) —— 调制解调器监控面板
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) —— LTE 频段管理（用于串行模式调制解调器）
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) —— apk 软件包仓库

所安装的组件归其各自作者所有，并按其各自的许可证分发。本许可证（MIT）仅涵盖本脚本的代码。

## 许可证

[MIT](LICENSE) © 2026 lastik997
