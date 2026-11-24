#!/bin/bash
# Install n1x-osi-idle with DKMS and load it at every boot. Switched off unless --enable is given
# (an existing /etc/modprobe.d/n1x-osi-idle.conf is kept).
#   sudo ./install.sh            # module installed, OSI off (enable=0)
#   sudo ./install.sh --enable   # OSI on now and at every boot; no reboot needed
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
PKG=n1x-osi-idle VER=1.0 SRC=/usr/src/n1x-osi-idle-1.0
dkms status "$PKG/$VER" | grep -q . && dkms remove "$PKG/$VER" --all
rm -rf "$SRC"; install -d "$SRC"
install -m644 "$here"/{Makefile,Kbuild,dkms.conf,n1x_osi_idle.c} "$SRC/"
dkms install "$PKG/$VER"
CONF=/etc/modprobe.d/n1x-osi-idle.conf
if [ "${1:-}" = --enable ]; then
	echo "options n1x_osi_idle enable=1" > "$CONF"
elif [ ! -e "$CONF" ]; then
	echo "options n1x_osi_idle enable=0" > "$CONF"
fi
echo "n1x_osi_idle" > /etc/modules-load.d/n1x-osi-idle.conf
if ! grep -q 'enable=1' "$CONF"; then
	echo "OK: installed, OSI off ($CONF). Switch it on with: sudo ./install.sh --enable"
	exit 0
fi
# An already loaded copy leaves the firmware in OSI mode and the CPUs in WFI when removed;
# the new one takes over from there.
rmmod n1x_osi_idle 2>/dev/null || true
modprobe n1x_osi_idle
sleep 0.5
journalctl -k -b --no-pager | grep n1x_osi_idle | tail -3
[ "$(cat /sys/devices/system/cpu/cpuidle/current_driver)" = n1x_osi_idle ] &&
	echo "OK: OSI idle active" || { echo "!! not active; see journalctl -k"; exit 1; }
