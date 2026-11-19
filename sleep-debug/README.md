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
