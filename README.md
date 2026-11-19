# surface-ultra-misc

(日本語: [README_jp.md](README_jp.md))

Small pieces for running Linux on the Microsoft Surface Laptop Ultra (NVIDIA N1X SoC, arm64).
The camera lives in its own repository, [surface-ultra-camera](https://github.com/ikegam/surface-ultra-camera).

Unofficial; not affiliated with Microsoft, NVIDIA or MediaTek. Tested on Omarchy (linux-omarchy 7.3).

## Credits

This builds on teo-casares' work bringing Omarchy up on this machine:
[the Gist](https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8) (kernel patches, DKMS modules,
services) and [omacom/omarchy discussion #15885](https://github.com/omacom/omarchy/discussions/15885).
Start there; the pieces below assume that setup.

| Directory | What | Relation to teo-casares' work |
|---|---|---|
| [`als/`](als/) | ambient light sensor driver | independent |
| [`thermal/`](thermal/) | SoC power / skin temperature control (CPU and GPU limits, two profiles), Tj safety net | independent; complements their fan daemon, and reads the SSAM temperature sensors registered by `ssam-helper` |
| [`ssam-helper/`](ssam-helper/) | stock SSAM + helper modules | **their approach** (described in the discussion), implemented independently |
| [`backlight/`](backlight/) | automatic brightness | **a patch to their `n1x-edp-backlight`** (the script is not copied here) |
| [`power-button/`](power-button/) | power button driver | independent driver; the cause of the phantom "Volume Down" (floating `MSHW0040` pins) was found by them |
| [`suspend/`](suspend/) | no wakeups with the lid closed; keys dead right after resume | the lid hook is **their approach** (described in the discussion), implemented independently, with the touchpad and power button added; the NVIDIA part is independent |
| [`sapd-lps0/`](sapd-lps0/) | sends the Surface-specific Modern Standby notifications around suspend (experimental) | independent |
| [`osi-idle/`](osi-idle/) | CPU idle and s2idle in PSCI OS-initiated mode, as Windows runs the SoC (experimental) | independent |
| [`sleep-debug/`](sleep-debug/) | suspend diagnostics: last PM phase in a UEFI variable, boot-time report, per-suspend log | independent |
| [`keyboard/`](keyboard/) | Caps Lock lag; repeated keys through a key remapper | independent |
| [`wifi-powersave/`](wifi-powersave/) | Wi-Fi power save on battery only | independent |
| [`audio-jack/`](audio-jack/) | headphone jack detection | independent (upstream Realtek driver) |
| [`speaker-amp/`](speaker-amp/) | speakers: run the amps' DSP firmware and tuning from Windows | independent; works with their audio setup (UCM profile, `n1x-sdw-settle`) |
| [`speaker-tuning/`](speaker-tuning/) | speakers: Windows Dolby tuning as a PipeWire filter (optional) | independent |
| [`gpu-power/`](gpu-power/) | notes and probes on NVIDIA power management (nvidia-powerd, RATED_TDP) | independent |

## Dropped

- `usb4/` (2026-11-12): linux-omarchy keeps a tunnel root port awake while a dock's PCIe tunnel runs through it
  (patch `1105`, already in 7.3-3), so the udev rule that kept all three ports on is no longer needed.
- The `soc_button_array` blacklist from `power-button/install.sh` (2026-11-12): the kernel skips `MSHW0040` itself.

If you installed them: `sudo rm -f /etc/udev/rules.d/75-n1x-usb4-tunnel-pm.rules /etc/modprobe.d/n1x-no-soc-button-array.conf`

## License

GPL-2.0 (see LICENSE). The spi-hid sources in `als/` come from the spi-hid series carried by linux-omarchy
(Microsoft, Google, Semihalf and others); each modified file says what was changed.
The rt721-sdca sources in `audio-jack/` are Realtek's (GPL-2.0-only), copied unmodified from Linux v7.4-rc1.
