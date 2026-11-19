#!/bin/bash
# Wi-Fi power save on battery only. Applies at once; no reboot.
#   sudo ./install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
command -v iw >/dev/null || { echo "needs iw: sudo pacman -S iw"; exit 1; }
install -Dm755 "$here/surface-wifi-powersave" /usr/local/sbin/surface-wifi-powersave
install -m644 "$here/62-surface-wifi-powersave.rules" /etc/udev/rules.d/
install -Dm755 "$here/90-surface-wifi-powersave" /etc/NetworkManager/dispatcher.d/90-surface-wifi-powersave
udevadm control --reload
/usr/local/sbin/surface-wifi-powersave
for i in $(iw dev | awk '/Interface/{print $2}'); do echo "$i: $(iw dev "$i" get power_save)"; done
