#!/bin/bash
# Remove n1x-osi-idle. The firmware cannot go back from OSI to PC mode, so until the next boot
# the CPUs only use WFI (a bit more power); after a reboot the stock ACPI idle driver is back.
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rm -f /etc/modprobe.d/n1x-osi-idle.conf /etc/modules-load.d/n1x-osi-idle.conf
rmmod n1x_osi_idle 2>/dev/null
dkms remove n1x-osi-idle/1.0 --all
rm -rf /usr/src/n1x-osi-idle-1.0
echo "removed; reboot to get the ACPI idle driver back"
