# power-button

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

Makes the power button work. A short press sends `KEY_POWER`, which opens Omarchy's power menu.

The buttons are behind ACPI `MSHW0040` (`\_SB.MSBT`). On x86 Surfaces `soc_button_array` turns that into
gpio-keys devices. Upstream 7.3 builds `soc_button_array` for x86 only; linux-omarchy builds it for arm64 again but
skips `MSHW0040` on this machine (omacom/omarchy-pkgs#2166), so the power button has no driver. Its `_CRS`
has three GPIOs on `\_SB.GIO0`: pin 46 (power, the only one marked as a wake source) and pins 40/41. This laptop has
no volume rocker; as teo-casares found, 40/41 float and report "Volume Down" held forever. `n1x-power-button` binds
to `MSHW0040`, takes only pin 46 and leaves 40/41 alone, so `modprobe.blacklist=gpio_keys` can stay on the kernel
command line. The level at load time counts as released. A press during suspend wakes the machine but is not
reported, so the power menu does not open after resume.

```
cd power-button
sudo ./install.sh      # DKMS, loaded at once and at every boot; no reboot
sudo ./uninstall.sh
```

Waking from suspend with the button works (tested with the lid open). If the machine sleeps with the lid closed, also
turn off the button's wakeup (`/sys/bus/platform/devices/MSHW0040:00/power/wakeup`), as for the keyboard and touchpad;
otherwise a press in a bag wakes it. The hook in [`suspend/`](../suspend/) does this.
