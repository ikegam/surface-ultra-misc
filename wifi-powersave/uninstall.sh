#!/bin/bash
# Remove it and turn power save off again (Omarchy's default).
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rm -f /usr/local/sbin/surface-wifi-powersave /etc/udev/rules.d/62-surface-wifi-powersave.rules \
      /etc/NetworkManager/dispatcher.d/90-surface-wifi-powersave
udevadm control --reload
for i in $(iw dev | awk '/Interface/{print $2}'); do iw dev "$i" set power_save off; done
