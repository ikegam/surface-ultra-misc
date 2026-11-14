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
    [ -n "$xml" ] || die "mount the Windows partition (read-only is fine), or pass the tuning file"
fi
echo "Tuning: $xml"

# A private copy, so the Windows partition can be unmounted afterwards.
mkdir -p "$CACHE/oem"
install -m 644 "$xml" "$CACHE/oem/$TUNING_XML"

missing=
for p in lsp-plugins.lv2 calf.lv2; do
    [ -d "/usr/lib/lv2/$p" ] || missing="$missing $p"
done
[ -z "$missing" ] || die "missing LV2 plugins:$missing; install them with: sudo pacman -S --needed lsp-plugins-lv2 calf"

fetch_converter
# Without the volume leveler: it pulls everything down to -26 LUFS and the speakers end up quiet.
run_converter "$CACHE/oem/$TUNING_XML" --no-activate --force --disable autogain "$@"
restart_audio
sleep 2
# Keep the speaker itself as the default output; selecting the filter's sink too stacks two volumes.
spk=$(wpctl status | sed -n 's/^ *│ *\*\{0,1\} *\([0-9]*\)\. Built-in Audio Speakers.*/\1/p' | head -1)
[ -n "$spk" ] && wpctl set-default "$spk"
sleep 2
run_converter --doctor || true
