# sapd-lps0: Surface Modern Standby notifications

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

**Currently off on the author's machine (2026-11-20).** It did not stop the resets. Since it went in, long
lid-close sleeps started on battery no longer wake: the machine stays asleep (~0.4 W) and only a long press gets it back.
Sleeps started on AC are unaffected. It is now loaded with `enable=0` (`/etc/modprobe.d/n1x-sapd-lps0.conf`:
`options n1x_sapd_lps0 enable=0`) to test whether it causes this.

Result (2026-11-22): with it off, 5 of 5 lid-close sleeps started on battery woke by the lid alone (64, 176, 284,
332 and 339 min, the last one overnight; about 0.7 W asleep). With it on, the last 4 of 4 did not. It once woke
after 243 min with the module on, so the mechanism is not understood, but the module stays off here. Do not install
this module unless you want to repeat the experiment.

Correction (2026-11-23): those 5 sleeps also ran with the `suspend/surface-ultra-lid-wakeup` hook switched off
(`chmod -x`), so the result does not separate the two. The first lid-close suspend after the hook was switched back
on (2026-11-22 12:14, started on AC, this module still off) never came back and the battery was empty 17 h later,
which is more than s2idle draws.

Second correction (2026-11-23): with the hook off again and this module still off, a lid-close suspend on battery
(05:53) did not come back either. So neither this module nor the hook explains the failures; the 6 good sleeps in
a row fit the old rate of about 1 failure in 7-10 by chance. The cause is open.

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
