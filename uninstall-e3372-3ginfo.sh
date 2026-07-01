#!/bin/sh
#
# uninstall-e3372-3ginfo.sh
# Удаление того, что поставил setup-e3372-3ginfo.sh, на OpenWrt 25 (apk).
#
# УДАЛЯЕТ (то, что мы принесли специально под задачу):
#   - панель luci-app-3ginfo-lite и её русскую локаль;
#   - apk-репозиторий 4IceG и его ключ;
#   - интерфейс LTE_Huawei_3372 и его правило в firewall-зоне wan;
#   - конфиг 3ginfo (/etc/config/3ginfo).
#
# НЕ ТРОГАЕТ (общесистемная инфраструктура — нужна для работы роутера
# и других USB-устройств, удаление может что-то сломать):
#   - kmod-usb-core, kmod-usb2, kmod-usb3, kmod-usb-net,
#     kmod-usb-net-cdc-ether, kmod-usb-net-rndis, usbutils, usb-modeswitch;
#   - wget-ssl и sms-tool (могли пригодиться и для другого).
#
# Запуск:  sh uninstall-e3372-3ginfo.sh
#

IFACE="LTE_Huawei_3372"
KEY_DST="/etc/apk/keys/IceG-apkpub.pem"
FEEDS="/etc/apk/repositories.d/customfeeds.list"
REPO_MATCH="Modem-extras-apk"     # по этой подстроке ищем строку репозитория в customfeeds

say() { echo ""; echo ">>> $1"; }

command -v apk >/dev/null 2>&1 || { echo "apk не найден — это не OpenWrt 25 (apk)."; exit 1; }

# --- Предупреждение и подтверждение ----------------------------------------
cat <<EOF
============================================================
Удаление openwrt-huawei-e3372.

БУДЕТ УДАЛЕНО:
  - панель luci-app-3ginfo-lite (+ русская локаль, если стояла)
  - репозиторий 4IceG и его ключ
  - интерфейс ${IFACE} и его правило в firewall-зоне wan
  - конфиг 3ginfo

БУДЕТ ОСТАВЛЕНО (для корректной работы роутера и других USB-устройств):
  - USB/сетевые драйверы: kmod-usb-core, kmod-usb2, kmod-usb3, kmod-usb-net,
    kmod-usb-net-cdc-ether, kmod-usb-net-rndis, usbutils, usb-modeswitch
  - wget-ssl, sms-tool
Эти пакеты трогать небезопасно: от них может зависеть работа роутера
и другой периферии, а места они почти не занимают.
============================================================
EOF
printf "Продолжить удаление? [y/N]: "
read ans
case "$ans" in
  y|Y|yes|YES) ;;
  *) echo "Отменено. Ничего не удалено."; exit 0 ;;
esac

# --- 1. Интерфейс модема и правило firewall --------------------------------
say "Удаление интерфейса ${IFACE} и правила firewall"
# убрать сеть из всех firewall-зон, где она прописана
for Z in $(uci show firewall 2>/dev/null | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.network=.*/\1/p" | sort -u); do
  if uci -q get "firewall.${Z}.network" | grep -qw "$IFACE"; then
    uci del_list "firewall.${Z}.network=${IFACE}" 2>/dev/null
    echo "Убрано из firewall ${Z}."
  fi
done
uci commit firewall 2>/dev/null

if uci -q get "network.${IFACE}" >/dev/null; then
  uci delete "network.${IFACE}"
  uci commit network
  echo "Интерфейс ${IFACE} удалён."
else
  echo "Интерфейс ${IFACE} не найден — пропускаю."
fi

/etc/init.d/network restart
/etc/init.d/firewall restart

# --- 2. Панель и локаль ----------------------------------------------------
say "Удаление панели luci-app-3ginfo-lite"
apk del luci-i18n-3ginfo-lite-ru 2>/dev/null && echo "Русская локаль удалена."
apk del luci-app-3ginfo-lite 2>/dev/null && echo "Панель удалена." || echo "Панель не установлена или уже удалена."

# конфиг панели (остаётся после удаления пакета)
if [ -f /etc/config/3ginfo ]; then
  rm -f /etc/config/3ginfo
  echo "Конфиг /etc/config/3ginfo удалён."
fi

# --- 3. Репозиторий 4IceG и ключ -------------------------------------------
say "Удаление репозитория 4IceG и ключа"
if [ -f "$FEEDS" ] && grep -q "$REPO_MATCH" "$FEEDS"; then
  grep -v "$REPO_MATCH" "$FEEDS" > "${FEEDS}.tmp" && mv "${FEEDS}.tmp" "$FEEDS"
  echo "Строка репозитория убрана из $FEEDS."
else
  echo "Строка репозитория в $FEEDS не найдена — пропускаю."
fi
if [ -f "$KEY_DST" ]; then
  rm -f "$KEY_DST"
  echo "Ключ $KEY_DST удалён."
fi
apk update 2>/dev/null

# --- Готово ----------------------------------------------------------------
cat <<EOF

============================================================
Удаление завершено.

Оставлены (намеренно, для корректной работы роутера):
  kmod-usb-core, kmod-usb2, kmod-usb3, kmod-usb-net,
  kmod-usb-net-cdc-ether, kmod-usb-net-rndis, usbutils, usb-modeswitch,
  wget-ssl, sms-tool.

Если хочешь убрать и их — делай это вручную и осознанно, по одному,
проверяя, что они не нужны другим USB-устройствам. Пример:
  apk del wget-ssl sms-tool
(драйверы kmod-usb-* лучше не трогать вовсе).
============================================================
EOF

# --- Перезагрузка (по желанию, с подтверждением) ---------------------------
echo ""
printf "Перезагрузить роутер сейчас, чтобы завершить очистку? Связь по ssh оборвётся. [y/N]: "
read rb
case "$rb" in
  y|Y|yes|YES)
    echo "Перезагрузка..."
    reboot
    ;;
  *)
    echo "Перезагрузка пропущена. При желании выполни вручную: reboot"
    ;;
esac
