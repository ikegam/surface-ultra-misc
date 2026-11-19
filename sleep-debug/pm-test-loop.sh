#!/bin/bash
# Repeat the suspend path up to a pm_test level and come straight back, to find the stage at
# which the Surface Laptop Ultra powers off during s2idle entry.
#   sudo ./pm-test-loop.sh [level] [count]     level: freezer | devices (default) | platform
# Each cycle suspends everything up to <level>, waits 5 s, and resumes (no wake source needed).
# Progress is written and fsync'ed to /var/log/n1x-pmtest.log before every cycle, so after a
# power-off the last line shows which cycle died. Save your work first; lid stays open.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
level=${1:-devices} count=${2:-30}
log=/var/log/n1x-pmtest.log
grep -qw "$level" /sys/power/pm_test || { echo "unknown level $level"; exit 1; }
[ "$(cat /sys/power/mem_sleep | grep -o '\[[a-z0-9]*\]')" = "[s2idle]" ] || { echo "mem_sleep is not s2idle"; exit 1; }
echo 1 > /sys/power/pm_debug_messages
echo 1 > /sys/power/pm_print_times
trap 'echo none > /sys/power/pm_test' EXIT
echo "$level" > /sys/power/pm_test
echo "=== $(date '+%F %T') level=$level count=$count" >> "$log"; sync "$log"
for i in $(seq 1 "$count"); do
	echo "$(date '+%T') cycle $i/$count start" >> "$log"; sync "$log"
	if ! echo mem > /sys/power/state; then
		echo "$(date '+%T') cycle $i: write failed ($?)" >> "$log"; sync "$log"
		echo "cycle $i failed; see journalctl -k"; exit 1
	fi
	echo "$(date '+%T') cycle $i ok" >> "$log"; sync "$log"
	echo "cycle $i/$count ok"
	sleep 3
done
echo "=== $(date '+%T') done: $count cycles ok" >> "$log"; sync "$log"
echo "done: $count cycles of '$level' ok"
