# openwrt-huawei-e3372

[Русский](README.md) · **English** · [中文](README.zh-CN.md)

Installer script that sets up monitoring of a **Huawei E3372 (HiLink)** USB modem on **OpenWrt 25 (apk)** via the [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) panel.

A single run on a clean system installs the drivers and dependencies, adds the 4IceG repository, installs the panel, and (optionally) sets up the modem's network interface for you.

## Why

In HiLink mode the Huawei E3372 acts as a USB network card: it does NAT on its own and exposes its web UI at `192.168.8.1`. The 3ginfo panel reads its data (operator, LTE, RSSI/RSRP/SINR/RSRQ, etc.) not through AT commands but via HTTP requests to the modem's API. This needs a specific set of packages — the script deploys them and works around the common pitfalls.

## Requirements

- OpenWrt 25.x with the **apk** package manager (the script is not intended for opkg-based builds).
- Internet access on the router at runtime (via the modem or another uplink) — packages and the repository key are downloaded.
- A Huawei E3372 in HiLink mode (USB VID `12d1`), plugged in and detected by the system.

## What the script does

1. Installs USB and network drivers: `usbutils`, `usb-modeswitch`, `kmod-usb-*`, `kmod-usb-net-cdc-ether`, `kmod-usb-net-rndis`.
2. Installs **GNU wget (`wget-ssl`)** and `sms-tool`.
3. Verifies that `/usr/bin/wget` is the GNU build and not BusyBox (fixes the alternatives symlink if needed).
4. Adds the [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) apk repository and its signing key.
5. Installs `luci-app-3ginfo-lite`, asks (`y/n`) whether to install the panel's Russian locale, and writes the modem address `192.168.8.1` into the panel config.
6. *(Optional, with confirmation)* finds the modem's network interface by USB VID `12d1`, creates `interface LTE_Huawei_3372` (proto dhcp), adds it to the `wan` firewall zone and binds it to the panel.
7. *(Optional, with confirmation)* reboots the router.

Both optional steps ask for confirmation — network/firewall and reboot are never touched silently.

## Installation

Run the commands **on the router** (over SSH), not on your computer:

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-huawei-e3372/main/setup-e3372-3ginfo.sh
sh setup-e3372-3ginfo.sh
```

After installation open **Modem → 3ginfo-lite** in LuCI and refresh the Modem(s) tab (Ctrl+F5) — the data should populate.

## Uninstall

To remove everything the script installed, use the uninstaller. On the router:

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-huawei-e3372/main/uninstall-e3372-3ginfo.sh
sh uninstall-e3372-3ginfo.sh
```

It removes the panel, the 4IceG repository and its key, the `LTE_Huawei_3372` interface with its firewall rule, and the 3ginfo config, then offers a reboot.

**Kept on purpose** (system-wide; removing them may break the router or other peripherals): the USB drivers `kmod-usb-*`, `usbutils`, `usb-modeswitch`, plus `wget-ssl` and `sms-tool`. The script reports this; remove them only manually and deliberately.

## Setting up the interface manually

The script can do it all, but if you skipped the auto-setup, create the modem interface by hand:

```sh
# find the modem interface (usually eth2) in the output of:  ip a  /  logread | grep cdc_ether
uci set network.LTE_Huawei_3372=interface
uci set network.LTE_Huawei_3372.proto='dhcp'
uci set network.LTE_Huawei_3372.device='eth2'      # use your own
uci commit network

# add it to the wan firewall zone (check the zone index: uci show firewall | grep name=\'wan\')
uci add_list firewall.@zone[1].network='LTE_Huawei_3372'
uci commit firewall

/etc/init.d/network restart
/etc/init.d/firewall restart
```

Then in the panel (**3ginfo-lite → Configuration**) select Interface `LTE_Huawei_3372`; the modem address `192.168.8.1` is already set by the script.

## Known HiLink limitations

These are properties of HiLink mode, not the script — they can't be fixed by configuration:

- **Band locking (modemband) and SMS from LuCI don't work.** HiLink has no serial AT port, and both features rely on AT commands. SMS remain available through the modem's web UI at `http://192.168.8.1`.
- **TAC / band / EARFCN fields may be empty** — this specific data isn't exposed by the E3372 API.
- **The "operator registration problem" banner is a false positive.** The panel tries to read registration status via an AT command (`AT+CREG?`) that HiLink doesn't have, so the field stays empty — hence the warning. It doesn't affect actual operation: if the operator is detected and traffic flows, registration is fine. Just click Dismiss.

## Troubleshooting

```sh
wget --version | head -1                    # must be "GNU Wget ..." (not BusyBox)
lsusb                                        # should list Huawei ... 12d1:14dc
ip route                                     # default via 192.168.8.1 dev <modem iface>
ifstatus LTE_Huawei_3372 | grep l3_device    # modem interface
```

If the panel is empty and `wget --version` shows BusyBox — install `wget-ssl` and check the `/usr/bin/wget` alternatives symlink. This is the most common cause.

> **Note:** after major system upgrades, check `wget --version`. If apk switches `/usr/bin/wget` back to BusyBox, the panel will go blank — same cause.

## Credits

This project is just an installer. All the heavy lifting is done in the **[4IceG](https://github.com/4IceG)** projects:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — modem monitoring panel
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — LTE band management (for serial modems)
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk package repository

The installed components are the property of their authors and are distributed under their own licenses. This license (MIT) covers only the code of this script.

## License

[MIT](LICENSE) © 2026 lastik9
