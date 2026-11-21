# sleep-debug: suspend diagnostics

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

For the s2idle resets (see `sapd-lps0`): the journal ends at `Performing sleep operation` and pstore stays empty,
because everything after that is in RAM and lost with the power. Not needed to run the machine.

- **`n1x_sleep_trace`** (DKMS module): hooks the `suspend_resume` tracepoint and writes the PM phase reached
  (suspend entry, `dpm_suspend*`, `machine_suspend`, DRIPS entry/exit, `dpm_resume_noirq`, `dpm_complete`) into
  the non-volatile UEFI variable `N1XSleepTrace-e592f01a-...` through the non-blocking runtime-service path, about
  ten small writes per suspend. After a reset the variable still holds the last phase.
- **`n1x-sleep-collect`** (`n1x-sleep-collect.service`, once per boot): reads that variable, checks how the
  previous boot ended (in suspend, shut down, or abruptly), the firmware's BERT record, the RTC time at boot
  (roughly when the power went) and saves two SPM SRAM pages. One block per boot goes to
  `/var/log/n1x-sleep-trace.log`, raw data to `/var/lib/n1x-sleep-trace/<boot-id>/`.
- **`n1x-sleep-log`** (systemd-sleep hook): before each suspend, writes the machine state (lid, battery, thermal,
  GPU and its apps, memory, camera, enabled wakeup sources, suspend stats, top processes) to
  `/var/log/n1x-sleep.log` and syncs it; after resume, the s2idle wake cycles, the IRQs that grew and the
  hardware sleep time. On battery it also logs the average power while asleep to `n1x-sleep-trace.log`.

**The tracer is installed switched off** (`/etc/modprobe.d/n1x-sleep-trace.conf`: `options n1x_sleep_trace enable=0`),
and is off on the author's machine since 2026-11-21. It writes a non-volatile UEFI variable about ten times per
suspend, several of them from `tick_freeze()` with interrupts off, right before DRIPS. On a machine that may lose
power in exactly that window this risks the firmware's variable store (boot entries, Secure Boot keys), and it
changes the timing of the phase under test. Turn it on only for a short, deliberate test:
`echo Y | sudo tee /sys/module/n1x_sleep_trace/parameters/enable`. The collector and the sleep log hook do not
write UEFI variables and stay on.

```
=== boot 8702c3ec collected 2026-11-19 23:13:37
previous boot ended abruptly (not in suspend)
trace var: suspend #1 started 2026-11-19 14:13:12, last phase dpm_complete:done [completed] (13 writes, DRIPS in/out 2/2, mono 1066.3s)
BERT: none
```

```
cd sleep-debug
sudo ./install.sh      # DKMS, loads at once; the collector runs from the next boot
sudo ./uninstall.sh    # also deletes the UEFI variable
```

`sudo ./install.sh --panic` also turns a hung task or CPU lockup into a panic, so the kernel log tail lands in
efi-pstore and the machine reboots 10 s later (`systemd-pstore` copies it to `/var/lib/systemd/pstore`), and turns
on `pm_debug_messages` / `pm_print_times`. `uninstall.sh` undoes it.

`pm-test-loop.sh [freezer|devices|platform] [count]` (root) runs the suspend path up to that `pm_test` level and
straight back, 30 times by default, logging each cycle to `/var/log/n1x-pmtest.log` with an fsync first; after a
power-off the last line names the cycle that died. Save your work first.
