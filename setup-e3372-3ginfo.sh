#!/bin/sh
#
# setup-e3372-3ginfo.sh
# Установка мониторинга Huawei E3372 (HiLink) + панели luci-app-3ginfo-lite
# на чистой OpenWrt 25 (пакетный менеджер apk).
#
# Что делает:
#   - ставит USB/сетевые драйверы для HiLink;
#   - ставит GNU wget (ssl) — обязателен для чтения API модема панелью;
#   - подключает apk-репозиторий 4IceG и ставит luci-app-3ginfo-lite;
#   - предлагает (y/n) установить русскую локаль панели;
#   - прописывает адрес модема 192.168.8.1 в конфиг 3ginfo;
#   - (опционально, с подтверждением) создаёт interface LTE_Huawei_3372 (dhcp),
#     добавляет его в firewall-зону wan и привязывает к панели;
#   - (опционально, с подтверждением) перезагружает роутер.
#
# Для работы скрипта роутеру нужен доступ в интернет (через модем или другой аплинк),
# т.к. пакеты и ключ репозитория качаются из сети.
#
# Запуск:  sh setup-e3372-3ginfo.sh
#

IFACE="LTE_Huawei_3372"     # имя сетевого интерфейса модема
# Прямые ссылки на raw.githubusercontent.com — намеренно: форма
# github.com/.../raw/... отдаёт редирект (302), а HTTP-прокси на роутере
# (Clash / ssclash на 127.0.0.1:7890) его ломают -> "HTTP error 400" и
# "unexpected end of file" при apk update. Прямой raw-URL редиректа не даёт.
REPO_URL="https://raw.githubusercontent.com/4IceG/Modem-extras-apk/main/myapk/packages.adb"
KEY_URL="https://raw.githubusercontent.com/4IceG/Modem-extras-apk/main/myapk/IceG-apkpub.pem"
KEY_DST="/etc/apk/keys/IceG-apkpub.pem"
FEEDS="/etc/apk/repositories.d/customfeeds.list"
REPO_MATCH="Modem-extras-apk"   # по этой подстроке ищем/убираем строку фида

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
# ПОРЯДОК ВАЖЕН: сначала кладём валидный ключ, и только потом добавляем строку
# фида. Иначе при неудаче с ключом строка фида остаётся в customfeeds.list и
# ЛЮБОЙ последующий apk update на роутере падает ("1 unavailable") — причём
# причина совершенно неочевидна.

# Непустой файл НЕ доказывает, что ключ правильный: может лежать чужой ключ
# (валидный PEM -> "UNTRUSTED signature"), а за прокси вместо ключа нередко
# прилетает HTML-заглушка. Поэтому проверяем PEM-заголовок.
key_ok() { [ -s "$1" ] && head -n1 "$1" | grep -q 'BEGIN PUBLIC KEY'; }

if key_ok "$KEY_DST"; then
  echo "Ключ 4IceG уже установлен: $KEY_DST"
else
  rm -f "$KEY_DST"
  if wget -q -O "$KEY_DST" "$KEY_URL" && key_ok "$KEY_DST"; then
    echo "Ключ 4IceG установлен: $KEY_DST"
  else
    rm -f "$KEY_DST"
    echo "!! Не удалось скачать валидный ключ 4IceG — панель будет пропущена."
    echo "!! Если на роутере HTTP-прокси (Clash/ssclash), попробуй:"
    echo "!!   /etc/init.d/clash stop  ->  перезапусти этот скрипт  ->  /etc/init.d/clash start"
  fi
fi

# ICEG_OK=1 только если фид реально работает; иначе строку фида не оставляем.
ICEG_OK=0
if [ -s "$KEY_DST" ]; then
  grep -qF "$REPO_URL" "$FEEDS" 2>/dev/null || echo "$REPO_URL" >> "$FEEDS"
  if apk update; then
    ICEG_OK=1
  else
    echo "!! apk update упал с фидом 4IceG — убираю строку обратно, чтобы не сломать apk."
    grep -v "$REPO_MATCH" "$FEEDS" > "${FEEDS}.tmp" 2>/dev/null && mv "${FEEDS}.tmp" "$FEEDS"
    apk update || true
  fi
else
  # ключа нет -> ни в коем случае не оставляем строку фида
  if [ -f "$FEEDS" ] && grep -q "$REPO_MATCH" "$FEEDS" 2>/dev/null; then
    grep -v "$REPO_MATCH" "$FEEDS" > "${FEEDS}.tmp" && mv "${FEEDS}.tmp" "$FEEDS"
    echo "Строка фида 4IceG убрана из $FEEDS (ключа нет)."
  fi
  apk update || true
fi

# --- 5. Установка панели ----------------------------------------------------
say "Шаг 5/5: установка luci-app-3ginfo-lite"

