#!/bin/sh
#
# setup-hilink-3ginfo.sh
# Установка мониторинга Huawei E3372 (HiLink) + панели luci-app-3ginfo-lite
# на чистой OpenWrt 25 (пакетный менеджер apk).
#
# Что делает:
#   - ставит USB/сетевые драйверы для HiLink;
#   - ставит GNU wget (ssl) — обязателен для чтения API модема панелью;
#   - подключает apk-репозиторий 4IceG и ставит luci-app-3ginfo-lite + ru-локаль;
#   - прописывает адрес модема 192.168.8.1 в конфиг 3ginfo;
#   - (опционально, с подтверждением) создаёт interface LTE (dhcp),
#     добавляет его в firewall-зону wan и привязывает к панели;
#   - (опционально, с подтверждением) перезагружает роутер.
#
# Для работы скрипта роутеру нужен доступ в интернет (через модем или другой аплинк),
# т.к. пакеты и ключ репозитория качаются из сети.
#
# Запуск:  sh setup-hilink-3ginfo.sh
#

REPO_URL="https://github.com/4IceG/Modem-extras-apk/raw/refs/heads/main/myapk/packages.adb"
KEY_URL="https://github.com/4IceG/Modem-extras-apk/raw/refs/heads/main/myapk/IceG-apkpub.pem"
KEY_DST="/etc/apk/keys/IceG-apkpub.pem"
FEEDS="/etc/apk/repositories.d/customfeeds.list"

say() { echo ""; echo ">>> $1"; }
die() { echo ""; echo "!!! ОШИБКА: $1"; exit 1; }

# --- 0. Проверки окружения -------------------------------------------------
command -v apk >/dev/null 2>&1 || die "apk не найден. Скрипт рассчитан на OpenWrt 25 (apk), не на opkg."

# --- 1. Драйверы USB и сети для HiLink -------------------------------------
# usb-modeswitch на случай старта модема в режиме CD-ROM;
# cdc-ether и rndis — два варианта, как E3372h представляется (зависит от прошивки).
say "Шаг 1/5: установка USB- и сетевых драйверов"
apk update || die "apk update не прошёл (нет интернета на роутере?)"
apk add \
  usbutils usb-modeswitch \
  kmod-usb-core kmod-usb2 kmod-usb3 \
  kmod-usb-net \
  kmod-usb-net-cdc-ether \
  kmod-usb-net-rndis \
  || die "не удалось поставить драйверы"

# --- 2. Зависимости 3ginfo для HiLink: GNU wget + sms-tool -----------------
# КЛЮЧЕВОЙ момент: панели для HiLink нужен ИМЕННО GNU wget,
# т.к. он умеет --save-cookies/--keep-session-cookies и держит сессию модема.
# BusyBox-wget этого не умеет -> сессия не ставится -> панель пустая (ошибка 125002).
#
# Берём ИМЕННО wget-ssl (GNU wget С поддержкой https), а НЕ wget-nossl!
# wget-nossl подменяет системный /usr/bin/wget на сборку без https, и тогда
# ломается скачивание по https и у самого apk (пакеты с downloads.openwrt.org),
# и у нас (ключ репозитория с github на шаге 4). wget-ssl этой проблемы не создаёт.
say "Шаг 2/5: установка GNU wget (ssl) и sms-tool"
apk add wget-ssl sms-tool || die "не удалось поставить wget-ssl/sms-tool"

# --- 3. Проверка, что /usr/bin/wget теперь GNU, а не BusyBox ----------------
say "Шаг 3/5: проверка версии wget"
if wget --version 2>&1 | grep -q "GNU Wget"; then
  echo "OK: $(wget --version 2>&1 | head -1)"
else
  echo "ВНИМАНИЕ: /usr/bin/wget всё ещё не GNU (вероятно, alternative-симлинк не переключился)."
  echo "Текущий симлинк:"
  ls -l /usr/bin/wget 2>/dev/null
  echo "Пробую переключить вручную..."
  if [ -e /usr/libexec/wget-ssl ]; then
    ln -sf /usr/libexec/wget-ssl /usr/bin/wget
    if wget --version 2>&1 | grep -q "GNU Wget"; then
      echo "OK после ручного переключения: $(wget --version 2>&1 | head -1)"
    else
      die "wget по-прежнему не GNU. Без этого панель работать не будет — разбирайся с alternatives вручную."
    fi
  else
    die "/usr/libexec/wget-ssl не найден. Проверь, что wget-ssl реально установился."
  fi
fi

# --- 4. Подключение apk-репозитория 4IceG (Modem-extras-apk) ----------------
say "Шаг 4/5: подключение репозитория 4IceG и ключа"
mkdir -p /etc/apk/repositories.d /etc/apk/keys
# добавляем строку репозитория только если её ещё нет (без дублей)
if grep -qF "$REPO_URL" "$FEEDS" 2>/dev/null; then
  echo "Репозиторий уже прописан в $FEEDS — пропускаю."
else
  echo "$REPO_URL" >> "$FEEDS"
  echo "Добавлено в $FEEDS"
fi
wget -q -O "$KEY_DST" "$KEY_URL" || die "не удалось скачать ключ репозитория"
[ -s "$KEY_DST" ] || die "файл ключа пустой: $KEY_DST"
echo "Ключ сохранён: $KEY_DST"
apk update || die "apk update с новым репозиторием не прошёл (проверь ключ/сеть)"

# --- 5. Установка панели и русской локали ----------------------------------
say "Шаг 5/5: установка luci-app-3ginfo-lite + русская локаль"
apk add luci-app-3ginfo-lite luci-i18n-3ginfo-lite-ru || die "не удалось поставить панель"

