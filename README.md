# openwrt-huawei-e3372

**Русский** · [English](README.en.md) · [中文](README.zh-CN.md)

Установочный скрипт для мониторинга USB-модема **Huawei E3372 (HiLink)** на **OpenWrt 25 (apk)** через панель [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite).

Один прогон на чистой системе: ставит драйверы, зависимости, подключает репозиторий 4IceG, устанавливает панель и (по желанию) сам создаёт сетевой интерфейс модема.

## Зачем

Huawei E3372 в режиме HiLink выступает как USB-сетевая карта: он сам делает NAT и висит на `192.168.8.1` со своей веб-мордой. Панель 3ginfo снимает с него показания (оператор, LTE, RSSI/RSRP/SINR/RSRQ и т.д.) не AT-командами, а запросами к API модема по HTTP. Для этого нужен строго определённый набор пакетов — скрипт его и разворачивает, попутно обходя типичные грабли.

## Требования

- OpenWrt 25.x с пакетным менеджером **apk** (для сборок на opkg скрипт не предназначен).
- Доступ в интернет на роутере на момент запуска (через модем или другой аплинк) — качаются пакеты и ключ репозитория.
- Модем Huawei E3372 в режиме HiLink (USB VID `12d1`), воткнутый и определившийся в системе.

## Что делает скрипт

1. Ставит USB- и сетевые драйверы: `usbutils`, `usb-modeswitch`, `kmod-usb-*`, `kmod-usb-net-cdc-ether`, `kmod-usb-net-rndis`.
2. Ставит **GNU wget (`wget-ssl`)** и `sms-tool`.
3. Проверяет, что `/usr/bin/wget` — именно GNU-версия, а не BusyBox (при необходимости чинит alternative-симлинк).
4. Подключает apk-репозиторий [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) и его ключ.
5. Ставит `luci-app-3ginfo-lite`, спрашивает (`y/n`) про установку русской локали панели и прописывает адрес модема `192.168.8.1` в конфиг панели.
6. *(Опционально, с подтверждением)* находит сетевой интерфейс модема по USB VID `12d1`, создаёт `interface LTE_Huawei_3372` (proto dhcp), добавляет его в firewall-зону `wan` и привязывает к панели.
7. *(Опционально, с подтверждением)* перезагружает роутер.

Оба опциональных шага спрашивают подтверждение — молча network/firewall и reboot не трогаются.

## Установка

Команды выполняются **на роутере** (по SSH), а не на компьютере:

```sh
wget -O setup-e3372-3ginfo.sh https://raw.githubusercontent.com/lastik9/openwrt-huawei-e3372/main/setup-e3372-3ginfo.sh
sh setup-e3372-3ginfo.sh
```

Запуск показывает меню — выбери **`1) Установить`**. Пустой ввод (просто Enter),
`0` или `q` закрывают меню, ничего не устанавливая. Можно и без меню, сразу
установкой: `sh setup-e3372-3ginfo.sh install`.

После установки открой в LuCI **Modem → 3ginfo-lite** и обнови вкладку Modem(s) (Ctrl+F5) — данные должны подтянуться.

## Удаление

Убрать всё, что поставил скрипт, можно аптинсталлером. На роутере:

```sh
wget -O uninstall-e3372-3ginfo.sh https://raw.githubusercontent.com/lastik9/openwrt-huawei-e3372/main/uninstall-e3372-3ginfo.sh
sh uninstall-e3372-3ginfo.sh
```

То же удаление доступно из меню установщика (пункт **`2) Удалить`**) или командой
`sh setup-e3372-3ginfo.sh uninstall` — отдельный файл качать не обязательно.

Он удалит панель, репозиторий 4IceG с ключом, интерфейс `LTE_Huawei_3372` с правилом firewall и конфиг 3ginfo, затем предложит перезагрузку.

**Намеренно оставляются** (общесистемные, их удаление может сломать роутер или другую USB-периферию): драйверы `kmod-usb-*`, `usbutils`, `usb-modeswitch`, а также `wget-ssl` и `sms-tool`. Скрипт об этом сообщает; убирать их стоит только вручную и осознанно.

## Если настраиваешь интерфейс вручную

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

## Известные ограничения HiLink

Это особенности режима HiLink, а не скрипта — настройкой не лечатся:

- **Блокировка бэндов (modemband) и SMS из LuCI не работают.** У HiLink нет последовательного AT-порта, а обе функции работают через AT-команды. SMS остаются доступны через веб-морду модема на `http://192.168.8.1`.
- **Поля TAC / band / EARFCN могут быть пустыми** — эти данные API конкретно E3372 не отдаёт.
- **Плашка «Проблема с регистрацией в сети оператора» — ложная.** Панель пытается прочитать статус регистрации AT-командой (`AT+CREG?`), которой у HiLink нет, поле остаётся пустым — отсюда предупреждение. На реальную работу не влияет: если оператор определён и идёт трафик, регистрация в порядке. Жми Dismiss.

## Болячки и как лечить

- **Панель не установилась, `apk update` ругается `error 8` / `unexpected end of file` / `UNTRUSTED signature`** — почти всегда виноват **HTTP-прокси на роутере** (Clash / ssclash на `127.0.0.1:7890`): он ломает редиректы GitHub (`HTTP error 400`). Лечение:
  ```sh
  /etc/init.d/clash stop
  sh setup-e3372-3ginfo.sh install
  /etc/init.d/clash start
  ```
  Если строка фида залипла и ломает `apk update`, убери её вручную:
  ```sh
  sed -i '\#Modem-extras-apk#d' /etc/apk/repositories.d/customfeeds.list && apk update
  ```
  (Начиная с этой версии скрипт откатывает строку фида сам, но на старых установках она могла остаться.)
- **`wget` сохранил файл как `index.html`** — за прокси busybox-`wget` теряет имя из URL. Качай с явным именем: `wget -O <имя> <URL>`.

## Диагностика

```sh
wget --version | head -1                    # должно быть "GNU Wget ..." (не BusyBox)
lsusb                                        # должна быть строка Huawei ... 12d1:14dc
ip route                                     # default через 192.168.8.1 dev <iface модема>
ifstatus LTE_Huawei_3372 | grep l3_device    # интерфейс модема
```

Если панель пустая, а `wget --version` показывает BusyBox — доставь `wget-ssl` и проверь alternative-симлинк `/usr/bin/wget`. Это самая частая причина.

> **На заметку:** после крупных апгрейдов системы проверяй `wget --version`. Если apk вернёт `/usr/bin/wget` на BusyBox, панель опустеет — причина будет та же.

## Благодарности

Проект — лишь установщик. Вся тяжёлая работа сделана в проектах **[4IceG](https://github.com/4IceG)**:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — панель мониторинга модема
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — управление LTE-диапазонами (для serial-модемов)
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk-репозиторий пакетов

Устанавливаемые компоненты являются собственностью их авторов и распространяются под их собственными лицензиями. Настоящая лицензия (MIT) покрывает только код этого скрипта.

## Лицензия

[MIT](LICENSE) © 2026 lastik9
