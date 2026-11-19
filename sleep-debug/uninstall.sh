#!/bin/bash
# Remove the suspend diagnostics (logs in /var/log and /var/lib/n1x-sleep-trace are kept).
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rmmod n1x_sleep_trace 2>/dev/null
dkms remove n1x-sleep-trace/1.0 --all
rm -rf /usr/src/n1x-sleep-trace-1.0 /etc/modules-load.d/n1x-sleep-trace.conf
systemctl disable n1x-sleep-collect.service 2>/dev/null
rm -f /etc/systemd/system/n1x-sleep-collect.service /usr/local/bin/n1x-sleep-collect \
      /usr/lib/systemd/system-sleep/n1x-sleep-log
v=/sys/firmware/efi/efivars/N1XSleepTrace-e592f01a-04b3-4563-8c48-1035716f772f
[ -e "$v" ] && chattr -i "$v" && rm -f "$v"
if [ -e /etc/sysctl.d/90-n1x-suspend-debug.conf ]; then
	rm -f /etc/sysctl.d/90-n1x-suspend-debug.conf /etc/tmpfiles.d/n1x-suspend-debug.conf
	sysctl -q kernel.softlockup_panic=0 kernel.hardlockup_panic=0 kernel.hung_task_panic=0 kernel.panic=0
	echo 0 > /sys/power/pm_debug_messages
	echo 0 > /sys/power/pm_print_times
fi
systemctl daemon-reload
