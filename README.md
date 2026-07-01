# openwrt-hilink-3ginfo

Установочный скрипт для мониторинга **Huawei E3372 (HiLink)** на **OpenWrt 25 (apk)** через панель [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite).

**Выберите язык · Choose language · 选择语言:** разверните нужный блок ниже.

<details open>
<summary><b>🇷🇺 Русский</b></summary>

<br>

Установочный скрипт для мониторинга USB-модема **Huawei E3372 (HiLink)** на **OpenWrt 25 (apk)** через панель [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite).

Один прогон на чистой системе: ставит драйверы, зависимости, подключает репозиторий 4IceG, устанавливает панель и (по желанию) сам создаёт сетевой интерфейс модема.

### Зачем

Huawei E3372 в режиме HiLink выступает как USB-сетевая карта: он сам делает NAT и висит на `192.168.8.1` со своей веб-мордой. Панель 3ginfo снимает с него показания (оператор, LTE, RSSI/RSRP/SINR/RSRQ и т.д.) не AT-командами, а запросами к API модема по HTTP. Для этого нужен строго определённый набор пакетов — скрипт его и разворачивает, попутно обходя типичные грабли.

### Требования

- OpenWrt 25.x с пакетным менеджером **apk** (для сборок на opkg скрипт не предназначен).
- Доступ в интернет на роутере на момент запуска (через модем или другой аплинк) — качаются пакеты и ключ репозитория.
- Модем Huawei E3372 в режиме HiLink (USB VID `12d1`), воткнутый и определившийся в системе.

### Что делает скрипт

1. Ставит USB- и сетевые драйверы: `usbutils`, `usb-modeswitch`, `kmod-usb-*`, `kmod-usb-net-cdc-ether`, `kmod-usb-net-rndis`.
2. Ставит **GNU wget (`wget-ssl`)** и `sms-tool`.
3. Проверяет, что `/usr/bin/wget` — именно GNU-версия, а не BusyBox (при необходимости чинит alternative-симлинк).
4. Подключает apk-репозиторий [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) и его ключ.
5. Ставит `luci-app-3ginfo-lite`, спрашивает (`y/n`) про установку русской локали панели и прописывает адрес модема `192.168.8.1` в конфиг панели.
6. *(Опционально, с подтверждением)* находит сетевой интерфейс модема по USB VID `12d1`, создаёт `interface LTE_Huawei_3372` (proto dhcp), добавляет его в firewall-зону `wan` и привязывает к панели.
7. *(Опционально, с подтверждением)* перезагружает роутер.

Оба опциональных шага спрашивают подтверждение — молча network/firewall и reboot не трогаются.

### Установка

Команды выполняются **на роутере** (по SSH), а не на компьютере:

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-hilink-3ginfo/main/setup-hilink-3ginfo.sh
sh setup-hilink-3ginfo.sh
```

После установки открой в LuCI **Modem → 3ginfo-lite** и обнови вкладку Modem(s) (Ctrl+F5) — данные должны подтянуться.

### Удаление

Убрать всё, что поставил скрипт, можно аптинсталлером. На роутере:

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-hilink-3ginfo/main/uninstall-hilink-3ginfo.sh
sh uninstall-hilink-3ginfo.sh
```

Он удалит панель, репозиторий 4IceG с ключом, интерфейс `LTE_Huawei_3372` с правилом firewall и конфиг 3ginfo, затем предложит перезагрузку.

**Намеренно оставляются** (общесистемные, их удаление может сломать роутер или другую USB-периферию): драйверы `kmod-usb-*`, `usbutils`, `usb-modeswitch`, а также `wget-ssl` и `sms-tool`. Скрипт об этом сообщает; убирать их стоит только вручную и осознанно.

### Если настраиваешь интерфейс вручную

Скрипт умеет всё сам, но если ты пропустил автонастройку — создай интерфейс модема руками:

```sh
# найди интерфейс модема (обычно eth2) в выводе:  ip a  /  logread | grep cdc_ether
uci set network.LTE_Huawei_3372=interface
uci set network.LTE_Huawei_3372.proto='dhcp'
uci set network.LTE_Huawei_3372.device='eth2'      # подставь свой
uci commit network

# добавь в firewall-зону wan (индекс зоны уточни: uci show firewall | grep name=\'wan\')
uci add_list firewall.@zone[1].network='LTE_Huawei_3372'
uci commit firewall

/etc/init.d/network restart
/etc/init.d/firewall restart
```

