#!/bin/bash
# Install the suspend diagnostics: the n1x_sleep_trace module (DKMS), the boot-time collector
# and the system-sleep log hook. No reboot needed.
#   sudo ./install.sh            the three tools
#   sudo ./install.sh --panic    also: turn a hung task / CPU lockup into a panic (kernel log to
#                                efi-pstore, reboot after 10 s) and PM debug messages on
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
PKG=n1x-sleep-trace VER=1.0 SRC=/usr/src/n1x-sleep-trace-1.0
dkms status "$PKG/$VER" | grep -q . && dkms remove "$PKG/$VER" --all
rm -rf "$SRC"; install -d "$SRC"
install -m644 "$here"/{Makefile,Kbuild,dkms.conf,n1x_sleep_trace.c} "$SRC/"
dkms install "$PKG/$VER"
echo n1x_sleep_trace > /etc/modules-load.d/n1x-sleep-trace.conf
install -m755 "$here/n1x-sleep-collect" /usr/local/bin/
install -m644 "$here/n1x-sleep-collect.service" /etc/systemd/system/
install -m755 "$here/n1x-sleep-log" /usr/lib/systemd/system-sleep/
systemctl daemon-reload
systemctl enable n1x-sleep-collect.service
rmmod n1x_sleep_trace 2>/dev/null || true
modprobe n1x_sleep_trace
if [ "${1:-}" = --panic ]; then
	install -m644 "$here/90-n1x-suspend-debug.conf" /etc/sysctl.d/
	install -m644 "$here/n1x-suspend-debug.tmpfiles.conf" /etc/tmpfiles.d/n1x-suspend-debug.conf
	modprobe efi_pstore
	systemctl enable systemd-pstore.service
	sysctl -q -p /etc/sysctl.d/90-n1x-suspend-debug.conf
	systemd-tmpfiles --create /etc/tmpfiles.d/n1x-suspend-debug.conf
	echo "panic on hang: on (pstore backend: $(cat /sys/module/pstore/parameters/backend))"
fi
echo "OK: tracer loaded; boot reports go to /var/log/n1x-sleep-trace.log, per-suspend state to /var/log/n1x-sleep.log"