# Адрес модема для HiLink всегда 192.168.8.1 — прописываем сразу, безусловно.
# При желании меняется руками в LuCI: Modem -> 3ginfo-lite -> "Конфигурация".
if [ -f /etc/config/3ginfo ]; then
  uci set "3ginfo.@3ginfo[0].device=192.168.8.1"
  uci commit 3ginfo
  echo "3ginfo: адрес модема выставлен в 192.168.8.1"
fi

# --- (Опционально) Автонастройка интерфейса модема + firewall + 3ginfo ------
# Находим сетевой интерфейс модема по USB Vendor ID Huawei (12d1),
# создаём interface LTE (proto dhcp), кидаем в firewall-зону wan,
# прописываем модем в конфиг 3ginfo. Модем должен быть воткнут СЕЙЧАС.
say "Доп. шаг: автонастройка интерфейса модема (опционально)"
printf "Настроить интерфейс модема автоматически (LTE/dhcp + зона wan + 3ginfo)? [y/N]: "
read setup_if
case "$setup_if" in
  y|Y|yes|YES)
    # 1. найти netdev модема по VID Huawei 12d1
    MIFACE=""
    for d in /sys/class/net/*; do
      iface=$(basename "$d")
      [ -e "$d/device" ] || continue
      dev=$(readlink -f "$d/device" 2>/dev/null)
      while [ -n "$dev" ] && [ "$dev" != "/" ]; do
        if [ -e "$dev/idVendor" ]; then
          [ "$(cat "$dev/idVendor" 2>/dev/null)" = "12d1" ] && MIFACE="$iface"
          break
        fi
        dev=$(dirname "$dev")
      done
      [ -n "$MIFACE" ] && break
    done

    if [ -z "$MIFACE" ]; then
      echo "ВНИМАНИЕ: интерфейс модема (Huawei 12d1) не найден."
      echo "Модем воткнут и определился? Проверь 'lsusb' и 'ip a'. Настрой интерфейс вручную."
    else
      echo "Найден интерфейс модема: $MIFACE"

      # 2. interface LTE (proto dhcp)
      if uci -q get network.LTE >/dev/null; then
        echo "network.LTE уже существует — обновляю device на $MIFACE."
        uci set network.LTE.device="$MIFACE"
      else
        uci set network.LTE=interface
        uci set network.LTE.proto='dhcp'
        uci set network.LTE.device="$MIFACE"
      fi
      uci commit network

      # 3. firewall: добавить сеть LTE в зону wan (без дублей)
      ZONE=$(uci show firewall 2>/dev/null | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'.*/\1/p" | head -1)
      if [ -z "$ZONE" ]; then
        echo "ВНИМАНИЕ: firewall-зона wan не найдена — добавь сеть LTE в зону wan вручную."
      elif uci -q get "firewall.${ZONE}.network" | grep -qw LTE; then
        echo "Сеть LTE уже в зоне wan."
      else
        uci add_list "firewall.${ZONE}.network=LTE"
        uci commit firewall
        echo "Сеть LTE добавлена в firewall-зону wan (${ZONE})."
      fi

      # 4. конфиг 3ginfo: привязать интерфейс LTE (адрес модема уже выставлен выше)
      if [ -f /etc/config/3ginfo ]; then
        uci set "3ginfo.@3ginfo[0].network=LTE"
        uci commit 3ginfo
        echo "3ginfo: интерфейс LTE привязан"
      fi

      # 5. применить
      /etc/init.d/network restart
      /etc/init.d/firewall restart
      echo "Сеть и firewall перезапущены. Интерфейс LTE поднят на $MIFACE."
    fi
    ;;
  *)
    echo "Пропускаю автонастройку — интерфейс и firewall настроишь вручную."
    ;;
esac

# --- Готово ----------------------------------------------------------------
cat <<'EOF'

============================================================
Установка завершена.

Если автонастройку интерфейса ты ПРОПУСТИЛ — сделай руками:
  1. Создать интерфейс модема (proto=dhcp на его eth*/usb*, обычно eth2)
     и добавить его в firewall-зону wan. Адрес роутер получит из 192.168.8.0/24.
  2. В LuCI: Modem -> 3ginfo-lite -> "Конфигурация":
        - Interface: интерфейс модема
        - IP-адрес / Порт связи: 192.168.8.1
     Save & Apply.

Если автонастройка ОТРАБОТАЛА — интерфейс LTE, зона wan и конфиг 3ginfo
уже прописаны. Останется только обновить вкладку Modem(s) (Ctrl+F5).

Проверки в консоли:
  wget --version | head -1        # должно быть "GNU Wget ..."
  ip route                        # default через 192.168.8.1 dev <iface модема>
  ifstatus LTE | grep l3_device   # должен показать интерфейс модема

Известные ограничения HiLink (не лечатся настройкой):
  - блокировка бэндов (modemband) и SMS из LuCI не работают — нет AT-порта;
    SMS остаются через веб-морду модема на http://192.168.8.1
  - поля TAC / band / EARFCN могут быть пустыми: их API E3372 не отдаёт
  - плашка "Проблема с регистрацией" — ложная (3ginfo пытается AT-командами),
    на реальные данные не влияет

На будущее: после крупных апгрейдов системы проверяй "wget --version".
Если apk вернёт /usr/bin/wget на BusyBox — панель опустеет, причина та же.
============================================================
EOF

# --- Перезагрузка (по желанию, с подтверждением) ---------------------------
# Ребут чистит состояние: kmod-ы подхватываются с нуля, модем переинициализируется.
echo ""
printf "Перезагрузить роутер сейчас? Связь по ssh оборвётся. [y/N]: "
read ans
case "$ans" in
  y|Y|yes|YES)
    echo "Перезагрузка..."
    reboot
    ;;
  *)
    echo "Перезагрузка пропущена. При желании выполни вручную: reboot"
    ;;
esac