Затем в панели (**3ginfo-lite → Конфигурация**) выбери Interface `LTE_Huawei_3372`, адрес модема `192.168.8.1` уже проставлен скриптом.

### Известные ограничения HiLink

Это особенности режима HiLink, а не скрипта — настройкой не лечатся:

- **Блокировка бэндов (modemband) и SMS из LuCI не работают.** У HiLink нет последовательного AT-порта, а обе функции работают через AT-команды. SMS остаются доступны через веб-морду модема на `http://192.168.8.1`.
- **Поля TAC / band / EARFCN могут быть пустыми** — эти данные API конкретно E3372 не отдаёт.
- **Плашка «Проблема с регистрацией в сети оператора» — ложная.** Панель пытается прочитать статус регистрации AT-командой (`AT+CREG?`), которой у HiLink нет, поле остаётся пустым — отсюда предупреждение. На реальную работу не влияет: если оператор определён и идёт трафик, регистрация в порядке. Жми Dismiss.

### Диагностика

```sh
wget --version | head -1                    # должно быть "GNU Wget ..." (не BusyBox)
lsusb                                        # должна быть строка Huawei ... 12d1:14dc
ip route                                     # default через 192.168.8.1 dev <iface модема>
ifstatus LTE_Huawei_3372 | grep l3_device    # интерфейс модема
```

Если панель пустая, а `wget --version` показывает BusyBox — доставь `wget-ssl` и проверь alternative-симлинк `/usr/bin/wget`. Это самая частая причина.

> **На заметку:** после крупных апгрейдов системы проверяй `wget --version`. Если apk вернёт `/usr/bin/wget` на BusyBox, панель опустеет — причина будет та же.

### Благодарности

