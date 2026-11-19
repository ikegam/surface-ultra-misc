#!/bin/bash
# Install n1x-osi-idle with DKMS, load it at every boot, and load it now. No reboot needed.
#   sudo ./install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
PKG=n1x-osi-idle VER=1.0 SRC=/usr/src/n1x-osi-idle-1.0
dkms status "$PKG/$VER" | grep -q . && dkms remove "$PKG/$VER" --all
rm -rf "$SRC"; install -d "$SRC"
install -m644 "$here"/{Makefile,Kbuild,dkms.conf,n1x_osi_idle.c} "$SRC/"
dkms install "$PKG/$VER"
echo "options n1x_osi_idle enable=1" > /etc/modprobe.d/n1x-osi-idle.conf
echo "n1x_osi_idle" > /etc/modules-load.d/n1x-osi-idle.conf
# An already loaded copy leaves the firmware in OSI mode and the CPUs in WFI when removed;
# the new one takes over from there.
rmmod n1x_osi_idle 2>/dev/null || true
modprobe n1x_osi_idle
sleep 0.5
journalctl -k -b --no-pager | grep n1x_osi_idle | tail -3
[ "$(cat /sys/devices/system/cpu/cpuidle/current_driver)" = n1x_osi_idle ] &&
	echo "OK: OSI idle active" || { echo "!! not active; see journalctl -k"; exit 1; }
