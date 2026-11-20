# sapd-lps0: Surface Modern Standby notifications

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

**Currently off on the author's machine (2026-11-20).** It did not stop the resets. Since it went in, long
lid-close sleeps started on battery no longer wake: the machine stays asleep (~0.4 W) and only a long press gets it back.
Sleeps started on AC are unaffected. It is now loaded with `enable=0` (`/etc/modprobe.d/n1x-sapd-lps0.conf`:
`options n1x_sapd_lps0 enable=0`) to test whether it causes this. Not proven either way yet.

**Experimental, under evaluation.** About 1 in 7-10 lid-close s2idle suspends never came back here: the journal ends
at `PM: suspend entry (s2idle)` and the SoC resets on its own, with no pstore record. The boot that follows then stalls
in NVIDIA GSP init (`GspStatusQueueInit ... NV_ERR_TIMEOUT`, no display). A second long press of the power button
gives a normal boot.

The firmware has two LPS0 devices (`_CID PNP0D80`) with the Microsoft Modern Standby `_DSM`
(`11e00d56-ce64-47ce-837b-1f898f9aa461`):

- `\_SB.PEPD` (`NVDA6210`): NVIDIA's platform extension. linux-omarchy's power_wrap (NVIDIA's lid-wake patch,
  NV-Kernels #656) already calls it (`LPS0 EC sleep notifications enabled` in the kernel log).
- `\_SB.SAPD` (`MSHW0299`): Surface-only. Nothing calls it on Linux. Function 7 (sleep entry) drives GPIO 136 low,
  and functions 3/4/8/9 drive it high. No other ACPI method touches that pin. On Windows it is low for the whole
  sleep; on Linux it stays high.

`n1x_sapd_lps0` binds to `MSHW0299` and sends the same sequence Windows does, in the device noirq phases: 3, 7, 5
on the way down and 6, 9, 8, 4 on the way up. Failures are logged and never block suspend. Whether this stops the
resets is not proven yet; it is being tested over a few dozen lid-close suspends. Sleep depth is unchanged (one
DRIPS per suspend).

```
cd sapd-lps0
sudo ./install.sh                                   # DKMS, loads at once, no reboot
cat /sys/bus/platform/devices/MSHW0299:00/stats     # functions=0x3f8 entries=N failures=0 enable=1
echo 0 | sudo tee /sys/module/n1x_sapd_lps0/parameters/enable   # stop sending, for an A/B test
sudo ./uninstall.sh
```

Each suspend logs `entry notifications sent (#N)` / `exit notifications sent` (module parameter `verbose`).