PANEL_OK=0
if [ "$ICEG_OK" = "1" ] && apk add luci-app-3ginfo-lite; then
  PANEL_OK=1
  echo "Панель установлена."

  # Русская локаль панели — по желанию.
  printf "Установить русский язык для панели 4IceG? [y/N]: "
  read ru_locale
  case "$ru_locale" in
    y|Y|yes|YES)
      if apk add luci-i18n-3ginfo-lite-ru; then
        echo "Русская локаль установлена."
      else
        echo "Не удалось поставить локаль (не критично, интерфейс останется на английском)."
      fi
      ;;
    *)
      echo "Русская локаль пропущена — интерфейс панели останется на английском."
      ;;
  esac
else
  # Не die: панель — не единственная цель. Модем и интерфейс настроим всё равно.
  echo "!! Панель luci-app-3ginfo-lite НЕ установлена (фид 4IceG недоступен)."
  echo "!! Модем и сетевой интерфейс при этом настроятся — интернет работать будет,"
  echo "!! не будет только веб-панели мониторинга."
  echo "!! Чаще всего причина — HTTP-прокси на роутере (Clash/ssclash на :7890)."
  echo "!! Лечение: /etc/init.d/clash stop -> перезапустить скрипт -> /etc/init.d/clash start"
fi

# Адрес модема для HiLink всегда 192.168.8.1 — прописываем сразу, безусловно.
# При желании меняется руками в LuCI: Modem -> 3ginfo-lite -> "Конфигурация".
if [ -f /etc/config/3ginfo ]; then
  uci set "3ginfo.@3ginfo[0].device=192.168.8.1"
  uci commit 3ginfo
  echo "3ginfo: адрес модема выставлен в 192.168.8.1"
fi

# --- (Опционально) Автонастройка интерфейса модема + firewall + 3ginfo ------
# Находим сетевой интерфейс модема по USB Vendor ID Huawei (12d1),
# создаём interface $IFACE (proto dhcp), кидаем в firewall-зону wan,
# привязываем к конфигу 3ginfo. Модем должен быть воткнут СЕЙЧАС.
say "Доп. шаг: автонастройка интерфейса модема (опционально)"
printf "Настроить интерфейс модема автоматически (%s / dhcp + зона wan + 3ginfo)? [y/N]: " "$IFACE"
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

      # 2. interface $IFACE (proto dhcp)
      if uci -q get "network.${IFACE}" >/dev/null; then
        echo "network.${IFACE} уже существует — обновляю device на $MIFACE."
        uci set "network.${IFACE}.device=$MIFACE"
      else
        uci set "network.${IFACE}=interface"
        uci set "network.${IFACE}.proto=dhcp"
        uci set "network.${IFACE}.device=$MIFACE"
      fi
      uci commit network

      # 3. firewall: добавить сеть $IFACE в зону wan (без дублей)
      ZONE=$(uci show firewall 2>/dev/null | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'.*/\1/p" | head -1)
      if [ -z "$ZONE" ]; then
        echo "ВНИМАНИЕ: firewall-зона wan не найдена — добавь сеть ${IFACE} в зону wan вручную."
      elif uci -q get "firewall.${ZONE}.network" | grep -qw "$IFACE"; then
        echo "Сеть ${IFACE} уже в зоне wan."
      else
        uci add_list "firewall.${ZONE}.network=${IFACE}"
        uci commit firewall
        echo "Сеть ${IFACE} добавлена в firewall-зону wan (${ZONE})."
      fi

      # 4. конфиг 3ginfo: привязать интерфейс (адрес модема уже выставлен выше)
      if [ -f /etc/config/3ginfo ]; then
        uci set "3ginfo.@3ginfo[0].network=${IFACE}"
        uci commit 3ginfo
        echo "3ginfo: интерфейс ${IFACE} привязан"
      fi

      # 5. применить
      /etc/init.d/network restart
      /etc/init.d/firewall restart
      echo "Сеть и firewall перезапущены. Интерфейс ${IFACE} поднят на $MIFACE."
    fi
    ;;
  *)
    echo "Пропускаю автонастройку — интерфейс и firewall настроишь вручную."
    ;;
esac

# --- Готово ----------------------------------------------------------------
cat <<EOF

============================================================
Установка завершена.

Если автонастройку интерфейса ты ПРОПУСТИЛ — сделай руками:
  1. Создать интерфейс модема (proto=dhcp на его eth*/usb*, обычно eth2)
     и добавить его в firewall-зону wan. Адрес роутер получит из 192.168.8.0/24.
  2. В LuCI: Modem -> 3ginfo-lite -> "Конфигурация":
        - Interface: интерфейс модема
        - IP-адрес / Порт связи: 192.168.8.1
     Save & Apply.

Если автонастройка ОТРАБОТАЛА — интерфейс ${IFACE}, зона wan и конфиг 3ginfo
уже прописаны. Останется только обновить вкладку Modem(s) (Ctrl+F5).

Проверки в консоли:
  wget --version | head -1                   # должно быть "GNU Wget ..."
  ip route                                   # default через 192.168.8.1 dev <iface модема>
  ifstatus ${IFACE} | grep l3_device         # должен показать интерфейс модема

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
