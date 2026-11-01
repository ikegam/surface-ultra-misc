#!/bin/bash
# Install n1x-power-button with DKMS and load it. No reboot needed.
#   sudo ./install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
PKG=n1x-power-button VER=1.0 SRC=/usr/src/n1x-power-button-1.0
dkms status "$PKG/$VER" | grep -q . && dkms remove "$PKG/$VER" --all
rm -rf "$SRC"; install -d "$SRC"
install -m644 "$here"/{Makefile,Kbuild,dkms.conf,n1x_power_button.c} "$SRC/"
dkms install "$PKG/$VER"
rmmod n1x_power_button 2>/dev/null || true
modprobe n1x_power_button
sleep 0.5
journalctl -k -b --no-pager | grep -i "n1x-power-button\|MSHW0040" | tail -3
grep -q "Surface Laptop Ultra Power Button" /proc/bus/input/devices \
	&& echo "OK: input device registered; a short press should open the power menu" \
	|| { echo "!! no input device; see journalctl -k"; exit 1; }