Проект — лишь установщик. Вся тяжёлая работа сделана в проектах **[4IceG](https://github.com/4IceG)**:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — панель мониторинга модема
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — управление LTE-диапазонами (для serial-модемов)
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk-репозиторий пакетов

Устанавливаемые компоненты являются собственностью их авторов и распространяются под их собственными лицензиями. Настоящая лицензия (MIT) покрывает только код этого скрипта.

### Лицензия

[MIT](LICENSE) © 2026 lastik997

</details>

<details>
<summary><b>🇬🇧 English</b></summary>

<br>

Installer script that sets up monitoring of a **Huawei E3372 (HiLink)** USB modem on **OpenWrt 25 (apk)** via the [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) panel.

A single run on a clean system installs the drivers and dependencies, adds the 4IceG repository, installs the panel, and (optionally) sets up the modem's network interface for you.

### Why

In HiLink mode the Huawei E3372 acts as a USB network card: it does NAT on its own and exposes its web UI at `192.168.8.1`. The 3ginfo panel reads its data (operator, LTE, RSSI/RSRP/SINR/RSRQ, etc.) not through AT commands but via HTTP requests to the modem's API. This needs a specific set of packages — the script deploys them and works around the common pitfalls.

### Requirements

- OpenWrt 25.x with the **apk** package manager (the script is not intended for opkg-based builds).
- Internet access on the router at runtime (via the modem or another uplink) — packages and the repository key are downloaded.
- A Huawei E3372 in HiLink mode (USB VID `12d1`), plugged in and detected by the system.

### What the script does

1. Installs USB and network drivers: `usbutils`, `usb-modeswitch`, `kmod-usb-*`, `kmod-usb-net-cdc-ether`, `kmod-usb-net-rndis`.
2. Installs **GNU wget (`wget-ssl`)** and `sms-tool`.
3. Verifies that `/usr/bin/wget` is the GNU build and not BusyBox (fixes the alternatives symlink if needed).
4. Adds the [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) apk repository and its signing key.
5. Installs `luci-app-3ginfo-lite`, asks (`y/n`) whether to install the panel's Russian locale, and writes the modem address `192.168.8.1` into the panel config.
6. *(Optional, with confirmation)* finds the modem's network interface by USB VID `12d1`, creates `interface LTE_Huawei_3372` (proto dhcp), adds it to the `wan` firewall zone and binds it to the panel.
7. *(Optional, with confirmation)* reboots the router.

Both optional steps ask for confirmation — network/firewall and reboot are never touched silently.

### Installation

Run the commands **on the router** (over SSH), not on your computer:

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-hilink-3ginfo/main/setup-hilink-3ginfo.sh
sh setup-hilink-3ginfo.sh
```

After installation open **Modem → 3ginfo-lite** in LuCI and refresh the Modem(s) tab (Ctrl+F5) — the data should populate.

### Uninstall

To remove everything the script installed, use the uninstaller. On the router:

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-hilink-3ginfo/main/uninstall-hilink-3ginfo.sh
sh uninstall-hilink-3ginfo.sh
```

It removes the panel, the 4IceG repository and its key, the `LTE_Huawei_3372` interface with its firewall rule, and the 3ginfo config, then offers a reboot.

**Kept on purpose** (system-wide; removing them may break the router or other peripherals): the USB drivers `kmod-usb-*`, `usbutils`, `usb-modeswitch`, plus `wget-ssl` and `sms-tool`. The script reports this; remove them only manually and deliberately.

### Setting up the interface manually

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

### Known HiLink limitations

These are properties of HiLink mode, not the script — they can't be fixed by configuration:

- **Band locking (modemband) and SMS from LuCI don't work.** HiLink has no serial AT port, and both features rely on AT commands. SMS remain available through the modem's web UI at `http://192.168.8.1`.
- **TAC / band / EARFCN fields may be empty** — this specific data isn't exposed by the E3372 API.
- **The "operator registration problem" banner is a false positive.** The panel tries to read registration status via an AT command (`AT+CREG?`) that HiLink doesn't have, so the field stays empty — hence the warning. It doesn't affect actual operation: if the operator is detected and traffic flows, registration is fine. Just click Dismiss.

### Troubleshooting

```sh
wget --version | head -1                    # must be "GNU Wget ..." (not BusyBox)
lsusb                                        # should list Huawei ... 12d1:14dc
ip route                                     # default via 192.168.8.1 dev <modem iface>
ifstatus LTE_Huawei_3372 | grep l3_device    # modem interface
```

If the panel is empty and `wget --version` shows BusyBox — install `wget-ssl` and check the `/usr/bin/wget` alternatives symlink. This is the most common cause.

> **Note:** after major system upgrades, check `wget --version`. If apk switches `/usr/bin/wget` back to BusyBox, the panel will go blank — same cause.

### Credits

This project is just an installer. All the heavy lifting is done in the **[4IceG](https://github.com/4IceG)** projects:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — modem monitoring panel
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — LTE band management (for serial modems)
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk package repository

The installed components are the property of their authors and are distributed under their own licenses. This license (MIT) covers only the code of this script.

### License

[MIT](LICENSE) © 2026 lastik997

</details>

<details>
<summary><b>🇨🇳 中文</b></summary>

<br>

用于在 **OpenWrt 25（apk）** 上通过 [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) 面板监控 **华为 E3372（HiLink）** USB 调制解调器的安装脚本。

在干净的系统上运行一次即可：安装驱动和依赖、添加 4IceG 软件源、安装面板，并（可选）自动为你配置调制解调器的网络接口。

### 为什么需要它

在 HiLink 模式下，华为 E3372 表现为一块 USB 网卡：它自身完成 NAT，并在 `192.168.8.1` 上提供 Web 管理界面。3ginfo 面板读取其数据（运营商、LTE、RSSI/RSRP/SINR/RSRQ 等）不是通过 AT 指令，而是通过 HTTP 请求访问调制解调器的 API。这需要一组特定的软件包——本脚本负责部署它们，并规避常见的坑。

### 环境要求

- 使用 **apk** 包管理器的 OpenWrt 25.x（本脚本不适用于基于 opkg 的固件）。
- 运行时路由器需可访问互联网（通过调制解调器或其他上行链路）——需下载软件包和软件源密钥。
- 处于 HiLink 模式（USB VID `12d1`）、已插入并被系统识别的华为 E3372。

### 脚本做了什么

1. 安装 USB 与网络驱动：`usbutils`、`usb-modeswitch`、`kmod-usb-*`、`kmod-usb-net-cdc-ether`、`kmod-usb-net-rndis`。
2. 安装 **GNU wget（`wget-ssl`）** 和 `sms-tool`。
3. 校验 `/usr/bin/wget` 确为 GNU 版本而非 BusyBox（必要时修复 alternatives 软链接）。
4. 添加 [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) apk 软件源及其签名密钥。
5. 安装 `luci-app-3ginfo-lite`，询问（`y/n`）是否安装面板的俄语语言包，并将调制解调器地址 `192.168.8.1` 写入面板配置。
6. *（可选，需确认）* 通过 USB VID `12d1` 找到调制解调器的网络接口，创建 `interface LTE_Huawei_3372`（proto dhcp），将其加入 `wan` 防火墙区域并绑定到面板。
7. *（可选，需确认）* 重启路由器。

两个可选步骤都会请求确认——不会在无提示的情况下改动 network/firewall 或执行重启。

### 安装

命令需在**路由器上**（通过 SSH）执行，而不是在你的电脑上：

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-hilink-3ginfo/main/setup-hilink-3ginfo.sh
sh setup-hilink-3ginfo.sh
```

安装完成后，在 LuCI 中打开 **Modem → 3ginfo-lite** 并刷新 Modem(s) 标签页（Ctrl+F5）——数据应会显示出来。

### 卸载

要移除脚本安装的所有内容，请使用卸载脚本。在路由器上：

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-hilink-3ginfo/main/uninstall-hilink-3ginfo.sh
sh uninstall-hilink-3ginfo.sh
```

它会移除面板、4IceG 软件源及其密钥、`LTE_Huawei_3372` 接口及其防火墙规则，以及 3ginfo 配置，然后询问是否重启。

**特意保留**（属于系统级组件，移除它们可能导致路由器或其他外设无法工作）：USB 驱动 `kmod-usb-*`、`usbutils`、`usb-modeswitch`，以及 `wget-ssl` 和 `sms-tool`。脚本会提示这一点；如需移除，请仅手动且谨慎地进行。

### 手动配置接口

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

### HiLink 已知限制

这些是 HiLink 模式本身的特性，而非脚本问题——无法通过配置解决：

- **无法进行频段锁定（modemband）和从 LuCI 收发短信。** HiLink 没有串行 AT 端口，而这两项功能都依赖 AT 指令。短信仍可通过调制解调器的 Web 界面 `http://192.168.8.1` 使用。
- **TAC / 频段 / EARFCN 字段可能为空**——E3372 的 API 不提供这些数据。
- **“运营商网络注册问题”提示为误报。** 面板尝试用 AT 指令（`AT+CREG?`）读取注册状态，而 HiLink 没有该端口，字段保持为空——因此出现该警告。它不影响实际运行：只要能识别运营商且有流量，注册就是正常的。点击 Dismiss 即可。

### 故障排查

```sh
wget --version | head -1                    # 必须是 "GNU Wget ..."（而非 BusyBox）
lsusb                                        # 应列出 Huawei ... 12d1:14dc
ip route                                     # 默认路由经由 192.168.8.1 dev <调制解调器接口>
ifstatus LTE_Huawei_3372 | grep l3_device    # 调制解调器接口
```

如果面板为空，而 `wget --version` 显示为 BusyBox——请安装 `wget-ssl` 并检查 `/usr/bin/wget` 的 alternatives 软链接。这是最常见的原因。

> **提示：** 系统大版本升级后，请检查 `wget --version`。若 apk 将 `/usr/bin/wget` 切回 BusyBox，面板会变空——原因相同。

### 致谢

本项目只是一个安装器。所有繁重的工作都由 **[4IceG](https://github.com/4IceG)** 的项目完成：

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) —— 调制解调器监控面板
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) —— LTE 频段管理（用于串行模式调制解调器）
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) —— apk 软件包仓库

所安装的组件归其各自作者所有，并按其各自的许可证分发。本许可证（MIT）仅涵盖本脚本的代码。

### 许可证

[MIT](LICENSE) © 2026 lastik997

</details>
