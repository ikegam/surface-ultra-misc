#!/bin/bash
# Rebuild the sound card so the rt1320 module modprobe picks now is the one in use; the amps then
# load their DSP FW and tuning. Stops the calling user's PipeWire while the card is down.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U=${SUDO_USER:-}; drv=/sys/bus/platform/drivers/mtk_sdw_mc
usr() { [ -n "$U" ] && runuser -u "$U" -- env XDG_RUNTIME_DIR=/run/user/$(id -u "$U") systemctl --user "$@"; }
usr stop pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber
[ -e $drv/mtk_sdw_mc ] && echo mtk_sdw_mc > $drv/unbind
sleep 1
rmmod snd_soc_rt1320_sdw 2>/dev/null
modprobe snd_soc_rt1320_sdw
sleep 2
echo mtk_sdw_mc > $drv/bind
sleep 6
usr start pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse
# PipeWire restarts break screen sharing until the portals restart too.
for unit in xdg-desktop-portal-hyprland xdg-desktop-portal; do usr -q is-active $unit && usr restart $unit; done
echo "rt1320 in use: $(modinfo -F filename snd_soc_rt1320_sdw)"
grep -q mt8901 /proc/asound/cards || { echo "!! sound card missing; see journalctl -k"; exit 1; }
echo "OK: sound card is back"
"$(dirname "$0")/status.sh"
