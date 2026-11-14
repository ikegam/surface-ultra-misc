#!/bin/bash
# Run the Surface Laptop Ultra speaker amps with their Windows DSP firmware and tuning.
#   sudo ./install.sh [--no-reload] [WINDOWS_DIR]
# Without WINDOWS_DIR it uses a mounted Windows partition, or mounts it read-only for a moment.
# Builds the firmware from your Windows install, installs the patched rt1320 driver with DKMS,
# and rebuilds the sound card (audio stops for a few seconds; no reboot needed).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
[ "$(cat /sys/class/dmi/id/product_name)" = "Microsoft Surface Laptop Ultra" ] ||
    { echo "this is for the Microsoft Surface Laptop Ultra"; exit 1; }

reload=1
[ "${1:-}" = --no-reload ] && { reload=0; shift; }

FW=/usr/lib/firmware/updates/realtek/rt1320
UCM=/usr/share/alsa/ucm2/conf.d/mt8901-soundwir/HiFi-surface-laptop-ultra.conf
GAIN=/usr/local/lib/surface-ultra-misc/speaker-amp-gain
PKG=n1x-rt1320-sdw VER=7.3-surface1 SRC=/usr/src/$PKG-$VER

# 1. firmware, from the Realtek driver in your Windows install
tmp=$(mktemp -d); mnt=
cleanup() { [ -n "$mnt" ] && umount "$mnt" && rmdir "$mnt"; rm -rf "$tmp"; }
trap cleanup EXIT

# No Windows directory given and none mounted: mount the Windows partition read-only
# for the extraction, and unmount it again afterwards.
windows_mounted() {
    local m
    for m in $(findmnt -rn -t ntfs,ntfs3,fuseblk -o TARGET); do
        [ -d "$m/Windows/System32" ] && return 0
    done
    return 1
}
win=("$@")
if [ ${#win[@]} = 0 ] && ! windows_mounted; then
    for dev in $(lsblk -nrpo NAME,FSTYPE | awk '$2 == "ntfs" {print $1}'); do
        m=$(mktemp -d)
        if mount -o ro "$dev" "$m" 2>/dev/null; then
            if [ -d "$m/Windows/System32" ]; then mnt=$m; win=("$m/Windows"); break; fi
            umount "$m"
        fi
        rmdir "$m"
    done
fi

if python3 -I "$here/extract.py" "${win[@]}" "$tmp"; then
    install -d "$FW"
    install -m644 "$tmp"/rt1320_*.dat "$FW/"
elif ls "$FW"/rt1320_*Surface_Laptop_Ultra*.dat >/dev/null 2>&1; then
    echo "Keeping the firmware already in $FW."
else
    exit 1
fi

# 2. driver
dkms status "$PKG/$VER" | grep -q . && dkms remove "$PKG/$VER" --all
rm -rf "$SRC"; install -d "$SRC"
install -m644 "$here"/module/{Makefile,Kbuild,dkms.conf,*.c,*.h,*.patch} "$SRC/"
dkms install "$PKG/$VER"

# 3. amp gain: let the UCM profile raise its -9 dB cap while the DSP FW runs
install -D -m755 "$here/speaker-amp-gain" "$GAIN"
if [ -f "$UCM" ] && ! grep -q speaker-amp-gain "$UCM"; then
    cp -a "$UCM" "$UCM.orig-speaker-amp"
    sed -i "/cset \"name='rt1320-2 FU21 Playback Volume'/a\\\\t\\texec \"-$GAIN\"" "$UCM"
    grep -q speaker-amp-gain "$UCM" || echo "!! could not add the gain hook to $UCM; the amps stay at -9 dB"
fi

if [ $reload = 1 ]; then
    "$here/reload.sh"
else
    echo "Installed; takes effect at the next boot (or run reload.sh)."
fi
