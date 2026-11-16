#!/bin/bash
# Power-cycle both RT1320 amps through their LDO enables, as ACPI CNT0._PS3/_PS0 do on Windows:
# GPIO 0x4A (74) = AMP1 LDO, GPIO 0x2F (47) = AMP2 LDO. Linux never calls those, so the amps stay
# powered (battery-backed) across reboots and power-off, and a DSP left broken (e.g. by a SoC crash
# in s2idle) stays broken. Stops the calling user's PipeWire while the card is down.
#   sudo ./amp-power-cycle.sh [module options]   e.g. auto_dspfw=0: amps come back without DSP FW (ROM path)
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U=${SUDO_USER:-}; drv=/sys/bus/platform/drivers/mtk_sdw_mc
usr() { [ -n "$U" ] && runuser -u "$U" -- env XDG_RUNTIME_DIR=/run/user/$(id -u "$U") systemctl --user "$@"; }

echo "before: $(gpioget -c gpiochip0 -a 47 74)"
usr stop pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber
[ -e $drv/mtk_sdw_mc ] && echo mtk_sdw_mc > $drv/unbind
sleep 1
rmmod snd_soc_rt1320_sdw 2>/dev/null

timeout 3 gpioset -c gpiochip0 47=0 74=0     # LDOs off for 3 s
echo "off:    $(gpioget -c gpiochip0 -a 47 74)"
timeout 1 gpioset -c gpiochip0 47=1 74=1     # back on
echo "on:     $(gpioget -c gpiochip0 -a 47 74)"
sleep 2

modprobe snd_soc_rt1320_sdw "$@"
sleep 2
echo mtk_sdw_mc > $drv/bind
sleep 3
usr start pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse
for unit in xdg-desktop-portal-hyprland xdg-desktop-portal; do usr -q is-active $unit && usr restart $unit; done
grep -q mt8901 /proc/asound/cards && echo "OK: sound card is back" || echo "!! sound card missing; see journalctl -k"
echo "The amps load their DSP FW about 10 s after the card is up; check with status.sh."
