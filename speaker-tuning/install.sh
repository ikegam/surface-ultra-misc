#!/usr/bin/env bash
# Apply the Surface Laptop Ultra's Windows (Dolby) speaker tuning as a PipeWire filter-chain.
#
#   ./install.sh                    find the tuning in a mounted Windows partition
#   ./install.sh /mnt/win/Windows   ... in this Windows directory
#   ./install.sh tuning.xml         ... use this tuning file
#   ./install.sh SRC --variant warm extra arguments go to dolby_to_pipewire.py
set -euo pipefail
cd "$(dirname "$0")"
. ./common.sh

[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" = "Microsoft Surface Laptop Ultra" ] ||
    die "this is for the Microsoft Surface Laptop Ultra"

find_xml() {
    local win=$1
    find "$win/System32/DriverStore/FileRepository" -maxdepth 2 -path '*dax3_ext_rtk_nv.inf_*' \
        -name "$TUNING_XML" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

src=
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then src=$1; shift; fi

xml=
mounted=()
cleanup() { local d; for d in "${mounted[@]}"; do udisksctl unmount -b "$d" >/dev/null 2>&1; done; }
trap cleanup EXIT
if [ -n "$src" ] && [ -f "$src" ]; then
    xml=$src
elif [ -n "$src" ]; then
    xml=$(find_xml "$src")
    [ -n "$xml" ] || die "no $TUNING_XML under $src"
else
    while read -r mnt; do
        [ -d "$mnt/Windows" ] || continue
        xml=$(find_xml "$mnt/Windows")
        [ -n "$xml" ] && break
    done < <(findmnt -rn -t ntfs,ntfs3,fuseblk -o TARGET)
    # Not mounted: use the copy from an earlier run, else mount read-only for a moment.
    if [ -z "$xml" ] && [ -f "$CACHE/oem/$TUNING_XML" ]; then
        xml=$CACHE/oem/$TUNING_XML
    fi
    if [ -z "$xml" ] && command -v udisksctl >/dev/null; then
        for dev in $(lsblk -nrpo NAME,FSTYPE,MOUNTPOINT | awk '$2 == "ntfs" && $3 == "" {print $1}'); do
            mnt=$(udisksctl mount -b "$dev" -o ro 2>/dev/null | sed -n 's/^Mounted .* at //p') || continue
            [ -n "$mnt" ] || continue
            mounted+=("$dev")
            [ -d "$mnt/Windows" ] && xml=$(find_xml "$mnt/Windows")
            [ -n "$xml" ] && break
        done
    fi
    [ -n "$xml" ] || die "no Windows partition with the tuning found; pass the tuning file"
fi
echo "Tuning: $xml"

# A private copy, so the Windows partition can be unmounted afterwards.
mkdir -p "$CACHE/oem"
[ "$xml" = "$CACHE/oem/$TUNING_XML" ] || install -m 644 "$xml" "$CACHE/oem/$TUNING_XML"

missing=
for p in lsp-plugins.lv2 calf.lv2; do
    [ -d "/usr/lib/lv2/$p" ] || missing="$missing $p"
done
[ -z "$missing" ] || die "missing LV2 plugins:$missing; install them with: sudo pacman -S --needed lsp-plugins-lv2 calf"

fetch_converter
# Without the volume leveler: it pulls everything down to -26 LUFS and the speakers end up quiet.
run_converter "$CACHE/oem/$TUNING_XML" --no-activate --force --disable autogain "$@"
# The converted chain boosts +4 dB (volmax) into a limiter whose automatic level regulation
# (ALR) then pulls everything, vocals included, down as a mix gets denser. Drop the boost
# (speaker-amp's amp gain of 85 makes up for it), keep the bass enhancer a little gentler
# (Windows has it off, but it gives this chassis its body), and let ALR move slowly.
# Turning ALR off makes the limiter distort when it does act.
for conf in "${XDG_CONFIG_HOME:-$HOME/.config}"/pipewire/pipewire.conf.d/Dolby_*.conf; do
    [ -f "$conf" ] || continue
    sed -i -e 's/^\( *g_in = \)1\.584893192$/\11/' \
           -e 's/^\( *amount = \)3\.981071706$/\13/' \
           -e 's/^\( *alr_at = \)10$/\150/' -e 's/^\( *alr_rt = \)200$/\11000/' "$conf"
done
restart_audio
sleep 2
# Keep the speaker itself as the default output; selecting the filter's sink too stacks two volumes.
spk=$(wpctl status | sed -n 's/^ *│ *\*\{0,1\} *\([0-9]*\)\. Built-in Audio Speakers.*/\1/p' | head -1)
[ -n "$spk" ] && wpctl set-default "$spk"
sleep 2
run_converter --doctor || true
