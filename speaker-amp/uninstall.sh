#!/bin/bash
# Undo install.sh: stock rt1320 driver, no amp DSP firmware, UCM profile restored.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
PKG=n1x-rt1320-sdw VER=7.3-surface1
UCM=/usr/share/alsa/ucm2/conf.d/mt8901-soundwir/HiFi-surface-laptop-ultra.conf
dkms status "$PKG/$VER" | grep -q . && dkms remove "$PKG/$VER" --all
rm -rf "/usr/src/$PKG-$VER"
rm -f /usr/lib/firmware/updates/realtek/rt1320/rt1320_*Surface_Laptop_Ultra*.dat
rm -f /usr/local/lib/surface-ultra-misc/speaker-amp-gain
[ -f "$UCM.orig-speaker-amp" ] && mv "$UCM.orig-speaker-amp" "$UCM"
"$here/reload.sh"
