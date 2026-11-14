# shellcheck shell=bash
# Shared by install.sh and uninstall.sh.

# The converter runs from a pinned commit, fetched at install time (MIT, not vendored here).
CONVERTER_REPO=https://github.com/antoinecellerier/speaker-tuning-to-easyeffects
CONVERTER_REV=2180c7338d3d73ffce646c9fd449948a7c5a5fbc

CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/surface-ultra-misc/speaker-tuning
CONVERTER=$CACHE/speaker-tuning-to-easyeffects

# Dolby tuning for the RT1320 speaker amps, inside the Surface's Windows audio driver
# (dax3_ext_rtk_nv.inf). It is read from your own Windows install and never leaves this machine.
TUNING_XML=SOUNDWIRE_SDCAFUNCTION_10_MAN_025D_FUNC_1320_SUBSYS_308E10EC.xml

die() { echo "error: $*" >&2; exit 1; }

fetch_converter() {
    command -v git >/dev/null || die "git is required"
    if [ ! -d "$CONVERTER/.git" ]; then
        mkdir -p "$CACHE"
        git clone -q "$CONVERTER_REPO" "$CONVERTER"
    fi
    if ! git -C "$CONVERTER" cat-file -e "$CONVERTER_REV^{commit}" 2>/dev/null; then
        git -C "$CONVERTER" fetch -q origin
    fi
    git -C "$CONVERTER" -c advice.detachedHead=false checkout -q "$CONVERTER_REV"
}

run_converter() {
    command -v uv >/dev/null || die "uv is required (pacman -S uv)"
    (cd "$CONVERTER" && uv run -q --no-project --with numpy --with scipy \
        python dolby_to_pipewire.py "$@")
}

# Restarting PipeWire leaves screen sharing broken until the portals are restarted too.
restart_audio() {
    echo "Restarting PipeWire (sound cuts out for a moment)..."
    systemctl --user restart pipewire pipewire-pulse wireplumber
    local unit
    for unit in xdg-desktop-portal-hyprland xdg-desktop-portal; do
        if systemctl --user -q is-active "$unit"; then
            systemctl --user restart "$unit"
        fi
    done
}
