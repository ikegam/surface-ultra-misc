#!/bin/bash
# Remove n1x-power-button.
#   sudo ./uninstall.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rmmod n1x_power_button 2>/dev/null
dkms remove n1x-power-button/1.0 --all
rm -rf /usr/src/n1x-power-button-1.0
