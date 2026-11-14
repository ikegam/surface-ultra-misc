#!/usr/bin/env bash
# Keep the built-in speakers open while idle so playback starts at once.
#   ./no-suspend.sh on | off
# Waking the SoundWire link and both RT1320 amps (and their DSP) after PipeWire closed the
# idle speakers took ~2 s. Costs some idle power. After a system resume the speakers stay
# closed until the first playback, which keeps that one start slow but never overlaps the
# amp DSP reload that runs on resume.
set -euo pipefail
cd "$(dirname "$0")"
. ./common.sh
dst=${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d
case "${1:-}" in
on)  install -D -m 644 wireplumber/51-speaker-no-suspend.conf "$dst/51-speaker-no-suspend.conf" ;;
off) rm -f "$dst/51-speaker-no-suspend.conf" ;;
*)   die "usage: $0 on|off" ;;
esac
systemctl --user restart wireplumber
# portals, as after a PipeWire restart, so screen sharing keeps working
for unit in xdg-desktop-portal-hyprland xdg-desktop-portal; do
    systemctl --user -q is-active "$unit" && systemctl --user restart "$unit"
done
echo "speaker idle suspend: $1"
